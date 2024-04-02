// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    uint8 public constant DECIMALS = 8;
    int256 public constant WETH_PRICE = 4000e8;
    int256 public constant WBTC_PRICE = 70000e8;

    struct NetworkConfig {
        address wethPriceFeed;
        address wbtcPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        } else {
            activeNetworkConfig = getAnvilConfig();
        }
    }

    function getSepoliaConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethPriceFeed != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator wethMockPriceFeed = new MockV3Aggregator(DECIMALS, WETH_PRICE);
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH");
        wethMock.mint(address(this), 1000e8);

        MockV3Aggregator wbtcMockPriceFeed = new MockV3Aggregator(DECIMALS, WBTC_PRICE);
        ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC");
        wbtcMock.mint(address(this), 1000e8);

        vm.stopBroadcast();
        return NetworkConfig({
            wethPriceFeed: address(wethMockPriceFeed),
            wbtcPriceFeed: address(wbtcMockPriceFeed),
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            deployerKey: vm.envUint("ANVIL_PRIVATE_KEY")
        });
    }
}
