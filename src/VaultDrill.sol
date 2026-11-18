// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
}

contract VaultDrill {
    mapping(address => uint256) public balances;
    address public owner;

    constructor() payable { owner = msg.sender; }

    function deposit() external payable { balances[msg.sender] += msg.value; }

    function withdraw() external {
        (bool ok, ) = msg.sender.call{value: balances[msg.sender]}("");
        require(ok, "transfer failed");
        balances[msg.sender] = 0;
    }

    function sweep(address token, uint256 amount) external {
        IERC20(token).transfer(msg.sender, amount);
    }
}
