// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {CnyEngine} from "../../src/implementations/CnyEngine.sol";
import {CnyStablecoin} from "../../src/implementations/CnyStablecoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    CnyStablecoin public cnyToken;
    CnyEngine public cnyEngine;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintDscIsCalled;
    address[] public usersDepositedCollateral;

    uint96 public constant MAX_DEPOSIT_COLLATERAL = type(uint96).max;

    constructor(CnyStablecoin _cnyToken, CnyEngine _cnyEngine) {
        cnyToken = _cnyToken;
        cnyEngine = _cnyEngine;

        address[] memory collateralTokens = cnyEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        if (msg.sender == address(cnyEngine)) return;
        if (msg.sender == address(cnyToken)) return;

        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_COLLATERAL);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(cnyEngine), amountCollateral);
        cnyEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        for (uint256 i = 0; i < usersDepositedCollateral.length; i++) {
            if (usersDepositedCollateral[i] == msg.sender) {
                return;
            }
        }

        usersDepositedCollateral.push(msg.sender);
    }

    function mintDsc(uint256 amountToMint, uint256 senderSeed) public {
        if (usersDepositedCollateral.length == 0) return;

        address sender = usersDepositedCollateral[senderSeed % usersDepositedCollateral.length];
        (uint256 totalDscMinted, uint256 collateralValueInRef) = cnyEngine.getAccountInformation(sender);

        uint256 maxMintable = (collateralValueInRef * 50) / 100;
        if (maxMintable <= totalDscMinted) return;

        uint256 safeMax = maxMintable - totalDscMinted;
        if (safeMax == 0) return;

        amountToMint = bound(amountToMint, 1, safeMax);

        // Verify using engine's own formula before minting
        uint256 projectedHF = cnyEngine.calculateHealthFactor(totalDscMinted + amountToMint, collateralValueInRef);
        if (projectedHF < cnyEngine.getMinHealthFactor()) return;

        vm.startPrank(sender);
        try cnyEngine.mintDsc(amountToMint) {
            timesMintDscIsCalled++;
        } catch {}
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateralToRedeem) public {
        if (msg.sender == address(cnyEngine)) return;
        if (msg.sender == address(cnyToken)) return;

        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 userCollateralBalance = cnyEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amountCollateralToRedeem = bound(amountCollateralToRedeem, 0, userCollateralBalance);

        if (amountCollateralToRedeem == 0) return;

        (uint256 totalDscMinted,) = cnyEngine.getAccountInformation(msg.sender);
        if (totalDscMinted > 0) {
            uint256 remainingCollateralValue = cnyEngine.getAccountCollateralValueInReferenceValue(msg.sender)
                - cnyEngine.getReferenceValueOfToken(address(collateral), amountCollateralToRedeem);
            uint256 projectedHealthFactor = cnyEngine.calculateHealthFactor(totalDscMinted, remainingCollateralValue);
            if (projectedHealthFactor < cnyEngine.getMinHealthFactor()) return;
        }

        vm.startPrank(msg.sender);
        cnyEngine.redeemCollateral(address(collateral), amountCollateralToRedeem);
        vm.stopPrank();
    }

    function burnDsc(uint256 amountToBurn) public {
        if (msg.sender == address(cnyEngine)) return;
        if (msg.sender == address(cnyToken)) return;
        
        (uint256 totalDscMinted,) = cnyEngine.getAccountInformation(msg.sender);
        amountToBurn = bound(amountToBurn, 0, totalDscMinted);

        if (amountToBurn == 0) return;

        vm.startPrank(msg.sender);
        cnyToken.approve(address(cnyEngine), amountToBurn);
        cnyEngine.burnDsc(amountToBurn);
        vm.stopPrank();
    }

    ////////////////////////////////////
    ///////////// HELPERS //////////////
    ////////////////////////////////////

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }

    ////////////////////////////////////
    ///////////// GETTERS //////////////
    ////////////////////////////////////

    function getUsersDepositedCollateral() public view returns (address[] memory) {
        return usersDepositedCollateral;
    }
}

