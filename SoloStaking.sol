// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SGT.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SoloStaking is Ownable {
    SGT public sgt;
    uint256 public constant MIN_STAKE = 32 ether;
    mapping(address => uint256) public stakedEth;
    mapping(address => uint256) public bondedSgt;

    event Staked(address indexed user, uint256 ethAmount, uint256 sgtAmount);
    event Unstaked(address indexed user, uint256 ethAmount);

    constructor(address _sgt) { sgt = SGT(_sgt); }

    function stake() external payable {
        require(msg.value >= MIN_STAKE, "MIN_32_ETH");
        uint256 sgtAmount = msg.value; // 1:1 bond ratio
        sgt.transferFrom(msg.sender, address(this), sgtAmount);
        stakedEth[msg.sender] += msg.value;
        bondedSgt[msg.sender] += sgtAmount;
        emit Staked(msg.sender, msg.value, sgtAmount);
    }

    function unstake(uint256 ethAmount) external {
        require(stakedEth[msg.sender] >= ethAmount, "INSUFFICIENT_STAKE");
        uint256 sgtAmount = ethAmount;
        stakedEth[msg.sender] -= ethAmount;
        bondedSgt[msg.sender] -= sgtAmount;
        sgt.transfer(msg.sender, sgtAmount);
        payable(msg.sender).transfer(ethAmount);
        emit Unstaked(msg.sender, ethAmount);
    }

    receive() external payable {}
}