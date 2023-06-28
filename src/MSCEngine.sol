// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MuhStablecoin} from "./MuhStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title MSCEngine
 * @author Ford Pickert
 *
 * The system is designed to be as minimalistic as possible, with tokens maintaining a 1-1 peg.
 *
 * The MSC system should always be overcollateralized.
 *
 * @notice This contract is the core of the MSC System. It handles all logic for minting and redeeming MSC, as well as depositing & withdrawing collateral.
 * @notice This contract is very loosely based on MakerDAO's DSS (DAI) system.
 */
contract MSCEngine is ReentrancyGuard {
    // Errors
    error MSCEngine__NeedsMoreThanZero();
    error MSCEngine__TokenAndPriceFeedAddressesMustBeSameLength();
    error MSCEngine__NotAllowedToken();
    error MSCEngine__TransferFailed();
    error MSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error MSCEngine__HealthFactorOk();
    error MSCEngine__MintFailed();
    error MSCEngine__HealthFactorNotImproved();

    // Types
    using OracleLib for AggregatorV3Interface;

    // State Variables
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    mapping(address user => uint256 amountMSCMinted) private s_MSCMinted;

    address[] private s_collateralTokens;

    MuhStablecoin private immutable i_msc;

    // Events
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );

    // Modifiers
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert MSCEngine__NeedsMoreThanZero();
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0))
            revert MSCEngine__NotAllowedToken();
        _;
    }

    // Functions
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address mscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert MSCEngine__TokenAndPriceFeedAddressesMustBeSameLength();
        }

        // if they have a price feed, they allowed
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_msc = MuhStablecoin(mscAddress);
    }

    // External Functions

    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountMSCToMint The amount of MSC to mint
     * @notice Deposits your collateral and mints MSC in a single transaction
     */
    function depositCollateralAndMintMSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountMSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintMSC(amountMSCToMint);
    }

    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @notice Follows CEI pattern
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;

        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );

        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );

        if (!success) revert MSCEngine__TransferFailed();
    }

    /**
     * @param tokenCollateralAddress The collateral address to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountMSCToBurn The amount of MSC to burn
     * @notice Redeems underlying collateral and burns MSC in a single transaction
     */
    function redeemCollateralForMSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountMSCToBurn
    ) external {
        burnMSC(amountMSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral already checks health factor, so no check needed here
    }

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(
            msg.sender,
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @param amountMSCToMint The amount of MSC to mint
     * @notice Must have more collateral value than the minimum threshold
     */
    function mintMSC(
        uint256 amountMSCToMint
    ) public moreThanZero(amountMSCToMint) nonReentrant {
        s_MSCMinted[msg.sender] += amountMSCToMint;
        // revert if they mint too much
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_msc.mint(msg.sender, amountMSCToMint);
        if (!minted) revert MSCEngine__MintFailed();
    }

    function burnMSC(uint256 amount) public moreThanZero(amount) {
        _burnMSC(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // dont think this will ever hit but just in case
    }

    // If someone is almost undercollateralized, we will pay you to liquidate them
    /**
     * @param collateral The ERC20 collateral address to liquidate from user
     * @param user The address of the user to liquidate
     * @param debtToCover The amount of MSC to burn to improve the user's health facttor
     * @notice You can partially liquidate a user
     * @notice Liquidators receive a liquidation bonus
     * @notice This function assumes the protocol is 200% overcollateralized
     * @notice If protocol is under 100% collateralization, liquidators will not be incentivized [Known Bug]
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        // Check health factor of user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR)
            revert MSCEngine__HealthFactorOk();

        // Need to burn MSC debt + take collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );

        // Give liquidator 10% bonus
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;

        _redeemCollateral(
            user,
            msg.sender,
            collateral,
            totalCollateralToRedeem
        );

        // Burn MSC
        _burnMSC(debtToCover, user, msg.sender);

        // Check health factor
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor)
            revert MSCEngine__HealthFactorNotImproved();
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // Private & Internal Functions

    function _burnMSC(
        uint256 amountMSCToBurn,
        address onBehalfOf,
        address mscFrom
    ) private {
        s_MSCMinted[onBehalfOf] -= amountMSCToBurn;
        bool success = i_msc.transferFrom(
            mscFrom,
            address(this),
            amountMSCToBurn
        );
        if (!success) revert MSCEngine__TransferFailed();

        i_msc.burn(amountMSCToBurn);
    }

    function _redeemCollateral(
        address from,
        address to,
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;

        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) revert MSCEngine__TransferFailed();
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalMSCMinted, uint256 collateralValueInUsd)
    {
        totalMSCMinted = s_MSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * @notice Returns how close to liquidation a user is
     * @notice If health factor goes below 1, that user can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        (
            uint256 totalMSCMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * 10e18) / totalMSCMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert MSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    // Public & External View Functions

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();

        return
            (usdAmountInWei * 1e18) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        // loop thru each collateral token, get amount deposited, and map it to the price to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / 1e18;
    }

    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalMSCMinted, uint256 collateralValueInUsd)
    {
        (totalMSCMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(
        address user,
        address token
    ) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getCollateralTokenPriceFeed(
        address token
    ) external view returns (address) {
        return s_priceFeeds[token];
    }
}
