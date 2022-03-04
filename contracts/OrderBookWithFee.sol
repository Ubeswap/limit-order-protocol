// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./OrderBook.sol";

/// @title Public order book with fees
contract OrderBookWithFee is OrderBook {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /// @notice Denominator for the fee
    uint256 public constant FEE_DENOMINATOR = 1_000_000;

    // solhint-disable-next-line no-empty-blocks
    constructor(LimitOrderProtocol _limitOrderProtocol) OrderBook(_limitOrderProtocol) {}

    function broadcastOrder(
        LimitOrderProtocol.Order memory _order,
        bytes calldata _signature,
        uint256 _fee,
        address _feeRecipient
    ) public {
        require(_feeRecipient != address(0), "OBWF: Invalid fee recipient");
        uint256 feeAmount = _fee.mul(_order.makingAmount).div(FEE_DENOMINATOR);
        if (feeAmount > 0) {
            IERC20(_order.makerAsset).safeTransferFrom(
                msg.sender,
                _feeRecipient,
                feeAmount
            );
        }
        _broadcastOrder(_order, _signature);
    }
}
