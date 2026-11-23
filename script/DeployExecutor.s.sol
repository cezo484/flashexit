// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { FlashExitExecutor } from "../src/FlashExitExecutor.sol";

/// @notice Deploys FlashExitExecutor on the destination chain (Unichain Sepolia).
/// @dev Env: PRIVATE_KEY, REACTIVE_ADDR (Lasna RC), CALLBACK_PROXY,
///      POOL_MANAGER, FUND_VALUE (default 0.0005 ether, funds callback delivery).
contract DeployExecutor is Script {
    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address reactive = vm.envAddress("REACTIVE_ADDR");
        IPayable proxy = IPayable(payable(vm.envAddress("CALLBACK_PROXY")));
        IPoolManager manager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        uint256 fundValue = vm.envOr("FUND_VALUE", uint256(0.0005 ether));

        vm.startBroadcast(key);
        FlashExitExecutor executor = new FlashExitExecutor{ value: fundValue }(proxy, reactive, manager);
        vm.stopBroadcast();

        console.log("EXECUTOR", address(executor));
    }
}
