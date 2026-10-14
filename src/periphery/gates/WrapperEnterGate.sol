// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {IEnterGate} from "lib/midnight/src/interfaces/IGate.sol";
import {IMidnight, Market} from "lib/midnight/src/interfaces/IMidnight.sol";
import {IdLib} from "lib/midnight/src/libraries/IdLib.sol";
import {IVaultV2} from "../../interfaces/IVaultV2.sol";
import {IVaultV2Factory} from "../../interfaces/IVaultV2Factory.sol";

/// @dev Lets in holders of shares of a vault created by vaultV2Factory, if one of the vault's adapters has credit in the market.
/// @dev Markets other than marketId should not use this gate as their enterGate.
/// @dev The adapter is not checked to be a known adapter implementation, so a curator can enable as adapter any account with credit in the market that implements parentVault().
contract WrapperEnterGate is IEnterGate {
    error Unauthorized();

    address public immutable midnight;
    address public immutable gate;
    bytes32 public immutable marketId;
    address public immutable vaultV2Factory;

    constructor(address _midnight, address _gate, Market memory market, address _vaultV2Factory) {
        midnight = _midnight;
        gate = _gate;
        market.enterGate = address(this);
        marketId = IdLib.toId(market);
        vaultV2Factory = _vaultV2Factory;
    }

    function transientAllowIncreaseCredit(address user, address adapter) external {
        (bool success, bytes memory data) = adapter.staticcall(abi.encodeWithSignature("parentVault()"));
        require(success && data.length >= 32, Unauthorized());
        address vault = abi.decode(data, (address));
        require(
            IVaultV2Factory(vaultV2Factory).isVaultV2(vault) && IVaultV2(vault).isAdapter(adapter)
                && IMidnight(midnight).credit(marketId, adapter) > 0 && IVaultV2(vault).balanceOf(user) > 0,
            Unauthorized()
        );

        bytes32 slot = keccak256(abi.encode(user));
        assembly ("memory-safe") {
            tstore(slot, 1)
        }
    }

    function isTransientlyAllowed(address user) public view returns (bool allowed) {
        bytes32 slot = keccak256(abi.encode(user));
        assembly ("memory-safe") {
            allowed := tload(slot)
        }
    }

    function canIncreaseCredit(address account) external view returns (bool) {
        return isTransientlyAllowed(account) || IEnterGate(gate).canIncreaseCredit(account);
    }

    function canIncreaseDebt(address account) external view returns (bool) {
        return IEnterGate(gate).canIncreaseDebt(account);
    }
}
