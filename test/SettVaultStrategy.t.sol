// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../contracts/SettVaultSgtEth.sol";
import "../contracts/StrategySgtEthLp.sol";

contract DSTest {
    event log(string);
    event logs(bytes);
    event log_address(address);
    event log_uint(uint256);
    event log_int(int256);
    event log_named_address(string key, address val);
    event log_named_uint(string key, uint256 val);
    event log_named_int(string key, int256 val);

    bool public IS_TEST = true;

    function assertTrue(bool condition) internal {
        if (!condition) {
            emit log("Error: Assertion Failed");
            fail();
        }
    }

    function assertEq(uint256 a, uint256 b) internal {
        if (a != b) {
            emit log("Error: a == b not satisfied [uint256]");
            emit log_named_uint("      Left", a);
            emit log_named_uint("     Right", b);
            fail();
        }
    }

    function assertEq(address a, address b) internal {
        if (a != b) {
            emit log("Error: a == b not satisfied [address]");
            emit log_named_address("      Left", a);
            emit log_named_address("     Right", b);
            fail();
        }
    }

    function fail() internal pure {
        revert("Test Failed");
    }
}

interface Vm {
    function warp(uint256) external;
    function roll(uint256) external;
    function expectRevert(bytes calldata) external;
}

contract MockERC20 is IERC20 {
    using SafeMath for uint256;
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    constructor(string memory _name, string memory _symbol) public {
        name = _name;
        symbol = _symbol;
    }

    function mint(address account, uint256 amount) public {
        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function totalSupply() public view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }
    function allowance(address owner, address spender) public view override returns (uint256) { return _allowances[owner][spender]; }
    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(amount);
        _allowances[sender][msg.sender] = _allowances[sender][msg.sender].sub(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }
}

contract MockUniswapV2Router is IUniswapV2Router02 {
    using SafeMath for uint256;
    address public lpToken;
    address public weth;

    constructor(address _lpToken, address _weth) public {
        lpToken = _lpToken;
        weth = _weth;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256,
        address[] calldata path,
        address to,
        uint256
    ) external override returns (uint256[] memory amounts) {
        MockERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        MockERC20(weth).mint(to, amountIn);
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountIn;
        return amounts;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256,
        uint256,
        address to,
        uint256
    ) external override returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        MockERC20(tokenA).transferFrom(msg.sender, address(this), amountADesired);
        MockERC20(tokenB).transferFrom(msg.sender, address(this), amountBDesired);
        liquidity = amountADesired.add(amountBDesired);
        MockERC20(lpToken).mint(to, liquidity);
        return (amountADesired, amountBDesired, liquidity);
    }
}

contract SettVaultStrategyTest is DSTest {
    using SafeMath for uint256;

    Vm public constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    MockERC20 public lpToken;
    MockERC20 public sgt;
    MockERC20 public weth;
    MockERC20 public strayToken;
    MockUniswapV2Router public router;

    SettVaultSgtEth public vault;
    StrategySgtEthLp public strategy;

    address public governance = address(0x1111);
    address public controller = address(0x2222);
    address public strategist = address(0x3333);
    address public treasury = address(0x4444);
    address public alice = address(0x5555);
    address public bob = address(0x6666);

    function setUp() public {
        lpToken = new MockERC20("Uniswap V2 SGT/ETH LP", "UNI-V2");
        sgt = new MockERC20("SharedStake Governance Token", "SGT");
        weth = new MockERC20("Wrapped Ether", "WETH");
        strayToken = new MockERC20("Stray Token", "STRAY");

        router = new MockUniswapV2Router(address(lpToken), address(weth));

        vault = new SettVaultSgtEth(
            address(lpToken),
            address(this),
            controller
        );

        strategy = new StrategySgtEthLp(
            address(lpToken),
            address(sgt),
            address(weth),
            address(router),
            address(vault),
            address(this),
            strategist,
            treasury
        );

        vault.setStrategy(address(strategy));
    }

    function testInitialDepositAndShareRatio() public {
        lpToken.mint(address(this), 100 ether);
        lpToken.approve(address(vault), 100 ether);
        vault.deposit(100 ether);

        assertEq(vault.totalSupply(), 100 ether);
        assertEq(vault.balanceOf(address(this)), 100 ether);
        assertEq(vault.getPricePerFullShare(), 1 ether);
    }

    function testEarnAndDeploymentToStrategy() public {
        lpToken.mint(address(this), 100 ether);
        lpToken.approve(address(vault), 100 ether);
        vault.deposit(100 ether);

        uint256 availBefore = vault.available();
        assertTrue(availBefore > 0);

        vault.earn();

        assertEq(strategy.balanceOf(), availBefore);
        assertEq(vault.balance(), 100 ether);
    }

    function testHarvestAutoCompoundingYield() public {
        lpToken.mint(address(this), 100 ether);
        lpToken.approve(address(vault), 100 ether);
        vault.deposit(100 ether);
        vault.earn();

        assertEq(vault.getPricePerFullShare(), 1 ether);

        sgt.mint(address(strategy), 10 ether);

        strategy.setStrategist(address(this));
        strategy.harvest();

        assertEq(sgt.balanceOf(treasury), 0.45 ether);
        assertEq(sgt.balanceOf(address(this)), 0.05 ether);

        uint256 poolAfter = vault.balance();
        assertTrue(poolAfter > 100 ether);
        assertTrue(vault.getPricePerFullShare() > 1 ether);

        emit log_named_uint("Vault Pool After Compound", poolAfter);
        emit log_named_uint("Price Per Full Share", vault.getPricePerFullShare());
    }

    function testTimeLockBoostAndVotingCheckpoints() public {
        lpToken.mint(address(this), 100 ether);
        lpToken.approve(address(vault), 100 ether);
        vault.deposit(100 ether);

        vault.lockShares(100 ether, 180 days);

        (uint256 lockAmt, , uint256 boost) = vault.locks(address(this));
        assertEq(lockAmt, 100 ether);
        assertTrue(boost > 10000);
        assertTrue(boost < 25000);

        uint256 votes = vault.getVotes(address(this));
        assertTrue(votes > 100 ether);
    }

    function testUnlockAndWithdraw() public {
        lpToken.mint(address(this), 100 ether);
        lpToken.approve(address(vault), 100 ether);
        vault.deposit(100 ether);

        vault.lockShares(100 ether, 30 days);

        vm.warp(block.timestamp + 31 days);

        vault.unlock();
        vault.withdraw(100 ether);

        assertEq(lpToken.balanceOf(address(this)), 100 ether);
        assertEq(vault.balanceOf(address(this)), 0);
    }

    function testWithdrawFromStrategy() public {
        lpToken.mint(address(this), 100 ether);
        lpToken.approve(address(vault), 100 ether);
        vault.deposit(100 ether);

        vault.earn();
        assertTrue(strategy.balanceOf() > 90 ether);

        vault.withdraw(50 ether);
        assertEq(lpToken.balanceOf(address(this)), 50 ether);

        vault.withdrawAll();
        assertEq(lpToken.balanceOf(address(this)), 100 ether);
        assertEq(vault.totalSupply(), 0);
    }

    function testInCaseTokensGetStuck() public {
        strayToken.mint(address(strategy), 500 ether);
        strategy.inCaseTokensGetStuck(address(strayToken));
        assertEq(strayToken.balanceOf(address(this)), 500 ether);
    }

    function testSetFeesAndAdminControls() public {
        strategy.setFees(300, 100);
        assertEq(strategy.performanceFee(), 300);
        assertEq(strategy.strategistFee(), 100);

        vault.setMin(9000);
        assertEq(vault.min(), 9000);
    }
}
