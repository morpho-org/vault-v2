// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {AaveV3Adapter} from "./AaveV3Adapter.sol";
import {IAaveV3AdapterFactory} from "./interfaces/IAaveV3AdapterFactory.sol";

/// @title AaveV3AdapterFactory
/// @notice Factory for deploying AaveV3Adapter instances
contract AaveV3AdapterFactory is IAaveV3AdapterFactory {
    /* IMMUTABLES */

    address public immutable aavePool;

    /* STORAGE */

    mapping(address parentVault => mapping(address aToken => address)) public aaveV3Adapter;
    mapping(address account => bool) public isAaveV3Adapter;

    /* FUNCTIONS */

    constructor(address _aavePool) {
        aavePool = _aavePool;
    }

    /// @dev Returns the address of the deployed AaveV3Adapter.
    function createAaveV3Adapter(address parentVault, address aToken) external returns (address) {
        address _aaveV3Adapter = address(new AaveV3Adapter{salt: bytes32(0)}(parentVault, aavePool, aToken));
        aaveV3Adapter[parentVault][aToken] = _aaveV3Adapter;
        isAaveV3Adapter[_aaveV3Adapter] = true;
        emit CreateAaveV3Adapter(parentVault, aToken, _aaveV3Adapter);
        return _aaveV3Adapter;
    }
}
