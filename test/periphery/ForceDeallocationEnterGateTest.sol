// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IMidnight, Market} from "../../lib/midnight/src/interfaces/IMidnight.sol";
import {IMidnightAdapterBase} from "../../src/adapters/interfaces/IMidnightAdapter.sol";
import {IMidnightAdapterFactory} from "../../src/adapters/interfaces/IMidnightAdapterFactory.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {
    SET_IS_WHITELISTED_TYPEHASH
} from "../../lib/midnight/src/periphery/whitelist-enter-gate/interfaces/IWhitelistEnterGate.sol";
import {
    IWhitelistEnterGate
} from "../../lib/midnight/src/periphery/whitelist-enter-gate/interfaces/IWhitelistEnterGate.sol";
import {ForceDeallocationEnterGate} from "../../src/periphery/gates/ForceDeallocationEnterGate.sol";
import {IForceDeallocationEnterGate} from "../../src/periphery/gates/interfaces/IForceDeallocationEnterGate.sol";
import {ForceDeallocationEnterGateFactory} from "../../src/periphery/gates/ForceDeallocationEnterGateFactory.sol";
import {
    IForceDeallocationEnterGateFactory
} from "../../src/periphery/gates/interfaces/IForceDeallocationEnterGateFactory.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/// forge-config: default.isolate = false
contract ForceDeallocationEnterGateTest is Test {
    address internal midnight = makeAddr("midnight");
    address internal adapterFactory = makeAddr("adapterFactory");
    address internal otherFactory = makeAddr("otherFactory");
    address internal adapter = makeAddr("adapter");
    address internal user = makeAddr("user");
    bytes32 internal marketId = keccak256("market");

    ERC20Mock internal vault;
    ForceDeallocationEnterGate internal gate;

    function setUp() public {
        vault = new ERC20Mock(18);
        gate = new ForceDeallocationEnterGate(midnight, address(this), address(this), false, false);
        gate.addAdapterFactory(adapterFactory);

        _setIsAdapter(adapterFactory, adapter, true);
        _setIsAdapter(adapterFactory, user, false);
        vm.mockCall(adapter, abi.encodeCall(IMidnightAdapterBase.parentVault, ()), abi.encode(address(vault)));
        vm.mockCall(adapter, abi.encodeCall(IMidnightAdapterBase.forceDeallocatingMarketId, ()), abi.encode(marketId));
        vm.mockCall(midnight, abi.encodeCall(IMidnight.credit, (marketId, adapter)), abi.encode(uint128(1)));
        _setMarketEnterGate(address(gate));
    }

    function testConstructor() public view {
        assertEq(gate.midnight(), midnight);
        assertEq(gate.roleSetter(true), address(this));
        assertEq(gate.roleSetter(false), address(this));
        assertFalse(gate.CREDIT_OPEN());
        assertFalse(gate.DEBT_OPEN());
        assertTrue(gate.isAdapterFactory(adapterFactory));
        assertEq(gate.adapterFactoriesLength(), 1);
        assertEq(gate.adapterFactories(0), adapterFactory);
    }

    function testOpenSideAllowsAnyAccount() public {
        ForceDeallocationEnterGate openGate =
            new ForceDeallocationEnterGate(midnight, address(this), address(this), true, false);

        assertTrue(openGate.canIncreaseCredit(user));
        assertFalse(openGate.canIncreaseDebt(user));
    }

    function testAddAdapterFactory() public {
        address newFactory = makeAddr("newFactory");
        vm.expectEmit(true, false, false, true, address(gate));
        emit IForceDeallocationEnterGate.AddAdapterFactory(newFactory);
        gate.addAdapterFactory(newFactory);
        assertTrue(gate.isAdapterFactory(newFactory));
        assertEq(gate.adapterFactoriesLength(), 2);
        assertEq(gate.adapterFactories(0), adapterFactory);
        assertEq(gate.adapterFactories(1), newFactory);
    }

    function testAddAdapterFactoryTwice() public {
        address newFactory = makeAddr("newFactory");
        gate.addAdapterFactory(newFactory);

        vm.expectRevert(IForceDeallocationEnterGate.AlreadyAdapterFactory.selector);
        gate.addAdapterFactory(newFactory);
    }

    function testAddAdapterFactoryNotCreditRoleSetter(address caller, address newFactory) public {
        vm.assume(caller != address(this));
        vm.prank(caller);
        vm.expectRevert(IWhitelistEnterGate.NotRoleSetter.selector);
        gate.addAdapterFactory(newFactory);
    }

    function testTransientAllowIncreaseCredit(address caller, uint256 shares) public {
        shares = bound(shares, 1, type(uint128).max);
        deal(address(vault), user, shares);

        vm.prank(caller);
        gate.transientAllowIncreaseCredit(user, adapter, adapterFactory);

        assertEq(gate.transientAdapter(user), adapter);
        assertTrue(gate.isTransientlyAllowed(user));
        assertTrue(gate.canIncreaseCredit(user));
        assertFalse(gate.isTransientlyAllowed(makeAddr("otherUser")));
    }

    function testTransientAllowIncreaseCreditRejectsUntrustedFactory() public {
        deal(address(vault), user, 1);
        vm.expectRevert(IForceDeallocationEnterGate.Unauthorized.selector);
        gate.transientAllowIncreaseCredit(user, adapter, otherFactory);
    }

    function testTransientAllowIncreaseCreditRejectsNonAdapter() public {
        deal(address(vault), user, 1);
        _setIsAdapter(adapterFactory, adapter, false);
        vm.expectRevert(IForceDeallocationEnterGate.Unauthorized.selector);
        gate.transientAllowIncreaseCredit(user, adapter, adapterFactory);
    }

    function testTransientAllowIncreaseCreditRejectsAdapterUser() public {
        deal(address(vault), user, 1);
        _setIsAdapter(adapterFactory, user, true);
        vm.expectRevert(IForceDeallocationEnterGate.Unauthorized.selector);
        gate.transientAllowIncreaseCredit(user, adapter, adapterFactory);
    }

    function testTransientAllowIncreaseCreditRejectsAdapterFromAnotherTrustedFactory() public {
        address secondFactory = makeAddr("secondFactory");
        gate.addAdapterFactory(secondFactory);
        _setIsAdapter(secondFactory, user, true);
        deal(address(vault), user, 1);

        vm.expectRevert(IForceDeallocationEnterGate.Unauthorized.selector);
        gate.transientAllowIncreaseCredit(user, adapter, adapterFactory);
    }

    function testTransientAllowIncreaseCreditRejectsUserWithoutShares() public {
        vm.expectRevert(IForceDeallocationEnterGate.Unauthorized.selector);
        gate.transientAllowIncreaseCredit(user, adapter, adapterFactory);
    }

    function testFallsBackToWhitelistWithoutForceDeallocation() public {
        _allowAndWhitelistUser();
        vm.mockCall(adapter, abi.encodeCall(IMidnightAdapterBase.forceDeallocatingMarketId, ()), abi.encode(bytes32(0)));

        assertFalse(gate.isTransientlyAllowed(user));
        assertTrue(gate.canIncreaseCredit(user));
    }

    function testFallsBackToWhitelistWhenMarketUsesAnotherGate() public {
        _allowAndWhitelistUser();
        _setMarketEnterGate(makeAddr("otherGate"));

        assertFalse(gate.isTransientlyAllowed(user));
        assertTrue(gate.canIncreaseCredit(user));
    }

    function testFallsBackToWhitelistWhenAdapterHasNoCredit() public {
        _allowAndWhitelistUser();
        vm.mockCall(midnight, abi.encodeCall(IMidnight.credit, (marketId, adapter)), abi.encode(uint128(0)));

        assertFalse(gate.isTransientlyAllowed(user));
        assertTrue(gate.canIncreaseCredit(user));
    }

    function testWhitelistBehavior() public {
        gate.setIsWhitelister(true, address(this), true);
        gate.setIsWhitelisted(true, user, true);
        gate.setIsWhitelister(false, address(this), true);
        gate.setIsWhitelisted(false, user, true);

        assertTrue(gate.canIncreaseCredit(user));
        assertTrue(gate.canIncreaseDebt(user));
        assertFalse(gate.canIncreaseCredit(makeAddr("otherUser")));
        assertFalse(gate.canIncreaseDebt(makeAddr("otherUser")));
    }

    function testWhitelistSignature() public {
        uint256 privateKey = 0xA11CE;
        address whitelister = vm.addr(privateKey);
        gate.setIsWhitelister(true, whitelister, true);

        uint256 deadline = block.timestamp + 1;
        bytes32 hashStruct = keccak256(abi.encode(SET_IS_WHITELISTED_TYPEHASH, true, user, true, 0, deadline));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", gate.DOMAIN_SEPARATOR(), hashStruct));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        gate.setIsWhitelistedWithSig(true, user, true, 0, deadline, v, r, s);

        assertTrue(gate.isWhitelisted(true, user));
        assertTrue(gate.canIncreaseCredit(user));
    }

    function _allowAndWhitelistUser() internal {
        deal(address(vault), user, 1);
        gate.transientAllowIncreaseCredit(user, adapter, adapterFactory);
        gate.setIsWhitelister(true, address(this), true);
        gate.setIsWhitelisted(true, user, true);
    }

    function _setIsAdapter(address factory, address account, bool isAdapter) internal {
        vm.mockCall(
            factory, abi.encodeCall(IMidnightAdapterFactory.isMidnightAdapter, (account)), abi.encode(isAdapter)
        );
    }

    function _setMarketEnterGate(address enterGate) internal {
        Market memory market;
        market.enterGate = enterGate;
        vm.mockCall(midnight, abi.encodeCall(IMidnight.toMarket, (marketId)), abi.encode(market));
    }
}

contract ForceDeallocationEnterGateFactoryTest is Test {
    address internal midnight = makeAddr("midnight");
    ForceDeallocationEnterGateFactory internal factory;

    function setUp() public {
        factory = new ForceDeallocationEnterGateFactory(midnight);
    }

    function testCreateForceDeallocationEnterGate() public {
        address creditRoleSetter = makeAddr("creditRoleSetter");
        address debtRoleSetter = makeAddr("debtRoleSetter");
        bytes32 preSalt = keccak256("salt");

        address created =
            factory.createForceDeallocationEnterGate(creditRoleSetter, debtRoleSetter, false, true, preSalt);
        ForceDeallocationEnterGate gate = ForceDeallocationEnterGate(created);

        assertTrue(factory.isForceDeallocationEnterGate(created));
        assertEq(factory.midnight(), midnight);
        assertEq(gate.midnight(), midnight);
        assertEq(gate.roleSetter(true), creditRoleSetter);
        assertEq(gate.roleSetter(false), debtRoleSetter);
        assertFalse(gate.CREDIT_OPEN());
        assertTrue(gate.DEBT_OPEN());
    }

    function testCreateSaltIsScopedToCaller() public {
        bytes32 preSalt = keccak256("salt");
        address first = factory.createForceDeallocationEnterGate(address(this), address(this), false, false, preSalt);

        address caller = makeAddr("otherCaller");
        vm.prank(caller);
        address second = factory.createForceDeallocationEnterGate(address(this), address(this), false, false, preSalt);

        assertNotEq(first, second);
    }

    function testCreateForceDeallocationEnterGateEvent() public {
        bytes32 preSalt = keccak256("salt");
        vm.recordLogs();
        address created = factory.createForceDeallocationEnterGate(address(this), address(this), true, false, preSalt);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 eventSignature =
            keccak256("CreateForceDeallocationEnterGate(address,address,address,address,bool,bool,bytes32)");
        bool eventFound;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(factory) && logs[i].topics[0] == eventSignature
                    && logs[i].topics[1] == bytes32(uint256(uint160(address(this))))
                    && logs[i].topics[2] == bytes32(uint256(uint160(created)))
            ) {
                (address creditRoleSetter, address debtRoleSetter, bool creditOpen, bool debtOpen, bytes32 salt) =
                    abi.decode(logs[i].data, (address, address, bool, bool, bytes32));
                eventFound = creditRoleSetter == address(this) && debtRoleSetter == address(this) && creditOpen
                    && !debtOpen && salt == preSalt;
            }
        }

        assertTrue(eventFound);
    }
}

contract ForceDeallocationEnterGateTransientPermissionTest is Test {
    address internal midnight = makeAddr("midnight");
    address internal adapterFactory = makeAddr("adapterFactory");
    address internal adapter = makeAddr("adapter");
    address internal user = makeAddr("user");
    ForceDeallocationEnterGate internal gate;

    function setUp() public {
        ERC20Mock vault = new ERC20Mock(18);
        gate = new ForceDeallocationEnterGate(midnight, address(this), address(this), false, false);
        gate.addAdapterFactory(adapterFactory);
        vm.mockCall(
            adapterFactory, abi.encodeCall(IMidnightAdapterFactory.isMidnightAdapter, (adapter)), abi.encode(true)
        );
        vm.mockCall(
            adapterFactory, abi.encodeCall(IMidnightAdapterFactory.isMidnightAdapter, (user)), abi.encode(false)
        );
        vm.mockCall(adapter, abi.encodeCall(IMidnightAdapterBase.parentVault, ()), abi.encode(address(vault)));
        deal(address(vault), user, 1);
        gate.transientAllowIncreaseCredit(user, adapter, adapterFactory);
    }

    function testTransientPermissionIsClearedAfterTransaction() public view {
        assertEq(gate.transientAdapter(user), address(0));
        assertFalse(gate.canIncreaseCredit(user));
    }
}
