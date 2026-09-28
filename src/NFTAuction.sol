// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title NFTAuction
 * @dev 支持ETH和ERC20出价的NFT拍卖合约，使用Chainlink预言机进行价格转换
 * @notice 使用UUPS代理模式实现合约升级
 */
contract NFTAuction is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuard,
    UUPSUpgradeable
{
    // ============ 类型定义 ============

    /**
     * @dev 拍卖结构体
     * @param seller 卖家地址
     * @param nftContract NFT合约地址
     * @param tokenId Token ID
     * @param startPriceUsd 起拍价（USD，8位小数）
     * @param highestBidUsd 当前最高出价（USD，8位小数）
     * @param highestBidder 当前最高出价者
     * @param highestBidToken 最高出价的支付代币（address(0)表示ETH）
     * @param highestBidAmount 最高出价的原始金额（代币单位）
     * @param endTime 拍卖结束时间
     * @param active 拍卖是否活跃
     * @param ended 拍卖是否已结算
     */
    struct Auction {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 startPriceUsd;
        uint256 highestBidUsd;
        address highestBidder;
        address highestBidToken;
        uint256 highestBidAmount;
        uint256 endTime;
        bool active;
        bool ended;
    }

    // ============ 状态变量 ============

    /// @dev ETH/USD Chainlink价格预言机
    AggregatorV3Interface public ethUsdPriceFeed;

    /// @dev ERC20代币地址 => USD Chainlink价格预言机
    mapping(address => AggregatorV3Interface) public tokenPriceFeeds;

    /// @dev 支持的ERC20代币
    mapping(address => bool) public supportedTokens;

    /// @dev 拍卖ID计数器
    uint256 public auctionCounter;

    /// @dev 拍卖ID => 拍卖信息
    mapping(uint256 => Auction) public auctions;

    /// @dev 待退款金额：auctionId => bidder => token => amount
    mapping(uint256 => mapping(address => mapping(address => uint256))) public pendingReturns;

    /// @dev 平台手续费（基点，10000 = 100%）
    uint256 public platformFeeBps;

    /// @dev 手续费接收地址
    address public feeRecipient;

    /// @dev Chainlink USD价格预言机的小数位数
    uint8 public constant USD_DECIMALS = 8;

    /// @dev 价格过期时间（默认1小时）
    uint256 public constant PRICE_STALE_THRESHOLD = 1 hours;

    // ============ 事件定义 ============

    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 startPriceUsd,
        uint256 endTime
    );

    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        address indexed paymentToken,
        uint256 amount,
        uint256 amountUsd
    );

    event AuctionEnded(
        uint256 indexed auctionId,
        address indexed winner,
        address indexed paymentToken,
        uint256 amount,
        uint256 amountUsd
    );

    event AuctionCancelled(uint256 indexed auctionId);

    event BidRefunded(
        uint256 indexed auctionId,
        address indexed bidder,
        address indexed token,
        uint256 amount
    );

    event TokenAdded(address indexed token, address indexed priceFeed);
    event TokenRemoved(address indexed token);

    event PlatformFeeUpdated(uint256 oldBps, uint256 newBps);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    // ============ 自定义错误 ============

    error AuctionNotActive();
    error AuctionAlreadyClosed();
    error AuctionNotEnded();
    error AuctionAlreadyEnded();
    error BidTooLow(uint256 currentBidUsd, uint256 newBidUsd);
    error SellerCannotBid();
    error TokenNotSupported(address token);
    error InvalidPriceFeed();
    error StalePrice();
    error ZeroAddress();
    error ZeroAmount();
    error NoPendingReturn();
    error TransferFailed();
    error NotSeller();
    error HasBids();

    // ============ 初始化函数 ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化函数，在代理部署时调用
     * @param _ethUsdPriceFeed ETH/USD Chainlink价格预言机地址
     * @param _feeRecipient 手续费接收地址
     */
    function initialize(
        address _ethUsdPriceFeed,
        address _feeRecipient
    ) public initializer {
        if (_ethUsdPriceFeed == address(0) || _feeRecipient == address(0))
            revert ZeroAddress();

        __Ownable_init(msg.sender);

        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);
        feeRecipient = _feeRecipient;
        platformFeeBps = 250; // 2.5%
    }

    // ============ UUPS升级授权 ============

    /**
     * @dev 授权升级函数，只有owner可以升级
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // ============ 代币管理 ============

    /**
     * @dev 添加支持的ERC20代币
     * @param token ERC20代币地址
     * @param priceFeed 该代币的USD价格预言机地址
     */
    function addSupportedToken(
        address token,
        address priceFeed
    ) external onlyOwner {
        if (token == address(0) || priceFeed == address(0))
            revert ZeroAddress();
        if (supportedTokens[token])
            revert TokenNotSupported(token); // already supported

        supportedTokens[token] = true;
        tokenPriceFeeds[token] = AggregatorV3Interface(priceFeed);

        emit TokenAdded(token, priceFeed);
    }

    /**
     * @dev 移除支持的ERC20代币
     * @param token ERC20代币地址
     */
    function removeSupportedToken(address token) external onlyOwner {
        if (!supportedTokens[token])
            revert TokenNotSupported(token); // not supported

        supportedTokens[token] = false;
        delete tokenPriceFeeds[token];

        emit TokenRemoved(token);
    }

    // ============ 拍卖管理 ============

    /**
     * @dev 创建拍卖
     * @param nftContract NFT合约地址
     * @param tokenId Token ID
     * @param startPriceUsd 起拍价（USD，8位小数）
     * @param durationSeconds 拍卖持续时间（秒）
     * @return auctionId 拍卖ID
     */
    function createAuction(
        address nftContract,
        uint256 tokenId,
        uint256 startPriceUsd,
        uint256 durationSeconds
    ) external returns (uint256) {
        if (startPriceUsd == 0) revert ZeroAmount();
        if (durationSeconds == 0) revert ZeroAmount();

        IERC721 nft = IERC721(nftContract);

        // 验证所有权
        require(nft.ownerOf(tokenId) == msg.sender, "Not the owner");

        // 验证授权
        require(
            nft.getApproved(tokenId) == address(this) ||
                nft.isApprovedForAll(msg.sender, address(this)),
            "Auction contract not approved"
        );

        // 托管 NFT：转入合约保管，修复双重挂单 + 撤回 approval 漏洞。
        // 创建后 NFT 由合约持有，卖家无法重复挂单或撤回授权影响结算。
        nft.transferFrom(msg.sender, address(this), tokenId);

        auctionCounter++;
        uint256 auctionId = auctionCounter;

        auctions[auctionId] = Auction({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            startPriceUsd: startPriceUsd,
            highestBidUsd: 0,
            highestBidder: address(0),
            highestBidToken: address(0),
            highestBidAmount: 0,
            endTime: block.timestamp + durationSeconds,
            active: true,
            ended: false
        });

        emit AuctionCreated(
            auctionId,
            msg.sender,
            nftContract,
            tokenId,
            startPriceUsd,
            block.timestamp + durationSeconds
        );

        return auctionId;
    }

    /**
     * @dev 取消拍卖（仅在没有出价时）
     * @param auctionId 拍卖ID
     */
    function cancelAuction(uint256 auctionId) external {
        Auction storage auction = auctions[auctionId];

        if (!auction.active) revert AuctionNotActive();
        if (auction.ended) revert AuctionAlreadyEnded();
        if (auction.seller != msg.sender) revert NotSeller();
        if (auction.highestBidder != address(0)) revert HasBids();

        auction.active = false;
        auction.ended = true;

        // 退还托管的 NFT 给卖家
        IERC721(auction.nftContract).transferFrom(
            address(this),
            auction.seller,
            auction.tokenId
        );

        emit AuctionCancelled(auctionId);
    }

    // ============ 出价 ============

    /**
     * @dev 使用ETH出价
     * @param auctionId 拍卖ID
     */
    function bidWithEth(uint256 auctionId) external payable {
        if (msg.value == 0) revert ZeroAmount();

        Auction storage auction = auctions[auctionId];

        if (!auction.active) revert AuctionNotActive();
        if (auction.ended) revert AuctionAlreadyClosed();
        if (block.timestamp >= auction.endTime) revert AuctionAlreadyClosed();
        if (auction.seller == msg.sender) revert SellerCannotBid();

        // 将ETH转换为USD
        uint256 bidUsd = getUsdValueEth(msg.value);

        // 验证出价金额
        uint256 minBidUsd = auction.highestBidUsd == 0
            ? auction.startPriceUsd
            : auction.highestBidUsd + (auction.highestBidUsd * 5 / 100); // 5% 最低加价

        if (bidUsd < minBidUsd)
            revert BidTooLow(minBidUsd, bidUsd);

        // 退款之前的最高出价者
        if (auction.highestBidder != address(0)) {
            pendingReturns[auctionId][auction.highestBidder][
                auction.highestBidToken
            ] += auction.highestBidAmount;
        }

        // 更新最高出价
        auction.highestBidUsd = bidUsd;
        auction.highestBidder = msg.sender;
        auction.highestBidToken = address(0); // ETH
        auction.highestBidAmount = msg.value;

        emit BidPlaced(auctionId, msg.sender, address(0), msg.value, bidUsd);
    }

    /**
     * @dev 使用ERC20代币出价
     * @param auctionId 拍卖ID
     * @param token ERC20代币地址
     * @param amount 出价金额（代币单位）
     */
    function bidWithERC20(
        uint256 auctionId,
        address token,
        uint256 amount
    ) external {
        if (amount == 0) revert ZeroAmount();
        if (!supportedTokens[token]) revert TokenNotSupported(token);

        Auction storage auction = auctions[auctionId];

        if (!auction.active) revert AuctionNotActive();
        if (auction.ended) revert AuctionAlreadyClosed();
        if (block.timestamp >= auction.endTime) revert AuctionAlreadyClosed();
        if (auction.seller == msg.sender) revert SellerCannotBid();

        // 将ERC20代币金额转换为USD
        uint256 bidUsd = getUsdValueToken(token, amount);

        // 验证出价金额
        uint256 minBidUsd = auction.highestBidUsd == 0
            ? auction.startPriceUsd
            : auction.highestBidUsd + (auction.highestBidUsd * 5 / 100); // 5% 最低加价

        if (bidUsd < minBidUsd)
            revert BidTooLow(minBidUsd, bidUsd);

        // 转移ERC20代币到合约
        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "ERC20 transfer failed"
        );

        // 退款之前的最高出价者
        if (auction.highestBidder != address(0)) {
            pendingReturns[auctionId][auction.highestBidder][
                auction.highestBidToken
            ] += auction.highestBidAmount;
        }

        // 更新最高出价
        auction.highestBidUsd = bidUsd;
        auction.highestBidder = msg.sender;
        auction.highestBidToken = token;
        auction.highestBidAmount = amount;

        emit BidPlaced(auctionId, msg.sender, token, amount, bidUsd);
    }

    // ============ 结算 ============

    /**
     * @dev 结束拍卖
     * @param auctionId 拍卖ID
     * @notice 任何人都可以在拍卖结束后调用此函数进行结算
     */
    function endAuction(uint256 auctionId) external virtual nonReentrant {
        Auction storage auction = auctions[auctionId];

        if (!auction.active) revert AuctionNotActive();
        if (auction.ended) revert AuctionAlreadyEnded();
        if (block.timestamp < auction.endTime) revert AuctionNotEnded();

        auction.active = false;
        auction.ended = true;

        if (auction.highestBidder != address(0)) {
            // 有人出价，进行结算
            uint256 feeAmount = (auction.highestBidAmount * platformFeeBps) /
                10000;
            uint256 sellerAmount = auction.highestBidAmount - feeAmount;

            // 从合约托管转 NFT 给赢家
            IERC721(auction.nftContract).safeTransferFrom(
                address(this),
                auction.highestBidder,
                auction.tokenId
            );

            // 资金分配
            if (auction.highestBidToken == address(0)) {
                // ETH支付
                (bool successFee, ) = feeRecipient.call{value: feeAmount}("");
                if (!successFee) revert TransferFailed();

                (bool successSeller, ) = auction.seller.call{
                    value: sellerAmount
                }("");
                if (!successSeller) revert TransferFailed();
            } else {
                // ERC20支付
                require(
                    IERC20(auction.highestBidToken).transfer(
                        feeRecipient,
                        feeAmount
                    ),
                    "Fee transfer failed"
                );
                require(
                    IERC20(auction.highestBidToken).transfer(
                        auction.seller,
                        sellerAmount
                    ),
                    "Seller transfer failed"
                );
            }

            emit AuctionEnded(
                auctionId,
                auction.highestBidder,
                auction.highestBidToken,
                auction.highestBidAmount,
                auction.highestBidUsd
            );
        } else {
            // 没有人出价，拍卖流拍，退回托管的 NFT 给卖家
            IERC721(auction.nftContract).safeTransferFrom(
                address(this),
                auction.seller,
                auction.tokenId
            );
            emit AuctionEnded(auctionId, address(0), address(0), 0, 0);
        }
    }

    // ============ 退款 ============

    /**
     * @dev 提取待退款金额
     * @param auctionId 拍卖ID
     * @param token 代币地址（address(0)表示ETH）
     */
    function withdrawPendingReturn(
        uint256 auctionId,
        address token
    ) external nonReentrant {
        uint256 amount = pendingReturns[auctionId][msg.sender][token];
        if (amount == 0) revert NoPendingReturn();

        // 先清零防止重入
        pendingReturns[auctionId][msg.sender][token] = 0;

        if (token == address(0)) {
            (bool success, ) = msg.sender.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            require(
                IERC20(token).transfer(msg.sender, amount),
                "ERC20 transfer failed"
            );
        }

        emit BidRefunded(auctionId, msg.sender, token, amount);
    }

    // ============ 价格查询 ============

    /**
     * @dev 获取ETH的USD价值
     * @param ethAmount ETH金额（wei）
     * @return usdValue USD价值（8位小数）
     */
    function getUsdValueEth(
        uint256 ethAmount
    ) public view returns (uint256 usdValue) {
        (
            uint80 roundId,
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = ethUsdPriceFeed.latestRoundData();

        if (price <= 0) revert InvalidPriceFeed();
        if (updatedAt == 0 || block.timestamp - updatedAt > PRICE_STALE_THRESHOLD)
            revert StalePrice();
        if (answeredInRound < roundId) revert StalePrice();

        uint8 feedDecimals = ethUsdPriceFeed.decimals();
        // ethAmount (18 decimals) * price => divide by 10^(feedDecimals + 10) to get 8-decimal USD
        usdValue =
            (ethAmount * uint256(price)) /
            (10 ** (uint256(feedDecimals) + 18 - USD_DECIMALS));
    }

    /**
     * @dev 获取ERC20代币的USD价值
     * @param token ERC20代币地址
     * @param tokenAmount 代币金额（最小单位）
     * @return usdValue USD价值（8位小数）
     */
    function getUsdValueToken(
        address token,
        uint256 tokenAmount
    ) public view returns (uint256 usdValue) {
        if (!supportedTokens[token]) revert TokenNotSupported(token);

        AggregatorV3Interface priceFeed = tokenPriceFeeds[token];
        (
            uint80 roundId,
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        if (price <= 0) revert InvalidPriceFeed();
        if (updatedAt == 0 || block.timestamp - updatedAt > PRICE_STALE_THRESHOLD)
            revert StalePrice();
        if (answeredInRound < roundId) revert StalePrice();

        uint8 feedDecimals = priceFeed.decimals();

        usdValue =
            (tokenAmount * uint256(price)) /
            (10 ** (uint256(feedDecimals) + 18 - USD_DECIMALS));
    }

    /**
     * @dev 获取拍卖的USD最低出价
     * @param auctionId 拍卖ID
     * @return minBidUsd 最低出价（USD，8位小数）
     */
    function getMinBidUsd(
        uint256 auctionId
    ) external view returns (uint256 minBidUsd) {
        Auction storage auction = auctions[auctionId];
        if (auction.highestBidUsd == 0) {
            return auction.startPriceUsd;
        }
        return auction.highestBidUsd + (auction.highestBidUsd * 5 / 100);
    }

    // ============ 管理函数 ============

    /**
     * @dev 设置平台手续费
     * @param newBps 新的手续费（基点）
     * @notice 最大10%
     */
    function setPlatformFee(uint256 newBps) external onlyOwner {
        require(newBps <= 1000, "Fee too high"); // 最大10%
        uint256 oldBps = platformFeeBps;
        platformFeeBps = newBps;

        emit PlatformFeeUpdated(oldBps, newBps);
    }

    /**
     * @dev 更新手续费接收地址
     * @param newRecipient 新的接收地址
     */
    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ZeroAddress();
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;

        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    /**
     * @dev 更新ETH/USD价格预言机
     * @param newPriceFeed 新的价格预言机地址
     */
    function setEthUsdPriceFeed(address newPriceFeed) external onlyOwner {
        if (newPriceFeed == address(0)) revert ZeroAddress();
        ethUsdPriceFeed = AggregatorV3Interface(newPriceFeed);
    }

    /**
     * @dev 更新ERC20代币的价格预言机
     * @param token ERC20代币地址
     * @param newPriceFeed 新的价格预言机地址
     */
    function setTokenPriceFeed(
        address token,
        address newPriceFeed
    ) external onlyOwner {
        if (!supportedTokens[token]) revert TokenNotSupported(token);
        if (newPriceFeed == address(0)) revert ZeroAddress();
        tokenPriceFeeds[token] = AggregatorV3Interface(newPriceFeed);
    }

    // ============ 存储间隙 ============

    /**
     * @dev 为未来升级预留存储空间
     */
    uint256[40] private __gap;
}
