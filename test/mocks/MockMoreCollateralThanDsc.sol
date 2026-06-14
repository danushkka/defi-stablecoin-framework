// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BasePeggedToken} from "../../src/abstract/BasePeggedToken.sol";
import {MockV3Aggregator} from "./MockV3Aggregator.sol";

contract MockMoreCollateralThanDsc is BasePeggedToken {
    address public mockAggregator;

    constructor(address initialOwner, address _mockAggregator)
        BasePeggedToken("MockMoreCollateral", "MMC", initialOwner)
    {
        mockAggregator = _mockAggregator;
    }

    function burn(uint256 _amount) public override(BasePeggedToken) onlyOwner {
        MockV3Aggregator(mockAggregator).updateAnswer(0);
        super.burn(_amount);
    }
}
