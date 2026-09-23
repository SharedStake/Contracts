const solc = require('solc');
const fs = require('fs');
const path = require('path');

// Solidity files and their expected compiler version ranges
const contracts = [
  { file: 'ConsolidatedFund.sol', minVersion: '0.8.0', maxVersion: '0.8.99' },
  { file: 'vEth2.sol', minVersion: '0.7.5', maxVersion: '0.7.99' },
  { file: 'Minter_v1.0.1.sol', minVersion: '0.7.5', maxVersion: '0.7.99' },
  { file: 'SGT.sol', minVersion: '0.5.16', maxVersion: '0.5.99' },
  { file: 'SmartTimelock.sol', minVersion: '0.6.9', maxVersion: '0.6.99' },
  { file: 'SmartVesting.sol', minVersion: '0.6.9', maxVersion: '0.6.99' },
  { file: 'Airdrop.sol', minVersion: '0.6.11', maxVersion: '0.6.99' },
  { file: 'Airdrop_v2.sol', minVersion: '0.6.11', maxVersion: '0.6.99' },
  { file: 'MasterChef.sol', minVersion: '0.6.12', maxVersion: '0.6.99' },
  { file: 'stakingPools.sol', minVersion: '0.5.17', maxVersion: '0.5.99' },
];

function getSolidityVersion(content) {
  const match = content.match(/pragma solidity\s+[=^~]?\s*(\d+\.\d+\.\d+)/);
  return match ? match[1] : null;
}

let failures = 0;

// Test 1: Verify all contract files exist
console.log('Test 1: Verify all contract files exist');
for (const contract of contracts) {
  if (fs.existsSync(contract.file)) {
    console.log(`  ✓ ${contract.file} exists`);
  } else {
    console.error(`  ✗ ${contract.file} is missing`);
    failures++;
  }
}

// Test 2: Verify pragma versions are correctly specified
console.log('\nTest 2: Verify pragma versions are specified');
for (const contract of contracts) {
  if (fs.existsSync(contract.file)) {
    const content = fs.readFileSync(contract.file, 'utf8');
    const version = getSolidityVersion(content);
    if (version) {
      console.log(`  ✓ ${contract.file}: solidity ${version}`);
    } else {
      console.error(`  ✗ ${contract.file}: no pragma version found`);
      failures++;
    }
  }
}

// Test 3: Compile contracts with compatible compiler (0.8.4)
console.log('\nTest 3: Compile contracts with available compiler (0.8.4)');
const solFiles = fs.readdirSync('.').filter(f => f.endsWith('.sol') && !f.includes('flat'));
const compileTargets = {};

for (const file of solFiles) {
  const content = fs.readFileSync(file, 'utf8');
  // Only compile contracts with ^0.8.0 pragma (compatible with 0.8.4)
  // ConsolidatedFund.sol uses pragma solidity ^0.8.0 and 0.8.4 - compatible
  if (file === 'ConsolidatedFund.sol') {
    compileTargets[file] = { content };
  }
}

if (Object.keys(compileTargets).length > 0) {
  const input = {
    language: 'Solidity',
    sources: compileTargets,
    settings: {
      outputSelection: { '*': { '*': ['abi'] } },
      remappings: ['@openzeppelin/=node_modules/@openzeppelin/']
    }
  };
  const output = JSON.parse(solc.compile(JSON.stringify(input)));
  const errors = (output.errors || []).filter(e => e.severity === 'error');
  if (errors.length > 0) {
    console.error('  ✗ Compilation errors:');
    errors.forEach(e => console.error('   ', e.message));
    failures++;
  } else {
    for (const file of Object.keys(compileTargets)) {
      if (output.contracts && output.contracts[file]) {
        console.log(`  ✓ ${file} compiled: ${Object.keys(output.contracts[file]).join(', ')}`);
      } else {
        console.error(`  ✗ ${file}: no output`);
        failures++;
      }
    }
  }
}

// Test 4: Verify key security patterns in the code
console.log('\nTest 4: Verify security patterns');

// Check SmartTimelock uses safeTransfer
const smartTimelock = fs.readFileSync('SmartTimelock.sol', 'utf8');
if (smartTimelock.includes('SafeERC20') && smartTimelock.includes('safeTransfer')) {
  console.log('  ✓ SmartTimelock.sol uses SafeERC20.safeTransfer');
} else {
  console.error('  ✗ SmartTimelock.sol does not use SafeERC20.safeTransfer');
  failures++;
}

// Check SmartVesting uses safeTransfer
const smartVesting = fs.readFileSync('SmartVesting.sol', 'utf8');
if (smartVesting.includes('SafeERC20') && smartVesting.includes('safeTransfer')) {
  console.log('  ✓ SmartVesting.sol uses SafeERC20.safeTransfer');
} else {
  console.error('  ✗ SmartVesting.sol does not use SafeERC20.safeTransfer');
  failures++;
}

// Check SmartTimeLock_flat uses safeTransfer
if (fs.existsSync('SmartTimeLock_flat.sol')) {
  const smartTimelockFlat = fs.readFileSync('SmartTimeLock_flat.sol', 'utf8');
  if (smartTimelockFlat.includes('SafeERC20') && smartTimelockFlat.includes('safeTransfer')) {
    console.log('  ✓ SmartTimeLock_flat.sol uses SafeERC20.safeTransfer');
  } else {
    console.error('  ✗ SmartTimeLock_flat.sol does not use SafeERC20.safeTransfer');
    failures++;
  }
}

// Check SmartVesting_flat uses safeTransfer
if (fs.existsSync('SmartVesting_flat.sol')) {
  const smartVestingFlat = fs.readFileSync('SmartVesting_flat.sol', 'utf8');
  if (smartVestingFlat.includes('SafeERC20') && smartVestingFlat.includes('safeTransfer')) {
    console.log('  ✓ SmartVesting_flat.sol uses SafeERC20.safeTransfer');
  } else {
    console.error('  ✗ SmartVesting_flat.sol does not use SafeERC20.safeTransfer');
    failures++;
  }
}

// Check Minter adminFee validation
const minter = fs.readFileSync('Minter_v1.0.1.sol', 'utf8');
if (minter.includes('require(amount < costPerValidator')) {
  console.log('  ✓ Minter_v1.0.1.sol has adminFee validation');
} else {
  console.error('  ✗ Minter_v1.0.1.sol missing adminFee validation');
  failures++;
}

// Check Minter adminFeeTotal underflow protection
if (minter.includes('if (adminFeePortion > adminFeeTotal)')) {
  console.log('  ✓ Minter_v1.0.1.sol has adminFeeTotal underflow protection');
} else {
  console.error('  ✗ Minter_v1.0.1.sol missing adminFeeTotal underflow protection');
  failures++;
}

// Summary
console.log('\n' + '='.repeat(50));
if (failures === 0) {
  console.log('All tests passed!');
  process.exit(0);
} else {
  console.log(`${failures} test(s) failed!`);
  process.exit(1);
}
