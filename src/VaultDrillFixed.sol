// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Patched version of VaultDrill (drill #1 remediation):
// - withdraw(): Checks-Effects-Interactions (balance zeroed BEFORE the call)
//   + nonReentrant guard, so a reentrant call reverts instead of draining.
// - sweep(): onlyOwner + checked ERC20 return value (reverts on failure).
// The import below only reuses the IERC20 interface; VaultDrill.sol itself
// is NOT modified.

import "./VaultDrill.sol";

contract VaultDrillFixed {
    mapping(address => uint256) public balances;
    address public owner;

    bool private _locked;

    modifier nonReentrant() {
        require(!_locked, "ReentrancyGuard: reentrant call");
        _locked = true;
        _;
        _locked = false;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor() payable {
        owner = msg.sender;
    }

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() external nonReentrant {
        uint256 amount = balances[msg.sender];
        balances[msg.sender] = 0;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");
    }

    function sweep(address token, uint256 amount) external onlyOwner {
        require(IERC20(token).transfer(owner, amount), "sweep failed");
    }
}
