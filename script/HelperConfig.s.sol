//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract HelperConfig is Script {
    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    struct NetworkConfig {
        address wBtcPriceFeed;
        address wEthPriceFeed;
        address wEth;
        address wBtc;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaDeploymentInfo();
        } else {
            activeNetworkConfig = setAndGetAnvilDeploymentInfo();
        }
    }

    function getSepoliaDeploymentInfo() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wBtcPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            wEthPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wEth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wBtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function setAndGetAnvilDeploymentInfo() public returns (NetworkConfig memory) {
        // Check to see if we set an active network config
        if (activeNetworkConfig.wBtcPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();

        ERC20Mock wBtcMock = new ERC20Mock();
        ERC20Mock wEthMock = new ERC20Mock();
        MockV3Aggregator wBtcPriceFeed = new MockV3Aggregator(8, 2000e8);
        MockV3Aggregator wEthPriceFeed = new MockV3Aggregator(8, 1000e8);

        wBtcMock.mint(msg.sender, 1000e18);
        wEthMock.mint(msg.sender, 2000e18);

        vm.stopBroadcast();

        return NetworkConfig({
            wBtcPriceFeed: address(wBtcPriceFeed),
            wEthPriceFeed: address(wEthPriceFeed),
            wEth: address(wEthMock),
            wBtc: address(wBtcMock),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }
}
