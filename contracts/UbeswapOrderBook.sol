// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./interfaces/IOrderRewardDistributor.sol";
import "./OrderBook.sol";

/// @title Public Ubeswap order book
contract UbeswapOrderBook is OrderBook, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /// @notice Maximum fee is 10 bps
    uint256 public constant MAX_FEE = 1_000;
    /// @notice Denominator for fee and subsidyRate
    uint256 public constant PCT_DENOMINATOR = 1_000_000;

    /// @notice Fee for broadcasting an order. In units of PCT_DENOMINATOR
    uint256 public fee;

    /// @notice Fee recipient
    address public feeRecipient;

    /// @notice Reward distributor module
    IOrderRewardDistributor public rewardDistributor;

    event FeeChanged(uint256 oldFee, uint256 newFee);
    event FeeRecipientChanged(address oldFeeRecipient, address newFeeRecipient);
    event RewardDistributorChanged(
        address oldRewardDistributor,
        address newRewardDistributor
    );

    constructor(
        LimitOrderProtocol _limitOrderProtocol,
        uint256 _fee,
        address _feeRecipient,
        IOrderRewardDistributor _rewardDistributor
    ) OrderBook(_limitOrderProtocol) {
        require(_fee <= MAX_FEE, "UOB: Fee exceeds MAX_FEE");
        fee = _fee;
        feeRecipient = _feeRecipient;
        rewardDistributor = _rewardDistributor;
    }

    /// @notice Admin function to change the fee rate
    /// @param _fee The new fee
    function changeFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_FEE, "UOB: Fee exceeds MAX_FEE");
        emit FeeChanged(fee, _fee);
        fee = _fee;
    }

    /// @notice Admin function to change the fee recipient
    /// @param _feeRecipient The new fee recipient
    function changeFeeRecipient(address _feeRecipient) external onlyOwner {
        emit FeeRecipientChanged(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    /// @notice Admin function to change the reward distributor contract
    /// @param _rewardDistributor The new reward distributor. 0 address will disable rewards
    function changeRewardDistributor(IOrderRewardDistributor _rewardDistributor)
        external
        onlyOwner
    {
        emit RewardDistributorChanged(
            address(rewardDistributor),
            address(_rewardDistributor)
        );
        rewardDistributor = _rewardDistributor;
    }

    function broadcastOrder(
        LimitOrderProtocol.Order memory _order,
        bytes calldata _signature
    ) public {
        if (feeRecipient != address(0) && fee > 0) {
            uint256 feeAmount = _order.makingAmount.mul(fee).div(
                PCT_DENOMINATOR
            );
            if (feeAmount > 0) {
                IERC20(_order.makerAsset).safeTransferFrom(
                    msg.sender,
                    feeRecipient,
                    feeAmount
                );
            }

            if (address(rewardDistributor) != address(0)) {
                rewardDistributor.distributeReward(_order, msg.sender);
            }
        }
        _broadcastOrder(_order, _signature);
    }
}
