// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { StableCoin } from "../../src/StableCoin.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine public engine;
    StableCoin public dsc;
    ERC20Mock public weth;
    ERC20Mock public wbtc;

    uint256 public constant MAX_COLLATERAL_AMOUNT = type(uint96).max;

    constructor(DSCEngine _engine, StableCoin _dsc) {
        engine = _engine;
        dsc = _dsc;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralAssetFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_COLLATERAL_AMOUNT);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    // Helpers
    function _getCollateralAssetFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
