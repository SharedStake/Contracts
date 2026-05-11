// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AutoCompoundVault is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public lpToken;
    address public rewardPool;
    mapping(address => uint256) public balances;
    uint256 public totalShares;

    event Deposited(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 amount, uint256 shares);
    event Compounded(uint256 rewards);

    constructor(address _lpToken, address _rewardPool) {
        lpToken = IERC20(_lpToken);
        rewardPool = _rewardPool;
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "ZERO_AMOUNT");
        lpToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 shares = totalShares == 0 ? amount : amount * totalShares / lpToken.balanceOf(address(this));
        balances[msg.sender] += shares;
        totalShares += shares;
        emit Deposited(msg.sender, amount, shares);
    }

    function withdraw(uint256 shares) external {
        require(shares <= balances[msg.sender], "INSUFFICIENT_SHARES");
        uint256 amount = shares * lpToken.balanceOf(address(this)) / totalShares;
        balances[msg.sender] -= shares;
        totalShares -= shares;
        lpToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount, shares);
    }

    function compound() external onlyOwner {
        uint256 rewards = IERC20(rewardPool).balanceOf(address(this));
        if (rewards > 0) {
            emit Compounded(rewards);
        }
    }
}