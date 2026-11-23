// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { TestToken } from "../src/TestToken.sol";

/// @notice Performs the trigger swap on the origin chain (Base Sepolia) that
///         pushes the pool price across an order's trigger.
/// @dev Env: PRIVATE_KEY, POOL_MANAGER, SWAP_ROUTER, TOKEN0, TOKEN1,
///      AMOUNT (default 10_000 ether), ZERO_FOR_ONE (default true = price down),
///      FEE (default 3000), TICK_SPACING (default 60).
contract TriggerSwap is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        IPoolManager manager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        PoolSwapTest router = PoolSwapTest(vm.envAddress("SWAP_ROUTER"));
        address token0 = vm.envAddress("TOKEN0");
        address token1 = vm.envAddress("TOKEN1");
        uint256 amount = vm.envOr("AMOUNT", uint256(10_000 ether));
        bool zeroForOne = vm.envOr("ZERO_FOR_ONE", true);
        uint24 fee = uint24(vm.envOr("FEE", uint256(3000)));
        int24 tickSpacing = int24(int256(vm.envOr("TICK_SPACING", uint256(60))));

        address tokenIn = zeroForOne ? token0 : token1;
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(0))
        });

        vm.startBroadcast(key);
        TestToken(tokenIn).approve(address(router), type(uint256).max);
        router.swap(
            poolKey,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(amount),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }),
            ""
        );
        vm.stopBroadcast();

        (uint160 sqrtPriceX96,,,) = manager.getSlot0(poolKey.toId());
        console.log("SQRT_PRICE_X96_AFTER", sqrtPriceX96);
    }
}
