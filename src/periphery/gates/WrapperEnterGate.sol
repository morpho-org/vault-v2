// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {IEnterGate} from "lib/midnight/src/interfaces/IGate.sol";
import {IMidnight} from "lib/midnight/src/interfaces/IMidnight.sol";
import {IMidnightAdapter} from "../../adapters/interfaces/IMidnightAdapter.sol";
import {IVaultV2} from "../../interfaces/IVaultV2.sol";
import {IVaultV2Factory} from "../../interfaces/IVaultV2Factory.sol";

/// @dev Lets in, while one of its adapters is force-deallocated from a market that uses this gate, holders of shares of a vault created by vaultV2Factory, if the adapter has credit in that market.
/// @dev The adapter is not checked to be a known adapter implementation, so the curator of any vault created by vaultV2Factory can enable as adapter any account that implements parentVault() and forceDeallocatingMarketId().
contract WrapperEnterGate is IEnterGate {
    error Unauthorized();

    address public immutable midnight;
    address public immutable gate;
    address public immutable vaultV2Factory;

    constructor(address _midnight, address _gate, address _vaultV2Factory) {
        midnight = _midnight;
        gate = _gate;
        vaultV2Factory = _vaultV2Factory;
    }

    function transientAllowIncreaseCredit(address user, address adapter) external {
        (bool success, bytes memory data) = adapter.staticcall(abi.encodeWithSignature("parentVault()"));
        require(success && data.length >= 32, Unauthorized());
        address vault = abi.decode(data, (address));
        require(
            IVaultV2Factory(vaultV2Factory).isVaultV2(vault) && IVaultV2(vault).isAdapter(adapter)
                && IVaultV2(vault).balanceOf(user) > 0,
            Unauthorized()
        );

        bytes32 slot = keccak256(abi.encode(user));
        assembly ("memory-safe") {
            tstore(slot, adapter)
        }
    }

    function transientAdapter(address user) public view returns (address adapter) {
        bytes32 slot = keccak256(abi.encode(user));
        assembly ("memory-safe") {
            adapter := tload(slot)
        }
    }

    function isTransientlyAllowed(address user) public view returns (bool) {
        address adapter = transientAdapter(user);
        if (adapter == address(0)) return false;
        bytes32 marketId = IMidnightAdapter(adapter).forceDeallocatingMarketId();
        return marketId != 0 && IMidnight(midnight).toMarket(marketId).enterGate == address(this)
            && IMidnight(midnight).credit(marketId, adapter) > 0;
    }

    function canIncreaseCredit(address account) external view returns (bool) {
        return isTransientlyAllowed(account) || IEnterGate(gate).canIncreaseCredit(account);
    }

    function canIncreaseDebt(address account) external view returns (bool) {
        return IEnterGate(gate).canIncreaseDebt(account);
    }
}
