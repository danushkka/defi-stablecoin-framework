// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDSCEngine} from "../interfaces/IDSCEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IBasePeggedToken} from "../interfaces/IBasePeggedToken.sol";
import {OracleLib} from "../libraries/OracleLib.sol";

/**
 * @title AbstractDSCEngine
 * @notice Abstract base contract for any DSC engine implementation.
 *
 * Contains all generic protocol logic:
 * - Collateral deposits and redemptions
 * - DSC minting and burning
 * - Health factor enforcement
 * - Liquidation mechanism
 *
 * Subclasses must implement ONE function:
 * - _getReferenceValuePerUsd(): returns how many peg currency units equal 1 USD
 *
 * Example: CNY implementation returns ~6.75 (1 USD = 6.75 CNY)
 *          EUR implementation returns ~0.92 (1 USD = 0.92 EUR)
 */

abstract contract AbstractDSCEngine is IDSCEngine, ReentrancyGuard {
    ////////////////////////////////////
    ////////////// TYPES ///////////////
    ////////////////////////////////////

    using OracleLib for AggregatorV3Interface;

    ////////////////////////////////////
    ///////// STATE VARIABLES //////////
    ////////////////////////////////////

    uint256 internal constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 internal constant DECIMAL_PRECISION = 1e18;
    uint256 private constant LIQUIDATION_ADJUSTMENT = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountMinted) private s_dscMinted;

    address[] private s_collateralTokens;

    IBasePeggedToken private immutable i_stablecoin;

    ////////////////////////////////////
    //////////// MODIFIERS /////////////
    ////////////////////////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert IDSCEngine__MustBeMoreThanZero();
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) revert IDSCEngine__TokenNotAllowed();
        _;
    }

    ////////////////////////////////////
    //////////// CONSTRUCTOR ///////////
    ////////////////////////////////////

    constructor(
        address[] memory tokenCollateralAddresses,
        address[] memory priceFeedAddresses,
        address stablecoinAddress
    ) {
        if (tokenCollateralAddresses.length != priceFeedAddresses.length) {
            revert IDSCEngine__TokenAndPriceFeedLengthMismatch();
        }
        for (uint256 i = 0; i < tokenCollateralAddresses.length; i++) {
            s_priceFeeds[tokenCollateralAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenCollateralAddresses[i]);
        }
        i_stablecoin = IBasePeggedToken(stablecoinAddress);
    }

    ////////////////////////////////////
    //////// ABSTRACT FUNCTION /////////
    ////////////////////////////////////

    /**
     * @notice The ONE function subclasses must implement.
     * @return How many peg currency units equal 1 USD, scaled to 1e18.
     * @dev Example: CNY returns 6.756e18 (1 USD = 6.756 CNY)
     *               EUR returns 0.92e18  (1 USD = 0.92 EUR)
     */
    function _getReferenceValuePerUsd() internal view virtual returns (uint256);

    ////////////////////////////////////
    //////// PUBLIC & EXTERNAL /////////
    ////////////////////////////////////

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    )
        external
        isAllowedToken(tokenCollateralAddress)
        moreThanZero(amountCollateral)
        moreThanZero(amountDscToMint)
        nonReentrant
    {
        _depositCollateral(tokenCollateralAddress, amountCollateral);
        _mintDsc(amountDscToMint);
    }

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        isAllowedToken(tokenCollateralAddress)
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _depositCollateral(tokenCollateralAddress, amountCollateral);
    }

    function mintDsc(uint256 amountToMint) external moreThanZero(amountToMint) nonReentrant {
        _mintDsc(amountToMint);
    }

    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateralToRedeem,
        uint256 amountDscToBurn
    ) external moreThanZero(amountCollateralToRedeem) isAllowedToken(tokenCollateralAddress) nonReentrant {
        _burnDsc(msg.sender, msg.sender, amountDscToBurn);
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateralToRedeem);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateralToRedeem)
        external
        moreThanZero(amountCollateralToRedeem)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateralToRedeem);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc(uint256 amountToBurn) external moreThanZero(amountToBurn) nonReentrant {
        _burnDsc(msg.sender, msg.sender, amountToBurn);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function liquidate(address tokenCollateralAddress, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert IDSCEngine__HealthFactorIsNormal(startingHealthFactor);
        }

        uint256 tokenAmountToCover = getTokenAmountFromReferenceValue(tokenCollateralAddress, debtToCover);
        uint256 bonus = (tokenAmountToCover * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountToCover + bonus;

        _burnDsc(msg.sender, user, debtToCover);
        _redeemCollateral(user, msg.sender, tokenCollateralAddress, totalCollateralToRedeem);

        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor <= startingHealthFactor) {
            revert IDSCEngine__HealthFactorNotImproved(endingHealthFactor);
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ////////////////////////////////////
    //////// PRIVATE & INTERNAL ////////
    ////////////////////////////////////

    function _depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) private {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) revert IDSCEngine__TransferFailed();

        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
    }

    function _mintDsc(uint256 amountToMint) private {
        s_dscMinted[msg.sender] += amountToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_stablecoin.mint(msg.sender, amountToMint);
        if (!minted) revert IDSCEngine__MintingFailed();
    }

    function _burnDsc(address from, address user, uint256 amountToBurn) private {
        s_dscMinted[user] -= amountToBurn;

        bool success = i_stablecoin.transferFrom(from, address(this), amountToBurn);
        if (!success) revert IDSCEngine__TransferFailed();

        i_stablecoin.burn(amountToBurn);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amount) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amount;

        bool success = IERC20(tokenCollateralAddress).transfer(to, amount);
        if (!success) revert IDSCEngine__TransferFailed();

        emit CollateralRedeemed(from, to, tokenCollateralAddress, amount);
    }

    function _getAccountInformation(address user) private view returns (uint256, uint256) {
        return (s_dscMinted[user], getAccountCollateralValueInReferenceValue(user));
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInRef)
        private
        pure
        returns (uint256)
    {
        // NOTE: returns max uint when no debt exists — perfectly healthy position.
        // Partial liquidations must leave some debt remaining or this bypasses
        // the HealthFactorNotImproved check in liquidate().

        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjusted = (collateralValueInRef * LIQUIDATION_ADJUSTMENT) / LIQUIDATION_PRECISION;
        return (collateralAdjusted * DECIMAL_PRECISION) / totalDscMinted;
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValue) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValue);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert IDSCEngine__HealthFactorIsBroken(healthFactor);
        }
    }

    ////////////////////////////////////
    ///////////// GETTERS //////////////
    ////////////////////////////////////

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInReferenceValue)
    {
        return _getAccountInformation(user);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInReferenceValue)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInReferenceValue);
    }

    function getAccountCollateralValueInReferenceValue(address user)
        public
        view
        returns (uint256 totalCollateralValue)
    {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValue += getReferenceValueOfToken(token, amount);
        }
    }

    function getReferenceValueOfToken(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 usdPrice,,,) = priceFeed.stalePriceCheck();

        uint256 usdValue = (uint256(usdPrice) * ADDITIONAL_FEED_PRECISION * amount) / DECIMAL_PRECISION;
        uint256 refPerUsd = _getReferenceValuePerUsd();
        return (usdValue * refPerUsd) / DECIMAL_PRECISION;
    }

    function getTokenAmountFromReferenceValue(address token, uint256 referenceValueAmount)
        public
        view
        returns (uint256)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 usdPrice,,,) = priceFeed.stalePriceCheck();

        uint256 refPerUsd = _getReferenceValuePerUsd();
        uint256 usdAmount = (referenceValueAmount * DECIMAL_PRECISION) / refPerUsd;
        return (usdAmount * DECIMAL_PRECISION) / (uint256(usdPrice) * ADDITIONAL_FEED_PRECISION);
    }

    function getReferenceValuePerUsd() external view returns (uint256) {
        return _getReferenceValuePerUsd();
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getStablecoin() external view returns (address) {
        return address(i_stablecoin);
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getDecimalPrecision() external pure returns (uint256) {
        return DECIMAL_PRECISION;
    }

    function getLiquidationAdjustment() external pure returns (uint256) {
        return LIQUIDATION_ADJUSTMENT;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }
}
