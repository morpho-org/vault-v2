#!/usr/bin/env python3
# Ranks VaultV2s having a MorphoMarketV1AdapterV2, on every chain of address-book.json, by totalAssets / allowance(adapter -> vault), descending.
# Usage: ALCHEMY_KEY=<key> python3 scripts/rank_vaults.py
# RPCs are the [rpc_endpoints] aliases of foundry.toml (chain id -> url).
# State (per chain: vaults, number covered, ranking) is saved to rank_vaults.json every 50 vaults. Rerunning resumes from it; delete the file to start over.
import json
import os
import subprocess

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def cast(chain, *args):
    return subprocess.run(["cast", *args, "--rpc-url", chain], capture_output=True, text=True, check=True).stdout.strip()


book = json.load(open("address-book.json"))["chains"]
state = json.load(open("rank_vaults.json")) if os.path.exists("rank_vaults.json") else {}

for chain in book:
    FACTORY = book[chain]["output"]["VaultV2Factory"]
    ADAPTER_FACTORY = book[chain]["output"]["MorphoMarketV1AdapterV2Factory"]
    if chain in state:
        print(f"Chain {chain}: resuming from rank_vaults.json, {state[chain]['covered']}/{len(state[chain]['vaults'])} vaults covered")
    else:
        print(f"Chain {chain}: fetching CreateVaultV2 logs...")
        logs = json.loads(cast(chain, "logs", "--json", "--from-block", "0", "--address", FACTORY,
                               "CreateVaultV2(address indexed owner, address indexed asset, bytes32 salt, address indexed newVaultV2)"))
        state[chain] = {"vaults": ["0x" + log["topics"][3][-40:] for log in logs], "covered": 0, "rows": []}
        print(f"Chain {chain}: found {len(state[chain]['vaults'])} vaults")
        json.dump(state, open("rank_vaults.json", "w"))

    vaults, rows = state[chain]["vaults"], state[chain]["rows"]
    for i in range(state[chain]["covered"], len(vaults)):
        vault = vaults[i]
        print(f"[{chain} {i + 1}/{len(vaults)}] {vault}: ", end="", flush=True)
        adapter = cast(chain, "call", ADAPTER_FACTORY, "morphoMarketV1AdapterV2(address)(address)", vault)
        if adapter == "0x0000000000000000000000000000000000000000" or cast(chain, "call", vault, "isAdapter(address)(bool)", adapter) != "true":
            print("no MorphoMarketV1AdapterV2")
        else:
            asset = cast(chain, "call", vault, "asset()(address)")
            total_assets = int(cast(chain, "call", vault, "totalAssets()(uint256)").split()[0])
            allowance = int(cast(chain, "call", asset, "allowance(address,address)(uint256)", adapter, vault).split()[0])
            print(f"adapter {adapter}, totalAssets {total_assets}, allowance {allowance}")
            rows.append([total_assets / allowance, chain, vault, adapter, total_assets, allowance])
        if (i + 1) % 50 == 0:
            state[chain]["covered"] = i + 1
            json.dump(state, open("rank_vaults.json", "w"))
    state[chain]["covered"] = len(vaults)
    json.dump(state, open("rank_vaults.json", "w"))

rows = sorted((row for chain in state for row in state[chain]["rows"]), reverse=True)
print()
print(f"{sum(len(state[chain]['vaults']) for chain in state)} vaults on {len(state)} chains, {len(rows)} with a MorphoMarketV1AdapterV2")
print("ratio chain vault adapter totalAssets allowance")
for row in rows:
    print(*row)
