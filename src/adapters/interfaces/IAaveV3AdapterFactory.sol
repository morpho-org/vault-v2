// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title IAaveV3AdapterFactory
/// @notice Interface for the Aave V3 adapter factory
interface IAaveV3AdapterFactory {
    /* EVENTS */

    event CreateAaveV3Adapter(
        address indexed parentVault, address indexed aToken, address indexed aaveV3Adapter
    );

    /* FUNCTIONS */

    function aavePool() external view returns (address);
    function aaveV3Adapter(address parentVault, address aToken) external view returns (address);
    function isAaveV3Adapter(address account) external view returns (bool);
    function createAaveV3Adapter(address parentVault, address aToken) external returns (address);
}
