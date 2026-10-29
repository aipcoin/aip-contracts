# AIP Contracts — Public Verification Copy

This repository contains the source code of the smart contracts deployed on
**BNB Smart Chain (mainnet, chainId 56)**. It is published **for verification
purposes only**, so that anyone can independently confirm that the deployed
bytecode matches the published source.

## Deployed contracts (BNB Smart Chain mainnet)

| Contract | Address |
|---|---|
| AIP Token (`AIPToken`) | [`0xC0AfFf091ae11A1e8D24BDa63Cc72C84801C988b`](https://bscscan.com/address/0xC0AfFf091ae11A1e8D24BDa63Cc72C84801C988b#code) |
| Bonding curve / main (`BondingCurve`) | [`0x3F696DCA7849C0B78EC1f22e88798Cc3D7954ab0`](https://bscscan.com/address/0x3F696DCA7849C0B78EC1f22e88798Cc3D7954ab0#code) |
| Floor plan sub (`FloorPlanSub`) | [`0x5d290D8eAcE637499Dbcd0C5EC2CA588cC3371b6`](https://bscscan.com/address/0x5d290D8eAcE637499Dbcd0C5EC2CA588cC3371b6#code) |
| Weekly ranking sub (`WeeklyRankingSub`) | [`0xAC7C560c9bA83909E4EFeB1060431c29b902DC1d`](https://bscscan.com/address/0xAC7C560c9bA83909E4EFeB1060431c29b902DC1d#code) |
| Finale pool sub (`FinalePoolSub`) | [`0xb49C7E06aD4000F063f71c3696247621C6A41b63`](https://bscscan.com/address/0xb49C7E06aD4000F063f71c3696247621C6A41b63#code) |

The bonding-curve main contract references the canonical
[BSC-USD (USDT) token](https://bscscan.com/address/0x55d398326f99059fF775485246999027B3197955)
(`0x55d398326f99059fF775485246999027B3197955`).

### Constructor arguments

| Contract | Constructor arguments (in order) |
|---|---|
| `AIPToken` | `bondingCurve = 0x3F69…4ab0` |
| `BondingCurve` | `usdt = 0x55d3…7955` |
| `FloorPlanSub` | `aipToken = 0xC0Af…988b`, `usdt = 0x55d3…7955`, `bondingCurve = 0x3F69…4ab0` |
| `WeeklyRankingSub` | `aipToken = 0xC0Af…988b`, `bondingCurve = 0x3F69…4ab0` |
| `FinalePoolSub` | `aipToken = 0xC0Af…988b`, `bondingCurve = 0x3F69…4ab0` |

## How to reproduce the deployed bytecode

```bash
npm install
npx hardhat compile
```

The runtime bytecode of each compiled contract is written to
`artifacts/contracts/<File>.sol/<Contract>.json` under
`evm.deployedBytecode.object`.

Note: constructor arguments are stored as *immutables*. In the compiled
artifact they appear as zero placeholders; the actual values are patched in by
the deployment transaction. A raw artifact-vs-`eth_getCode` comparison
therefore differs only at those immutable positions. The exact end-to-end
check is to deploy the compiled contracts with the constructor arguments
listed above (e.g. on a local Hardhat node): the resulting runtime bytecode is
byte-for-byte identical to the on-chain code at the mainnet addresses listed
in this README.

Compiler settings (also in `hardhat.config.js`):

- solc `0.8.24`
- `viaIR: true`
- optimizer: enabled, `runs: 1`
- metadata: `bytecodeHash: "none"` (no CBOR metadata appended to the bytecode)

Dependencies are pinned to exact versions (`hardhat 2.28.6`,
`@openzeppelin/contracts 5.6.1`) to make the build reproducible.

## Repository layout

```
contracts/
  AIPToken.sol          ERC20 token (fixed supply, minted once to the main contract)
  BondingCurve.sol      Main contract: bonding-curve sale, referrals, staking, app access
  ExponentialMath.sol   Fixed-point math library used by the bonding curve
  FloorPlanSub.sol      Floor-plan (consensus seat) escrow sub-contract
  WeeklyRankingSub.sol  Weekly top-3 ranking prize pool sub-contract
  FinalePoolSub.sol     Final-purchase prize pool sub-contract
```

## Notice

- These sources are provided **for verification and review only**.
- **No license is granted.** All rights are reserved. You may read, compile
  and verify the code against the blockchain, but you may **not** copy,
  redistribute, or deploy derivative works from it.
- The `SPDX-License-Identifier: MIT` headers are kept byte-for-byte solely to
  preserve bit-exact source compatibility with the deployed bytecode; they do
  not grant any rights under this repository.
- The code is provided "as is", without warranty of any kind. Interacting with
  smart contracts involves risk; always do your own research.
