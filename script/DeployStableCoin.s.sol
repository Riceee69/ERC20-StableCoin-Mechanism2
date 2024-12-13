//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {DecentralisedStableCoin} from "../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployStableCoin is Script {
    address[] public priceFeedAddresses;
    address[] public tokenAddresses;

    function run() public returns (DecentralisedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        (address wBtcPriceFeed, address wEthPriceFeed, address wEth, address wBtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();

        priceFeedAddresses = [wBtcPriceFeed, wEthPriceFeed];
        tokenAddresses = [wBtc, wEth];

        vm.startBroadcast(deployerKey);

        DecentralisedStableCoin dsc = new DecentralisedStableCoin(msg.sender);
        DSCEngine dscEngine = new DSCEngine(address(dsc), priceFeedAddresses, tokenAddresses);

        //dsc.transferOwnership(address(dscEngine));

        vm.stopBroadcast();

        return (dsc, dscEngine, helperConfig);
    }
}
