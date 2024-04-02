// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployRON} from "../../../script/DeployRON.s.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";
import {RONEngine} from "../../../src/RONEngine.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract Handler is Test {
    RONEngine ronEngine;
    DecentralizedStableCoin ron;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 public mintTimesCalled = 0;
    int256 public constant INITIAL_WETH_PRICE = 4000e8;
    int256 public constant INITIAL_WBTC_PRICE = 70000e8;

    uint256 MAX_DEPOSIT_AMOUNT = type(uint96).max;
    address[] depositers;

    address mainLiquidator;

    constructor(RONEngine _ronEngine, DecentralizedStableCoin _ron, address _mainLiquidator) {
        ronEngine = _ronEngine;
        ron = _ron;
        address[] memory collateralAddresses = ronEngine.getCollateralTokens();
        weth = ERC20Mock(collateralAddresses[0]);
        wbtc = ERC20Mock(collateralAddresses[1]);
        mainLiquidator = _mainLiquidator;
    }

    ///////////////
    // RonEngine //
    ///////////////

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_AMOUNT);
        collateral.mint(msg.sender, amountCollateral);
        vm.startPrank(msg.sender);
        collateral.approve(address(ronEngine), amountCollateral);
        ronEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        depositers.push(msg.sender);
    }

    function mintRon(uint256 amount, uint256 depositersSeed) public {
        if (depositers.length == 0) return;
        address sender = depositers[depositersSeed % depositers.length];
        (uint256 totalRonMinted, uint256 totalCollateralValueUSD) = ronEngine.getAccountInfo(sender);
        int256 maxRonToMint = (int256(totalCollateralValueUSD) * 60 / 100) - int256(totalRonMinted);
        if (maxRonToMint <= 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxRonToMint));
        if (amount == 0) {
            return;
        }
        vm.prank(sender);
        ronEngine.mintRon(amount);
        mintTimesCalled++;
    }

    function redeemCollateral(uint256 amountCollateral, uint256 depositersSeed) public {
        if (depositers.length == 0) return;
        ERC20Mock collateral;
        address sender = depositers[depositersSeed % depositers.length];
        if (ronEngine.getCollateralDeposited(sender, address(weth)) > 0) {
            collateral = ERC20Mock(ronEngine.getCollateralTokens()[0]);
        } else {
            collateral = ERC20Mock(ronEngine.getCollateralTokens()[1]);
        }
        uint256 maxCollateral = ronEngine.getMaxAvailableToRedeem(sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateral);
        if (amountCollateral == 0) {
            return;
        }
        vm.prank(sender);
        ronEngine.redeemCollateral(address(collateral), amountCollateral);
    }

    function burnRon(uint256 amountRon, uint256 depositersSeed) public {
        if (depositers.length == 0) return;
        address sender = depositers[depositersSeed % depositers.length];
        // Must burn more than 0
        amountRon = bound(amountRon, 0, ron.balanceOf(sender));
        if (amountRon == 0) {
            return;
        }
        vm.startPrank(sender);
        ron.approve(address(ronEngine), amountRon);
        ronEngine.burnRon(amountRon);
        vm.stopPrank();
    }

    function liquidate(uint256 collateralSeed, address userToBeLiquidated, uint256 debtToCover) public {
        uint256 minHealthFactor = ronEngine.getMinHealthFactor();
        uint256 userHealthFactor = ronEngine.getHealthFactor(userToBeLiquidated);
        if (userHealthFactor >= minHealthFactor) {
            return;
        }
        debtToCover = bound(debtToCover, 1, uint256(type(uint96).max));
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        ronEngine.liquidate(address(collateral), userToBeLiquidated, debtToCover);
    }

    /////////////////////////////
    // DecentralizedStableCoin //
    /////////////////////////////
    function transferRon(uint256 amountRon, address to) public {
        if (to == address(0)) {
            to = address(1);
        }
        amountRon = bound(amountRon, 0, ron.balanceOf(msg.sender));
        vm.prank(msg.sender);
        ron.transfer(to, amountRon);
    }

    ////////////////
    // Aggregator //
    ////////////////

    function updateCollateralPrice(uint256 randomNumber, uint256 collateralSeed) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        MockV3Aggregator priceFeed = MockV3Aggregator(ronEngine.getPriceFeed(address(collateral)));

        // Get current price from the price feed
        int256 currentPrice = priceFeed.latestAnswer();

        // Generate a random percentage change between 5% to 15%
        uint256 randomPercentageChange = randomNumber % 10 + 6;

        // Calculate the new price
        int256 newPriceInt = currentPrice - (currentPrice * int256(randomPercentageChange) / 100);

        // Update the price feed with the new price
        priceFeed.updateAnswer(newPriceInt);

        //Now we need to check, if it is more than 25% down, we should call liquidateUsersIfPriceTanks
        if (MockV3Aggregator(ronEngine.getPriceFeed(address(weth))).latestAnswer() < (INITIAL_WETH_PRICE * 75 / 100)) {
            _liquidateUsersIfPriceTanks(address(weth));
        }
        if (MockV3Aggregator(ronEngine.getPriceFeed(address(wbtc))).latestAnswer() < (INITIAL_WBTC_PRICE * 75 / 100)) {
            _liquidateUsersIfPriceTanks(address(wbtc));
        }
    }

    //////////////////////
    // Helper Functions //
    //////////////////////

    function _getCollateralFromSeed(uint256 seed) private view returns (ERC20Mock) {
        if (seed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }

    function _liquidateUsersIfPriceTanks(address token) private {
        for (uint256 i = 0; i < depositers.length; i++) {
            if (ronEngine.getHealthFactor(depositers[i]) < 1) {
                vm.startPrank(mainLiquidator);
                ronEngine.liquidate(token, depositers[i], ronEngine.getRONMinted(depositers[i]));
            }
        }
    }
}
