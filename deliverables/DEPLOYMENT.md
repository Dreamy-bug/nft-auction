# 部署地址

> 网络：Sepolia 测试网（Chain ID 11155111）
> 部署日期：2026-09-28（本次为托管模式修复后的重新部署）
> Etherscan 源码验证：全部 `Pass - Verified`（2026-09-28）
> RPC：`https://ethereum-sepolia-rpc.publicnode.com`

## 合约地址

| 合约 | 地址 | Etherscan | 验证 |
|---|---|---|---|
| **Proxy（交互入口）** | `0x4515b3F0e70f136B1768433d9df208D90aCb9A48` | [查看](https://sepolia.etherscan.io/address/0x4515b3F0e70f136B1768433d9df208D90aCb9A48#code) | ✅ |
| V1 实现 (NFTAuction) | `0x0e73Bb70fD615e9a77bbE700b30eD9A924524097` | [查看](https://sepolia.etherscan.io/address/0x0e73Bb70fD615e9a77bbE700b30eD9A924524097#code) | ✅ |
| V2 实现 (NFTAuctionV2，proxy 当前指向) | `0x71218133E02B4acc0fEbb67eA76125907B59f19B` | [查看](https://sepolia.etherscan.io/address/0x71218133E02B4acc0fEbb67eA76125907B59f19B#code) | ✅ |
| MyNFT | `0x06d2CEA962A471D71F7485cf9124E3eCF57BE99a` | [查看](https://sepolia.etherscan.io/address/0x06d2CEA962A471D71F7485cf9124E3eCF57BE99a#code) | ✅ |
| MockUSDC | `0x7DAD41c6CC96f508D9fa2EDEC38708FC2d7F236E` | [查看](https://sepolia.etherscan.io/address/0x7DAD41c6CC96f508D9fa2EDEC38708FC2d7F236E#code) | ✅ |
| ETH/USD Feed | `0x694AA1769357215DE4FAC081bf1f309aDC325306` | — | Sepolia 真实 Chainlink |
| USDC/USD Feed (Mock) | `0x279eFaaa49D6Eae9cD96FD6be72Ac8cF1b384Ac3` | [查看](https://sepolia.etherscan.io/address/0x279eFaaa49D6Eae9cD96FD6be72Ac8cF1b384Ac3#code) | ✅ |

## 部署账户

| 角色 | 地址 |
|---|---|
| Proxy owner / feeRecipient / seller | `0x6243daF140f5E60dCadF72A9F6033828893B4a2d` |

私钥见项目根目录 `.env` 的 `PRIVATE_KEY`（仅测试网，已 gitignore，不会提交）。

## 本次部署说明

本次重新部署是为了落地**双重挂单 + 撤回 approval 资金锁死漏洞的修复（托管模式方案 1）**：
- `createAuction` 现在会 `transferFrom(seller, this, tokenId)` 把 NFT 托管进合约；
- `endAuction` 从合约转给赢家，流拍 / `cancelAuction` 退回卖家。

旧部署（2026-09-18，含漏洞）地址已废弃，请勿交互：

| 旧合约 | 旧地址（已废弃） |
|---|---|
| Proxy | `0xF2adaB519444dE79b924A5dbfC5d4BeE9934ebD3` |
| V1 实现 | `0xa030bafCdceD188FF0956df9b43a4dACD8a1026D` |
| V2 实现 | `0xd49fa4791E266330Ce3F630F7dc068E4F6A7EFeD` |

## 链上验证记录

部署交易记录在 `broadcast/` 目录。关键交易：

| 步骤 | 交易哈希 |
|---|---|
| V1 + Proxy 部署 | 见 `broadcast/DeployNFTAuction.s.sol/11155111/run-latest.json` |
| V2 升级 | 见 `broadcast/UpgradeNFTAuction.s.sol/11155111/run-latest.json` |
| 演示合约部署 | 见 `broadcast/DeploySepoliaDemo.s.sol/11155111/run-latest.json` |

### 托管模式链上验证（2026-09-28）

修复后的 `createAuction` 在 Sepolia 真实执行，确认 NFT 被托管进合约：

- `setApprovalForAll(proxy, true)` — tx `0xcb99691c5137460c11e37cc543b7e6785feafe48c93bfc4b68dc767f939c2cc7`
- `createAuction(NFT, tokenId=1, startPrice=1000e8 USD, 1天)` — tx `0x458dd4c29498034d6217051a10b5bb9e13ec6bc9c4ada794e08350046cbff528`
  - 该笔交易内 NFT 合约发出 `Transfer(from=deployer → to=proxy, tokenId=1)` 事件 = 托管转账已发生
- 调用后 `ownerOf(1)` = `0x4515b3F0...`（proxy 地址）= NFT 确实被合约托管 ✓
- `auctionCounter()` = 1