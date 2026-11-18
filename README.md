# muse-drill-vault-poc

Executable Foundry PoC for the two Critical bugs in `VaultDrill` (Training
Session #1 audit, reproduced here as runnable tests — Training Session #4).

`src/VaultDrill.sol` is the **exact** contract from the drill (unmodified,
byte-identical — deliberately NOT run through `forge fmt`, which is why the
CI workflow skips the `forge fmt --check` step).
`src/VaultDrillFixed.sol` is the patched version (CEI + `nonReentrant` +
`onlyOwner` on `sweep`).

## Run

```bash
forge test -vvv
```

Requires [Foundry](https://getfoundry.sh/) (`forge` 1.9.0 used here).
No network, no deployment, no real funds — everything runs locally on
Foundry's in-memory EVM.

Clone with submodules (for `forge-std`), then test:

```bash
git clone --recursive https://github.com/zalana28/muse-drill-vault-poc.git
cd muse-drill-vault-poc
forge test -vvv
```

Clone fresh (tanpa `--recursive`): jalankan `forge install foundry-rs/forge-std` dulu sebelum `forge test`.

## Bug → test mapping

| # | Bug (severity) | Where | Test | What the test proves |
|---|---|---|---|---|
| 1 | Reentrancy in `withdraw()` — ETH is sent **before** `balances[msg.sender] = 0` (Critical) | `src/VaultDrill.sol` | `testReentrancyDrain` | An attacker contract reenters `withdraw()` from its `receive()` and drains the vault: vault balance `0`, attacker ends with `11 ether` (its own `1` + the victim's `10`), while the victim's recorded balance (`10 ether`) is left unbacked. |
| 2 | `sweep()` has no access control — anyone can call it (Critical) | `src/VaultDrill.sol` | `testSweepAnyone` | A random stranger (not the owner) calls `sweep()` and takes all `1,000` mock tokens held by the vault. |
| — | Patch check: CEI + `nonReentrant` (fix for bug #1) | `src/VaultDrillFixed.sol` | `testPatchWithdraw` | The same reentrancy attempt against the fixed vault reverts (`vm.expectRevert`); the vault keeps all `11 ether` and the attacker gets nothing. |

Bonus note from the original audit (Low, not covered by a test here):
`sweep()` also ignores the `bool` return value of `IERC20.transfer` — the
fixed version wraps it in `require(..., "sweep failed")`.
