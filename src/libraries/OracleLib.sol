//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// import {console} from "forge-std/Test.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {DSCEngine} from "../DSCEngine.sol";

library OracleLib {
    error OracleLib__stalePrice();

    uint256 public constant TIMEOUT = 2 hours;

    function staleCheckOnLatestRoundCall(AggregatorV3Interface dataFeed) public view returns(uint80, int, uint, uint, uint80) {
            (
                uint80 roundID,
                int answer,
                uint startedAt,
                uint updatedAt,
                uint80 answeredInRound
            ) = dataFeed.latestRoundData();

            //stale and sanity check
            if(block.timestamp - updatedAt > TIMEOUT ||  updatedAt == 0) {
            //console.log(block.timestamp - updatedAt, TIMEOUT);
            //reverting makes the contract opeartions closed as long as the Oracle is down so we should implement fallback Oracle 
            //it is not implemented here 
            revert OracleLib__stalePrice();
        }

        return (roundID, answer, startedAt, updatedAt, answeredInRound);
    }
}