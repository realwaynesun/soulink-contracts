// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SoulinkRegistry} from "../src/SoulinkRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice Deployment procedure:
///   Testnet (Base Sepolia, chain 84532):
///     forge script Deploy --rpc-url $BASE_SEPOLIA_RPC --broadcast --verify
///   Mainnet (Base, chain 8453):
///     forge script Deploy --rpc-url $BASE_MAINNET_RPC --broadcast --verify --slow
///   Both require DEPLOYER_PRIVATE_KEY env var set.
contract Deploy is Script {
    uint256 constant BASE_MAINNET_CHAIN_ID = 8453;
    uint256 constant BASE_SEPOLIA_CHAIN_ID = 84532;

    // USDC on Base mainnet
    address constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    // USDC on Base Sepolia testnet
    address constant BASE_SEPOLIA_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    function run() external {
        require(
            block.chainid == BASE_MAINNET_CHAIN_ID || block.chainid == BASE_SEPOLIA_CHAIN_ID,
            "Deploy: must target Base mainnet (8453) or Base Sepolia (84532)"
        );

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address usdcAddress = block.chainid == BASE_SEPOLIA_CHAIN_ID
            ? BASE_SEPOLIA_USDC
            : BASE_USDC;

        console.log("Deploying SoulinkRegistry (UUPS)...");
        console.log("Chain ID:", block.chainid);
        console.log("USDC:", usdcAddress);
        console.log("Owner:", deployer);

        vm.startBroadcast(deployerKey);

        // Deploy implementation
        SoulinkRegistry implementation = new SoulinkRegistry();

        // Deploy proxy pointing to implementation, calling initialize()
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(SoulinkRegistry.initialize, (usdcAddress, deployer))
        );

        vm.stopBroadcast();

        console.log("Implementation deployed at:", address(implementation));
        console.log("Proxy deployed at:", address(proxy));
    }
}
