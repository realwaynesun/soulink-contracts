// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SoulinXPool} from "../src/SoulinXPool.sol";

/// @notice Deploy SoulinXPool on X Layer mainnet (chain 196).
///   forge script DeploySoulinXPool --profile xlayer --rpc-url xlayer --broadcast --verify
///   Requires DEPLOYER_PRIVATE_KEY and FEE_RECIPIENT env vars.
contract DeploySoulinXPool is Script {
    address constant XLAYER_USDG = 0x4ae46a509F6b1D9056937BA4500cb143933D2dc8;

    function run() external {
        require(block.chainid == 196, "X Layer mainnet only");

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");

        console.log("Deploying SoulinXPool...");
        console.log("Chain ID:", block.chainid);
        console.log("USDG:", XLAYER_USDG);
        console.log("Operator:", deployer);
        console.log("Fee Recipient:", feeRecipient);

        vm.startBroadcast(deployerKey);

        SoulinXPool pool = new SoulinXPool(XLAYER_USDG, deployer, feeRecipient);

        vm.stopBroadcast();

        console.log("SoulinXPool deployed at:", address(pool));
    }
}
