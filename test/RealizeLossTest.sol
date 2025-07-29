// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract RealizeLossTest is BaseTest {
    AdapterMock internal adapter;
    uint256 MAX_TEST_AMOUNT;

    function setUp() public override {
        super.setUp();

        MAX_TEST_AMOUNT = 10 ** min(18 + underlyingToken.decimals(), 36);

        adapter = new AdapterMock(address(vault));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(adapter), true)));
        vault.setIsAdapter(address(adapter), true);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);

        increaseAbsoluteCap(expectedIdData[0], type(uint128).max);
        increaseAbsoluteCap(expectedIdData[1], type(uint128).max);
        increaseRelativeCap(expectedIdData[0], WAD);
        increaseRelativeCap(expectedIdData[1], WAD);
    }
}
