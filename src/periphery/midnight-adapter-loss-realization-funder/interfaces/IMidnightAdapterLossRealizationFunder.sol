// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {Market} from "lib/midnight/src/interfaces/IMidnight.sol";

interface IMidnightAdapterLossRealizationFunder {
    event Constructor(address indexed adapter, address indexed owner);
    event SetOwner(address indexed newOwner);
    event SetMaxIncentive(uint256 maxIncentive);
    event SetMinLossForMaxIncentive(uint256 minLossForMaxIncentive);
    event WithdrawEth(address indexed receiver, uint256 assets);
    event RealizeLoss(
        address indexed caller, bytes32[] marketIds, uint256 loss, uint256 incentive, address indexed receiver
    );

    error NotOwner();
    error EthTransferFailed();

    function adapter() external view returns (address);
    function parentVault() external view returns (address);
    function owner() external view returns (address);
    function maxIncentive() external view returns (uint256);
    function minLossForMaxIncentive() external view returns (uint256);
    function setOwner(address newOwner) external;
    function setMaxIncentive(uint256 newMaxIncentive) external;
    function setMinLossForMaxIncentive(uint256 newMinLossForMaxIncentive) external;
    function withdraw(uint256 assets, address payable receiver) external;
    function realizeLoss(Market[] memory markets, address payable receiver) external returns (uint256, uint256);
}
