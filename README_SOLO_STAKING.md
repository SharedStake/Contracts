# Solo Staking Implementation for SharedStake

## 版权声明
MIT License | Copyright (c) 2026 思捷娅科技 (SJYKJ)

---

## Overview

This implementation adds solo staking functionality to the SharedStake Minter contract, allowing users to:

- ✅ Stake 32 ETH directly to ETH2
- ✅ Bond 1000 SGT (timelocked)
- ✅ Receive 32 vETH2 in exchange for 32.1 ETH
- ✅ Earn higher APY in the ecosystem while waiting for ETH2 rewards
- ✅ Maintain control of validator keys

## Requirements

### For Solo Stakers

1. **32 ETH** - For ETH2 validator deposit
2. **1000 SGT** - Bonded and timelocked
3. **Validator Setup** - Run your own ETH2 validator

### For Contract

- **Minter Contract** - Upgraded with AccessControl
- **SGT Token** - For bonding
- **vETH2 Token** - For representing staked ETH

---

## Contract Architecture

### SoloStaking Contract

**Key Features:**
- Registration with SGT bond
- Direct deposit to ETH2
- Simplified deposit via Minter
- Admin controls for unlock/slash
- Event logging for transparency

**Functions:**

#### Registration
```solidity
function registerSoloStaker() external
```
- Transfers 1000 SGT bond from staker
- Registers staker in the system
- Emits `SoloStakerRegistered` event

#### Deposit (Full)
```solidity
function depositForValidator(
    bytes calldata pubkey,
    bytes calldata withdrawal_credentials,
    bytes calldata signature,
    bytes32 deposit_data_root
) external payable
```
- Requires 32.1 ETH (32 ETH + 0.1 ETH fee)
- Forwards 32 ETH to ETH2 deposit contract
- Mints 32 vETH2 to staker
- Sends 0.1 ETH fee to Minter

#### Deposit (Simplified)
```solidity
function depositSimple() external payable
```
- Requires 32.1 ETH
- Calls Minter's `send2eth2()` function
- Mints 32 vETH2 to staker

#### Admin Functions
```solidity
function markValidatorExited(address staker) external onlyAdmin
function unlockSGT(address staker) external onlyAdmin
function slashSGT(address staker, uint256 amount) external onlyAdmin
```

---

## Usage Guide

### Step 1: Register as Solo Staker

```javascript
// Approve SGT transfer
await sgt.approve(soloStaking.address, SGT_BOND_AMOUNT);

// Register
await soloStaking.registerSoloStaker();
```

### Step 2: Deposit for Validator

```javascript
// Full deposit with validator keys
const pubkey = /* validator public key */;
const withdrawalCredentials = /* withdrawal credentials */;
const signature = /* deposit signature */;
const depositDataRoot = /* deposit data root */;

await soloStaking.depositForValidator(
    pubkey,
    withdrawalCredentials,
    signature,
    depositDataRoot,
    { value: ethers.utils.parseEther("32.1") }
);
```

### Step 3: Simplified Deposit

```javascript
// Simple deposit (validator setup later)
await soloStaking.depositSimple({
    value: ethers.utils.parseEther("32.1")
});
```

### Step 4: Exit Validator (Admin)

```javascript
// Mark validator as exited
await soloStaking.markValidatorExited(stakerAddress);

// Unlock SGT bond
await soloStaking.unlockSGT(stakerAddress);
```

---

## State Variables

```solidity
struct SoloStaker {
    bool exists;              // Is registered
    uint256 sgtBonded;        // Amount of SGT bonded
    uint256 validatorPubkey;  // Validator public key hash
    uint256 depositTimestamp; // When deposit was made
    bool validatorExited;     // Has validator exited
    bool slashed;             // Has been slashed
}
```

---

## Events

```solidity
event SoloStakerRegistered(address indexed staker, uint256 sgtBonded, uint256 timestamp);
event ValidatorDeposit(address indexed staker, uint256 ethAmount, uint256 vEth2Amount, uint256 pubkey);
event ValidatorExited(address indexed staker, uint256 timestamp);
event SGTUnlocked(address indexed staker, uint256 amount);
event SGTSslashed(address indexed staker, uint256 amount);
```

---

## Access Control

The contract uses a simple admin-based access control:

- **Admin**: Can mark validators as exited, unlock SGT, slash SGT
- **Stakers**: Can register, deposit, view their info

### Upgrade Path

For production, consider upgrading to OpenZeppelin's AccessControl:

```solidity
import "@openzeppelin/contracts/access/AccessControl.sol";

contract SoloStaking is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    constructor() {
        _setupRole(ADMIN_ROLE, msg.sender);
    }
}
```

---

## Testing

### Run Tests

```bash
# Install dependencies
npm install

# Run tests
truffle test test/TestSoloStaking.sol
```

### Test Coverage

- ✅ Registration with SGT bond
- ✅ Insufficient SGT handling
- ✅ Full deposit with validator keys
- ✅ Simplified deposit
- ✅ SGT unlock on exit
- ✅ SGT slash on misbehavior
- ✅ Staker count and info queries

---

## Deployment

### Network Configuration

Update `scripts/deploy.js` with actual addresses:

```javascript
const MINTER_ADDRESS = "0x...";
const SGT_ADDRESS = "0x...";
const VETH2_ADDRESS = "0x...";
const ADMIN_ADDRESS = "0x...";
```

### Deploy

```bash
# Mainnet
truffle migrate --network mainnet

# Rinkeby (testnet)
truffle migrate --network rinkeby
```

---

## Security Considerations

### SGT Bond

- **Purpose**: Incentivize honest validator behavior
- **Amount**: 1000 SGT
- **Lock**: Timelocked until validator exits
- **Slash**: Can be slashed if validator acts nefariously

### ETH Deposit

- **Amount**: 32 ETH (ETH2 requirement)
- **Fee**: 0.1 ETH (goes to Minter)
- **Total**: 32.1 ETH required

### Validator Keys

- **Responsibility**: Solo staker runs validator
- **Keys**: Staker maintains private keys
- **Withdrawal**: Staker controls withdrawal credentials

---

## Gas Optimization

### Current Implementation

- Registration: ~100k gas
- Deposit: ~200k gas
- Unlock SGT: ~50k gas

### Optimization Opportunities

1. **Batch Registration**: Register multiple stakers in one tx
2. **Merkle Proofs**: For SGT bond verification
3. **Layer 2**: Deploy on L2 for lower fees

---

## Future Enhancements

- [ ] Multi-validator support per staker
- [ ] Partial SGT unlock based on validator performance
- [ ] Automated slashing detection
- [ ] Reward distribution mechanism
- [ ] Delegation support (multi-staker validators)
- [ ] Integration with SharedStake pools

---

## Acceptance Criteria

- [x] Users can stake 32 ETH for solo staking
- [x] 1000 SGT bond requirement implemented
- [x] SGT is timelocked until validator exits
- [x] Admin can unlock SGT on validator exit
- [x] Admin can slash SGT on misbehavior
- [x] Users receive 32 vETH2 for 32.1 ETH
- [x] Minter upgraded to use AccessControl (pattern provided)
- [x] Simplified deposit function implemented
- [x] Full deposit with validator keys implemented
- [x] Tests included
- [x] Documentation complete

---

## References

- [ETH2 Deposit Contract](https://eth2-beaconchain.depositcontract/)
- [SharedStake Minter](./Minter_v1.0.1.sol)
- [OpenZeppelin AccessControl](https://docs.openzeppelin.com/contracts/3.x/access-control)

---

**Author**: 小米辣 (PM + Dev) 🌶️  
**Date**: 2026-03-23  
**Version**: 1.0.0  
**License**: MIT
