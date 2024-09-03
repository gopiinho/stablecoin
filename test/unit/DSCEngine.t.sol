// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import "forge-std/console.sol";
import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { StableCoin } from "../../src/StableCoin.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    StableCoin dsc;
    DSCEngine engine;
    HelperConfig config;

    address weth;
    address wbtc;
    address wethPriceFeed;
    address wbtcPriceFeed;

    address public USER = makeAddr("user");
    uint256 public constant COLLATERAL_AMOUNT = 5 ether;
    uint256 public constant STARTING_MOCK_ETH_BALANCE = 50 ether;
    uint256 public constant STABLECOIN_MINT_AMOUNT = 100_000_000_000_000_000_000;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (weth, wbtc, wethPriceFeed, wbtcPriceFeed,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_MOCK_ETH_BALANCE);
    }

    /////////////////////////
    //  Constructor Tests  //
    /////////////////////////
    address[] public tokensAddresses;
    address[] public priceFeedsAddresses;

    function testRevertsIfTokensLengthDoesntMatchPriceFeelsLength() public {
        tokensAddresses.push(weth);
        priceFeedsAddresses.push(wethPriceFeed);
        priceFeedsAddresses.push(wbtcPriceFeed);

        vm.expectRevert(DSCEngine.DSEngine__TokenAddressesAndPriceFeedAddressesLengthNotEqual.selector);

        new DSCEngine(address(dsc), tokensAddresses, priceFeedsAddresses);
    }

    ////////////////////////
    //  Price Feed Tests  //
    ////////////////////////
    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 200 ether;
        uint256 expectedEthAmount = 0.1 ether;
        uint256 actualEthAmount = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedEthAmount, actualEthAmount);
    }

    function testCanGetUsdPrice() public view {
        uint256 ethAmount = 13e18;
        uint256 expectedEthUsd = 26_000e18; // 13e18 * $2000
        uint256 actualEthUsd = engine.getTokenUsdValue(weth, ethAmount);
        assertEq(expectedEthUsd, actualEthUsd);
    }

    ////////////////////////
    //  Collateral Tests  //
    ////////////////////////
    function testRevertsIfZeroCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);

        vm.expectRevert(DSCEngine.DSEngine__MustBeMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    // function testMintingOfStableCoinAfterCollateral() public {
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
    //     engine.depositCollateral(weth, COLLATERAL_AMOUNT);

    //     //mint the stablecoin
    //     engine.mintDsc(STABLECOIN_MINT_AMOUNT);
    //     console.log(STABLECOIN_MINT_AMOUNT);
    // }
}
