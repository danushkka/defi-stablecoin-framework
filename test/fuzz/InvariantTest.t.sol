// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployCnyStablecoin} from "../../script/DeployCnyStablecoin.s.sol";
import {CnyEngine} from "../../src/implementations/CnyEngine.sol";
import {CnyStablecoin} from "../../src/implementations/CnyStablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantTest is StdInvariant, Test {
    DeployCnyStablecoin deployer;
    CnyEngine engine;
    CnyStablecoin cnyToken;
    HelperConfig config;
    Handler handler;

    address weth;
    address wbtc;

    function setUp() public {
        deployer = new DeployCnyStablecoin();
        (cnyToken, engine, config) = deployer.run();
        handler = new Handler(cnyToken, engine);
        targetContract(address(handler));
        (,,, weth, wbtc,) = config.activeNetworkConfig();
    }

    /**
     * @notice Core solvency invariant — total DSC supply must never
     * exceed total collateral value in the reference currency (CNY).
     * This holds regardless of which peg currency is used.
     */
    function invariant_totalSupplyNeverExceedsCollateralValue() public view {
        uint256 totalSupply = cnyToken.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValueInRef = engine.getReferenceValueOfToken(weth, totalWethDeposited);
        uint256 wbtcValueInRef = engine.getReferenceValueOfToken(wbtc, totalWbtcDeposited);

        assert(totalSupply <= wethValueInRef + wbtcValueInRef);
    }

    /**
     * @notice Accounting invariant — engine's internal records must
     * match actual token balances held by the contract.
     */
    function invariant_engineAccountingMatchesActualBalances() public view {
        address[] memory users = handler.getUsersDepositedCollateral();

        uint256 totalDscMinted;
        uint256 totalWeth;
        uint256 totalWbtc;

        for (uint256 i = 0; i < users.length; i++) {
            (uint256 dscMinted,) = engine.getAccountInformation(users[i]);
            totalDscMinted += dscMinted;
            totalWeth += engine.getCollateralBalanceOfUser(users[i], weth);
            totalWbtc += engine.getCollateralBalanceOfUser(users[i], wbtc);
        }

        assertEq(totalDscMinted, cnyToken.totalSupply());
        assertEq(totalWeth, IERC20(weth).balanceOf(address(engine)));
        assertEq(totalWbtc, IERC20(wbtc).balanceOf(address(engine)));
    }

    /**
     * @notice Health factor invariant — no user with minted DSC
     * should ever have a health factor below the minimum.
     */
    function invariant_healthFactorNeverBreaks() public view {
        address[] memory users = handler.getUsersDepositedCollateral();
        for (uint256 i = 0; i < users.length; i++) {
            (uint256 dscMinted,) = engine.getAccountInformation(users[i]);
            if (dscMinted > 0) {
                assert(engine.getHealthFactor(users[i]) >= engine.getMinHealthFactor());
            }
        }
    }

    /**
     * @notice Engine holds no DSC — all DSC passing through the engine
     * during burns should be immediately destroyed, never held.
     */
    function invariant_engineHoldsNoDsc() public view {
        assertEq(cnyToken.balanceOf(address(engine)), 0);
    }

    /**
     * @notice Getters never revert — all view functions must always
     * return without reverting regardless of protocol state.
     */
    function invariant_gettersShouldNotRevert() public view {
        engine.getCollateralTokens();
        engine.getStablecoin();
        engine.getReferenceValuePerUsd();
    }
}
