// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IAdapterRegistry} from "../../../interfaces/IAdapterRegistry.sol";

interface IMorphoMarketV1RegistryV2 is IAdapterRegistry {
    function morphoMarketV1AdapterV2Factory() external view returns (address);
}
