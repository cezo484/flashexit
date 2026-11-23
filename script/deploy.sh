#!/usr/bin/env bash
# FlashExit testnet deployment pipeline (TESTNETS ONLY).
# Usage:
#   source .env.deploy          # sets DEPLOYER_KEY (never commit it)
#   ./script/deploy.sh base     # tokens + pool on Base Sepolia
#   ./script/deploy.sh uni      # tokens + pool on Unichain Sepolia
#   ./script/deploy.sh lasna    # reactive contract on Lasna (forge create)
#   ./script/deploy.sh executor # executor on Unichain Sepolia (needs RC_ADDR)
#   ./script/deploy.sh wire     # setExecutor + deposit + createOrder
#   ./script/deploy.sh trigger  # trigger swap on Base Sepolia
# Addresses are recorded in deployments/<chain>.env as each step completes.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.foundry/bin:$PATH"

BASE_RPC="https://sepolia.base.org"
UNI_RPC="https://sepolia.unichain.org"
LASNA_RPC="https://lasna-rpc.rnk.dev/"
BASE_PM="0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408"
UNI_PM="0x00B036B58a818B1BC34d502D3fE730Db729e62AC"
UNI_PROXY="0x775c9B990ADe401060B78D0e98684eEf8d2466C1" # verified live 2026-11-23 via Reactive MCP get_network_info; the old 0x9299... address was stale and broke callbacks (NotAuthorized)

mkdir -p deployments
DEPLOYER="$(cast wallet address --private-key "$DEPLOYER_KEY")"
echo "Deployer: $DEPLOYER"

step="${1:-all}"
run() { echo "--- $*"; "$@"; }

case "$step" in
base)
  echo "== Base Sepolia: tokens =="
  run forge script script/DeployTokens.s.sol --rpc-url "$BASE_RPC" --broadcast \
    --private-key "$DEPLOYER_KEY" 2>&1 | tee deployments/base-tokens.log
  echo "Fill in TOKEN0/TOKEN1 from the log, then re-run with those set:"
  echo "  TOKEN0=0x... TOKEN1=0x... ./script/deploy.sh base-pool"
  ;;
base-pool)
  : "${TOKEN0:?set TOKEN0}"; : "${TOKEN1:?set TOKEN1}"
  echo "== Base Sepolia: pool =="
  TOKEN0="$TOKEN0" TOKEN1="$TOKEN1" POOL_MANAGER="$BASE_PM" \
    forge script script/SetupPool.s.sol --rpc-url "$BASE_RPC" --broadcast \
    --private-key "$DEPLOYER_KEY" 2>&1 | tee deployments/base-pool.log
  ;;
uni)
  echo "== Unichain Sepolia: tokens =="
  run forge script script/DeployTokens.s.sol --rpc-url "$UNI_RPC" --broadcast \
    --private-key "$DEPLOYER_KEY" 2>&1 | tee deployments/uni-tokens.log
  echo "Fill in TOKEN0/TOKEN1 from the log, then run:"
  echo "  TOKEN0=0x... TOKEN1=0x... ./script/deploy.sh uni-pool"
  ;;
uni-pool)
  : "${TOKEN0:?set TOKEN0}"; : "${TOKEN1:?set TOKEN1}"
  echo "== Unichain Sepolia: pool =="
  TOKEN0="$TOKEN0" TOKEN1="$TOKEN1" POOL_MANAGER="$UNI_PM" \
    forge script script/SetupPool.s.sol --rpc-url "$UNI_RPC" --broadcast \
    --private-key "$DEPLOYER_KEY" 2>&1 | tee deployments/uni-pool.log
  ;;
lasna)
  echo "== Lasna: reactive contract (forge create; constructor subscribes on orders only) =="
  : "${RC_VALUE:=0.1ether}"
  run forge create --broadcast --rpc-url "$LASNA_RPC" --chain-id 5318007 \
    --private-key "$DEPLOYER_KEY" --value "$RC_VALUE" \
    src/FlashExitReactive.sol:FlashExitReactive \
    --constructor-args 0x0000000000000000000000000000000000000000 "$BASE_PM" \
    2>&1 | tee deployments/lasna-rc.log
  ;;
executor)
  : "${RC_ADDR:?set RC_ADDR}"
  echo "== Unichain Sepolia: executor =="
  REACTIVE_ADDR="$RC_ADDR" CALLBACK_PROXY="$UNI_PROXY" POOL_MANAGER="$UNI_PM" \
    forge script script/DeployExecutor.s.sol --rpc-url "$UNI_RPC" --broadcast \
    --private-key "$DEPLOYER_KEY" 2>&1 | tee deployments/uni-executor.log
  ;;
wire)
  : "${RC_ADDR:?set RC_ADDR}"; : "${EXECUTOR:?set EXECUTOR}"
  : "${UNI_TOKEN0:?set UNI_TOKEN0}"; : "${UNI_TOKEN1:?set UNI_TOKEN1}"
  : "${BASE_POOL_ID:?set BASE_POOL_ID}"; : "${TRIGGER:?set TRIGGER}"
  : "${AMOUNT_IN:=100ether}"; : "${MIN_OUT:=0}"
  echo "== Wire RC -> executor =="
  run cast send "$RC_ADDR" "setExecutor(address)" "$EXECUTOR" \
    --rpc-url "$LASNA_RPC" --private-key "$DEPLOYER_KEY"
  echo "== Deposit FLASH into executor =="
  run cast send "$UNI_TOKEN0" "approve(address,uint256)" "$EXECUTOR" "$AMOUNT_IN" \
    --rpc-url "$UNI_RPC" --private-key "$DEPLOYER_KEY"
  run cast send "$EXECUTOR" "deposit(address,uint256)" "$UNI_TOKEN0" "$AMOUNT_IN" \
    --rpc-url "$UNI_RPC" --private-key "$DEPLOYER_KEY"
  echo "== Create stop-loss order on Lasna =="
  DEADLINE=$(( $(date +%s) + 7*24*3600 ))
  run cast send "$RC_ADDR" \
    "createOrder(bytes32,address,address,uint256,uint256,bool,uint256,uint256,uint24,int24)" \
    "$BASE_POOL_ID" "$UNI_TOKEN0" "$UNI_TOKEN1" "$AMOUNT_IN" "$TRIGGER" true "$MIN_OUT" \
    "$DEADLINE" 3000 60 \
    --rpc-url "$LASNA_RPC" --private-key "$DEPLOYER_KEY"
  ;;
trigger)
  : "${BASE_SWAP_ROUTER:?set BASE_SWAP_ROUTER}"
  : "${BASE_TOKEN0:?set BASE_TOKEN0}"; : "${BASE_TOKEN1:?set BASE_TOKEN1}"
  : "${AMOUNT:=10000ether}"
  echo "== Trigger swap on Base Sepolia =="
  POOL_MANAGER="$BASE_PM" SWAP_ROUTER="$BASE_SWAP_ROUTER" \
    TOKEN0="$BASE_TOKEN0" TOKEN1="$BASE_TOKEN1" AMOUNT="$AMOUNT" \
    forge script script/TriggerSwap.s.sol --rpc-url "$BASE_RPC" --broadcast \
    --private-key "$DEPLOYER_KEY" 2>&1 | tee deployments/trigger.log
  ;;
*)
  echo "Unknown step: $step (base|base-pool|uni|uni-pool|lasna|executor|wire|trigger)"
  exit 1
  ;;
esac
echo "Done: $step"
