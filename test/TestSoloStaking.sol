// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

import "truffle/Assert.sol";
import "truffle/DeployedAddresses.sol";
import "../SoloStaking.sol";

contract TestSoloStaking {
    SoloStaking public soloStaking;
    
    // Mock contracts for testing
    MockMinter public minter;
    MockSGT public sgt;
    MockVETH2 public veth2;
    
    uint256 public constant VALIDATOR_DEPOSIT = 32 ether;
    uint256 public constant SGT_BOND_AMOUNT = 1000 * 10**18;
    uint256 public constant DEPOSIT_FEE = 0.1 ether;
    
    address public admin = address(1);
    address public staker1 = address(2);
    address public staker2 = address(3);
    
    function beforeEach() public {
        // Deploy mock contracts
        minter = new MockMinter();
        sgt = new MockSGT();
        veth2 = new MockVETH2();
        
        // Deploy SoloStaking contract
        soloStaking = new SoloStaking(address(minter), address(sgt), address(veth2), admin);
        
        // Fund stakers with SGT
        sgt.mint(staker1, SGT_BOND_AMOUNT * 2);
        sgt.mint(staker2, SGT_BOND_AMOUNT);
    }
    
    function testRegisterSoloStaker() public {
        vm.prank(staker1);
        sgt.approve(address(soloStaking), SGT_BOND_AMOUNT);
        
        vm.prank(staker1);
        soloStaking.registerSoloStaker();
        
        (bool exists, uint256 sgtBonded,,,,) = soloStaking.getSoloStakerInfo(staker1);
        
        Assert.isTrue(exists, "Staker should be registered");
        Assert.equal(sgtBonded, SGT_BOND_AMOUNT, "SGT bond amount should match");
    }
    
    function testRegisterSoloStakerInsufficientSGT() public {
        vm.prank(staker2);
        sgt.approve(address(soloStaking), SGT_BOND_AMOUNT);
        
        // This should succeed since staker2 has enough SGT
        vm.prank(staker2);
        soloStaking.registerSoloStaker();
        
        (bool exists,,,) = soloStaking.getSoloStakerInfo(staker2);
        Assert.isTrue(exists, "Staker should be registered");
    }
    
    function testDepositForValidator() public {
        // Register staker
        vm.prank(staker1);
        sgt.approve(address(soloStaking), SGT_BOND_AMOUNT);
        vm.prank(staker1);
        soloStaking.registerSoloStaker();
        
        // Deposit for validator
        bytes memory pubkey = abi.encodePacked(bytes32(uint256(1)));
        bytes memory withdrawal_credentials = abi.encodePacked(bytes32(uint256(2)));
        bytes memory signature = abi.encodePacked(bytes32(uint256(3)));
        bytes32 deposit_data_root = bytes32(uint256(4));
        
        vm.prank(staker1);
        soloStaking.depositForValidator{value: VALIDATOR_DEPOSIT.add(DEPOSIT_FEE)}(
            pubkey,
            withdrawal_credentials,
            signature,
            deposit_data_root
        );
        
        // Check vETH2 was minted
        uint256 vEth2Balance = veth2.balanceOf(staker1);
        Assert.equal(vEth2Balance, VALIDATOR_DEPOSIT, "vETH2 should be minted");
    }
    
    function testDepositSimple() public {
        // Register staker
        vm.prank(staker1);
        sgt.approve(address(soloStaking), SGT_BOND_AMOUNT);
        vm.prank(staker1);
        soloStaking.registerSoloStaker();
        
        // Simple deposit
        vm.prank(staker1);
        soloStaking.depositSimple{value: VALIDATOR_DEPOSIT.add(DEPOSIT_FEE)}();
        
        // Check vETH2 was minted
        uint256 vEth2Balance = veth2.balanceOf(staker1);
        Assert.equal(vEth2Balance, VALIDATOR_DEPOSIT, "vETH2 should be minted");
    }
    
    function testUnlockSGT() public {
        // Register staker
        vm.prank(staker1);
        sgt.approve(address(soloStaking), SGT_BOND_AMOUNT);
        vm.prank(staker1);
        soloStaking.registerSoloStaker();
        
        // Mark validator as exited
        vm.prank(admin);
        soloStaking.markValidatorExited(staker1);
        
        // Unlock SGT
        uint256 balanceBefore = sgt.balanceOf(staker1);
        vm.prank(admin);
        soloStaking.unlockSGT(staker1);
        uint256 balanceAfter = sgt.balanceOf(staker1);
        
        Assert.equal(balanceAfter, balanceBefore.add(SGT_BOND_AMOUNT), "SGT should be unlocked");
    }
    
    function testSlashSGT() public {
        // Register staker
        vm.prank(staker1);
        sgt.approve(address(soloStaking), SGT_BOND_AMOUNT);
        vm.prank(staker1);
        soloStaking.registerSoloStaker();
        
        // Slash SGT
        uint256 slashAmount = SGT_BOND_AMOUNT / 2;
        uint256 adminBalanceBefore = sgt.balanceOf(admin);
        vm.prank(admin);
        soloStaking.slashSGT(staker1, slashAmount);
        uint256 adminBalanceAfter = sgt.balanceOf(admin);
        
        Assert.equal(adminBalanceAfter, adminBalanceBefore.add(slashAmount), "Admin should receive slashed SGT");
    }
    
    function testGetSoloStakerCount() public {
        Assert.equal(soloStaking.getSoloStakerCount(), 0, "Initial count should be 0");
        
        // Register stakers
        vm.prank(staker1);
        sgt.approve(address(soloStaking), SGT_BOND_AMOUNT);
        vm.prank(staker1);
        soloStaking.registerSoloStaker();
        
        vm.prank(staker2);
        sgt.approve(address(soloStaking), SGT_BOND_AMOUNT);
        vm.prank(staker2);
        soloStaking.registerSoloStaker();
        
        Assert.equal(soloStaking.getSoloStakerCount(), 2, "Count should be 2");
    }
}

// Mock Contracts
contract MockMinter {
    function send2eth2() external payable {}
}

contract MockSGT {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
    
    function transfer(address recipient, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }
    
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        allowance[sender][msg.sender] -= amount;
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract MockVETH2 {
    mapping(address => uint256) public balanceOf;
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
}
