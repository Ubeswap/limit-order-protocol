// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import "./LimitOrderProtocol.sol";

/// @title Internal base OrderBook
abstract contract OrderBook {
    /// @notice The limit order protocol this orderbook references
    LimitOrderProtocol public immutable limitOrderProtocol;

    /// @notice Mapping of all broadcasted order hashes
    mapping(bytes32 => bool) public broadcastedOrderHashes;

    /// @notice Emitted every time an order is broadcasted
    event OrderBroadcasted(
        address indexed maker,
        bytes32 indexed orderHash,
        LimitOrderProtocol.Order order,
        bytes signature
    );

    constructor(LimitOrderProtocol _limitOrderProtocol) {
        limitOrderProtocol = _limitOrderProtocol;
    }

    /// @notice Broadcast a limit order with its signature
    /// @param _order The order to broadcast
    /// @param _signature The order's signature. Should be signed by _order.maker
    function _broadcastOrder(
        LimitOrderProtocol.Order memory _order,
        bytes calldata _signature
    ) internal {
        bytes32 orderHash = limitOrderProtocol.hashOrder(_order);
        require(
            !broadcastedOrderHashes[orderHash],
            "OB: Order already broadcasted"
        );
        require(
            SignatureChecker.isValidSignatureNow(
                _order.maker,
                orderHash,
                _signature
            ),
            "OB: bad signature"
        );
        broadcastedOrderHashes[orderHash] = true;

        emit OrderBroadcasted(_order.maker, orderHash, _order, _signature);
    }
}
