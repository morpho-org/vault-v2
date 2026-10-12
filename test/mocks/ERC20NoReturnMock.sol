// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

contract ERC20NoReturnMock {
    uint8 private immutable _decimals;

    string public name = "no return token";
    string public symbol = "NORETURN";

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(uint8 __decimals) {
        _decimals = __decimals;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function _transfer(address _from, address _to, uint256 _amount) internal {
        balanceOf[_from] -= _amount;
        balanceOf[_to] += _amount;
    }

    function transfer(address _to, uint256 _amount) public {
        _transfer(msg.sender, _to, _amount);
    }

    function transferFrom(address _from, address _to, uint256 _amount) public {
        allowance[_from][msg.sender] -= _amount;
        _transfer(_from, _to, _amount);
    }

    function approve(address _spender, uint256 _amount) public {
        allowance[msg.sender][_spender] = _amount;
    }
}
