// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title InkMockPriceFeed
 * @notice Chainlink / eOracle-compatible mock price feed for testing on Ink
 * @dev Used for volatility, slippage, oracle staleness and circuit breaker tests
 */
contract InkMockPriceFeed {
    int256 private s_price;
    uint80 private s_roundId;
    uint256 private s_updatedAt;
    address public owner;

    event PriceUpdated(int256 newPrice, uint256 updatedAt);

    constructor(int256 initialPrice) {
        require(initialPrice > 0, "Invalid initial price");
        owner = msg.sender;
        s_price = initialPrice;
        s_roundId = 1;
        s_updatedAt = block.timestamp;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    /**
     * @notice Updates mock price for testing volatility, slippage or circuit breaker scenarios
     */
    function setLatestPrice(int256 newPrice) external onlyOwner {
        require(newPrice > 0, "Invalid price");
        s_price = newPrice;
        s_roundId++;
        s_updatedAt = block.timestamp;
        emit PriceUpdated(newPrice, s_updatedAt);
    }

    /**
     * @notice Standard Chainlink / eOracle compatible interface
     *         Matches the oracle checks used in InkOmniVaultAI
     */
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (
            s_roundId,          // roundId
            s_price,            // answer (Price with 8 decimals)
            s_updatedAt,        // startedAt
            s_updatedAt,        // updatedAt
            s_roundId           // answeredInRound
        );
    }

    // Optional helpers for advanced tests
    function getPrice() external view returns (int256) {
        return s_price;
    }

    function getRoundId() external view returns (uint80) {
        return s_roundId;
    }
}