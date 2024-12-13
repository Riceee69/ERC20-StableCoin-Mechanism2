//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployStableCoin} from "../../../script/DeployStableCoin.s.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {DecentralisedStableCoin} from "../../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Handler} from "./Handler.t.sol";

contract Invariant is StdInvariant, Test {

/**
 * control flow of invariant testing: setUp() => invariant_protocolMustHaveMoreCollateralThanDSC() => Handler function(s) invariant fuzzing => //invariant_protocolMustHaveMoreCollateralThanDSC()... so on.
 */

    DeployStableCoin deployer;
    HelperConfig config;
    DecentralisedStableCoin dsc;
    DSCEngine dscEngine;
    address wBtcPriceFeed;
    address wEthPriceFeed;
    address wEth;
    address wBtc;
    Handler handler;

    address USER = makeAddr("user");

    function setUp() public {
        deployer = new DeployStableCoin();
        (dsc, dscEngine, config) = deployer.run();
        (wBtcPriceFeed, wEthPriceFeed, wEth, wBtc,) = config.activeNetworkConfig();
        dsc.transferOwnership(address(dscEngine));

        handler = new Handler(dscEngine);

        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreCollateralThanDSC() public view {
        uint256 totalDSCSupply = dsc.totalSupply();
        uint256 totalWethDeposited = ERC20Mock(wEth).balanceOf(address(dscEngine));
        uint256 totalWbtcDepsited = ERC20Mock(wBtc).balanceOf(address(dscEngine));

        uint256 totalWethValue = dscEngine.getAmountInUsd(wEth, totalWethDeposited);
        uint256 totalWbtcValue = dscEngine.getAmountInUsd(wBtc, totalWbtcDepsited);
        console.log("totalWethValue: ", totalWethValue);
        console.log("totalWbtcValue: ", totalWbtcValue);
        console.log("totalDSCSupply: ", totalDSCSupply);
        console.log("Mint Called: ", handler.timesMintFunctionIsCalled());
        console.log("Deposit Called: ", handler.timesDepositFunctionIsCalled());
        console.log("Redeem Called: ", handler.timesRedeemFunctionIsCalled());
        assert(totalWethValue + totalWbtcValue >= totalDSCSupply);
    }

    function invariant_protocolGettersShouldNotRevert() public view {
        dscEngine.getCollateralBalance(wEth, USER);
        dscEngine.getCollateralBalance(wBtc, USER);
        dscEngine.getTotalCollateralValue(USER);
        dscEngine.getAmountInUsd(wEth, 3e18);
        dscEngine.getAmountInToken(wBtc, 5000e18);
        dscEngine.getHealthFactor(USER);
        dscEngine.getLiquidationBonus();
        dscEngine.getTokenAddresses();
        dscEngine.getUserInfo(USER);
        dscEngine.getLiquidationThreshold();
        dscEngine.getMinHealthFactor();
        dscEngine.getPrecision();
        dscEngine.getPriceFeedPrecision();
    }
}