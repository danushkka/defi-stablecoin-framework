// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import {BasePeggedToken} from "../abstract/BasePeggedToken.sol";

/**
 * @title CnyStablecoin
 * @notice CNY-pegged decentralized stablecoin token.
 * All logic is inherited from BasePeggedToken.
 * This contract exists purely to define the token's identity.
 */
contract CnyStablecoin is BasePeggedToken {
    constructor(address initialOwner) BasePeggedToken("CNY Stablecoin", "CNYdsc", initialOwner) {}
}
