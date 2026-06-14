// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {CnyStablecoin} from "../../src/implementations/CnyStablecoin.sol";
import {BasePeggedToken} from "../../src/abstract/BasePeggedToken.sol";

contract BasePeggedTokenTest is Test {
    ////////////////////////////////////
    ///////// STATE VARIABLES //////////
    ////////////////////////////////////

    CnyStablecoin public cnyToken;
    address public OWNER = makeAddr("OWNER");
    address public USER = makeAddr("USER");

    ////////////////////////////////////
    //////////// FUNCTIONS /////////////
    ////////////////////////////////////

    function setUp() public {
        cnyToken = new CnyStablecoin(OWNER);
    }

    ////////////////////////////////////
    /////////// CONSTRUCTOR ////////////
    ////////////////////////////////////

    function testConstructorSetsNameAndSymbol() public view {
        assertEq(cnyToken.name(), "CNY Stablecoin");
        assertEq(cnyToken.symbol(), "CNYdsc");
    }

    function testConstructorSetsOwner() public {
        address expectedOwner = USER;
        CnyStablecoin newToken = new CnyStablecoin(USER);

        assertEq(newToken.owner(), expectedOwner);
    }

    ////////////////////////////////////
    /////////////// MINT ///////////////
    ////////////////////////////////////

    function testCanMint() public {
        uint256 amountToMint = 100;

        vm.startPrank(OWNER);
        uint256 initialBalance = cnyToken.balanceOf(OWNER);
        cnyToken.mint(OWNER, amountToMint);
        uint256 finalBalance = cnyToken.balanceOf(OWNER);
        vm.stopPrank();

        assertEq(finalBalance, initialBalance + amountToMint);
    }

    function testMintReturnsTrue() public {
        vm.prank(OWNER);
        bool result = cnyToken.mint(OWNER, 100);
        assertTrue(result);
    }

    function testMintRevertsIfAddressZero() public {
        vm.prank(cnyToken.owner());
        vm.expectRevert(BasePeggedToken.BasePeggedToken__CannotMintToAddressZero.selector);
        cnyToken.mint(address(0), 100);
    }

    function testMintRevertsIfZeroAmount() public {
        vm.prank(cnyToken.owner());
        vm.expectRevert(BasePeggedToken.BasePeggedToken__MustBeMoreThanZero.selector);
        cnyToken.mint(USER, 0);
    }

    function testMintRevertsIfNotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        cnyToken.mint(address(this), 100);
    }

    ////////////////////////////////////
    /////////////// BURN ///////////////
    ////////////////////////////////////

    function testCanBurn() public {
        uint256 amountToMint = 100;
        uint256 amountToBurn = 50;

        vm.startPrank(OWNER);
        cnyToken.mint(OWNER, amountToMint);
        uint256 balanceBeforeBurn = cnyToken.balanceOf(OWNER);
        cnyToken.burn(amountToBurn);
        uint256 balanceAfterBurn = cnyToken.balanceOf(OWNER);
        vm.stopPrank();

        assertEq(balanceAfterBurn, balanceBeforeBurn - amountToBurn);
    }

    function testBurnRevertsIfZeroAmount() public {
        vm.prank(OWNER);
        vm.expectRevert(BasePeggedToken.BasePeggedToken__MustBeMoreThanZero.selector);
        cnyToken.burn(0);
    }

    function testBurnRevertsIfAmountExceedsBalance() public {
        uint256 amountToBurn = 100;
        vm.prank(OWNER);
        vm.expectRevert(BasePeggedToken.BasePeggedToken__BurnAmountExceedsBalance.selector);
        cnyToken.burn(amountToBurn);
    }

    function testBurnRevertsIfNotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        cnyToken.burn(50);
    }
}
