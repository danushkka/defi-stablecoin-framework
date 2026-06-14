// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @notice Library for Chainlink price feed validation.
 * Used by AbstractDSCEngine to prevent using stale prices
 * during market disruptions or oracle failures.
 *
 * Core behavior: reverts if the price feed hasn't been
 * updated within MAX_TIME_SINCE_LAST_UPDATE.
 */

library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant MAX_TIME_SINCE_LAST_UPDATE = 3 hours; // 3 hours = 10800 seconds

    function stalePriceCheck(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = priceFeed.latestRoundData();
        uint256 timePassedSinceLastUpdate = block.timestamp - updatedAt;

        if (timePassedSinceLastUpdate > MAX_TIME_SINCE_LAST_UPDATE) {
            revert OracleLib__StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
