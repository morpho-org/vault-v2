// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {IMidnightAdapter} from "../../adapters/interfaces/IMidnightAdapter.sol";
import {WrapperEnterGate} from "./WrapperEnterGate.sol";
import {IEnterGateFactory} from "./interfaces/IEnterGateFactory.sol";

contract WrapperEnterGateFactory is IEnterGateFactory {
    event CreateWrapperEnterGate(address indexed adapter, address indexed wrapperEnterGate, address indexed gate);

    mapping(address account => bool) public isGate;

    function createWrapperEnterGate(address adapter, address gate) external returns (address) {
        address wrapperEnterGate = address(new WrapperEnterGate(adapter, IMidnightAdapter(adapter).parentVault(), gate));
        isGate[wrapperEnterGate] = true;
        emit CreateWrapperEnterGate(adapter, wrapperEnterGate, gate);
        return wrapperEnterGate;
    }
}
