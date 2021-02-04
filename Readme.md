# Contracts
A repository to track and open source SharedStake's on-chain contracts and their addresses.


## vEth2

Veth2 is a yield bearing token that represents staked Ether. The contract has a minter address that mints the token whenever an Ether deposited to the minter contract. When 32 eth exceeded, you can call the stake to eth2 function on the minter contract and create a validator. This will lock the Eth deposited into the eth2.

> Address: [0x898bad2774eb97cf6b94605677f43b41871410b1](https://etherscan.io/token/0x898bad2774eb97cf6b94605677f43b41871410b1)


## Minter

Minter contract is responsible for:
- minting/burning vEth2
- Staking Ether to Eth2
- Collect Admin fee
- Change the minter contract & address in case its needed. 

> Address: [0xbca3b7b87dcb15f0efa66136bc0e4684a3e5da4d](https://etherscan.io/token/0xbca3b7b87dcb15f0efa66136bc0e4684a3e5da4d)


## SGT

SGT is the Governance Token of the SharedStake platform.
SharedStake DAO is a Decentralized Ethereum Staking Service, which provides extra incentive with yield farming, on top of Ethereum2 staking profits.
Protocol allows stakers to use their staked Ether as vEth2 while earning ethereum2 staking profits and supports various other DAO such as Uniswap and Snowswap.
> Address: [0x84810bcF08744d5862B8181f12d17bfd57d3b078](https://etherscan.io/token/0x84810bcF08744d5862B8181f12d17bfd57d3b078)


## Airdrop

Merkle Root Distributor. These Contract deal with verification of Merkle trees (hash trees) for the airdrop distribution. **"Distributor" Contract will be implemented with this template, which has non-continutous merkle root distribution for eth2 staking rewards.**

> Address: [0x342eb0fc69c2e20e2ae6338579af572b81cdbdf8](https://etherscan.io/token/0x342eb0fc69c2e20e2ae6338579af572b81cdbdf8)


## Staking Pools

You can stake your SGT, [SGT-ETH uniswap LP](https://info.uniswap.org/pair/0x3d07f6e1627da96b8836190de64c1aed70e3fc55) or vEth2 to get **SGT Rewards**.

> SGT   :[0xc637dB981e417869814B2Ea2F1bD115d2D993597](https://etherscan.io/token/0xc637dB981e417869814B2Ea2F1bD115d2D993597)

> Uni-LP:[0x64A1DB33f68695df773924682D2EFb1161B329e8](https://etherscan.io/token/0x64A1DB33f68695df773924682D2EFb1161B329e8)

> vEth2 :[0xA919D7a5fb7ad4ab6F2aae82b6F39d181A027d35](https://etherscan.io/token/0xA919D7a5fb7ad4ab6F2aae82b6F39d181A027d35)


# Development
You can use Remix or any other preffered setup.

## Release guide
- Release vEth2Token.sol with your address for owner and minter
- Release Minter.sol, using the vEth2 token address
- Call set minter on vEth2 to transfer the ownership to Minter address.
- In the case of contract upgrades, Minter has a setMinter to transfer the token supply to the new contract

## Notes:
-  Minter will not transfer non-staked Ether to the new contract!