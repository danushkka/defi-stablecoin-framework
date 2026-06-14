// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BasePeggedToken} from "../../src/abstract/BasePeggedToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


/*
 * @notice A DSC token whose transferFrom always returns false.
 * Used to test DSCEngine__TransferFailed branch in _burnDsc.
 */
contract MockFailBurnDsc is BasePeggedToken {
    constructor(address initialOwner) BasePeggedToken("MockFailBurn", "MFB", initialOwner) {}

    function transferFrom(address, address, uint256) public pure override(ERC20, IERC20) returns (bool) {
        return false;
    }
}
