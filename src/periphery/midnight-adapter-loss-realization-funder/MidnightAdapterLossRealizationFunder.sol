// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {IMidnightAdapterLossRealizationFunder} from "./interfaces/IMidnightAdapterLossRealizationFunder.sol";
import {IMidnightAdapter} from "../../adapters/interfaces/IMidnightAdapter.sol";
import {Market} from "lib/midnight/src/interfaces/IMidnight.sol";
import {IdLib} from "lib/midnight/src/libraries/IdLib.sol";
import {MathLib} from "../../libraries/MathLib.sol";

/// @dev Rewards realizing a loss in the Midnight Adapter.
contract MidnightAdapterLossRealizationFunder is IMidnightAdapterLossRealizationFunder {
    address public immutable adapter;
    address public immutable parentVault;

    address public owner;
    uint256 public maxIncentive;
    uint256 public minLossForMaxIncentive;

    constructor(address _adapter, address _owner) payable {
        adapter = _adapter;
        parentVault = IMidnightAdapter(_adapter).parentVault();
        owner = _owner;
        emit Constructor(_adapter, _owner);
    }

    receive() external payable {}

    function setOwner(address newOwner) external {
        require(msg.sender == owner, NotOwner());
        owner = newOwner;
        emit SetOwner(newOwner);
    }

    function setMaxIncentive(uint256 newMaxIncentive) external {
        require(msg.sender == owner, NotOwner());
        maxIncentive = newMaxIncentive;
        emit SetMaxIncentive(newMaxIncentive);
    }

    function setMinLossForMaxIncentive(uint256 newMinLossForMaxIncentive) external {
        require(msg.sender == owner, NotOwner());
        minLossForMaxIncentive = newMinLossForMaxIncentive;
        emit SetMinLossForMaxIncentive(newMinLossForMaxIncentive);
    }

    function withdraw(uint256 assets, address payable receiver) external {
        require(msg.sender == owner, NotOwner());
        (bool success,) = receiver.call{value: assets}("");
        require(success, EthTransferFailed());
        emit WithdrawEth(receiver, assets);
    }

    function realizeLoss(Market[] memory markets, address payable receiver) external returns (uint256, uint256) {
        uint256 adapterAssets = IMidnightAdapter(adapter).realAssets();
        address asset = IMidnightAdapter(adapter).asset();

        bytes32[] memory marketIds = new bytes32[](markets.length);
        for (uint256 i = 0; i < markets.length; i++) {
            require(markets[i].loanToken == asset, IMidnightAdapter.LoanAssetMismatch());
            IMidnightAdapter(adapter).withdrawToVault(markets[i], 0);
            marketIds[i] = IdLib.toId(markets[i]);
        }

        uint256 loss = adapterAssets - IMidnightAdapter(adapter).realAssets();
        uint256 paid = MathLib.min(maxIncentive, maxIncentive * loss / minLossForMaxIncentive);
        // forge-lint: disable-next-item(arbitrary-send-eth) caller chooses the incentive receiver.
        (bool success,) = receiver.call{value: paid}("");
        require(success, EthTransferFailed());
        emit RealizeLoss(msg.sender, marketIds, loss, paid, receiver);
        return (loss, paid);
    }
}
