pragma solidity 0.6.9;

import {IERC20} from "https://raw.githubusercontent.com/sharedStake-dev/badger-system/master/deps/%40openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "https://raw.githubusercontent.com/sharedStake-dev/badger-system/master/deps/%40openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "https://raw.githubusercontent.com/sharedStake-dev/badger-system/master/deps/%40openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "https://raw.githubusercontent.com/sharedStake-dev/badger-system/master/deps/%40openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {Executor} from "https://raw.githubusercontent.com/sharedStake-dev/badger-system/master/contracts/badger-timelock/Executor.sol";

// SmartTimeLock forked from badger.finance

/**
 * @dev A token holder contract that will allow a beneficiary to extract the
 * tokens after a given release time.
 *
 * Useful for simple vesting schedules like "advisors get all of their tokens
 * after 1 year".
 */
abstract contract TokenTimelock is Ownable {
    using SafeERC20 for IERC20;

    // ERC20 basic token contract being held
    IERC20 private _token;

    // beneficiary of tokens after they are released
    address private _beneficiary;

    // timestamp when token release is enabled
    uint256 private _releaseTime;

    constructor (IERC20 token, address beneficiary, uint256 releaseTime) public {
        // solhint-disable-next-line not-rely-on-time
        require(releaseTime > block.timestamp, "TokenTimelock: release time is before current time");
        _token = token;
        _beneficiary = beneficiary;
        _releaseTime = releaseTime;
    }

    /**
     * @return the token being held.
     */
    function token() public view returns (IERC20) {
        return _token;
    }

    /**
     * @return the beneficiary of the tokens.
     */
    function beneficiary() public view returns (address) {
        return _beneficiary;
    }

    /**
     * @return the time when the tokens are released.
     */
    function releaseTime() public view returns (uint256) {
        return _releaseTime;
    }

    /**
     * @notice Allows the beneficiary to be changed for future multi sig deploys or team structure changes
     */
    function changeBeneficiary(address newBeneficiary) external onlyOwner() {
        _beneficiary = newBeneficiary;
    }

    /**
     * @notice Transfers tokens held by timelock to beneficiary.
     */
    function release() public virtual {
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp >= _releaseTime, "TokenTimelock: current time is before release time");

        uint256 amount = _token.balanceOf(address(this));
        require(amount > 0, "TokenTimelock: no tokens to release");

        _token.safeTransfer(_beneficiary, amount);
    }
}

/* 
  A token timelock that is capable of interacting with other smart contracts.
  This allows the beneficiary to participate in on-chain goverance processes, despite having locked tokens.
  Features safety functions to allow beneficiary to claim ETH & ERC20-compliant tokens sent to the timelock contract, accidentially or otherwise.
  An optional 'governor' address has the ability to allow the timelock to send it's tokens to approved destinations. 
  This is intended to allow the token holder to stake their tokens in approved mechanisms.
*/

contract SmartTimelock is TokenTimelock, Executor, ReentrancyGuard {
    address internal _governor;
    mapping(address => bool) internal _transferAllowed;

    constructor(
        IERC20 token,
        address beneficiary,
        address governor,
        uint256 releaseTime
    ) TokenTimelock(token, beneficiary, releaseTime) public {
        _governor = governor;
    }

    event Call(address to, uint256 value, bytes data, bool transfersAllowed);
    event ApproveTransfer(address to);
    event RevokeTransfer(address to);
    event ClaimToken(IERC20 token, uint256 amount);
    event ClaimEther(uint256 amount);

    modifier onlyGovernor() {
        require(msg.sender == _governor, "smart-timelock/only-governor");
        _;
    }

    /**
     * @notice Allows the timelock to call arbitrary contracts, as long as it does not reduce it's locked token balance
     * @dev Initialization check is implicitly provided by `voteExists()` as new votes can only be
     *      created via `newVote(),` which requires initialization
     * @param to Contract address to call
     * @param value ETH value to send, if any
     * @param data Encoded data to send
     */
    function call(
        address to,
        uint256 value,
        bytes calldata data
    ) external payable onlyOwner() nonReentrant() returns (bool success) {
        uint256 preAmount = token().balanceOf(address(this));

        success = execute(to, value, data, gasleft());

        if (!_transferAllowed[to]) {
            uint256 postAmount = token().balanceOf(address(this));
            require(
                postAmount >= preAmount,
                "smart-timelock/locked-balance-check"
            );
        }

        emit Call(to, value, data, _transferAllowed[to]);
    }

    function approveTransfer(address to) external onlyGovernor() {
        _transferAllowed[to] = true;
        emit ApproveTransfer(to);
    }

    function revokeTransfer(address to) external onlyGovernor() {
        _transferAllowed[to] = false;
        emit RevokeTransfer(to);
    }

    /**
     * @notice Claim ERC20-compliant tokens other than locked token.
     * @param tokenToClaim Token to claim balance of.
     */
    function claimToken(IERC20 tokenToClaim)
        external
        onlyOwner()
        nonReentrant()
    {
        require(
            address(tokenToClaim) != address(token()),
            "smart-timelock/no-locked-token-claim"
        );
        uint256 preAmount = token().balanceOf(address(this));

        uint256 claimableTokenAmount = tokenToClaim.balanceOf(address(this));
        require(
            claimableTokenAmount > 0,
            "smart-timelock/no-token-balance-to-claim"
        );

        tokenToClaim.transfer(beneficiary(), claimableTokenAmount);

        uint256 postAmount = token().balanceOf(address(this));
        require(postAmount >= preAmount, "smart-timelock/locked-balance-check");

        emit ClaimToken(tokenToClaim, claimableTokenAmount);
    }

    /**
     * @notice Claim Ether in contract.
     */
    function claimEther() external onlyOwner() nonReentrant() {
        uint256 preAmount = token().balanceOf(address(this));

        uint256 etherToTransfer = address(this).balance;
        require(
            etherToTransfer > 0,
            "smart-timelock/no-ether-balance-to-claim"
        );

        payable(beneficiary()).transfer(etherToTransfer);

        uint256 postAmount = token().balanceOf(address(this));
        require(postAmount >= preAmount, "smart-timelock/locked-balance-check");

        emit ClaimEther(etherToTransfer);
    }

    /**
     * @notice Governor address
     */
    function governor() external view returns (address) {
        return _governor;
    }

    /**
     * @notice Allow timelock to receive Ether
     */
    receive() external payable {}
}
