// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.37;

import {IEnterSubGate} from "./interfaces/IEnterSubGate.sol";
import {IMidnightAdapterFactory} from "../../adapters/interfaces/IMidnightAdapterFactory.sol";
import {IVaultV2CompatibleEnterGate} from "./interfaces/IVaultV2CompatibleEnterGate.sol";
import {IMidnight, Market, Offer} from "../../../lib/midnight/src/interfaces/IMidnight.sol";
import {IdLib} from "../../../lib/midnight/src/libraries/IdLib.sol";
import {CALLBACK_SUCCESS} from "../../../lib/midnight/src/libraries/ConstantsLib.sol";

/// @dev Uses a subgate and lets vault users be temporarily "admitted" to increase their credit through forceDeallocate.
/// @dev Any market, on any Midnight, can use this gate as its enterGate. The subgate's permissions apply to all of them.
/// @dev roleSetter permanently registers adapter factories; their debt-free adapters admit a vault shareholder only during their own sale and clear admission in the buyer callback before token transfers.
/// @dev The gate can irrecoverably buy credit in its own markets for zero assets, including settlement fees, independently of the subgate.
contract VaultV2CompatibleEnterGate is IVaultV2CompatibleEnterGate {
    address public immutable subGate;

    mapping(address factory => bool) public canAdmit;

    address transient admitted;

    constructor(address _subGate) {
        subGate = _subGate;
    }

    function roleSetter() public view returns (address) {
        return IEnterSubGate(subGate).roleSetter(true);
    }

    function addAdmitterFactory(address factory) external {
        require(msg.sender == roleSetter(), Unauthorized());
        canAdmit[factory] = true;
        emit AddAdmitterFactory(factory);
    }

    /// @dev Transiently allow a vault shareholder to increase credit in any market using this gate.
    /// @dev The caller must be debt-free, check the buyer holds its vault's shares, and clear admission in its own sale's buyer callback before token transfers.
    function admit(address user, address factory) external {
        require(canAdmit[factory] && IMidnightAdapterFactory(factory).isCreated(msg.sender), Unauthorized());

        admitted = user;
        emit Admit(msg.sender, user, factory);
    }

    /// @dev Clear the admission, should be called from the buyer callback of the buyer's take.
    function unadmit() external {
        admitted = address(0);
    }

    /// @dev The seller must authorize the offer. Bought credit cannot be recovered from this gate.
    function buyAtZero(Offer memory offer, bytes memory ratifierData, uint256 units) external {
        require(!offer.buy && offer.market.enterGate == address(this), IncorrectOffer());
        IMidnight(offer.market.midnight)
            .take(offer, ratifierData, units, address(this), address(0), address(this), hex"");
        emit BuyAtZero(msg.sender, IdLib.toId(offer.market), units);
    }

    function onBuy(bytes32, Market memory, uint256 buyerAssets, uint256, uint256, address, bytes memory)
        external
        pure
        returns (bytes32)
    {
        require(buyerAssets == 0, NonZeroBuyAssets());
        return CALLBACK_SUCCESS;
    }

    function canIncreaseCredit(address account) external view returns (bool) {
        return account == address(this) || (admitted != address(0) && account == admitted)
            || IEnterSubGate(subGate).creditIncreaseAllowed(account);
    }

    function canIncreaseDebt(address account) external view returns (bool) {
        return IEnterSubGate(subGate).debtIncreaseAllowed(account);
    }
}
