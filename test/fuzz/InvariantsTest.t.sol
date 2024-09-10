// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// Protocol Invariants
// 1. The total supply of stablecoin (DSC) should always be lower than total collateral value.
// 2. Getter functions should never revert.

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { StableCoin } from "../../src/StableCoin.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Handler } from "./Handler.t.sol";

contract InvariantTest is StdInvariant, Test {
    DeployDSC public deployer;
    HelperConfig public config;
    DSCEngine public engine;
    StableCoin public stableCoin;
    address public weth;
    address public wbtc;
    Handler public handler;

    function setUp() external {
        deployer = new DeployDSC();
        (stableCoin, engine, config) = deployer.run();
        (weth, wbtc,,,) = config.activeNetworkConfig();
        handler = new Handler(engine, stableCoin);
        //use this for open testing for super weird randomness
        // targetContract(address(engine));
        targetContract(address(handler));
    }

    // Get the total USD value of protocol collateral.
    // Compare it with total supply of minted DSC.
    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = stableCoin.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbthDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getTokenUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = engine.getTokenUsdValue(wbtc, totalWbthDeposited);

        console.log("wethValue: %s", wethValue);
        console.log("wbtcValue: %s", wbtcValue);
        console.log("DSC supply: %s", totalSupply);
        console.log("Times mint is called: ", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }
}
