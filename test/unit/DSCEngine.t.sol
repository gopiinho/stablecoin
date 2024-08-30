// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { StableCoin } from "../../src/StableCoin.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    StableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address weth;
    address wethPriceFeed;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (weth,, wethPriceFeed,,) = config.activeNetworkConfig();
    }

    ////////////////////////
    //  Price Feed Tests  //
    ////////////////////////
    function testCanGetUsdPrice() public view {
        uint256 ethAmount = 13e18;
        uint256 expectedEthUsd = 26_000e18; // 13e18 * $2000

        uint256 actualEthUsd = engine.getTokenUsdValue(weth, ethAmount);

        assertEq(expectedEthUsd, actualEthUsd);
    }
}
