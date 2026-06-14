// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IDSCEngine
 * @notice Universal interface for any DSC engine implementation.
 * Any stablecoin engine — regardless of peg currency — must implement
 * all functions defined here. This ensures all implementations are
 * interchangeable and composable.
 *
 * @dev Implementors must provide _getReferenceValuePerUsd() in their
 * concrete engine to define the peg currency conversion rate.
 */

interface IDSCEngine {
    ////////////////////////////////////
    ////////////// ERRORS //////////////
    ////////////////////////////////////

    error IDSCEngine__MustBeMoreThanZero();
    error IDSCEngine__TokenNotAllowed();
    error IDSCEngine__TransferFailed();
    error IDSCEngine__HealthFactorIsBroken(uint256 healthFactor);
    error IDSCEngine__HealthFactorIsNormal(uint256 healthFactor);
    error IDSCEngine__HealthFactorNotImproved(uint256 healthFactor);
    error IDSCEngine__MintingFailed();
    error IDSCEngine__TokenAndPriceFeedLengthMismatch();

    ////////////////////////////////////
    ////////////// EVENTS //////////////
    ////////////////////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    ////////////////////////////////////
    ////// CORE PROTOCOL FUNCTIONS /////
    ////////////////////////////////////

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external;

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) external;

    function mintDsc(uint256 amountToMint) external;

    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateralToRedeem,
        uint256 amountDscToBurn
    ) external;

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateralToRedeem) external;

    function burnDsc(uint256 amountToBurn) external;

    function liquidate(address tokenCollateralAddress, address user, uint256 debtToCover) external;

    ////////////////////////////////////
    ///////////// GETTERS //////////////
    ////////////////////////////////////

    ////////////////////////////////////
    //////// ACCOUNT INFORMATION ///////
    ////////////////////////////////////

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInReferenceValue);

    function getAccountCollateralValueInReferenceValue(address user) external view returns (uint256);

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256);

    function getHealthFactor(address user) external view returns (uint256);

    ////////////////////////////////////
    ///////// VALUE CONVERSION /////////
    ////////////////////////////////////

    function getReferenceValuePerUsd() external view returns (uint256);

    function getReferenceValueOfToken(address token, uint256 amount) external view returns (uint256);

    function getTokenAmountFromReferenceValue(address token, uint256 referenceValueAmount)
        external
        view
        returns (uint256);

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInReferenceValue)
        external
        pure
        returns (uint256);

    ////////////////////////////////////
    ///////////// PROTOCOL /////////////
    ////////////////////////////////////

    function getCollateralTokens() external view returns (address[] memory);

    function getStablecoin() external view returns (address);

    function getPriceFeed(address token) external view returns (address);
}
