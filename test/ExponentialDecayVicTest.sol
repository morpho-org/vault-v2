// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
// import "../src/vic/ManualVic.sol";
// import "../src/vic/ManualVicFactory.sol";
import "./mocks/VaultV2Mock.sol";
import "../src/vic/ExponentialDecayVic.sol";
// import "../src/vic/interfaces/IManualVic.sol";
// import "../src/vic/interfaces/IManualVicFactory.sol";
import {stdStorage, StdStorage} from "../lib/forge-std/src/Test.sol";

contract ExponentialDecayVicTest is Test {
    using stdStorage for StdStorage;

    ExponentialDecayVic public vic;
    IVaultV2 public vault;
    address public curator;
    address public allocator;
    address public sentinel;

    function setUp() public {
        curator = makeAddr("curator");
        allocator = makeAddr("allocator");
        sentinel = makeAddr("sentinel");
        vault = IVaultV2(address(new VaultV2Mock(address(0), address(0), curator, allocator, sentinel)));
        vic = new ExponentialDecayVic(address(vault));
    }

    function testPings(uint256 currentRate, uint256 totalAssets, uint256 halfLife, uint256 targetIPS) public {
        currentRate = bound(currentRate, uint256(0.001e18) / 365 days, uint256(2e18) / 365 days);
        totalAssets = bound(totalAssets, 1e8, 1e36);
        halfLife = bound(halfLife, 1, 1 hours);
        targetIPS = bound(targetIPS, 0, totalAssets * 2 / 365 days);

        uint256 targetRate = targetIPS * WAD / totalAssets;

        console.log("setup");
        console.log("target ips   %e", targetIPS);
        console.log("current rate %e", currentRate);
        console.log("target rate  %e", targetRate);
        console.log("totalAssets  %e", totalAssets);
        console.log("halfLife     %s", halfLife);

        vm.prank(curator);
        vic.setDecayHalfLife(halfLife);

        vm.prank(curator);
        vic.increaseMaxInterestPerSecond(type(uint256).max / WAD);

        vm.prank(allocator);
        vic.setTargetInterestPerSecond(targetIPS);

        stdstore.target(address(vic)).sig("currentRate()").checked_write(currentRate);

        vm.prank(address(vault));
        vic.interestPerSecond(totalAssets, halfLife);

        uint256 expectedRate;
        if (targetRate > currentRate) {
            expectedRate = currentRate + (targetRate - currentRate) / 2;
        } else {
            expectedRate = currentRate - (currentRate - targetRate) / 2;
        }

        console.log("------------");
        console.log("new cur %e", vic.currentRate());

        assertApproxEqRel(vic.currentRate(), expectedRate, 0.01e18);
    }
}
