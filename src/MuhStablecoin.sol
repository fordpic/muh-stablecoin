// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 * @title MuhStablecoin
 * @author Ford Pickert
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 *
 * This is the ERC20 implementation of my stablecoin system. It is meant to be governed by MSCEngine
 */

contract MuhStablecoin is ERC20Burnable, Ownable {
    error MuhStablecoin__MustBeMoreThanZero();
    error MuhStablecoin__BurnAmountExceedsBalance();
    error MuhStablecoin__NotZeroAddress();

    constructor() ERC20("MuhStablecoin", "MSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (_amount <= 0) revert MuhStablecoin__MustBeMoreThanZero();
        if (balance < _amount) revert MuhStablecoin__BurnAmountExceedsBalance();

        super.burn(_amount);
    }

    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) revert MuhStablecoin__NotZeroAddress();
        if (_amount <= 0) revert MuhStablecoin__MustBeMoreThanZero();

        _mint(_to, _amount);
        return true;
    }
}
