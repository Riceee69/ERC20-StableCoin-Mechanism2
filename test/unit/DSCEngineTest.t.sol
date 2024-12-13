//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {DeployStableCoin} from "../../script/DeployStableCoin.s.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {DSCMintFailMock} from "../mocks/DSCMintFailMock.sol";
import {DSCBurnFailMock} from "../mocks/DSCBurnFailMock.sol";
import {DSCTransferFailMock} from "../mocks/DSCTransferFailMock.sol";
import {MockERC20TransferFail} from "../mocks/MockERC20TransferFail.sol";
import {MockERC20TransferFromFail} from "../mocks/MockERC20TransferFromFail.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";


contract DSCEngineTest is Test {
    DecentralisedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    DeployStableCoin deployStableCoin;

    address wEth;
    address wBtc;
    address wEthPriceFeed;
    address wBtcPriceFeed;
    address[] priceFeedAddresses;
    address[] tokenAddresses;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant COLLATERAL_ETH_AMOUNT = 5 ether;
    uint256 public constant LIQUIDATOR_COLLATERAL_ETH_AMOUNT = 10 ether;
    uint256 public constant REDEEM_ETH_AMOUNT = 4 ether;
    uint256 public constant MINT_DSC_AMOUNT = 1000 ether;
    uint256 public constant BURN_DSC_AMOUNT = 500 ether;
    int256 public constant ETH_CRASH_PRICE = 300e8;
    uint256  constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant PRECISION = 1e18;

    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATOR_BONUS = 10; //10%

    event CollateralDeposited(address indexed from, address indexed tokenAddress, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed tokenAddress, uint256 amount);
    event DSCMinted(address indexed to, uint256 amount);
    event DSCBurned(address indexed from, address indexed by, uint256 amount);

    ////////////////////////////
    // setup                 //
    ///////////////////////////
    function setUp() public {
        deployStableCoin = new DeployStableCoin();

        (dsc, dscEngine, helperConfig) = deployStableCoin.run();
        dsc.transferOwnership(address(dscEngine));

        (wBtcPriceFeed, wEthPriceFeed, wEth, wBtc,) = helperConfig.activeNetworkConfig();

        ERC20Mock(wEth).mint(USER, COLLATERAL_ETH_AMOUNT);
    }

    ////////////////////////////
    // constructor tests     //
    ///////////////////////////
    function testPriceFeedAddressesLengthEqualtoTokenAddressesLength() public {
        priceFeedAddresses = [wEthPriceFeed, wBtcPriceFeed];
        tokenAddresses = [wEth];
        vm.expectRevert(DSCEngine.DSCEngine__UnequalDataInputs.selector);
        new DSCEngine(address(dsc), priceFeedAddresses, tokenAddresses);
    }

    /////////////////////////////
    // price feed tests       //
    ////////////////////////////
    function testGetTotalCollateralValue() public {
        uint256 initialBTC = 10 ether;
        ERC20Mock(wBtc).mint(USER, initialBTC);

        uint256 ethAmount = 5e18;
        uint256 btcAmount = 10e18;

        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(dscEngine), COLLATERAL_ETH_AMOUNT);
        ERC20Mock(wBtc).approve(address(dscEngine), initialBTC);

        dscEngine.depositCollateral(wEth, ethAmount);
        dscEngine.depositCollateral(wBtc, btcAmount);
        vm.stopPrank();

        //at 1000$ per eth and 2000$ per btc
        uint256 expectedCollateralValue = 25000e18;
        uint256 actualCollateralValue = dscEngine.getTotalCollateralValue(USER);

        assertEq(actualCollateralValue, expectedCollateralValue);
    }

    function testGetAmountInUsd() public view {
        uint256 ethAmount = 5e18;
        uint256 expectedAmountInUsd = 5000e18;
        uint256 actualAmountInUsd = dscEngine.getAmountInUsd(wEth, ethAmount);
        assertEq(actualAmountInUsd, expectedAmountInUsd);
    }

    function testGetAmountInToken() public view {
        uint256 usdAmount = 5000e18;
        uint256 expectedAmountInToken = 5e18;
        uint256 actualAmountInToken = dscEngine.getAmountInToken(wEth, usdAmount);
        assertEq(actualAmountInToken, expectedAmountInToken);
    }

    ////////////////////////////////////
    // depositCollateral tests        //
    ///////////////////////////////////
    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(dscEngine), COLLATERAL_ETH_AMOUNT);
        dscEngine.depositCollateral(wEth, COLLATERAL_ETH_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testRevertIfZeroCollateralValue() public {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(dscEngine), COLLATERAL_ETH_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(wEth, 0);
        vm.stopPrank();
    }

    function testMustBeAllowedTokenAddress() public {
        ERC20Mock randomToken = new ERC20Mock();

        vm.startPrank(USER);

        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedAddress.selector);
        dscEngine.depositCollateral(address(randomToken), COLLATERAL_ETH_AMOUNT);

        vm.stopPrank();
    }

    function testEmitDepositCollateral() public {
        vm.startPrank(USER);

        ERC20Mock(wEth).approve(address(dscEngine), COLLATERAL_ETH_AMOUNT);
        vm.expectEmit(true, true, false, true);
        emit CollateralDeposited(USER, wEth, COLLATERAL_ETH_AMOUNT);
        dscEngine.depositCollateral(wEth, COLLATERAL_ETH_AMOUNT);

        vm.stopPrank();
    }

    function testUpdateUserCollateralState() public depositCollateral {
        assertEq(dscEngine.s_userCollateral(USER, wEth), COLLATERAL_ETH_AMOUNT);
    }

    function testRevertIfCollateralTransferFromFails() public {
        //setup
        MockERC20TransferFromFail mockERC20 = new MockERC20TransferFromFail();
        MockV3Aggregator mockERC20PriceFeed = new MockV3Aggregator(8, 1000e8);
        priceFeedAddresses = [address(mockERC20PriceFeed)];
        tokenAddresses = [address(mockERC20)];
        DSCEngine mockDSCEngine = new DSCEngine(address(dsc), priceFeedAddresses, tokenAddresses);

        vm.startPrank(USER);
        mockERC20.mint(USER, COLLATERAL_ETH_AMOUNT);
        mockERC20.approve(address(mockDSCEngine), COLLATERAL_ETH_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDSCEngine.depositCollateral(address(mockERC20), COLLATERAL_ETH_AMOUNT);
        vm.stopPrank();
    }

    ////////////////////////////////////
    // mint and user info tests       //
    ////////////////////////////////////
    function testRevertIfMintAmountZero() public {
        vm.startPrank(USER);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.mintDSC(0);

        vm.stopPrank();
    }

    function testUpdateUserDSCBalanceStateAndGetUserInfo() public depositCollateral {
        vm.startPrank(USER);
        dscEngine.mintDSC(MINT_DSC_AMOUNT);
        assertEq(dscEngine.s_DSCMinted(USER), MINT_DSC_AMOUNT);
        assertEq(dsc.balanceOf(USER), MINT_DSC_AMOUNT);
        (uint256 dscBalance, uint256 collateralValue) = dscEngine.getUserInfo(USER);
        assertEq(dscBalance, MINT_DSC_AMOUNT);
        assertEq(collateralValue, dscEngine.getTotalCollateralValue(USER));
        vm.stopPrank();
    }

    function testEmitMintDSC() public depositCollateral {
        vm.expectEmit(true, false, false, true);
        emit DSCMinted(USER, MINT_DSC_AMOUNT);

        vm.prank(USER);
        dscEngine.mintDSC(MINT_DSC_AMOUNT);
    }

    function testRevertIfHealthFactorTooLowOnMint() public {
        uint256 MINT_DSC_AMOUNT_2 = 5000 ether; //to break healh factor check
        vm.startPrank(USER);

        ERC20Mock(wEth).approve(address(dscEngine), COLLATERAL_ETH_AMOUNT);
        dscEngine.depositCollateral(wEth, COLLATERAL_ETH_AMOUNT);

        uint256 healthFactor = dscEngine.checkHealthFactor(
            MINT_DSC_AMOUNT_2, dscEngine.getAmountInUsd(wEth, COLLATERAL_ETH_AMOUNT)
        );

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorTooLow.selector, healthFactor));
        dscEngine.mintDSC(MINT_DSC_AMOUNT_2);

        vm.stopPrank();
    }

    function testRevertIfMintFails() public {
        //setup for this test
        priceFeedAddresses = [wEthPriceFeed, wBtcPriceFeed];
        tokenAddresses = [wEth, wBtc];
        DSCMintFailMock mockDSC = new DSCMintFailMock(address(this));
        DSCEngine mockDSCEngine = new DSCEngine(address(mockDSC), priceFeedAddresses, tokenAddresses);
        mockDSC.transferOwnership(address(mockDSCEngine));

        vm.startPrank(USER);

        ERC20Mock(wEth).approve(address(mockDSCEngine), COLLATERAL_ETH_AMOUNT);
        mockDSCEngine.depositCollateral(wEth, COLLATERAL_ETH_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDSCEngine.mintDSC(MINT_DSC_AMOUNT);

        vm.stopPrank();
    }

    ////////////////////////////////////
    // getHealthFactor tests          //
    ////////////////////////////////////
    function testGetHealthFactorIfNoDSCMinted() public depositCollateral {
        uint256 expectedHealthFactor = type(uint256).max;
        uint256 actualHealthFactor = dscEngine.getHealthFactor(USER);
        assertEq(actualHealthFactor, expectedHealthFactor);
    }

    ////////////////////////////////////
    // burn tests                     //
    ////////////////////////////////////
    modifier depositCollateralAndMintDSC() {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(dscEngine), COLLATERAL_ETH_AMOUNT);
        dscEngine.depositCollateralToMintDSC(wEth, COLLATERAL_ETH_AMOUNT, MINT_DSC_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testRevertIfZeroBurnAmount() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.burnDSC(0);
        vm.stopPrank();
    }

    function testRevertIfBurnAmountMoreThanDSCBalance() public {
        vm.startPrank(USER);
        vm.expectRevert();
        dscEngine.burnDSC(MINT_DSC_AMOUNT);
        vm.stopPrank();
    }

    function testUpdateUserDSCBalanceStateAndEmitBurnEvent() public depositCollateralAndMintDSC {
        vm.prank(USER);
        dsc.approve(address(dscEngine), BURN_DSC_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit DSCBurned(USER, USER, BURN_DSC_AMOUNT);

        vm.prank(USER);
        dscEngine.burnDSC(BURN_DSC_AMOUNT);
        assertEq(dsc.balanceOf(USER), MINT_DSC_AMOUNT - BURN_DSC_AMOUNT);
        assertEq(dscEngine.s_DSCMinted(USER), MINT_DSC_AMOUNT - BURN_DSC_AMOUNT);
    }

    function testRevertIfDSCTransferFails() public {
        priceFeedAddresses = [wEthPriceFeed, wBtcPriceFeed];
        tokenAddresses = [wEth, wBtc];
        DSCTransferFailMock mockDSC = new DSCTransferFailMock(address(this));
        DSCEngine mockDSCEngine = new DSCEngine(address(mockDSC), priceFeedAddresses, tokenAddresses);
        mockDSC.transferOwnership(address(mockDSCEngine));

        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(mockDSCEngine), COLLATERAL_ETH_AMOUNT);
        mockDSCEngine.depositCollateralToMintDSC(wEth, COLLATERAL_ETH_AMOUNT, MINT_DSC_AMOUNT);
        mockDSC.approve(address(mockDSCEngine), BURN_DSC_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDSCEngine.burnDSC(BURN_DSC_AMOUNT);
        vm.stopPrank();
    }

    function testRevertIfBurnFails() public {
        priceFeedAddresses = [wEthPriceFeed, wBtcPriceFeed];
        tokenAddresses = [wEth, wBtc];
        DSCBurnFailMock mockDSC = new DSCBurnFailMock(address(this));
        DSCEngine mockDSCEngine = new DSCEngine(address(mockDSC), priceFeedAddresses, tokenAddresses);
        mockDSC.transferOwnership(address(mockDSCEngine));

        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(mockDSCEngine), COLLATERAL_ETH_AMOUNT);
        mockDSCEngine.depositCollateralToMintDSC(wEth, COLLATERAL_ETH_AMOUNT, MINT_DSC_AMOUNT);
        mockDSC.approve(address(mockDSCEngine), BURN_DSC_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__BurnFailed.selector);
        mockDSCEngine.burnDSC(BURN_DSC_AMOUNT);
        vm.stopPrank();
    }

    ////////////////////////////////////
    // redeem tests                   //
    ////////////////////////////////////
    function testRevertIfZeroRedeemAmount() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.redeemCollateral(wEth, 0);
        vm.stopPrank();
    }

    function testRevertIfWrongTokenAddress() public {
        ERC20Mock randomToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedAddress.selector);
        dscEngine.redeemCollateral(address(randomToken), COLLATERAL_ETH_AMOUNT);
        vm.stopPrank();
    }

    function testUpdateUserCollateralStateAndEmitRedeemEvent() public depositCollateral {
        vm.expectEmit(true, true, true, true);
        emit CollateralRedeemed(USER, USER, wEth,REDEEM_ETH_AMOUNT);
        vm.prank(USER);
        dscEngine.redeemCollateral(wEth, REDEEM_ETH_AMOUNT);
        assertEq(dscEngine.s_userCollateral(USER, wEth), COLLATERAL_ETH_AMOUNT - REDEEM_ETH_AMOUNT);
    }

    function testRevertIfHealthFactorTooLowOnRedeem() public depositCollateralAndMintDSC{
        vm.startPrank(USER);
        uint256 userHealthFactor = dscEngine.checkHealthFactor(MINT_DSC_AMOUNT, dscEngine.getAmountInUsd(wEth, 
        COLLATERAL_ETH_AMOUNT - REDEEM_ETH_AMOUNT));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorTooLow.selector, userHealthFactor));
        dscEngine.redeemCollateral(wEth, REDEEM_ETH_AMOUNT);
        vm.stopPrank();
    }

    function testRevertIfRedeemTransferFails() public {
        //setup
        MockERC20TransferFail mockERC20 = new MockERC20TransferFail();
        MockV3Aggregator mockERC20PriceFeed = new MockV3Aggregator(8, 1000e8);
        priceFeedAddresses = [address(mockERC20PriceFeed)];
        tokenAddresses = [address(mockERC20)];
        DSCEngine mockDSCEngine = new DSCEngine(address(dsc), priceFeedAddresses, tokenAddresses);

        vm.startPrank(USER);
        mockERC20.mint(USER, COLLATERAL_ETH_AMOUNT);
        mockERC20.approve(address(mockDSCEngine), COLLATERAL_ETH_AMOUNT);
        mockDSCEngine.depositCollateral(address(mockERC20), COLLATERAL_ETH_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDSCEngine.redeemCollateral(address(mockERC20), REDEEM_ETH_AMOUNT);
        vm.stopPrank();
    }

    ////////////////////////////////////
    // liquidate tests                //
    ////////////////////////////////////
    modifier liquidated {
        vm.startPrank(USER);

        ERC20Mock(wEth).approve(address(dscEngine), COLLATERAL_ETH_AMOUNT);
        dscEngine.depositCollateralToMintDSC(wEth, COLLATERAL_ETH_AMOUNT, MINT_DSC_AMOUNT);
        dsc.approve(address(dscEngine), MINT_DSC_AMOUNT);

        vm.stopPrank();
        
        MockV3Aggregator(wEthPriceFeed).updateAnswer(ETH_CRASH_PRICE);

        vm.startPrank(LIQUIDATOR);

        ERC20Mock(wEth).mint(LIQUIDATOR, LIQUIDATOR_COLLATERAL_ETH_AMOUNT);
        ERC20Mock(wEth).approve(address(dscEngine), LIQUIDATOR_COLLATERAL_ETH_AMOUNT);
        dscEngine.depositCollateralToMintDSC(wEth, LIQUIDATOR_COLLATERAL_ETH_AMOUNT, MINT_DSC_AMOUNT);
        dsc.approve(address(dscEngine), MINT_DSC_AMOUNT);
        dscEngine.liquidate(wEth, USER, MINT_DSC_AMOUNT);

        vm.stopPrank();
        _;
    }

    function testRevertIfZeroDebtToCover() public {
        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.liquidate(wEth,USER, 0);
        vm.stopPrank();
    }

    function testRevertIfUserHealthFactorOk() public depositCollateralAndMintDSC {
        vm.prank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dscEngine.liquidate(wEth, USER, MINT_DSC_AMOUNT);
    }

    function testRevertIfUserHealthFactorUnimproved() public depositCollateralAndMintDSC {
        //Liquidator tokens minted after changing ETH price to ensure his health factor remains ok
        uint256 debtToCover = 500e18;
        vm.prank(USER);
        dsc.approve(address(dscEngine), MINT_DSC_AMOUNT);

        MockV3Aggregator(wEthPriceFeed).updateAnswer(ETH_CRASH_PRICE);

        vm.startPrank(LIQUIDATOR);

        ERC20Mock(wEth).mint(LIQUIDATOR, LIQUIDATOR_COLLATERAL_ETH_AMOUNT);
        ERC20Mock(wEth).approve(address(dscEngine), LIQUIDATOR_COLLATERAL_ETH_AMOUNT);
        dscEngine.depositCollateralToMintDSC(wEth, LIQUIDATOR_COLLATERAL_ETH_AMOUNT, MINT_DSC_AMOUNT);
        dsc.approve(address(dscEngine), MINT_DSC_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorDidNotImprove.selector);
        dscEngine.liquidate(wEth, USER, debtToCover);

        vm.stopPrank();
    }

    function testTotalRewardCollateralReceivedAndUserRemainingCollateral() public liquidated {
        uint256 receivedReward = ERC20Mock(wEth).balanceOf(LIQUIDATOR);
        uint256 expectedReward = (dscEngine.getAmountInToken(wEth, MINT_DSC_AMOUNT) / dscEngine.getLiquidationBonus()) + dscEngine.getAmountInToken(wEth, MINT_DSC_AMOUNT);
        assertEq(expectedReward, receivedReward);
        uint256 expectedUserCollateral =  COLLATERAL_ETH_AMOUNT - receivedReward;
        uint256 actualUserCollateral = dscEngine.s_userCollateral(USER, wEth);
        assertEq(expectedUserCollateral, actualUserCollateral);
    }

    function testUserAndLiquidatorDSCBalanceStates() public liquidated{
        uint256 userDSCBalance = dsc.balanceOf(USER);
        uint256 liquidatorDSCBalance = dsc.balanceOf(LIQUIDATOR);
        assertEq(userDSCBalance, dscEngine.s_DSCMinted(USER));
        assertEq(liquidatorDSCBalance, dscEngine.s_DSCMinted(LIQUIDATOR));
    }

    ////////////////////////////////////
    // helper function tests          //
    ////////////////////////////////////    
    function testGetPriceFeedPrecision() public view {
        uint256 expectedPriceFeedPrecision = 1e10;
        uint256 actualPriceFeedPrecision = dscEngine.getPriceFeedPrecision();
        assertEq(actualPriceFeedPrecision, expectedPriceFeedPrecision);
    }

    function testGetPrecision() public view {
        uint256 expectedPrecision = 1e18;
        uint256 actualPrecision = dscEngine.getPrecision();
        assertEq(actualPrecision, expectedPrecision);
    }

    function testGetMinHealthFactor() public view {
        uint256 expectedMinHealthFactor = 1e18;
        uint256 actualMinHealthFactor = dscEngine.getMinHealthFactor();
        assertEq(actualMinHealthFactor, expectedMinHealthFactor);
    }

    function testGetLiquidationThreshold() public view {
        uint256 expectedLiquidationThreshold = 50;
        uint256 actualLiquidationThreshold = dscEngine.getLiquidationThreshold();
        assertEq(actualLiquidationThreshold, expectedLiquidationThreshold);
    }

    function testGetLiquidationBonus() public view {
        uint256 expectedLiquidationBonus = 10;
        uint256 actualLiquidationBonus = dscEngine.getLiquidationBonus();
        assertEq(actualLiquidationBonus, expectedLiquidationBonus);
    }

    function testGetTokenAddresses() public {
    tokenAddresses = [wBtc, wEth];
    address[] memory actualTokenAddresses = dscEngine.getTokenAddresses();
    assertEq(actualTokenAddresses, tokenAddresses);
    }

    function testGetHealthFactor() public depositCollateralAndMintDSC{
        uint256 expectedHealthFactor = 2.5e18;
        uint256 actualHealthFactor = dscEngine.getHealthFactor(USER);
        assertEq(actualHealthFactor, expectedHealthFactor);
    }
}
