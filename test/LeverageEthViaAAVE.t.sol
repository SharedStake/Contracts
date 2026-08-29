// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Mocks.sol";
import "../contracts/LeverageEthViaAAVE.sol";

contract LeverageEthViaAAVETest {
    using SafeMath for uint256;

    MockWETH public weth;
    MockERC20 public aWeth;
    MockERC20 public dai;
    MockDebtToken public stableDebtToken;
    MockDebtToken public variableDebtToken;
    MockDebtToken public wethVariableDebtToken;
    MockDebtToken public wethStableDebtToken;

    MockLendingPoolAddressesProvider public addressesProvider;
    MockAaveLendingPool public lendingPool;
    MockWETHGateway public wethGateway;
    MockUniswapV2Router public uniswapRouter;
    MockChainlinkAggregator public priceFeed;

    MockVETH2 public vEth2;
    MockSharedDeposit public sharedDeposit;

    LeverageEthViaAAVE public strategy;

    address public user = address(0x1111111111111111111111111111111111111111);
    address public otherUser = address(0x2222222222222222222222222222222222222222);

    function setUp() public {
        weth = new MockWETH();
        aWeth = new MockERC20("Aave Interest Bearing WETH", "aWETH");
        dai = new MockERC20("Dai Stablecoin", "DAI");
        stableDebtToken = new MockDebtToken("Aave Stable Debt DAI", "sDebtDAI");
        variableDebtToken = new MockDebtToken("Aave Variable Debt DAI", "vDebtDAI");
        wethVariableDebtToken = new MockDebtToken("Aave Variable Debt WETH", "vDebtWETH");
        wethStableDebtToken = new MockDebtToken("Aave Stable Debt WETH", "sDebtWETH");

        addressesProvider = new MockLendingPoolAddressesProvider();
        lendingPool = new MockAaveLendingPool(address(aWeth), address(dai), address(stableDebtToken));
        addressesProvider.setLendingPool(address(lendingPool));

        wethGateway = new MockWETHGateway(address(aWeth), payable(address(weth)), address(lendingPool));
        uniswapRouter = new MockUniswapV2Router(address(weth));
        priceFeed = new MockChainlinkAggregator(2000 * 1e8); // $2000 per ETH

        vEth2 = new MockVETH2();
        sharedDeposit = new MockSharedDeposit(address(vEth2));

        strategy = new LeverageEthViaAAVE(
            address(addressesProvider),
            address(wethGateway),
            address(uniswapRouter),
            address(weth),
            address(aWeth),
            address(dai),
            address(stableDebtToken),
            address(variableDebtToken),
            address(sharedDeposit),
            address(vEth2),
            address(priceFeed)
        );

        strategy.setTokens(
            address(weth),
            address(aWeth),
            address(dai),
            address(stableDebtToken),
            address(variableDebtToken),
            address(wethVariableDebtToken),
            address(wethStableDebtToken)
        );

        // Fund user and mock contracts with ETH and tokens
        payable(address(uniswapRouter)).transfer(10 ether);
        payable(address(lendingPool)).transfer(10 ether);
        payable(address(wethGateway)).transfer(10 ether);
        payable(address(this)).transfer(10 ether);
    }

    function testInitialization() public view {
        require(strategy.owner() == address(this), "Owner should be deployer");
        require(strategy.stableAsset() == address(dai), "Stable asset should be DAI");
        require(strategy.sharedDeposit() == address(sharedDeposit), "Shared deposit address match");
        require(strategy.vEth2Token() == address(vEth2), "vEth2 token match");
        require(strategy.getLatestPrice() == 2000 * 1e8, "ETH price should be 2000 USD");
    }

    function testLongEthWithSharedDeposit() public {
        // Execute longEth strategy with 1 ETH, leverage loop, and staking into SharedDeposit
        uint256 depositAmount = 1 ether;
        (uint256 ethStaked, uint256 vEthMinted) = strategy.longEth{value: depositAmount}(
            150, // minHealthFactor
            1,   // 1 loop
            2,   // variable debt
            true, // stakeInSharedDeposit
            0    // minAmountOut
        );

        require(ethStaked > 0, "ETH should have been staked");
        require(vEthMinted > 0, "vETH2 tokens should have been minted to caller");
        require(vEth2.balanceOf(address(this)) == vEthMinted, "Caller received vETH2");
        require(aWeth.balanceOf(address(strategy)) >= depositAmount, "Strategy holds aWETH collateral");
        // Verify credit delegation to caller
        uint256 allowance = variableDebtToken.borrowAllowance(address(strategy), address(this));
        require(allowance > 0, "Remaining credit should be delegated to caller");
    }

    function testLongEthMultipleLoops() public {
        // Execute longEth with multiple loops (compound leverage)
        (uint256 ethStaked, uint256 vEthMinted) = strategy.longEth{value: 1 ether}(
            150,
            3,   // 3 loops
            2,
            true,
            0
        );

        require(ethStaked > 0, "ETH staked");
        require(vEthMinted > 0, "vEth minted");
    }

    function testMaxLongEthConvenience() public {
        (uint256 ethStaked, uint256 vEthMinted) = strategy.maxLongEth{value: 1 ether}(
            150,
            2,
            true
        );
        require(ethStaked > 0, "ETH staked via maxLongEth");
        require(vEthMinted > 0, "vETH2 minted via maxLongEth");
    }

    function testLongEthStandaloneWithoutSharedDeposit() public {
        // Clear sharedDeposit to simulate testnet environment (e.g. Kovan)
        strategy.setSharedDeposit(address(0), address(0));

        (uint256 ethReturned, uint256 vEthMinted) = strategy.longEth{value: 1 ether}(
            150,
            1,
            2,
            false, // no staking
            0
        );

        require(vEthMinted == 0, "No vEth minted in standalone mode");
        require(ethReturned > 0, "ETH returned directly to caller");
    }

    function testShortEthStrategyWithSwap() public {
        // Mint DAI collateral to caller
        uint256 collateralDai = 5000 * 1e18; // 5000 DAI
        dai.mint(address(this), collateralDai);
        dai.approve(address(strategy), collateralDai);

        uint256 borrowEthAmount = 1 ether;
        uint256 daiReturned = strategy.shortEth(
            address(dai),
            collateralDai,
            borrowEthAmount,
            2, // variable rate
            false, // swap to DAI
            0
        );

        require(daiReturned > 0, "DAI returned from shorting ETH");
        require(dai.balanceOf(address(this)) >= daiReturned, "Caller received swapped DAI");
    }

    function testShortEthStrategyWithSharedDepositStaking() public {
        // Mint DAI collateral to caller
        uint256 collateralDai = 5000 * 1e18;
        dai.mint(address(this), collateralDai);
        dai.approve(address(strategy), collateralDai);

        uint256 borrowEthAmount = 1 ether;
        uint256 vEthReceived = strategy.shortEth(
            address(dai),
            collateralDai,
            borrowEthAmount,
            2,
            true, // Stake borrowed ETH into SharedDeposit!
            0
        );

        require(vEthReceived == borrowEthAmount, "Caller received vETH2 for staked borrowed ETH");
        require(vEth2.balanceOf(address(this)) == vEthReceived, "Caller vETH2 balance updated");
    }

    function testCreditDelegationContractToUser() public {
        uint256 delegAmount = 10000 * 1e18;
        strategy.delegateCreditToUser(user, address(stableDebtToken), delegAmount);

        uint256 allowance = stableDebtToken.borrowAllowance(address(strategy), user);
        require(allowance == delegAmount, "Delegation allowance should match");
    }

    function testBorrowOnBehalfOfUser() public {
        // Simulate user delegating credit on DAI to strategy
        variableDebtToken.approveDelegation(address(strategy), 1000 * 1e18);

        // Strategy executes borrowOnBehalfOfUser, swaps to ETH and stakes to SharedDeposit for user
        uint256 vEthMinted = strategy.borrowOnBehalfOfUser(
            address(dai),
            1000 * 1e18,
            2,
            user,
            true, // swap to ETH
            true, // stake in SharedDeposit
            0
        );

        require(vEthMinted > 0, "vETH2 minted for user");
        require(vEth2.balanceOf(user) == vEthMinted, "User received minted vETH2");
    }

    function testRepayDebtAndWithdrawCollateral() public {
        // Open long position
        strategy.longEth{value: 1 ether}(150, 1, 2, false, 0);

        // Repay stable debt
        dai.mint(address(this), 2000 * 1e18);
        dai.approve(address(strategy), 2000 * 1e18);
        uint256 repaid = strategy.repayDebt(address(dai), 1000 * 1e18, 2, address(strategy));
        require(repaid == 1000 * 1e18, "Debt repaid");

        // Withdraw ETH collateral
        strategy.withdrawETHCollateral(1 ether, payable(address(this)));
    }

    function testCloseLongPosition() public {
        strategy.longEth{value: 1 ether}(150, 1, 2, false, 0);

        dai.mint(address(this), 2000 * 1e18);
        dai.approve(address(strategy), 2000 * 1e18);

        strategy.closeLongPosition(500 * 1e18, 1 ether, payable(address(this)));
    }

    function testCloseShortPosition() public {
        uint256 collateralDai = 5000 * 1e18;
        dai.mint(address(this), collateralDai);
        dai.approve(address(strategy), collateralDai);

        strategy.shortEth(address(dai), collateralDai, 1 ether, 2, false, 0);

        strategy.closeShortPosition{value: 1 ether}(address(dai), collateralDai, address(this));
        require(dai.balanceOf(address(this)) >= collateralDai, "Collateral returned");
    }

    function testPausable() public {
        strategy.pause();
        require(strategy.paused(), "Strategy should be paused");

        // Attempting longEth when paused should revert
        (bool success, ) = address(strategy).call{value: 1 ether}(
            abi.encodeWithSelector(strategy.longEth.selector, 150, 1, 2, false, 0)
        );
        require(!success, "Should revert when paused");

        strategy.unpause();
        require(!strategy.paused(), "Strategy should be unpaused");
    }

    function testTwoStepOwnershipTransfer() public {
        strategy.nominateNewOwner(user);
        require(strategy.nominatedOwner() == user, "Nominated owner set");
        require(strategy.owner() == address(this), "Owner remains current until accepted");

        // Accept ownership as non-nominated caller should fail
        (bool success, ) = address(strategy).call(abi.encodeWithSelector(strategy.acceptOwnership.selector));
        require(!success, "Non-nominated cannot accept");

        // Now nominate this contract back and accept
        strategy.nominateNewOwner(address(this));
        strategy.acceptOwnership();
        require(strategy.owner() == address(this), "Owner updated after accept");
    }

    function testDirectOwnershipTransfer() public {
        strategy.transferOwnership(user);
        require(strategy.owner() == user, "Direct ownership transfer works");
    }

    function testSlippageRevert() public {
        // High minAmountOut should revert if slippage is violated
        (bool success, ) = address(strategy).call{value: 1 ether}(
            abi.encodeWithSelector(strategy.longEth.selector, 150, 1, 2, false, 9999 ether)
        );
        require(!success, "Should revert on excessive slippage expectation");
    }

    function testInvalidMinHealthFactorRevert() public {
        // minHealthFactor <= 100 must revert
        (bool success, ) = address(strategy).call{value: 1 ether}(
            abi.encodeWithSelector(strategy.longEth.selector, 90, 1, 2, false, 0)
        );
        require(!success, "Should revert when minHealthFactor <= 100");
    }

    function testAccountDataViews() public view {
        uint256 hf = strategy.getHealthFactor(address(strategy));
        require(hf > 0, "Health factor view valid");

        uint256 avail = strategy.getAvailableBorrowsETH(address(strategy));
        require(avail > 0, "Available borrows ETH view valid");

        uint256 debt = strategy.getTotalDebtETH(address(strategy));
        require(debt == 0, "Initial debt is 0");
    }

    function testRescueTokensAndEth() public {
        dai.mint(address(strategy), 500 * 1e18);
        require(dai.balanceOf(address(strategy)) == 500 * 1e18, "Strategy holds DAI");

        strategy.rescueTokens(address(dai), user, 500 * 1e18);
        require(dai.balanceOf(user) == 500 * 1e18, "User received rescued DAI");

        payable(address(strategy)).transfer(1 ether);
        uint256 userEthBefore = user.balance;
        strategy.rescueETH(payable(user), 1 ether);
        require(user.balance == userEthBefore.add(1 ether), "User received rescued ETH");
    }

    receive() external payable {}
}
