// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title StakingRewardsTimelock
 * @dev 基于时间锁定的质押奖励合约
 * @author Vincent
 */
contract StakingRewardsTimelock {
    // 状态变量
    address public stakingToken;
    address public rewardToken;
    address public owner;
    
    // 时间锁定配置
    struct TimelockConfig {
        uint256 duration;      // 锁定时间（秒）
        uint256 rewardRate;    // 奖励率（基点，10000 = 100%）
        bool active;           // 是否激活
    }
    
    // 用户信息
    struct UserInfo {
        uint256 amount;           // 质押数量
        uint256 rewardDebt;       // 奖励债务
        uint256 lockStartTime;    // 锁定开始时间
        uint256 lockDuration;     // 锁定时长
        uint256 rewardRate;       // 奖励率
    }
    
    // 时间锁定配置
    mapping(uint256 => TimelockConfig) public timelockConfigs;
    uint256[] public timelockDurations;
    
    // 用户信息
    mapping(address => UserInfo) public userInfo;
    
    // 奖励池
    uint256 public totalStaked;
    uint256 public rewardPerSecond;
    uint256 public lastUpdateTime;
    uint256 public accRewardPerShare;
    
    // 事件
    event Staked(address indexed user, uint256 amount, uint256 duration);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event TimelockConfigUpdated(uint256 duration, uint256 rewardRate, bool active);
    
    constructor(
        address _stakingToken,
        address _rewardToken,
        uint256 _rewardPerSecond
    ) {
        require(_stakingToken != address(0), "Invalid staking token");
        require(_rewardToken != address(0), "Invalid reward token");
        require(_rewardPerSecond > 0, "Invalid reward per second");
        
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        rewardPerSecond = _rewardPerSecond;
        owner = msg.sender;
        lastUpdateTime = block.timestamp;
        
        // 初始化时间锁定配置
        _initializeTimelockConfigs();
    }
    
    /**
     * @dev 初始化时间锁定配置
     */
    function _initializeTimelockConfigs() internal {
        // 30天锁定，50%奖励率
        timelockConfigs[30 days] = TimelockConfig({
            duration: 30 days,
            rewardRate: 5000, // 50%
            active: true
        });
        timelockDurations.push(30 days);
        
        // 90天锁定，100%奖励率
        timelockConfigs[90 days] = TimelockConfig({
            duration: 90 days,
            rewardRate: 10000, // 100%
            active: true
        });
        timelockDurations.push(90 days);
        
        // 180天锁定，200%奖励率
        timelockConfigs[180 days] = TimelockConfig({
            duration: 180 days,
            rewardRate: 20000, // 200%
            active: true
        });
        timelockDurations.push(180 days);
        
        // 365天锁定，500%奖励率
        timelockConfigs[365 days] = TimelockConfig({
            duration: 365 days,
            rewardRate: 50000, // 500%
            active: true
        });
        timelockDurations.push(365 days);
    }
    
    /**
     * @dev 更新奖励变量
     */
    function updateReward() public {
        if (block.timestamp <= lastUpdateTime) {
            return;
        }
        
        if (totalStaked == 0) {
            lastUpdateTime = block.timestamp;
            return;
        }
        
        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        uint256 reward = timeElapsed * rewardPerSecond;
        
        accRewardPerShare += (reward * 1e18) / totalStaked;
        lastUpdateTime = block.timestamp;
    }
    
    /**
     * @dev 质押代币
     * @param amount 质押数量
     * @param duration 锁定时长
     */
    function stake(uint256 amount, uint256 duration) external {
        require(amount > 0, "Amount must be > 0");
        require(timelockConfigs[duration].active, "Invalid timelock duration");
        
        updateReward();
        
        UserInfo storage user = userInfo[msg.sender];
        
        // 如果用户已有质押，先领取奖励
        if (user.amount > 0) {
            uint256 pendingReward = _calculatePendingReward(msg.sender);
            if (pendingReward > 0) {
                _payReward(msg.sender, pendingReward);
            }
        }
        
        // 更新用户信息
        user.amount += amount;
        user.lockStartTime = block.timestamp;
        user.lockDuration = duration;
        user.rewardRate = timelockConfigs[duration].rewardRate;
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e18;
        
        // 更新总质押量
        totalStaked += amount;
        
        emit Staked(msg.sender, amount, duration);
    }
    
    /**
     * @dev 提取代币
     * @param amount 提取数量
     */
    function withdraw(uint256 amount) external {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= amount, "Insufficient balance");
        require(amount > 0, "Amount must be > 0");
        
        // 检查时间锁定
        require(
            block.timestamp >= user.lockStartTime + user.lockDuration,
            "Timelock not expired"
        );
        
        updateReward();
        
        // 计算并支付奖励
        uint256 pendingReward = _calculatePendingReward(msg.sender);
        if (pendingReward > 0) {
            _payReward(msg.sender, pendingReward);
        }
        
        // 更新用户信息
        user.amount -= amount;
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e18;
        
        // 更新总质押量
        totalStaked -= amount;
        
        // 转移代币
        _transferToken(msg.sender, amount);
        
        emit Withdrawn(msg.sender, amount);
    }
    
    /**
     * @dev 领取奖励
     */
    function claimReward() external {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount > 0, "No staked amount");
        
        updateReward();
        
        uint256 pendingReward = _calculatePendingReward(msg.sender);
        require(pendingReward > 0, "No pending reward");
        
        _payReward(msg.sender, pendingReward);
        
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e18;
    }
    
    /**
     * @dev 计算待领取奖励
     * @param user 用户地址
     * @return pendingReward 待领取奖励
     */
    function _calculatePendingReward(address user) internal returns (uint256 pendingReward) {
        UserInfo storage userInfo_ = userInfo[user];
        
        // 基础奖励
        uint256 baseReward = (userInfo_.amount * accRewardPerShare) / 1e18 - userInfo_.rewardDebt;
        
        // 时间锁定奖励加成
        uint256 timelockBonus = (baseReward * userInfo_.rewardRate) / 10000;
        
        pendingReward = baseReward + timelockBonus;
    }
    
    /**
     * @dev 支付奖励
     * @param user 用户地址
     * @param amount 奖励数量
     */
    function _payReward(address user, uint256 amount) internal {
        // 这里应该转移奖励代币
        // rewardToken.transfer(user, amount);
        
        emit RewardPaid(user, amount);
    }
    
    /**
     * @dev 转移代币
     * @param to 接收地址
     * @param amount 转移数量
     */
    function _transferToken(address to, uint256 amount) internal {
        // 这里应该转移质押代币
        // stakingToken.transfer(to, amount);
    }
    
    /**
     * @dev 更新时间锁定配置
     * @param duration 锁定时长
     * @param rewardRate 奖励率
     * @param active 是否激活
     */
    function updateTimelockConfig(uint256 duration, uint256 rewardRate, bool active) external {
        require(msg.sender == owner, "Only owner");
        require(duration > 0, "Invalid duration");
        require(rewardRate > 0, "Invalid reward rate");
        
        timelockConfigs[duration] = TimelockConfig({
            duration: duration,
            rewardRate: rewardRate,
            active: active
        });
        
        // 如果是新的时长，添加到数组
        bool found = false;
        for (uint256 i = 0; i < timelockDurations.length; i++) {
            if (timelockDurations[i] == duration) {
                found = true;
                break;
            }
        }
        if (!found) {
            timelockDurations.push(duration);
        }
        
        emit TimelockConfigUpdated(duration, rewardRate, active);
    }
    
    /**
     * @dev 获取用户信息
     * @param user 用户地址
     * @return amount 质押数量
     * @return lockStartTime 锁定开始时间
     * @return lockDuration 锁定时长
     * @return rewardRate 奖励率
     */
    function getUserInfo(address user) external view returns (
        uint256 amount,
        uint256 lockStartTime,
        uint256 lockDuration,
        uint256 rewardRate
    ) {
        UserInfo storage user_ = userInfo[user];
        return (user_.amount, user_.lockStartTime, user_.lockDuration, user_.rewardRate);
    }
    
    /**
     * @dev 获取时间锁定配置
     * @param duration 锁定时长
     * @return rewardRate 奖励率
     * @return active 是否激活
     */
    function getTimelockConfig(uint256 duration) external view returns (
        uint256 rewardRate,
        bool active
    ) {
        TimelockConfig storage config = timelockConfigs[duration];
        return (config.rewardRate, config.active);
    }
    
    /**
     * @dev 获取所有时间锁定时长
     * @return durations 时间锁定时长数组
     */
    function getTimelockDurations() external view returns (uint256[] memory) {
        return timelockDurations;
    }
}
