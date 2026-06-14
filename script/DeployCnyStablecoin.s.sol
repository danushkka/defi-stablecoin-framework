// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CnyStablecoin} from "../src/implementations/CnyStablecoin.sol";
import {CnyEngine} from "../src/implementations/CnyEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Script} from "forge-std/Script.sol";

/**
 * @title DeployCnyStablecoin
 * @notice Deploys the CNY-pegged stablecoin system.
 *
 * Deployment sequence:
 * 1. Deploy CnyStablecoin (deployer is initial owner)
 * 2. Deploy CnyEngine
 * 3. Transfer CnyStablecoin ownership to CnyEngine
 */

contract DeployCnyStablecoin is Script {
    address[] public collateralTokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (CnyStablecoin, CnyEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (
            address cnyPriceFeedAddress,
            address wethPriceFeedAddress,
            address wbtcPriceFeedAddress,
            address weth,
            address wbtc,
            uint256 deployerKey
        ) = config.activeNetworkConfig();

        collateralTokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethPriceFeedAddress, wbtcPriceFeedAddress];

        vm.startBroadcast(deployerKey);
        address deployer = vm.addr(deployerKey);

        // Step 1 - Deploy the Dsc token
        CnyStablecoin cnyToken = new CnyStablecoin(deployer);

        // Step 2 - Deploy the Engine
        CnyEngine cnyEngine =
            new CnyEngine(collateralTokenAddresses, priceFeedAddresses, cnyPriceFeedAddress, address(cnyToken));

        // Step 3 - Transfer ownership to the Engine
        cnyToken.transferOwnership(address(cnyEngine));
        vm.stopBroadcast();

        return (cnyToken, cnyEngine, config);
    }
}
