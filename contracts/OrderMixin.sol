// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./helpers/AmountCalculator.sol";
import "./helpers/ChainlinkCalculator.sol";
import "./helpers/NonceManager.sol";
import "./helpers/PredicateHelper.sol";
import "./interfaces/InteractiveNotificationReceiver.sol";
import "./libraries/ArgumentsDecoder.sol";
import "./libraries/Permitable.sol";

/// @title Regular Limit Order mixin
abstract contract OrderMixin is
    EIP712,
    AmountCalculator,
    ChainlinkCalculator,
    NonceManager,
    PredicateHelper,
    Permitable
{
    using Address for address;
    using ArgumentsDecoder for bytes;

    /// @notice Emitted every time order gets filled, including partial fills
    event OrderFilled(
        address indexed maker,
        bytes32 orderHash,
        uint256 remaining
    );

    /// @notice Emitted when order gets cancelled
    event OrderCanceled(
        address indexed maker,
        bytes32 orderHash,
        uint256 remainingRaw
    );

    // Fixed-size order part with core information
    struct StaticOrder {
        uint256 salt;
        address makerAsset;
        address takerAsset;
        address maker;
        address receiver;
        address allowedSender;  // equals to Zero address on public orders
        uint256 makingAmount;
        uint256 takingAmount;
    }

    // `StaticOrder` extension including variable-sized additional order meta information
    struct Order {
        uint256 salt;
        address makerAsset;
        address takerAsset;
        address maker;
        address receiver;
        address allowedSender;  // equals to Zero address on public orders
        uint256 makingAmount;
        uint256 takingAmount;
        bytes makerAssetData;
        bytes takerAssetData;
        bytes getMakerAmount; // this.staticcall(abi.encodePacked(bytes, swapTakerAmount)) => (swapMakerAmount)
        bytes getTakerAmount; // this.staticcall(abi.encodePacked(bytes, swapMakerAmount)) => (swapTakerAmount)
        bytes predicate;      // this.staticcall(bytes) => (bool)
        bytes permit;         // On first fill: permit.1.call(abi.encodePacked(permit.selector, permit.2))
        bytes interaction;
    }

    bytes32 constant public LIMIT_ORDER_TYPEHASH = keccak256(
        "Order(uint256 salt,address makerAsset,address takerAsset,address maker,address receiver,address allowedSender,uint256 makingAmount,uint256 takingAmount,bytes makerAssetData,bytes takerAssetData,bytes getMakerAmount,bytes getTakerAmount,bytes predicate,bytes permit,bytes interaction)"
    );
    uint256 constant private _ORDER_DOES_NOT_EXIST = 0;
    uint256 constant private _ORDER_FILLED = 1;

    // Used to pack these values into an array (Stack to deep)
    uint256 constant private _MAKING_AMOUNT = 0;
    uint256 constant private _TAKING_AMOUNT = 1;
    uint256 constant private _THRESHOLD_AMOUNT = 2;

    /// @notice Stores unfilled amounts for each order plus one.
    /// Therefore 0 means order doesn't exist and 1 means order was filled
    mapping(bytes32 => uint256) private _remaining;

    /// @notice Returns unfilled amount for order. Throws if order does not exist
    function remaining(bytes32 orderHash) external view returns(uint256) {
        uint256 amount = _remaining[orderHash];
        require(amount != _ORDER_DOES_NOT_EXIST, "LOP: Unknown order");
        unchecked { amount -= 1; }
        return amount;
    }

    /// @notice Returns unfilled amount for order
    /// @return Result Unfilled amount of order plus one if order exists. Otherwise 0
    function remainingRaw(bytes32 orderHash) external view returns(uint256) {
        return _remaining[orderHash];
    }

    /// @notice Same as `remainingRaw` but for multiple orders
    function remainingsRaw(bytes32[] memory orderHashes) external view returns(uint256[] memory) {
        uint256[] memory results = new uint256[](orderHashes.length);
        for (uint256 i = 0; i < orderHashes.length; i++) {
            results[i] = _remaining[orderHashes[i]];
        }
        return results;
    }

    /**
     * @notice Calls every target with corresponding data. Then reverts with CALL_RESULTS_0101011 where zeroes and ones
     * denote failure or success of the corresponding call
     * @param targets Array of addresses that will be called
     * @param data Array of data that will be passed to each call
     */
    function simulateCalls(address[] calldata targets, bytes[] calldata data) external {
        require(targets.length == data.length, "LOP: array size mismatch");
        bytes memory reason = new bytes(targets.length);
        for (uint256 i = 0; i < targets.length; i++) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, bytes memory result) = targets[i].call(data[i]);
            if (success && result.length > 0) {
                success = result.length == 32 && result.decodeBool();
            }
            reason[i] = success ? bytes1("1") : bytes1("0");
        }

        // Always revert and provide per call results
        revert(string(abi.encodePacked("CALL_RESULTS_", reason)));
    }

    /// @notice Cancels order by setting remaining amount to zero
    function cancelOrder(Order memory order) external {
        require(order.maker == msg.sender, "LOP: Access denied");

        bytes32 orderHash = hashOrder(order);
        uint256 orderRemaining = _remaining[orderHash];
        require(orderRemaining != _ORDER_FILLED, "LOP: already filled");
        emit OrderCanceled(msg.sender, orderHash, orderRemaining);
        _remaining[orderHash] = _ORDER_FILLED;
    }

    /// @notice Fills an order. If one doesn't exist (first fill) it will be created using order.makerAssetData
    /// @param order Order quote to fill
    /// @param signature Signature to confirm quote ownership
    /// @param amounts [Making amount, Taking amount, Threshold amount]
    function fillOrder(
        Order memory order,
        bytes calldata signature,
        uint256[3] memory amounts
    ) external returns(uint256 /* actualMakingAmount */, uint256 /* actualTakingAmount */) {
        return _fillOrderTo(order, signature, amounts, msg.sender, new bytes(0));
    }

    /// @notice Same as `fillOrder` but calls permit first,
    /// allowing to approve token spending and make a swap in one transaction.
    /// Also allows to specify funds destination instead of `msg.sender`
    /// @param order Order quote to fill
    /// @param signature Signature to confirm quote ownership
    /// @param amounts [Making amount, Taking amount, Threshold amount]
    /// @param target Address that will receive swap funds
    /// @param permit Should consist of abiencoded token address and encoded `IERC20Permit.permit` call.
    /// @dev See tests for examples
    function fillOrderToWithPermit(
        Order memory order,
        bytes calldata signature,
        uint256[3] memory amounts,
        address target,
        bytes calldata permit
    ) external returns(uint256 /* actualMakingAmount */, uint256 /* actualTakingAmount */) {
        require(permit.length >= 20, "LOP: permit length too low");
        (address token, bytes calldata permitData) = permit.decodeTargetAndData();
        _permit(token, permitData);
        return _fillOrderTo(order, signature, amounts, target, new bytes(0));
    }

    /// @notice Same as `fillOrderTo` but allows for additional interaction between asset transfers
    /// @param order Order quote to fill
    /// @param signature Signature to confirm quote ownership
    /// @param amounts [Making amount, Taking amount, Threshold amount]
    /// @param target Address that will receive swap funds
    /// @param extraInteraction Address that will receive swap funds
    function fillOrderWithExtraInteraction(
        Order memory order,
        bytes calldata signature,
        uint256[3] memory amounts,
        address target,
        bytes calldata extraInteraction
    ) public returns(uint256 /* actualMakingAmount */, uint256 /* actualTakingAmount */) {
        return _fillOrderTo(
            order,
            signature,
            amounts,
            target,
            extraInteraction
        );
    }

    /// @notice Same as `fillOrder` but allows to specify funds destination instead of `msg.sender`
    /// @param order Order quote to fill
    /// @param signature Signature to confirm quote ownership
    /// @param amounts [Making amount, Taking amount, Threshold amount]
    /// @param target Address that will receive swap funds
    function fillOrderTo(
        Order memory order,
        bytes calldata signature,
        uint256[3] memory amounts,
        address target
    ) public returns(uint256 /* actualMakingAmount */, uint256 /* actualTakingAmount */) {
        return _fillOrderTo(
            order,
            signature,
            amounts,
            target,
            new bytes(0)
        );
    }

    /// @notice Same as `fillOrder` but allows to specify funds destination instead of `msg.sender`
    /// @param order Order quote to fill
    /// @param signature Signature to confirm quote ownership
    /// @param amounts [Making amount, Taking amount, Threshold amount]
    /// @param target Address that will receive swap funds
    /// @param extraInteraction If specified, will add interaction between asset transfers
    function _fillOrderTo(
        Order memory order,
        bytes calldata signature,
        uint256[3] memory amounts,
        address target,
        bytes memory extraInteraction
    ) internal returns(uint256 /* actualMakingAmount */, uint256 /* actualTakingAmount */) {
        require(target != address(0), "LOP: zero target is forbidden");
        bytes32 orderHash = hashOrder(order);

        {  // Stack too deep
            uint256 remainingMakerAmount = _remaining[orderHash];
            require(remainingMakerAmount != _ORDER_FILLED, "LOP: remaining amount is 0");
            require(order.allowedSender == address(0) || order.allowedSender == msg.sender, "LOP: private order");
            if (remainingMakerAmount == _ORDER_DOES_NOT_EXIST) {
                // First fill: validate order and permit maker asset
                require(SignatureChecker.isValidSignatureNow(order.maker, orderHash, signature), "LOP: bad signature");
                remainingMakerAmount = order.makingAmount;
                if (order.permit.length >= 20) {
                    // proceed only if permit length is enough to store address
                    (address token, bytes memory permit) = order.permit.decodeTargetAndCalldata();
                    _permitMemory(token, permit);
                    require(_remaining[orderHash] == _ORDER_DOES_NOT_EXIST, "LOP: reentrancy detected");
                }
            } else {
                unchecked { remainingMakerAmount -= 1; }
            }

            // Check if order is valid
            if (order.predicate.length > 0) {
                require(checkPredicate(order), "LOP: predicate returned false");
            }

            // Compute maker and taker assets amount
            if ((amounts[_TAKING_AMOUNT] == 0) == (amounts[_MAKING_AMOUNT] == 0)) {
                revert("LOP: only one amount should be 0");
            } else if (amounts[_TAKING_AMOUNT] == 0) {
                uint256 requestedMakingAmount = amounts[_MAKING_AMOUNT];
                if (amounts[_MAKING_AMOUNT] > remainingMakerAmount) {
                    amounts[_MAKING_AMOUNT] = remainingMakerAmount;
                }
                amounts[_TAKING_AMOUNT] = _callGetter(order.getTakerAmount, order.makingAmount, amounts[_MAKING_AMOUNT], order.takingAmount);
                // check that actual rate is not worse than what was expected
                // amounts[_TAKING_AMOUNT] / amounts[_MAKING_AMOUNT] <= amounts[_THRESHOLD_AMOUNT] / requestedMakingAmount
                require(amounts[_TAKING_AMOUNT] * requestedMakingAmount <= amounts[_THRESHOLD_AMOUNT] * amounts[_MAKING_AMOUNT], "LOP: taking amount too high");
            } else {
                uint256 requestedTakingAmount = amounts[_TAKING_AMOUNT];
                amounts[_MAKING_AMOUNT] = _callGetter(order.getMakerAmount, order.takingAmount, amounts[_TAKING_AMOUNT], order.makingAmount);
                if (amounts[_MAKING_AMOUNT] > remainingMakerAmount) {
                    amounts[_MAKING_AMOUNT] = remainingMakerAmount;
                    amounts[_TAKING_AMOUNT] = _callGetter(order.getTakerAmount, order.makingAmount, amounts[_MAKING_AMOUNT], order.takingAmount);
                }
                // check that actual rate is not worse than what was expected
                // amounts[_MAKING_AMOUNT] / amounts[_TAKING_AMOUNT] >= amounts[_THRESHOLD_AMOUNT] / requestedTakingAmount
                require(amounts[_MAKING_AMOUNT] * requestedTakingAmount >= amounts[_THRESHOLD_AMOUNT] * amounts[_TAKING_AMOUNT], "LOP: making amount too low");
            }

            require(amounts[_MAKING_AMOUNT] > 0 && amounts[_TAKING_AMOUNT] > 0, "LOP: can't swap 0 amount");

            // Update remaining amount in storage
            unchecked {
                remainingMakerAmount = remainingMakerAmount - amounts[_MAKING_AMOUNT];
                _remaining[orderHash] = remainingMakerAmount + 1;
            }
            emit OrderFilled(msg.sender, orderHash, remainingMakerAmount);
        }

        // Maker => Taker
        _makeCall(
            order.makerAsset,
            abi.encodePacked(
                IERC20.transferFrom.selector,
                uint256(uint160(order.maker)),
                uint256(uint160(target)),
                amounts[_MAKING_AMOUNT],
                order.makerAssetData
            )
        );

        // Handle external extraInteraction
        if (extraInteraction.length >= 20) {
            // proceed only if interaction length is enough to store address
            (address interactionTarget, bytes memory interactionData) = extraInteraction.decodeTargetAndCalldata();
            InteractiveNotificationReceiver(interactionTarget).notifyFillOrder(
                msg.sender, order.makerAsset, order.takerAsset, amounts[_MAKING_AMOUNT], amounts[_TAKING_AMOUNT], interactionData
            );
        }
        
        // Taker => Maker
        _makeCall(
            order.takerAsset,
            abi.encodePacked(
                IERC20.transferFrom.selector,
                uint256(uint160(msg.sender)),
                uint256(uint160(order.receiver == address(0) ? order.maker : order.receiver)),
                amounts[_TAKING_AMOUNT],
                order.takerAssetData
            )
        );

        // Maker can handle funds interactively
        if (order.interaction.length >= 20) {
            // proceed only if interaction length is enough to store address
            (address interactionTarget, bytes memory interactionData) = order.interaction.decodeTargetAndCalldata();
            InteractiveNotificationReceiver(interactionTarget).notifyFillOrder(
                msg.sender, order.makerAsset, order.takerAsset, amounts[_MAKING_AMOUNT], amounts[_TAKING_AMOUNT], interactionData
            );
        }

        return (amounts[_MAKING_AMOUNT], amounts[_TAKING_AMOUNT]);
    }

    /// @notice Checks order predicate
    function checkPredicate(Order memory order) public view returns(bool) {
        bytes memory result = address(this).functionStaticCall(order.predicate, "LOP: predicate call failed");
        require(result.length == 32, "LOP: invalid predicate return");
        return result.decodeBool();
    }

    function hashOrder(Order memory order) public view returns(bytes32) {
        StaticOrder memory staticOrder;
        assembly {  // solhint-disable-line no-inline-assembly
            staticOrder := order
        }
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    LIMIT_ORDER_TYPEHASH,
                    staticOrder,
                    keccak256(order.makerAssetData),
                    keccak256(order.takerAssetData),
                    keccak256(order.getMakerAmount),
                    keccak256(order.getTakerAmount),
                    keccak256(order.predicate),
                    keccak256(order.permit),
                    keccak256(order.interaction)
                )
            )
        );
    }

    function _makeCall(address asset, bytes memory assetData) private {
        bytes memory result = asset.functionCall(assetData, "LOP: asset.call failed");
        if (result.length > 0) {
            require(result.length == 32 && result.decodeBool(), "LOP: asset.call bad result");
        }
    }

    function _callGetter(bytes memory getter, uint256 orderExpectedAmount, uint256 amount, uint256 orderResultAmount) private view returns(uint256) {
        if (getter.length == 0) {
            // On empty getter calldata only exact amount is allowed
            require(amount == orderExpectedAmount, "LOP: wrong amount");
            return orderResultAmount;
        } else {
            bytes memory result = address(this).functionStaticCall(abi.encodePacked(getter, amount), "LOP: getAmount call failed");
            require(result.length == 32, "LOP: invalid getAmount return");
            return result.decodeUint256();
        }
    }
}
