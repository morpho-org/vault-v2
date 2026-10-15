// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {Market} from "lib/midnight/src/interfaces/IMidnight.sol";
import {WrapperEnterGate} from "./WrapperEnterGate.sol";
import {IEnterGateFactory} from "./interfaces/IEnterGateFactory.sol";

contract WrapperEnterGateFactory is IEnterGateFactory {
    event CreateWrapperEnterGate(
        address indexed wrapperEnterGate, address indexed gate, address indexed roleSetter, bytes32 marketId
    );

    mapping(address account => bool) public isGate;

    function createWrapperEnterGate(address gate, address roleSetter, Market memory market) external returns (address) {
        address wrapperEnterGate = address(new WrapperEnterGate(gate, roleSetter, market));
        isGate[wrapperEnterGate] = true;
        emit CreateWrapperEnterGate(wrapperEnterGate, gate, roleSetter, WrapperEnterGate(wrapperEnterGate).marketId());
        return wrapperEnterGate;
    }
}
