# NFT 拍卖智能合约 — 项目文档

> Foundry 实现的 NFT 拍卖智能合约系统。卖家挂单 ERC721 NFT，竞拍者用 **ETH 或白名单 ERC20** 出价；通过 **Chainlink `AggregatorV3Interface`** 价格源把不同币种换算成 USD 公平比价。合约以 **UUPS 代理** 部署，可升级到 V2（动态手续费）。

## 1. 功能说明

### 核心流程
1. **创建拍卖** `createAuction(nft, tokenId, startPriceUsd, duration)` — 卖家注册 NFT（须拥有并 approve 合约）；NFT **不托管**，留在卖家手里直到结算时直接 `safeTransferFrom` 卖家→赢家。
2. **出价** `bidWithEth(auctionId)` / `bidWithERC20(auctionId, token, amount)` — 换算成 USD，强制 **5% 最小增量**。被超越的出价记入 `pendingReturns[auctionId][bidder][token]` 待退（`address(0)` 位置 = ETH）。
3. **结算** `endAuction(auctionId)` — 任何人可在 `endTime` 后调用；最高出价扣手续费给 `feeRecipient`，剩余给卖家，NFT 转给赢家。
4. **退款** `withdrawPendingReturn(auctionId, token)` — 被超越的竞拍者取回资金。
5. **取消** `cancelAuction(auctionId)` — 仅卖家，且无人出价时。

### USD 换算与预言机安全（`getUsdValueEth` / `getUsdValueToken`）
- 读 `latestRoundData`，价格 ≤ 0 时 `revert InvalidPriceFeed`
- `updatedAt` 为 0 / 超过 1h / `answeredInRound < roundId` 时 `revert StalePrice`
- USD 值归一化到 **8 位小数**（`USD_DECIMALS`）

### V2 动态手续费
- `feeTiers[3]` bps + `feeThresholds[2]` USD（降序）：< thr0 → tier0，< thr1 → tier1，else tier2
- 当前配置：`<$1000 → 2.5%`，`$1000–$10000 → 2%`，`≥$10000 → 1.5%`
- `dynamicFeeEnabled == false` 时回退 V1 固定费（默认 2.5%）
- 通过 `initializeV2` + `reinitializer(2)` 初始化

### 管理功能（owner）
`addSupportedToken` / `removeSupportedToken` / `setPlatformFee` / `setFeeRecipient` / `setEthUsdPriceFeed`

### 安全特性
- `endAuction` / `withdrawPendingReturn` 为 `nonReentrant`，外部转账前置零状态（CEI）
- 卖家不能自抬价（`SellerCannotBid`）
- UUPS 升级权限 `onlyOwner`
- 价格源多重安全校验

## 2. 项目结构

```
nft-auction/
├── src/
│   ├── NFTAuction.sol       # V1 实现（UUPS 代理后）
│   ├── NFTAuctionV2.sol    # V2 动态手续费
│   └── MyNFT.sol            # ERC721
├── test/
│   ├── NFTAuction.t.sol    # 核心测试 + V2 升级测试
│   ├── MyNFT.t.sol
│   └── mocks/               # MockAggregator, MockERC20
├── script/
│   ├── DeployNFTAuction.s.sol   # V1+proxy 部署
│   ├── UpgradeNFTAuction.s.sol  # V2 升级
│   ├── DeploySepoliaDemo.s.sol  # Sepolia 演示合约（NFT/USDC/feed）
│   └── DeployLocal.s.sol        # 本地 anvil 一键演示
├── frontend/                # MetaMask 前端演示
├── foundry.toml
├── remappings.txt
├── .env.example
└── deliverables/           # 作业交付物
```

## 3. 部署步骤

### 前置准备
1. 安装 Foundry（`forge`/`cast`/`anvil`），加入 PATH
2. 复制 `.env.example` 为 `.env`，填入：
   - `PRIVATE_KEY` — 有 Sepolia ETH 余额的账户私钥
   - `SEPOLIA_RPC` — Sepolia RPC 节点
   - `ETHERSCAN_API_KEY` — Etherscan API key（用于验证）
   - `ETH_USD_PRICE_FEED=0x694AA1769357215DE4FAC081bf1f309aDC325306`（Sepolia 真实 Chainlink）
   - `FEE_RECIPIENT` — 手续费接收地址
3. 领 Sepolia 测试 ETH（faucet：注意多数 faucet 要求主网少量余额防刷）

### 编译与测试
```bash
forge build           # 编译
forge test           # 跑全部 68 个测试
forge coverage        # 覆盖率报告
```

### 部署到 Sepolia

```bash
# 1. 部署 V1 实现 + UUPS 代理 + initialize
forge script script/DeployNFTAuction.s.sol --tc DeployNFTAuction \
    --rpc-url $SEPOLIA_RPC --broadcast --verify

# 脚本会输出 Proxy 地址，填回 .env 的 PROXY_ADDRESS

# 2. 升级到 V2（动态手续费）
forge script script/UpgradeNFTAuction.s.sol \
    --rpc-url $SEPOLIA_RPC --broadcast --verify

# 3. 补部署演示合约（NFT / USDC / USDC-USD feed）+ addSupportedToken + 铸演示币
forge script script/DeploySepoliaDemo.s.sol --tc DeploySepoliaDemo \
    --rpc-url $SEPOLIA_RPC --broadcast --verify
```

### 已部署地址（Sepolia，2026-09-18）

完整地址表见 [DEPLOYMENT.md](./DEPLOYMENT.md)。代理入口：
```
0xF2adaB519444dE79b924A5dbfC5d4BeE9934ebD3
```

## 4. 前端演示

合约已部署，前端已配置为 Sepolia。启动：

```bash
cd frontend
python -m http.server 8080
# 浏览器打开 http://localhost:8080
```

MetaMask 切到 Sepolia 网络，导入 deployer 私钥即可操作完整拍卖流程。详见 `frontend/README.md`。

## 5. 合理测试覆盖

- 单元测试：68 个，覆盖创建/出价/结算/退款/跨币种比价/预言机安全/升级/动态费
- 链上端到端：Sepolia 真实交易创建拍卖 + 出价（见 [DEPLOYMENT.md](./DEPLOYMENT.md)）

## 6. 交付清单

| 交付物 | 位置 |
|---|---|
| 项目代码 | 项目根目录（src/ test/ script/ frontend/） |
| 测试报告 | `deliverables/TEST_REPORT.md` |
| 部署地址 | `deliverables/DEPLOYMENT.md` |
| 项目文档 | 本文件 |