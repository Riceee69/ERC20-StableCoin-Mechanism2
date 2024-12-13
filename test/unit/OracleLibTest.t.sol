//SPDX-License-Identifier: MIT  

pragma solidity ^0.8.0;

import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {Test} from "forge-std/Test.sol";
import {OracleLib, AggregatorV3Interface} from "../../src/libraries/OracleLib.sol";

contract OracleLibTest is Test {
    using OracleLib for AggregatorV3Interface;
    MockV3Aggregator mockDataFeed;

    function setUp() public {
        mockDataFeed = new MockV3Aggregator(8, 1000);
    }

    function testRevertDueToTimeout() public {
        vm.warp(block.timestamp + 2 hours + 1 seconds);

        vm.expectRevert(OracleLib.OracleLib__stalePrice.selector);
        AggregatorV3Interface(address(mockDataFeed)).staleCheckOnLatestRoundCall();
    }

    function testRevertDueToUpdatedAtZero() public {
        mockDataFeed.updateRoundData(1, 1100, 0, 0);

        vm.expectRevert(OracleLib.OracleLib__stalePrice.selector);
        AggregatorV3Interface(address(mockDataFeed)).staleCheckOnLatestRoundCall();
    }
}