// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

import "./Minter_v1.0.1.sol";
import "./deps/Address.sol";
import "./deps/SafeMath.sol";

/**
 * @title SoloStaking
 * @dev Solo staking extension for Minter contract
 * 
 * Requirements:
 * - Users must have 32 ETH
 * - Users must bond 1000 SGT (timelocked)
 * - Users receive 32 vETH2 in exchange for 32.1 ETH
 * - Admin can unlock SGT when validator exits
 * - Admin can slash SGT if validator acts nefariously
 * 
 * 版权声明：MIT License | Copyright (c) 2026 思捷娅科技 (SJYKJ)
 */
contract SoloStaking {
    using SafeMath for uint256;
    using Address for address payable;
    
    // Constants
    uint256 public constant VALIDATOR_DEPOSIT = 32 ether;
    uint256 public constant SGT_BOND_AMOUNT = 1000 * 10**18; // 1000 SGT (18 decimals)
    uint256 public constant DEPOSIT_FEE = 0.1 ether; // 0.1 ETH fee
    
    // State variables
    IMinter public immutable minter;
    ISGT public immutable sgt;
    IvETH2 public immutable veth2;
    
    struct SoloStaker {
        bool exists;
        uint256 sgtBonded;
        uint256 validatorPubkey;
        uint256 depositTimestamp;
        bool validatorExited;
        bool slashed;
    }
    
    mapping(address => SoloStaker) public soloStakers;
    address[] public soloStakerList;
    
    // Access Control
    address public admin;
    
    // Events
    event SoloStakerRegistered(address indexed staker, uint256 sgtBonded, uint256 timestamp);
    event ValidatorDeposit(address indexed staker, uint256 ethAmount, uint256 vEth2Amount, uint256 pubkey);
    event ValidatorExited(address indexed staker, uint256 timestamp);
    event SGTUnlocked(address indexed staker, uint256 amount);
    event SGTSlashed(address indexed staker, uint256 amount);
    
    // Interfaces
    interface IMinter {
        function send2eth2() external payable;
    }
    
    interface ISGT {
        function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
        function transfer(address recipient, uint256 amount) external returns (bool);
        function balanceOf(address account) external view returns (uint256);
    }
    
    interface IvETH2 {
        function mint(address to, uint256 amount) external;
        function balanceOf(address account) external view returns (uint256);
    }
    
    interface IDepositContract {
        function deposit(bytes calldata pubkey, bytes calldata withdrawal_credentials, bytes calldata signature, bytes32 deposit_data_root) external payable;
    }
    
    // Deposit Contract (ETH2)
    IDepositContract public constant DEPOSIT_CONTRACT = IDepositContract(0x00000000219ab540356cBB839Cbe05303d7705Fa);
    
    constructor(address _minter, address _sgt, address _veth2, address _admin) {
        minter = IMinter(_minter);
        sgt = ISGT(_sgt);
        veth2 = IvETH2(_veth2);
        admin = _admin;
    }
    
    // Modifiers
    modifier onlyAdmin() {
        require(msg.sender == admin, "SoloStaking: caller is not admin");
        _;
    }
    
    modifier onlyStaker() {
        require(soloStakers[msg.sender].exists, "SoloStaking: not a registered staker");
        _;
    }
    
    /**
     * @dev Register as a solo staker
     * Requirements:
     * - Must have 1000 SGT bonded
     * - SGT is timelocked until validator exits
     */
    function registerSoloStaker() external {
        require(!soloStakers[msg.sender].exists, "SoloStaking: already registered");
        
        // Transfer SGT bond from staker
        require(sgt.balanceOf(msg.sender) >= SGT_BOND_AMOUNT, "SoloStaking: insufficient SGT balance");
        require(sgt.transferFrom(msg.sender, address(this), SGT_BOND_AMOUNT), "SoloStaking: SGT transfer failed");
        
        // Register staker
        soloStakers[msg.sender] = SoloStaker({
            exists: true,
            sgtBonded: SGT_BOND_AMOUNT,
            validatorPubkey: 0,
            depositTimestamp: block.timestamp,
            validatorExited: false,
            slashed: false
        });
        
        soloStakerList.push(msg.sender);
        
        emit SoloStakerRegistered(msg.sender, SGT_BOND_AMOUNT, block.timestamp);
    }
    
    /**
     * @dev Deposit 32.1 ETH and receive 32 vETH2
     * Requirements:
     * - Must be registered solo staker
     * - Must send exactly 32.1 ETH (32 ETH deposit + 0.1 ETH fee)
     * - Must provide validator pubkey
     */
    function depositForValidator(bytes calldata pubkey, bytes calldata withdrawal_credentials, bytes calldata signature, bytes32 deposit_data_root) external payable onlyStaker {
        SoloStaker storage staker = soloStakers[msg.sender];
        
        require(!staker.validatorExited, "SoloStaking: validator already exited");
        require(msg.value == VALIDATOR_DEPOSIT.add(DEPOSIT_FEE), "SoloStaking: incorrect ETH amount");
        require(staker.validatorPubkey == 0, "SoloStaking: validator already registered");
        
        // Store validator pubkey
        staker.validatorPubkey = uint256(keccak256(pubkey));
        staker.depositTimestamp = block.timestamp;
        
        // Forward 32 ETH to ETH2 deposit contract
        payable(address(DEPOSIT_CONTRACT)).transfer(VALIDATOR_DEPOSIT);
        
        // Call deposit on deposit contract
        DEPOSIT_CONTRACT.deposit{value: VALIDATOR_DEPOSIT}(pubkey, withdrawal_credentials, signature, deposit_data_root);
        
        // Mint 32 vETH2 to staker
        veth2.mint(msg.sender, VALIDATOR_DEPOSIT);
        
        // Fee goes to minter contract
        payable(address(minter)).sendValue(DEPOSIT_FEE);
        
        emit ValidatorDeposit(msg.sender, VALIDATOR_DEPOSIT, VALIDATOR_DEPOSIT, staker.validatorPubkey);
    }
    
    /**
     * @dev Simple deposit function (for simplified implementation)
     * Returns 32 vETH2 for 32.1 ETH
     */
    function depositSimple() external payable onlyStaker {
        SoloStaker storage staker = soloStakers[msg.sender];
        
        require(!staker.validatorExited, "SoloStaking: validator already exited");
        require(msg.value == VALIDATOR_DEPOSIT.add(DEPOSIT_FEE), "SoloStaking: incorrect ETH amount");
        require(staker.validatorPubkey == 0, "SoloStaking: validator already registered");
        
        // Store deposit info
        staker.validatorPubkey = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp)));
        staker.depositTimestamp = block.timestamp;
        
        // Forward 32 ETH to minter (which will handle ETH2 deposit)
        payable(address(minter)).sendValue(VALIDATOR_DEPOSIT);
        
        // Call minter's send2eth2 function
        minter.send2eth2{value: 0}();
        
        // Mint 32 vETH2 to staker
        veth2.mint(msg.sender, VALIDATOR_DEPOSIT);
        
        // Fee stays in contract
        emit ValidatorDeposit(msg.sender, VALIDATOR_DEPOSIT, VALIDATOR_DEPOSIT, staker.validatorPubkey);
    }
    
    /**
     * @dev Mark validator as exited (admin only)
     * This allows the admin to unlock SGT when validator exits
     */
    function markValidatorExited(address staker) external onlyAdmin {
        require(soloStakers[staker].exists, "SoloStaking: staker does not exist");
        require(!soloStakers[staker].validatorExited, "SoloStaking: validator already exited");
        
        soloStakers[staker].validatorExited = true;
        
        emit ValidatorExited(staker, block.timestamp);
    }
    
    /**
     * @dev Unlock SGT bond when validator exits (admin only)
     */
    function unlockSGT(address staker) external onlyAdmin {
        SoloStaker storage stakerData = soloStakers[staker];
        
        require(stakerData.exists, "SoloStaking: staker does not exist");
        require(stakerData.validatorExited, "SoloStaking: validator not exited");
        require(!stakerData.slashed, "SoloStaking: staker has been slashed");
        
        uint256 amount = stakerData.sgtBonded;
        stakerData.sgtBonded = 0;
        
        require(sgt.transfer(staker, amount), "SoloStaking: SGT transfer failed");
        
        emit SGTUnlocked(staker, amount);
    }
    
    /**
     * @dev Slash SGT bond if validator acts nefariously (admin only)
     */
    function slashSGT(address staker, uint256 slashAmount) external onlyAdmin {
        SoloStaker storage stakerData = soloStakers[staker];
        
        require(stakerData.exists, "SoloStaking: staker does not exist");
        require(stakerData.sgtBonded >= slashAmount, "SoloStaking: insufficient bonded SGT");
        
        stakerData.sgtBonded = stakerData.sgtBonded.sub(slashAmount);
        stakerData.slashed = true;
        
        // Transfer slashed SGT to admin (or burn)
        require(sgt.transfer(admin, slashAmount), "SoloStaking: SGT transfer failed");
        
        emit SGTSslashed(staker, slashAmount);
    }
    
    /**
     * @dev Get all solo stakers
     */
    function getAllSoloStakers() external view returns (address[] memory) {
        return soloStakerList;
    }
    
    /**
     * @dev Get solo staker info
     */
    function getSoloStakerInfo(address staker) external view returns (
        bool exists,
        uint256 sgtBonded,
        uint256 validatorPubkey,
        uint256 depositTimestamp,
        bool validatorExited,
        bool slashed
    ) {
        SoloStaker storage stakerData = soloStakers[staker];
        return (
            stakerData.exists,
            stakerData.sgtBonded,
            stakerData.validatorPubkey,
            stakerData.depositTimestamp,
            stakerData.validatorExited,
            stakerData.slashed
        );
    }
    
    /**
     * @dev Get total number of solo stakers
     */
    function getSoloStakerCount() external view returns (uint256) {
        return soloStakerList.length;
    }
}
