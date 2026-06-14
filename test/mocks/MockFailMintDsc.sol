// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BasePeggedToken} from "../../src/abstract/BasePeggedToken.sol";

/**
 * @notice A DSC token whose mint always returns false.
 * Used to test DSCEngine__MintingFailed branch in _mintDsc.
 */
contract MockFailMintDsc is BasePeggedToken {
    constructor(address initialOwner) BasePeggedToken("MockFailMint", "MFM", initialOwner) {}

    function mint(address, uint256) external pure override(BasePeggedToken) returns (bool) {
        return false;
    }
}
