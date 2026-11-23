// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IUnlockCallback } from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency, CurrencyLibrary } from "@uniswap/v4-core/src/types/Currency.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

interface IERC20Minimal {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @title FlashExitExecutor
/// @notice Lives on Unichain Sepolia. Receives exit callbacks from FlashExitReactive
///         (via the Reactive callback proxy) and executes the exit swap on Uniswap v4.
///         Users deposit the token they want to sell up front; the output goes
///         straight to them when the trigger fires.
/// @dev The callback is billed to this contract in the destination chain's native
///      token, so keep it funded or delivery reverts with InDebt.
contract FlashExitExecutor is AbstractCallback, IUnlockCallback {
    using CurrencyLibrary for Currency;

    IPoolManager public immutable poolManager;

    /// @notice Parameters carried through the unlock callback.
    struct ExitParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minOut;
        uint24 fee;
        int24 tickSpacing;
        address owner;
    }

    /// @notice user => token => deposited amount available for exits.
    mapping(address => mapping(address => uint256)) public deposits;

    event Deposited(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 amount);
    event ExitExecuted(
        uint256 indexed orderId,
        address indexed owner,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    error NotPoolManager();
    error InsufficientDeposit();
    error Slippage();
    error ZeroAmount();

    constructor(IPayable callbackProxy_, address callbackSender_, IPoolManager poolManager_)
        payable
        AbstractCallback(callbackProxy_, callbackSender_)
    {
        poolManager = poolManager_;
    }

    /// @notice Deposits tokens that a future exit may sell.
    function deposit(address token, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        IERC20Minimal(token).transferFrom(msg.sender, address(this), amount);
        deposits[msg.sender][token] += amount;
        emit Deposited(msg.sender, token, amount);
    }

    /// @notice Withdraws unspent deposits.
    function withdraw(address token, uint256 amount) external {
        if (deposits[msg.sender][token] < amount) revert InsufficientDeposit();
        deposits[msg.sender][token] -= amount;
        IERC20Minimal(token).transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, token, amount);
    }

    /// @notice Settles outstanding callback debt from this contract's own balance.
    function coverDebt() external {
        _coverDebt();
    }

    /// @notice Executes an exit swap. Only the callback proxy may call it, and only
    ///         when the injected sender is the authorized reactive contract.
    function executeExit(
        address reactive_,
        uint256 orderId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        uint24 fee,
        int24 tickSpacing,
        address owner_
    ) external onlyServiceProvider onlyCallbackSender(reactive_) {
        if (deposits[owner_][tokenIn] < amountIn) revert InsufficientDeposit();
        deposits[owner_][tokenIn] -= amountIn;

        bytes memory result = poolManager.unlock(
            abi.encode(
                orderId,
                ExitParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    minOut: minOut,
                    fee: fee,
                    tickSpacing: tickSpacing,
                    owner: owner_
                })
            )
        );
        uint256 amountOut = abi.decode(result, (uint256));
        emit ExitExecuted(orderId, owner_, tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @notice Uniswap v4 unlock callback: performs the exact-input swap, settles
    ///         the input side and sends the output to the order owner.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        (, ExitParams memory params) = abi.decode(data, (uint256, ExitParams));
        return abi.encode(_swapAndSettle(params));
    }

    function _swapAndSettle(ExitParams memory params) internal returns (uint256 amountOut) {
        (Currency currency0, Currency currency1) = params.tokenIn < params.tokenOut
            ? (Currency.wrap(params.tokenIn), Currency.wrap(params.tokenOut))
            : (Currency.wrap(params.tokenOut), Currency.wrap(params.tokenIn));
        bool zeroForOne = params.tokenIn == Currency.unwrap(currency0);

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: params.fee,
            tickSpacing: params.tickSpacing,
            hooks: IHooks(address(0))
        });

        BalanceDelta delta = poolManager.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(params.amountIn),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            ""
        );

        int128 deltaIn = zeroForOne ? delta.amount0() : delta.amount1();
        int128 deltaOut = zeroForOne ? delta.amount1() : delta.amount0();
        if (deltaOut <= 0 || uint128(deltaOut) < params.minOut) revert Slippage();
        amountOut = uint128(deltaOut);

        Currency currencyIn = zeroForOne ? currency0 : currency1;
        Currency currencyOut = zeroForOne ? currency1 : currency0;

        // Settle the input side: sync, pay, settle.
        poolManager.sync(currencyIn);
        IERC20Minimal(params.tokenIn).transfer(address(poolManager), uint128(-deltaIn));
        poolManager.settle();

        // Send the output straight to the order owner.
        poolManager.take(currencyOut, params.owner, amountOut);
    }
}
