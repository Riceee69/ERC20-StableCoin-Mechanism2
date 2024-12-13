//to handle the sequence of function calls in stateful fuzzing

//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine dscEngine;

    ERC20Mock wEth;
    ERC20Mock wBtc;

    mapping (address user => bool) InitialCollateralDeposited;
    address[] usersWithDepositedCollateral;

    uint256 public timesMintFunctionIsCalled;
    uint256 public timesDepositFunctionIsCalled;
    uint256 public timesRedeemFunctionIsCalled;
    uint256 constant MAX_DEPOSIT_AMOUNT = type(uint96).max;

    constructor(DSCEngine _dscEngine) {
        dscEngine = _dscEngine;

        address[] memory tokenAddresses = dscEngine.getTokenAddresses();
        wEth = ERC20Mock(tokenAddresses[0]);
        wBtc = ERC20Mock(tokenAddresses[1]);

    }

//Mint DSC Handler
    function mintDSC(uint256 amountDSC, uint256 userSeed) public {
        vm.assume(usersWithDepositedCollateral.length > 0);

        address user = usersWithDepositedCollateral[userSeed % usersWithDepositedCollateral.length];
        uint256 totalCollateralValue = dscEngine.getTotalCollateralValue(user);
        uint256 userDscBalance = dscEngine.s_DSCMinted(user);

        int256 maxDSC = int256(totalCollateralValue) / 2 - int256(userDscBalance);
        vm.assume(maxDSC > 0);

        amountDSC = bound(amountDSC, 1, uint256(maxDSC));

        vm.prank(user);
        dscEngine.mintDSC(amountDSC);
        timesMintFunctionIsCalled++;
    }

    //Deposit Collateral Handler
    function depositCollateral(uint256 tokenSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getTokenFromSeed(tokenSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_AMOUNT);

        vm.startPrank(msg.sender);

        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);

        vm.stopPrank();

        if(!InitialCollateralDeposited[msg.sender]){
            usersWithDepositedCollateral.push(msg.sender);
            InitialCollateralDeposited[msg.sender] = true;
        }

        timesDepositFunctionIsCalled++;
    }

    //Redeem Collateral Handler
    function redeemCollateral(uint256 tokenSeed, uint256 amountCollateral, uint256 userSeed) public {
        vm.assume(usersWithDepositedCollateral.length > 0);

        address user = usersWithDepositedCollateral[userSeed % usersWithDepositedCollateral.length];
        ERC20Mock collateral = _getTokenFromSeed(tokenSeed);
        uint256 collateralBalance = dscEngine.getCollateralBalance(address(collateral), user);
        uint256 userDscBalance = dscEngine.s_DSCMinted(user);

        vm.assume(collateralBalance > 0);

        //checks if collateral has been depoisted in different token but redeeming in another token
        int256 maxCollateral = int256(collateralBalance) - (int256(userDscBalance) * 2);
        vm.assume(maxCollateral > 0);

        amountCollateral = bound(amountCollateral, 1, uint256(maxCollateral));
        vm.prank(user);
        dscEngine.redeemCollateral(address(collateral), amountCollateral);

        timesRedeemFunctionIsCalled++;        
    }

    ////////////////////////////
    // Helper Functions      //
    ///////////////////////////
    function _getTokenFromSeed(uint256 tokenSeed) private view returns (ERC20Mock) {
        if(tokenSeed % 2 == 0) return wEth;
        return wBtc;
    }
}