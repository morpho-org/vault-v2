#!/usr/bin/env python3
# Ranks Ethereum VaultV2s having a MorphoMarketV1AdapterV2 by totalAssets / allowance(adapter -> vault), descending.
# Usage: ETH_RPC_URL=<rpc> python3 rank_vaults.py
# Writes the ranking to rank_vaults.json every 50 vaults and at the end.
import json
import subprocess

FACTORY = "0xA1D94F746dEfa1928926b84fB2596c06926C0405"
ADAPTER_FACTORY = "0x32BB1c0D48D8b1B3363e86eeB9A0300BAd61ccc1"
FACTORY_BLOCK = 23375073


def cast(*args):
    return subprocess.run(["cast", *args], capture_output=True, text=True, check=True).stdout.strip()


print("Fetching CreateVaultV2 logs...")
logs = json.loads(cast("logs", "--json", "--from-block", str(FACTORY_BLOCK), "--address", FACTORY,
                       "CreateVaultV2(address indexed owner, address indexed asset, bytes32 salt, address indexed newVaultV2)"))
vaults = ["0x" + log["topics"][3][-40:] for log in logs]
print(f"Found {len(vaults)} vaults")

rows = []
for i, vault in enumerate(vaults):
    print(f"[{i + 1}/{len(vaults)}] {vault}: ", end="", flush=True)
    adapter = cast("call", ADAPTER_FACTORY, "morphoMarketV1AdapterV2(address)(address)", vault)
    if adapter == "0x0000000000000000000000000000000000000000" or cast("call", vault, "isAdapter(address)(bool)", adapter) != "true":
        print("no MorphoMarketV1AdapterV2")
    else:
        asset = cast("call", vault, "asset()(address)")
        total_assets = int(cast("call", vault, "totalAssets()(uint256)").split()[0])
        allowance = int(cast("call", asset, "allowance(address,address)(uint256)", adapter, vault).split()[0])
        print(f"adapter {adapter}, totalAssets {total_assets}, allowance {allowance}")
        rows.append((total_assets / allowance, vault, adapter, total_assets, allowance))
    if (i + 1) % 50 == 0:
        json.dump({"covered": i + 1, "total": len(vaults), "rows": sorted(rows, reverse=True)}, open("rank_vaults.json", "w"))

rows.sort(reverse=True)
json.dump({"covered": len(vaults), "total": len(vaults), "rows": rows}, open("rank_vaults.json", "w"))
print()
print(f"{len(vaults)} vaults, {len(rows)} with a MorphoMarketV1AdapterV2")
print("ratio vault adapter totalAssets allowance")
for row in rows:
    print(*row)
