#!/usr/bin/env python3
"""Measure FlashExit end-to-end latency from on-chain timestamps.

Reads the three legs of a demo run and prints a latency table:
  1. Trigger Swap tx on Base Sepolia (block timestamp).
  2. OrderTriggered event on Lasna (block timestamp).
  3. ExitExecuted event on Unichain Sepolia (block timestamp).

Usage:
  python3 script/measure-latency.py --trigger-tx 0x... --rc 0x... --executor 0x... --order-id 0
"""
import argparse
import json
import sys
import urllib.request

BASE_RPC = "https://sepolia.base.org"
UNI_RPC = "https://sepolia.unichain.org"
LASNA_RPC = "https://lasna-rpc.rnk.dev/"

ORDER_TRIGGERED = "0x" + "00"  # placeholder, replaced below (keccak of event sig)


def keccak_topic(sig: str) -> str:
    # eth_hash without dependency: use sha3 via hashlib (keccak-256 != sha3-256,
    # so shell out to cast instead if available).
    import subprocess
    out = subprocess.run(
        ["cast", "keccak", sig], capture_output=True, text=True, check=True
    ).stdout.strip()
    return out


def rpc(url: str, method: str, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(url, data=body, headers={
        "Content-Type": "application/json",
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
    })
    with urllib.request.urlopen(req, timeout=60) as r:
        resp = json.load(r)
    if "error" in resp:
        raise RuntimeError(f"{url} {method}: {resp['error']}")
    return resp["result"]


def tx_block_time(rpc_url: str, tx_hash: str) -> int:
    tx = rpc(rpc_url, "eth_getTransactionByHash", [tx_hash])
    if not tx or not tx.get("blockNumber"):
        raise RuntimeError(f"tx {tx_hash} not mined yet")
    block = rpc(rpc_url, "eth_getBlockByNumber", [tx["blockNumber"], False])
    return int(block["timestamp"], 16), int(tx["blockNumber"], 16)


def find_event_time(rpc_url: str, address: str, topic0: str, topic1: str | None, from_block: int):
    topics = [topic0] + ([topic1] if topic1 else [])
    logs = rpc(rpc_url, "eth_getLogs", [{
        "address": address, "topics": topics,
        "fromBlock": hex(from_block), "toBlock": "latest",
    }])
    if not logs:
        return None, None
    log = logs[0]
    block = rpc(rpc_url, "eth_getBlockByNumber", [log["blockNumber"], False])
    return int(block["timestamp"], 16), int(log["blockNumber"], 16)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--trigger-tx", required=True)
    ap.add_argument("--rc", required=True, help="FlashExitReactive address on Lasna")
    ap.add_argument("--executor", required=True, help="FlashExitExecutor on Unichain Sepolia")
    ap.add_argument("--order-id", type=int, default=0)
    ap.add_argument("--from-block", type=int, default=0)
    ap.add_argument("--from-block-lasna", type=int, default=None,
                    help="fromBlock for the Lasna query (defaults to --from-block)")
    ap.add_argument("--from-block-uni", type=int, default=None,
                    help="fromBlock for the Unichain query (defaults to --from-block)")
    args = ap.parse_args()
    from_lasna = args.from_block_lasna if args.from_block_lasna is not None else args.from_block
    from_uni = args.from_block_uni if args.from_block_uni is not None else args.from_block

    order_topic = "0x" + f"{args.order_id:064x}"
    trig_topic = keccak_topic("OrderTriggered(uint256,bytes32,uint256)")
    exit_topic = keccak_topic("ExitExecuted(uint256,address,address,address,uint256,uint256)")

    t0, b0 = tx_block_time(BASE_RPC, args.trigger_tx)
    t1, b1 = find_event_time(LASNA_RPC, args.rc, trig_topic, order_topic, from_lasna)
    t2, b2 = find_event_time(UNI_RPC, args.executor, exit_topic, order_topic, from_uni)

    print(f"Trigger swap mined (Base Sepolia block {b0}):      {t0}")
    if t1 is None:
        print("OrderTriggered on Lasna: NOT FOUND (callback may still be in flight)")
        sys.exit(2)
    print(f"OrderTriggered (Lasna block {b1}):                  {t1}  (+{t1 - t0}s)")
    if t2 is None:
        print("ExitExecuted on Unichain: NOT FOUND (callback may still be in flight)")
        sys.exit(2)
    print(f"ExitExecuted (Unichain Sepolia block {b2}):         {t2}  (+{t2 - t1}s)")
    print(f"End-to-end (trigger -> exit):                      {t2 - t0}s")


if __name__ == "__main__":
    main()
