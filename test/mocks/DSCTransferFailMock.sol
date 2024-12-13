//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DSCTransferFailMock is ERC20Burnable, Ownable {
    error DecentralisedStableCoin__AmountMoreThanBalance();
    error DecentralisedStableCoin__ZeroAmount();
    error DecentralisedStableCoin__InvalidAddress();

    constructor(address initialOwner) ERC20("DecentralisedStableCoin", "DSC") Ownable(initialOwner) {}

    function burn(uint256 _amount) public override onlyOwner {
        if (_amount <= 0) {
            revert DecentralisedStableCoin__ZeroAmount();
        }
        if (_amount > balanceOf(msg.sender)) {
            revert DecentralisedStableCoin__AmountMoreThanBalance();
        }

        super.burn(_amount);
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

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return false;
    }
}
