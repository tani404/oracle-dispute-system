//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {OracleDisputeSystem} from "../src/OracleDisputeSystem.sol";

contract DeployODS is Script {
    function run() public returns (OracleDisputeSystem) {
        vm.startBroadcast();
        OracleDisputeSystem ods = new OracleDisputeSystem();
        vm.stopBroadcast();

        return ods;
    }
}
