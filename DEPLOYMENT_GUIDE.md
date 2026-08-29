# AAVE Long/Short ETH Leverage Strategy & SharedStake Integration

## Overview
`LeverageEthViaAAVE` provides an AAVE collateralized debt position (CDP) leverage proxy contract integrated with Uniswap V2, Chainlink Oracles, and the SharedStake protocol.

It enables two primary investment strategies:
1. **Long ETH (Leveraged Long + Staking)**:
   - User deposits ETH into the contract.
   - ETH is deposited as collateral into Aave (receiving aWETH).
   - Stablecoins (e.g. DAI) are borrowed from Aave against the ETH collateral.
   - Stablecoins are swapped to ETH via Uniswap V2 Router.
   - Optionally loops to compound leverage up to a configurable `minHealthFactor`.
   - Remaining borrowing power on debt tokens is credit-delegated back to the user.
   - Swapped/accumulated ETH is deposited into the SharedStake `SharedDeposit` contract, minting `vETH2` tokens which are forwarded directly to the user.
   - If `sharedDeposit` is unconfigured (`address(0)`, e.g., on testnets like Kovan), the contract gracefully returns the acquired ETH directly to the user.

2. **Short ETH (Leveraged Short + Staking Hedge)**:
   - User deposits stablecoins (e.g. DAI/USDC) into the contract as collateral.
   - Stablecoins are deposited into Aave.
   - Contract borrows ETH against the stable collateral.
   - Mode A (Short & Swap): Swaps borrowed ETH to stablecoins via Uniswap and returns to user.
   - Mode B (Short & Stake): Deposits borrowed ETH directly into SharedStake `SharedDeposit` to earn validator staking yields (`vETH2`) while holding a short position on ETH.
   - Remaining credit is delegated back to the user.

## Bidirectional Credit Delegation
The contract supports full bidirectional credit delegation on both Stable Debt Tokens and Variable Debt Tokens:
- **Contract to User**: Grants the user direct borrow allowance against the contract's collateral.
- **User to Contract**: Allows the contract to execute borrows on behalf of a user who deposited collateral in their personal account and delegated credit to the contract (`borrowOnBehalfOfUser`).

## Testing
Unit tests are implemented in Foundry covering all strategies, credit delegation flows, repayment, collateral withdrawals, and error conditions.

Run tests:
```bash
forge test -vvv
```
