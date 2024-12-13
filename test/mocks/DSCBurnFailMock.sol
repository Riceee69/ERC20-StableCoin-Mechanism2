//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DSCBurnFailMock is ERC20Burnable, Ownable {
    error DecentralisedStableCoin__AmountMoreThanBalance();
    error DecentralisedStableCoin__ZeroAmount();
    error DecentralisedStableCoin__InvalidAddress();

    constructor(address initialOwner) ERC20("DecentralisedStableCoin", "DSC") Ownable(initialOwner) {}

    function burnToken(uint256 _amount) public onlyOwner returns (bool) {
        if (_amount <= 0) {
            revert DecentralisedStableCoin__ZeroAmount();
        }
        if (_amount > balanceOf(msg.sender)) {
            revert DecentralisedStableCoin__AmountMoreThanBalance();
        }

        super.burn(_amount);
        return false; //burn failed mock
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_amount <= 0) {
            revert DecentralisedStableCoin__ZeroAmount();
        }
        if (_to == address(0)) {
            revert DecentralisedStableCoin__InvalidAddress();
        }

        _mint(_to, _amount);
        return true;
    }
}
