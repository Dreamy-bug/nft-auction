// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./NFTAuction.sol";

/**
 * @title NFTAuctionV2
 * @dev NFT拍卖合约的升级版本，增加动态手续费功能
 * @notice 额外挑战：根据拍卖金额动态调整手续费
 *
 * 手续费规则：
 * - 低于 $1,000: 2.5% (250 bps)
 * - $1,000 ~ $10,000: 2.0% (200 bps)
 * - 高于 $10,000: 1.5% (150 bps)
 */
contract NFTAuctionV2 is NFTAuction {
    // ============ 新状态变量 ============

    /// @dev 手续费等级（基点）：[低档, 中档, 高档]
    uint256[3] public feeTiers;

    /// @dev 手续费阈值（USD，8位小数）：[阈值1, 阈值2]
    /// 金额 < 阈值1 → 使用feeTiers[0]
    /// 阈值1 <= 金额 < 阈值2 → 使用feeTiers[1]
    /// 金额 >= 阈值2 → 使用feeTiers[2]
    uint256[2] public feeThresholds;

    /// @dev 是否启用动态手续费
    bool public dynamicFeeEnabled;

    // ============ 新事件 ============

    event DynamicFeeEnabled(uint256[3] tiers, uint256[2] thresholds);
    event DynamicFeeDisabled();
    event FeeTiersUpdated(uint256[3] oldTiers, uint256[3] newTiers);
    event FeeThresholdsUpdated(uint256[2] oldThresholds, uint256[2] newThresholds);

    // ============ V2初始化 ============

    /**
     * @dev V2版本的初始化函数
     * @notice 使用reinitializer(2)确保只调用一次
     * @param _feeTiers 三个手续费等级的基点
     * @param _feeThresholds 两个手续费阈值（USD，8位小数）
     */
    function initializeV2(
        uint256[3] memory _feeTiers,
        uint256[2] memory _feeThresholds
    ) public reinitializer(2) {
        // 验证手续费等级
        require(_feeTiers[0] <= 1000, "Tier 0 fee too high");
        require(_feeTiers[1] <= 1000, "Tier 1 fee too high");
        require(_feeTiers[2] <= 1000, "Tier 2 fee too high");
        require(_feeTiers[0] >= _feeTiers[1], "Tiers must be descending");
        require(_feeTiers[1] >= _feeTiers[2], "Tiers must be descending");

        // 验证阈值
        require(_feeThresholds[0] < _feeThresholds[1], "Thresholds must be ascending");

        feeTiers = _feeTiers;
        feeThresholds = _feeThresholds;
        dynamicFeeEnabled = true;

        emit DynamicFeeEnabled(_feeTiers, _feeThresholds);
    }

    // ============ 动态手续费逻辑 ============

    /**
     * @dev 根据USD金额计算动态手续费
     * @param amountUsd 金额（USD，8位小数）
     * @return feeBps 对应的费率（基点）
     */
    function getDynamicFeeBps(
        uint256 amountUsd
    ) public view returns (uint256 feeBps) {
        if (!dynamicFeeEnabled) {
            return platformFeeBps;
        }

        if (amountUsd < feeThresholds[0]) {
            return feeTiers[0]; // 低档费率
        } else if (amountUsd < feeThresholds[1]) {
            return feeTiers[1]; // 中档费率
        } else {
            return feeTiers[2]; // 高档费率
        }
    }

    /**
     * @dev 计算手续费金额（覆盖内部计算逻辑）
     * @param amountUsd USD金额
     * @param rawAmount 原始代币金额
     * @return feeAmount 手续费原始代币金额
     */
    function calculateFee(
        uint256 amountUsd,
        uint256 rawAmount
    ) public pure returns (uint256 feeAmount) {
        // V2使用动态费率，这个函数提供给外部查询
        // 实际手续费计算在endAuction中完成
        feeAmount = 0; // placeholder - actual calculation happens in endAuction
    }

    /**
     * @dev 结束拍卖（重写以支持动态手续费）
     * @param auctionId 拍卖ID
     */
    function endAuction(uint256 auctionId) external override nonReentrant {
        Auction storage auction = auctions[auctionId];

        if (!auction.active) revert AuctionNotActive();
        if (auction.ended) revert AuctionAlreadyEnded();
        if (block.timestamp < auction.endTime) revert AuctionNotEnded();

        auction.active = false;
        auction.ended = true;

        if (auction.highestBidder != address(0)) {
            // 使用动态手续费
            uint256 feeBps = getDynamicFeeBps(auction.highestBidUsd);
            uint256 feeAmount = (auction.highestBidAmount * feeBps) / 10000;
            uint256 sellerAmount = auction.highestBidAmount - feeAmount;

            // 转移NFT给出价最高者
            IERC721(auction.nftContract).safeTransferFrom(
                auction.seller,
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
            // 没有人出价，拍卖流拍
            emit AuctionEnded(auctionId, address(0), address(0), 0, 0);
        }
    }

    // ============ 动态手续费管理 ============

    /**
     * @dev 启用动态手续费
     * @param _feeTiers 三个手续费等级的基点
     * @param _feeThresholds 两个手续费阈值
     */
    function enableDynamicFee(
        uint256[3] memory _feeTiers,
        uint256[2] memory _feeThresholds
    ) external onlyOwner {
        require(_feeTiers[0] <= 1000, "Tier 0 fee too high");
        require(_feeTiers[1] <= 1000, "Tier 1 fee too high");
        require(_feeTiers[2] <= 1000, "Tier 2 fee too high");
        require(_feeTiers[0] >= _feeTiers[1], "Tiers must be descending");
        require(_feeTiers[1] >= _feeTiers[2], "Tiers must be descending");
        require(_feeThresholds[0] < _feeThresholds[1], "Thresholds must be ascending");

        feeTiers = _feeTiers;
        feeThresholds = _feeThresholds;
        dynamicFeeEnabled = true;

        emit DynamicFeeEnabled(_feeTiers, _feeThresholds);
    }

    /**
     * @dev 禁用动态手续费，回退到固定手续费
     */
    function disableDynamicFee() external onlyOwner {
        dynamicFeeEnabled = false;

        emit DynamicFeeDisabled();
    }

    /**
     * @dev 更新手续费等级
     * @param newTiers 新的三个手续费等级
     */
    function updateFeeTiers(
        uint256[3] memory newTiers
    ) external onlyOwner {
        require(newTiers[0] <= 1000, "Tier 0 fee too high");
        require(newTiers[1] <= 1000, "Tier 1 fee too high");
        require(newTiers[2] <= 1000, "Tier 2 fee too high");
        require(newTiers[0] >= newTiers[1], "Tiers must be descending");
        require(newTiers[1] >= newTiers[2], "Tiers must be descending");

        uint256[3] memory oldTiers = feeTiers;
        feeTiers = newTiers;

        emit FeeTiersUpdated(oldTiers, newTiers);
    }

    /**
     * @dev 更新手续费阈值
     * @param newThresholds 新的两个手续费阈值
     */
    function updateFeeThresholds(
        uint256[2] memory newThresholds
    ) external onlyOwner {
        require(
            newThresholds[0] < newThresholds[1],
            "Thresholds must be ascending"
        );

        uint256[2] memory oldThresholds = feeThresholds;
        feeThresholds = newThresholds;

        emit FeeThresholdsUpdated(oldThresholds, newThresholds);
    }

    // ============ 版本信息 ============

    /**
     * @dev 获取合约版本
     * @return 版本号
     */
    function version() external pure returns (string memory) {
        return "2.0.0";
    }

    // ============ 存储间隙 ============

    /**
     * @dev 为未来升级预留存储空间（减少5个槽位用于V2新增变量）
     */
    uint256[35] private __gap;
}
