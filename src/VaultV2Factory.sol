// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import {WAD, MAX_PROTOCOL_FEE} from "./libraries/ConstantsLib.sol";

import {VaultV2} from "./VaultV2.sol";
import {IVaultV2Factory} from "./interfaces/IVaultV2Factory.sol";

contract VaultV2Factory is IVaultV2Factory {
    address public owner;
    address public protocolFeeRecipient;
    uint96 public protocolFee;
    mapping(address => bool) public isVaultV2;

    constructor(address _owner) {
        require(_owner != address(0), ErrorsLib.ZeroAddress());

        owner = _owner;
    }

    function setOwner(address newOwner) external {
        require(msg.sender == owner, ErrorsLib.Unauthorized());
        owner = newOwner;
    }

    function setProtocolFee(uint96 newProtocolFee) external {
        require(msg.sender == owner, ErrorsLib.Unauthorized());
        require(newProtocolFee <= MAX_PROTOCOL_FEE, ErrorsLib.FeeTooHigh());
        protocolFee = newProtocolFee;
        emit EventsLib.SetProtocolFee(newProtocolFee);
    }

    function setProtocolFeeRecipient(address newProtocolFeeRecipient) external {
        require(msg.sender == owner, ErrorsLib.Unauthorized());
        protocolFeeRecipient = newProtocolFeeRecipient;
        emit EventsLib.SetProtocolFeeRecipient(newProtocolFeeRecipient);
    }

    function createVaultV2(address _owner, address _asset) external returns (address) {
        address vaultV2 = address(new VaultV2{salt: 0}(_owner, _asset));

        isVaultV2[vaultV2] = true;
        emit EventsLib.SetIsVaultV2(vaultV2);

        return vaultV2;
    }
}
