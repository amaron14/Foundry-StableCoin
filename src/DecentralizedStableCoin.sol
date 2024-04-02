// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @author amaron
 * Collateral - Exogenous (ETH & BTC)
 * Minting - Algorithmic
 * Relative Stabillity - pegged to the usd
 *
 * This contract is meant to be controlled by ths RONEngine, this is only the erc20 implementation
 *
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__AmountMustBeGreaterThanZero();
    error DecentralizedStableCoin__BalanceMustBeGreaterThanOrEqualToAmount();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "RON") Ownable(msg.sender) {}

    function burnFrom(address user, uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(user);
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeGreaterThanZero();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin__BalanceMustBeGreaterThanOrEqualToAmount();
        }
        super.burnFrom(user, _amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeGreaterThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
