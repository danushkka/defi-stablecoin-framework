// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IBasePeggedToken} from "../interfaces/IBasePeggedToken.sol";

/**
 * @title BasePeggedToken
 * @notice Abstract base for any DSC token.
 * Subclasses only need to pass name and symbol to the constructor.
 * All mint/burn logic lives here and is inherited for free.
 *
 * Ownership is transferred to the engine after deployment,
 * so only the engine can mint and burn.
 */

abstract contract BasePeggedToken is IBasePeggedToken, ERC20Burnable, Ownable {
    ////////////////////////////////////
    ////////////// ERRORS //////////////
    ////////////////////////////////////

    error BasePeggedToken__CannotMintToAddressZero();
    error BasePeggedToken__MustBeMoreThanZero();
    error BasePeggedToken__BurnAmountExceedsBalance();

    ////////////////////////////////////
    //////////// CONSTRUCTOR ///////////
    ////////////////////////////////////

    /**
     * @param name Token name e.g. "USD Stablecoin"
     * @param symbol Token symbol e.g. "USDdsc"
     * @param initialOwner Address that owns the token initially
     *        (should be transferred to the engine after deployment)
     */

    constructor(string memory name, string memory symbol, address initialOwner)
        ERC20(name, symbol)
        Ownable(initialOwner)
    {}

    ////////////////////////////////////
    //////////// FUNCTIONS /////////////
    ////////////////////////////////////

    function mint(address _to, uint256 _amount) external virtual override(IBasePeggedToken) onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert BasePeggedToken__CannotMintToAddressZero();
        }
        if (_amount == 0) {
            revert BasePeggedToken__MustBeMoreThanZero();
        }

        _mint(_to, _amount);
        return true;
    }

    function burn(uint256 _amount) public virtual override(IBasePeggedToken, ERC20Burnable) onlyOwner {
        if (_amount == 0) {
            revert BasePeggedToken__MustBeMoreThanZero();
        }
        if (_amount > balanceOf(msg.sender)) {
            revert BasePeggedToken__BurnAmountExceedsBalance();
        }

        super.burn(_amount);
    }
}
