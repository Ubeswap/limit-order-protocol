// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./LimitOrderProtocol.sol";

/// @title Public order book for OrderRFQ
contract OrderRFQBook is EIP712("Ubeswap Limit Order Protocol", "2") {
    /// @notice The limit order protocol this orderbook references
    LimitOrderProtocol public immutable limitOrderProtocol;

    /// @notice Mapping from order hash to an OrderRFQ
    mapping(bytes32 => LimitOrderProtocol.OrderRFQ) public orderRFQs;
    /// @notice Mapping from order hash to an OrderRFQ's signature
    mapping(bytes32 => bytes) public signatures;

    /// @notice Emitted every time an order is broadcasted
    event OrderBroadcastedRFQ(address indexed maker, bytes32 orderHash);

    constructor(LimitOrderProtocol _limitOrderProtocol) {
        limitOrderProtocol = _limitOrderProtocol;
    }

    /// @notice Broadcast a limit order with its signature
    /// @param _order The order to broadcast
    /// @param _signature The order's signature. Should be signed by _order.maker
    function broadcastOrderRFQ(
        LimitOrderProtocol.OrderRFQ memory _order,
        bytes calldata _signature
    ) external {
        bytes32 orderHash = limitOrderProtocol.hashOrderRFQ(_order);
        require(SignatureChecker.isValidSignatureNow(_order.maker, orderHash, _signature), "OB: bad signature");
        orderRFQs[orderHash] = _order;
        signatures[orderHash] = _signature;
        emit OrderBroadcastedRFQ(_order.maker, orderHash);
    }

    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns(bytes32) {
        return _domainSeparatorV4();
    }
}

