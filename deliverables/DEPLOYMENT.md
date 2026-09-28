# 部署地址

> 网络：Sepolia 测试网（Chain ID 11155111）
> 部署日期：2026-09-18
> Etherscan 源码验证：全部 `Pass - Verified`（2026-09-28）
> RPC：`https://ethereum-sepolia-rpc.publicnode.com`

## 合约地址

| 合约 | 地址 | Etherscan | 验证 |
|---|---|---|---|
| **Proxy（交互入口）** | `0xF2adaB519444dE79b924A5dbfC5d4BeE9934ebD3` | [查看](https://sepolia.etherscan.io/address/0xF2adaB519444dE79b924A5dbfC5d4BeE9934ebD3#code) | ✅ |
| V1 实现 (NFTAuction) | `0xa030bafCdceD188FF0956df9b43a4dACD8a1026D` | [查看](https://sepolia.etherscan.io/address/0xa030bafCdceD188FF0956df9b43a4dACD8a1026D#code) | ✅ |
| V2 实现 (NFTAuctionV2) | `0xd49fa4791E266330Ce3F630F7dc068E4F6A7EFeD` | [查看](https://sepolia.etherscan.io/address/0xd49fa4791E266330Ce3F630F7dc068E4F6A7EFeD#code) | ✅ |
| MyNFT | `0xb1cF5AA6a253Ea7Dbf15D5e948Bf58054f8b61f4` | [查看](https://sepolia.etherscan.io/address/0xb1cF5AA6a253Ea7Dbf15D5e948Bf58054f8b61f4#code) | ✅ |
| MockUSDC | `0xfa3E9dd2bfBA452456f622fb1bd348aC65C4f3Cf` | [查看](https://sepolia.etherscan.io/address/0xfa3E9dd2bfBA452456f622fb1bd348aC65C4f3Cf#code) | ✅ |
| ETH/USD Feed | `0x694AA1769357215DE4FAC081bf1f309aDC325306` | — | Sepolia 真实 Chainlink |
| USDC/USDC Feed (Mock) | `0x4fCFB08C2758C5E3F77EB8b893768472C5F2EF3C` | [查看](https://sepolia.etherscan.io/address/0x4fCFB08C2758C5E3F77EB8b893768472C5F2EF3C#code) | ✅ |

## 部署账户

| 角色 | 地址 |
|---|---|
| Proxy owner / feeRecipient / seller | `0x6243daF140f5E60dCadF72A9F6033828893B4a2d` |

私钥见项目根目录 `.env` 的 `PRIVATE_KEY`（仅测试网，已 gitignore，不会提交）。

## 链上验证记录

部署交易记录在 `broadcast/` 目录。关键交易：

| 步骤 | 交易哈希 |
|---|---|
| V1 + Proxy 部署 | 见 `broadcast/DeployNFTAuction.s.sol/11155111/run-latest.json` |
| V2 升级 | 见 `broadcast/UpgradeNFTAuction.s.sol/11155111/run-latest.json` |
| 演示合约部署 | 见 `broadcast/DeploySepoliaDemo.s.sol/11155111/run-latest.json` |

端到端验证交易：
- 创建拍卖 #1：`0x13525a8c590159a5e202719a3681140b51b6c0152d9aa3089ddedf34fcb2d36b`
- 出价 1.0 ETH：`0xf1f63bdb00389ebb5575a488b0a0d90b209c46446f7b76ae8618168c7b10f85a`