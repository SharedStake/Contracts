pragma solidity =0.6.11;

/**
 * @title MultiSendERC20
 * @notice Send ERC20 tokens to multiple recipients in a single transaction
 * @dev Saves gas by batching multiple transfer calls
 * 
 * Inspired by: https://etherscan.io/tx/0xb19d20b422df26b50775358f64234e8d45d6d96befddfa8cd77ceefa568eb9fb
 * 
 * Usage:
 * 1. Approve this contract to spend your tokens: token.approve(multisendAddress, totalAmount)
 * 2. Call multiSend(token, recipients, amounts)
 */

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract MultiSendERC20 {
    address public owner;
    
    event MultiTransfer(
        address indexed token,
        address indexed sender,
        uint256 recipientCount,
        uint256 totalAmount
    );
    
    event TransferFailed(
        address indexed token,
        address indexed recipient,
        uint256 amount,
        string reason
    );
    
    modifier onlyOwner() {
        require(msg.sender == owner, "MultiSend: not owner");
        _;
    }
    
    constructor() public {
        owner = msg.sender;
    }
    
    /**
     * @notice Transfer ownership of the contract
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "MultiSend: zero address");
        owner = newOwner;
    }
    
    /**
     * @notice Send tokens to multiple recipients
     * @param token The ERC20 token address
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts (same length as recipients)
     * @dev Requires approval of total amount before calling
     */
    function multiSend(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external returns (bool) {
        require(token != address(0), "MultiSend: invalid token");
        require(recipients.length > 0, "MultiSend: empty recipients");
        require(recipients.length == amounts.length, "MultiSend: length mismatch");
        
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            require(recipients[i] != address(0), "MultiSend: zero address recipient");
            require(amounts[i] > 0, "MultiSend: zero amount");
            totalAmount += amounts[i];
        }
        
        require(totalAmount > 0, "MultiSend: total amount zero");
        
        IERC20 tokenContract = IERC20(token);
        uint256 allowance = tokenContract.allowance(msg.sender, address(this));
        require(allowance >= totalAmount, "MultiSend: insufficient allowance");
        
        for (uint256 i = 0; i < recipients.length; i++) {
            require(
                tokenContract.transferFrom(msg.sender, recipients[i], amounts[i]),
                "MultiSend: transfer failed"
            );
        }
        
        emit MultiTransfer(token, msg.sender, recipients.length, totalAmount);
        return true;
    }
    
    /**
     * @notice Send tokens (safe version - skips failed transfers)
     * @param token The ERC20 token address
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts (same length as recipients)
     * @dev Continues even if individual transfers fail, emits event for each failure
     */
    function multiSendSafe(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external returns (uint256 successCount) {
        require(token != address(0), "MultiSend: invalid token");
        require(recipients.length > 0, "MultiSend: empty recipients");
        require(recipients.length == amounts.length, "MultiSend: length mismatch");
        
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        
        IERC20 tokenContract = IERC20(token);
        uint256 balanceBefore = tokenContract.balanceOf(address(this));
        
        // Pull all tokens at once
        require(
            tokenContract.transferFrom(msg.sender, address(this), totalAmount),
            "MultiSend: pull failed"
        );
        
        for (uint256 i = 0; i < recipients.length; i++) {
            (bool success, bytes memory data) = address(tokenContract).call(
                abi.encodeWithSelector(
                    IERC20.transfer.selector,
                    recipients[i],
                    amounts[i]
                )
            );
            
            if (success && data.length > 0 && abi.decode(data, (bool))) {
                successCount++;
            } else {
                emit TransferFailed(token, recipients[i], amounts[i], "transfer failed");
            }
        }
        
        // Return remaining tokens (from failed transfers) to sender
        uint256 remaining = tokenContract.balanceOf(address(this));
        if (remaining > 0) {
            tokenContract.transfer(msg.sender, remaining);
        }
        
        emit MultiTransfer(token, msg.sender, successCount, totalAmount - remaining);
        return successCount;
    }
    
    /**
     * @notice Withdraw accidentally sent tokens
     */
    function withdrawToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner, amount);
    }
    
    /**
     * @notice Withdraw accidentally sent ETH
     */
    function withdrawETH() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
    
    receive() external payable {}
}
