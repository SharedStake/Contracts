// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MultiSend is Ownable {
    event MultiTransfer(address indexed token, uint256 totalSent, uint256 recipients);

    function multiSendToken(address token, address[] calldata recipients, uint256[] calldata amounts) external onlyOwner {
        require(recipients.length == amounts.length, "MULTISEND: length mismatch");
        IERC20 t = IERC20(token);
        uint256 total = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            total += amounts[i];
            require(t.transferFrom(msg.sender, recipients[i], amounts[i]), "MULTISEND: transfer failed");
        }
        emit MultiTransfer(token, total, recipients.length);
    }
}