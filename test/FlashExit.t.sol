// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { ReactiveTest } from "reactive-test-lib/ReactiveTest.sol";
import { FeeMode, CallbackResult } from "reactive-test-lib/ReactiveTypes.sol";
import { Deployers } from "@uniswap/v4-core/test/utils/Deployers.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { SwapParams, ModifyLiquidityParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";

import { FlashExitReactive } from "../src/FlashExitReactive.sol";
import { FlashExitExecutor } from "../src/FlashExitExecutor.sol";
import { TestToken } from "../src/TestToken.sol";

/// @title FlashExit full-loop tests
/// @notice Simulates the whole Reactive Omni pipeline locally: a Swap on the
///         origin chain (Base Sepolia) is picked up by the reactive contract on
///         Lasna, which requests a callback that executes the exit swap on the
///         destination chain (Unichain Sepolia).
contract FlashExitTest is ReactiveTest, Deployers {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    uint256 constant LASNA = 5318007;
    uint256 constant BASE_SEPOLIA = 84532;
    uint256 constant UNICHAIN_SEPOLIA = 1301;

    FlashExitReactive public rc;
    FlashExitExecutor public executor;
    TestToken public token0;
    TestToken public token1;
    PoolId public poolId;

    address public user = address(0xBEEF);
    address public uniProxy;

    uint256 constant ORDER_AMOUNT = 100 ether;
    uint256 constant USER_FUNDS = 100_000 ether;

    function setUp() public {
        _reactiveSetUp(LASNA);
        _registerChain(BASE_SEPOLIA);
        uniProxy = _registerChain(UNICHAIN_SEPOLIA);

        // One local PoolManager stands in for both chains' managers (the
        // simulator shares one EVM; chain context switches via _switchToChain).
        deployFreshManagerAndRouters();
        // The engine attributes each log's chain from its emitter's
        // registration, so the manager must be registered on the origin chain.
        _registerContract(BASE_SEPOLIA, address(manager));

        // Deploy the demo tokens and sort them into currency0/currency1.
        TestToken a = new TestToken("Flash Token", "FLASH");
        TestToken b = new TestToken("Mock USD", "mUSD");
        (token0, token1) = address(a) < address(b) ? (a, b) : (b, a);
        token0.mint(address(this), USER_FUNDS * 10);
        token1.mint(address(this), USER_FUNDS * 10);
        token0.mint(user, USER_FUNDS);
        token1.mint(user, USER_FUNDS);

        key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);
        _addLiquidity(500_000 ether);

        // Reactive contract on Lasna (executor wired later, as in production).
        rc = new FlashExitReactive(address(0), address(manager));
        _registerContract(LASNA, address(rc));

        // Executor on Unichain Sepolia, trusting the reactive contract.
        executor = new FlashExitExecutor(IPayable(payable(uniProxy)), address(rc), manager);
        _registerContract(UNICHAIN_SEPOLIA, address(executor));
        _fund(address(executor), 10 ether);

        // Wire them together.
        rc.setExecutor(address(executor));
    }

    function _addLiquidity(uint256 amount) internal {
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -6000,
                tickUpper: 6000,
                liquidityDelta: int256(amount),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    /// @notice Swaps token0 -> token1 on the origin chain, pushing the price down.
    function _swapDown(uint256 amountIn) internal {
        _switchToChain(BASE_SEPOLIA);
        token0.approve(address(swapRouter), type(uint256).max);
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(amountIn),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }),
            ZERO_BYTES
        );
        _switchToChain(LASNA);
    }

    /// @notice Swaps token1 -> token0 on the origin chain, pushing the price up.
    function _swapUp(uint256 amountIn) internal {
        _switchToChain(BASE_SEPOLIA);
        token1.approve(address(swapRouter), type(uint256).max);
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: false,
                amountSpecified: -int256(amountIn),
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }),
            ZERO_BYTES
        );
        _switchToChain(LASNA);
    }

    function _placeOrder(bool triggerBelow, uint256 triggerSqrtPriceX96) internal returns (uint256) {
        vm.prank(user);
        token0.approve(address(executor), type(uint256).max);
        vm.prank(user);
        executor.deposit(address(token0), ORDER_AMOUNT);
        vm.prank(user);
        return rc.createOrder(
            PoolId.unwrap(poolId),
            address(token0),
            address(token1),
            ORDER_AMOUNT,
            triggerSqrtPriceX96,
            triggerBelow,
            0, // minOut
            block.timestamp + 7 days,
            3000,
            60
        );
    }

    function _currentSqrtPrice() internal view returns (uint160) {
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(poolId);
        return sqrtPriceX96;
    }

    // ---- full loop ----

    function testStopLossFullLoop() public {
        uint160 start = _currentSqrtPrice();
        // Stop-loss 2% below the starting price (sqrt of 0.98 ~= 0.99).
        uint256 trigger = uint256(start) * 99 / 100;
        uint256 orderId = _placeOrder(true, trigger);

        uint256 userToken1Before = token1.balanceOf(user);
        _swapDown(50_000 ether);
        assertLt(_currentSqrtPrice(), trigger, "price did not cross the trigger");

        CallbackResult[] memory results = _react(FeeMode.Subsidized);
        assertEq(results.length, 1, "expected exactly one callback");
        assertTrue(results[0].success, "callback failed");
        assertEq(results[0].destChainId, UNICHAIN_SEPOLIA);

        // Order is triggered and the user received token1 for the sold token0.
        (, , , , , , , , , , , FlashExitReactive.Status status,) = rc.orders(orderId);
        assertEq(uint256(status), uint256(FlashExitReactive.Status.Triggered));
        assertGt(token1.balanceOf(user), userToken1Before, "user got no exit proceeds");
        assertEq(executor.deposits(user, address(token0)), 0, "deposit not spent");
        _assertEmitted(address(executor), keccak256("ExitExecuted(uint256,address,address,address,uint256,uint256)"));
    }

    function testTakeProfitFullLoop() public {
        uint160 start = _currentSqrtPrice();
        // Take-profit 2% above the starting price (sqrt of 1.02 ~= 1.01).
        uint256 trigger = uint256(start) * 101 / 100;
        uint256 orderId = _placeOrder(false, trigger);

        uint256 userToken1Before = token1.balanceOf(user);
        _swapUp(50_000 ether);
        assertGt(_currentSqrtPrice(), trigger, "price did not cross the trigger");

        CallbackResult[] memory results = _react(FeeMode.Subsidized);
        assertEq(results.length, 1);
        assertTrue(results[0].success);

        (, , , , , , , , , , , FlashExitReactive.Status status,) = rc.orders(orderId);
        assertEq(uint256(status), uint256(FlashExitReactive.Status.Triggered));
        assertGt(token1.balanceOf(user), userToken1Before);
    }

    function testNoFireWithoutCrossing() public {
        uint160 start = _currentSqrtPrice();
        uint256 trigger = uint256(start) * 90 / 100; // 19% price drop needed
        uint256 orderId = _placeOrder(true, trigger);

        _swapDown(1_000 ether); // small move, nowhere near the trigger
        CallbackResult[] memory results = _react(FeeMode.Subsidized);
        assertEq(results.length, 0, "no callback expected");

        (, , , , , , , , , , , FlashExitReactive.Status status,) = rc.orders(orderId);
        assertEq(uint256(status), uint256(FlashExitReactive.Status.Active));
        assertEq(executor.deposits(user, address(token0)), ORDER_AMOUNT);
    }

    function testFiresOnlyOnce() public {
        uint160 start = _currentSqrtPrice();
        uint256 trigger = uint256(start) * 99 / 100;
        _placeOrder(true, trigger);

        _swapDown(50_000 ether);
        CallbackResult[] memory first = _react(FeeMode.Subsidized);
        assertEq(first.length, 1);

        // Price is still below the trigger, but the order already fired.
        _swapDown(10_000 ether);
        CallbackResult[] memory second = _react(FeeMode.Subsidized);
        assertEq(second.length, 0, "order must fire exactly once");
    }

    function testExpiredOrderDoesNotFire() public {
        uint160 start = _currentSqrtPrice();
        uint256 trigger = uint256(start) * 99 / 100;
        uint256 orderId = _placeOrder(true, trigger);

        vm.warp(block.timestamp + 8 days);
        _swapDown(50_000 ether);
        CallbackResult[] memory results = _react(FeeMode.Subsidized);
        assertEq(results.length, 0, "expired order must not fire");

        (, , , , , , , , , , , FlashExitReactive.Status status,) = rc.orders(orderId);
        assertEq(uint256(status), uint256(FlashExitReactive.Status.Expired));
    }

    function testTwoOrdersSamePool() public {
        uint160 start = _currentSqrtPrice();
        uint256 t1 = uint256(start) * 99 / 100;
        uint256 t2 = uint256(start) * 95 / 100;
        _placeOrder(true, t1);
        _placeOrder(true, t2);

        _swapDown(50_000 ether);
        CallbackResult[] memory results = _react(FeeMode.Subsidized);
        assertEq(results.length, 2, "both orders should fire");
        assertTrue(results[0].success && results[1].success);
    }

    // ---- guards ----

    function testCancelOrder() public {
        uint160 start = _currentSqrtPrice();
        uint256 orderId = _placeOrder(true, uint256(start) * 99 / 100);
        vm.prank(user);
        rc.cancelOrder(orderId);

        _swapDown(50_000 ether);
        CallbackResult[] memory results = _react(FeeMode.Subsidized);
        assertEq(results.length, 0, "cancelled order must not fire");
    }

    function testCancelByStrangerReverts() public {
        uint160 start = _currentSqrtPrice();
        uint256 orderId = _placeOrder(true, uint256(start) * 99 / 100);
        vm.prank(address(0xCAFE));
        vm.expectRevert(FlashExitReactive.NotOrderOwner.selector);
        rc.cancelOrder(orderId);
    }

    function testReactRevertsForNonSystem() public {
        // react() may only be called by the system contract.
        uint256 topic0 = rc.SWAP_TOPIC0();
        vm.expectRevert();
        rc.react(
            IReactive.LogRecord({
                chainId: BASE_SEPOLIA,
                contractAddress: address(manager),
                topic0: topic0,
                topic1: 0,
                topic2: 0,
                topic3: 0,
                data: "",
                blockNumber: 0,
                opCode: 3,
                blockHash: 0,
                txHash: 0,
                logIndex: 0
            })
        );
    }

    function testExecuteExitRevertsForNonProxy() public {
        vm.expectRevert();
        executor.executeExit(address(rc), 0, address(token0), address(token1), 1, 0, 3000, 60, user);
    }

    function testExecuteExitRevertsForWrongSender() public {
        // Even the proxy cannot drive the callback for another reactive contract.
        vm.prank(uniProxy);
        vm.expectRevert();
        executor.executeExit(address(0xDEAD), 0, address(token0), address(token1), 1, 0, 3000, 60, user);
    }

    function testCreateOrderRequiresExecutor() public {
        FlashExitReactive fresh = new FlashExitReactive(address(0), address(manager));
        vm.prank(user);
        vm.expectRevert(FlashExitReactive.ExecutorNotSet.selector);
        fresh.createOrder(PoolId.unwrap(poolId), address(token0), address(token1), 1, 1, true, 0, block.timestamp + 1, 3000, 60);
    }

    function testBadOrderReverts() public {
        vm.prank(user);
        vm.expectRevert(FlashExitReactive.BadOrder.selector);
        rc.createOrder(PoolId.unwrap(poolId), address(token0), address(token0), 1, 1, true, 0, block.timestamp + 1, 3000, 60);
    }

    function testSetExecutorOnlyOwner() public {
        vm.prank(address(0xCAFE));
        vm.expectRevert(FlashExitReactive.NotOwner.selector);
        rc.setExecutor(address(0xCAFE));
    }

    // ---- deposits ----

    function testDepositWithdraw() public {
        vm.prank(user);
        token1.approve(address(executor), type(uint256).max);
        vm.prank(user);
        executor.deposit(address(token1), 500 ether);
        assertEq(executor.deposits(user, address(token1)), 500 ether);

        vm.prank(user);
        executor.withdraw(address(token1), 200 ether);
        assertEq(executor.deposits(user, address(token1)), 300 ether);
        assertEq(token1.balanceOf(user), USER_FUNDS - 300 ether);
    }

    function testWithdrawMoreThanDepositReverts() public {
        vm.prank(user);
        vm.expectRevert(FlashExitExecutor.InsufficientDeposit.selector);
        executor.withdraw(address(token1), 1);
    }

    function testMinOutProtectsUser() public {
        // minOut above what the swap can deliver: the callback must fail and
        // the deposit must stay put (the whole callback reverts).
        uint160 start = _currentSqrtPrice();
        uint256 trigger = uint256(start) * 99 / 100;

        vm.prank(user);
        token0.approve(address(executor), type(uint256).max);
        vm.prank(user);
        executor.deposit(address(token0), ORDER_AMOUNT);
        vm.prank(user);
        rc.createOrder(
            PoolId.unwrap(poolId),
            address(token0),
            address(token1),
            ORDER_AMOUNT,
            trigger,
            true,
            type(uint256).max, // impossible minOut
            block.timestamp + 7 days,
            3000,
            60
        );

        _swapDown(50_000 ether);
        CallbackResult[] memory results = _react(FeeMode.Subsidized);
        assertEq(results.length, 1);
        assertFalse(results[0].success, "callback must fail on slippage");
        assertEq(executor.deposits(user, address(token0)), ORDER_AMOUNT, "deposit must survive a failed callback");
    }
}
