// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library SharesHandlerLib {
    bytes32 constant HANDLER_PREFIX = keccak256("Morpho VaultV2 Shares Handler");

    function setHandled(address handler, address owner) external {
        bytes32 handlerKey = keccak256(abi.encodePacked(HANDLER_PREFIX, handler));
        assembly {
            tstore(handlerKey, owner)
        }
    }

    function getHandled(address handler) external view returns (address handled) {
        bytes32 handlerKey = keccak256(abi.encodePacked(HANDLER_PREFIX, handler));
        assembly {
            handled := tload(handlerKey)
        }
    }
}
