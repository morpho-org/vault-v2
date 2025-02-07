// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {VaultsV2} from "../VaultsV2.sol";

struct SetIRMData {
    address irm;
}

struct EnableNewMarketData {
    address market;
}

struct ReallocateFromIdleData {
    uint256 marketIndex;
    uint256 amount;
}

struct ReallocateToIdleData {
    uint256 marketIndex;
    uint256 amount;
}

struct WithdrawData {
    uint256 assets;
    address receiver;
    address owner;
}

library DecodeLib {
    using DecodeLib for bytes;
    using DecodeLib for bytes32;

    function selector_(bytes memory _call) internal pure returns (bytes4) {
        return bytes4(_call);
    }

    function field_(bytes memory _call, uint256 offset) internal pure returns (bytes32 ret) {
        assembly ("memory-safe") {
            ret := mload(add(_call, add(36, mul(32, offset))))
        }
    }

    function address_(bytes32 data) internal pure returns (address) {
        require(data >> 20 == bytes32(0));
        return address(bytes20(data));
    }

    function uint256_(bytes32 data) internal pure returns (uint256) {
        return uint256(data);
    }

    function decodeAsSetIRMData(bytes memory _call) internal pure returns (SetIRMData memory) {
        require(_call.length == 36);
        require(_call.selector_() == VaultsV2.setIRM.selector);
        return SetIRMData({irm: _call.field_(0).address_()});
    }

    function decodeAsEnableNewMarketData(bytes memory _call) internal pure returns (EnableNewMarketData memory) {
        require(_call.length == 36);
        require(_call.selector_() == VaultsV2.enableNewMarket.selector);
        return EnableNewMarketData({market: _call.field_(0).address_()});
    }

    function decodeAsReallocateFromIdleData(bytes memory _call) internal pure returns (ReallocateFromIdleData memory) {
        require(_call.length == 68);
        require(_call.selector_() == VaultsV2.reallocateFromIdle.selector);
        return ReallocateFromIdleData({marketIndex: _call.field_(0).uint256_(), amount: _call.field_(1).uint256_()});
    }

    function decodeAsReallocateToIdleData(bytes memory _call) internal pure returns (ReallocateToIdleData memory) {
        require(_call.length == 68);
        require(_call.selector_() == VaultsV2.reallocateToIdle.selector);
        return ReallocateToIdleData({marketIndex: _call.field_(0).uint256_(), amount: _call.field_(1).uint256_()});
    }

    function decodeAsWithdrawData(bytes memory _call) internal pure returns (WithdrawData memory) {
        require(_call.length == 100);
        require(_call.selector_() == VaultsV2.withdraw.selector);
        return WithdrawData({
            assets: _call.field_(0).uint256_(),
            receiver: _call.field_(1).address_(),
            owner: _call.field_(2).address_()
        });
    }
}
