// Spdx-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function Utils.wad() external returns (uint256) envfree;
}

// Check that no function can break the cap limit, except:
// - for the fact that the total asset can decrease when accruing interest;
// - for exit functions (withdraw, redeem & forceDeallocate);
// - for decreaseRelativeCap;
// - for deallocate (it can actually increase allocations because of interests, while allocate would revert if interest makes the allocation exceed the cap)
rule relativeCapValidity(env e, method f, calldataarg args)
filtered {
    f -> f.selector != sig:withdraw(uint256, address, address).selector &&
         f.selector != sig:redeem(uint256, address, address).selector &&
         f.selector != sig:forceDeallocate(address, bytes, uint256, address).selector &&
         f.selector != sig:decreaseRelativeCap(bytes, uint256).selector &&
         f.selector != sig:deallocate(address, bytes, uint256).selector
} {
    bytes32 id;
    // Tracks the firstTotalAssets value after calling f.
    uint256 firstTotalAssetsAfter;

    require currentContract.caps[id].relativeCap < Utils.wad() =>
    currentContract.caps[id].allocation <= (firstTotalAssetsAfter * currentContract.caps[id].relativeCap) / Utils.wad();

    f(e, args);

    // Note that firstTotalAssets is not reset after f, because in CVL functions calls are not isolated in different transactions.
    require firstTotalAssetsAfter == currentContract.firstTotalAssets;

    assert currentContract.caps[id].relativeCap < Utils.wad() =>
    currentContract.caps[id].allocation <= (firstTotalAssetsAfter * currentContract.caps[id].relativeCap) / Utils.wad();
}
