// SPDX-License-Identifier: GPL-2.0-or-later
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
    error NoRealizableLoss();
    error NotAuthorized();
    error RealizableLoss();

    /* FUNCTIONS */

    function parentVault() external view returns (address);
    function morpho() external view returns (address);
    function irm() external view returns (address);
    function skimRecipient() external view returns (address);
    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
    function assetsInMarket(Id marketId) external view returns (uint256);
    function sharesInMarket(Id marketId) external view returns (uint256);
}
