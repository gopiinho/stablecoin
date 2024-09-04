// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC20Burnable, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @author  https://github.com/gopiinho
 * @title   StableCoin
 * @notice  his is a ERC20 implementation of a decentralized stablecoin meant to be governed the the
 * DSCEngine.sol
 * contract
 */
contract StableCoin is ERC20Burnable, Ownable {
    error StableCoin__MustBeMoreThanZero();
    error StableCoin__NotEnoughBalanceToBurn();
    error StableCoin__NotAddressZero();

    constructor() ERC20("StableCoin", "DSC") Ownable(msg.sender) { }

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert StableCoin__MustBeMoreThanZero();
        }
        if (_amount > balance) {
            revert StableCoin__NotEnoughBalanceToBurn();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert StableCoin__NotAddressZero();
        }
        if (_amount <= 0) {
            revert StableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
