// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MuhStablecoin} from "../src/MuhStablecoin.sol";
import {MSCEngine} from "../src/MSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployMSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (MuhStablecoin, MSCEngine) {
        HelperConfig config = new HelperConfig();

        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc,
            uint256 deployerKey
        ) = config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        MuhStablecoin msc = new MuhStablecoin();
        MSCEngine engine = new MSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(msc)
        );

        msc.transferOwnership(address(engine)); // have to transfer bc MSC is ownable
        vm.stopBroadcast();

        return (msc, engine);
    }
}
