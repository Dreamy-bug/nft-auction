// 精简 ABI —— 仅包含前端演示所需函数与事件
// 合约源码: src/NFTAuction.sol, NFTAuctionV2.sol, MyNFT.sol, test/mocks/*

const NFTAuctionABI = [
  // 初始化/管理
  "function initialize(address _ethUsdPriceFeed, address _feeRecipient) external",
  "function addSupportedToken(address token, address priceFeed) external",
  "function removeSupportedToken(address token) external",
  "function setPlatformFee(uint256 newBps) external",
  "function setFeeRecipient(address newRecipient) external",
  "function owner() view returns (address)",
  "function feeRecipient() view returns (address)",
  "function platformFeeBps() view returns (uint256)",
  "function ethUsdPriceFeed() view returns (address)",
  "function supportedTokens(address) view returns (bool)",
  "function auctionCounter() view returns (uint256)",
  // 拍卖
  "function createAuction(address nftContract, uint256 tokenId, uint256 startPriceUsd, uint256 durationSeconds) external returns (uint256)",
  "function cancelAuction(uint256 auctionId) external",
  "function bidWithEth(uint256 auctionId) external payable",
  "function bidWithERC20(uint256 auctionId, address token, uint256 amount) external",
  "function endAuction(uint256 auctionId) external",
  "function withdrawPendingReturn(uint256 auctionId, address token) external",
  // 查询
  "function getMinBidUsd(uint256 auctionId) view returns (uint256)",
  "function getUsdValueEth(uint256 ethAmount) view returns (uint256)",
  "function getUsdValueToken(address token, uint256 tokenAmount) view returns (uint256)",
  "function auctions(uint256) view returns (address seller, address nftContract, uint256 tokenId, uint256 startPriceUsd, uint256 highestBidUsd, address highestBidder, address highestBidToken, uint256 highestBidAmount, uint256 endTime, bool active, bool ended)",
  "function pendingReturns(uint256, address, address) view returns (uint256)",
  // 事件
  "event AuctionCreated(uint256 indexed auctionId, address indexed seller, address indexed nftContract, uint256 tokenId, uint256 startPriceUsd, uint256 endTime)",
  "event BidPlaced(uint256 indexed auctionId, address indexed bidder, address indexed paymentToken, uint256 amount, uint256 amountUsd)",
  "event AuctionEnded(uint256 indexed auctionId, address indexed winner, address indexed paymentToken, uint256 amount, uint256 amountUsd)",
  "event AuctionCancelled(uint256 indexed auctionId)",
  "event BidRefunded(uint256 indexed auctionId, address indexed bidder, address indexed token, uint256 amount)",
  "event TokenAdded(address indexed token, address indexed priceFeed)",
];

const NFTAuctionV2ABI = [
  "function initializeV2(uint256[3] _feeTiers, uint256[2] _feeThresholds) external",
  "function upgradeToAndCall(address newImplementation, bytes memory data) external",
  "function version() pure returns (string memory)",
  "function dynamicFeeEnabled() view returns (bool)",
  "function getDynamicFeeBps(uint256 amountUsd) view returns (uint256)",
  "function feeTiers(uint256) view returns (uint256)",
  "function feeThresholds(uint256) view returns (uint256)",
  "function disableDynamicFee() external",
  "function enableDynamicFee(uint256[3] _feeTiers, uint256[2] _feeThresholds) external",
];

const MyNFTABI = [
  "function mint(address to, string memory uri) external returns (uint256)",
  "function ownerOf(uint256 tokenId) view returns (address)",
  "function tokenURI(uint256 tokenId) view returns (string memory)",
  "function totalSupply() view returns (uint256)",
  "function approve(address to, uint256 tokenId) external",
  "function setApprovalForAll(address operator, bool approved) external",
  "function getApproved(uint256 tokenId) view returns (address)",
  "function isApprovedForAll(address owner, address operator) view returns (bool)",
  "function balanceOf(address owner) view returns (uint256)",
  "function name() view returns (string memory)",
  "function symbol() view returns (string memory)",
  "event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)",
  "event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId)",
];

const MockERC20ABI = [
  "function mint(address to, uint256 amount) external",
  "function name() view returns (string memory)",
  "function symbol() view returns (string memory)",
  "function decimals() view returns (uint8)",
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address, address) view returns (uint256)",
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function transfer(address to, uint256 amount) external returns (bool)",
];

const MockAggregatorABI = [
  "function latestRoundData() view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)",
  "function decimals() view returns (uint8)",
  "function setAnswer(int256 _newAnswer) external",
];

if (typeof window !== "undefined") {
  window.ABIS = {
    NFTAuction: NFTAuctionABI,
    NFTAuctionV2: NFTAuctionV2ABI,
    MyNFT: MyNFTABI,
    MockERC20: MockERC20ABI,
    MockAggregator: MockAggregatorABI,
  };
}
