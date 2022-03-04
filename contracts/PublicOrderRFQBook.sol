// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./OrderRFQBook.sol";

/// @title Public order book for OrderRFQ
contract PublicOrderRFQBook is OrderRFQBook {

    // solhint-disable-next-line no-empty-blocks
    constructor(LimitOrderProtocol _limitOrderProtocol) OrderRFQBook(_limitOrderProtocol) {}

    /// @notice Broadcast a limit order with its signature
    /// @param _order The order to broadcast
    /// @param _signature The order's signature. Should be signed by _order.maker
    function broadcastOrderRFQ(
        LimitOrderProtocol.OrderRFQ memory _order,
        bytes calldata _signature
    ) external {
        _broadcastOrderRFQ(_order, _signature);
    }
}
