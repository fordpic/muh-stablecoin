// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {MSCEngine} from "../../src/MSCEngine.sol";
import {MuhStablecoin} from "../../src/MuhStablecoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract Handler is Test {
    MSCEngine public engine;
    MuhStablecoin public msc;

    ERC20Mock public weth;
    ERC20Mock public wbtc;

    uint256 public timesMintIsCalled;

    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max; // max uint96 value so that we dont overflow/revert on a 256 when depositing

    constructor(MSCEngine _engine, MuhStablecoin _msc) {
        engine = _engine;
        msc = _msc;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function mintMSC(uint256 amount) public {
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        (uint256 totalMSCMinted, uint256 collateralValueInUsd) = engine
            .getAccountInformation(msg.sender);

        int256 maxMSCToMint = (int256(collateralValueInUsd) / 2) -
            int256(totalMSCMinted);
        if (maxMSCToMint < 0) return;

        amount = bound(amount, 0, uint256(maxMSCToMint));
        if (amount == 0) return;

        engine.mintMSC(amount);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // must be more than zero
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE); // bound the collateral

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateral = engine.getCollateralBalanceOfUser(
            address(collateral),
            msg.sender
        );

        amountCollateral = bound(amountCollateral, 0, maxCollateral);
        if (amountCollateral == 0) return;
        engine.redeemCollateral(address(collateral), amountCollateral);
    }

    // Helper Functions
    function _getCollateralFromSeed(
        uint256 collateralSeed
    ) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
