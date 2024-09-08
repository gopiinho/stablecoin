// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { StableCoin } from "./StableCoin.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 *
 *
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
    /// Errors  ///
    ///////////////
    error DSEngine__MustBeMoreThanZero();
    error DSEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSEngine__TokenAddressesAndPriceFeedAddressesLengthNotEqual();
    error DSEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintingFailed();
    error DSCEngine__BurningFailed();
    error DSCEngine__HeathFactorOk(uint256 heathFactor);
    error DSCEngine__HealthFactorNotImproved();

    ///////////////////////
    /// State Variables ///
    ///////////////////////
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS_PERCENTAGE = 10;

    StableCoin private immutable i_stableCoin;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    ///////////////
    ///  Events ///
    ///////////////
    event CollateralDeposited(address indexed user, address indexed collateralAsset, uint256 indexed collateralAmount);
    event CollateralWithdrawn(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed collateralAsset,
        uint256 collateralAmount
    );

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
     * @notice  Deposits the given tokens as collateral and mints the input amount os StableCoin (DSC).
     * @param   tokenCollateralAddress  Address of the token to be used as collateral.
     * @param   tokenCollateralAmount  Amount of token to be used as collateral.
     * @param   amountToMint  Amount of StableCoin (DSC) to be minted.
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 tokenCollateralAmount,
        uint256 amountToMint
    ) public {
        depositCollateral(tokenCollateralAddress, tokenCollateralAmount);
        mintDsc(amountToMint);
    }

    /**
     * @notice  Deposits the given tokens as collateral.
     * @param   tokenCollateralAddress  Address of the token to be used as collateral.
     * @param   tokenCollateralAmount  Amount of token to be used as collateral.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 tokenCollateralAmount)
        public
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
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice  This function burns the StableCoin (DSC) and withdraws the given tokens as collateral.
     * @param   tokenCollateralAddress  Address of the token to be withdrown as collateral.
     * @param   tokenCollateralAmount  Amount of token to be withdrawn as collateral.
     */
    function withdrawCollateralForDsc(address tokenCollateralAddress, uint256 tokenCollateralAmount)
        external
        isAllowedToken(tokenCollateralAddress)
        moreThanZero(tokenCollateralAmount)
    {
        burnDsc(tokenCollateralAmount);
        withdrawCollateral(tokenCollateralAddress, tokenCollateralAmount);
    }

    /**
     * @notice  Withdraws the given tokens as collateral.
     * @param   tokenCollateralAddress  Address of the token to be withdrown as collateral.
     * @param   tokenCollateralAmount  Amount of token to be withdrawn as collateral.
     */
    function withdrawCollateral(address tokenCollateralAddress, uint256 tokenCollateralAmount)
        public
        isAllowedToken(tokenCollateralAddress)
        moreThanZero(tokenCollateralAmount)
        nonReentrant
    {
        _withdrawCollateral(msg.sender, msg.sender, tokenCollateralAddress, tokenCollateralAmount);
    }

    /**
     * @notice  User must have more collateral than minimum threshold.
     * @notice  Mints the input amount of StableCoin (DSC) to the user.
     * @param   amountToMint The amount of StableCoin (DSC) to be minted.
     */
    function mintDsc(uint256 amountToMint) public moreThanZero(amountToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_stableCoin.mint(msg.sender, amountToMint);
        if (!minted) {
            revert DSCEngine__MintingFailed();
        }
    }

    /**
     * @notice  Burns the input amount of StableCoin (DSC) from the user and reduces their accounting debt.
     * @param   amountToBurn  Amount of StableCoin (DSC) to be burned.
     */
    function burnDsc(uint256 amountToBurn) public moreThanZero(amountToBurn) nonReentrant {
        _burnDsc(amountToBurn, msg.sender, msg.sender);
    }

    ///////////////////////////////////////
    // Private & Internal View Functions //
    ///////////////////////////////////////
    /**
     * @dev Low-Level function, do not call this, unless function calling this is checking for health factors.
     */
    function _burnDsc(uint256 amountToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountToBurn;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool success = i_stableCoin.transferFrom(dscFrom, address(this), amountToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_stableCoin.burn(amountToBurn);
    }

    function _withdrawCollateral(
        address from,
        address to,
        address tokenCollateralAddress,
        uint256 tokenCollateralAmount
    ) private isAllowedToken(tokenCollateralAddress) moreThanZero(tokenCollateralAmount) {
        s_collateralDeposited[from][tokenCollateralAddress] -= tokenCollateralAmount;
        emit CollateralWithdrawn(from, to, tokenCollateralAddress, tokenCollateralAmount);
        bool success = IERC20(tokenCollateralAddress).transfer(to, tokenCollateralAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

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
        if (totalDscMinted == 0) {
            return type(uint256).max; // Return maximum value if no DSC is minted
        }
        return ((collateralAdjustedForThreshold * PRECISION) / totalDscMinted);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _checkHealthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /**
     * @notice  Allows other users to patially liquidate the positions of other users if their help factor is below
     * MIN_HEALTH_FACTOR.
     * @notice  You will get a liquidation bonus for taking the users funds.
     * @notice  This function assumes the protocol is roughly 200% over collateralized in order for this mechanism to
     * work.
     * @param   collateral The ERC20 address of token to liquidate from user.
     * @param   user The address of user that has broken the minimum heath factor.
     * @param   debtToCover The amount of DSC to burn to improve the heath factor of the user.
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _checkHealthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HeathFactorOk(startingUserHealthFactor);
        }
        // Calculate how many collateral tokens we need to cover the debt
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // Here the person who liquidates the collateral will get a bonus of LIQUIDATION_BONUS_PERCENTAGE
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS_PERCENTAGE) / PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _withdrawCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _checkHealthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////////////////////////
    // Public & External View Functions ///
    ///////////////////////////////////////
    /**
     * @notice  Gets the total collateral value of a user in USD.
     * @param   user Address of user to check the collateral value.
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getTokenUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    /**
     * @notice  Gets the amount of a token in USD from chainlink price feeds.
     * @param   token Address of ERC20 token to check the amount per USD value of.
     * @param   amountInUsd USD amount to check the token value of.
     */
    function getTokenAmountFromUsd(address token, uint256 amountInUsd) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((amountInUsd * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    /**
     * @notice  Gets the USD value of a token from chainlink price feeds.
     * @param   token  Address of token to get USD value of.
     * @param   amount  Amount of tokens to get USD value of paired with its address.
     * @return  uint256  USD value of the tokens rounded down to readable numbers.
     */
    function getTokenUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getUserDepositedCollateralBalance(address user, address collateral) external view returns (uint256) {
        return s_collateralDeposited[user][collateral];
    }

    function getUserMintedDsc(address user) external view returns (uint256) {
        return s_DSCMinted[user];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _checkHealthFactor(user);
    }
}
