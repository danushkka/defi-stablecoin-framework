// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {CnyStablecoin} from "../../src/implementations/CnyStablecoin.sol";
import {CnyEngine} from "../../src/implementations/CnyEngine.sol";
import {DeployCnyStablecoin} from "../../script/DeployCnyStablecoin.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {OracleLib} from "../../src/libraries/OracleLib.sol";
import {IDSCEngine} from "../../src/interfaces/IDSCEngine.sol";
import {MockMoreCollateralThanDsc} from "../mocks/MockMoreCollateralThanDsc.sol";
import {MockFailCollateral} from "../mocks/MockFailCollateral.sol";
import {MockFailMintDsc} from "../mocks/MockFailMintDsc.sol";
import {MockFailBurnDsc} from "../mocks/MockFailBurnDsc.sol";
import {MockFailRedeemCollateral} from "../mocks/MockFailRedeemCollateral.sol";

contract CnyEngineTest is Test {
    ////////////////////////////////////
    ///////// STATE VARIABLES //////////
    ////////////////////////////////////

    CnyStablecoin cnyToken;
    CnyEngine engine;
    DeployCnyStablecoin deployer;
    HelperConfig config;

    address cnyPriceFeed;
    address wethPriceFeed;
    address wbtcPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_BALANCE = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 1000 ether;
    uint256 public constant AMOUNT_TO_REDEEM = 5 ether;
    uint256 public constant AMOUNT_TO_COVER = 20 ether;

    address public user = makeAddr("user");
    address public liquidator = makeAddr("liquidator");

    ////////////////////////////////////
    ////////////// EVENTS //////////////
    ////////////////////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    ////////////////////////////////////
    //////////// MODIFIERS /////////////
    ////////////////////////////////////

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    modifier liquidated() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        int256 newEthPrice = 18e8;
        MockV3Aggregator(wethPriceFeed).updateAnswer(newEthPrice);

        ERC20Mock(weth).mint(liquidator, AMOUNT_TO_COVER);
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine), AMOUNT_TO_COVER);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_TO_COVER, AMOUNT_TO_MINT);
        cnyToken.approve(address(engine), AMOUNT_TO_MINT);
        engine.liquidate(weth, user, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    ////////////////////////////////////
    //////////// FUNCTIONS /////////////
    ////////////////////////////////////

    function setUp() public {
        deployer = new DeployCnyStablecoin();
        (cnyToken, engine, config) = deployer.run();
        (cnyPriceFeed, wethPriceFeed, wbtcPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(user, STARTING_BALANCE);
    }

    ////////////////////////////////////
    /////////// CONSTRUCTOR ////////////
    ////////////////////////////////////

    function testConstructorRevertsIfLengthMismatch() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethPriceFeed);
        tokenAddresses.push(wbtc);

        vm.expectRevert(IDSCEngine.IDSCEngine__TokenAndPriceFeedLengthMismatch.selector);
        new CnyEngine(tokenAddresses, priceFeedAddresses, cnyPriceFeed, address(cnyToken));
    }

    ////////////////////////////////////
    ///////////// GETTERS //////////////
    ////////////////////////////////////

    function testGetReferenceValuePerUsd() public view {
        // 1 USD = 1 / 0.148 CNY = 6.756... CNY
        uint256 expected = 6_756756756756756756;
        assertEq(engine.getReferenceValuePerUsd(), expected);
    }

    function testGetPriceFeed() public view {
        assertEq(engine.getPriceFeed(weth), wethPriceFeed);
        assertEq(engine.getPriceFeed(wbtc), wbtcPriceFeed);
    }

    function testGetReferenceValueOfToken() public view {
        // 10 ETH at $2000 = $20000
        // $20000 * 6.756 CNY/USD = ~135135 CNY
        uint256 cnyPerUsd = engine.getReferenceValuePerUsd();
        uint256 usdValue = 20_000e18;
        uint256 expectedCnyValue = (usdValue * cnyPerUsd) / 1e18;
        uint256 actualCnyValue = engine.getReferenceValueOfToken(weth, 10 ether);

        assertEq(actualCnyValue, expectedCnyValue);
        assert(actualCnyValue > 135_135e18);
        assert(actualCnyValue < 135_145e18);
    }

    function testGetTokenAmountFromReferenceValue() public view {
        // 135_135.13... CNY should equal 10 ETH
        uint256 cnyAmount = 135_135.13513513513512e18;
        uint256 expectedEthAmount = 10 ether;
        assertEq(engine.getTokenAmountFromReferenceValue(weth, cnyAmount), expectedEthAmount);
    }

    function testGetAccountCollateralValueInReferenceValue() public depositedCollateral {
        uint256 expected = engine.getReferenceValueOfToken(weth, AMOUNT_COLLATERAL);
        assertEq(engine.getAccountCollateralValueInReferenceValue(user), expected);
    }

    function testGetAccountInformation() public depositedCollateralAndMintedDsc {
        (uint256 dscMinted, uint256 collateralValue) = engine.getAccountInformation(user);
        assertEq(dscMinted, AMOUNT_TO_MINT);
        assertEq(collateralValue, engine.getReferenceValueOfToken(weth, AMOUNT_COLLATERAL));
    }

    function testHealthFactorIsMaxWithNoDebt() public depositedCollateral {
        assertEq(engine.getHealthFactor(user), type(uint256).max);
    }

    function testGetCollateralTokens() public view {
        address[] memory tokens = engine.getCollateralTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], weth);
        assertEq(tokens[1], wbtc);
    }

    function testGetStablecoin() public view {
        assertEq(engine.getStablecoin(), address(cnyToken));
    }

    function testGetLiquidationBonus() public view {
        assertEq(engine.getLiquidationBonus(), 10);
    }

    function testGetLiquidationPrecision() public view {
        assertEq(engine.getLiquidationPrecision(), 100);
    }

    function testGetAdditionalFeedPrecision() public view {
        assertEq(engine.getAdditionalFeedPrecision(), 1e10);
    }

    function testGetDecimalPrecision() public view {
        assertEq(engine.getDecimalPrecision(), 1e18);
    }

    function testGetLiquidationAdjustment() public view {
        assertEq(engine.getLiquidationAdjustment(), 50);
    }

    function testGetMinHealthFactor() public view {
        assertEq(engine.getMinHealthFactor(), 1e18);
    }

    ////////////////////////////////////
    //////// DEPOSIT_COLLATERAL ////////
    ////////////////////////////////////

    function testDepositRevertsIfZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(IDSCEngine.IDSCEngine__MustBeMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testDepositRevertsIfNotAllowedToken() public {
        ERC20Mock notAllowed = new ERC20Mock();
        vm.startPrank(user);
        notAllowed.approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(IDSCEngine.IDSCEngine__TokenNotAllowed.selector);
        engine.depositCollateral(address(notAllowed), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateral() public depositedCollateral {
        uint256 balance = engine.getCollateralBalanceOfUser(user, weth);
        assertEq(balance, AMOUNT_COLLATERAL);
    }

    function testDepositEmitsEvent() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectEmit(true, true, true, true);
        emit CollateralDeposited(user, weth, AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ////////////////////////////////////
    ///////////// MINT_DSC /////////////
    ////////////////////////////////////

    function testMintRevertsIfZeroAmount() public {
        vm.startPrank(user);
        vm.expectRevert(IDSCEngine.IDSCEngine__MustBeMoreThanZero.selector);
        engine.mintDsc(0);
        vm.stopPrank();
    }

    function testMintRevertsIfHealthFactorBroken() public {
        uint256 collateralValue = engine.getAccountCollateralValueInReferenceValue(user);
        uint256 expectedHF = engine.calculateHealthFactor(AMOUNT_TO_MINT, collateralValue);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IDSCEngine.IDSCEngine__HealthFactorIsBroken.selector, expectedHF));
        engine.mintDsc(AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testCanMint() public depositedCollateral {
        vm.startPrank(user);
        engine.mintDsc(AMOUNT_TO_MINT);
        vm.stopPrank();
        assertEq(cnyToken.balanceOf(user), AMOUNT_TO_MINT);
    }

    ////////////////////////////////////
    //////// REDEEM_COLLATERAL /////////
    ////////////////////////////////////

    function testRedeemRevertsIfZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        vm.expectRevert(IDSCEngine.IDSCEngine__MustBeMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        engine.redeemCollateral(weth, AMOUNT_TO_REDEEM);
        vm.stopPrank();

        uint256 expected = engine.getReferenceValueOfToken(weth, AMOUNT_COLLATERAL - AMOUNT_TO_REDEEM);
        assertEq(engine.getAccountCollateralValueInReferenceValue(user), expected);
    }

    function testRedeemRevertsIfHealthFactorBroken() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IDSCEngine.IDSCEngine__HealthFactorIsBroken.selector, 0));
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ////////////////////////////////////
    ///// REDEEM_COLLATERAL_FOR_DSC ////
    ////////////////////////////////////

    function testCanRedeemCollateralForDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        cnyToken.approve(address(engine), AMOUNT_TO_MINT);
        engine.redeemCollateralForDsc(weth, AMOUNT_TO_REDEEM, AMOUNT_TO_MINT);
        vm.stopPrank();

        uint256 expectedCollateralValueOfUser =
            engine.getReferenceValueOfToken(weth, AMOUNT_COLLATERAL - AMOUNT_TO_REDEEM);

        assertEq(cnyToken.balanceOf(user), 0);
        assertEq(engine.getAccountCollateralValueInReferenceValue(user), expectedCollateralValueOfUser);
    }

    function testRedeemCollateralForDscRevertsIfHealthFactorBroken() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        uint256 smallAmountToBurn = 1e18;

        cnyToken.approve(address(engine), smallAmountToBurn);
        vm.expectRevert(abi.encodeWithSelector(IDSCEngine.IDSCEngine__HealthFactorIsBroken.selector, 0));
        engine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, smallAmountToBurn);
        vm.stopPrank();
    }

    function testRedeemCollateralForDscRevertsIfZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        vm.expectRevert(IDSCEngine.IDSCEngine__MustBeMoreThanZero.selector);
        engine.redeemCollateralForDsc(weth, 0, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testRedeemCollateralForDscRevertsIfNotAllowedToken() public depositedCollateralAndMintedDsc {
        ERC20Mock notAllowed = new ERC20Mock();

        vm.startPrank(user);
        vm.expectRevert(IDSCEngine.IDSCEngine__TokenNotAllowed.selector);
        engine.redeemCollateralForDsc(address(notAllowed), AMOUNT_TO_REDEEM, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    ////////////////////////////////////
    ///////////// BURN_DSC /////////////
    ////////////////////////////////////

    function testBurnRevertsIfZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        vm.expectRevert(IDSCEngine.IDSCEngine__MustBeMoreThanZero.selector);
        engine.burnDsc(0);
        vm.stopPrank();
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        cnyToken.approve(address(engine), AMOUNT_TO_MINT);
        engine.burnDsc(AMOUNT_TO_MINT);
        vm.stopPrank();
        assertEq(cnyToken.balanceOf(user), 0);
    }

    ////////////////////////////////////
    //////////// LIQUIDATE /////////////
    ////////////////////////////////////

    function testLiquidateRevertsIfHealthFactorNormal() public depositedCollateralAndMintedDsc {
        uint256 hf = engine.getHealthFactor(user);
        vm.startPrank(liquidator);
        vm.expectRevert(abi.encodeWithSelector(IDSCEngine.IDSCEngine__HealthFactorIsNormal.selector, hf));
        engine.liquidate(weth, user, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testLiquidateTheExactAmount() public liquidated {
        uint256 tokenAmountToCover = engine.getTokenAmountFromReferenceValue(weth, AMOUNT_TO_MINT);
        uint256 bonus = (tokenAmountToCover * engine.getLiquidationBonus()) / engine.getLiquidationPrecision();
        uint256 expectedTokensLiquidated = tokenAmountToCover + bonus;
        uint256 expectedCnyLiquidated = engine.getReferenceValueOfToken(weth, expectedTokensLiquidated);

        uint256 remaining = engine.getCollateralBalanceOfUser(user, weth);
        uint256 actualTokensLiquidated = AMOUNT_COLLATERAL - remaining;
        uint256 actualCnyLiquidated = engine.getReferenceValueOfToken(weth, actualTokensLiquidated);

        assertEq(actualCnyLiquidated, expectedCnyLiquidated);
    }

    function testLiquidateRevertsIfHealthFactorNotImproved() public {
        MockMoreCollateralThanDsc mockMoreCollateral = new MockMoreCollateralThanDsc(address(this), wethPriceFeed);

        address[] memory tokens = new address[](1);
        address[] memory feeds = new address[](1);
        tokens[0] = weth;
        feeds[0] = wethPriceFeed;

        CnyEngine mockEngine = new CnyEngine(tokens, feeds, cnyPriceFeed, address(mockMoreCollateral));
        mockMoreCollateral.transferOwnership(address(mockEngine));

        ERC20Mock(weth).mint(user, AMOUNT_COLLATERAL);
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockEngine), AMOUNT_COLLATERAL);
        mockEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        ERC20Mock(weth).mint(liquidator, AMOUNT_TO_COVER);
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(mockEngine), AMOUNT_TO_COVER);
        mockEngine.depositCollateralAndMintDsc(weth, AMOUNT_TO_COVER, AMOUNT_TO_MINT);
        mockMoreCollateral.approve(address(mockEngine), AMOUNT_TO_MINT);
        vm.stopPrank();

        MockV3Aggregator(wethPriceFeed).updateAnswer(18e8);

        vm.startPrank(liquidator);
        uint256 debtToCover = AMOUNT_TO_MINT / 10;
        vm.expectRevert(abi.encodeWithSelector(IDSCEngine.IDSCEngine__HealthFactorNotImproved.selector, 0));
        mockEngine.liquidate(weth, user, debtToCover);
        vm.stopPrank();
    }

    ////////////////////////////////////
    ////////// HEALTH_FACTOR ///////////
    ////////////////////////////////////

    function testHealthFactorCanBecomeLessThanOne() public depositedCollateralAndMintedDsc {
        MockV3Aggregator(wethPriceFeed).updateAnswer(18e8);
        uint256 hf = engine.getHealthFactor(user);
        assert(hf < engine.getMinHealthFactor());
    }

    ////////////////////////////////////
    //////// TRANSFER_FAIL TESTS ///////
    ////////////////////////////////////

    function testDepositCollateralRevertsIfTransferFails() public {
        MockFailCollateral failToken = new MockFailCollateral();
        failToken.mint(user, AMOUNT_COLLATERAL);

        address[] memory tokens = new address[](1);
        address[] memory priceFeeds = new address[](1);
        tokens[0] = address(failToken);
        priceFeeds[0] = wethPriceFeed;

        CnyEngine engineWithFailToken = new CnyEngine(tokens, priceFeeds, cnyPriceFeed, address(cnyToken));

        vm.startPrank(user);
        failToken.approve(address(engineWithFailToken), AMOUNT_COLLATERAL);
        vm.expectRevert(IDSCEngine.IDSCEngine__TransferFailed.selector);
        engineWithFailToken.depositCollateral(address(failToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testMintRevertsIfMintFails() public {
        MockFailMintDsc failDsc = new MockFailMintDsc(address(this));

        address[] memory tokens = new address[](1);
        address[] memory priceFeeds = new address[](1);
        tokens[0] = weth;
        priceFeeds[0] = wethPriceFeed;

        vm.prank(user);
        CnyEngine failEngine = new CnyEngine(tokens, priceFeeds, cnyPriceFeed, address(failDsc));
        failDsc.transferOwnership(address(failEngine));

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(failEngine), AMOUNT_COLLATERAL);
        failEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

        vm.expectRevert(IDSCEngine.IDSCEngine__MintingFailed.selector);
        failEngine.mintDsc(AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testBurnRevertsIfTransferFails() public {
        MockFailBurnDsc failDsc = new MockFailBurnDsc(address(this));

        address[] memory tokens = new address[](1);
        address[] memory priceFeeds = new address[](1);
        tokens[0] = weth;
        priceFeeds[0] = wethPriceFeed;

        vm.prank(user);
        CnyEngine failEngine = new CnyEngine(tokens, priceFeeds, cnyPriceFeed, address(failDsc));
        failDsc.transferOwnership(address(failEngine));

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(failEngine), AMOUNT_COLLATERAL);

        // MockFailBurnDsc only overrides transferFrom, not mint
        // so depositCollateralAndMintDsc succeeds — only burnDsc fails
        failEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);

        vm.expectRevert(IDSCEngine.IDSCEngine__TransferFailed.selector);
        failEngine.burnDsc(AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertsIfTransferFails() public {
        MockFailRedeemCollateral failToken = new MockFailRedeemCollateral();
        failToken.mint(user, AMOUNT_COLLATERAL);

        address[] memory tokens = new address[](1);
        address[] memory priceFeeds = new address[](1);
        tokens[0] = address(failToken);
        priceFeeds[0] = wethPriceFeed;

        CnyEngine failEngine = new CnyEngine(tokens, priceFeeds, cnyPriceFeed, address(cnyToken));

        vm.startPrank(user);
        failToken.approve(address(failEngine), AMOUNT_COLLATERAL);
        failEngine.depositCollateral(address(failToken), AMOUNT_COLLATERAL);

        vm.expectRevert(IDSCEngine.IDSCEngine__TransferFailed.selector);
        failEngine.redeemCollateral(address(failToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ////////////////////////////////////
    ////////// HELPER_CONFIG ///////////
    ////////////////////////////////////

    function testHelperConfigReturnsAnvilConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        (
            address cnyPriceFeedAddress,
            address wethPriceFeedAddress,
            address wbtcPriceFeedAddress,
            address wethAddress,
            address wbtcAddress,
            uint256 deployerPrivateKey
        ) = helperConfig.activeNetworkConfig();

        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getOrCreateAnvilEthConfig();

        assertEq(cnyPriceFeedAddress, networkConfig.cnyPriceFeedAddress);
        assertEq(wethPriceFeedAddress, networkConfig.wethPriceFeedAddress);
        assertEq(wbtcPriceFeedAddress, networkConfig.wbtcPriceFeedAddress);
        assertEq(wethAddress, networkConfig.weth);
        assertEq(wbtcAddress, networkConfig.wbtc);
        assertEq(deployerPrivateKey, networkConfig.deployerKey);
    }

    function testHelperConfigReturnsSepoliaConfig() public {
        vm.chainId(11155111);

        HelperConfig helperConfig = new HelperConfig();
        (
            address cnyPriceFeedAddress,
            address wethPriceFeedAddress,
            address wbtcPriceFeedAddress,
            address wethAddress,
            address wbtcAddress,
            uint256 deployerPrivateKey
        ) = helperConfig.activeNetworkConfig();

        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getSepoliaEthConfig();

        assertEq(cnyPriceFeedAddress, networkConfig.cnyPriceFeedAddress);
        assertEq(wethPriceFeedAddress, networkConfig.wethPriceFeedAddress);
        assertEq(wbtcPriceFeedAddress, networkConfig.wbtcPriceFeedAddress);
        assertEq(wethAddress, networkConfig.weth);
        assertEq(wbtcAddress, networkConfig.wbtc);
        assertEq(deployerPrivateKey, networkConfig.deployerKey);

        assertEq(cnyPriceFeedAddress, 0xeF8A4aF35cd47424672E3C590aBD37FBB7A7759a);
        assertEq(wethPriceFeedAddress, 0x694AA1769357215DE4FAC081bf1f309aDC325306);
        assertEq(wbtcPriceFeedAddress, 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43);
        assertEq(wethAddress, 0xdd13E55209Fd76AfE204dBda4007C227904f0a81);
        assertEq(wbtcAddress, 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063);
        assertEq(deployerPrivateKey, uint256(0));
    }

    ////////////////////////////////////
    //////////// ORACLE_LIB ////////////
    ////////////////////////////////////

    function testRevertsOnStalePrice() public {
        vm.warp(block.timestamp + 5 hours);
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        engine.getReferenceValueOfToken(weth, AMOUNT_COLLATERAL);
    }

    function testFreshPriceDoesNotRevert() public view {
        engine.getReferenceValueOfToken(weth, 1 ether);
    }
}
