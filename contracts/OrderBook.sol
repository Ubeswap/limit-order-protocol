// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

interface ILimitOrderProtocol {
    // Imported from OrderMixin
    struct Order {
        uint256 salt;
        address makerAsset;
        address takerAsset;
        address maker;
        address receiver;
        address allowedSender; // equals to Zero address on public orders
        uint256 makingAmount;
        uint256 takingAmount;
        bytes makerAssetData;
        bytes takerAssetData;
        bytes getMakerAmount; // this.staticcall(abi.encodePacked(bytes, swapTakerAmount)) => (swapMakerAmount)
        bytes getTakerAmount; // this.staticcall(abi.encodePacked(bytes, swapMakerAmount)) => (swapTakerAmount)
        bytes predicate; // this.staticcall(bytes) => (bool)
        bytes permit; // On first fill: permit.1.call(abi.encodePacked(permit.selector, permit.2))
        bytes interaction;
    }

    function hashOrder(Order memory order) external view returns (bytes32);
}

/// @title Public order book for Order
// solhint-disable-next-line max-states-count
contract OrderBook {
    /// @notice The limit order protocol this orderbook references
    ILimitOrderProtocol public immutable limitOrderProtocol;

    /// @notice Mapping from order hash to an Order's signature
    mapping(bytes32 => bytes) public signatures;

    // Deconstructed mappings for an Order
    mapping(bytes32 => uint256) internal _salts;
    mapping(bytes32 => address) internal _makerAssets;
    mapping(bytes32 => address) internal _takerAssets;
    mapping(bytes32 => address) internal _makers;
    mapping(bytes32 => address) internal _receivers;
    mapping(bytes32 => address) internal _allowedSenders;
    mapping(bytes32 => uint256) internal _makingAmounts;
    mapping(bytes32 => uint256) internal _takingAmounts;
    mapping(bytes32 => bytes) internal _makerAssetDatas;
    mapping(bytes32 => bytes) internal _takerAssetDatas;
    mapping(bytes32 => bytes) internal _getMakerAmounts;
    mapping(bytes32 => bytes) internal _getTakerAmounts;
    mapping(bytes32 => bytes) internal _predicates;
    mapping(bytes32 => bytes) internal _permits;
    mapping(bytes32 => bytes) internal _interactions;

    /// @notice Emitted every time an order is broadcasted
    event OrderBroadcasted(address indexed maker, bytes32 orderHash);

    constructor(ILimitOrderProtocol _limitOrderProtocol) {
        limitOrderProtocol = _limitOrderProtocol;
    }

    /// @notice Broadcast a limit order with its signature
    /// @param _order The order to broadcast
    /// @param _signature The order's signature. Should be signed by _order.maker
    function _broadcastOrder(
        ILimitOrderProtocol.Order memory _order,
        bytes calldata _signature
    ) internal virtual {
        bytes32 orderHash = limitOrderProtocol.hashOrder(_order);
        require(
            SignatureChecker.isValidSignatureNow(
                _order.maker,
                orderHash,
                _signature
            ),
            "OB: bad signature"
        );

        _salts[orderHash] = _order.salt;
        _makerAssets[orderHash] = _order.makerAsset;
        _takerAssets[orderHash] = _order.takerAsset;
        _makers[orderHash] = _order.maker;
        _receivers[orderHash] = _order.receiver;
        _allowedSenders[orderHash] = _order.allowedSender;
        _makingAmounts[orderHash] = _order.makingAmount;
        _takingAmounts[orderHash] = _order.takingAmount;
        _makerAssetDatas[orderHash] = _order.makerAssetData;
        _takerAssetDatas[orderHash] = _order.takerAssetData;
        _getMakerAmounts[orderHash] = _order.getMakerAmount;
        _getTakerAmounts[orderHash] = _order.getTakerAmount;
        _predicates[orderHash] = _order.predicate;
        _permits[orderHash] = _order.permit;
        _interactions[orderHash] = _order.interaction;

        signatures[orderHash] = _signature;
        emit OrderBroadcasted(_order.maker, orderHash);
    }

    /// @notice Get a broadcasted order
    /// @param _orderHash An order's hash to fetch the underlying order
    /// @return order The order that corresponds to the _orderHash
    function orders(bytes32 _orderHash)
        external
        view
        returns (ILimitOrderProtocol.Order memory order)
    {
        order = ILimitOrderProtocol.Order({
            salt: _salts[_orderHash],
            makerAsset: _makerAssets[_orderHash],
            takerAsset: _takerAssets[_orderHash],
            maker: _makers[_orderHash],
            receiver: _receivers[_orderHash],
            allowedSender: _allowedSenders[_orderHash],
            makingAmount: _makingAmounts[_orderHash],
            takingAmount: _takingAmounts[_orderHash],
            makerAssetData: _makerAssetDatas[_orderHash],
            takerAssetData: _takerAssetDatas[_orderHash],
            getMakerAmount: _getMakerAmounts[_orderHash],
            getTakerAmount: _getTakerAmounts[_orderHash],
            predicate: _predicates[_orderHash],
            permit: _permits[_orderHash],
            interaction: _interactions[_orderHash]
        });
    }
}
