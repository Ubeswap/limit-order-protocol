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

    /// @notice Maximum fee is 10 bps
    uint256 public constant MAX_FEE = 1_000;
    /// @notice Denominator for the fee
    uint256 public constant FEE_DENOMINATOR = 1_000_000;

    /// @notice Fee for broadcasting an order. Always divided by FEE_DENOMINATOR
    uint256 public fee;

    /// @notice Fee recipient
    address public feeRecipient;

    event FeeChanged(uint256 oldFee, uint256 newFee);
    event FeeRecipientChanged(address oldFeeRecipient, address newFeeRecipient);

    constructor(
        LimitOrderProtocol _limitOrderProtocol,
        uint256 _fee,
        address _feeRecipient
    ) OrderBook(_limitOrderProtocol) {
        require(_fee <= MAX_FEE, "UOB: Fee exceeds MAX_FEE");
        fee = _fee;
        feeRecipient = _feeRecipient;
    }

    function changeFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_FEE, "UOB: Fee exceeds MAX_FEE");
        emit FeeChanged(fee, _fee);
        fee = _fee;
    }

    function changeFeeRecipient(address _feeRecipient) external onlyOwner {
        emit FeeRecipientChanged(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    function broadcastOrder(
        LimitOrderProtocol.Order memory _order,
        bytes calldata _signature
    ) public {
        if (feeRecipient != address(0) && fee > 0) {
            uint256 feeAmount = _order.makingAmount.mul(fee).div(FEE_DENOMINATOR);
            if (feeAmount > 0) {
                IERC20(_order.makerAsset).safeTransferFrom(
                    msg.sender,
                    feeRecipient,
                    feeAmount
                );
            }
        }
        _broadcastOrder(_order, _signature);
    }
}
