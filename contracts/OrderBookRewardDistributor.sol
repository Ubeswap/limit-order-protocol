// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./interfaces/IOrderRewardDistributor.sol";
import "./OrderBook.sol";
import "./helpers/Whitelistable.sol";

/// @title Public Ubeswap order book
contract OrderBookRewardDistributor is
    IOrderRewardDistributor,
    Ownable,
    Whitelistable
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /// @notice Denominator for fee and rewardRate
    uint256 public constant PCT_DENOMINATOR = 1_000_000;

    /// @notice Currency which rewards are paid out in
    IERC20 public rewardCurrency;
    /// @notice Mapping of each makerToken's reward rate
    mapping(address => uint256) public rewardRate;

    event RewardCurrencyChanged(
        address oldRewardCurrency,
        address newRewardCurrency
    );
    event RewardRateChanged(
        address token,
        uint256 oldRewardRate,
        uint256 newRewardRate
    );
    event ERC20Rescued(address token, uint256 amount);

    constructor(IERC20 _rewardCurrency) {
        rewardCurrency = _rewardCurrency;
    }

    /// @notice Admin function to change the Reward rate for a makerToken
    /// @param _token The makerToken
    /// @param _rewardRate The new Reward rate
    function changeRewardRate(address _token, uint256 _rewardRate)
        external
        onlyOwner
    {
        // solhint-disable-next-line reason-string
        require(
            _rewardRate <= PCT_DENOMINATOR,
            "UOB: rewardRate exceeds PCT_DENOMINATOR"
        );
        emit RewardRateChanged(_token, rewardRate[_token], _rewardRate);
        rewardRate[_token] = _rewardRate;
    }

    /// @notice Admin function to change the Reward currency
    /// @param _rewardCurrency The new Reward currency
    function changeRewardCurrency(IERC20 _rewardCurrency) external onlyOwner {
        emit RewardCurrencyChanged(
            address(rewardCurrency),
            address(_rewardCurrency)
        );
        rewardCurrency = _rewardCurrency;
    }

    /// @notice Admin function to rescue any ERC20 tokens in the contract
    /// @param _token The currency to rescue
    function rescueERC20(IERC20 _token, uint256 _amount) external onlyOwner {
        emit ERC20Rescued(address(_token), _amount);
        _token.safeTransfer(msg.sender, _amount);
    }

    function distributeReward(
        LimitOrderProtocol.Order memory _order,
        address _rewardRecipient
    ) public onlyWhitelist {
        uint256 rewardAmount = _order
            .makingAmount
            .mul(rewardRate[_order.makerAsset])
            .div(PCT_DENOMINATOR);
        if (
            rewardAmount > 0 &&
            address(rewardCurrency) != address(0) &&
            rewardCurrency.balanceOf(address(this)) >= rewardAmount
        ) {
            rewardCurrency.safeTransfer(_rewardRecipient, rewardAmount);
        }
    }
}
