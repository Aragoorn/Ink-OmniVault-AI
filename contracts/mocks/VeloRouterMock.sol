// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title VeloRouterMock
 * @notice Minimal mock of Velodrome/Uniswap-style router for testing on Ink
 */
contract VeloRouterMock {
    event SwapExactETHForTokens(
        address indexed to,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] path
    );

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "VeloRouterMock: expired");
        require(path.length >= 2, "VeloRouterMock: bad path");
        require(msg.value > 0, "VeloRouterMock: zero value");

        amounts = new uint256[](path.length);
        amounts[0] = msg.value;
        // Simplified: pretend we got amountOutMin of the output token
        amounts[path.length - 1] = amountOutMin;

        emit SwapExactETHForTokens(to, msg.value, amountOutMin, path);
    }

    receive() external payable {}
}