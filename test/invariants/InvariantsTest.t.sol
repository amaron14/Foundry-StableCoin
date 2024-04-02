// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployRON} from "../../script/DeployRON.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {RONEngine} from "../../src/RONEngine.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {Handler} from "./handlers/Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DecentralizedStableCoin ron;
    RONEngine ronEngine;
    HelperConfig config;
    address wethPriceFeed;
    address wbtcPriceFeed;
    address weth;
    address wbtc;
    ERC20Mock wethMock;
    ERC20Mock wbtcMock;
    Handler handler;
    address public USER = makeAddr("user");

    function setUp() public {
        DeployRON deployer = new DeployRON();
        (ron, ronEngine, config) = deployer.run();
        (wethPriceFeed, wbtcPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        wethMock = ERC20Mock(weth);
        wethMock.mint(USER, type(uint96).max);
        wbtcMock = ERC20Mock(wbtc);
        wbtcMock.mint(USER, type(uint96).max);
        handler = new Handler(ronEngine, ron, USER);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = ron.totalSupply();
        uint256 wethDeposted = ERC20Mock(weth).balanceOf(address(ronEngine));
        uint256 wbtcDeposited = ERC20Mock(wbtc).balanceOf(address(ronEngine));

        uint256 wethValue = ronEngine.getUsdValue(weth, wethDeposted);
        uint256 wbtcValue = ronEngine.getUsdValue(wbtc, wbtcDeposited);

        console.log("wethValue: %s", wethValue);
        console.log("wbtcValue: %s", wbtcValue);
        console.log("total supply: %s", totalSupply);

        assert(wethValue + wbtcValue >= totalSupply);
    }
}
