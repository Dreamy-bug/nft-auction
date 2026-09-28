# NFT 拍卖前端演示

Sepolia 测试网 + MetaMask 前端，完整跑一遍 NFT 拍卖流程。合约已部署并经 Etherscan 源码验证。

## 已部署合约（Sepolia，chainId 11155111）

| 合约 | 地址 |
|------|------|
| Proxy（交互入口） | `0xF2adaB519444dE79b924A5dbfC5d4BeE9934ebD3` |
| V1 实现 (NFTAuction) | `0xa030bafCdceD188FF0956df9b43a4dACD8a1026D` |
| V2 实现 (NFTAuctionV2) | `0xd49fa4791E266330Ce3F630F7dc068E4F6A7EFeD` |
| MyNFT | `0xb1cF5AA6a253Ea7Dbf15D5e948Bf58054f8b61f4` |
| MockUSDC | `0xfa3E9dd2bfBA452456f622fb1bd348aC65C4f3Cf` |
| ETH/USD Feed | `0x694AA1769357215DE4FAC081bf1f309aDC325306`（真实 Chainlink） |
| USDC/USD Feed | `0x4fCFB08C2758C5E3F77EB8b893768472C5F2EF3C`（Mock，$1） |

地址都已写入 `contracts.js`。Etherscan 验证：https://sepolia.etherscan.io/address/0xF2adaB519444dE79b924A5dbfC5d4BeE9934ebD3#code

## 启动步骤

> 前置：已安装 Foundry（forge/cast 在 `~/.foundry/bin`，需加入 PATH）。合约**已部署**，无需重新部署；以下仅启动前端。

### 1. 起静态服务
```bash
cd frontend
python -m http.server 8080
# 浏览器打开 http://localhost:8080
```

### 2. 配置 MetaMask
- 添加 Sepolia 网络：RPC `https://ethereum-sepolia-rpc.publicnode.com`，链 ID `11155111`，货币符号 `ETH`，浏览器 `https://sepolia.etherscan.io`（页面"连接"按钮会自动引导添加）
- 导入账户：粘贴 `.env` 中的 `PRIVATE_KEY`（地址 `0x6243daF140f5E60dCadF72A9F6033828893B4a2d`，即 owner/seller/feeRecipient）

### 3. 领水/代币
- deployer 已有约 8.8 Sepolia ETH，可作为 seller
- 竞拍者用自己的 Sepolia 账户；让 deployer 转一些 USDC 过去即可出价（合约已支持 USDC）
- 拍卖接受 ETH 和 USDC 两种出价，通过 Chainlink 价格源换算 USD 公平比价

## 角色与流程
| 账户 | 角色 |
|------|------|
| deployer (`0x6243…4a2d`) | owner / seller / feeRecipient（铸 NFT、创建拍卖、收手续费） |
| 你自己的 Sepolia 账户 | bidder（ETH/USDC 出价） |

**完整流程**：deployer 铸 NFT → approve + 创建拍卖 → 竞拍者 ETH 出价 → 另一竞拍者用 USDC 超越出价（跨币种比价）→ endTime 后任何人结算 → 被超越者提取退款。

> Sepolia 出块约 12s。演示用 `持续=120s`，约 2 分钟后即可结算。
> ETH/USD 用真实 Chainlink 价格源；USDC/USD 用 Mock（$1），1 小时内不会触发 StalePrice。

## 部署命令（仅供参考，合约已部署）

```bash
# V1 + UUPS proxy
forge script script/DeployNFTAuction.s.sol --tc DeployNFTAuction --rpc-url $SEPOLIA_RPC --broadcast --verify

# 升级到 V2（需 .env 的 PROXY_ADDRESS）
forge script script/UpgradeNFTAuction.s.sol --rpc-url $SEPOLIA_RPC --broadcast --verify

# 补部署 NFT/USDC/feed + addSupportedToken + 铸演示币
forge script script/DeploySepoliaDemo.s.sol --tc DeploySepoliaDemo --rpc-url $SEPOLIA_RPC --broadcast --verify
```

## 文件
- `index.html` / `style.css` / `app.js` 前端
- `abi.js` 精简 ABI
- `contracts.js` 部署地址（已填 Sepolia 地址）

## 本地 anvil 版本（可选）

如需纯本地演示（不花测试币），仍有本地脚本：
```bash
anvil --chain-id 31337 --accounts 4
forge script script/DeployLocal.s.sol --tc DeployLocal --rpc-url http://127.0.0.1:8545 --broadcast \
    --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --private-key <account0 私钥>
```
把输出地址填回 `contracts.js`，并把 `app.js` 顶部的 `CHAIN_ID` 改回 `31337n` 即可。当前默认配置为 Sepolia。