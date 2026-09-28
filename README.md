# NFT Auction Market

基于 Foundry 框架开发的 NFT 拍卖市场，支持 ETH 和 ERC20 出价，集成 Chainlink 预言机进行价格转换，使用 UUPS 代理模式实现合约升级。

## 项目结构

```
nft-auction/
├── foundry.toml              # Foundry 配置文件
├── .env.example              # 环境变量模板
├── README.md                 # 项目文档
├── homework03.md             # 作业题目
├── src/
│   ├── MyNFT.sol             # ERC721 NFT 合约
│   ├── NFTAuction.sol        # 拍卖合约（UUPS 可升级）
│   └── NFTAuctionV2.sol      # 升级版（动态手续费）
├── test/
│   ├── mocks/
│   │   ├── MockERC20.sol     # ERC20 Mock
│   │   └── MockAggregator.sol # Chainlink 预言机 Mock
│   ├── MyNFT.t.sol           # NFT 合约测试
│   └── NFTAuction.t.sol      # 拍卖合约测试 + V2 升级测试
├── script/
│   ├── DeployNFTAuction.s.sol  # V1 + UUPS proxy 部署
│   ├── UpgradeNFTAuction.s.sol # 升级到 V2
│   ├── DeploySepoliaDemo.s.sol # Sepolia 演示合约（NFT/USDC/feed）
│   └── DeployLocal.s.sol       # 本地 anvil 一键演示
├── frontend/                 # MetaMask 前端演示（Sepolia 配置）
├── deliverables/             # 作业交付物（测试报告/部署地址/项目文档）
└── lib/                      # 依赖库（OpenZeppelin / Chainlink / forge-std）
```

## 功能说明

### MyNFT 合约
- 基于 ERC721 标准的 NFT 合约
- 支持 URI 存储元数据
- 只有 owner 可以铸造
- 最大供应量 10,000

### NFTAuction 合约
- **创建拍卖**：卖家将 NFT 上架拍卖，设置起拍价和持续时间
- **ETH 出价**：使用 ETH 出价，通过 Chainlink 预言机转换为 USD 进行比较
- **ERC20 出价**：使用支持的 ERC20 代币出价，同样转换为 USD
- **跨币种比较**：ETH 和 ERC20 出价可以通过 USD 价值进行公平比较
- **结束拍卖**：拍卖结束后，NFT 转移给出价最高者，资金（扣除手续费）转移给卖家
- **退款机制**：被超越的出价者可以提取他们的资金
- **取消拍卖**：卖家可以在没有人出价时取消拍卖
- **5% 最低加价**：每次出价必须高于当前最高出价 5%

### NFTAuctionV2 合约（额外挑战）
- **动态手续费**：根据拍卖金额自动调整手续费
  - < $1,000 → 2.5% 手续费
  - $1,000 ~ $10,000 → 2.0% 手续费
  - ≥ $10,000 → 1.5% 手续费
- 可以启用/禁用动态手续费功能
- 完全向后兼容 V1 数据

### Chainlink 集成
- 使用 `AggregatorV3Interface` 获取实时价格数据
- 支持 ETH/USD 和 ERC20/USD 价格源
- 内置价格过期检测（1小时阈值）
- 自动处理不同精度（8位小数的 USD 价格源）

### UUPS 升级模式
- 使用 OpenZeppelin 的 UUPS 代理模式
- 只有合约 owner 可以执行升级
- 升级时自动调用新版本的初始化函数
- 存储间隙预留，确保升级兼容性

## 安装与设置

### 前置条件
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js (可选)

### 安装步骤

1. 克隆项目并安装依赖：

```bash
cd nft-auction

# 安装依赖
forge install OpenZeppelin/openzeppelin-contracts
forge install OpenZeppelin/openzeppelin-contracts-upgradeable
forge install smartcontractkit/chainlink
# @chainlink/contracts 的实际来源（remappings 指向这里）：
#   下载 chainlink-brownie-contracts 到 lib/，或
#   forge install smartcontractkit/chainlink-brownie-contracts
```

2. 配置环境变量：

```bash
cp .env.example .env
# 编辑 .env 文件，填入你的私钥和API密钥
```

3. 编译合约：

```bash
forge build
```

4. 运行测试：

```bash
forge test
```

## 测试

### 运行所有测试
```bash
forge test
```

### 详细输出
```bash
forge test -vvv
```

### 运行特定测试
```bash
forge test --match-test test_BidWithEth
```

### 查看测试覆盖率
```bash
forge coverage
```

### 分叉测试网测试 Chainlink 集成
```bash
forge test --fork-url $SEPOLIA_RPC --match-test test_GetUsdValueEth
```

## 部署

### 部署到 Sepolia 测试网

```bash
# 部署 NFTAuction（UUPS代理模式）
forge script script/DeployNFTAuction.s.sol \
    --rpc-url $SEPOLIA_RPC \
    --broadcast \
    --verify

# 记录输出的 Proxy Address 并更新 .env 中的 PROXY_ADDRESS
```

### 升级到 V2

```bash
# 确保 .env 中的 PROXY_ADDRESS 已更新
forge script script/UpgradeNFTAuction.s.sol \
    --rpc-url $SEPOLIA_RPC \
    --broadcast
```

### 添加支持的 ERC20 代币

部署后，可以通过合约交互添加支持的 ERC20 代币：

```bash
cast send <PROXY_ADDRESS> "addSupportedToken(address,address)" \
    <TOKEN_ADDRESS> <PRICE_FEED_ADDRESS> \
    --rpc-url $SEPOLIA_RPC \
    --private-key <PRIVATE_KEY>
```

## 合约地址（Sepolia 测试网，已部署并 Etherscan 验证）

| 合约 | 地址 |
|------|------|
| NFTAuction Proxy（交互入口） | `0xF2adaB519444dE79b924A5dbfC5d4BeE9934ebD3` |
| NFTAuction Implementation V1 | `0xa030bafCdceD188FF0956df9b43a4dACD8a1026D` |
| NFTAuctionV2 Implementation | `0xd49fa4791E266330Ce3F630F7dc068E4F6A7EFeD` |
| MyNFT | `0xb1cF5AA6a253Ea7Dbf15D5e948Bf58054f8b61f4` |
| MockUSDC | `0xfa3E9dd2bfBA452456f622fb1bd348aC65C4f3Cf` |
| ETH/USD Feed | `0x694AA1769357215DE4FAC081bf1f309aDC325306`（真实 Chainlink） |

部署详情见 `deliverables/DEPLOYMENT.md`。

## 技术栈

- **Solidity** ^0.8.24
- **Foundry** - 开发框架
- **OpenZeppelin** - 安全合约库
- **Chainlink** - 价格预言机
- **UUPS Proxy** - 可升级代理模式

## 安全注意事项

- 使用 `ReentrancyGuard` 防止重入攻击
- 遵循 Checks-Effects-Interactions (CEI) 模式
- 使用低级 `.call` 进行 ETH 转账并检查返回值
- Chainlink 价格有过期检测
- 所有管理函数都有 `onlyOwner` 修饰符
- 使用自定义错误节省 gas

## License

MIT
