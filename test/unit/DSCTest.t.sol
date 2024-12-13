//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";

contract DSCTest is Test {
    DecentralisedStableCoin dsc;
    uint256 constant MINT_DSC_AMOUNT = 1000 ether;
    
    function setUp() public {
        dsc = new DecentralisedStableCoin(address(this));
    }

    //////////////////////////////
    // Mint tests              //
    /////////////////////////////
    function testRevertIfMintAmountIsZero() public {
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin__ZeroAmount.selector);
        //vm.prank(address(this));
        dsc.mint(address(this), 0);
    }

    function testRevertIfMintAddressIsZero() public {
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin__InvalidAddress.selector);
        dsc.mint(address(0), MINT_DSC_AMOUNT);
    }

    //////////////////////////////
    // Burn tests              //
    /////////////////////////////    
    function testRevertIfBurnAmountIsZero() public {
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin__ZeroAmount.selector);
        dsc.burnToken(0);
    }

    function testReverIfBurnAmountMoreThanBalance() public {
        dsc.mint(address(this), MINT_DSC_AMOUNT);
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin__AmountMoreThanBalance.selector);
        dsc.burnToken(MINT_DSC_AMOUNT + 1);
    }
}