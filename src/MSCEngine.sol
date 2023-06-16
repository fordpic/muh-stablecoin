// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MuhStablecoin} from "./MuhStablecoin.sol";

/**
 * @title MSCEngine
 * @author Ford Pickert
 *
 * The system is designed to be as minimalistic as possible, with tokens maintaining a 1-1 peg.
 *
 * The MSC system should always be overcollateralized.
 *
 * @notice This contract is the core of the MSC System. It handles all logic for mining and redeeming MSC, as well as depositing & withdrawing collateral.
 * @notice This contract is very loosely based on MakerDAO's DSS (DAI) system.
 */
contract MSCEngine {
    // Errors
    error MSCEngine__NeedsMoreThanZero();
    error MSCEngine__TokenAndPriceFeedAddressesMustBeSameLength();

    // State Variables
    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed

    MuhStablecoin private immutable i_msc;

    // Modifiers
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert MSCEngine__NeedsMoreThanZero();
        _;
    }

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
        }

        i_msc = MuhStablecoin(mscAddress);
    }

    // External Functions
    function depositCollateralAndMintMSC() external {}

    function depositCollateral(
        address tokenCollateralAddress,
        uint256 tokenCollateral
    ) external {}

    function redeemCollateralForMSC() external {}

    function redeemCollateral() external {}

    function mintMSC() external {}

    function burnMSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
