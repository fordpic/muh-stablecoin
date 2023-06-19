// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MuhStablecoin} from "../src/MuhStablecoin.sol";
import {MSCEngine} from "../src/MSCEngine.sol";

contract DeployMSC is Script {
    function run() external returns (MuhStablecoin, MSCEngine) {
        vm.startBroadcast();
        MuhStablecoin msc = new MuhStablecoin();
        // MSCEngine engine = new MSCEngine();
        vm.stopBroadcast();
    }
}
