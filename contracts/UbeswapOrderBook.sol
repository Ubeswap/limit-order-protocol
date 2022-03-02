// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./OrderBook.sol";

/// @title Public Ubeswap order book
contract UbeswapOrderBook is OrderBook, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /// @notice Denominator for bps
    uint256 public constant BPS = 1000;

    /// @notice Fee in bps for broadcasting an order
    uint256 public fee;

    /// @notice Fee recipient
    address public feeRecipient;

    event FeeChanged(uint256 oldFee, uint256 newFee);
    event FeeRecipientChanged(address oldFee, address newFee);

    constructor(
        ILimitOrderProtocol _limitOrderProtocol,
        uint256 _fee,
        address _feeRecipient
    ) OrderBook(_limitOrderProtocol) {
        fee = _fee;
        feeRecipient = _feeRecipient;
    }

    function changeFee(uint256 _fee) external onlyOwner {
        emit FeeChanged(fee, _fee);
        fee = _fee;
    }

    function changeFeeRecipient(address _feeRecipient) external onlyOwner {
        emit FeeRecipientChanged(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    function broadcastOrder(
        ILimitOrderProtocol.Order memory _order,
        bytes calldata _signature
    ) public override {
        if (feeRecipient != address(0) && fee > 0) {
            uint256 feeAmount = fee.mul(_order.makingAmount).div(BPS);
            if (feeAmount > 0) {
                IERC20(_order.makerAsset).safeTransferFrom(
                    msg.sender,
                    feeRecipient,
                    feeAmount
                );
            }
        }
        super.broadcastOrder(_order, _signature);
    }
}
