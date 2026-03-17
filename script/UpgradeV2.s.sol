// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SoulinkRegistry} from "../src/SoulinkRegistry.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @notice Upgrade SoulinkRegistry to V2 (ERC-8004 compatible)
///   Base Sepolia:
///     PROXY_ADDRESS=0x... forge script UpgradeV2 --rpc-url $BASE_SEPOLIA_RPC --broadcast --verify
///   Base Mainnet:
///     PROXY_ADDRESS=0x15d13ed36b337dff3d5877ed46655037ee4c1be0 \
///     forge script UpgradeV2 --rpc-url $BASE_RPC_URL --broadcast --verify --slow
///   X Layer:
///     PROXY_ADDRESS=0x... forge script UpgradeV2 --profile xlayer --rpc-url xlayer --broadcast --verify
contract UpgradeV2 is Script {
    function run() external {
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        console.log("Upgrading SoulinkRegistry to V2...");
        console.log("Chain ID:", block.chainid);
        console.log("Proxy:", proxyAddress);

        vm.startBroadcast(deployerKey);

        SoulinkRegistry newImpl = new SoulinkRegistry();

        UUPSUpgradeable(proxyAddress).upgradeToAndCall(
            address(newImpl),
            abi.encodeCall(SoulinkRegistry.initializeV2, ())
        );

        vm.stopBroadcast();

        console.log("New implementation:", address(newImpl));
        console.log("Upgrade complete. V2 initialized.");
    }
}
