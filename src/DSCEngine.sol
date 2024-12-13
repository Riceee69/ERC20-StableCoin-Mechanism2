//SPDX-License-Identifier: MIT

/**
 * @title Decentralised Stable Coin Engine
 * @author Arish
 * @notice This is the contract that will implement the entire mechanics of our Stable Coin Collateralisation System.
 * The collateral can be wETH or wBTC.
 *
 */
pragma solidity ^0.8.0;

import {DecentralisedStableCoin} from "./DecentralisedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
// import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract DSCEngine {
    ///////////////////////
    // Error Codes       //
    ///////////////////////
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__UnequalDataInputs();
    error DSCEngine__NotAllowedAddress();
    error DSCEngine__TransferFailed();
    error DSCEngine__DSCValueGreaterThanCollateralValue();
    error DSCEngine__HealthFactorTooLow(uint256 userHealthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__BurnFailed();
    error DSCEngine__RedeemAmountGreaterThanCollateral();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorDidNotImprove();
    error DSCEngine__EmergencyFreeze();
    error DSCEngine__Insolvent();
    // error DSCEngine__PriceAnomalyDetected();

    ///////////////////////
    // Types             //
    ///////////////////////    
    using OracleLib for AggregatorV3Interface;

    ///////////////////////
    // State Variables   //
    ///////////////////////
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant PRICE_FEED_PRECISION = 1e10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATOR_BONUS = 10; //10%
    // uint256 private constant MAX_PERCENTAGE_PRICE_CHANGE = 40; //40%


    DecentralisedStableCoin public immutable i_DSCToken;

    mapping(address token => address priceFeed) public s_priceFeed;
    mapping(address user => mapping(address token => uint256 collateralAmount)) public s_userCollateral;
    mapping(address user => uint256 dscMinted) public s_DSCMinted;
    // mapping(address token => uint256 lastPrice) s_lastPriceOfToken;
    address[] public s_tokenAddresses;



    ///////////////////////
    // Events            //
    //////////////////////
    event CollateralDeposited(address indexed from, address indexed tokenAddress, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed tokenAddress, uint256 amount);
    event DSCMinted(address indexed to, uint256 amount);
    event DSCBurned(address indexed from, address indexed by, uint256 amount);

    ///////////////////////
    // Modifiers         //
    ///////////////////////
    modifier mustBeMoreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier mustBeAllowedTokenAddress(address tokenAddress) {
        if (s_priceFeed[tokenAddress] == address(0)) {
            revert DSCEngine__NotAllowedAddress();
        }
        _;
    }

    ///////////////////////
    // Functions         //
    ///////////////////////
    constructor(
        address _DSCTokenContractAddress,
        address[] memory _priceFeedAddresses,
        address[] memory _tokenAddresses
    ) {
        if (_priceFeedAddresses.length != _tokenAddresses.length) {
            revert DSCEngine__UnequalDataInputs();
        }

        for (uint256 i = 0; i < _priceFeedAddresses.length; i++) {
            s_priceFeed[_tokenAddresses[i]] = _priceFeedAddresses[i];
            s_tokenAddresses.push(_tokenAddresses[i]);
            
            //initializing prices of tokens
            // AggregatorV3Interface _priceFeed = AggregatorV3Interface(_priceFeedAddresses[i]);
            // (, int256 price,,,) = _priceFeed.staleCheckOnLatestRoundCall();
            // s_lastPriceOfToken[_tokenAddresses[i]] = uint256(price);
        }

        i_DSCToken = DecentralisedStableCoin(_DSCTokenContractAddress);
    }

    ////////////////////////////////////////
    // External/Public Functions         //
    ///////////////////////////////////////

    /**
     * @dev To deposit collateral to mint DSC
     * @param tokenAddress: The address of the collateral token
     * @param amountCollateral: The amount of collateral to deposit
     * @param amountDSC: The amount of DSC to mint
     */
    function depositCollateralToMintDSC(address tokenAddress, uint256 amountCollateral, uint256 amountDSC) external {
        depositCollateral(tokenAddress, amountCollateral);
        mintDSC(amountDSC);
    }

    /**
     * @dev To deposit collateral
     * @param tokenAddress: The address of the collateral token
     * @param amountCollateral: The amount of collateral to deposit
     * @notice Follows CEI patterm
     */
    function depositCollateral(address tokenAddress, uint256 amountCollateral)
        public
        mustBeMoreThanZero(amountCollateral)
        mustBeAllowedTokenAddress(tokenAddress)
    {
        s_userCollateral[msg.sender][tokenAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenAddress, amountCollateral);

        //to initiate a transfer from user to contract for the tokenAddress
        bool success = IERC20(tokenAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @dev To redeem collateral for DSC
     * @param tokenAddress: The address of the collateral token
     * @param amountCollateral: The amount of collateral to redeem
     * @param amountDSC: The amount of DSC to mint
     */
    function redeemCollateralForDSC(address tokenAddress, uint256 amountCollateral, uint256 amountDSC) external {
        burnDSC(amountDSC);
        redeemCollateral(tokenAddress, amountCollateral);
    }

    function redeemCollateral(address tokenAddress, uint256 amountCollateral)
        public
        mustBeMoreThanZero(amountCollateral)
        mustBeAllowedTokenAddress(tokenAddress)
    {
        //check if user has enough collateral(solidity compiler does it for us)
        _redeemCollateral(msg.sender, msg.sender, tokenAddress, amountCollateral);
        //check if health factor doesnt get too low on withdrawing the collateral(check is done after transfer because this is more gas efficient)
        _revertIfHealthFactorTooLow(msg.sender);
    }

    /**
     * @dev To mint DSC
     * @param amountDSC: The amount of DSC to mint
     * @notice Follows CEI pattern
     */
    function mintDSC(uint256 amountDSC) public mustBeMoreThanZero(amountDSC) {
        s_DSCMinted[msg.sender] += amountDSC;
        emit DSCMinted(msg.sender, amountDSC);
        //Need to check collateral value > amountDSC
        _revertIfHealthFactorTooLow(msg.sender);

        bool success = i_DSCToken.mint(msg.sender, amountDSC);
        if (!success) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * @dev To burn DSC to save our position from getting liquidated or to redeem collateral
     */
    function burnDSC(uint256 amountDSC) public mustBeMoreThanZero(amountDSC) {
        _burnDSC(msg.sender, msg.sender, amountDSC);
    }

    /**
     * @dev To liquidate a position when the Collateral Price gets way too close to the $DSC they hold, so that the position doesn't get under collateralized.
     * @param collateralTokenAddress: The address of the collateral token
     * @param user: The address of the user
     * @param debtToCover: The amount of $DSC to be burned
     */
    function liquidate(address collateralTokenAddress, address user, uint256 debtToCover)
        external
        mustBeMoreThanZero(debtToCover)
        mustBeAllowedTokenAddress(collateralTokenAddress)
    {
        uint256 startingUserHealthFactor = _getHealthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        //check how much erc20 token the liquidator gets as reward for burning the DSC
        uint256 valueInToken = _getAmountInToken(collateralTokenAddress, debtToCover);
        uint256 rewardCollateral = (valueInToken * LIQUIDATOR_BONUS) / 100;
        uint256 totalRewardCollateral = valueInToken + rewardCollateral;

        //burn the DSC of the user and transfer the reward collateral to the liquidator
        _redeemCollateral(user, msg.sender, collateralTokenAddress, totalRewardCollateral);
        _burnDSC(user, msg.sender, debtToCover);//burns both user and liquidator DSC 

        // finally check if health factor is ok now for both user and liquidator
        uint256 endingUserHealthFactor = _getHealthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor || endingUserHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorDidNotImprove();
        }

        _revertIfHealthFactorTooLow(msg.sender);
    }

    /**
     * @dev To get how Healthy a position is from being liquidated
     */
    function getHealthFactor(address user) external view returns (uint256) {
        return _getHealthFactor(user);
    }

    /////////////////////////////////////////////
    // Private Functions                       //
    /////////////////////////////////////////////
    function _redeemCollateral(address from, address to, address tokenAddress, uint256 amountCollateral) private {
        s_userCollateral[from][tokenAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenAddress, amountCollateral);

        bool success = IERC20(tokenAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _burnDSC(address from, address by, uint256 amountDSC) private {
        s_DSCMinted[from] -= amountDSC;
        emit DSCBurned(from, by, amountDSC);

        bool success = i_DSCToken.transferFrom(by, address(this), amountDSC);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        success = i_DSCToken.burnToken(amountDSC);
        if (!success) {
            revert DSCEngine__BurnFailed();
        }

        if (from != by) {
        s_DSCMinted[by] -= amountDSC;

        success = i_DSCToken.transferFrom(from, address(this), amountDSC);
            if (!success) {
                revert DSCEngine__TransferFailed();
            }

            success = i_DSCToken.burnToken(amountDSC);
            if (!success) {
                revert DSCEngine__BurnFailed();
            }           
        }
    }

    /**
     * @dev To check for price anomalies (sudden high price deviation) then freeze certain 
     * functions.
     */
    // function _pauseIfPriceChangeAnamoly(uint256 currentPrice, address tokenAddress) private {
    //     uint256 lastPrice = s_lastPriceOfToken[tokenAddress];
    //     uint256 percentageChange;

    //     if(currentPrice > lastPrice) {
    //         percentageChange = ((currentPrice - lastPrice) * 100) / lastPrice;
    //     } else {
    //         percentageChange = ((lastPrice - currentPrice) * 100) / lastPrice;
    //     }

    //     if(percentageChange > MAX_PERCENTAGE_PRICE_CHANGE) {
    //         _pause();
    //         revert DSCEngine__PriceAnomalyDetected();
    //     }

    //     s_lastPriceOfToken[tokenAddress] = currentPrice;
    // }

    /////////////////////////////////////////////
    // Public View Functions                   //
    /////////////////////////////////////////////
    function getTotalCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {
        //Need to convert wETH and wBTC to USD and add them
        for (uint256 i = 0; i < s_tokenAddresses.length; i++) {
            uint256 amount = s_userCollateral[user][s_tokenAddresses[i]];
            totalCollateralValueInUSD += _getAmountInUsd(s_tokenAddresses[i], amount);
        }
    }

    function getUserInfo(address user) public view returns (uint256 dscValue, uint256 collateralValue) {
        dscValue = s_DSCMinted[user];
        collateralValue = getTotalCollateralValue(user);
    }

    //////////////////////////////////////////////////////
    // Helper Public/External View Functions            //
    //////////////////////////////////////////////////////
    function checkHealthFactor(uint256 dscValue, uint256 collateralValue)
        public
        pure
        returns (uint256 userHealthFactor)
    {
        return _checkHealthFactor(dscValue, collateralValue);
    }

    function getAmountInUsd(address tokenAddress, uint256 amount) public view returns (uint256 amountInUSD) {
        return _getAmountInUsd(tokenAddress, amount);
    }

    function getAmountInToken(address tokenAddress, uint256 amountInUSD) public view returns (uint256 amountInToken) {
        return _getAmountInToken(tokenAddress, amountInUSD);
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATOR_BONUS;
    }

    function getTokenAddresses() external view returns (address[] memory) {
        return s_tokenAddresses;
    }

    function getCollateralBalance(address tokenAddress, address user) public view returns (uint256) {
        return s_userCollateral[user][tokenAddress];
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getPriceFeedPrecision() external pure returns (uint256) {
        return PRICE_FEED_PRECISION;
    }
    /////////////////////////////////////////////
    // Private/Internal View Functions         //
    /////////////////////////////////////////////
    function _getAmountInUsd(address tokenAddress, uint256 amount) private view returns (uint256 amountInUSD) {
        AggregatorV3Interface dataFeed = AggregatorV3Interface(s_priceFeed[tokenAddress]);
        (, int256 price,,,) = dataFeed.staleCheckOnLatestRoundCall();
        //_pauseIfPriceChangeAnamoly(uint256(price), tokenAddress);

        //price is in 1e8 decimals and amount is in 1e18 decimals
        amountInUSD = (uint256(price) * PRICE_FEED_PRECISION * amount) / PRECISION;
    }

    function _getHealthFactor(address user) private view returns (uint256 userHealthFactor) {
        //Needs collateral value and DSC value
        (uint256 dscValue, uint256 collateralValue) = getUserInfo(user);

        if (dscValue == 0) {
            return type(uint256).max;
        }

        return _checkHealthFactor(dscValue, collateralValue);
    }

    function _checkHealthFactor(uint256 dscValue, uint256 collateralValue)
        private
        pure
        returns (uint256 userHealthFactor)
    {
        uint256 adjustedCollateralValue = collateralValue * LIQUIDATION_THRESHOLD / 100;
        userHealthFactor = adjustedCollateralValue * PRECISION / dscValue;
    }

    function _revertIfHealthFactorTooLow(address user) private view {
        uint256 userHealthFactor = _getHealthFactor(user);

        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorTooLow(userHealthFactor);
        }
    }

    function _getAmountInToken(address tokenAddress, uint256 amountInUSD)
        private
        view
        returns (uint256 amountInToken)
    {
        AggregatorV3Interface dataFeed = AggregatorV3Interface(s_priceFeed[tokenAddress]);
        (, int256 price,,,) = dataFeed.staleCheckOnLatestRoundCall();
        //_pauseIfPriceChangeAnamoly(uint256(price), tokenAddress);
        amountInToken = (amountInUSD * PRECISION) / (uint256(price) * PRICE_FEED_PRECISION);
    }
}
