// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AbstractDSCEngine} from "../abstract/AbstractDSCEngine.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "../libraries/OracleLib.sol";

/**
 * @title CnyEngine
 * @notice CNY-pegged implementation of AbstractDSCEngine.
 * The only responsibility of this contract is to provide
 * the CNY/USD price to the parent engine.
 */

contract CnyEngine is AbstractDSCEngine {
    using OracleLib for AggregatorV3Interface;

    AggregatorV3Interface private immutable i_cnyPriceFeed;

    /**
     * @param _collateralTokenAddresses Addresses of the collateral tokens
     * @param _priceFeedAddresses Addresses of the price feeds
     * @param _cnyPriceFeedAddress Address of the CNY/USD price feed
     * @param _cnyTokenAddress Address of the DSC token
     */
    constructor(
        address[] memory _collateralTokenAddresses,
        address[] memory _priceFeedAddresses,
        address _cnyPriceFeedAddress,
        address _cnyTokenAddress
    ) AbstractDSCEngine(_collateralTokenAddresses, _priceFeedAddresses, _cnyTokenAddress) {
        i_cnyPriceFeed = AggregatorV3Interface(_cnyPriceFeedAddress);
    }

    function _getReferenceValuePerUsd() internal view override returns (uint256) {
        (, int256 cnyPerUsd,,,) = i_cnyPriceFeed.stalePriceCheck();
        return (DECIMAL_PRECISION * DECIMAL_PRECISION) / (uint256(cnyPerUsd) * ADDITIONAL_FEED_PRECISION);
    }
}
