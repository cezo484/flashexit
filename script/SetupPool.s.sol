// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { ModifyLiquidityParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { PoolModifyLiquidityTest } from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import { TestToken } from "../src/TestToken.sol";

/// @notice Creates the FLASH/mUSD v4 pool at 1:1 and seeds wide-range liquidity.
///         Also deploys the helper routers used by later steps (liquidity + swaps).
/// @dev Env: PRIVATE_KEY, POOL_MANAGER, TOKEN0, TOKEN1,
///      LIQUIDITY (default 100_000 ether), FEE (default 3000), TICK_SPACING (default 60).
///      The deployer must hold enough of both tokens (see DeployTokens).
contract SetupPool is Script {
    using PoolIdLibrary for PoolKey;

    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        IPoolManager manager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        address token0 = vm.envAddress("TOKEN0");
        address token1 = vm.envAddress("TOKEN1");
        uint256 liquidity = vm.envOr("LIQUIDITY", uint256(100_000 ether));
        uint24 fee = uint24(vm.envOr("FEE", uint256(3000)));
        int24 tickSpacing = int24(int256(vm.envOr("TICK_SPACING", uint256(60))));

        vm.startBroadcast(key);

        PoolModifyLiquidityTest liqRouter = new PoolModifyLiquidityTest(manager);
        PoolSwapTest swapRouter = new PoolSwapTest(manager);

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(0))
        });
        manager.initialize(poolKey, SQRT_PRICE_1_1);

        TestToken(token0).approve(address(liqRouter), type(uint256).max);
        TestToken(token1).approve(address(liqRouter), type(uint256).max);
        liqRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -6000,
                tickUpper: 6000,
                liquidityDelta: int256(liquidity),
                salt: bytes32(0)
            }),
            ""
        );

        vm.stopBroadcast();

        console.log("LIQ_ROUTER", address(liqRouter));
        console.log("SWAP_ROUTER", address(swapRouter));
        console.log("POOL_ID:");
        console.logBytes32(PoolId.unwrap(poolKey.toId()));
    }
}
