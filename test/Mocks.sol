// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../contracts/LeverageEthViaAAVE.sol";

contract MockERC20 is IERC20 {
    using SafeMath for uint256;

    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public override totalSupply;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    constructor(string memory _name, string memory _symbol) public {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) public virtual {
        totalSupply = totalSupply.add(amount);
        balanceOf[to] = balanceOf[to].add(amount);
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) public virtual {
        balanceOf[from] = balanceOf[from].sub(amount);
        totalSupply = totalSupply.sub(amount);
        emit Transfer(from, address(0), amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        balanceOf[msg.sender] = balanceOf[msg.sender].sub(amount);
        balanceOf[to] = balanceOf[to].add(amount);
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (allowance[from][msg.sender] != uint256(-1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(amount);
        }
        balanceOf[from] = balanceOf[from].sub(amount);
        balanceOf[to] = balanceOf[to].add(amount);
        emit Transfer(from, to, amount);
        return true;
    }
}

contract MockWETH is MockERC20, IWETH {
    constructor() public MockERC20("Wrapped Ether", "WETH") {}

    function deposit() public payable override {
        mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) public override {
        burn(msg.sender, amount);
        msg.sender.transfer(amount);
    }

    receive() external payable {
        deposit();
    }
}

contract MockDebtToken is MockERC20, ICreditDelegationToken {
    mapping(address => mapping(address => uint256)) public allowancesDelegation;

    constructor(string memory _name, string memory _symbol) public MockERC20(_name, _symbol) {}

    function approveDelegation(address delegatee, uint256 amount) external override {
        allowancesDelegation[msg.sender][delegatee] = amount;
    }

    function borrowAllowance(address fromUser, address toUser) external view override returns (uint256) {
        return allowancesDelegation[fromUser][toUser];
    }
}

contract MockChainlinkAggregator is AggregatorV3Interface {
    int256 public price;
    uint8 public override decimals = 8;

    constructor(int256 _initialPrice) public {
        price = _initialPrice;
    }

    function setPrice(int256 _price) external {
        price = _price;
    }

    function latestRoundData() external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (1, price, block.timestamp, block.timestamp, 1);
    }
}

contract MockLendingPoolAddressesProvider is ILendingPoolAddressesProvider {
    address public pool;
    address public oracle;

    function setLendingPool(address _pool) external {
        pool = _pool;
    }

    function setPriceOracle(address _oracle) external {
        oracle = _oracle;
    }

    function getLendingPool() external view override returns (address) {
        return pool;
    }

    function getPriceOracle() external view override returns (address) {
        return oracle;
    }
}

contract MockAaveLendingPool is ILendingPool {
    using SafeMath for uint256;

    MockERC20 public aWeth;
    MockERC20 public dai;
    MockDebtToken public daiDebtToken;

    uint256 public totalCollateralETH = 10 ether;
    uint256 public totalDebtETH = 0;
    uint256 public availableBorrowsETH = 5 ether;
    uint256 public currentLiquidationThreshold = 8000;
    uint256 public ltv = 7500;
    uint256 public healthFactor = 3 * 1e18; // 3.0 HF

    constructor(address _aWeth, address _dai, address _daiDebtToken) public {
        aWeth = MockERC20(_aWeth);
        dai = MockERC20(_dai);
        daiDebtToken = MockDebtToken(_daiDebtToken);
    }

    function setUserAccountData(
        uint256 _collateral,
        uint256 _debt,
        uint256 _avail,
        uint256 _liq,
        uint256 _ltv,
        uint256 _hf
    ) external {
        totalCollateralETH = _collateral;
        totalDebtETH = _debt;
        availableBorrowsETH = _avail;
        currentLiquidationThreshold = _liq;
        ltv = _ltv;
        healthFactor = _hf;
    }

    function deposit(address asset, uint256 amount, address onBehalfOf, uint16) external override {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        if (asset == address(aWeth) || asset == 0xd0A1E359811322d97991E03f863a0C30C2cF029C) {
            aWeth.mint(onBehalfOf, amount);
        }
        totalCollateralETH = totalCollateralETH.add(amount);
    }

    function withdraw(address asset, uint256 amount, address to) external override returns (uint256) {
        if (asset == address(aWeth)) {
            aWeth.burn(msg.sender, amount);
        }
        IERC20(asset).transfer(to, amount);
        if (totalCollateralETH >= amount) {
            totalCollateralETH = totalCollateralETH.sub(amount);
        }
        return amount;
    }

    function borrow(address asset, uint256 amount, uint256, uint16, address /*onBehalfOf*/) external override {
        MockERC20(asset).mint(msg.sender, amount);
        totalDebtETH = totalDebtETH.add(amount.div(2000)); // approximate DAI to ETH debt
        if (availableBorrowsETH > amount.div(2000)) {
            availableBorrowsETH = availableBorrowsETH.sub(amount.div(2000));
        } else {
            availableBorrowsETH = 0;
        }
        healthFactor = 16 * 1e17; // 1.6 HF
    }

    function repay(address asset, uint256 amount, uint256, address /*onBehalfOf*/) external override returns (uint256) {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        if (totalDebtETH > amount.div(2000)) {
            totalDebtETH = totalDebtETH.sub(amount.div(2000));
        } else {
            totalDebtETH = 0;
        }
        healthFactor = 25 * 1e17; // 2.5 HF
        return amount;
    }

    function setUserUseReserveAsCollateral(address, bool) external override {}

    function getUserAccountData(address) external view override returns (
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256
    ) {
        return (
            totalCollateralETH,
            totalDebtETH,
            availableBorrowsETH,
            currentLiquidationThreshold,
            ltv,
            healthFactor
        );
    }

    receive() external payable {}
}

contract MockWETHGateway is IWETHGateway {
    using SafeMath for uint256;

    MockERC20 public aWeth;
    MockWETH public weth;
    address public lendingPool;

    constructor(address _aWeth, address payable _weth, address _lendingPool) public {
        aWeth = MockERC20(_aWeth);
        weth = MockWETH(_weth);
        lendingPool = _lendingPool;
    }

    function depositETH(address, address onBehalfOf, uint16) external payable override {
        aWeth.mint(onBehalfOf, msg.value);
    }

    function withdrawETH(address, uint256 amount, address to) external override {
        aWeth.burn(msg.sender, amount);
        payable(to).transfer(amount);
    }

    function repayETH(address, uint256, uint256, address) external payable override {}

    function borrowETH(address, uint256 amount, uint256, uint16) external override {
        payable(msg.sender).transfer(amount);
    }

    receive() external payable {}
}

contract MockUniswapV2Router is IUniswapV2Router02 {
    using SafeMath for uint256;

    address public override WETH;
    uint256 public rateDaiPerEth = 2000; // 1 ETH = 2000 DAI

    constructor(address _weth) public {
        WETH = _weth;
    }

    function setRate(uint256 _rate) external {
        rateDaiPerEth = _rate;
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /*deadline*/
    ) external override returns (uint256[] memory amounts) {
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        uint256 ethOut = amountIn.mul(1e18).div(rateDaiPerEth.mul(1e18));
        require(ethOut >= amountOutMin, "MockRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        payable(to).transfer(ethOut);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = ethOut;
        return amounts;
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /*deadline*/
    ) external payable override returns (uint256[] memory amounts) {
        uint256 tokenOut = msg.value.mul(rateDaiPerEth);
        require(tokenOut >= amountOutMin, "MockRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        MockERC20(path[1]).mint(to, tokenOut);

        amounts = new uint256[](2);
        amounts[0] = msg.value;
        amounts[1] = tokenOut;
        return amounts;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 /*amountOutMin*/,
        address[] calldata path,
        address to,
        uint256 /*deadline*/
    ) external override returns (uint256[] memory amounts) {
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        MockERC20(path[1]).mint(to, amountIn);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountIn;
        return amounts;
    }

    receive() external payable {}
}

contract MockVETH2 is MockERC20, IvETH2 {
    constructor() public MockERC20("validator-Eth2", "vETH2") {}

    function mint(address dst, uint256 rawAmount) public override(MockERC20, IvETH2) {
        totalSupply = totalSupply.add(rawAmount);
        balanceOf[dst] = balanceOf[dst].add(rawAmount);
        emit Transfer(address(0), dst, rawAmount);
    }

    function burn(address src, uint256 rawAmount) public override(MockERC20, IvETH2) {
        balanceOf[src] = balanceOf[src].sub(rawAmount);
        totalSupply = totalSupply.sub(rawAmount);
        emit Transfer(src, address(0), rawAmount);
    }
}

contract MockSharedDeposit is ISharedDeposit {
    using SafeMath for uint256;

    MockVETH2 public vEth2;

    constructor(address _vEth2) public {
        vEth2 = MockVETH2(_vEth2);
    }

    function BETHTokenAddress() external view override returns (address) {
        return address(vEth2);
    }

    function deposit() external payable override {
        require(msg.value > 0, "MockSharedDeposit: Zero value");
        // Mint 1:1 vETH2 for deposited ETH
        vEth2.mint(msg.sender, msg.value);
    }

    receive() external payable {
        vEth2.mint(msg.sender, msg.value);
    }
}
