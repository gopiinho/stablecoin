// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";
import { DSCEngine } from "../src/DSCEngine.sol";
import { StableCoin } from "../src/StableCoin.sol";
import { HelperConfig } from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DSCEngine, StableCoin) {
        HelperConfig config = new HelperConfig();
        (address weth, address wbtc, address wethUsdPriceFeed, address wbtcUsdPriceFeed, uint256 deployerKey) =
            config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast();
        StableCoin stableCoin = new StableCoin();
        DSCEngine dscEngine = new DSCEngine(address(stableCoin), tokenAddresses, priceFeedAddresses);

        stableCoin.transferOwnership(address(dscEngine));
        vm.stopBroadcast();

        return (stableCoin, dscEngine);
    }
}
