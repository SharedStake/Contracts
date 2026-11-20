// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

/**
 * @title IERC20
 * @notice Standard ERC20 token interface.
 */
interface IERC20 {
    /**
     * @notice Returns total token supply.
     * @return Total token supply.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Returns token balance of an account.
     * @param account Target address to query.
     * @return Account balance.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @notice Transfers tokens to a recipient.
     * @param recipient Target address receiving tokens.
     * @param amount Number of tokens transferred.
     * @return True if transfer succeeded.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @notice Returns remaining allowance granted to spender.
     * @param owner Approving account.
     * @param spender Delegated address.
     * @return Remaining allowance.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @notice Grants allowance to spender.
     * @param spender Delegated address.
     * @param amount Number of tokens allowed.
     * @return True if approval succeeded.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @notice Transfers tokens from sender to recipient using allowance.
     * @param sender Source address.
     * @param recipient Destination address.
     * @param amount Number of tokens transferred.
     * @return True if transfer succeeded.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
 * @title SafeMath
 * @notice Standard arithmetic library with overflow verification.
 */
library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        return a - b;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        return a / b;
    }
}

/**
 * @title IStrategy
 * @notice Interface for strategy connected to Sett vault.
 */
interface IStrategy {
    function want() external view returns (address);
    function deposit() external;
    function withdraw(address _recipient) external;
    function withdraw(uint256 _amount) external;
    function withdrawAll() external returns (uint256 balance);
    function balanceOf() external view returns (uint256);
    function harvest() external;
}

/**
 * @title SettVaultSgtEth
 * @notice Yearn/Sett style auto-compounding vault for SGT/ETH Uniswap V2 LP tokens.
 * Features customizable principal locking duration, boosted reward rate computation,
 * and historical voting power checkpoints for governance participation.
 */
contract SettVaultSgtEth is IERC20 {
    using SafeMath for uint256;

    string public name = "SharedStake Sett SGT/ETH LP";
    string public symbol = "bSgtEthLP";
    uint8 public decimals = 18;
    uint256 private _totalSupply;

    IERC20 public token;
    address public governance;
    address public controller;
    address public strategy;

    uint256 public min = 9500;
    uint256 public constant max = 10000;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    /**
     * @notice Record of lockup parameters for an individual account.
     */
    struct LockInfo {
        uint256 amount;
        uint256 unlockTimestamp;
        uint256 boostMultiplier;
    }
    mapping(address => LockInfo) public locks;

    /**
     * @notice Governance vote weight record at a designated block.
     */
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }
    mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;
    mapping(address => uint32) public numCheckpoints;

    event Deposited(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 amount, uint256 shares);
    event Locked(address indexed user, uint256 amount, uint256 duration, uint256 boostMultiplier);
    event Unlocked(address indexed user, uint256 amount);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

    modifier onlyGovernance() {
        require(msg.sender == governance, "!governance");
        _;
    }

    modifier onlyController() {
        require(msg.sender == controller || msg.sender == governance, "!controller");
        _;
    }

    /**
     * @notice Initializes vault with underlying LP token, governance, and controller addresses.
     * @param _token Address of underlying Uniswap V2 SGT/ETH LP token.
     * @param _governance Admin address possessing governance privileges.
     * @param _controller Management controller address.
     */
    constructor(
        address _token,
        address _governance,
        address _controller
    ) public {
        require(_token != address(0), "Invalid token");
        require(_governance != address(0), "Invalid governance");
        token = IERC20(_token);
        governance = _governance;
        controller = _controller;
    }

    /**
     * @notice Returns total minted share supply.
     * @return Total minted shares.
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @notice Returns vault shares held by an account.
     * @param account Target account address.
     * @return Balance of vault shares.
     */
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    /**
     * @notice Transfers vault shares to a recipient if unlocked.
     * @param recipient Receiving account.
     * @param amount Share quantity to transfer.
     * @return True upon success.
     */
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _checkLock(msg.sender, amount);
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    /**
     * @notice Queries approved share allowance.
     * @param owner Account owning shares.
     * @param spender Delegated address allowed to spend.
     * @return Remaining allowance.
     */
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @notice Approves spender to transfer shares on behalf of caller.
     * @param spender Delegated address.
     * @param amount Approved share limit.
     * @return True upon success.
     */
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice Transfers shares from sender to recipient with allowance and lock verification.
     * @param sender Source account.
     * @param recipient Destination account.
     * @param amount Share quantity transferred.
     * @return True upon success.
     */
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _checkLock(sender, amount);
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender].sub(amount));
        return true;
    }

    /**
     * @notice Calculates total underlying LP balance managed by vault and attached strategy.
     * @return Total underlying LP balance.
     */
    function balance() public view returns (uint256) {
        uint256 bal = token.balanceOf(address(this));
        if (strategy != address(0)) {
            bal = bal.add(IStrategy(strategy).balanceOf());
        }
        return bal;
    }

    /**
     * @notice Configures deployment threshold ratio for idle assets.
     * @param _min Minimum deployment threshold basis points out of 10000.
     */
    function setMin(uint256 _min) external onlyGovernance {
        require(_min <= max, "min > max");
        min = _min;
    }

    /**
     * @notice Reassigns governance authority.
     * @param _governance New governance address.
     */
    function setGovernance(address _governance) external onlyGovernance {
        require(_governance != address(0), "zero address");
        governance = _governance;
    }

    /**
     * @notice Updates controller address.
     * @param _controller New controller address.
     */
    function setController(address _controller) external onlyGovernance {
        controller = _controller;
    }

    /**
     * @notice Binds strategy contract to vault.
     * @param _strategy Address of strategy contract.
     */
    function setStrategy(address _strategy) external onlyGovernance {
        require(_strategy != address(0), "zero strategy");
        require(IStrategy(_strategy).want() == address(token), "invalid strategy want");
        strategy = _strategy;
    }

    /**
     * @notice Deploys available idle underlying assets from vault into active strategy.
     */
    function earn() public {
        if (strategy == address(0)) return;
        uint256 _bal = available();
        if (_bal > 0) {
            token.transfer(strategy, _bal);
            IStrategy(strategy).deposit();
        }
    }

    /**
     * @notice Computes currently deployable idle token balance based on min threshold.
     * @return Deployable idle token quantity.
     */
    function available() public view returns (uint256) {
        return token.balanceOf(address(this)).mul(min).div(max);
    }

    /**
     * @notice Deposits underlying LP tokens in exchange for newly minted vault shares.
     * @param _amount Number of underlying LP tokens deposited.
     */
    function deposit(uint256 _amount) public {
        uint256 _pool = balance();
        require(token.transferFrom(msg.sender, address(this), _amount), "transferFrom failed");
        uint256 shares = 0;
        if (_totalSupply == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(_totalSupply)).div(_pool);
        }
        _mint(msg.sender, shares);
        emit Deposited(msg.sender, _amount, shares);
    }

    /**
     * @notice Deposits entire caller LP token balance into vault.
     */
    function depositAll() external {
        deposit(token.balanceOf(msg.sender));
    }

    /**
     * @notice Deposits LP tokens and immediately applies time-lock for boosted voting power.
     * @param _amount LP tokens deposited.
     * @param _durationSeconds Duration of principal lock in seconds.
     */
    function depositWithLock(uint256 _amount, uint256 _durationSeconds) external {
        deposit(_amount);
        lockShares(balanceOf(msg.sender), _durationSeconds);
    }

    /**
     * @notice Locks specified shares for duration to achieve boosted voting power and rewards.
     * @param _shares Quantity of vault shares locked.
     * @param _durationSeconds Lock duration between 7 days and 365 days.
     */
    function lockShares(uint256 _shares, uint256 _durationSeconds) public {
        require(_shares > 0 && _shares <= _balances[msg.sender], "invalid shares");
        require(_durationSeconds >= 7 days, "min lock 7 days");
        require(_durationSeconds <= 365 days, "max lock 1 year");

        uint256 boost = uint256(10000).add(_durationSeconds.mul(15000).div(365 days));

        locks[msg.sender] = LockInfo({
            amount: _shares,
            unlockTimestamp: block.timestamp.add(_durationSeconds),
            boostMultiplier: boost
        });

        _writeCheckpoint(msg.sender, _shares.mul(boost).div(10000));
        emit Locked(msg.sender, _shares, _durationSeconds, boost);
    }

    /**
     * @notice Releases expired principal locks and resets voting checkpoint.
     */
    function unlock() external {
        LockInfo memory lock = locks[msg.sender];
        require(lock.amount > 0, "no lock");
        require(block.timestamp >= lock.unlockTimestamp, "lock not expired");
        delete locks[msg.sender];
        _writeCheckpoint(msg.sender, _balances[msg.sender]);
        emit Unlocked(msg.sender, lock.amount);
    }

    /**
     * @notice Burns vault shares and redeems proportional underlying LP tokens.
     * @param _shares Number of shares redeemed.
     */
    function withdraw(uint256 _shares) public {
        _checkLock(msg.sender, _shares);
        uint256 r = (balance().mul(_shares)).div(_totalSupply);
        _burn(msg.sender, _shares);

        uint256 b = token.balanceOf(address(this));
        if (b < r) {
            uint256 _toWithdraw = r.sub(b);
            if (strategy != address(0)) {
                IStrategy(strategy).withdraw(_toWithdraw);
            }
            uint256 _after = token.balanceOf(address(this));
            uint256 _diff = _after.sub(b);
            if (_diff < _toWithdraw) {
                r = b.add(_diff);
            }
        }

        token.transfer(msg.sender, r);
        emit Withdrawn(msg.sender, r, _shares);
    }

    /**
     * @notice Redeems entire unlocked share balance for underlying LP tokens.
     */
    function withdrawAll() external {
        withdraw(_balances[msg.sender]);
    }

    /**
     * @notice Computes exchange rate of 1 share expressed in underlying LP tokens (18 decimals).
     * @return Underlying tokens corresponding to 1 unit share.
     */
    function getPricePerFullShare() public view returns (uint256) {
        if (_totalSupply == 0) return 1e18;
        return balance().mul(1e18).div(_totalSupply);
    }

    /**
     * @notice Queries current voting weight of an account.
     * @param account Target account address.
     * @return Current voting power.
     */
    function getVotes(address account) external view returns (uint256) {
        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) return 0;
        return checkpoints[account][nCheckpoints - 1].votes;
    }

    /**
     * @notice Queries historical voting power of an account at a previous block number.
     * @param account Target account address.
     * @param blockNumber Historical block number.
     * @return Historical voting power.
     */
    function getPriorVotes(address account, uint256 blockNumber) external view returns (uint256) {
        require(blockNumber < block.number, "not yet determined");
        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) return 0;
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }
        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2;
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _checkLock(address account, uint256 amount) internal view {
        LockInfo memory lock = locks[account];
        if (lock.amount > 0 && block.timestamp < lock.unlockTimestamp) {
            uint256 unlockedShares = _balances[account] > lock.amount ? _balances[account].sub(lock.amount) : 0;
            require(amount <= unlockedShares, "shares locked for voting/boost");
        }
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "transfer from zero");
        require(recipient != address(0), "transfer to zero");
        _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "mint to zero");
        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "burn from zero");
        _balances[account] = _balances[account].sub(amount);
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "approve from zero");
        require(spender != address(0), "approve to zero");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _writeCheckpoint(address delegatee, uint256 newVotes) internal {
        uint32 blockNumber = uint32(block.number);
        uint32 nCheckpoints = numCheckpoints[delegatee];
        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }
        emit DelegateVotesChanged(delegatee, nCheckpoints > 0 ? checkpoints[delegatee][nCheckpoints - 1].votes : 0, newVotes);
    }
}
