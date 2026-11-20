# SharedStake Sett Vault and Auto-Compounding Strategy (SGT/ETH LP)

## Overview
This implementation provides a Yearn and Sett style auto-compounding vault (`SettVaultSgtEth.sol`) and Uniswap V2 LP strategy (`StrategySgtEthLp.sol`) for the SharedStake protocol, resolving Issue #7.

## Architecture

### 1. SettVaultSgtEth
- **Underlying Asset (`want`)**: Uniswap V2 SGT/ETH LP token (`UNI-V2`).
- **Share Token**: `bSgtEthLP` (18 decimals).
- **Core Operations**:
  - `deposit(uint256 amount)`: Accepts LP tokens and mints proportional vault shares.
  - `withdraw(uint256 shares)`: Burns shares and returns underlying LP tokens including compounded yield.
  - `earn()`: Deploys idle vault assets into the active strategy.
  - `getPricePerFullShare()`: Computes current valuation of a single share relative to total underlying pool balance.

### 2. Time-Lock Boost and Governance Voting
- **Time-Lock Principal**: Depositors can lock principal shares for periods between 7 days and 365 days.
  - Boost Formula: $\text{Boost Multiplier} = 10000 + \left(\frac{15000 \times \text{duration}}{365\text{ days}}\right)$, scaling from 1.0x to 2.5x.
- **Vote Checkpoints**: `getVotes(address account)` and `getPriorVotes(address account, uint256 blockNumber)` provide historical checkpointed voting power for governance proposals.

### 3. StrategySgtEthLp
- **Auto-Compounding Loop (`harvest`)**:
  1. Deducts performance (4.5%) and strategist (0.5%) fees.
  2. Swaps 50% of harvestable SGT into WETH via Uniswap V2 router.
  3. Provides SGT and WETH as liquidity to Uniswap V2 pool.
  4. Retains minted LP tokens inside strategy to compound vault `getPricePerFullShare`.
- **Emergency Protection**: `inCaseTokensGetStuck(address token)` recovers non-core assets to governance.

## Deployment Steps

1. **Deploy Sett Vault**:
   ```solidity
   SettVaultSgtEth vault = new SettVaultSgtEth(
       SGT_ETH_LP_ADDRESS,
       GOVERNANCE_ADDRESS,
       CONTROLLER_ADDRESS
   );
   ```

2. **Deploy Strategy**:
   ```solidity
   StrategySgtEthLp strategy = new StrategySgtEthLp(
       SGT_ETH_LP_ADDRESS,
       SGT_TOKEN_ADDRESS,
       WETH_ADDRESS,
       UNISWAP_V2_ROUTER_ADDRESS,
       address(vault),
       GOVERNANCE_ADDRESS,
       STRATEGIST_ADDRESS,
       TREASURY_ADDRESS
   );
   ```

3. **Link Strategy**:
   ```solidity
   vault.setStrategy(address(strategy));
   ```

## Testnet Verification

Run the test suite using Foundry:
```bash
forge test -vvv
```

## Payout Routing
- **EVM (Base/Arbitrum/Polygon/ETH):** `0xF46C9F6d70C50BF81ef3588AB523a90a594a2F89`
- **Stellar:** `GCL6OXAMLD75BMTINA6EMRUDWK5THQUSHMYNLSNBCJAPZJHNYJTUNIBC`
