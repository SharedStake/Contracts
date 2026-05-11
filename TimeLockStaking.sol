// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
contract TimeLockStaking {
    using SafeMath for uint256;
    struct Stake { uint256 amount; uint256 lockDuration; uint256 stakedAt; uint256 claimedAt; }
    IERC20 public stakingToken; IERC20 public rewardToken;
    uint256 public baseRewardRate = 1e18;
    mapping(uint256 => uint256) public lockMultiplier;
    mapping(address => Stake[]) public stakes;
    event Staked(address indexed user, uint256 amount, uint256 lockDuration);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    constructor(address _stakingToken, address _rewardToken) {
        stakingToken = IERC20(_stakingToken); rewardToken = IERC20(_rewardToken);
        lockMultiplier[30 days] = 1; lockMultiplier[60 days] = 2; lockMultiplier[90 days] = 3;
    }
    function stake(uint256 amount, uint256 lockDuration) external {
        require(lockMultiplier[lockDuration] > 0, "invalid duration");
        stakingToken.transferFrom(msg.sender, address(this), amount);
        stakes[msg.sender].push(Stake(amount, lockDuration, block.timestamp, block.timestamp));
        emit Staked(msg.sender, amount, lockDuration);
    }
    function calculateReward(address user, uint256 stakeIndex) public view returns (uint256) {
        Stake storage s = stakes[user][stakeIndex];
        uint256 elapsed = block.timestamp.sub(s.stakedAt);
        if (elapsed < s.lockDuration) return 0;
        uint256 multiplier = lockMultiplier[s.lockDuration];
        return s.amount.mul(baseRewardRate).mul(multiplier).div(1e18);
    }
    function getReward(uint256 stakeIndex) external {
        uint256 reward = calculateReward(msg.sender, stakeIndex);
        require(reward > 0, "no reward");
        stakes[msg.sender][stakeIndex].claimedAt = block.timestamp;
        rewardToken.transfer(msg.sender, reward);
        emit RewardPaid(msg.sender, reward);
    }
    function withdraw(uint256 stakeIndex) external {
        Stake storage s = stakes[msg.sender][stakeIndex];
        require(block.timestapp >= s.stakedAt.add(s.lockDuration), "locked");
        uint256 amount = s.amount; s.amount = 0;
        stakingToken.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }
}