// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/*
 * @title MuhStablecoin
 * @author Ford Pickert
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 *
 * This is the ERC20 implementation of my stablecoin system. It is meant to be governed by MSCEngine
 */

contract MuhStablecoin is ERC20Burnable {
    constructor() ERC20("MuhStablecoin", "MSC") {}
}
