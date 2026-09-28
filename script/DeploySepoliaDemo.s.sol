// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import "../src/NFTAuction.sol";
import "../src/NFTAuctionV2.sol";
import "../src/MyNFT.sol";
import "../test/mocks/MockERC20.sol";
import "../test/mocks/MockAggregator.sol";

/**
 * @title DeploySepoliaDemo
 * @dev 在 Sepolia 上为已部署的 NFTAuction proxy 补齐演示所需合约：
 *      MyNFT + MockERC20(USDC) + MockAggregator(USDC/USD=$1)，
 *      并给 proxy 添加 USDC 支持、给演示账户铸币。
 *
 * 前置：proxy 已部署（PROXY_ADDRESS 已在 .env 中填好）。
 *
 * 使用方法：
 *   forge script script/DeploySepoliaDemo.s.sol --tc DeploySepoliaDemo \
 *       --rpc-url $SEPOLIA_RPC --broadcast
 */
contract DeploySepoliaDemo is Script {
    // 演示账户（用 anvil 公开地址仅作占位；实际谁连前端谁扮演角色，
    //  这里只是预铸一些 USDC 给几个常见地址方便测试，deployer 自己也会拿到）
    address constant SELLER  = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant BIDDER1 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address constant BIDDER2 = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address proxy = vm.envAddress("PROXY_ADDRESS");

        console.log("=== DeploySepoliaDemo ===");
        console.log("Deployer:", deployer);
        console.log("Proxy:", proxy);

        vm.startBroadcast(pk);

        // 1. USDC/USD 价格源 mock（$1，8 位小数）
        MockAggregator usdcFeed = new MockAggregator(8, int256(1e8));
        console.log("USDC/USD feed:", address(usdcFeed));

        // 2. 测试 USDC（18 位，与本地演示一致）
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 18);
        console.log("USDC:", address(usdc));

        // 3. NFT 合约
        MyNFT nft = new MyNFT();
        console.log("NFT:", address(nft));

        // 4. 给 proxy 添加 USDC 为支持代币（owner = deployer）
        NFTAuction auction = NFTAuction(payable(proxy));
        auction.addSupportedToken(address(usdc), address(usdcFeed));
        console.log("USDC added to auction as supported token");

        // 5. 演示数据：给 deployer 铸一个 NFT（deployer 兼任 seller），
        //    给竞拍者铸 USDC。注意：MyNFT 用 _safeMint，铸给 EOA 在真实链上 OK，
        //    但 forge 模拟执行会对 EOA 调 onERC721Received 而 revert，故铸给 deployer（脚本运行者）。
        nft.mint(deployer, "ipfs://sepolia-demo-nft/1");
        usdc.mint(BIDDER1, 1_000_000 * 1e18);
        usdc.mint(BIDDER2, 1_000_000 * 1e18);
        // deployer 也拿点 USDC 方便自己出价测试
        usdc.mint(deployer, 1_000_000 * 1e18);
        console.log("Demo data minted (NFT #1 -> deployer/seller, USDC -> BIDDER1/BIDDER2/deployer)");

        vm.stopBroadcast();

        console.log("\n=== Sepolia Demo Addresses ===");
        console.log("PROXY        :", proxy);
        console.log("NFT          :", address(nft));
        console.log("USDC         :", address(usdc));
        console.log("ETH_USD_FEED:", 0x694AA1769357215DE4FAC081bf1f309aDC325306); // 真实 Sepolia Chainlink
        console.log("USDC_FEED    :", address(usdcFeed));
        console.log("OWNER        :", deployer);
        console.log("SELLER       :", SELLER);
        console.log("BIDDER1      :", BIDDER1);
        console.log("BIDDER2      :", BIDDER2);
    }
}
