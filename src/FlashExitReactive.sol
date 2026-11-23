// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";

/// @title FlashExitReactive
/// @notice Lives on Reactive Lasna. Watches Uniswap v4 Swap events on Base Sepolia
///         and fires a callback to FlashExitExecutor on Unichain Sepolia when a
///         user's stop-loss or take-profit trigger is crossed.
/// @dev Built for the Reactive Omni Buildathon, Track 1 (Every Second Counts).
///      Subscriptions are per-pool: createOrder subscribes to the pool's Swap
///      events the first time an order for that pool is placed.
contract FlashExitReactive is AbstractReactive {
    /// @notice Base Sepolia, where prices are observed.
    uint256 public constant ORIGIN_CHAIN_ID = 84532;
    /// @notice Unichain Sepolia, where the exit swap executes.
    uint256 public constant DEST_CHAIN_ID = 1301;
    /// @notice Uniswap v4 Swap event signature hash.
    uint256 public constant SWAP_TOPIC0 =
        0x40e9cecb9f5f1f1c5b9c97dec2917b7ee92e57ba5563708daca94dd84ad7112f;
    /// @notice Gas forwarded to the executor callback (swap + settle + take).
    uint64 public constant CALLBACK_GAS_LIMIT = 1_000_000;

    /// @notice PoolManager on the origin chain (immutable so tests can point at a local one).
    address public immutable originPoolManager;

    address public owner;
    address public executor;

    enum Status {
        Active,
        Triggered,
        Cancelled,
        Expired
    }

    struct Order {
        address owner;
        bytes32 poolId;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 triggerSqrtPriceX96;
        bool triggerBelow;
        uint256 minOut;
        uint256 deadline;
        uint24 fee;
        int24 tickSpacing;
        Status status;
        uint256 createdAt;
    }

    uint256 public nextOrderId;
    mapping(uint256 => Order) public orders;
    mapping(bytes32 => uint256[]) public poolOrders;
    mapping(bytes32 => bool) public subscribedPools;
    mapping(bytes32 => uint256) public lastSqrtPriceX96;

    event OrderCreated(
        uint256 indexed orderId,
        address indexed owner,
        bytes32 indexed poolId,
        uint256 triggerSqrtPriceX96,
        bool triggerBelow
    );
    event OrderTriggered(uint256 indexed orderId, bytes32 indexed poolId, uint256 sqrtPriceX96);
    event OrderCancelled(uint256 indexed orderId);
    event OrderExpired(uint256 indexed orderId);
    event ExecutorSet(address indexed executor);

    error NotOwner();
    error ExecutorNotSet();
    error BadOrder();
    error NotOrderOwner();
    error OrderNotActive();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address executor_, address originPoolManager_) payable {
        owner = msg.sender;
        executor = executor_;
        originPoolManager = originPoolManager_;
    }

    /// @notice Points the reactive contract at the executor on the destination chain.
    /// @dev Deploy order: reactive contract first, executor second (it needs the
    ///      reactive contract's address), then this setter wires them together.
    function setExecutor(address executor_) external onlyOwner {
        executor = executor_;
        emit ExecutorSet(executor_);
    }

    /// @notice Places a stop-loss (triggerBelow) or take-profit (!triggerBelow) order.
    /// @param poolId Pool id on the origin chain whose price is watched.
    /// @param tokenIn Token sold on the destination chain when the trigger fires.
    /// @param tokenOut Token received on the destination chain.
    /// @param amountIn Amount of tokenIn to sell (must be deposited in the executor first).
    /// @param triggerSqrtPriceX96 sqrtPriceX96 threshold, compared directly (no price math needed).
    /// @param triggerBelow True for stop-loss (fire at or below), false for take-profit (at or above).
    /// @param minOut Minimum tokenOut accepted by the exit swap (slippage guard).
    /// @param deadline Order expires after this timestamp and never fires.
    /// @param fee Fee tier of the destination pool.
    /// @param tickSpacing Tick spacing of the destination pool.
    function createOrder(
        bytes32 poolId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 triggerSqrtPriceX96,
        bool triggerBelow,
        uint256 minOut,
        uint256 deadline,
        uint24 fee,
        int24 tickSpacing
    ) external returns (uint256 orderId) {
        if (executor == address(0)) revert ExecutorNotSet();
        if (
            tokenIn == address(0) || tokenOut == address(0) || tokenIn == tokenOut
                || amountIn == 0 || triggerSqrtPriceX96 == 0 || deadline <= block.timestamp
        ) revert BadOrder();

        orderId = nextOrderId++;
        orders[orderId] = Order({
            owner: msg.sender,
            poolId: poolId,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            triggerSqrtPriceX96: triggerSqrtPriceX96,
            triggerBelow: triggerBelow,
            minOut: minOut,
            deadline: deadline,
            fee: fee,
            tickSpacing: tickSpacing,
            status: Status.Active,
            createdAt: block.timestamp
        });
        poolOrders[poolId].push(orderId);

        if (!subscribedPools[poolId]) {
            subscribedPools[poolId] = true;
            SYSTEM.subscribe(
                ORIGIN_CHAIN_ID,
                originPoolManager,
                SWAP_TOPIC0,
                uint256(poolId),
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }

        emit OrderCreated(orderId, msg.sender, poolId, triggerSqrtPriceX96, triggerBelow);
    }

    /// @notice Cancels an active order. Only the order owner or the contract owner.
    function cancelOrder(uint256 orderId) external {
        Order storage order = orders[orderId];
        if (order.status != Status.Active) revert OrderNotActive();
        if (msg.sender != order.owner && msg.sender != owner) revert NotOrderOwner();
        order.status = Status.Cancelled;
        emit OrderCancelled(orderId);
    }

    /// @notice Settles outstanding debt from this contract's own balance.
    function coverDebt() external {
        _coverDebt();
    }

    /// @notice Order ids watching a given pool.
    function getOrdersForPool(bytes32 poolId) external view returns (uint256[] memory) {
        return poolOrders[poolId];
    }

    /// @inheritdoc IReactive
    function react(LogRecord calldata log_) external override onlySystem {
        if (log_.topic0 != SWAP_TOPIC0) return;
        if (log_.chainId != ORIGIN_CHAIN_ID) return;
        if (log_.contractAddress != originPoolManager) return;
        if (log_.opCode != 3) return; // Swap has 3 topics: sig, poolId, sender

        bytes32 poolId = bytes32(log_.topic1);
        (, , uint160 sqrtPriceX96, , , ) =
            abi.decode(log_.data, (int128, int128, uint160, uint128, int24, uint24));
        lastSqrtPriceX96[poolId] = sqrtPriceX96;

        uint256[] storage ids = poolOrders[poolId];
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 orderId = ids[i];
            Order storage order = orders[orderId];
            if (order.status != Status.Active) continue;
            if (block.timestamp > order.deadline) {
                order.status = Status.Expired;
                emit OrderExpired(orderId);
                continue;
            }
            bool hit = order.triggerBelow
                ? sqrtPriceX96 <= order.triggerSqrtPriceX96
                : sqrtPriceX96 >= order.triggerSqrtPriceX96;
            if (!hit) continue;

            order.status = Status.Triggered;
            emit OrderTriggered(orderId, poolId, sqrtPriceX96);
            _requestExit(orderId, order);
        }
    }

    function _requestExit(uint256 orderId, Order storage order) internal {
        bytes memory payload = abi.encodeWithSignature(
            "executeExit(address,uint256,address,address,uint256,uint256,uint24,int24,address)",
            address(0), // placeholder: the proxy injects this contract's address
            orderId,
            order.tokenIn,
            order.tokenOut,
            order.amountIn,
            order.minOut,
            order.fee,
            order.tickSpacing,
            order.owner
        );
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: DEST_CHAIN_ID,
                recipient: executor,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
    }
}
