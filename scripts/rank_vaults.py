#!/usr/bin/env python3
# Ranks VaultV2s having a MorphoMarketV1AdapterV2, on every chain of address-book.json except those of scripts/untested_chains.txt (one chain id per line, a reason may follow), by totalAssets / allowance(adapter -> vault), descending.
# Usage: ALCHEMY_KEY=<key> python3 scripts/rank_vaults.py
# RPCs are the [rpc_endpoints] aliases of foundry.toml (chain id -> url). Chains run in parallel, one thread each.
# State (vaults, number covered, ranking) is saved to scripts/rank_vaults_<chain>.json every 50 vaults. Rerunning resumes from it; delete the file to start over.
import json
import os
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# eth_getLogs block range caps of the RPCs (default 2M).
CHUNK = {"484": 100_000, "1135": 100_000, "16661": 100_000, "714": 100_000}
CHUNK |= {chain: 10_000 for chain in ("4114", "685689", "1672", "4326", "1868", "130", "57073", "9745", "988", "25")}
CHUNK["4153"] = 100_000
CHUNK["534352"] = 100_000


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
        latest = int(cast(chain, "block-number"))
        lo, hi = 0, latest
        while lo < hi:  # binary search of the factory deployment block
            mid = (lo + hi) // 2
            if cast(chain, "code", FACTORY, "--block", str(mid)) == "0x":
                lo = mid + 1
            else:
                hi = mid
        logs = []
        print(f"Chain {chain}: factory deployed at block {lo}, fetching logs up to block {latest} in chunks of {CHUNK.get(chain, 2_000_000)} blocks")
        for block in range(lo, latest + 1, CHUNK.get(chain, 2_000_000)):
            print(f"Chain {chain}: logs from block {block}, {len(logs)} vaults so far")
            logs += json.loads(cast(chain, "logs", "--json", "--from-block", str(block), "--to-block", str(min(block + CHUNK.get(chain, 2_000_000) - 1, latest)), "--address", FACTORY,
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
for line in open("scripts/untested_chains.txt"):
    del book[line.split()[0]]
states = {}
with ThreadPoolExecutor(len(book)) as executor:
    futures = {executor.submit(run, chain): chain for chain in book}
    for future in as_completed(futures):
        try:
            states[futures[future]] = future.result()
        except Exception as e:
            print(f"Chain {futures[future]}: FAILED, {e} {getattr(e, 'stdout', '')}{getattr(e, 'stderr', '')}")
