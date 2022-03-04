// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./LimitOrderProtocol.sol";

/// @title Internal order book for OrderRFQ
abstract contract OrderRFQBook {
    /// @notice The limit order protocol this orderbook references
    LimitOrderProtocol public immutable limitOrderProtocol;

    /// @notice Emitted every time an order is broadcasted
    event OrderBroadcastedRFQ(
        address indexed maker,
        bytes32 orderHash,
        LimitOrderProtocol.OrderRFQ order,
        bytes signature
    );

    constructor(LimitOrderProtocol _limitOrderProtocol) {
        limitOrderProtocol = _limitOrderProtocol;
    }

    /// @notice Broadcast a limit order with its signature
    /// @param _order The order to broadcast
    /// @param _signature The order's signature. Should be signed by _order.maker
    function _broadcastOrderRFQ(
        LimitOrderProtocol.OrderRFQ memory _order,
        bytes calldata _signature
    ) internal {
        bytes32 orderHash = limitOrderProtocol.hashOrderRFQ(_order);
        require(SignatureChecker.isValidSignatureNow(_order.maker, orderHash, _signature), "OB: bad signature");
        emit OrderBroadcastedRFQ(_order.maker, orderHash, _order, _signature);
    }
}
