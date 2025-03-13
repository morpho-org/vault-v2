// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {UtilsLib} from "../libraries/UtilsLib.sol";
import {DecodeLib, ReallocateFromIdleData, ReallocateToIdleData, WithdrawData} from "../libraries/DecodeLib.sol";

import {IVaultV2} from "../VaultV2.sol";
import {BaseAllocator} from "./BaseAllocator.sol";

contract MMAllocator is BaseAllocator {
    using DecodeLib for bytes;
    using UtilsLib for uint256;

    address public immutable owner;
    IVaultV2 public immutable vault;
    IERC20 public immutable asset;

    constructor(address _owner, IVaultV2 _vault) {
        owner = _owner;
        vault = _vault;
        asset = vault.asset();
    }

    address public publicAllocator;

    function setPublicAllocator(address newPublicAllocator) public {
        require(msg.sender == owner);
        publicAllocator = newPublicAllocator;
    }

    function authorizeMulticall(address sender, bytes[] calldata bundle) external view override {
        // if (sender == owner) return;
        // if (sender == publicAllocator) {
        //     // This implements the public allocator.
        //     require(bundle.length == 2);
        //     ReallocateToIdleData memory toIdle = bundle[0].decodeAsReallocateToIdleData();
        //     ReallocateFromIdleData memory fromIdle = bundle[1].decodeAsReallocateFromIdleData();
        //     require(toIdle.amount == fromIdle.amount);
        // } else {
        //     // This implements the withdraw queue.
        //     WithdrawData memory withdraw = bundle[bundle.length - 1].decodeAsWithdrawData();
        //     uint256 missingLiquidity = withdraw.assets.zeroFloorSub(asset.balanceOf(address(vault)));
        //     for (uint256 i; i < bundle.length - 1; i++) {
        //         ReallocateToIdleData memory toIdle = bundle[i].decodeAsReallocateToIdleData();
        //         require(toIdle.marketIndex == i);
        //         require(missingLiquidity > 0);
        //         IMarket market = vault.markets(i);
        //         require(toIdle.amount == UtilsLib.min(missingLiquidity, market.maxWithdraw(address(vault))));
        //         missingLiquidity -= toIdle.amount;
        //     }
        // }
    }
}
