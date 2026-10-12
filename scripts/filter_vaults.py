#!/usr/bin/env python3
# Reads the scripts/rank_vaults_<chain>.json files of rank_vaults.py and filters out vaults that have
# allowance > 0.99 * max_uint AND total_assets * 10**EXPONENT < allowance, where allowance is the one of the adapter to the parent vault.
# Prints the kept vaults and the highest exponent for which every vault is still filtered out.
# Usage: python3 scripts/filter_vaults.py
import json
import os

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

EXPONENT = 12
MAX_UINT = 2**256 - 1

book = json.load(open("address-book.json"))["chains"]
for line in open("scripts/untested_chains.txt"):
    del book[line.split()[0]]

rows = []
for chain in book:
    state = json.load(open(f"scripts/rank_vaults_{chain}.json"))
    print(f"Chain {chain}: {state['covered']}/{len(state['vaults'])} vaults covered, {len(state['rows'])} with a MorphoMarketV1AdapterV2")
    rows += state["rows"]

# rows are [ratio, chain, vault, adapter, total_assets, allowance]
kept = [row for row in rows if not (row[5] > 0.99 * MAX_UINT and row[4] * 10**EXPONENT < row[5])]
print()
print(f"{len(rows)} vaults with a MorphoMarketV1AdapterV2, {len(rows) - len(kept)} filtered out, {len(kept)} kept")
print("ratio chain vault adapter totalAssets allowance")
for row in sorted(kept, reverse=True):
    print(*row)

exponent = 0
while all(row[4] * 10 ** (exponent + 1) < row[5] for row in rows if row[4] > 0 and row[5] > 0.99 * MAX_UINT):
    exponent += 1
binding = max((row for row in rows if row[5] > 0.99 * MAX_UINT), key=lambda row: row[4] / row[5])
print()
print(f"highest exponent filtering out everything: {exponent}, binding vault: chain {binding[1]} {binding[2]} totalAssets {binding[4]} allowance {binding[5]}")
