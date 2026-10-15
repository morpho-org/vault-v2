// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.37;

import {
    IWhitelistEnterGate,
    SET_IS_WHITELISTED_TYPEHASH,
    EIP712_DOMAIN_TYPEHASH
} from "lib/midnight/src/periphery/whitelist-enter-gate/interfaces/IWhitelistEnterGate.sol";
import {IMidnight} from "lib/midnight/src/interfaces/IMidnight.sol";
import {IMidnightAdapter} from "../../adapters/interfaces/IMidnightAdapter.sol";
import {IMidnightAdapterFactory} from "../../adapters/interfaces/IMidnightAdapterFactory.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IForceDeallocationEnterGate} from "./interfaces/IForceDeallocationEnterGate.sol";

/// @dev This gate restricts which accounts can increase their credit or debt in a market.
/// @dev Each side (credit, debt) has its own whitelist. Only whitelisted accounts can enter on that side.
/// @dev Each side has its own role setter and whitelisters.
/// @dev A side can be made open at deployment, letting any account enter on that side (forever).
/// @dev As with any enter gate, it does not prevent accounts from exiting the market.
/// @dev If block.chainid changes (hard fork), the EIP-712 domain separator changes and previously signed messages are no longer valid.
/// @dev In addition to its whitelist, lets holders of a vault's shares increase credit while one of that vault's adapters is force-deallocated from a market using this gate.
/// @dev The transient permission ends with the transaction. canIncreaseCredit does not know the market, so during the forced take's buyer onBuy callback, users transiently allowed earlier in the transaction can buy from other sellers in any market using this gate.
/// @dev The credit role setter is trusted: it can add a factory that reports any account as an adapter, which would block force deallocation through this gate.
contract ForceDeallocationEnterGate is IForceDeallocationEnterGate {
    bool public immutable CREDIT_OPEN;
    bool public immutable DEBT_OPEN;

    address public immutable midnight;
    mapping(bool creditSide => address) public roleSetter;
    mapping(bool creditSide => mapping(address account => bool)) public isWhitelister;
    mapping(bool creditSide => mapping(address whitelister => mapping(address account => uint256))) public nonces;
    mapping(bool creditSide => mapping(address account => bool)) public isWhitelisted;
    /// @dev Append-only so depositors who rely on a factory can always force-deallocate.
    mapping(address adapterFactory => bool) public isAdapterFactory;
    address[] public adapterFactories;

    constructor(
        address _midnight,
        address _creditRoleSetter,
        address _debtRoleSetter,
        bool _creditOpen,
        bool _debtOpen
    ) {
        midnight = _midnight;
        roleSetter[true] = _creditRoleSetter;
        roleSetter[false] = _debtRoleSetter;
        CREDIT_OPEN = _creditOpen;
        DEBT_OPEN = _debtOpen;
        emit Constructor(_creditRoleSetter, _debtRoleSetter, _creditOpen, _debtOpen);
    }

    function setRoleSetter(bool creditSide, address newRoleSetter) external {
        require(msg.sender == roleSetter[creditSide], NotRoleSetter());
        roleSetter[creditSide] = newRoleSetter;
        emit SetRoleSetter(creditSide, newRoleSetter);
    }

    function setIsWhitelister(bool creditSide, address account, bool newIsWhitelister) external {
        require(msg.sender == roleSetter[creditSide], NotRoleSetter());
        isWhitelister[creditSide][account] = newIsWhitelister;
        emit SetIsWhitelister(creditSide, account, newIsWhitelister);
    }

    function setIsWhitelisted(bool creditSide, address account, bool newIsWhitelisted) external {
        require(isWhitelister[creditSide][msg.sender], NotWhitelister());
        isWhitelisted[creditSide][account] = newIsWhitelisted;
        emit SetIsWhitelisted(msg.sender, creditSide, account, newIsWhitelisted);
    }

    /// @dev Adding a factory is restricted to the credit role setter; factories cannot be removed so depositors can exit.
    function addAdapterFactory(address adapterFactory) external {
        require(msg.sender == roleSetter[true], NotRoleSetter());
        require(IMidnightAdapterFactory(adapterFactory).midnight() == midnight, IncorrectMidnight());
        require(!isAdapterFactory[adapterFactory], AlreadyAdapterFactory());
        isAdapterFactory[adapterFactory] = true;
        adapterFactories.push(adapterFactory);
        emit AddAdapterFactory(adapterFactory);
    }

    function adapterFactoriesLength() external view returns (uint256) {
        return adapterFactories.length;
    }

    function setIsWhitelistedWithSig(
        bool creditSide,
        address account,
        bool newIsWhitelisted,
        uint256 nonce,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, DeadlineExpired());
        bytes32 hashStruct =
            keccak256(abi.encode(SET_IS_WHITELISTED_TYPEHASH, creditSide, account, newIsWhitelisted, nonce, deadline));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        // forge-lint: disable-next-item(ecrecover) malleability is ok thanks to the nonce.
        address whitelister = ecrecover(digest, v, r, s);
        require(whitelister != address(0) && isWhitelister[creditSide][whitelister], InvalidSigner());
        uint256 previousNonce = nonces[creditSide][whitelister][account];
        if (nonce == previousNonce) {
            nonces[creditSide][whitelister][account] = previousNonce + 1;
            isWhitelisted[creditSide][account] = newIsWhitelisted;
        } else {
            require(nonce < previousNonce, InvalidNonce());
            require(isWhitelisted[creditSide][account] == newIsWhitelisted, WhitelistedStatusChanged());
        }
        emit SetIsWhitelistedWithSig(
            msg.sender, whitelister, creditSide, account, newIsWhitelisted, nonce, previousNonce
        );
    }

    function transientAllowIncreaseCredit(address user, address adapter, address adapterFactory) external {
        require(
            isAdapterFactory[adapterFactory] && IMidnightAdapterFactory(adapterFactory).isMidnightAdapter(adapter),
            Unauthorized()
        );

        bytes32 slot = keccak256(abi.encode(user));
        assembly ("memory-safe") {
            tstore(slot, adapter)
        }
    }

    function transientAdapter(address user) public view returns (address adapter) {
        bytes32 slot = keccak256(abi.encode(user));
        assembly ("memory-safe") {
            adapter := tload(slot)
        }
    }

    /// @dev A user must hold vault shares and not be an adapter of any trusted factory. Check this when using the permission
    /// because a share or adapter may be transferred or deployed later in the transaction.
    function isTransientlyAllowed(address user) public view returns (bool) {
        address adapter = transientAdapter(user);
        if (adapter == address(0)) return false;
        for (uint256 i; i < adapterFactories.length; ++i) {
            if (IMidnightAdapterFactory(adapterFactories[i]).isMidnightAdapter(user)) return false;
        }
        bool hasShares = IERC20(IMidnightAdapter(adapter).parentVault()).balanceOf(user) > 0;
        if (!hasShares) return false;
        bytes32 marketId = IMidnightAdapter(adapter).forceDeallocatingMarketId();
        return marketId != 0 && IMidnight(midnight).toMarket(marketId).enterGate == address(this)
            && IMidnight(midnight).credit(marketId, adapter) > 0;
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    function canIncreaseCredit(address account) external view returns (bool) {
        return CREDIT_OPEN || isWhitelisted[true][account] || isTransientlyAllowed(account);
    }

    function canIncreaseDebt(address account) external view returns (bool) {
        return DEBT_OPEN || isWhitelisted[false][account];
    }

    /// @dev Useful for EOAs to batch privileged calls.
    /// @dev Does not return anything, because accounts who would use the return data would be contracts, which can do the multicall themselves.
    function multicall(bytes[] calldata data) external {
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory returnData) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(32, returnData), mload(returnData))
                }
            }
        }
    }
}
