// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployMSC} from "../../script/DeployMSC.s.sol";
import {MSCEngine} from "../../src/MSCEngine.sol";
import {MuhStablecoin} from "../../src/MuhStablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployMSC public deployer;
    MSCEngine public engine;
    MuhStablecoin public msc;
    HelperConfig public config;
    Handler public handler;

    address public weth;
    address public wbtc;
    address public USER = makeAddr("user");

    function setUp() external {
        deployer = new DeployMSC();
        (msc, engine, config) = deployer.run();
        (, , weth, wbtc, ) = config.activeNetworkConfig();

        handler = new Handler(engine, msc);
        targetContract(address(handler));
    }

    function invariant_protcolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = msc.totalSupply();
        uint256 totalWethDeposited = ERC20Mock(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = ERC20Mock(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("weth:", wethValue);
        console.log("wbtc:", wbtcValue);
        console.log("totalSupply:", totalSupply);
        console.log("Times mint is called: ", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        engine.getAddtlPrecision();
        engine.getLiquidationThreshold();
        engine.getLiquidationPrecision();
        engine.getMinHealthFactor();
        engine.getLiquidationBonus();
    }
}
