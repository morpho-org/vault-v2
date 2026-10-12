#!/usr/bin/env python3
# Ranks Ethereum VaultV2s having a MorphoMarketV1AdapterV2 by totalAssets / allowance(adapter -> vault), descending.
# Usage: ETH_RPC_URL=<rpc> python3 rank_vaults.py
import json
import subprocess

FACTORY = "0xA1D94F746dEfa1928926b84fB2596c06926C0405"
ADAPTER_FACTORY = "0x32BB1c0D48D8b1B3363e86eeB9A0300BAd61ccc1"
FACTORY_BLOCK = 23375073


def cast(*args):
    return subprocess.run(["cast", *args], capture_output=True, text=True, check=True).stdout.strip()


logs = json.loads(cast("logs", "--json", "--from-block", str(FACTORY_BLOCK), "--address", FACTORY,
                       "CreateVaultV2(address indexed owner, address indexed asset, bytes32 salt, address indexed newVaultV2)"))
vaults = ["0x" + log["topics"][3][-40:] for log in logs]

rows = []
for vault in vaults:
    adapter = cast("call", ADAPTER_FACTORY, "morphoMarketV1AdapterV2(address)(address)", vault)
    if adapter == "0x0000000000000000000000000000000000000000" or cast("call", vault, "isAdapter(address)(bool)", adapter) != "true":
        continue
    asset = cast("call", vault, "asset()(address)")
    total_assets = int(cast("call", vault, "totalAssets()(uint256)").split()[0])
    allowance = int(cast("call", asset, "allowance(address,address)(uint256)", adapter, vault).split()[0])
    rows.append((total_assets / allowance, vault, adapter, total_assets, allowance))

rows.sort(reverse=True)
print(f"{len(vaults)} vaults, {len(rows)} with a MorphoMarketV1AdapterV2")
print("ratio vault adapter totalAssets allowance")
for row in rows:
    print(*row)
