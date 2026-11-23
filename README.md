# FlashExit

**Reactive Omni Buildathon — Track 1: Every Second Counts**

FlashExit is a cross-chain stop-loss / take-profit executor. A reactive contract on
**Lasna** watches Uniswap v4 `Swap` events on **Base Sepolia**; the moment a pool
price crosses a user's trigger, it fires a callback that executes the exit swap on
**Unichain Sepolia** — no keeper, no polling, no user online.

## How it works

```
User creates order (trigger price, minOut, deadline)
        │
        ▼
FlashExitReactive (Lasna) subscribes to Swap events of the pool
        │
Base Sepolia pool price crosses the trigger ──► Swap event
        │
        ▼
Reactive Network delivers the log to react()
        │
        ▼
Callback → FlashExitExecutor (Unichain Sepolia)
        │
        ▼
Exact-in v4 swap, proceeds sent straight to the user
```

- **Multi-order registry**: many orders per pool, each with its own trigger,
  direction (below = stop-loss, above = take-profit), minOut slippage guard and
  deadline. Expired orders are skipped, never executed.
- **Fires once**: an order is marked `Triggered` before the callback is requested,
  so a volatile pool cannot double-fire it.
- **Slippage protection**: the executor reverts the callback if the swap output
  is below `minOut`; the user's deposit stays untouched on a failed callback.
- **Pre-funded exits**: users deposit the token to sell into the executor first,
  so the callback needs no approval and no user interaction at trigger time.

## Contracts

| Contract | Chain | Address |
|---|---|---|
| `FlashExitReactive` | Lasna (5318007) | [`0x8626fd3711de3bcAebd891De1321c08eD6774bF3`](https://lasna.reactscan.net/address/0x8626fd3711de3bcAebd891De1321c08eD6774bF3) |
| `FlashExitExecutor` | Unichain Sepolia (1301) | [`0xA316777667B4b8c6f65C8D123e64F0cdbB9401E7`](https://sepolia.uniscan.xyz/address/0xA316777667B4b8c6f65C8D123e64F0cdbB9401E7) |
| FLASH / mUSD | Base Sepolia (84532) | [`0xd9392c1600f999e6FA91f265015f22b97AF2F149`](https://sepolia.basescan.org/address/0xd9392c1600f999e6FA91f265015f22b97AF2F149) / [`0x885A1Ef5Cc861D8b5F3938bcb35894d5B49AE906`](https://sepolia.basescan.org/address/0x885A1Ef5Cc861D8b5F3938bcb35894d5B49AE906) |
| FLASH / mUSD | Unichain Sepolia (1301) | [`0x8626fd3711de3bcAebd891De1321c08eD6774bF3`](https://sepolia.uniscan.xyz/address/0x8626fd3711de3bcAebd891De1321c08eD6774bF3) / [`0xd9392c1600f999e6FA91f265015f22b97AF2F149`](https://sepolia.uniscan.xyz/address/0xd9392c1600f999e6FA91f265015f22b97AF2F149) |
| FLASH/mUSD pool (3000 / 60) | Base Sepolia | `0xbf23a44b60b6776a8ffe4dc905d813e0fd00979ff3d27465f9dfdf45eacf841f` |
| FLASH/mUSD pool (3000 / 60) | Unichain Sepolia | `0x394d6bcddf140a1642bfc963dd0c81eae68198b54ef291c2ae39ed058afffdc9` |

Deployer: `0x86B9Ab19810dFbF33d264C04f880171707a8f3E3` (testnet only).

## Measured latency

Measured end to end on testnet: trigger swap on Base Sepolia → `OrderTriggered`
on Lasna → `ExitExecuted` on Unichain Sepolia (block timestamps, via
`script/measure-latency.py`). Per-leg splits carry ±1–2s of cross-chain
block-timestamp skew; the end-to-end totals are the reliable numbers.

| Run | Trigger → Lasna | Lasna → Unichain | Total |
|---|---|---|---|
| Stop-loss, order 2 (100 FLASH → 99.60 mUSD) | 0s | 3s | **3s** |
| Take-profit, order 3 (100 FLASH → 99.40 mUSD) | ~0s | ~2s | **2s** |

Proof (23 Nov 2026, all testnet):

- Order 2, stop-loss: trigger swap [`0xa0fdf250…`](https://sepolia.basescan.org/tx/0xa0fdf25093db423dec5e86e2af1c2177b5500e8431084bc21248cafd3676874e) (Base block 62741460) → react [`0x6f65176d…`](https://lasna.reactscan.net/tx/0x6f65176d3bbf347cc4f751f1179bf9a8d8a1c1d6902c705db5d3c1d32828ce8a) (Lasna block 9086812) → exit [`0xd31c19aa…`](https://sepolia.uniscan.xyz/tx/0xd31c19aa349548cd6b4812bff208e18131b948681bd3ca9ea04b39f85387fdcb) (Unichain block 68617735).
- Order 3, take-profit: trigger swap [`0xd98a58ee…`](https://sepolia.basescan.org/tx/0xd98a58eef3b44cce6165029a760d2d1647c4f2ca06a12027bb00da4ad02925d6) (Base block 62742619) → react [`0x9f27f73e…`](https://lasna.reactscan.net/tx/0x9f27f73e975d410b779afb10a5d78e605e2860ef7f7eb4e2cacc45397e6c7691) (Lasna block 9087030) → exit [`0xd798e10c…`](https://sepolia.uniscan.xyz/tx/0xd798e10c01006a942f3bde79fbce5d8d9eded32c1f34a2d7a3415fb47bc52682) (Unichain block 68617966).

Note: the first executor deployment (`0xa9b4a5a4…`) was wired to a stale
Unichain callback proxy address (`0x9299472A…` from an older doc). Both
callbacks for orders 0 and 1 were delivered promptly but reverted with
`NotAuthorized`, which the Reactive MCP's `trace_reactive_tx` pinpointed from
the on-chain `CallbackFailure` event. The executor was redeployed against the
live proxy (`0x775c9B99…`, confirmed via MCP `get_network_info`), reserves
were funded with `depositTo`, and both demo runs above executed on the first
attempt.

## Build & test

```bash
forge build
forge test        # 17 tests, all passing
```

Requirements: Foundry, solc 0.8.29, `via_ir = true` (the reactive test simulator
hits "stack too deep" without it).

## Deploy (testnet)

```bash
# 1. Tokens + pool on each chain
forge script script/DeployTokens.s.sol --rpc-url <RPC> --broadcast
forge script script/SetupPool.s.sol --rpc-url <RPC> --broadcast   # needs POOL_MANAGER, TOKEN0, TOKEN1

# 2. Reactive contract on Lasna — forge create, NOT forge script:
#    the constructor subscription reverts under simulation.
forge create src/FlashExitReactive.sol:FlashExitReactive --broadcast \
  --rpc-url https://lasna-rpc.rnk.dev/ \
  --constructor-args <base-pool-manager> --value 0.1ether

# 3. Executor on Unichain Sepolia (needs REACTIVE_ADDR, CALLBACK_PROXY, POOL_MANAGER)
forge script script/DeployExecutor.s.sol --rpc-url https://sepolia.unichain.org --broadcast

# 4. Wire it up: setExecutor() on the reactive contract, deposit, createOrder.
#    See script/deploy.sh for the full staged pipeline.
```

`script/deploy.sh` runs the whole pipeline in stages:
`base`, `base-pool`, `uni`, `uni-pool`, `lasna`, `executor`, `wire`, `trigger`.

## Notes for reviewers

- **Omni API, not the legacy lib.** This project uses
  `Reactive-Network/reactive-lib-omni` (v0.1.0) and the `omni` branch of
  `reactive-test-lib`. The legacy `reactive-lib` (master) targets the old
  system contract and a different event model; it does not work on Omni.
- **Local v4-core patch.** `lib/v4-core/src/PoolManager.sol` pins
  `pragma solidity 0.8.26;` (exact), which conflicts with the reactive libs'
  `^0.8.29`. The local copy widens it to `^0.8.26` (commented in the file).
  This only affects local builds/tests — testnet uses the deployed PoolManagers.
- **Callback funding.** Callbacks are billed to the recipient in destination
  native token; the executor must hold ETH on Unichain Sepolia or delivery
  reverts with `InDebt`. The reactive contract likewise needs lREACT on Lasna
  (via the faucet contracts: 1 ETH → 100 lREACT).
- **Testnets only.** No mainnet code, no real funds. All demo tokens are
  valueless test tokens minted for this project.

## Author

cezo484 — Reactive Omni Buildathon, November 2026.
