// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IBasePeggedToken
 * @notice Interface for any DSC token.
 * The engine only needs mint, burn, and standard ERC20 functions.
 */
interface IBasePeggedToken is IERC20 {
    /// @notice Mints `amount` tokens to `to`. Only callable by owner (engine).
    /// @return bool Always returns true on success, reverts on failure.
    function mint(address to, uint256 amount) external returns (bool);

    /// @notice Burns `amount` tokens from caller. Only callable by owner (engine).
    function burn(uint256 amount) external;
}
