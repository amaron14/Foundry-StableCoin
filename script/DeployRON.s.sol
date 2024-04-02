// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {RONEngine} from "../src/RONEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployRON is Script {
    function run() external returns (DecentralizedStableCoin, RONEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address wethPriceFeed, address wbtcPriceFeed, address weth, address wbtc,) = config.activeNetworkConfig();
        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = weth;
        tokenAddresses[1] = wbtc;

        address[] memory priceFeedAddresses = new address[](2);
        priceFeedAddresses[0] = wethPriceFeed;
        priceFeedAddresses[1] = wbtcPriceFeed;

        vm.startBroadcast();
        DecentralizedStableCoin ron = new DecentralizedStableCoin();
        RONEngine ronEngine = new RONEngine(tokenAddresses, priceFeedAddresses, address(ron));
        ron.transferOwnership(address(ronEngine));
        vm.stopBroadcast();
        return (ron, ronEngine, config);
    }
}
