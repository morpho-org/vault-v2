// SPDX-License-Identifier: GPL-2.0-or-later

using MiniERC20 as asset;
using VaultV2 as vault;

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function totalAssets() external returns (uint);
    function totalAllocation() external returns (uint) envfree;
    function MiniERC20.balanceOf(address) external returns (uint256) envfree;
}

invariant realAssetsApproxAtLeastTotalAssets(env e)
    vault.totalAssets(e) <= vault.totalAllocation() + asset.balanceOf(vault)
    filtered {
        f -> f.contract == vault
    } {
        preserved deposit(uint assets, address onBehalf) with (env e2) {
            require e2.msg.sender != vault;
        }

        preserved mint(uint shares, address onBehalf) with (env e2) {
            require e2.msg.sender != vault;
        }
    }
