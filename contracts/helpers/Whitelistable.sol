// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract Whitelistable is Ownable {
    mapping(address => bool) public whitelist;

    event AddedToWhitelist(address user);
    event RemovedFromWhitelist(address user);

    modifier onlyWhitelist() {
        // solhint-disable-next-line reason-string
        require(whitelist[msg.sender], "Whitelistable: caller not whitelisted");
        _;
    }

    function addToWhitelist(address _user) external onlyOwner {
        whitelist[_user] = true;
        emit AddedToWhitelist(_user);
    }

    function removeFromWhitelist(address _user) external onlyOwner {
        whitelist[_user] = false;
        emit RemovedFromWhitelist(_user);
    }
}

