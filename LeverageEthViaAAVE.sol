// SPDX-License-Identifier: MIT

/**
 * EthDerivativeProxy
 * **This contract is not general purpose and needs a factory or manual user deploy per user **
 * 
 * A proxy contract to open a derivative position on ETH 
 * The position is based on an AAVE collateralized debt position
 * Allowing the user to long or short eth
 * 2 types:
 * - longEth / maxLongEth
 *      - user deposits eth into contract 
 *      - contract deposits eth into aave
 *      - withdraws dai / stablecoins
 *      - uses it to purchase eth
 *      - remaining borrowing power of collateral is delegated to user returning control
 *      - purchases assets can be reinvested or returned to the user
 * - short eth 
 *      - user deposits stablecoins
 *      - contract uses stablecoins to open a aave cdp
 *      - contract borrows eth
 *      - swaps eth for initial stablecoin asset 
 * 
 * 
 * 
 * */
pragma solidity 0.6.12;

import { IERC20 } from "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v3.3.0/contracts/token/ERC20/IERC20.sol";
import { SafeMath } from "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v3.3.0/contracts/math/SafeMath.sol";
import { SafeERC20 } from "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v3.3.0/contracts/token/ERC20/SafeERC20.sol";
import { Ownable } from  "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v3.3.0/contracts/access/Ownable.sol";
import { IFlashLoanReceiver } from "https://raw.githubusercontent.com/aave/protocol-v2/master/contracts/flashloan/interfaces/IFlashLoanReceiver.sol";
import { ILendingPoolAddressesProvider } from "https://raw.githubusercontent.com/aave/protocol-v2/master/contracts/interfaces/ILendingPoolAddressesProvider.sol";

import { ILendingPool } from "https://raw.githubusercontent.com/aave/protocol-v2/master/contracts/interfaces/ILendingPool.sol";
import { IWETHGateway } from "https://raw.githubusercontent.com/aave/protocol-v2/ice/mainnet-deployment-03-12-2020/contracts/misc/interfaces/IWETHGateway.sol";
import { IAToken } from "https://raw.githubusercontent.com/aave/protocol-v2/ice/mainnet-deployment-03-12-2020/contracts/interfaces/IAToken.sol";
import { ICreditDelegationToken } from "https://raw.githubusercontent.com/aave/protocol-v2/master/contracts/interfaces/ICreditDelegationToken.sol";
import { IUniswapV2Router02 } from "https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol";
import { IStableDebtToken } from "https://raw.githubusercontent.com/aave/code-examples-protocol/main/V2/Credit%20Delegation/Interfaces.sol";

import { AggregatorV3Interface } from "https://raw.githubusercontent.com/smartcontractkit/chainlink/1127674865885c034dd1950c16dd3ddd5e3df859/evm-contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

pragma solidity ^0.6.7;


contract PriceConsumerV3 {

    AggregatorV3Interface internal priceFeed;
    
    // Kovan
    address internal constant chainlinkETHUSDPriceFeed  = 0x9326BFA02ADD2366b30bacB125260Af641031331;

    // Mainnet
    // address internal constant chainlinkETHUSDPriceFeed  = 0xFf795577d9AC8bD7D90Ee22b6C1703490b6512FD;

    /**
     * Network: Kovan
     * Aggregator: ETH/USD
     * Address: 0x9326BFA02ADD2366b30bacB125260Af641031331
     */
    constructor() public {
        priceFeed = AggregatorV3Interface(chainlinkETHUSDPriceFeed);
    }

    /**
     * Returns the latest price
     */
    function getLatestPrice() public view returns (int) {
        (
            uint80 roundID, 
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        return price;
    }
}

contract Owned {
    address public owner;
    address public nominatedOwner;

    constructor(address _owner) public {
        require(_owner != address(0), "Owner address cannot be 0");
        owner = _owner;
        emit OwnerChanged(address(0), _owner);
    }

    function nominateNewOwner(address _owner) external onlyOwner {
        nominatedOwner = _owner;
        emit OwnerNominated(_owner);
    }

    function acceptOwnership() external {
        require(
            msg.sender == nominatedOwner,
            "You must be nominated before you can accept ownership"
        );
        emit OwnerChanged(owner, nominatedOwner);
        owner = nominatedOwner;
        nominatedOwner = address(0);
    }

    modifier onlyOwner {
        _onlyOwner();
        _;
    }

    function _onlyOwner() private view {
        require(
            msg.sender == owner,
            "Only the contract owner may perform this action"
        );
    }

    event OwnerNominated(address newOwner);
    event OwnerChanged(address oldOwner, address newOwner);
}

contract EthDerivativeProxy is Ownable, PriceConsumerV3 {
    using SafeERC20 for IERC20;

    // Kovan adresses
    address internal constant DAI_CONTRACT = 0xFf795577d9AC8bD7D90Ee22b6C1703490b6512FD;
    address internal constant WETH_CONTRACT = 0xd0A1E359811322d97991E03f863a0C30C2cF029C;
    address internal constant AWETH_CONTRACT = 0x87b1f4cf9BD63f7BBD3eE1aD04E8F52540349347;
    address internal constant AAVE_CONTRACT = 0x88757f2f99175387aB4C6a4b3067c77A695b0349;
    address internal constant UNISWAP_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant WETH_GATEWAY_ADDRESS = 0xf8aC10E65F2073460aAD5f28E1EABE807DC287CF;
    address internal constant ASD_DAI = 0x447a1cC578470cc2EA4450E0b730FD7c69369ff3;
    
    // // Mainnet
    // address internal constant DAI_CONTRACT = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    // address internal constant DEBT_DAI_CONTRACT = 0x6C3c78838c761c6Ac7bE9F59fe808ea2A6E4379d;
    // address internal constant WETH_CONTRACT = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // address internal constant AWETH_CONTRACT = 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e;
    // address internal constant AAVE_CONTRACT = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;
    // address internal constant UNISWAP_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    // address internal constant WETH_GATEWAY_ADDRESS = 0xDcD33426BA191383f1c9B431A342498fdac73488;
    
    ILendingPoolAddressesProvider public ADDRESSES_PROVIDER;
    IWETHGateway public WETH_GATEWAY;

    IUniswapV2Router02 public UNISWAP_ROUTER;

    ILendingPool public lendingPool;

    constructor(
        ) public {
          ADDRESSES_PROVIDER = ILendingPoolAddressesProvider(AAVE_CONTRACT);
          lendingPool = ILendingPool(ADDRESSES_PROVIDER.getLendingPool());
          WETH_GATEWAY = IWETHGateway(WETH_GATEWAY_ADDRESS);
          UNISWAP_ROUTER = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
        }

    // Pre-req is to deposit eth into the contract via a send 
    // When executed 
    // We will deposit the eth bal of this contract into AAVE
    // Withdraw half as much DAI as possible, and convert it to eth via uniswap
    // Repeat till the minHealthFactor is reached
    // Any leftover CDP value is credit delegated to the caller to do with as they please
    // ETH then owned by the contract can be pulled out or used to fund protocols
    function maxLongEth(uint minHealthFactor) public payable onlyOwner returns (uint) {
        uint amount = address(this).balance;
        depositETH(amount);

        uint healthFactor = getHealthFactor(address(this));
        if (minHealthFactor == 0) {
            minHealthFactor = 150;
        }
        require(minHealthFactor > 100, "healthFactor too low, needs to be above 1 * 100");

        uint loops = 0;
        while (healthFactor > minHealthFactor/100) {
            amount = borrowDAIAndSwapToETH();
            healthFactor = getHealthFactor(address(this));
            loops = loops + 1;
        }

        // Allow the user to use any leftovers
        approveDebtIncuree(msg.sender, IERC20(AWETH_CONTRACT).balanceOf(address(this)), ASD_DAI);
        return loops;
    }

    function longEth(uint amount) public payable onlyOwner returns (uint) {
        depositETH(amount);
        uint swapReturns = borrowDAIAndSwapToETH();
        return swapReturns;
    }

    // Borrows half the max borrow amount in dai and swaps to eth
    function borrowDAIAndSwapToETH() public payable onlyOwner returns (uint) {
        borrow(address(this), address(DAI_CONTRACT), uint256(getLatestPrice()));
        uint swapReturns = swapERC20ForETH(DAI_CONTRACT, IERC20(DAI_CONTRACT).balanceOf(address(this)), 0);
        return swapReturns;
    }

    function shortEth(address asset, uint amount) public payable onlyOwner returns (uint) {
        IERC20(asset).safeApprove(address(this), amount);
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        require(IERC20(asset).balanceOf(address(this)) == amount, "Did not receive tokens");
        depositCollateral(asset, address(this), amount);
        borrowETH(address(this));
        uint swapReturns = swapETHForERC20(asset,amount, 0);
        return swapReturns;
    }

    // Deposits collateral into the Aave, to enable debt delegation
    function depositCollateral(address asset, address depositOnBehalfOf, uint256 amount) public onlyOwner {
        IERC20(asset).safeApprove(address(lendingPool), amount);
        lendingPool.deposit(asset, amount, address(this), 0);
    }

    function depositETH(uint amount) public onlyOwner {
        WETH_GATEWAY.depositETH{ value: amount }(address(this), 0);

        require(IERC20(AWETH_CONTRACT).balanceOf(address(this)) > 0, "Did not receive any A token");
    }

    function borrowETH(address depositOnBehalfOf) public onlyOwner returns (uint256) {
        uint256 totalCollateralETH;
        uint256 totalDebtETH;
        uint256 availableBorrowsETH;
        uint256 currentLiquidationThreshold;
        uint256 ltv;
        uint256 healthFactor;

      (
        totalCollateralETH,
        totalDebtETH,
        availableBorrowsETH,
        currentLiquidationThreshold,
        ltv,
        healthFactor
       ) = lendingPool.getUserAccountData(depositOnBehalfOf);

        require(healthFactor > 1, "healthFactor too low");
        uint256 toBorrow = availableBorrowsETH / 2;
        WETH_GATEWAY.borrowETH(toBorrow, 1, 0);
    }
    
    function getUserAccountDataAsArray(address depositOnBehalfOf) public returns (uint[6] memory) {
        uint256 totalCollateralETH;
        uint256 totalDebtETH;
        uint256 availableBorrowsETH;
        uint256 currentLiquidationThreshold;
        uint256 ltv;
        uint256 healthFactor;
        
      (
        totalCollateralETH,
        totalDebtETH,
        availableBorrowsETH,
        currentLiquidationThreshold,
        ltv,
        healthFactor
       ) = lendingPool.getUserAccountData(depositOnBehalfOf);
       return [totalCollateralETH, totalDebtETH, availableBorrowsETH, currentLiquidationThreshold, ltv, healthFactor];
    }
    
    function getHealthFactor(address depositOnBehalfOf) public onlyOwner returns (uint) {
        // uint256 totalCollateralETH;
        // uint256 totalDebtETH;
        // uint256 availableBorrowsETH;
        // uint256 currentLiquidationThreshold;
        // uint256 ltv;
        // uint256 healthFactor;
        uint256[6] memory response = getUserAccountDataAsArray(depositOnBehalfOf);

       return response[5];
    }
    
    function getTotalDebtEth(address depositOnBehalfOf) public onlyOwner returns (uint) {
        uint256[6] memory response = getUserAccountDataAsArray(depositOnBehalfOf);
       return response[1];
    }
    
    function getAvailableBorrowsETH(address depositOnBehalfOf) public onlyOwner returns (uint) {
        uint256[6] memory response = getUserAccountDataAsArray(depositOnBehalfOf);
        return response[2];
    }

    function borrow(address depositOnBehalfOf, address asset, uint price) public onlyOwner returns (uint256) {
        uint256 availableBorrowsETH = getAvailableBorrowsETH(depositOnBehalfOf);
        uint256 healthFactor = getHealthFactor(depositOnBehalfOf);
        require(healthFactor > 1, "healthFactor too low");

        uint256 toBorrow = SafeMath.div(SafeMath.mul(availableBorrowsETH, price), 2);

       // function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
       // interestRateMode => 1 = stable, 2 = variable
        lendingPool.borrow(asset, toBorrow, 1, 0, depositOnBehalfOf);
        return toBorrow;
    }

    // Approves the flash loan executor to incure debt on this contract's behalf
    function approveDebtIncuree(address borrower, uint256 amount, address debtAsset) public onlyOwner {
        IStableDebtToken(debtAsset).approveDelegation(borrower, amount);
    }


    // Pay off the incurred debt
    function repayBorrower(uint256 amount, address asset) public {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(asset).safeApprove(address(lendingPool), amount);
        lendingPool.repay(asset, amount, 1, address(this));
    }

    // Withdraw all of a collateral as the underlying asset, if no outstanding loans delegated
    function withdrawCollateral(address asset, uint256 amount) public onlyOwner {
        lendingPool.withdraw(asset, amount, address(this));
    }

    /*
    * Rugpull yourself to drain all ETH and ERC20 tokens from the contract
    */
    function rugPull(address _erc20Asset) public payable onlyOwner {
        // withdraw all ETH
        msg.sender.call{ value: address(this).balance }("");

        // withdraw all x ERC20 tokens
        IERC20(_erc20Asset).transfer(msg.sender, IERC20(_erc20Asset).balanceOf(address(this)));
    }

    function swapERC20ForETH(address token, uint amountIn, uint amountOutMin) internal onlyOwner returns (uint256 amounts) {
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = UNISWAP_ROUTER.WETH();
    
        uint deadline = block.timestamp + 15; // Pass this as argument
        
        IERC20(token).approve(address(UNISWAP_ROUTER), amountIn);
        
        uint256 swapReturns = UNISWAP_ROUTER.swapExactTokensForETH(amountIn, amountOutMin, path, address(this), deadline)[1];
        
        require(swapReturns > 0, "Uniswap didn't return anything");
        return swapReturns;
    }

    function swapETHForERC20(address token, uint amountIn, uint amountOutMin) internal onlyOwner returns (uint256 amounts) {
        address[] memory path = new address[](2);
        path[0] = UNISWAP_ROUTER.WETH();
        path[1] = token;

        uint deadline = block.timestamp + 15; // Pass this as argument

        IERC20(token).approve(address(UNISWAP_ROUTER), amountIn);

        // function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        uint256 swapReturns = UNISWAP_ROUTER.swapExactETHForTokens{value: amountIn}(amountOutMin, path, address(this), deadline)[1];
        
        require(swapReturns > 0, "Uniswap didn't return anything");
        return swapReturns;
    }

    fallback () payable external {
        
    }

}
