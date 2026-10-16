// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.37;

import {IEnterGate} from "../../../lib/midnight/src/interfaces/IGate.sol";
import {IEnterSubGate} from "../../../lib/midnight/src/interfaces/IEnterSubGate.sol";
import {IMidnight, Market} from "../../../lib/midnight/src/interfaces/IMidnight.sol";
import {IdLib} from "../../../lib/midnight/src/libraries/IdLib.sol";
import {IMidnightAdapterFactory} from "../../adapters/interfaces/IMidnightAdapterFactory.sol";

/// @dev Uses a subgate and lets vault users be temporarily "admitted" to increase their credit.
/// @dev Lets vault users receive credit through forceDeallocate.
/// @dev Markets other than marketId should not use this gate as their enterGate.
/// @dev roleSetter must register only factories whose adapters follow the admission rules, including after upgrades.
/// @dev Registered factories must not revoke adapter membership.
/// @dev Registration is permanent. Revoking subgate approval does not revoke canAdmit.
contract VaultV2CompatibleEnterGate is IEnterGate {
    error Unauthorized();

    event SetCanAdmit(address indexed factory);

    address public immutable midnight;
    bytes32 public immutable marketId;
    /// @dev The underlying subgate.
    address public immutable subGate;

    mapping(address factory => bool) public canAdmit;

    address transient admitted;
    address transient admitter;

    constructor(address _subGate, Market memory _marketExceptGate) {
        midnight = _marketExceptGate.midnight;
        subGate = _subGate;
        _marketExceptGate.enterGate = address(this);
        marketId = IdLib.toId(_marketExceptGate);
    }

    function roleSetter() public view returns (address) {
        return IEnterSubGate(subGate).roleSetter(true);
    }

    function setCanAdmit(address factory) external {
        require(msg.sender == roleSetter(), Unauthorized());
        canAdmit[factory] = true;
        emit SetCanAdmit(factory);
    }

    /// @dev Transiently allow a vault shareholder to increase credit in the market.
    /// @dev The contract calling this function should not have debt.
    /// @dev The caller must use admission only for its own sale in marketId.
    /// @dev A contract calling this function must clear the buyer immediately after the buyer's take.
    /// @dev The caller must check that the buyer holds shares in its parent vault.
    function admit(address user, address factory) external {
        require(canAdmit[factory] && IMidnightAdapterFactory(factory).isMidnightAdapter(msg.sender), Unauthorized());

        admitted = user;
        admitter = msg.sender;
    }

    /// @dev Clear the admission, should be called ater taking the buyer's offer.
    function unadmit() external {
        admitted = address(0);
        admitter = address(0);
    }

    /// @dev To prevent admitted users from buying more in their onBuy callback, admissions are disabled in the liquidation lock of the admitter.
    function canIncreaseCredit(address account) external view returns (bool) {
        return (account == admitted && !IMidnight(midnight).liquidationLocked(marketId, admitter))
            || IEnterSubGate(subGate).canIncreaseCredit(marketId, account);
    }

    function canIncreaseDebt(address account) external view returns (bool) {
        return IEnterSubGate(subGate).canIncreaseDebt(marketId, account);
    }
}
