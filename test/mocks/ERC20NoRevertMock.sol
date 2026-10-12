// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

contract ERC20NoRevertMock {
    uint8 private immutable _decimals;

    string public name = "no revert token";
    string public symbol = "NOREVERT";

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(uint8 __decimals) {
        _decimals = __decimals;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function _transfer(address _from, address _to, uint256 _amount) internal returns (bool) {
        if (balanceOf[_from] < _amount) {
            return false;
        }
        balanceOf[_from] -= _amount;
        balanceOf[_to] += _amount;
        return true;
    }

    function transfer(address _to, uint256 _amount) public returns (bool) {
        return _transfer(msg.sender, _to, _amount);
    }

    function transferFrom(address _from, address _to, uint256 _amount) public returns (bool) {
        if (allowance[_from][msg.sender] < _amount) {
            return false;
        }
        allowance[_from][msg.sender] -= _amount;
        return _transfer(_from, _to, _amount);
    }

    function approve(address _spender, uint256 _amount) public returns (bool) {
        allowance[msg.sender][_spender] = _amount;
        return true;
    }
}
