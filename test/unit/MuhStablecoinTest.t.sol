// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {MuhStablecoin} from "../../src/MuhStablecoin.sol";

contract MuhStablecoinTest is Test {
    error MuhStablecoin__MustBeMoreThanZero();
    error MuhStablecoin__BurnAmountExceedsBalance();

    MuhStablecoin public msc;
    address public USER = makeAddr("user");

    uint256 public constant STARTING_MSC_BALANCE = 10 ether;
    uint256 public constant BURN_AMOUNT = 1 ether;

    function setUp() public {
        msc = new MuhStablecoin();
        msc.transferOwnership(USER);
    }

    function testMintsProperly() public {
        vm.startPrank(USER);
        msc.mint(USER, STARTING_MSC_BALANCE);
        vm.stopPrank();

        uint256 userBalance = msc.balanceOf(USER);
        assertEq(userBalance, STARTING_MSC_BALANCE);
    }

    function testBurnsProperly() public {
        vm.startPrank(USER);
        msc.mint(USER, STARTING_MSC_BALANCE);
        msc.burn(BURN_AMOUNT);
        uint256 userCurrentBalance = msc.balanceOf(USER);
        uint256 userExpectedFinalBalance = STARTING_MSC_BALANCE - BURN_AMOUNT;
        vm.stopPrank();

        console.log("Current Balance: ", userCurrentBalance);
        console.log("Expected Balance: ", userExpectedFinalBalance);

        assertEq(userCurrentBalance, userExpectedFinalBalance);
    }
}
