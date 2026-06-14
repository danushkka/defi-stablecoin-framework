// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

/**
 * @notice A collateral token that silently returns false on transfers.
 * Used to test DSCEngine__TransferFailed branches in depositCollateral
 * and redeemCollateral.
 */
contract MockFailCollateral is ERC20Mock {
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        return false;
    }
}
