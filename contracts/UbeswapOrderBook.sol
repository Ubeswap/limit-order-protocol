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
    /// @notice Denominator for fee and subsidyRate
    uint256 public constant PCT_DENOMINATOR = 1_000_000;

    /// @notice Fee for broadcasting an order. In units of PCT_DENOMINATOR
    uint256 public fee;

    /// @notice Currency which subsidies are paid out in
    IERC20 public subsidyCurrency;
    /// @notice Mapping of each makerToken's subsidy rate
    mapping(address => uint256) public subsidyRate;

    /// @notice Fee recipient
    address public feeRecipient;

    event FeeChanged(uint256 oldFee, uint256 newFee);
    event FeeRecipientChanged(address oldFeeRecipient, address newFeeRecipient);
    event SubsidyCurrencyChanged(
        address oldSubsidyCurrency,
        address newSubsidyCurrency
    );
    event SubsidyRateChanged(
        address token,
        uint256 oldSubsidyRate,
        uint256 newSubsidyRate
    );
    event ERC20Rescued(address token, uint256 amount);

    constructor(
        LimitOrderProtocol _limitOrderProtocol,
        uint256 _fee,
        address _feeRecipient,
        IERC20 _subsidyCurrency
    ) OrderBook(_limitOrderProtocol) {
        require(_fee <= MAX_FEE, "UOB: Fee exceeds MAX_FEE");
        fee = _fee;
        feeRecipient = _feeRecipient;
        subsidyCurrency = _subsidyCurrency;
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

    /// @notice Admin function to change the subsidy rate for a makerToken
    /// @param _token The makerToken
    /// @param _subsidyRate The new subsidy rate
    function changeSubsidyRate(address _token, uint256 _subsidyRate)
        external
        onlyOwner
    {
        // solhint-disable-next-line reason-string
        require(
            _subsidyRate <= PCT_DENOMINATOR,
            "UOB: Subsidy exceeds PCT_DENOMINATOR"
        );
        emit SubsidyRateChanged(_token, subsidyRate[_token], _subsidyRate);
        subsidyRate[_token] = _subsidyRate;
    }

    /// @notice Admin function to change the subsidy currency
    /// @param _subsidyCurrency The new subsidy currency
    function changeSubsidyCurrency(IERC20 _subsidyCurrency) external onlyOwner {
        emit SubsidyCurrencyChanged(
            address(subsidyCurrency),
            address(_subsidyCurrency)
        );
        subsidyCurrency = _subsidyCurrency;
    }

    /// @notice Admin function to rescue any ERC20 tokens in the contract
    /// @param _token The currency to rescue
    function rescueERC20(IERC20 _token, uint256 _amount) external onlyOwner {
        emit ERC20Rescued(address(_token), _amount);
        _token.safeTransfer(msg.sender, _amount);
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
            uint256 subsidyAmount = _order
                .makingAmount
                .mul(subsidyRate[_order.makerAsset])
                .div(PCT_DENOMINATOR);
            if (
                subsidyAmount > 0 &&
                address(subsidyCurrency) != address(0) &&
                subsidyCurrency.balanceOf(address(this)) >= subsidyAmount
            ) {
                subsidyCurrency.safeTransfer(msg.sender, subsidyAmount);
            }
        }
        _broadcastOrder(_order, _signature);
    }
}
