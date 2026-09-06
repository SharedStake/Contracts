#!/bin/bash

mkdir -p scripts/sett
echo "pragma solidity ^0.8.0;" > scripts/sett/SgtSettStyleVault.sol
echo "import '@yearn/contracts-v2';" >> scripts/sett/SgtSettStyleVault.sol
echo "import 'IERC20.sol';" >> scripts/sett/SgtSettStyleVault.sol
echo "contract SgtSettStyleVault {" >> scripts/sett/SgtSettStyleVault.sol
echo "    address public immutable sgt;" >> scripts/sett/SgtSettStyleVault.sol
echo "    IERC20 public sgtToken;" >> scripts/sett/SgtSettStyleVault.sol
echo "    mapping(address => uint256) public lockedFunds;" >> scripts/sett/SgtSettStyleVault.sol
echo "    function getRewardRate(uint256 lockupPeriod) public view returns (uint256) {" >> scripts/sett/SgtSettStyleVault.sol
echo "        // implement logic for reward rate modification based on lockup period" >> scripts/sett/SgtSettStyleVault.sol
echo "        return 0;" >> scripts/sett/SgtSettStyleVault.sol
echo "    }" >> scripts/sett/SgtSettStyleVault.sol
echo "}" >> scripts/sett/SgtSettStyleVault.sol

chmod +x scripts/sett/SgtSettStyleVault.sol
