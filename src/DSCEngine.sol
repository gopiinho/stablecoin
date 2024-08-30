// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { StableCoin } from "./StableCoin.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
    error DSEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintingFailed();

    ///////////////////////
    /// State Variables ///
    ///////////////////////
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    StableCoin private immutable i_stableCoin;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    ///////////////
    ///  Events ///
    ///////////////
    event CollateralDeposited(address indexed user, address indexed collateralAsset, uint256 indexed collateralAmount);

    ///////////////
    //  Modifier //
    ///////////////
    modifier isAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert DSEngine__TokenNotAllowed();
        }
        _;
    }

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSEngine__MustBeMoreThanZero();
        }
        _;
    }

    ///////////////
    // Functions //
    ///////////////
    constructor(address stableCoin, address[] memory tokenAddresses, address[] memory priceFeedAddresses) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSEngine__TokenAddressesAndPriceFeedAddressesLengthNotEqual();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_stableCoin = StableCoin(stableCoin);
    }

    ////////////////////////
    // External Functions //
    ////////////////////////
    /**
     * @param   tokenCollateralAddress  Address of the token to be used as collateral.
     * @param   tokenCollateralAmount  Amount of token to be used as collateral.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 tokenCollateralAmount)
        external
        isAllowedToken(tokenCollateralAddress)
        moreThanZero(tokenCollateralAmount)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += tokenCollateralAmount;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, tokenCollateralAmount);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), tokenCollateralAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice  User must have more collateral than minimum threshold.
     * @param   amountToMint The amount of StableCoin (DSC) to be minted.
     */
    function mintDsc(uint256 amountToMint) private moreThanZero(amountToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_stableCoin.mint(msg.sender, amountToMint);
        if (!minted) {
            revert DSCEngine__MintingFailed();
        }
    }

    ///////////////////////////////////////
    // Private & Internal View Functions //
    ///////////////////////////////////////
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * @notice  Returns the health factor of the user.
     * If the user's health factor is less than 1, then the user is at risk of liquidation.
     * @param   user Address of user to check the health factor of.
     */
    function _checkHealthFactor(address user) internal view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return ((collateralAdjustedForThreshold * PRECISION) / totalDscMinted);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _checkHealthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    ///////////////////////////////////////
    // Public & External View Functions ///
    ///////////////////////////////////////
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getTokenUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    /**
     * Gets the USD value of a token from chainlink price feeds.
     * @param   token  Address of token to get USD value of.
     * @param   amount  Amount of tokens to get USD value of paired with its address.
     * @return  uint256  USD value of the tokens rounded down to readable numbers.
     */
    function getTokenUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
