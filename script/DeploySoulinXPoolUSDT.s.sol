// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;
import {Script, console} from "forge-std/Script.sol";
import {SoulinXPool} from "../src/SoulinXPool.sol";
contract DeploySoulinXPoolUSDT is Script {
    address constant XLAYER_USDT = 0x1E4a5963aBFD975d8c9021ce480b42188849D41d;
    function run() external {
        require(block.chainid == 196, "X Layer only");
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(key);
        address fee = vm.envAddress("FEE_RECIPIENT");
        console.log("Deploying SoulinXPool with USDT...");
        console.log("USDT:", XLAYER_USDT);
        console.log("Operator:", deployer);
        vm.startBroadcast(key);
        SoulinXPool pool = new SoulinXPool(XLAYER_USDT, deployer, fee);
        vm.stopBroadcast();
        console.log("SoulinXPool deployed at:", address(pool));
    }
}
