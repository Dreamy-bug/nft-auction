// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/NFTAuction.sol";
import "../src/NFTAuctionV2.sol";
import "../src/MyNFT.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockAggregator.sol";

contract NFTAuctionTest is Test {
    NFTAuction public auction;
    MyNFT public nft;
    MockERC20 public usdc;
    MockAggregator public ethUsdFeed;
    MockAggregator public usdcUsdFeed;

    address public owner;
    address public seller;
    address public bidder1;
    address public bidder2;
    address public feeRecipient;

    uint256 constant ETH_PRICE = 2000e8;

    // 事件声明（用于测试vm.expectEmit）
    event AuctionCreated(uint256 indexed auctionId, address indexed seller, address indexed nftContract, uint256 tokenId, uint256 startPriceUsd, uint256 endTime);
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, address indexed paymentToken, uint256 amount, uint256 amountUsd);
    event AuctionEnded(uint256 indexed auctionId, address indexed winner, address indexed paymentToken, uint256 amount, uint256 amountUsd);
    event AuctionCancelled(uint256 indexed auctionId);
    event BidRefunded(uint256 indexed auctionId, address indexed bidder, address indexed token, uint256 amount);
    event TokenAdded(address indexed token, address indexed priceFeed);
    event TokenRemoved(address indexed token);
    event PlatformFeeUpdated(uint256 oldBps, uint256 newBps);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    uint256 constant USDC_PRICE = 1e8;
    uint256 constant START_PRICE_USD = 1000e8;
    uint256 constant AUCTION_DURATION = 1 days;

    function setUp() public {
        owner = address(this);
        seller = makeAddr("seller");
        bidder1 = makeAddr("bidder1");
        bidder2 = makeAddr("bidder2");
        feeRecipient = makeAddr("feeRecipient");

        ethUsdFeed = new MockAggregator(8, int256(ETH_PRICE));
        usdcUsdFeed = new MockAggregator(8, int256(USDC_PRICE));

        nft = new MyNFT();
        usdc = new MockERC20("USD Coin", "USDC", 18);

        // 部署V1通过UUPS代理
        NFTAuction implementation = new NFTAuction();
        bytes memory initData = abi.encodeCall(
            NFTAuction.initialize,
            (address(ethUsdFeed), feeRecipient)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        auction = NFTAuction(address(proxy));

        auction.addSupportedToken(address(usdc), address(usdcUsdFeed));

        nft.mint(seller, "uri1");
        nft.mint(seller, "uri2");

        usdc.mint(bidder1, 1_000_000 * 1e18);
        usdc.mint(bidder2, 1_000_000 * 1e18);

        vm.prank(seller);
        nft.setApprovalForAll(address(auction), true);

        vm.prank(bidder1);
        usdc.approve(address(auction), type(uint256).max);
        vm.prank(bidder2);
        usdc.approve(address(auction), type(uint256).max);
    }

    // ============ 1. 部署与初始化测试 ============

    function test_Initialize() public view {
        assertEq(auction.owner(), owner);
        assertEq(auction.feeRecipient(), feeRecipient);
        assertEq(auction.platformFeeBps(), 250);
        assertEq(address(auction.ethUsdPriceFeed()), address(ethUsdFeed));
    }

    function test_CannotReinitialize() public {
        vm.expectRevert();
        auction.initialize(address(ethUsdFeed), feeRecipient);
    }

    // ============ 2. 代币管理测试 ============

    function test_AddSupportedToken() public {
        MockERC20 newToken = new MockERC20("New Token", "NTK", 18);
        MockAggregator newFeed = new MockAggregator(8, 5e8);

        auction.addSupportedToken(address(newToken), address(newFeed));
        assertTrue(auction.supportedTokens(address(newToken)));
    }

    function test_AddSupportedTokenEmitsEvent() public {
        MockERC20 newToken = new MockERC20("New Token", "NTK", 18);
        MockAggregator newFeed = new MockAggregator(8, 5e8);

        vm.expectEmit(true, true, false, false);
        emit TokenAdded(address(newToken), address(newFeed));
        auction.addSupportedToken(address(newToken), address(newFeed));
    }

    function test_AddSupportedTokenNotOwnerReverts() public {
        MockERC20 newToken = new MockERC20("New Token", "NTK", 18);
        MockAggregator newFeed = new MockAggregator(8, 5e8);

        vm.prank(bidder1);
        vm.expectRevert();
        auction.addSupportedToken(address(newToken), address(newFeed));
    }

    function test_AddSupportedTokenZeroAddressReverts() public {
        vm.expectRevert(NFTAuction.ZeroAddress.selector);
        auction.addSupportedToken(address(0), address(usdcUsdFeed));
    }

    function test_RemoveSupportedToken() public {
        auction.removeSupportedToken(address(usdc));
        assertFalse(auction.supportedTokens(address(usdc)));
    }

    function test_RemoveSupportedTokenEmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit TokenRemoved(address(usdc));
        auction.removeSupportedToken(address(usdc));
    }

    function test_RemoveUnsupportedTokenReverts() public {
        vm.expectRevert();
        auction.removeSupportedToken(address(0xdead));
    }

    // ============ 3. 创建拍卖测试 ============

    function test_CreateAuction() public {
        vm.prank(seller);
        uint256 auctionId = auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        assertEq(auctionId, 1);

        (
            address _seller,
            address _nftContract,
            uint256 _tokenId,
            uint256 _startPriceUsd,
            uint256 _highestBidUsd,
            address _highestBidder,
            address _highestBidToken,
            uint256 _highestBidAmount,
            uint256 _endTime,
            bool _active,
            bool _ended
        ) = auction.auctions(1);

        assertEq(_seller, seller);
        assertEq(_nftContract, address(nft));
        assertEq(_tokenId, 1);
        assertEq(_startPriceUsd, START_PRICE_USD);
        assertEq(_highestBidUsd, 0);
        assertEq(_highestBidder, address(0));
        assertEq(_highestBidToken, address(0));
        assertEq(_highestBidAmount, 0);
        assertTrue(_active);
        assertFalse(_ended);
    }

    function test_CreateAuctionEmitsEvent() public {
        vm.prank(seller);
        vm.expectEmit(true, true, true, false);
        emit AuctionCreated(1, seller, address(nft), 1, START_PRICE_USD, block.timestamp + AUCTION_DURATION);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);
    }

    function test_CreateAuctionNotOwnerReverts() public {
        vm.prank(bidder1);
        vm.expectRevert("Not the owner");
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);
    }

    function test_CreateAuctionNotApprovedReverts() public {
        nft.mint(seller, "uri3");
        // 新铸造的NFT没有设置授权
        // 取消seller的全局授权
        vm.prank(seller);
        nft.setApprovalForAll(address(auction), false);

        vm.prank(seller);
        vm.expectRevert("Auction contract not approved");
        auction.createAuction(address(nft), 3, START_PRICE_USD, AUCTION_DURATION);

        // 恢复授权
        vm.prank(seller);
        nft.setApprovalForAll(address(auction), true);
    }

    function test_CreateAuctionZeroStartPriceReverts() public {
        vm.prank(seller);
        vm.expectRevert(NFTAuction.ZeroAmount.selector);
        auction.createAuction(address(nft), 1, 0, AUCTION_DURATION);
    }

    function test_CreateAuctionZeroDurationReverts() public {
        vm.prank(seller);
        vm.expectRevert(NFTAuction.ZeroAmount.selector);
        auction.createAuction(address(nft), 1, START_PRICE_USD, 0);
    }

    // ============ 4. ETH出价测试 ============

    function test_BidWithEth() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        uint256 bidAmount = 0.5 ether; // $1000 at $2000/ETH

        vm.deal(bidder1, bidAmount);
        vm.prank(bidder1);
        auction.bidWithEth{value: bidAmount}(1);

        (,,,,uint256 highestBidUsd,address highestBidder,address highestBidToken,uint256 highestBidAmount,,,) = auction.auctions(1);

        assertEq(highestBidder, bidder1);
        assertEq(highestBidToken, address(0));
        assertEq(highestBidAmount, bidAmount);
        assertGe(highestBidUsd, START_PRICE_USD);
    }

    function test_BidWithEthHigherBid() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        // 第一次出价
        vm.deal(bidder1, 1 ether);
        vm.prank(bidder1);
        auction.bidWithEth{value: 0.5 ether}(1);

        // 第二次出价更高：0.6 ETH = $1200 > $1050
        vm.deal(bidder2, 1 ether);
        vm.prank(bidder2);
        auction.bidWithEth{value: 0.6 ether}(1);

        (,,,, uint256 highestBidUsd, address highestBidder,,,,,) = auction.auctions(1);

        assertEq(highestBidder, bidder2);
        assertGt(highestBidUsd, 1000e8);
    }

    function test_BidWithEthTooLowReverts() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        vm.deal(bidder1, 1 ether);
        vm.prank(bidder1);
        vm.expectRevert();
        auction.bidWithEth{value: 0.1 ether}(1); // $200 < $1000
    }

    function test_BidWithEthZeroValueReverts() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        vm.prank(bidder1);
        vm.expectRevert(NFTAuction.ZeroAmount.selector);
        auction.bidWithEth{value: 0}(1);
    }

    function test_SellerCannotBid() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        vm.deal(seller, 1 ether);
        vm.prank(seller);
        vm.expectRevert(NFTAuction.SellerCannotBid.selector);
        auction.bidWithEth{value: 0.5 ether}(1);
    }

    function test_CannotBidOnEndedAuction() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        vm.deal(bidder1, 1 ether);
        vm.prank(bidder1);
        vm.expectRevert(NFTAuction.AuctionAlreadyClosed.selector);
        auction.bidWithEth{value: 0.5 ether}(1);
    }

    // ============ 5. ERC20出价测试 ============

    function test_BidWithERC20() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        uint256 bidAmount = 1000 * 1e18;

        uint256 balanceBefore = usdc.balanceOf(bidder1);
        vm.prank(bidder1);
        auction.bidWithERC20(1, address(usdc), bidAmount);

        assertEq(usdc.balanceOf(bidder1), balanceBefore - bidAmount);
        assertEq(usdc.balanceOf(address(auction)), bidAmount);

        (,,,,, address highestBidder, address highestBidToken, uint256 highestBidAmount,,,) = auction.auctions(1);

        assertEq(highestBidder, bidder1);
        assertEq(highestBidToken, address(usdc));
        assertEq(highestBidAmount, bidAmount);
    }

    function test_BidWithERC20UnapprovedReverts() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        MockERC20 newToken = new MockERC20("New", "NEW", 18);
        newToken.mint(bidder1, 1_000_000 * 1e18);

        vm.prank(bidder1);
        vm.expectRevert();
        auction.bidWithERC20(1, address(newToken), 1000 * 1e18);
    }

    function test_BidWithERC20ZeroAmountReverts() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        vm.prank(bidder1);
        vm.expectRevert(NFTAuction.ZeroAmount.selector);
        auction.bidWithERC20(1, address(usdc), 0);
    }

    // ============ 6. 跨币种比较测试 ============

    function test_CrossCurrencyBidding_EthThenERC20() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        // bidder1: 0.5 ETH = $1000
        vm.deal(bidder1, 1 ether);
        vm.prank(bidder1);
        auction.bidWithEth{value: 0.5 ether}(1);

        // bidder2: 1200 USDC = $1200 (> $1050 minBid)
        vm.prank(bidder2);
        auction.bidWithERC20(1, address(usdc), 1200 * 1e18);

        (,,,,, address highestBidder,,,,,) = auction.auctions(1);
        assertEq(highestBidder, bidder2);

        // bidder1的ETH在pendingReturns中
        assertEq(auction.pendingReturns(1, bidder1, address(0)), 0.5 ether);
    }

    function test_CrossCurrencyBidding_ERC20ThenEth() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        // bidder1: 1000 USDC = $1000
        vm.prank(bidder1);
        auction.bidWithERC20(1, address(usdc), 1000 * 1e18);

        // bidder2: 0.6 ETH = $1200 (> $1050 minBid)
        vm.deal(bidder2, 1 ether);
        vm.prank(bidder2);
        auction.bidWithEth{value: 0.6 ether}(1);

        (,,,,, address highestBidder, address highestBidToken, uint256 highestBidAmount,,,) = auction.auctions(1);
        assertEq(highestBidder, bidder2);
        assertEq(highestBidToken, address(0));
        assertEq(highestBidAmount, 0.6 ether);

        // bidder1的USDC在pendingReturns中
        assertEq(auction.pendingReturns(1, bidder1, address(usdc)), 1000 * 1e18);
    }

    // ============ 7. 结束拍卖测试 ============

    function test_EndAuction_WithBids() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        vm.deal(bidder1, 1 ether);
        vm.prank(bidder1);
        auction.bidWithEth{value: 0.5 ether}(1);

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        uint256 sellerBalanceBefore = seller.balance;
        uint256 feeRecipientBalanceBefore = feeRecipient.balance;

        auction.endAuction(1);

        assertEq(nft.ownerOf(1), bidder1);

        uint256 fee = (0.5 ether * 250) / 10000;
        uint256 sellerAmount = 0.5 ether - fee;
        assertEq(seller.balance, sellerBalanceBefore + sellerAmount);
        assertEq(feeRecipient.balance, feeRecipientBalanceBefore + fee);

        (,,,,,,,, uint256 _endTime, bool active, bool ended) = auction.auctions(1);
        assertFalse(active);
        assertTrue(ended);
    }

    function test_EndAuction_NoBids() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        auction.endAuction(1);

        assertEq(nft.ownerOf(1), seller);
    }

    function test_EndAuction_WithERC20Bid() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        vm.prank(bidder1);
        auction.bidWithERC20(1, address(usdc), 1000 * 1e18);

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        uint256 sellerBalBefore = usdc.balanceOf(seller);
        uint256 feeRecipientBalBefore = usdc.balanceOf(feeRecipient);

        auction.endAuction(1);

        assertEq(nft.ownerOf(1), bidder1);

        uint256 fee = (1000 * 1e18 * 250) / 10000;
        uint256 sellerAmount = 1000 * 1e18 - fee;
        assertEq(usdc.balanceOf(seller), sellerBalBefore + sellerAmount);
        assertEq(usdc.balanceOf(feeRecipient), feeRecipientBalBefore + fee);
    }

    function test_EndAuctionNotEndedReverts() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        vm.expectRevert(NFTAuction.AuctionNotEnded.selector);
        auction.endAuction(1);
    }

    function test_EndAuctionAlreadyEndedReverts() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        auction.endAuction(1);

        // After ending, active=false and ended=true, so AuctionNotActive is checked first
        vm.expectRevert(NFTAuction.AuctionNotActive.selector);
        auction.endAuction(1);
    }

    function test_EndAuctionEmitsEvent() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        vm.deal(bidder1, 1 ether);
        vm.prank(bidder1);
        auction.bidWithEth{value: 0.5 ether}(1);

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        vm.expectEmit(true, true, true, false);
        emit AuctionEnded(1, bidder1, address(0), 0.5 ether, 1000e8);
        auction.endAuction(1);
    }

    // ============ 8. 提取退款测试 ============

    function test_WithdrawPendingReturn_Eth() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        vm.deal(bidder1, 1 ether);
        vm.prank(bidder1);
        auction.bidWithEth{value: 0.5 ether}(1);

        vm.deal(bidder2, 1 ether);
        vm.prank(bidder2);
        auction.bidWithEth{value: 0.6 ether}(1);

        assertEq(auction.pendingReturns(1, bidder1, address(0)), 0.5 ether);

        uint256 bidder1BalanceBefore = bidder1.balance;
        vm.prank(bidder1);
        auction.withdrawPendingReturn(1, address(0));

        assertEq(bidder1.balance, bidder1BalanceBefore + 0.5 ether);
        assertEq(auction.pendingReturns(1, bidder1, address(0)), 0);
    }

    function test_WithdrawPendingReturn_ERC20() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        vm.prank(bidder1);
        auction.bidWithERC20(1, address(usdc), 1000 * 1e18);

        vm.deal(bidder2, 1 ether);
        vm.prank(bidder2);
        auction.bidWithEth{value: 0.6 ether}(1);

        assertEq(auction.pendingReturns(1, bidder1, address(usdc)), 1000 * 1e18);

        uint256 bidder1BalBefore = usdc.balanceOf(bidder1);
        vm.prank(bidder1);
        auction.withdrawPendingReturn(1, address(usdc));

        assertEq(usdc.balanceOf(bidder1), bidder1BalBefore + 1000 * 1e18);
        assertEq(auction.pendingReturns(1, bidder1, address(usdc)), 0);
    }

    function test_WithdrawNoPendingReturnReverts() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        vm.prank(bidder1);
        vm.expectRevert(NFTAuction.NoPendingReturn.selector);
        auction.withdrawPendingReturn(1, address(0));
    }

    function test_DoubleWithdrawReverts() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        vm.deal(bidder1, 1 ether);
        vm.prank(bidder1);
        auction.bidWithEth{value: 0.5 ether}(1);

        vm.deal(bidder2, 1 ether);
        vm.prank(bidder2);
        auction.bidWithEth{value: 0.6 ether}(1);

        vm.prank(bidder1);
        auction.withdrawPendingReturn(1, address(0));

        vm.prank(bidder1);
        vm.expectRevert(NFTAuction.NoPendingReturn.selector);
        auction.withdrawPendingReturn(1, address(0));
    }

    // ============ 9. 取消拍卖测试 ============

    function test_CancelAuction() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        vm.prank(seller);
        auction.cancelAuction(1);

        (,,,,,,,, uint256 _endTime, bool active, bool ended) = auction.auctions(1);
        assertFalse(active);
        assertTrue(ended);
    }

    function test_CancelAuctionNotSellerReverts() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        vm.prank(bidder1);
        vm.expectRevert(NFTAuction.NotSeller.selector);
        auction.cancelAuction(1);
    }

    function test_CancelAuctionWithBidsReverts() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        vm.deal(bidder1, 1 ether);
        vm.prank(bidder1);
        auction.bidWithEth{value: 0.5 ether}(1);

        vm.prank(seller);
        vm.expectRevert(NFTAuction.HasBids.selector);
        auction.cancelAuction(1);
    }

    // ============ 10. 价格转换测试 ============

    function test_GetUsdValueEth() public view {
        uint256 usdValue = auction.getUsdValueEth(1 ether);
        assertEq(usdValue, 2000e8);

        usdValue = auction.getUsdValueEth(0.5 ether);
        assertEq(usdValue, 1000e8);
    }

    function test_GetUsdValueToken() public view {
        uint256 usdValue = auction.getUsdValueToken(address(usdc), 1000 * 1e18);
        assertEq(usdValue, 1000e8);
    }

    function test_GetMinBidUsd() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        uint256 minBid = auction.getMinBidUsd(1);
        assertEq(minBid, START_PRICE_USD);

        vm.deal(bidder1, 1 ether);
        vm.prank(bidder1);
        auction.bidWithEth{value: 0.5 ether}(1);

        minBid = auction.getMinBidUsd(1);
        assertEq(minBid, 1050e8);
    }

    // ============ 11. 管理函数测试 ============

    function test_SetPlatformFee() public {
        auction.setPlatformFee(500);
        assertEq(auction.platformFeeBps(), 500);
    }

    function test_SetPlatformFeeTooHighReverts() public {
        vm.expectRevert("Fee too high");
        auction.setPlatformFee(1001);
    }

    function test_SetFeeRecipient() public {
        address newRecipient = makeAddr("newFeeRecipient");
        auction.setFeeRecipient(newRecipient);
        assertEq(auction.feeRecipient(), newRecipient);
    }

    function test_SetFeeRecipientZeroAddressReverts() public {
        vm.expectRevert(NFTAuction.ZeroAddress.selector);
        auction.setFeeRecipient(address(0));
    }

    function test_SetFeeRecipientNotOwnerReverts() public {
        vm.prank(bidder1);
        vm.expectRevert();
        auction.setFeeRecipient(makeAddr("newFeeRecipient"));
    }

    function test_SetEthUsdPriceFeed() public {
        MockAggregator newFeed = new MockAggregator(8, 3000e8);
        auction.setEthUsdPriceFeed(address(newFeed));
        assertEq(address(auction.ethUsdPriceFeed()), address(newFeed));
    }

    // ============ 12. 价格预言机异常测试 ============

    function test_StalePriceFeedReverts() public {
        // 先推进时间到一个较大的值
        vm.warp(1700000000); // 2023-11-14

        vm.prank(seller);
        uint256 auctionId = auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        // 设置预言机updatedAt为2小时前，使其过期
        ethUsdFeed.setUpdatedAt(block.timestamp - 2 hours);

        vm.deal(bidder1, 1 ether);
        vm.prank(bidder1);
        vm.expectRevert(NFTAuction.StalePrice.selector);
        auction.bidWithEth{value: 0.5 ether}(auctionId);
    }

    function test_NegativePriceReverts() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        ethUsdFeed.setAnswer(-1);

        vm.deal(bidder1, 1 ether);
        vm.prank(bidder1);
        vm.expectRevert(NFTAuction.InvalidPriceFeed.selector);
        auction.bidWithEth{value: 0.5 ether}(1);
    }

    // ============ 13. 完整拍卖流程测试 ============

    function test_FullAuctionFlow_Eth() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        vm.deal(bidder1, 2 ether);
        vm.prank(bidder1);
        auction.bidWithEth{value: 0.5 ether}(1);

        vm.deal(bidder2, 2 ether);
        vm.prank(bidder2);
        auction.bidWithEth{value: 0.6 ether}(1);

        vm.prank(bidder1);
        auction.withdrawPendingReturn(1, address(0));

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        uint256 sellerBalanceBefore = seller.balance;
        auction.endAuction(1);

        assertEq(nft.ownerOf(1), bidder2);
        assertGt(seller.balance, sellerBalanceBefore);
    }

    function test_FullAuctionFlow_ERC20() public {
        vm.prank(seller);
        auction.createAuction(address(nft), 1, START_PRICE_USD, AUCTION_DURATION);

        vm.prank(bidder1);
        auction.bidWithERC20(1, address(usdc), 1000 * 1e18);

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        uint256 sellerBalBefore = usdc.balanceOf(seller);
        auction.endAuction(1);

        assertEq(nft.ownerOf(1), bidder1);
        assertGt(usdc.balanceOf(seller), sellerBalBefore);
    }
}

// ============ UUPS升级测试 ============

contract NFTAuctionUpgradeTest is Test {
    NFTAuction public auction;
    NFTAuctionV2 public auctionV2;
    MyNFT public nft;
    MockERC20 public usdc;
    MockAggregator public ethUsdFeed;
    MockAggregator public usdcUsdFeed;

    address public owner;
    address public seller;
    address public bidder;
    address public feeRecipient;

    function setUp() public {
        owner = address(this);
        seller = makeAddr("seller");
        bidder = makeAddr("bidder");
        feeRecipient = makeAddr("feeRecipient");

        ethUsdFeed = new MockAggregator(8, 2000e8);
        usdcUsdFeed = new MockAggregator(8, 1e8);

        nft = new MyNFT();
        usdc = new MockERC20("USD Coin", "USDC", 18);

        NFTAuction impl = new NFTAuction();
        bytes memory initData = abi.encodeCall(
            NFTAuction.initialize,
            (address(ethUsdFeed), feeRecipient)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        auction = NFTAuction(address(proxy));

        auction.addSupportedToken(address(usdc), address(usdcUsdFeed));

        nft.mint(seller, "uri1");
        vm.prank(seller);
        nft.setApprovalForAll(address(auction), true);

        usdc.mint(bidder, 1_000_000 * 1e18);
        vm.prank(bidder);
        usdc.approve(address(auction), type(uint256).max);
    }

    function test_UpgradeToV2() public {
        vm.prank(seller);
        uint256 auctionId = auction.createAuction(address(nft), 1, 1000e8, 1 days);

        vm.deal(bidder, 2 ether);
        vm.prank(bidder);
        auction.bidWithEth{value: 0.5 ether}(auctionId);

        NFTAuctionV2 implV2 = new NFTAuctionV2();

        vm.prank(owner);
        auction.upgradeToAndCall(
            address(implV2),
            abi.encodeCall(
                NFTAuctionV2.initializeV2,
                ([uint256(250), uint256(200), uint256(150)], [uint256(1000e8), uint256(10000e8)])
            )
        );

        auctionV2 = NFTAuctionV2(address(auction));

        assertEq(auctionV2.version(), "2.0.0");
        assertTrue(auctionV2.dynamicFeeEnabled());

        // 验证V1数据保留
        (address _seller,,,,,,,,,,) = auctionV2.auctions(auctionId);
        assertEq(_seller, seller);

        // 测试动态手续费
        uint256 feeBps = auctionV2.getDynamicFeeBps(500e8); // $500
        assertEq(feeBps, 250); // 低档

        feeBps = auctionV2.getDynamicFeeBps(5000e8); // $5000
        assertEq(feeBps, 200); // 中档

        feeBps = auctionV2.getDynamicFeeBps(50000e8); // $50000
        assertEq(feeBps, 150); // 高档
    }

    function test_UpgradeNotOwnerReverts() public {
        NFTAuctionV2 implV2 = new NFTAuctionV2();

        vm.prank(bidder);
        vm.expectRevert();
        auction.upgradeToAndCall(
            address(implV2),
            abi.encodeCall(
                NFTAuctionV2.initializeV2,
                ([uint256(250), uint256(200), uint256(150)], [uint256(1000e8), uint256(10000e8)])
            )
        );
    }

    function test_V2DisableDynamicFee() public {
        auctionV2 = NFTAuctionV2(address(auction));

        NFTAuctionV2 implV2 = new NFTAuctionV2();
        vm.prank(owner);
        auction.upgradeToAndCall(
            address(implV2),
            abi.encodeCall(
                NFTAuctionV2.initializeV2,
                ([uint256(250), uint256(200), uint256(150)], [uint256(1000e8), uint256(10000e8)])
            )
        );

        auctionV2 = NFTAuctionV2(address(auction));

        auctionV2.disableDynamicFee();
        assertFalse(auctionV2.dynamicFeeEnabled());

        // 回退到固定手续费
        uint256 feeBps = auctionV2.getDynamicFeeBps(50000e8);
        assertEq(feeBps, 250); // 使用固定的platformFeeBps
    }
}

// ============ ERC1967Proxy 简化实现（用于测试） ============

contract ERC1967Proxy {
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

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
