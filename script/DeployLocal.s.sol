// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import "../src/NFTAuction.sol";
import "../src/NFTAuctionV2.sol";
import "../src/MyNFT.sol";
import "../test/mocks/MockERC20.sol";
import "../test/mocks/MockAggregator.sol";

/**
 * @title DeployLocal
 * @dev 本地 anvil 一键部署：Mock 价格源 + NFT + 拍卖(UUPS代理) + V2实现 + 演示数据
 *
 * 使用方法：
 *   anvil --chain-id 31337   # 先起本地链
 *   forge script script/DeployLocal.s.sol \
 *       --rpc-url http://127.0.0.1:8545 --broadcast \
 *       --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf8e68d4e
 *
 * account0 为 deployer/owner/feeRecipient。
 */
contract DeployLocal is Script {
    // anvil 默认账户
    address constant SELLER  = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // account1
    address constant BIDDER1 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // account2
    address constant BIDDER2 = 0x90F79bf6EB2c4f870365E785982E1f101E93b906; // account3

    function run() external {
        // vm.startBroadcast() 无参 → 用命令行 --private-key 注入的账户(account0)
        vm.startBroadcast();

        // 1. 价格源
        MockAggregator ethUsdFeed = new MockAggregator(8, int256(2000e8));   // ETH = $2000
        MockAggregator usdcFeed  = new MockAggregator(8, int256(1e8));      // USDC = $1

        // 2. ERC20 竞拍代币
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 18);

        // 3. NFT 合约
        MyNFT nft = new MyNFT();

        // 4. NFTAuction V1 实现 + UUPS 代理
        NFTAuction implV1 = new NFTAuction();
        bytes memory initData = abi.encodeCall(
            NFTAuction.initialize,
            (address(ethUsdFeed), msg.sender) // feeRecipient = deployer(account0)
        );
        LocalProxy proxy = new LocalProxy(address(implV1), initData);
        NFTAuction auction = NFTAuction(payable(address(proxy)));

        // 5. 预部署 V2 实现（供前端升级按钮使用）
        NFTAuctionV2 implV2 = new NFTAuctionV2();

        // 6. 配置：添加 USDC 为支持代币
        auction.addSupportedToken(address(usdc), address(usdcFeed));

        // 7. 演示数据：给卖家铸一个 NFT（tokenId=1），给竞拍者铸 USDC
        nft.mint(SELLER, "ipfs://demo-nft/1");
        usdc.mint(BIDDER1, 1_000_000 * 1e18);
        usdc.mint(BIDDER2, 1_000_000 * 1e18);

        vm.stopBroadcast();

        // 输出地址（部署后据此填充 frontend/contracts.js）
        console.log("=== DeployLocal Addresses ===");
        console.log("PROXY         :", address(proxy));
        console.log("IMPL_V1       :", address(implV1));
        console.log("IMPL_V2       :", address(implV2));
        console.log("NFT           :", address(nft));
        console.log("USDC          :", address(usdc));
        console.log("ETH_USD_FEED  :", address(ethUsdFeed));
        console.log("USDC_FEED     :", address(usdcFeed));
        console.log("OWNER         :", msg.sender);
        console.log("SELLER        :", SELLER);
        console.log("BIDDER1       :", BIDDER1);
        console.log("BIDDER2       :", BIDDER2);
        console.log("ETH price     : $2000 (8d)");
        console.log("USDC price    : $1 (8d)");
    }
}

/**
 * @dev 与项目内极简 ERC1967Proxy 同实现，改名为 LocalProxy 避免与
 *      script/DeployNFTAuction.s.sol 中的 ERC1967Proxy 重名冲突。
 *      仅靠 fallback delegatecall；升级时对代理调用 upgradeToAndCall，
 *      会经 fallback 委托到实现合约（UUPSUpgradeable）。
 */
contract LocalProxy {
    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor(address implementation, bytes memory _data) {
        assembly {
            sstore(_IMPLEMENTATION_SLOT, implementation)
        }
        if (_data.length > 0) {
            (bool success, ) = implementation.delegatecall(_data);
            require(success, "Proxy: initialization failed");
        }
    }

    fallback() external payable {
        _delegate();
    }

    receive() external payable {
        _delegate();
    }

    function _delegate() internal {
        address impl;
        assembly {
            impl := sload(_IMPLEMENTATION_SLOT)
        }
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
