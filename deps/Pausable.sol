// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.9;

import {Ownable} from "https://raw.githubusercontent.com/sharedStake-dev/badger-system/master/deps/%40openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Pausable
 * @dev Base contract which allows children to implement an emergency stop mechanism.
 * from https://github.com/FriendlyUser/solidity-smart-contracts//blob/v0.2.0/contracts/other/CredVert/Pausable.sol
 */
contract Pausable is Ownable {
    event Pause();
    event Unpause();

    bool public paused = false;

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     */
    modifier whenNotPaused() {
        require(!paused, "Pausable: Contract is paused and requires !paused");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     */
    modifier whenPaused() {
        require(paused, "Pausable: Contract is not paused but requires paused");
        _;
    }

    /**
     * @dev called by the owner to pause, triggers stopped state
     */
    function pause() public onlyOwner whenNotPaused {
        paused = true;
        emit Pause();
    }

    /**
     * @dev called by the owner to unpause, returns to normal state
     */
    function unpause() public onlyOwner whenPaused {
        paused = false;
        emit Unpause();
    }
}
