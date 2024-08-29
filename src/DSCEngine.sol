// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { StableCoin } from "./StableCoin.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * @author  https://github.com/gopiinho
 * @title   DSEngine
 * This system is minimal by designs and have to maintain 1 DSC == $1 USD peg.
 *
 * The properties of the stablecoin are following:
 * - Algorithmically Stable
 * - $1 USD Pegged
 * - Exogenous Collateral
 *
 * @notice This contract is the core of Stablecoin system and handles the logic for minting and redeeming DSC, as well
 * as depositing and withdrawing underlying collateral.
 * @notice This system is loosely based on MakerDAO's DAI system.
 */
contract DSCEngine is ReentrancyGuard {
    ///////////////
    ///  Errors ///
    ///////////////
    error DSEngine__MustBeMoreThanZero();
    error DSEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSEngine__TokenAddressesAndPriceFeedAddressesLengthNotEqual();

    ///////////////////////
    /// State Variables ///
    ///////////////////////
    StableCoin private immutable i_stableCoin;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

    ///////////////
    ///  Events ///
    ///////////////
    event CollateralDeposited(address indexed user, address indexed collateralAsset, uint256 indexed collateralAmount);

    ///////////////
    //  Modifier //
    ///////////////
    modifier isAllowedToken(address _tokenAddress) {
        if (s_priceFeeds[_tokenAddress] == address(0)) {
            revert DSEngine__TokenNotAllowed();
        }
        _;
    }

    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSEngine__MustBeMoreThanZero();
        }
        _;
    }

    ///////////////
    // Functions //
    ///////////////
    constructor(address _stableCoin, address[] memory _tokenAddresses, address[] memory _priceFeedAddresses) {
        if (_tokenAddresses.length != _priceFeedAddresses.length) {
            revert DSEngine__TokenAddressesAndPriceFeedAddressesLengthNotEqual();
        }
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_priceFeeds[_tokenAddresses[i]] = _priceFeedAddresses[i];
        }
        i_stableCoin = StableCoin(_stableCoin);
    }

    ////////////////////////
    // External Functions //
    ////////////////////////
    /**
     * @param   _tokenCollateralAddress  Address of the token to be used as collateral.
     * @param   _tokenCollateralAmount  Amount of token to be used as collateral.
     */
    function depositCollateral(address _tokenCollateralAddress, uint256 _tokenCollateralAmount)
        external
        isAllowedToken(_tokenCollateralAddress)
        moreThanZero(_tokenCollateralAmount)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][_tokenCollateralAddress] += _tokenCollateralAmount;
        emit CollateralDeposited(msg.sender, _tokenCollateralAddress, _tokenCollateralAmount);
        bool success = IERC20(_tokenCollateralAddress).transferFrom(msg.sender, address(this), _tokenCollateralAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }
}
