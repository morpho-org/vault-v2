// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {BaseCurator} from "./BaseCurator.sol";
import {IERC20, IERC4626} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";

import {UtilsLib} from "../libraries/UtilsLib.sol";
import "../libraries/DecodeLib.sol";

contract MMCurator is BaseCurator {
    using DecodeLib for bytes;
    using UtilsLib for uint256;

    address public immutable owner;
    VaultsV2 public immutable vault;
    IERC20 public immutable asset;

    constructor(address _owner, VaultsV2 _vault) {
        owner = _owner;
        vault = _vault;
        asset = vault.asset();
    }

    mapping(address => bool) public isAllocator;

    function setAllocator(address allocator, bool enabled) public {
        require(msg.sender == owner);
        isAllocator[allocator] = enabled;
    }

    function authorizeMulticall(address sender, bytes[] calldata bundle) external view override {
        if (sender == owner) return;
        if (isAllocator[sender]) {
            require(bundle.length == 2);
            ReallocateToIdleData memory toIdle = bundle[0].decodeAsReallocateToIdleData();
            ReallocateFromIdleData memory fromIdle = bundle[1].decodeAsReallocateFromIdleData();
            require(toIdle.amount == fromIdle.amount);
        } else if (bundle.length == 1) {
            checkRestrictedFunction(bundle[0].selector_());
        } else {
            WithdrawData memory withdraw = bundle[bundle.length - 1].decodeAsWithdrawData();
            // Should probably have internal accounting for idle here.
            uint256 missingLiquidity = withdraw.assets.zeroFloorSub(asset.balanceOf(address(vault)));
            for (uint256 i; i < bundle.length - 1; i++) {
                ReallocateToIdleData memory toIdle = bundle[i].decodeAsReallocateToIdleData();
                require(toIdle.marketIndex == i);
                require(missingLiquidity > 0);
                IERC4626 market = vault.markets(i);
                require(toIdle.amount == UtilsLib.min(missingLiquidity, market.maxWithdraw(address(vault))));
            }
        }
    }
}
