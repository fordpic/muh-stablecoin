// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title MSCEngine
 * @author Ford Pickert
 *
 * The system is designed to be as minimalistic as possible, with tokens maintaining a 1-1 peg
 *
 * The MSC system should always be overcollateralized
 *
 * @notice This contract is the core of the MSC System. It handles all logic for mining and redeeming MSC, as well as depositing & withdrawing collateral
 * @notice This contract is very loosely based on MakerDAO's DSS (DAI) system.
 */
contract MSCEngine {
    function depositCollateralAndMintMSC() external {}

    function redeemCollateralForMSC() external {}

    function burnMSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
