// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IAdapterRegistry} from "../../../interfaces/IAdapterRegistry.sol";

interface IMorphoVaultV1Registry is IAdapterRegistry {
    function morphoVaultV1AdapterFactory() external view returns (address);
    function morphoVaultV1Factory() external view returns (address);
}
