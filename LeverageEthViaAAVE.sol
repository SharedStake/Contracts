// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow checks.
 */
library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction underflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;
        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }
}

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be successful.
 */
library SafeERC20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        require(address(token).isContract(), "SafeERC20: call to non-contract");
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 */
contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor () internal {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

/**
 * @dev Contract module which provides a basic access control mechanism.
 */
contract Ownable {
    address private _owner;
    address private _nominatedOwner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnerNominated(address indexed newOwner);

    constructor () internal {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function nominatedOwner() public view returns (address) {
        return _nominatedOwner;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    function nominateNewOwner(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Ownable: new owner is 0 address");
        _nominatedOwner = _newOwner;
        emit OwnerNominated(_newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == _nominatedOwner, "Ownable: caller is not nominated");
        emit OwnershipTransferred(_owner, _nominatedOwner);
        _owner = _nominatedOwner;
        _nominatedOwner = address(0);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
        _nominatedOwner = address(0);
    }
}

/**
 * @dev Contract module which allows children to implement an emergency stop mechanism.
 */
contract Pausable is Ownable {
    event Paused(address account);
    event Unpaused(address account);

    bool private _paused;

    constructor () internal {
        _paused = false;
    }

    function paused() public view returns (bool) {
        return _paused;
    }

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }

    function pause() public onlyOwner whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() public onlyOwner whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

/* ==================================================================== */
/*                             INTERFACES                               */
/* ==================================================================== */

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface ILendingPoolAddressesProvider {
    function getLendingPool() external view returns (address);
    function getPriceOracle() external view returns (address);
}

interface ILendingPool {
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;
    function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external returns (uint256);
    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralETH,
        uint256 totalDebtETH,
        uint256 availableBorrowsETH,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
}

interface IWETHGateway {
    function depositETH(address lendingPool, address onBehalfOf, uint16 referralCode) external payable;
    function withdrawETH(address lendingPool, uint256 amount, address to) external;
    function repayETH(address lendingPool, uint256 amount, uint256 rateMode, address onBehalfOf) external payable;
    function borrowETH(address lendingPool, uint256 amount, uint256 interestRateMode, uint16 referralCode) external;
}

interface ICreditDelegationToken {
    function approveDelegation(address delegatee, uint256 amount) external;
    function borrowAllowance(address fromUser, address toUser) external view returns (uint256);
}

interface IStableDebtToken is ICreditDelegationToken {}
interface IVariableDebtToken is ICreditDelegationToken {}

interface IUniswapV2Router02 {
    function WETH() external pure returns (address);
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
    function decimals() external view returns (uint8);
}

interface ISharedDeposit {
    function deposit() external payable;
    function BETHTokenAddress() external view returns (address);
}

interface IvETH2 is IERC20 {
    function mint(address dst, uint256 rawAmount) external;
    function burn(address src, uint256 rawAmount) external;
}

/* ==================================================================== */
/*                        MAIN STRATEGY CONTRACT                        */
/* ==================================================================== */

/**
 * @title LeverageEthViaAAVE / EthDerivativeProxy
 * @notice A comprehensive derivative and leverage strategy proxy for ETH using AAVE CDP,
 * Uniswap V2 Router, Chainlink Price Feeds, and SharedStake staking protocol.
 *
 * Supports:
 * - Long ETH: Deposits ETH as collateral, borrows stablecoins (e.g. DAI), swaps to ETH on Uniswap,
 *   loops up to desired health factor, delegates remaining credit back to user, and optionally
 *   stakes resulting ETH into SharedStake (depositing to SharedDeposit and transferring vETH2 tokens to user).
 * - Short ETH: Deposits stablecoins as collateral, borrows ETH from AAVE, swaps ETH for stablecoins
 *   or deposits borrowed ETH to SharedStake to earn yield while shorting ETH.
 * - Bidirectional Credit Delegation:
 *     * Contract -> User: delegates remaining debt allowance to user.
 *     * User -> Contract: borrows against user-deposited Aave collateral and manages staking/swaps.
 * - Graceful fallback / testnet support (e.g., Kovan): If SharedStake is unavailable (sharedDeposit == address(0)),
 *   swapped/borrowed ETH is returned directly to the user.
 * - Position withdrawal & debt repayment.
 */
contract LeverageEthViaAAVE is Ownable, Pausable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    // AAVE Core Contracts
    ILendingPoolAddressesProvider public addressesProvider;
    ILendingPool public lendingPool;
    IWETHGateway public wethGateway;

    // Uniswap Router
    IUniswapV2Router02 public uniswapRouter;

    // Tokens & Assets
    address public weth;
    address public aWeth;
    address public stableAsset;              // e.g. DAI / USDC
    address public stableDebtToken;          // Stable debt token for stableAsset
    address public variableDebtToken;        // Variable debt token for stableAsset
    address public wethVariableDebtToken;    // Variable debt token for WETH
    address public wethStableDebtToken;      // Stable debt token for WETH

    // SharedStake Contracts (optional / can be zero on testnets without SharedStake)
    address public sharedDeposit;
    address public vEth2Token;

    // Chainlink Oracle Price Feed
    AggregatorV3Interface public priceFeed;

    // Events
    event LongPositionOpened(
        address indexed user,
        uint256 ethSupplied,
        uint256 totalDebtBorrowed,
        uint256 totalEthObtained,
        uint256 vEthMinted
    );

    event ShortPositionOpened(
        address indexed user,
        address collateralAsset,
        uint256 collateralAmount,
        uint256 ethBorrowed,
        uint256 returnAmount
    );

    event CreditDelegated(
        address indexed delegator,
        address indexed delegatee,
        address indexed debtToken,
        uint256 amount
    );

    event StakedToSharedDeposit(
        address indexed user,
        uint256 ethStaked,
        uint256 vEthMinted
    );

    event DebtRepaid(
        address indexed user,
        address indexed asset,
        uint256 amount,
        uint256 rateMode,
        address indexed onBehalfOf
    );

    event CollateralWithdrawn(
        address indexed user,
        address indexed asset,
        uint256 amount,
        address indexed to
    );

    event AddressesUpdated(
        address lendingPool,
        address wethGateway,
        address uniswapRouter,
        address priceFeed
    );

    event SharedDepositUpdated(
        address sharedDeposit,
        address vEth2Token
    );

    /**
     * @param _addressesProvider AAVE LendingPoolAddressesProvider
     * @param _wethGateway AAVE WETH Gateway
     * @param _uniswapRouter UniswapV2 Router
     * @param _weth WETH token address
     * @param _aWeth aWETH token address
     * @param _stableAsset Stablecoin address (e.g. DAI)
     * @param _stableDebtToken Stable debt token address for stableAsset
     * @param _variableDebtToken Variable debt token address for stableAsset
     * @param _sharedDeposit SharedDeposit contract address (or address(0))
     * @param _vEth2Token vETH2 token address (or address(0))
     * @param _priceFeed Chainlink ETH/USD aggregator address
     */
    constructor(
        address _addressesProvider,
        address _wethGateway,
        address _uniswapRouter,
        address _weth,
        address _aWeth,
        address _stableAsset,
        address _stableDebtToken,
        address _variableDebtToken,
        address _sharedDeposit,
        address _vEth2Token,
        address _priceFeed
    ) public {
        if (_addressesProvider != address(0)) {
            addressesProvider = ILendingPoolAddressesProvider(_addressesProvider);
            address pool = addressesProvider.getLendingPool();
            if (pool != address(0)) {
                lendingPool = ILendingPool(pool);
            }
        }
        wethGateway = IWETHGateway(_wethGateway);
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        weth = _weth;
        aWeth = _aWeth;
        stableAsset = _stableAsset;
        stableDebtToken = _stableDebtToken;
        variableDebtToken = _variableDebtToken;
        sharedDeposit = _sharedDeposit;
        vEth2Token = _vEth2Token;
        if (_priceFeed != address(0)) {
            priceFeed = AggregatorV3Interface(_priceFeed);
        }
    }

    /* ==================================================================== */
    /*                         LONG ETH STRATEGY                            */
    /* ==================================================================== */

    /**
     * @notice Leveraged Long ETH position.
     * Deposits supplied ETH into Aave, borrows stablecoins, swaps to ETH, optionally loops,
     * credit-delegates remaining borrow power to msg.sender, and optionally stakes final ETH into SharedDeposit.
     * @param minHealthFactor Minimum health factor (scaled by 100, e.g. 150 = 1.5 HF). 0 defaults to 150.
     * @param maxLoops Max iterations for leverage looping.
     * @param interestRateMode 1 for stable, 2 for variable debt.
     * @param stakeInSharedDeposit Whether to stake final accumulated ETH in SharedDeposit and return vETH2.
     * @param minAmountOut Minimum ETH expected from Uniswap swaps for slippage control.
     * @return totalEthReturnedOrStaked Amount of ETH returned or staked in SharedDeposit.
     * @return vEthMinted Amount of vETH2 tokens minted and transferred to msg.sender.
     */
    function longEth(
        uint256 minHealthFactor,
        uint256 maxLoops,
        uint256 interestRateMode,
        bool stakeInSharedDeposit,
        uint256 minAmountOut
    ) external payable whenNotPaused nonReentrant returns (uint256 totalEthReturnedOrStaked, uint256 vEthMinted) {
        require(msg.value > 0, "LeverageEthViaAAVE: No ETH supplied");
        if (minHealthFactor == 0) {
            minHealthFactor = 150;
        }
        require(minHealthFactor > 100, "LeverageEthViaAAVE: minHealthFactor must be > 100 (1.0)");
        if (maxLoops == 0) {
            maxLoops = 1;
        }
        if (interestRateMode != 1 && interestRateMode != 2) {
            interestRateMode = 2; // Default to variable rate mode
        }

        uint256 initialEth = msg.value;
        // Step 1: Deposit ETH collateral to Aave
        _depositETHCollateral(initialEth);

        uint256 totalDebtBorrowed = 0;
        uint256 totalEthObtained = 0;
        uint256 loops = 0;

        // Step 2: Leverage loop
        while (loops < maxLoops) {
            uint256 currentHF = getHealthFactor(address(this));
            if (currentHF <= minHealthFactor.mul(1e16)) { // healthFactor is 1e18
                break;
            }

            uint256 borrowed = _borrowStableAndSwapToETH(interestRateMode, minAmountOut);
            if (borrowed == 0) {
                break;
            }
            totalDebtBorrowed = totalDebtBorrowed.add(borrowed);
            loops = loops.add(1);

            // If we have more loops remaining and contract has ETH, we can deposit to compound leverage
            if (loops < maxLoops && address(this).balance > 0) {
                _depositETHCollateral(address(this).balance);
            }
        }

        totalEthObtained = address(this).balance;

        // Step 3: Credit delegate remaining borrowing power to msg.sender
        address debtTokenToDelegate = (interestRateMode == 1) ? stableDebtToken : variableDebtToken;
        if (debtTokenToDelegate != address(0)) {
            uint256 remainingAvailETH = getAvailableBorrowsETH(address(this));
            if (remainingAvailETH > 0) {
                int256 ethPrice = getLatestPrice();
                if (ethPrice > 0) {
                    uint256 remainingStable = remainingAvailETH.mul(uint256(ethPrice)).div(1e8);
                    _approveDebtDelegation(msg.sender, debtTokenToDelegate, remainingStable);
                }
            }
        }

        // Step 4: Handle ETH disposition (SharedDeposit or Direct Transfer)
        if (totalEthObtained > 0) {
            if (stakeInSharedDeposit && sharedDeposit != address(0)) {
                (totalEthReturnedOrStaked, vEthMinted) = _stakeETHToSharedDeposit(msg.sender, totalEthObtained);
            } else {
                totalEthReturnedOrStaked = totalEthObtained;
                msg.sender.sendValue(totalEthObtained);
            }
        }

        emit LongPositionOpened(msg.sender, initialEth, totalDebtBorrowed, totalEthObtained, vEthMinted);
        return (totalEthReturnedOrStaked, vEthMinted);
    }

    /**
     * @notice Convenience function for maximum leverage long ETH up to minHealthFactor.
     */
    function maxLongEth(
        uint256 minHealthFactor,
        uint256 interestRateMode,
        bool stakeInSharedDeposit
    ) external payable returns (uint256, uint256) {
        return this.longEth{value: msg.value}(minHealthFactor, 10, interestRateMode, stakeInSharedDeposit, 0);
    }

    /* ==================================================================== */
    /*                        SHORT ETH STRATEGY                            */
    /* ==================================================================== */

    /**
     * @notice Short ETH position using stablecoins as collateral.
     * Deposits stablecoin collateral into Aave, borrows ETH, and either:
     * (a) Swaps borrowed ETH to stablecoins on Uniswap and returns to msg.sender, OR
     * (b) Stakes borrowed ETH into SharedDeposit to earn staking yield (vETH2) while shorting ETH.
     * @param collateralAsset Address of collateral stablecoin (e.g. DAI/USDC)
     * @param collateralAmount Amount of stablecoin collateral to deposit
     * @param borrowEthAmount Amount of ETH to borrow against collateral
     * @param interestRateMode 1 for stable, 2 for variable debt
     * @param stakeInSharedDeposit Whether to stake borrowed ETH in SharedDeposit
     * @param minAmountOut Minimum output amount from swap for slippage control
     */
    function shortEth(
        address collateralAsset,
        uint256 collateralAmount,
        uint256 borrowEthAmount,
        uint256 interestRateMode,
        bool stakeInSharedDeposit,
        uint256 minAmountOut
    ) external whenNotPaused nonReentrant returns (uint256 returnAmount) {
        require(collateralAmount > 0, "LeverageEthViaAAVE: Zero collateral");
        require(borrowEthAmount > 0, "LeverageEthViaAAVE: Zero borrow amount");
        if (interestRateMode != 1 && interestRateMode != 2) {
            interestRateMode = 2;
        }

        // Step 1: Transfer and deposit stable collateral to Aave
        IERC20(collateralAsset).safeTransferFrom(msg.sender, address(this), collateralAmount);
        _depositCollateral(collateralAsset, address(this), collateralAmount);

        // Step 2: Borrow ETH from Aave
        _borrowETH(borrowEthAmount, interestRateMode);
        require(address(this).balance >= borrowEthAmount, "LeverageEthViaAAVE: ETH borrow failed");

        // Step 3: Credit delegation of remaining funds to msg.sender
        address debtTokenToDelegate = (interestRateMode == 1) ? wethStableDebtToken : wethVariableDebtToken;
        if (debtTokenToDelegate != address(0)) {
            uint256 remainingAvail = getAvailableBorrowsETH(address(this));
            if (remainingAvail > 0) {
                _approveDebtDelegation(msg.sender, debtTokenToDelegate, remainingAvail);
            }
        }

        // Step 4: Handle borrowed ETH
        if (stakeInSharedDeposit && sharedDeposit != address(0)) {
            (, returnAmount) = _stakeETHToSharedDeposit(msg.sender, borrowEthAmount);
        } else {
            // Swap borrowed ETH for collateral asset / stablecoins
            returnAmount = _swapETHForERC20(collateralAsset, borrowEthAmount, minAmountOut);
            IERC20(collateralAsset).safeTransfer(msg.sender, returnAmount);
        }

        emit ShortPositionOpened(msg.sender, collateralAsset, collateralAmount, borrowEthAmount, returnAmount);
        return returnAmount;
    }

    /* ==================================================================== */
    /*                   CREDIT DELEGATION CAPABILITIES                     */
    /* ==================================================================== */

    /**
     * @notice Delegates credit / borrowing allowance from this contract to a user.
     * @param delegatee User who is granted borrow allowance
     * @param debtToken Address of StableDebtToken or VariableDebtToken
     * @param amount Maximum amount allowed to borrow
     */
    function delegateCreditToUser(
        address delegatee,
        address debtToken,
        uint256 amount
    ) external onlyOwner {
        _approveDebtDelegation(delegatee, debtToken, amount);
    }

    /**
     * @notice Allows executing a borrow on behalf of a user who previously delegated credit to this contract.
     * Borrows asset using user's collateral/allowance, optionally swaps to ETH, and optionally stakes to SharedDeposit.
     * @param asset Asset to borrow (e.g. DAI or WETH)
     * @param amount Amount to borrow
     * @param rateMode 1 for stable, 2 for variable
     * @param user Account that delegated credit to this contract
     * @param swapToEth Whether to swap borrowed tokens to ETH
     * @param stakeInSharedDeposit Whether to stake ETH into SharedDeposit and send vETH2 to user
     * @param minAmountOut Minimum output from swap
     */
    function borrowOnBehalfOfUser(
        address asset,
        uint256 amount,
        uint256 rateMode,
        address user,
        bool swapToEth,
        bool stakeInSharedDeposit,
        uint256 minAmountOut
    ) external whenNotPaused nonReentrant returns (uint256 resultAmount) {
        require(user != address(0), "LeverageEthViaAAVE: Zero user address");
        require(amount > 0, "LeverageEthViaAAVE: Zero amount");

        // Borrow on behalf of user using credit delegation
        lendingPool.borrow(asset, amount, rateMode, 0, user);

        if (asset == weth || asset == address(0)) {
            // We have WETH or ETH
            if (asset == weth) {
                IWETH(weth).withdraw(IERC20(weth).balanceOf(address(this)));
            }
            uint256 ethBal = address(this).balance;
            if (stakeInSharedDeposit && sharedDeposit != address(0)) {
                (, resultAmount) = _stakeETHToSharedDeposit(user, ethBal);
            } else {
                resultAmount = ethBal;
                payable(user).sendValue(ethBal);
            }
        } else {
            // Stable asset borrowed
            if (swapToEth) {
                uint256 ethObtained = _swapERC20ForETH(asset, amount, minAmountOut);
                if (stakeInSharedDeposit && sharedDeposit != address(0)) {
                    (, resultAmount) = _stakeETHToSharedDeposit(user, ethObtained);
                } else {
                    resultAmount = ethObtained;
                    payable(user).sendValue(ethObtained);
                }
            } else {
                // Transfer borrowed stable asset directly to user
                resultAmount = IERC20(asset).balanceOf(address(this));
                IERC20(asset).safeTransfer(user, resultAmount);
            }
        }
        return resultAmount;
    }

    /**
     * @notice Helper to approve debt delegation on any debt token.
     */
    function approveDebtDelegation(
        address delegatee,
        address debtToken,
        uint256 amount
    ) external onlyOwner {
        _approveDebtDelegation(delegatee, debtToken, amount);
    }

    function _approveDebtDelegation(
        address delegatee,
        address debtToken,
        uint256 amount
    ) internal {
        require(delegatee != address(0), "LeverageEthViaAAVE: Zero delegatee address");
        require(debtToken != address(0), "LeverageEthViaAAVE: Zero debtToken address");
        ICreditDelegationToken(debtToken).approveDelegation(delegatee, amount);
        emit CreditDelegated(address(this), delegatee, debtToken, amount);
    }

    function getBorrowAllowance(
        address fromUser,
        address toUser,
        address debtToken
    ) external view returns (uint256) {
        return ICreditDelegationToken(debtToken).borrowAllowance(fromUser, toUser);
    }

    /* ==================================================================== */
    /*               REPAYMENT & COLLATERAL WITHDRAWAL                      */
    /* ==================================================================== */

    /**
     * @notice Repays debt on Aave for this contract or on behalf of another user.
     * @param asset Debt asset address
     * @param amount Amount to repay (type(uint256).max for full repay)
     * @param rateMode 1 for stable, 2 for variable
     * @param onBehalfOf Address of borrower whose debt is being repaid
     */
    function repayDebt(
        address asset,
        uint256 amount,
        uint256 rateMode,
        address onBehalfOf
    ) external nonReentrant returns (uint256) {
        if (IERC20(asset).balanceOf(address(this)) < amount) {
            uint256 needed = amount.sub(IERC20(asset).balanceOf(address(this)));
            IERC20(asset).safeTransferFrom(msg.sender, address(this), needed);
        }
        IERC20(asset).safeApprove(address(lendingPool), 0);
        IERC20(asset).safeApprove(address(lendingPool), amount);
        uint256 repaid = lendingPool.repay(asset, amount, rateMode, onBehalfOf);
        emit DebtRepaid(msg.sender, asset, repaid, rateMode, onBehalfOf);
        return repaid;
    }

    /**
     * @notice Repays ETH debt via WETHGateway.
     * @param rateMode 1 for stable, 2 for variable
     * @param onBehalfOf Address of borrower
     */
    function repayETH(
        uint256 rateMode,
        address onBehalfOf
    ) external payable nonReentrant {
        require(msg.value > 0, "LeverageEthViaAAVE: Zero ETH value");
        wethGateway.repayETH{value: msg.value}(address(lendingPool), msg.value, rateMode, onBehalfOf);
        emit DebtRepaid(msg.sender, weth, msg.value, rateMode, onBehalfOf);
    }

    /**
     * @notice Withdraws ERC20 collateral from Aave.
     * @param asset Address of collateral asset
     * @param amount Amount to withdraw
     * @param to Destination address
     */
    function withdrawCollateral(
        address asset,
        uint256 amount,
        address to
    ) external onlyOwner nonReentrant returns (uint256) {
        require(to != address(0), "LeverageEthViaAAVE: Zero to address");
        uint256 withdrawn = lendingPool.withdraw(asset, amount, to);
        emit CollateralWithdrawn(msg.sender, asset, withdrawn, to);
        return withdrawn;
    }

    /**
     * @notice Withdraws ETH collateral via WETHGateway or LendingPool.
     * @param amount Amount of ETH collateral to withdraw
     * @param to Destination address
     */
    function withdrawETHCollateral(
        uint256 amount,
        address payable to
    ) external onlyOwner nonReentrant {
        require(to != address(0), "LeverageEthViaAAVE: Zero to address");
        if (address(wethGateway) != address(0)) {
            IERC20(aWeth).safeApprove(address(wethGateway), 0);
            IERC20(aWeth).safeApprove(address(wethGateway), amount);
            wethGateway.withdrawETH(address(lendingPool), amount, to);
        } else {
            lendingPool.withdraw(weth, amount, address(this));
            IWETH(weth).withdraw(amount);
            to.sendValue(amount);
        }
        emit CollateralWithdrawn(msg.sender, weth, amount, to);
    }

    /**
     * @notice Closes a long position by repaying stable debt and withdrawing ETH collateral.
     * @param repayAmount Amount of stable debt to repay
     * @param withdrawCollateralAmount Amount of ETH collateral to withdraw
     * @param to Destination address
     */
    function closeLongPosition(
        uint256 repayAmount,
        uint256 withdrawCollateralAmount,
        address payable to
    ) external onlyOwner nonReentrant {
        require(to != address(0), "LeverageEthViaAAVE: Zero to address");
        if (repayAmount > 0) {
            IERC20(stableAsset).safeTransferFrom(msg.sender, address(this), repayAmount);
            IERC20(stableAsset).safeApprove(address(lendingPool), 0);
            IERC20(stableAsset).safeApprove(address(lendingPool), repayAmount);
            lendingPool.repay(stableAsset, repayAmount, 2, address(this));
        }
        if (withdrawCollateralAmount > 0) {
            if (address(wethGateway) != address(0)) {
                IERC20(aWeth).safeApprove(address(wethGateway), 0);
                IERC20(aWeth).safeApprove(address(wethGateway), withdrawCollateralAmount);
                wethGateway.withdrawETH(address(lendingPool), withdrawCollateralAmount, to);
            } else {
                lendingPool.withdraw(weth, withdrawCollateralAmount, address(this));
                IWETH(weth).withdraw(withdrawCollateralAmount);
                to.sendValue(withdrawCollateralAmount);
            }
        }
    }

    /**
     * @notice Closes a short position by repaying ETH debt and withdrawing stablecoin collateral.
     * @param collateralAsset Collateral asset to withdraw
     * @param withdrawCollateralAmount Amount of collateral to withdraw
     * @param to Destination address
     */
    function closeShortPosition(
        address collateralAsset,
        uint256 withdrawCollateralAmount,
        address to
    ) external payable onlyOwner nonReentrant {
        require(to != address(0), "LeverageEthViaAAVE: Zero to address");
        if (msg.value > 0) {
            wethGateway.repayETH{value: msg.value}(address(lendingPool), msg.value, 2, address(this));
        }
        if (withdrawCollateralAmount > 0) {
            lendingPool.withdraw(collateralAsset, withdrawCollateralAmount, to);
        }
    }

    /* ==================================================================== */
    /*                     SHAREDSTAKE INTEGRATION                          */
    /* ==================================================================== */

    /**
     * @notice Stakes ETH into SharedStake SharedDeposit contract and sends minted vETH2 to recipient.
     * @param recipient Address receiving minted vETH2
     * @param amount ETH amount to stake
     * @return ethStaked Amount of ETH staked
     * @return vEthMinted Amount of vETH2 tokens transferred to recipient
     */
    function stakeETHToSharedDeposit(
        address recipient,
        uint256 amount
    ) external payable onlyOwner nonReentrant returns (uint256 ethStaked, uint256 vEthMinted) {
        require(recipient != address(0), "LeverageEthViaAAVE: Zero recipient");
        uint256 stakeAmount = (msg.value > 0) ? msg.value : amount;
        return _stakeETHToSharedDeposit(recipient, stakeAmount);
    }

    function _stakeETHToSharedDeposit(
        address recipient,
        uint256 ethAmount
    ) internal returns (uint256 ethStaked, uint256 vEthMinted) {
        require(sharedDeposit != address(0), "LeverageEthViaAAVE: SharedDeposit not set");
        require(ethAmount > 0 && address(this).balance >= ethAmount, "LeverageEthViaAAVE: Insufficient ETH");

        address vToken = vEth2Token;
        if (vToken == address(0)) {
            // Try query from SharedDeposit contract
            vToken = ISharedDeposit(sharedDeposit).BETHTokenAddress();
        }

        uint256 balanceBefore = 0;
        if (vToken != address(0)) {
            balanceBefore = IERC20(vToken).balanceOf(address(this));
        }

        ISharedDeposit(sharedDeposit).deposit{value: ethAmount}();

        if (vToken != address(0)) {
            uint256 balanceAfter = IERC20(vToken).balanceOf(address(this));
            vEthMinted = balanceAfter.sub(balanceBefore);
            if (vEthMinted > 0) {
                IERC20(vToken).safeTransfer(recipient, vEthMinted);
            }
        }

        ethStaked = ethAmount;
        emit StakedToSharedDeposit(recipient, ethStaked, vEthMinted);
        return (ethStaked, vEthMinted);
    }

    /* ==================================================================== */
    /*                         INTERNAL HELPERS                             */
    /* ==================================================================== */

    function _depositETHCollateral(uint256 amount) internal {
        require(address(this).balance >= amount, "LeverageEthViaAAVE: Insufficient ETH balance");
        if (address(wethGateway) != address(0)) {
            wethGateway.depositETH{value: amount}(address(lendingPool), address(this), 0);
        } else {
            IWETH(weth).deposit{value: amount}();
            IERC20(weth).safeApprove(address(lendingPool), 0);
            IERC20(weth).safeApprove(address(lendingPool), amount);
            lendingPool.deposit(weth, amount, address(this), 0);
        }
    }

    function _depositCollateral(address asset, address onBehalfOf, uint256 amount) internal {
        IERC20(asset).safeApprove(address(lendingPool), 0);
        IERC20(asset).safeApprove(address(lendingPool), amount);
        lendingPool.deposit(asset, amount, onBehalfOf, 0);
    }

    function _borrowETH(uint256 amount, uint256 rateMode) internal {
        if (address(wethGateway) != address(0)) {
            wethGateway.borrowETH(address(lendingPool), amount, rateMode, 0);
        } else {
            lendingPool.borrow(weth, amount, rateMode, 0, address(this));
            IWETH(weth).withdraw(amount);
        }
    }

    function _borrowStableAndSwapToETH(
        uint256 rateMode,
        uint256 minEthOut
    ) internal returns (uint256 borrowedStable) {
        uint256 availableBorrowsETH = getAvailableBorrowsETH(address(this));
        if (availableBorrowsETH == 0) {
            return 0;
        }

        int256 ethPrice = getLatestPrice();
        require(ethPrice > 0, "LeverageEthViaAAVE: Invalid oracle price");

        // Borrow 50% of available borrow power in stablecoins
        uint256 toBorrowETH = availableBorrowsETH.div(2);
        if (toBorrowETH == 0) {
            return 0;
        }

        borrowedStable = toBorrowETH.mul(uint256(ethPrice)).div(1e8);
        if (borrowedStable == 0) {
            return 0;
        }

        lendingPool.borrow(stableAsset, borrowedStable, rateMode, 0, address(this));
        uint256 stableBalance = IERC20(stableAsset).balanceOf(address(this));
        if (stableBalance > 0) {
            _swapERC20ForETH(stableAsset, stableBalance, minEthOut);
        }
        return borrowedStable;
    }

    function _swapERC20ForETH(
        address token,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256) {
        require(token != address(0), "LeverageEthViaAAVE: Zero token");
        require(amountIn > 0, "LeverageEthViaAAVE: Zero amountIn");

        address routerWeth = uniswapRouter.WETH();
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = (routerWeth != address(0)) ? routerWeth : weth;

        IERC20(token).safeApprove(address(uniswapRouter), 0);
        IERC20(token).safeApprove(address(uniswapRouter), amountIn);

        uint256[] memory amounts = uniswapRouter.swapExactTokensForETH(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp.add(300)
        );
        require(amounts.length > 1 && amounts[1] > 0, "LeverageEthViaAAVE: Uniswap swap returned zero");
        return amounts[1];
    }

    function _swapETHForERC20(
        address token,
        uint256 ethAmount,
        uint256 amountOutMin
    ) internal returns (uint256) {
        require(token != address(0), "LeverageEthViaAAVE: Zero token");
        require(ethAmount > 0, "LeverageEthViaAAVE: Zero ETH amount");

        address routerWeth = uniswapRouter.WETH();
        address[] memory path = new address[](2);
        path[0] = (routerWeth != address(0)) ? routerWeth : weth;
        path[1] = token;

        uint256[] memory amounts = uniswapRouter.swapExactETHForTokens{value: ethAmount}(
            amountOutMin,
            path,
            address(this),
            block.timestamp.add(300)
        );
        require(amounts.length > 1 && amounts[1] > 0, "LeverageEthViaAAVE: Uniswap swap returned zero");
        return amounts[1];
    }

    /* ==================================================================== */
    /*                         ORACLE & ACCOUNT DATA                        */
    /* ==================================================================== */

    function getLatestPrice() public view returns (int256) {
        if (address(priceFeed) == address(0)) {
            return 2000 * 1e8; // Fallback price: $2000 with 8 decimals
        }
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return price;
    }

    function getUserAccountData(address user) public view returns (
        uint256 totalCollateralETH,
        uint256 totalDebtETH,
        uint256 availableBorrowsETH,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) {
        return lendingPool.getUserAccountData(user);
    }

    function getHealthFactor(address user) public view returns (uint256) {
        (, , , , , uint256 healthFactor) = lendingPool.getUserAccountData(user);
        return healthFactor;
    }

    function getAvailableBorrowsETH(address user) public view returns (uint256) {
        (, , uint256 availableBorrowsETH, , , ) = lendingPool.getUserAccountData(user);
        return availableBorrowsETH;
    }

    function getTotalDebtETH(address user) public view returns (uint256) {
        (, uint256 totalDebtETH, , , , ) = lendingPool.getUserAccountData(user);
        return totalDebtETH;
    }

    /* ==================================================================== */
    /*                        ADMIN & EMERGENCY RESCUE                      */
    /* ==================================================================== */

    function setAddresses(
        address _addressesProvider,
        address _wethGateway,
        address _uniswapRouter,
        address _priceFeed
    ) external onlyOwner {
        if (_addressesProvider != address(0)) {
            addressesProvider = ILendingPoolAddressesProvider(_addressesProvider);
            address pool = addressesProvider.getLendingPool();
            if (pool != address(0)) {
                lendingPool = ILendingPool(pool);
            }
        }
        if (_wethGateway != address(0)) {
            wethGateway = IWETHGateway(_wethGateway);
        }
        if (_uniswapRouter != address(0)) {
            uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        }
        if (_priceFeed != address(0)) {
            priceFeed = AggregatorV3Interface(_priceFeed);
        }
        emit AddressesUpdated(address(lendingPool), address(wethGateway), address(uniswapRouter), address(priceFeed));
    }

    function setTokens(
        address _weth,
        address _aWeth,
        address _stableAsset,
        address _stableDebtToken,
        address _variableDebtToken,
        address _wethVariableDebtToken,
        address _wethStableDebtToken
    ) external onlyOwner {
        weth = _weth;
        aWeth = _aWeth;
        stableAsset = _stableAsset;
        stableDebtToken = _stableDebtToken;
        variableDebtToken = _variableDebtToken;
        wethVariableDebtToken = _wethVariableDebtToken;
        wethStableDebtToken = _wethStableDebtToken;
    }

    function setSharedDeposit(address _sharedDeposit, address _vEth2Token) external onlyOwner {
        sharedDeposit = _sharedDeposit;
        vEth2Token = _vEth2Token;
        emit SharedDepositUpdated(_sharedDeposit, _vEth2Token);
    }

    function setPriceFeed(address _priceFeed) external onlyOwner {
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    function rescueTokens(address token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "LeverageEthViaAAVE: Zero to address");
        IERC20(token).safeTransfer(to, amount);
    }

    function rescueETH(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "LeverageEthViaAAVE: Zero to address");
        to.sendValue(amount);
    }

    receive() external payable {}
    fallback() external payable {}
}
