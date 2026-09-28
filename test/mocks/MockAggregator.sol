// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title MockAggregator
 * @dev 用于测试的Chainlink价格预言机Mock合约
 * @notice 实现 AggregatorV3Interface 接口，支持动态设置价格
 */
contract MockAggregator is AggregatorV3Interface {
    uint8 public override decimals;
    string public override description;
    uint256 public override version;

    int256 private _answer;
    uint256 private _updatedAt;
    uint80 private _roundId;
    uint80 private _answeredInRound;

    /**
     * @dev 构造函数
     * @param _decimals 价格小数位数（Chainlink USD价格通常为8）
     * @param _initialAnswer 初始价格
     */
    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        description = "Mock Price Feed";
        version = 1;

        _answer = _initialAnswer;
        _updatedAt = block.timestamp;
        _roundId = 1;
        _answeredInRound = 1;
    }

    /**
     * @dev 获取最新轮次数据
     * @return roundId 轮次ID
     * @return answer 价格
     * @return startedAt 开始时间
     * @return updatedAt 更新时间
     * @return answeredInRound 回答所在轮次
     */
    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _answer, _updatedAt, _updatedAt, _answeredInRound);
    }

    /**
     * @dev 设置价格（测试用）
     * @param _newAnswer 新价格
     */
    function setAnswer(int256 _newAnswer) external {
        _answer = _newAnswer;
        _roundId++;
        _answeredInRound = _roundId;
        _updatedAt = block.timestamp;
    }

    /**
     * @dev 设置更新时间（模拟过期数据）
     * @param _newUpdatedAt 新的更新时间
     */
    function setUpdatedAt(uint256 _newUpdatedAt) external {
        _updatedAt = _newUpdatedAt;
    }

    /**
     * @dev 获取指定轮次数据
     * @param _roundId 轮次ID
     */
    function getRoundData(
        uint80 _roundId
    )
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        require(_roundId <= _roundId && _roundId == _roundId, "Invalid round");
        return (_roundId, _answer, _updatedAt, _updatedAt, _answeredInRound);
    }
}
