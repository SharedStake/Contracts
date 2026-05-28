# MultiSendERC20

Send ERC20 tokens to multiple recipients in a single transaction. Saves gas by batching transfers.

## Functions

### `multiSend(token, recipients, amounts)`
Standard send - transfers tokens from sender to all recipients via `transferFrom`.
- Requires prior `approve()` of total amount
- Reverts if ANY transfer fails
- Emits `MultiTransfer` event

### `multiSendSafe(token, recipients, amounts)`
Safe send - pulls all tokens at once, distributes individually.
- Continues if individual transfers fail (handles non-standard ERC20s)
- Returns remaining tokens to sender
- Emits `TransferFailed` for each failure

## Usage

```solidity
// 1. Deploy MultiSendERC20
MultiSendERC20 multisend = new MultiSendERC20();

// 2. Approve spending
token.approve(multisendAddress, totalAmount);

// 3. Send to multiple recipients
address[] memory recipients = new address[](2);
recipients[0] = 0x123...;
recipients[1] = 0x456...;
uint256[] memory amounts = new uint256[](2);
amounts[0] = 100 ether;
amounts[1] = 200 ether;
multisend.multiSend(address(token), recipients, amounts);
```

## Testing

Deploy on testnet (Goerli/Sepolia) and verify with:
- Small batch (2-5 recipients)
- Large batch (50+ recipients)
- Token with transfer fees
- Failed transfer handling
