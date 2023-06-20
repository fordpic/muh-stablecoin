// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MuhStablecoin} from "./MuhStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
    error MSCEngine__MintFailed();

    // State Variables
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

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
    function depositCollateralAndMintMSC() external {}

    /**
     * @notice Follows CEI pattern
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
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

    function redeemCollateralForMSC() external {}

    function redeemCollateral() external {}

    /**
     * @notice Follows CEI pattern
     * @param amountMSCToMint The amount of MSC to mint
     * @notice Must have more collateral value than the minimum threshold
     */
    function mintMSC(
        uint256 amountMSCToMint
    ) external moreThanZero(amountMSCToMint) nonReentrant {
        s_MSCMinted[msg.sender] += amountMSCToMint;
        // revert if they mint too much
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_msc.mint(msg.sender, amountMSCToMint);
        if (!minted) revert MSCEngine__MintFailed();
    }

    function burnMSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    // Private & Internal Functions
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
        (, int256 price, , , ) = priceFeed.latestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / 1e18;
    }
}
