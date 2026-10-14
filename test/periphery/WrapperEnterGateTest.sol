// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IEnterGate} from "../../lib/midnight/src/interfaces/IGate.sol";
import {IMidnight, Market} from "../../lib/midnight/src/interfaces/IMidnight.sol";
import {IMidnightAdapter} from "../../src/adapters/interfaces/IMidnightAdapter.sol";
import {IVaultV2} from "../../src/interfaces/IVaultV2.sol";
import {IVaultV2Factory} from "../../src/interfaces/IVaultV2Factory.sol";
import {WrapperEnterGate} from "../../src/periphery/gates/WrapperEnterGate.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {EnterGateMock} from "../mocks/EnterGateMock.sol";

/// forge-config: default.isolate = false
contract WrapperEnterGateTest is Test {
    ERC20Mock internal vault;
    EnterGateMock internal gate;
    address internal vaultV2Factory = makeAddr("vaultV2Factory");
    WrapperEnterGate internal wrapper;
    address internal midnight = makeAddr("midnight");
    bytes32 internal constant marketId = keccak256("market");
    address internal adapter = makeAddr("adapter");
    address internal depositor = makeAddr("depositor");
    address internal recipient = makeAddr("recipient");

    function setUp() public {
        vault = new ERC20Mock(18);
        gate = new EnterGateMock();
        vm.mockCall(adapter, abi.encodeWithSignature("parentVault()"), abi.encode(address(vault)));
        vm.mockCall(vaultV2Factory, abi.encodeCall(IVaultV2Factory.isVaultV2, (address(vault))), abi.encode(true));
        vm.mockCall(address(vault), abi.encodeCall(IVaultV2.isAdapter, (adapter)), abi.encode(true));
        wrapper = new WrapperEnterGate(midnight, address(gate), vaultV2Factory);
        vm.mockCall(adapter, abi.encodeWithSignature("forceDeallocatingMarketId()"), abi.encode(marketId));
        Market memory market;
        market.enterGate = address(wrapper);
        vm.mockCall(midnight, abi.encodeCall(IMidnight.toMarket, (marketId)), abi.encode(market));
        vm.mockCall(midnight, abi.encodeCall(IMidnight.credit, (marketId, adapter)), abi.encode(uint128(1)));
    }

    function testConstructor() public view {
        assertEq(wrapper.midnight(), midnight);
        assertEq(wrapper.gate(), address(gate));
        assertEq(wrapper.vaultV2Factory(), vaultV2Factory);
    }

    function testAdapterCreditForwarded(bool allowed) public {
        gate.setCanIncreaseCredit(adapter, allowed);
        assertEq(wrapper.canIncreaseCredit(adapter), allowed);
    }

    function testTransientAllowIncreaseCredit(address caller, uint256 shares) public {
        shares = bound(shares, 1, type(uint128).max);
        deal(address(vault), depositor, shares);
        assertFalse(wrapper.canIncreaseCredit(depositor));
        vm.prank(caller);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertEq(wrapper.transientAdapter(depositor), adapter);
        assertTrue(wrapper.isTransientlyAllowed(depositor));
        assertTrue(wrapper.canIncreaseCredit(depositor));
        assertFalse(wrapper.isTransientlyAllowed(recipient));
    }

    /// forge-config: default.isolate = true
    function testAuthorizationClearedAfterTransaction() public {
        deal(address(vault), depositor, 1);
        this.allowAndCheckUser();
        assertFalse(wrapper.isTransientlyAllowed(depositor));
        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    function allowAndCheckUser() external {
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertTrue(wrapper.isTransientlyAllowed(depositor));
        assertTrue(wrapper.canIncreaseCredit(depositor));
    }

    function testTransientAllowIncreaseCreditRequiresShares() public {
        vm.expectRevert(WrapperEnterGate.Unauthorized.selector);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertFalse(wrapper.isTransientlyAllowed(depositor));
    }

    function testTransientAllowIncreaseCreditUsesParentVault() public {
        ERC20Mock otherVault = new ERC20Mock(18);
        vm.mockCall(vaultV2Factory, abi.encodeCall(IVaultV2Factory.isVaultV2, (address(otherVault))), abi.encode(true));
        vm.mockCall(address(otherVault), abi.encodeCall(IVaultV2.isAdapter, (adapter)), abi.encode(true));
        deal(address(otherVault), depositor, 1);
        vm.expectRevert(WrapperEnterGate.Unauthorized.selector);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertFalse(wrapper.isTransientlyAllowed(depositor));

        vm.mockCall(adapter, abi.encodeWithSignature("parentVault()"), abi.encode(address(otherVault)));
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertTrue(wrapper.isTransientlyAllowed(depositor));
    }

    function testRequiresParentVaultCode() public {
        address noCodeAdapter = makeAddr("noCodeAdapter");
        deal(address(vault), depositor, 1);
        vm.expectRevert(WrapperEnterGate.Unauthorized.selector);
        wrapper.transientAllowIncreaseCredit(depositor, noCodeAdapter);
        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    function testRequiresParentVaultSuccess() public {
        deal(address(vault), depositor, 1);
        vm.mockCallRevert(adapter, abi.encodeWithSignature("parentVault()"), "parentVault reverted");
        vm.expectRevert(WrapperEnterGate.Unauthorized.selector);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    function testRequiresVaultFromFactory() public {
        deal(address(vault), depositor, 1);
        vm.mockCall(vaultV2Factory, abi.encodeCall(IVaultV2Factory.isVaultV2, (address(vault))), abi.encode(false));
        vm.expectRevert(WrapperEnterGate.Unauthorized.selector);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertFalse(wrapper.canIncreaseCredit(depositor));

        vm.mockCall(vaultV2Factory, abi.encodeCall(IVaultV2Factory.isVaultV2, (address(vault))), abi.encode(true));
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertTrue(wrapper.canIncreaseCredit(depositor));
    }

    function testRequiresAdapterEnabledInVault() public {
        deal(address(vault), depositor, 1);
        vm.mockCall(address(vault), abi.encodeCall(IVaultV2.isAdapter, (adapter)), abi.encode(false));
        vm.expectRevert(WrapperEnterGate.Unauthorized.selector);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertFalse(wrapper.canIncreaseCredit(depositor));

        vm.mockCall(address(vault), abi.encodeCall(IVaultV2.isAdapter, (adapter)), abi.encode(true));
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertTrue(wrapper.canIncreaseCredit(depositor));
    }

    function testAuthorizationRevertsWithCaller() public {
        deal(address(vault), depositor, 1);
        vm.expectRevert(bytes("reverted"));
        this.allowAndRevert();
        assertFalse(wrapper.isTransientlyAllowed(depositor));
        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    function allowAndRevert() external {
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        revert("reverted");
    }

    function testIsTransientlyAllowedRequiresMarketCredit(bool allowed) public {
        deal(address(vault), depositor, 1);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        vm.mockCall(midnight, abi.encodeCall(IMidnight.credit, (marketId, adapter)), abi.encode(uint128(0)));
        gate.setCanIncreaseCredit(depositor, allowed);
        assertFalse(wrapper.isTransientlyAllowed(depositor));
        assertEq(wrapper.canIncreaseCredit(depositor), allowed);
    }

    function testIsTransientlyAllowedRequiresForceDeallocatingMarket() public {
        deal(address(vault), depositor, 1);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        vm.mockCall(adapter, abi.encodeWithSignature("forceDeallocatingMarketId()"), abi.encode(bytes32(0)));
        gate.setCanIncreaseCredit(depositor, true);
        assertFalse(wrapper.isTransientlyAllowed(depositor));
        assertTrue(wrapper.canIncreaseCredit(depositor));
    }

    function testIsTransientlyAllowedRequiresMarketGate(address otherGate) public {
        vm.assume(otherGate != address(wrapper));
        deal(address(vault), depositor, 1);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        Market memory market;
        market.enterGate = otherGate;
        vm.mockCall(midnight, abi.encodeCall(IMidnight.toMarket, (marketId)), abi.encode(market));
        gate.setCanIncreaseCredit(depositor, true);
        assertFalse(wrapper.isTransientlyAllowed(depositor));
        assertTrue(wrapper.canIncreaseCredit(depositor));
    }

    function testMultipleVaults() public {
        ERC20Mock otherVault = new ERC20Mock(18);
        address otherAdapter = makeAddr("otherAdapter");
        vm.mockCall(otherAdapter, abi.encodeWithSignature("parentVault()"), abi.encode(address(otherVault)));
        vm.mockCall(vaultV2Factory, abi.encodeCall(IVaultV2Factory.isVaultV2, (address(otherVault))), abi.encode(true));
        vm.mockCall(address(otherVault), abi.encodeCall(IVaultV2.isAdapter, (otherAdapter)), abi.encode(true));
        vm.mockCall(otherAdapter, abi.encodeWithSignature("forceDeallocatingMarketId()"), abi.encode(marketId));
        vm.mockCall(midnight, abi.encodeCall(IMidnight.credit, (marketId, otherAdapter)), abi.encode(uint128(1)));
        deal(address(vault), depositor, 1);
        deal(address(otherVault), recipient, 1);

        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        wrapper.transientAllowIncreaseCredit(recipient, otherAdapter);
        assertTrue(wrapper.canIncreaseCredit(depositor));
        assertTrue(wrapper.canIncreaseCredit(recipient));
    }

    function testDepositorCreditBypassesGate(uint256 shares) public {
        shares = bound(shares, 1, type(uint128).max);
        deal(address(vault), depositor, shares);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        vm.mockCallRevert(address(gate), abi.encodeCall(IEnterGate.canIncreaseCredit, (depositor)), "gate reverted");

        assertTrue(wrapper.canIncreaseCredit(depositor));
    }

    function testCreditForwarded(address account, bool allowed) public {
        vm.assume(account != adapter);
        gate.setCanIncreaseCredit(account, allowed);
        gate.setCanIncreaseDebt(account, !allowed);

        vm.expectCall(address(gate), abi.encodeCall(IEnterGate.canIncreaseCredit, (account)));
        assertEq(wrapper.canIncreaseCredit(account), allowed);
    }

    function testCreditUsesAccountNotCaller() public {
        deal(address(vault), depositor, 1);
        vm.prank(recipient);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);

        vm.prank(depositor);
        assertFalse(wrapper.canIncreaseCredit(recipient));
        vm.prank(recipient);
        assertTrue(wrapper.canIncreaseCredit(depositor));
    }

    function testAuthorizationSurvivesShareTransfersWithinTransaction(uint256 shares) public {
        shares = bound(shares, 2, type(uint128).max);
        deal(address(vault), depositor, shares);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertTrue(wrapper.canIncreaseCredit(depositor));
        assertFalse(wrapper.canIncreaseCredit(recipient));

        vm.prank(depositor);
        vault.transfer(recipient, shares - 1);
        assertTrue(wrapper.canIncreaseCredit(depositor), "one share is enough");
        assertFalse(wrapper.canIncreaseCredit(recipient));
        wrapper.transientAllowIncreaseCredit(recipient, adapter);

        vm.prank(depositor);
        vault.transfer(recipient, 1);
        assertTrue(wrapper.canIncreaseCredit(depositor), "authorization retained until the end of the transaction");
        assertTrue(wrapper.canIncreaseCredit(recipient));
    }

    function testCreditDoesNotAcceptSharesOfAnotherVault(uint256 shares) public {
        shares = bound(shares, 1, type(uint128).max);
        ERC20Mock otherVault = new ERC20Mock(18);
        deal(address(otherVault), depositor, shares);

        vm.expectRevert(WrapperEnterGate.Unauthorized.selector);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        assertFalse(wrapper.canIncreaseCredit(depositor));
    }

    function testCreditBubblesGateRevert() public {
        vm.mockCallRevert(address(gate), abi.encodeCall(IEnterGate.canIncreaseCredit, (depositor)), "gate reverted");

        vm.expectRevert(bytes("gate reverted"));
        wrapper.canIncreaseCredit(depositor);
    }

    function testDebtForwarded(address account, uint256 shares, bool allowed) public {
        vm.assume(account != adapter);
        shares = bound(shares, 0, type(uint128).max);
        deal(address(vault), account, shares);
        if (shares > 0) wrapper.transientAllowIncreaseCredit(account, adapter);
        gate.setCanIncreaseDebt(account, allowed);
        gate.setCanIncreaseCredit(account, !allowed);

        vm.expectCall(address(gate), abi.encodeCall(IEnterGate.canIncreaseDebt, (account)));
        assertEq(wrapper.canIncreaseDebt(account), allowed);
    }

    function testAdapterDebtForwarded(bool allowed) public {
        gate.setCanIncreaseDebt(adapter, allowed);

        vm.expectCall(address(gate), abi.encodeCall(IEnterGate.canIncreaseDebt, (adapter)));
        assertEq(wrapper.canIncreaseDebt(adapter), allowed);
    }

    function testDebtBubblesGateRevertForDepositorAndAdapter(bool isAdapter) public {
        address account = isAdapter ? adapter : depositor;
        deal(address(vault), depositor, 1);
        wrapper.transientAllowIncreaseCredit(depositor, adapter);
        vm.mockCallRevert(address(gate), abi.encodeCall(IEnterGate.canIncreaseDebt, (account)), "gate reverted");

        vm.expectRevert(bytes("gate reverted"));
        wrapper.canIncreaseDebt(account);
    }
}
