// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "../LimitOrderProtocol.sol";

interface IOrderNotificationReceiver {
    function notifyOrderBroadcasted(
        LimitOrderProtocol.Order memory _order,
        address _caller
    ) external;
}
