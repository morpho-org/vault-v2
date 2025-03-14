// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {ConstantsLib} from "./libraries/ConstantsLib.sol";

import {VaultV2} from "./VaultV2.sol";
import {IVaultV2Factory} from "./interfaces/IVaultV2Factory.sol";

contract VaultV2Factory is IVaultV2Factory {
    address public owner;
    uint96 public protocolFee;
    address public protocolFeeRecipient;
    mapping(address => bool) public isVaultV2;

    constructor(address _owner) {
        require(_owner != address(0), ErrorsLib.ZeroAddress());

        owner = _owner;
    }

    // This function will be de facto timelocked because owner should be timelocked.
    function setOwner(address newOwner) external {
        require(msg.sender == owner, ErrorsLib.Unauthorized());
        owner = newOwner;
    }

    // This function will be de facto timelocked because owner should be timelocked.
    function setProtocolFee(uint96 newProtocolFee, address newProtocolFeeRecipient) external {
        require(msg.sender == owner, ErrorsLib.Unauthorized());
        require(newProtocolFee < ConstantsLib.WAD, ErrorsLib.FeeTooHigh());
        protocolFee = newProtocolFee;
        protocolFeeRecipient = newProtocolFeeRecipient;
    }

    function createVaultV2(address _owner, address _curator, address _asset, string memory _name, string memory _symbol)
        external
        returns (address)
    {
        address vaultV2 = address(new VaultV2{salt: 0}(address(this), _owner, _curator, _asset, _name, _symbol));

        isVaultV2[vaultV2] = true;

        return vaultV2;
    }
}
