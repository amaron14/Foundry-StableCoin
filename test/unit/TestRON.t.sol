// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployRON} from "../../script/DeployRON.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {RONEngine} from "../../src/RONEngine.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract TestRon is Test {
    DecentralizedStableCoin ron;
    RONEngine ronEngine;
    HelperConfig config;
    address wethPriceFeed;
    address wbtcPriceFeed;
    address weth;
    address wbtc;
    ERC20Mock wethMock;
    address public USER = makeAddr("user");
    address[6] users;
    MockV3Aggregator priceFeed;
    int256 constant BREAKER = 2000e8;

    function setUp() public {
        DeployRON deployer = new DeployRON();
        (ron, ronEngine, config) = deployer.run();
        (wethPriceFeed, wbtcPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        wethMock = ERC20Mock(weth);
        wethMock.mint(USER, 10e18);
        wethMock.mint(address(this), 50e18);
        users[0] = makeAddr("user0");
        users[1] = makeAddr("user1");
        users[2] = makeAddr("user2");
        users[3] = makeAddr("user3");
        users[4] = makeAddr("user4");
        users[5] = makeAddr("user5");
        priceFeed = MockV3Aggregator(wethPriceFeed);
    }

    // depositCollateral

    function testRevertsIfCollateral0() public {
        vm.prank(USER);
        vm.expectRevert(RONEngine.RONEngine__AmountMustBeMoreThanZero.selector);
        ronEngine.depositCollateral(weth, 0);
    }

    function testCollateralUpdated() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 1e18);
        ronEngine.depositCollateral(weth, 1e18);
        uint256 expectedValue = 4000e18;
        uint256 collateralValue = ronEngine.getAccountCollateralValue(USER);
        vm.stopPrank();
        vm.assertEq(expectedValue, collateralValue);
    }

    function testRevertsIfUnapprovedToken() public {
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(ronEngine), 0, 1e18)
        );
        ronEngine.depositCollateral(weth, 1e18);
    }

    function testRevertsIfNonAllowedToken() public {
        vm.prank(USER);
        address randomToken = address(0xDEADBEEF);
        vm.expectRevert(RONEngine.RONEngine__TokenCantBeCollaterarlized.selector);
        ronEngine.depositCollateral(randomToken, 1e18);
    }

    function testMultipleDeposits() public {
        uint256 deposit1 = 1e18;
        uint256 deposit2 = 2e18;
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), type(uint256).max);
        ronEngine.depositCollateral(weth, deposit1);
        ronEngine.depositCollateral(weth, deposit2);
        uint256 expectedValue = deposit1 + deposit2;
        uint256 collateralValue = ronEngine.getCollateralDeposited(USER, address(weth));
        vm.stopPrank();
        vm.assertEq(expectedValue, collateralValue);
    }

    function testMultipleUsersDepositCollateral() public {
        for (uint256 i = 0; i < users.length; i++) {
            wethMock.mint(users[i], 10e18);
            vm.startPrank(users[i]);
            wethMock.approve(address(ronEngine), 1e18);
            ronEngine.depositCollateral(weth, 1e18);
            vm.stopPrank();
        }
    }

    function testDepositCollateralWhileMintingRon() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 2e18);
        uint256 depositAmount = 1e18;
        ronEngine.depositCollateral(weth, depositAmount);

        // Mint some RON
        uint256 mintAmount = 1000e18;
        ronEngine.mintRon(mintAmount);

        // Deposit additional collateral while minting is ongoing
        uint256 additionalDeposit = 1e18;
        ronEngine.depositCollateral(weth, additionalDeposit);

        uint256 expectedCollateral = depositAmount + additionalDeposit;
        uint256 actualCollateral = ronEngine.getCollateralDeposited(USER, address(weth));
        vm.stopPrank();
        vm.assertEq(expectedCollateral, actualCollateral);
    }

    // redeemCollateral

    // Test if revert when insufficient collateral
    function testRevertsIfInsufficientCollateral() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 1e18);
        ronEngine.depositCollateral(weth, 1e18);
        vm.expectRevert();
        ronEngine.redeemCollateral(weth, 2e18);
        vm.stopPrank();
    }

    function testRevertsIfTryingToRedeemTooMuchCollateral() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 1e18);
        ronEngine.depositCollateral(weth, 1e18);
        ronEngine.mintRon(2000e18);
        vm.expectRevert(abi.encodeWithSelector(RONEngine.RONEngine__BreaksMaxCollateralMintRatioAllowed.selector, 0));
        //vm.expectRevert(RONEngine.RONEngine__BreaksMaxCollateralMintRatioAllowed.selector);
        ronEngine.redeemCollateral(weth, 0.2 ether);
        vm.stopPrank();
    }

    function testRevertsIfRedeemZeroCollateral() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 1e18);
        ronEngine.depositCollateral(weth, 1e18);
        vm.expectRevert(abi.encodeWithSelector(RONEngine.RONEngine__AmountMustBeMoreThanZero.selector));
        ronEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    // Test partial redemption
    function testPartialRedemption() public {
        uint256 depositAmount = 1e18;
        uint256 redeemAmount = 0.5 ether;
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), depositAmount);
        ronEngine.depositCollateral(weth, depositAmount);
        ronEngine.redeemCollateral(weth, redeemAmount);
        uint256 expectedCollateral = depositAmount - redeemAmount;
        uint256 actualCollateral = ronEngine.getCollateralDeposited(USER, address(weth));
        vm.stopPrank();
        vm.assertEq(expectedCollateral, actualCollateral);
    }

    function testRedeemNonDepositedToken() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 1e18);
        ronEngine.depositCollateral(weth, 1e18);
        address anotherToken = wbtc; // Assuming wbtc is not deposited
        vm.expectRevert();
        ronEngine.redeemCollateral(anotherToken, 0.1 ether);
        vm.stopPrank();
    }

    function testRedeemCollateralForZeroRon() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 1e18);
        ronEngine.depositCollateral(weth, 1e18);
        //vm.expectRevert(abi.encodeWithSelector(RONEngine.RONEngine__AmountMustBeMoreThanZero.selector));
        ronEngine.redeemCollateralForRon(weth, 1e18, 0);
        vm.stopPrank();
    }

    // mintRon

    function testCantMintRonIfHealthFactorIsBroken() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 1e18);
        ronEngine.depositCollateral(weth, 1e18);
        vm.expectRevert(abi.encodeWithSelector(RONEngine.RONEngine__BreaksMaxCollateralMintRatioAllowed.selector, 0));
        ronEngine.mintRon(2401e18); // SHOULD REVERT - ETH PRICE IS 4,000$, 60% IS 2,400
        //(uint256 totalRonMinted, uint256 totalCollateralValueUSD) = ronEngine._getAccountInfo(USER);
        vm.stopPrank();
    }

    function testRevertsIfMintZeroRon() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 1e18);
        ronEngine.depositCollateral(weth, 1e18);
        vm.expectRevert(abi.encodeWithSelector(RONEngine.RONEngine__AmountMustBeMoreThanZero.selector));
        ronEngine.mintRon(0);
        vm.stopPrank();
    }

    function testMintRon() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 1e18);
        ronEngine.depositCollateral(weth, 1e18);
        uint256 mintAmount = 2400e18; // 2400 IS EXACTLY 60%
        ronEngine.mintRon(mintAmount);
        uint256 expectedTotalRonMinted = ron.totalSupply();
        uint256 actualTotalRonMinted = ron.balanceOf(USER);
        vm.stopPrank();
        vm.assertEq(expectedTotalRonMinted, actualTotalRonMinted);
    }

    function testMintRonAfterRedeemingSomeCollateral() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 2e18);
        uint256 depositAmount = 1e18;
        ronEngine.depositCollateral(weth, depositAmount);
        uint256 redeemAmount = 0.5 ether;
        ronEngine.redeemCollateral(weth, redeemAmount);
        uint256 mintAmount = 500e18;
        ronEngine.mintRon(mintAmount);
        uint256 expectedCollateralValue = depositAmount - redeemAmount;
        uint256 actualCollateralValue = ronEngine.getCollateralDeposited(USER, address(weth));
        vm.stopPrank();
        vm.assertEq(expectedCollateralValue, actualCollateralValue);
    }

    function testMultipleMintsBySameUser() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 2e18);
        ronEngine.depositCollateral(weth, 1e18);
        uint256 firstMintAmount = 500e18;
        ronEngine.mintRon(firstMintAmount);
        uint256 secondMintAmount = 700e18;
        ronEngine.mintRon(secondMintAmount);
        uint256 expectedTotalRonMinted = firstMintAmount + secondMintAmount;
        uint256 actualTotalRonMinted = ron.balanceOf(USER);
        vm.stopPrank();
        vm.assertEq(expectedTotalRonMinted, actualTotalRonMinted);
    }

    function testMintRonByMultipleUsers() public {
        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            wethMock.mint(users[i], 1e18);
            wethMock.approve(address(ronEngine), 1e18);
            ronEngine.depositCollateral(weth, 1e18);
            ronEngine.mintRon(500e18);
            vm.stopPrank();
        }

        uint256 expectedTotalMintedRons = users.length * 500e18;
        uint256 actualTotalMintedRons = ron.totalSupply();
        vm.assertEq(expectedTotalMintedRons, actualTotalMintedRons);
    }

    // burnRon

    function testRevertsIfBurnZeroRon() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 1e18);
        ronEngine.depositCollateral(weth, 1e18);
        uint256 mintAmount = 1000e18;
        ronEngine.mintRon(mintAmount);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmountMustBeGreaterThanZero.selector);
        ronEngine.burnRon(0);
        vm.stopPrank();
    }

    function testBurnRon() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 2e18);
        ronEngine.depositCollateral(weth, 1e18);
        uint256 mintAmount = 1000e18;
        ronEngine.mintRon(mintAmount);
        ron.approve(address(ronEngine), 500e18);
        uint256 burnAmount = 500e18;
        ronEngine.burnRon(burnAmount);

        uint256 expectedTotalRon = ron.totalSupply();
        vm.stopPrank();
        vm.assertEq(ronEngine.getRONMinted(USER), expectedTotalRon);
    }

    function testBurnRonWithInsufficientBalance() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 1e18);
        ronEngine.depositCollateral(weth, 1e18);
        uint256 mintAmount = 500e18;
        ronEngine.mintRon(mintAmount);
        vm.expectRevert();
        ronEngine.burnRon(501e18); // Trying to burn more than minted
        vm.stopPrank();
    }

    // liquidate

    function testLiquidationRevertsIfHealthFactorAboveThreshold() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 2e18);
        uint256 depositAmount = 1e18;
        ronEngine.depositCollateral(weth, depositAmount);
        uint256 mintAmount = 2400e18; // Mint amount that maintains healthy health factor
        ronEngine.mintRon(mintAmount);
        address liquidator = address(this);
        wethMock.approve(liquidator, depositAmount);
        //priceFeed.updateAnswer(2000e8);
        vm.expectRevert(abi.encodeWithSelector(RONEngine.RONEngine__HealthFactorIsGood.selector));
        ronEngine.liquidate(address(weth), USER, 1000e18);
        vm.stopPrank();
    }

    // reedemAllCollateralForAllRon

    function testRedeemAllCollateralForAllRonNotRevertIfEmpty() public {
        vm.startPrank(USER);
        ronEngine.redeemAllCollateralForAllRon();
        vm.stopPrank();
    }

    function testRedeemAllCollateralForAllRon() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 2e18);
        uint256 depositAmount = 1e18;
        ronEngine.depositCollateral(weth, depositAmount);
        uint256 mintAmount = 500e18;
        ronEngine.mintRon(mintAmount);
        uint256 expectedCollateralRedeemed = depositAmount;
        ron.approve(address(ronEngine), 500e18);
        uint256 balanceBefore = ERC20Mock(weth).balanceOf(USER);
        ronEngine.redeemAllCollateralForAllRon();
        uint256 balanceAfter = ERC20Mock(weth).balanceOf(USER);
        uint256 actualCollateralRedeemed = balanceAfter - balanceBefore;
        vm.stopPrank();
        vm.assertEq(expectedCollateralRedeemed, actualCollateralRedeemed);
        vm.assertEq(ron.balanceOf(USER), 0); // All Ron should be burned
    }

    function testRedeemAllCollateralFor0Ron() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 2e18);
        uint256 depositAmount = 1e18;
        ronEngine.depositCollateral(weth, depositAmount);
        uint256 expectedCollateralRedeemed = depositAmount;
        uint256 balanceBefore = ERC20Mock(weth).balanceOf(USER);
        ronEngine.redeemAllCollateralForAllRon();
        uint256 balanceAfter = ERC20Mock(weth).balanceOf(USER);
        uint256 actualCollateralRedeemed = balanceAfter - balanceBefore;
        vm.stopPrank();
        vm.assertEq(expectedCollateralRedeemed, actualCollateralRedeemed);
        vm.assertEq(ron.balanceOf(USER), 0); // All Ron should be burned
    }

    function testRedeemAllCollateralForAllRonWithSomeCollateralAlreadyRedeemed() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 2e18);
        uint256 depositAmount = 1e18;
        ronEngine.depositCollateral(weth, depositAmount);
        uint256 mintAmount = 500e18;
        ronEngine.mintRon(mintAmount);
        uint256 expectedCollateralRedeemed = depositAmount;
        ron.approve(address(ronEngine), 500e18);
        uint256 balanceBefore = ERC20Mock(weth).balanceOf(USER);
        ronEngine.redeemCollateral(weth, 0.1 ether);
        ronEngine.redeemAllCollateralForAllRon();
        uint256 balanceAfter = ERC20Mock(weth).balanceOf(USER);
        uint256 actualCollateralRedeemed = balanceAfter - balanceBefore;
        vm.stopPrank();
        vm.assertEq(expectedCollateralRedeemed, actualCollateralRedeemed);
        vm.assertEq(ron.balanceOf(USER), 0); // All Ron should be burned
    }

    //////////////////////////////////////////////////
    // BREAKING FACTORS FUNCTIONS (-50% collateral) //
    //////////////////////////////////////////////////

    /* 
    1. can't mint more Ron when max factor broken */
    function testCantMintMoreRonAfterPriceTanks() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 1e18);
        ronEngine.depositCollateral(weth, 1e18);
        uint256 mintAmount = 1200e18; // MAX after price tanks
        ronEngine.mintRon(mintAmount);
        vm.stopPrank();
        priceFeed.updateAnswer(BREAKER);
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(RONEngine.RONEngine__BreaksMaxCollateralMintRatioAllowed.selector, 0));
        ronEngine.mintRon(1200e18);
    }

    // 2. can't claim if max factor broken.
    function testRevertsIfTryingToRedeemAfterPriceTanks() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 1e18);
        ronEngine.depositCollateral(weth, 1e18);
        ronEngine.mintRon(1000e18);
        priceFeed.updateAnswer(BREAKER);
        vm.expectRevert(abi.encodeWithSelector(RONEngine.RONEngine__BreaksMaxCollateralMintRatioAllowed.selector, 0));
        ronEngine.redeemCollateral(weth, 0.2 ether);
        vm.stopPrank();
    }

    // 3. can liquidate if health factor is broken.
    function testLiquidation() public {
        vm.startPrank(USER);
        wethMock.approve(address(ronEngine), 2e18);
        uint256 depositAmount = 1e18;
        ronEngine.depositCollateral(weth, depositAmount);
        uint256 mintAmount = 1600e18; // Mint amount that maintains healthy health factor
        ronEngine.mintRon(mintAmount);
        vm.stopPrank();
        // now starting to prank as this contract
        vm.startPrank(address(this));
        wethMock.approve(address(ronEngine), 10e18);
        uint256 depositAmount2 = 10e18;
        ronEngine.depositCollateral(weth, depositAmount2);
        uint256 mintAmount2 = 5000e18; // Mint amount that maintains healthy health factor
        ronEngine.mintRon(mintAmount2);
        ron.approve(address(ronEngine), mintAmount2);
        priceFeed.updateAnswer(2000e8);
        uint256 balanceBefore = wethMock.balanceOf(address(this));
        ronEngine.liquidate(address(weth), USER, mintAmount);
        vm.stopPrank();
        uint256 balanceAfter = wethMock.balanceOf(address(this));
        vm.assertEq((balanceAfter - balanceBefore), 0.88 ether); // (1600 / 2000) is 0.8 + 10% it's 0.88
    }

    // others

    function testGetUsdPrice() public view {
        uint256 ethAmount = 2e18;
        uint256 expectedValue = 8000e18;
        uint256 ethUsdValue = ronEngine.getUsdValue(weth, ethAmount);
        vm.assertEq(ethUsdValue, expectedValue);
    }

    function testGetAmountTokenUsd() public view {
        uint256 expectedValue = 0.11 ether;
        uint256 tokenAmount = ronEngine.getTokenAmountFromUsd(weth, 400e18);
        console.log(expectedValue);
        console.log(tokenAmount * 110 / 100);
        vm.assertEq(expectedValue, tokenAmount * 110 / 100);
    }
}
