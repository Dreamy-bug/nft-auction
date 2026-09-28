// 部署地址 —— Sepolia 测试网 (chainId 11155111)
// 由 script/DeployNFTAuction.s.sol + DeploySepoliaDemo.s.sol 部署
// 真实 Chainlink ETH/USD feed + Mock USDC/USD feed
const CONTRACTS = {
  PROXY:        "0xF2adaB519444dE79b924A5dbfC5d4BeE9934ebD3",  // UUPS 代理，交互入口
  IMPL_V1:      "0xa030bafCdceD188FF0956df9b43a4dACD8a1026D",  // V1 实现
  IMPL_V2:      "0xd49fa4791E266330Ce3F630F7dc068E4F6A7EFeD",  // V2 实现（当前）
  NFT:          "0xb1cF5AA6a253Ea7Dbf15D5e948Bf58054f8b61f4",
  USDC:         "0xfa3E9dd2bfBA452456f622fb1bd348aC65C4f3Cf",
  ETH_USD_FEED:"0x694AA1769357215DE4FAC081bf1f309aDC325306",  // 真实 Sepolia Chainlink ETH/USD
  USDC_FEED:    "0x4fCFB08C2758C5E3F77EB8b893768472C5F2EF3C",  // Mock USDC/USD = $1
};

// Sepolia 演示账户说明：
// - deployer (0x6243daF140f5E60dCadF72A9F6033828893B4a2d)：owner/NFT 持有者(seller)/feeRecipient
//   私钥在项目 .env，导入 MetaMask 即可操作
// - BIDDER1/BIDDER2 已预铸 1,000,000 USDC，但需各自导入对应私钥才能操作
//   （下面 anvil 公开账户仅为占位，Sepolia 上这些地址的私钥你未必持有）
//   推荐：用你自己的 Sepolia 账户当竞拍者，让 deployer 转一些 USDC 过去即可。
const ACCOUNTS = [
  { role: "owner/deployer/seller/feeRecipient", label: "deployer",
    addr: "0x6243daF140f5E60dCadF72A9F6033828893B4a2d",
    key:  "见项目 .env（PRIVATE_KEY），导入 MetaMask 使用" },
  { role: "bidder1（USDC 出价）", label: "bidder1（占位）",
    addr: "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
    key:  "Sepolia 上未必持有此私钥，建议用自己账户" },
  { role: "bidder2（USDC 出价）", label: "bidder2（占位）",
    addr: "0x90F79bf6EB2c4f870365E785982E1f101E93b906",
    key:  "Sepolia 上未必持有此私钥，建议用自己账户" },
];

if (typeof window !== "undefined") {
  window.CONTRACTS = CONTRACTS;
  window.ACCOUNTS = ACCOUNTS;
}
