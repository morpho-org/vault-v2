#!/usr/bin/env python3
# Ranks VaultV2s having a MorphoMarketV1AdapterV2, on every chain of address-book.json, by totalAssets / allowance(adapter -> vault), descending.
# Usage: ALCHEMY_KEY=<key> python3 scripts/rank_vaults.py
# RPCs are the [rpc_endpoints] aliases of foundry.toml (chain id -> url). Chains run in parallel, one thread each.
# State (vaults, number covered, ranking) is saved to scripts/rank_vaults_<chain>.json every 50 vaults. Rerunning resumes from it; delete the file to start over.
import json
import os
import subprocess
from concurrent.futures import ThreadPoolExecutor

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def cast(chain, *args):
    return subprocess.run(["cast", *args, "--rpc-url", chain], capture_output=True, text=True, check=True).stdout.strip()


def run(chain):
    FACTORY = book[chain]["output"]["VaultV2Factory"]
    ADAPTER_FACTORY = book[chain]["output"]["MorphoMarketV1AdapterV2Factory"]
    file = f"scripts/rank_vaults_{chain}.json"
    if os.path.exists(file):
        state = json.load(open(file))
        print(f"Chain {chain}: resuming from {file}, {state['covered']}/{len(state['vaults'])} vaults covered")
    else:
        print(f"Chain {chain}: fetching CreateVaultV2 logs...")
        logs = json.loads(cast(chain, "logs", "--json", "--from-block", "0", "--address", FACTORY,
                               "CreateVaultV2(address indexed owner, address indexed asset, bytes32 salt, address indexed newVaultV2)"))
        state = {"vaults": ["0x" + log["topics"][3][-40:] for log in logs], "covered": 0, "rows": []}
        print(f"Chain {chain}: found {len(state['vaults'])} vaults")
        json.dump(state, open(file, "w"))

    vaults, rows = state["vaults"], state["rows"]
    for i in range(state["covered"], len(vaults)):
        vault = vaults[i]
        adapter = cast(chain, "call", ADAPTER_FACTORY, "morphoMarketV1AdapterV2(address)(address)", vault)
        if adapter == "0x0000000000000000000000000000000000000000" or cast(chain, "call", vault, "isAdapter(address)(bool)", adapter) != "true":
            print(f"[{chain} {i + 1}/{len(vaults)}] {vault}: no MorphoMarketV1AdapterV2")
        else:
            asset = cast(chain, "call", vault, "asset()(address)")
            total_assets = int(cast(chain, "call", vault, "totalAssets()(uint256)").split()[0])
            allowance = int(cast(chain, "call", asset, "allowance(address,address)(uint256)", adapter, vault).split()[0])
            print(f"[{chain} {i + 1}/{len(vaults)}] {vault}: adapter {adapter}, totalAssets {total_assets}, allowance {allowance}")
            rows.append([total_assets / allowance, chain, vault, adapter, total_assets, allowance])
        if (i + 1) % 50 == 0:
            state["covered"] = i + 1
            json.dump(state, open(file, "w"))
    state["covered"] = len(vaults)
    json.dump(state, open(file, "w"))
    return state


book = json.load(open("address-book.json"))["chains"]
with ThreadPoolExecutor(len(book)) as executor:
    futures = {chain: executor.submit(run, chain) for chain in book}
states = {}
for chain, future in futures.items():
    try:
        states[chain] = future.result()
    except Exception as e:
        print(f"Chain {chain}: FAILED, {e}")

rows = sorted((row for state in states.values() for row in state["rows"]), reverse=True)
print()
print(f"{sum(len(state['vaults']) for state in states.values())} vaults on {len(states)}/{len(book)} chains, {len(rows)} with a MorphoMarketV1AdapterV2")
print("ratio chain vault adapter totalAssets allowance")
for row in rows:
    print(*row)
