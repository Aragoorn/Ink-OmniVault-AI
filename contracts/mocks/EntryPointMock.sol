// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title EntryPointMock
 * @notice Minimal mock of ERC-4337 EntryPoint for unit testing
 */
contract EntryPointMock {
    mapping(address => uint256) public balances;

    event Deposited(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, address indexed dest, uint256 amount);

    function depositTo(address account) external payable {
        balances[account] += msg.value;
        emit Deposited(account, msg.value);
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function withdrawTo(address payable dest, uint256 amount) external {
        require(balances[msg.sender] >= amount, "EntryPointMock: insufficient balance");
        balances[msg.sender] -= amount;
        (bool success, ) = dest.call{value: amount}("");
        require(success, "EntryPointMock: withdraw failed");
        emit Withdrawn(msg.sender, dest, amount);
    }

    // Simple mock for getUserOpHash (enough for our tests)
    function getUserOpHash(bytes calldata) external pure returns (bytes32) {
        return keccak256(abi.encodePacked("EntryPointMock"));
    }

    receive() external payable {
        balances[msg.sender] += msg.value;
    }
}
