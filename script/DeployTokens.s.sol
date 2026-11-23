// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { TestToken } from "../src/TestToken.sol";

/// @notice Deploys the two demo tokens (FLASH + mUSD) and mints to the deployer.
///         Run once per chain (Base Sepolia for the watched pool, Unichain
///         Sepolia for the exit pool). Testnet only.
/// @dev Env: PRIVATE_KEY, MINT_AMOUNT (default 1_000_000 ether).
contract DeployTokens is Script {
    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        uint256 mintAmount = vm.envOr("MINT_AMOUNT", uint256(1_000_000 ether));
        vm.startBroadcast(key);

        TestToken flash = new TestToken("Flash Token", "FLASH");
        TestToken musd = new TestToken("Mock USD", "mUSD");
        flash.mint(vm.addr(key), mintAmount);
        musd.mint(vm.addr(key), mintAmount);

        vm.stopBroadcast();

        // Sort for the pool key: currency0 < currency1.
        (TestToken token0, TestToken token1) =
            address(flash) < address(musd) ? (flash, musd) : (musd, flash);
        console.log("FLASH", address(flash));
        console.log("mUSD", address(musd));
        console.log("TOKEN0", address(token0));
        console.log("TOKEN1", address(token1));
    }
}
