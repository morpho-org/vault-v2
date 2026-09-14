// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

// Compares the gas of computing vaultBuffer in MidnightAdapter.onSell two ways:
//   current:   vault.totalAssets()          (loops over adapters again when firstTotalAssets == 0)
//   proposed:  min(real, _totalAssets + _totalAssets * elapsed * maxRate / WAD) from 3 getters
// Not isolated: in the real flow the calls are nested inside onSell, not top-level transactions.
contract VaultBufferGasTest is BaseTest {
    using MathLib for uint256;

    function setUp() public override {
        super.setUp();
        vm.prank(allocator);
        vault.setMaxRate(MAX_MAX_RATE);
        writeTotalAssets(0.5e18);
    }

    function run(bool accrueFirst) internal {
        for (uint256 n = 1; n <= 10; n++) {
            AdapterMock adapter = new AdapterMock(address(vault));
            adapter.setInterest(1e18);
            vm.prank(curator);
            vault.submit(abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
            vault.addAdapter(address(adapter));
            vm.warp(block.timestamp + 1 days);
            if (accrueFirst) vault.accrueInterest();
            assertEq(vault.firstTotalAssets() != 0, accrueFirst);

            // Same prelude as onSell: warms vault, adapters, and asset.
            uint256 real = underlyingToken.balanceOf(address(vault));
            uint256 adaptersLength = vault.adaptersLength();
            for (uint256 i = 0; i < adaptersLength; i++) {
                real += IAdapter(vault.adapters(i)).realAssets();
            }
            assertEq(adaptersLength, n);

            // Without accrual in the tx, the vault's _totalAssets/lastUpdate/maxRate, performanceFee and
            // managementFee slots are cold in onSell. The loop above warmed them for iterations n > 1.
            if (!accrueFirst) coolVaultSlots();
            uint256 gCurrent = gasleft();
            uint256 bufCurrent = real.zeroFloorSub(vault.totalAssets());
            gCurrent = gCurrent - gasleft();

            if (!accrueFirst) coolVaultSlots();
            uint256 gProposed = gasleft();
            uint256 stored = vault._totalAssets();
            uint256 maxTotalAssets =
                stored + (stored * (block.timestamp - vault.lastUpdate())).mulDivDown(vault.maxRate(), WAD);
            uint256 bufProposed = real.zeroFloorSub(MathLib.min(real, maxTotalAssets));
            gProposed = gProposed - gasleft();

            assertEq(bufCurrent, bufProposed);
            assertGt(bufCurrent, 0);
            console.log("adapters %d: current %d, proposed %d", n, gCurrent, gProposed);
        }
    }

    function coolVaultSlots() internal {
        vm.coolSlot(address(vault), bytes32(uint256(15)));
        vm.coolSlot(address(vault), bytes32(uint256(25)));
        vm.coolSlot(address(vault), bytes32(uint256(26)));
    }

    /// forge-config: default.isolate = false
    function testGasNoAccrual() public {
        run(false);
    }

    /// forge-config: default.isolate = false
    function testGasAfterAccrual() public {
        run(true);
    }
}
