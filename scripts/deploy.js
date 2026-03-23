// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

const MINTER_ADDRESS = "0x..."; // Replace with actual Minter address
const SGT_ADDRESS = "0x...";    // Replace with actual SGT address
const VETH2_ADDRESS = "0x...";  // Replace with actual vETH2 address
const ADMIN_ADDRESS = "0x...";  // Replace with admin address

async function deploy() {
  console.log("Deploying SoloStaking contract...");
  
  const SoloStaking = await ethers.getContractFactory("SoloStaking");
  const soloStaking = await SoloStaking.deploy(
    MINTER_ADDRESS,
    SGT_ADDRESS,
    VETH2_ADDRESS,
    ADMIN_ADDRESS
  );
  
  await soloStaking.deployed();
  
  console.log("SoloStaking deployed to:", soloStaking.address);
  
  return soloStaking;
}

deploy()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
