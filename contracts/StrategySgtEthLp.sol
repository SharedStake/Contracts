// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./SettVaultSgtEth.sol";

/**
 * @title IUniswapV2Router02
 * @notice Uniswap V2 Router interface for swaps and liquidity addition.
 */
interface IUniswapV2Router02 {
    /**
     * @notice Swaps exact tokens for tokens along designated path.
     * @param amountIn Amount of input tokens sent.
     * @param amountOutMin Minimum amount of output tokens expected.
     * @param path Array of token addresses representing swap route.
     * @param to Recipient of output tokens.
     * @param deadline Unix timestamp by which transaction must be confirmed.
     * @return amounts Resulting output amounts per hop.
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Adds liquidity to Uniswap V2 pool.
     * @param tokenA First token address.
     * @param tokenB Second token address.
     * @param amountADesired Target amount of token A.
     * @param amountBDesired Target amount of token B.
     * @param amountAMin Slippage minimum for token A.
     * @param amountBMin Slippage minimum for token B.
     * @param to Recipient of newly minted LP tokens.
     * @param deadline Unix timestamp by which transaction must be confirmed.
     * @return amountA Actual amount of token A deposited.
     * @return amountB Actual amount of token B deposited.
     * @return liquidity Actual LP tokens minted.
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

/**
 * @title StrategySgtEthLp
 * @notice Auto-compounding strategy for SGT/ETH LP on Uniswap V2.
 * Harvests SGT rewards, swaps 50% to WETH, adds Uniswap V2 liquidity,
 * and reinvests LP tokens to compound vault share price.
 */
contract StrategySgtEthLp {
    using SafeMath for uint256;

    address public want;
    address public sgt;
    address public weth;
    address public uniswapRouter;

    address public vault;
    address public governance;
    address public strategist;
    address public treasury;

    uint256 public performanceFee = 450;
    uint256 public strategistFee = 50;
    uint256 public constant feeMax = 10000;

    event Harvested(uint256 sgtHarvested, uint256 lpMinted);
    event FeesDistributed(uint256 treasuryFee, uint256 strategistFee);

    modifier onlyGovernance() {
        require(msg.sender == governance, "!governance");
        _;
    }

    modifier onlyStrategist() {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        _;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "!vault");
        _;
    }

    /**
     * @notice Initializes strategy dependencies and approves token routers.
     * @param _want Uniswap V2 SGT/ETH LP token address.
     * @param _sgt SGT token address.
     * @param _weth WETH token address.
     * @param _uniswapRouter Uniswap V2 router address.
     * @param _vault Associated Sett vault address.
     * @param _governance Admin governance address.
     * @param _strategist Strategist role address.
     * @param _treasury Protocol treasury address.
     */
    constructor(
        address _want,
        address _sgt,
        address _weth,
        address _uniswapRouter,
        address _vault,
        address _governance,
        address _strategist,
        address _treasury
    ) public {
        require(_want != address(0), "invalid want");
        require(_sgt != address(0), "invalid sgt");
        require(_weth != address(0), "invalid weth");
        require(_uniswapRouter != address(0), "invalid router");
        require(_vault != address(0), "invalid vault");

        want = _want;
        sgt = _sgt;
        weth = _weth;
        uniswapRouter = _uniswapRouter;
        vault = _vault;
        governance = _governance;
        strategist = _strategist;
        treasury = _treasury;

        IERC20(want).approve(_vault, type(uint256).max);
        IERC20(sgt).approve(_uniswapRouter, type(uint256).max);
        IERC20(weth).approve(_uniswapRouter, type(uint256).max);
    }

    /**
     * @notice Hook invoked by vault when new LP assets are transferred to strategy.
     */
    function deposit() public onlyVault {}

    /**
     * @notice Withdraws specified LP amount back to vault.
     * @param _amount Requested LP tokens to withdraw.
     */
    function withdraw(uint256 _amount) external onlyVault {
        uint256 b = IERC20(want).balanceOf(address(this));
        if (b < _amount) {
            _amount = b;
        }
        IERC20(want).transfer(vault, _amount);
    }

    /**
     * @notice Withdraws all LP tokens held in strategy back to vault.
     * @return Total withdrawn LP tokens.
     */
    function withdrawAll() external onlyVault returns (uint256) {
        uint256 b = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, b);
        return b;
    }

    /**
     * @notice Returns total LP tokens held by strategy.
     * @return Strategy LP token balance.
     */
    function balanceOf() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    /**
     * @notice Harvests accumulated SGT yield, deducts fees, swaps to WETH, and mints LP tokens.
     */
    function harvest() public onlyStrategist {
        uint256 sgtBalance = IERC20(sgt).balanceOf(address(this));
        if (sgtBalance == 0) return;

        uint256 feeTreasury = sgtBalance.mul(performanceFee).div(feeMax);
        uint256 feeStrat = sgtBalance.mul(strategistFee).div(feeMax);
        if (feeTreasury > 0) {
            IERC20(sgt).transfer(treasury, feeTreasury);
        }
        if (feeStrat > 0) {
            IERC20(sgt).transfer(strategist, feeStrat);
        }
        emit FeesDistributed(feeTreasury, feeStrat);

        uint256 sgtToReinvest = IERC20(sgt).balanceOf(address(this));
        if (sgtToReinvest < 1000) return;

        uint256 sgtToSwap = sgtToReinvest.div(2);
        uint256 sgtRemaining = sgtToReinvest.sub(sgtToSwap);

        address[] memory path = new address[](2);
        path[0] = sgt;
        path[1] = weth;

        IUniswapV2Router02(uniswapRouter).swapExactTokensForTokens(
            sgtToSwap,
            0,
            path,
            address(this),
            block.timestamp.add(1800)
        );

        uint256 wethBalance = IERC20(weth).balanceOf(address(this));

        (, , uint256 lpMinted) = IUniswapV2Router02(uniswapRouter).addLiquidity(
            sgt,
            weth,
            sgtRemaining,
            wethBalance,
            0,
            0,
            address(this),
            block.timestamp.add(1800)
        );

        emit Harvested(sgtBalance, lpMinted);
    }

    /**
     * @notice Recovers extraneous ERC20 tokens inadvertently sent to strategy.
     * @param _token Address of stray token to rescue.
     */
    function inCaseTokensGetStuck(address _token) external onlyGovernance {
        require(_token != want, "!want");
        require(_token != sgt, "!sgt");
        require(_token != weth, "!weth");
        uint256 _amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(governance, _amount);
    }

    /**
     * @notice Updates governance admin address.
     * @param _governance New governance address.
     */
    function setGovernance(address _governance) external onlyGovernance {
        require(_governance != address(0), "invalid governance");
        governance = _governance;
    }

    /**
     * @notice Updates designated strategist address.
     * @param _strategist New strategist address.
     */
    function setStrategist(address _strategist) external onlyGovernance {
        strategist = _strategist;
    }

    /**
     * @notice Updates designated treasury address.
     * @param _treasury New treasury address.
     */
    function setTreasury(address _treasury) external onlyGovernance {
        treasury = _treasury;
    }

    /**
     * @notice Adjusts performance and strategist harvest fee rates in basis points.
     * @param _performanceFee Performance fee basis points.
     * @param _strategistFee Strategist fee basis points.
     */
    function setFees(uint256 _performanceFee, uint256 _strategistFee) external onlyGovernance {
        require(_performanceFee.add(_strategistFee) <= 2000, "fees too high");
        performanceFee = _performanceFee;
        strategistFee = _strategistFee;
    }
}
