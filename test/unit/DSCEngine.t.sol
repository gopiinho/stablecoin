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
    uint256 public constant COLLATERAL_AMOUNT = 5e18;
    uint256 public constant STARTING_MOCK_ETH_BALANCE = 50e18;
    uint256 public constant STABLECOIN_MINT_AMOUNT = 100_000_000_000_000_000_000;
    uint256 public constant DSC_AMOUNT_TO_MINT = 50e18;

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
    modifier depositCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateralAndMintDsc(weth, COLLATERAL_AMOUNT, DSC_AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testRevertsIfZeroCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);

        vm.expectRevert(DSCEngine.DSEngine__MustBeMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateralTokens() public {
        ERC20Mock randomToken = new ERC20Mock();
        ERC20Mock(randomToken).mint(USER, COLLATERAL_AMOUNT);

        vm.startPrank(USER);
        ERC20Mock(randomToken).approve(address(engine), COLLATERAL_AMOUNT);
        vm.expectRevert(DSCEngine.DSEngine__TokenNotAllowed.selector);
        engine.depositCollateral(address(randomToken), COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testCandepositCollateralAndMintDscAndGetAccountInfo() public depositCollateralAndMintedDsc {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = dsc.balanceOf(USER);
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(COLLATERAL_AMOUNT, expectedDepositAmount);
    }

    function testCandepositCollateralAndMintDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateralAndMintDsc(weth, COLLATERAL_AMOUNT, DSC_AMOUNT_TO_MINT);
        vm.stopPrank();

        (uint256 totalDscMinted,) = engine.getAccountInformation(USER);
        assertEq(totalDscMinted, DSC_AMOUNT_TO_MINT);
    }

    function testCanWithdrawCollateral() public depositCollateralAndMintedDsc {
        uint256 withdrawAmount = 3e18;
        uint256 startingUserCollateral = engine.getUserDepositedCollateralBalance(USER, weth);
        assertEq(startingUserCollateral, COLLATERAL_AMOUNT);

        vm.startPrank(USER);
        engine.withdrawCollateral(weth, withdrawAmount);
        vm.stopPrank();

        uint256 endingUserCollateral = engine.getUserDepositedCollateralBalance(USER, weth);
        assertEq(startingUserCollateral - withdrawAmount, endingUserCollateral);
    }

    ///////////////////
    // Mint DSC Test //
    ///////////////////
    function testCanMintDsc() public depositCollateralAndMintedDsc {
        uint256 userBalanceOfDsc = dsc.balanceOf(USER);
        assertEq(userBalanceOfDsc, DSC_AMOUNT_TO_MINT);
    }

    ///////////////////
    // Burn DSC Test //
    ///////////////////
    function testCantBurnMoreThanUserHas() public {
        vm.prank(USER);
        vm.expectRevert();
        engine.burnDsc(1e18);
    }

    function testCanBurnDsc() public depositCollateralAndMintedDsc {
        uint256 dscToBurn = 20e18;
        vm.startPrank(USER);
        dsc.approve(address(engine), dscToBurn);
        engine.burnDsc(dscToBurn);
        vm.stopPrank();
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, DSC_AMOUNT_TO_MINT - dscToBurn);
    }

    ////////////////////////
    // Health Factir Test //
    ////////////////////////
    function testProperlyReportsHealthFactor() public depositCollateralAndMintedDsc {
        uint256 expectedHealthFactor = 100e18;
        uint256 healthFactor = engine.getHealthFactor(USER);
        // 5 ether collateral * 2000 = $10000
        //  10000 * 0.5 = 5000 (50% liquidation threshold)
        // Minted $50 DCE means we need $100 collateral at all times
        // 5000 / 50 = 100 health factor
        assertEq(expectedHealthFactor, healthFactor);
    }
}
