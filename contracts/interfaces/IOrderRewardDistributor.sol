// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "../LimitOrderProtocol.sol";

interface IOrderRewardDistributor {
    function distributeReward(
        LimitOrderProtocol.Order memory _order,
        address _rewardRecipient
    ) external;
}
