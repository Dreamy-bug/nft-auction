// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import "../src/NFTAuction.sol";
import "../src/NFTAuctionV2.sol";

/**
 * @title UpgradeNFTAuction
 * @dev 将NFTAuction升级到V2版本（支持动态手续费）
 *
 * 使用方法：
 * forge script script/UpgradeNFTAuction.s.sol --rpc-url $SEPOLIA_RPC --broadcast
 */
contract UpgradeNFTAuction is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // 从环境变量读取代理合约地址
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");

        console.log("=== Upgrading NFTAuction to V2 ===");
        console.log("Deployer:", deployer);
        console.log("Proxy Address:", proxyAddress);

        vm.startBroadcast(deployerPrivateKey);

        // 1. 部署新的V2实现合约
        NFTAuctionV2 implementationV2 = new NFTAuctionV2();
        console.log("New V2 Implementation deployed at:", address(implementationV2));

        // 2. 通过代理升级，同时调用initializeV2
        NFTAuction proxy = NFTAuction(payable(proxyAddress));

        // 设置动态手续费参数：低档2.5%, 中档2%, 高档1.5%
        // 阈值：$1,000 和 $10,000（8位小数）
        uint256[3] memory feeTiers = [uint256(250), uint256(200), uint256(150)];
        uint256[2] memory feeThresholds = [uint256(1000e8), uint256(10000e8)];

        proxy.upgradeToAndCall(
            address(implementationV2),
            abi.encodeCall(NFTAuctionV2.initializeV2, (feeTiers, feeThresholds))
        );

        vm.stopBroadcast();

        console.log("\n=== Upgrade Summary ===");
        console.log("New Implementation Address:", address(implementationV2));
        console.log("Proxy Address (unchanged):", proxyAddress);
        console.log("New Version: 2.0.0");

        // 验证升级
        NFTAuctionV2 proxyV2 = NFTAuctionV2(proxyAddress);
        console.log("\n=== Verification ===");
        console.log("Version:", proxyV2.version());
        console.log("Dynamic Fee Enabled:", proxyV2.dynamicFeeEnabled());

        console.log("\n=== Dynamic Fee Configuration ===");
        console.log("Fee Tiers: 2.5%, 2.0%, 1.5%");
        console.log("Thresholds: $1,000, $10,000");
        console.log("  < $1,000     -> 2.5% fee");
        console.log("  $1,000-$10,000 -> 2.0% fee");
        console.log("  >= $10,000   -> 1.5% fee");
    }
}
