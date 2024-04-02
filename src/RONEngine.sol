// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title RONEngine
 * @author amaron
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our RON system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the RON.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming RON, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract RONEngine is ReentrancyGuard {
    //////////////////
    // Errors       //
    //////////////////

    error RONEngine__AmountMustBeMoreThanZero();
    error RONEngine__TokenCantBeCollaterarlized();
    error RONEngine__DifferentLengthes();
    error RONEngine__TransferFailed();
    error RONEngine__BreaksHealthFactor(uint256 healthFactor);
    error RONEngine__BreaksMaxCollateralMintRatioAllowed(uint256 maxCollateralMintRatioFactor);
    error RONEngine__MintFailed();
    error RONEngine__CantBurnMoreThanMinted();
    error RONEngine__HealthFactorIsGood();
    error RONEngine__UserHealthFactorStillBroken();

    //////////////////////////
    // Types                //
    //////////////////////////

    using OracleLib for AggregatorV3Interface;

    //////////////////////////
    // State Variables      //
    //////////////////////////

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountMinted) private s_RONMinted;
    DecentralizedStableCoin private immutable i_ron;
    address[] private s_collateralTokens;
    uint256 private constant MAX_COLLATERAL_MINT_RATIO = 60; // one can always mint total RON of max 60% of his total collateral value deposited;
    uint256 private constant LIQUIDATION_TRESHOLD = 75; // one should always have his total RON issued less than 75% of his total collateral value otherwise he can get liquidated.
    uint256 private constant LIQUIDATION_BONUS = 10; // bonus for liquidating is 10%
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    //////////////////
    // Events       //
    //////////////////

    event collateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event collateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);
    event ronMinted(address indexed user, uint256 indexed amount);

    //////////////////
    // Modifiers    //
    //////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert RONEngine__AmountMustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert RONEngine__TokenCantBeCollaterarlized();
        }
        _;
    }

    // Constructor

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address ronAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert RONEngine__DifferentLengthes();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_ron = DecentralizedStableCoin(ronAddress);
    }

    ///////////////////////////
    // External Functions    //
    ///////////////////////////

    /**
     * @dev Deposit collateral and mint RON tokens.
     * @param tokenCollateralAddress The token address of the collateral.
     * @param amountCollateral The amount of tokens to deposit as collateral.
     * @param amountToMint The amount of RON tokens to mint.
     * Emits a {CollateralDeposited} event.
     * If `amountToMint` is greater than 0, RON tokens will be minted based on the deposited collateral.
     * It's essential to check the health factor afterward to avoid liquidation risk.
     */
    function depositCollateralAndMintRon(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountToMint)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        _depositCollateral(msg.sender, tokenCollateralAddress, amountCollateral);
        if (amountToMint > 0) {
            _mintRon(msg.sender, amountToMint);
        }
        _revertIfMaxFactorIsBroken(msg.sender);
    }

    /**
     * @param tokenCollateralAddress the token address of the collateral
     * @param amountCollateral the amount of tokens to deposit as collateral
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        _depositCollateral(msg.sender, tokenCollateralAddress, amountCollateral);
    }

    /**
     * @param tokenCollateralAddress The ERC20 token address of the collateral you're depositing
     * @param amountCollateral The amount of collateral you're depositing
     * @param amountRonToBurn The amount of DSC you want to burn
     * @notice This function will withdraw your collateral and burn DSC in one transaction
     */
    function redeemCollateralForRon(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountRonToBurn)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        if (amountRonToBurn > 0) {
            _burnRon(msg.sender, msg.sender, amountRonToBurn);
        }
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfMaxFactorIsBroken(msg.sender);
    }

    /**
     * @dev Redeem all collateral for RON tokens.
     * Emits {CollateralRedeemed} events.
     * If the user has any RON tokens minted, they will be burned before redeeming collateral.
     * Ensure the health factor is healthy after redemption to avoid liquidation.
     */
    function redeemAllCollateralForAllRon() external nonReentrant {
        if (s_RONMinted[msg.sender] > 0) {
            _burnRon(msg.sender, msg.sender, s_RONMinted[msg.sender]);
        }
        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[msg.sender][token];
            if (amount > 0) {
                _redeemCollateral(msg.sender, msg.sender, token, amount);
            }
        }
        _revertIfMaxFactorIsBroken(msg.sender); //should never hit
    }

    /**
     * @dev Redeem collateral.
     * @param tokenCollateralAddress The ERC20 token address of the collateral.
     * @param amountToRedeem The amount of collateral to redeem.
     * Emits a {CollateralRedeemed} event.
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountToRedeem)
        external
        moreThanZero(amountToRedeem)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountToRedeem);
        _revertIfMaxFactorIsBroken(msg.sender);
    }

    /**
     * @dev Mint RON tokens.
     * @param amountToMint The amount of RON tokens to mint.
     * Emits a {RonMinted} event.
     */
    function mintRon(uint256 amountToMint) external moreThanZero(amountToMint) nonReentrant {
        _mintRon(msg.sender, amountToMint);
        _revertIfMaxFactorIsBroken(msg.sender);
    }

    /**
     * @notice careful! You'll burn your RON here! Make sure you want to do this...
     * @dev you might want to use this if you're nervous you might get liquidated and want to just burn
     * your RON but keep your collateral in.
     */
    function burnRon(uint256 amountToBurn) external nonReentrant {
        _burnRon(msg.sender, msg.sender, amountToBurn);
    }

    /**
     * @dev Liquidate a user's position.
     * @param tokenCollateralAddress The ERC20 token address of the collateral.
     * @param user The address of the user to liquidate.
     * @param debtToCover The amount of debt to cover.
     * Emits {CollateralRedeemed} and {RonBurned} events.
     * Before liquidation, it checks if the user's health factor is below the minimum threshold.
     * It burns RON tokens from the user and redeems collateral, potentially receiving a bonus.
     * After liquidation, it ensures the user's health factor is restored to a safe level.
     */
    function liquidate(address tokenCollateralAddress, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert RONEngine__HealthFactorIsGood();
        }
        uint256 tokenAndBonus =
            (getTokenAmountFromUsd(tokenCollateralAddress, debtToCover) * (100 + LIQUIDATION_BONUS)) / 100;
        _burnRon(user, msg.sender, debtToCover);
        _redeemCollateral(user, msg.sender, tokenCollateralAddress, tokenAndBonus);
        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor < MIN_HEALTH_FACTOR) {
            revert RONEngine__UserHealthFactorStillBroken();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /////////////////////////////////////
    // Internal / Private Functions    //
    /////////////////////////////////////

    function _burnRon(address onBehalfOf, address burner, uint256 amountToBurn) private {
        s_RONMinted[onBehalfOf] -= amountToBurn;
        i_ron.burnFrom(burner, amountToBurn);
    }

    function _mintRon(address user, uint256 amountToMint) private {
        s_RONMinted[user] += amountToMint;
        emit ronMinted(user, amountToMint);
        bool minted = i_ron.mint(user, amountToMint);
        if (!minted) {
            revert RONEngine__MintFailed();
        }
    }

    function _depositCollateral(address user, address tokenCollateralAddress, uint256 amountCollateral) private {
        s_collateralDeposited[user][tokenCollateralAddress] += amountCollateral;
        emit collateralDeposited(user, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(user, address(this), amountCollateral);
        if (!success) {
            revert RONEngine__TransferFailed();
        }
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountToRedeem)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountToRedeem;
        emit collateralRedeemed(from, to, tokenCollateralAddress, amountToRedeem);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountToRedeem);
        if (!success) {
            revert RONEngine__TransferFailed();
        }
    }

    function _getAccountInfo(address user)
        private
        view
        returns (uint256 totalRonMinted, uint256 collateralValueInUsd)
    {
        totalRonMinted = s_RONMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalRonMinted, uint256 totalCollateralValueUSD) = _getAccountInfo(user);
        if (totalRonMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForTreshold = (totalCollateralValueUSD * LIQUIDATION_TRESHOLD) / 100;
        return ((collateralAdjustedForTreshold) / totalRonMinted);
    }

    function _maxCollateralMintRatioFactor(address user) private view returns (uint256) {
        (uint256 totalRonMinted, uint256 totalCollateralValueUSD) = _getAccountInfo(user);
        if (totalRonMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForTreshold = (totalCollateralValueUSD * MAX_COLLATERAL_MINT_RATIO) / 100;
        return ((collateralAdjustedForTreshold) / totalRonMinted);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert RONEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _revertIfMaxFactorIsBroken(address user) internal view {
        uint256 userMaxCollateralMintRatioFactor = _maxCollateralMintRatioFactor(user);
        if (userMaxCollateralMintRatioFactor < MIN_HEALTH_FACTOR) {
            revert RONEngine__BreaksMaxCollateralMintRatioAllowed(userMaxCollateralMintRatioFactor);
        }
    }

    /////////////////////////////////////
    // GET Functions                   //
    /////////////////////////////////////

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((uint256(price) * 1e10) * amount) / 1e18;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (usdAmount * 1e18 / (uint256(price) * 1e10));
    }

    function getMaxAvailableToRedeem(address user, address token) public view returns (uint256) {
        (uint256 totalRonMinted, uint256 collateralValueInUsd) = _getAccountInfo(user);
        uint256 maxAvailable = (collateralValueInUsd - (totalRonMinted * 5 / 3));
        if (
            getTokenAmountFromUsd(token, maxAvailable)
                > getTokenAmountFromUsd(token, getCollateralDeposited(user, token))
        ) {
            return getTokenAmountFromUsd(token, getCollateralDeposited(user, token));
        }
        return getTokenAmountFromUsd(token, maxAvailable);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getMaxCollateralMintRatioFactor(address user) external view returns (uint256) {
        return _maxCollateralMintRatioFactor(user);
    }

    function getAccountInfo(address user)
        external
        view
        returns (uint256 totalRonMinted, uint256 collateralValueInUsd)
    {
        (totalRonMinted, collateralValueInUsd) = _getAccountInfo(user);
    }

    // Mapping to get price feed for a token
    function getPriceFeed(address _token) public view returns (address) {
        return s_priceFeeds[_token];
    }

    // Mapping to get collateral amount deposited by a user for a token
    function getCollateralDeposited(address _user, address _token) public view returns (uint256) {
        return s_collateralDeposited[_user][_token];
    }

    // Mapping to get the amount of RON minted by a user
    function getRONMinted(address _user) public view returns (uint256) {
        return s_RONMinted[_user];
    }

    // Get the immutable DecentralizedStableCoin address
    function getRONAddress() public view returns (address) {
        return address(i_ron);
    }

    // Get the array of collateral tokens
    function getCollateralTokens() public view returns (address[] memory) {
        return s_collateralTokens;
    }

    // Get the liquidation threshold
    function getLiquidationThreshold() public pure returns (uint256) {
        return LIQUIDATION_TRESHOLD;
    }

    // Get the liquidation bonus
    function getLiquidationBonus() public pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    // Get the minimum health factor
    function getMinHealthFactor() public pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    // Get the maximum value
    function getMaxCollateralMintRatio() public pure returns (uint256) {
        return MAX_COLLATERAL_MINT_RATIO;
    }
}
