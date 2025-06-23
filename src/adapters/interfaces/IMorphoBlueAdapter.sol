// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IAdapter} from "../../interfaces/IAdapter.sol";
import {Id} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";

interface IMorphoBlueAdapter is IAdapter {
    /* EVENTS */

    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);

    /* ERRORS */

    error IrmMismatch();
    error LoanAssetMismatch();
    error NotAuthorized();

    /* FUNCTIONS */

    function factory() external view returns (address);
    function parentVault() external view returns (address);
    function morpho() external view returns (address);
    function irm() external view returns (address);
    function skimRecipient() external view returns (address);
    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
    function allocation(Id marketId) external view returns (uint256);
    function shares(Id marketId) external view returns (uint256);
}
