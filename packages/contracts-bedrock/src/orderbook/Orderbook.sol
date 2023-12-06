// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Orderbook {
    address public constant _addOrder = 0x0000000000000000000000000000000000001337;
    address public constant _clearOrder = 0x0000000000000000000000000000000000001338;
    address public constant _removeOrder = 0x0000000000000000000000000000000000001339;
    address public constant _createPair = 0x0000000000000000000000000000000000001340;

    constructor() { }

    mapping(address => mapping(ERC20 => uint256)) public balances;
    mapping(uint256 => Pair) public pairs;

    struct Pair {
        address token0;
        address token1;
    }

    /**
     *
     * @param _token0 Token address
     * @param _token1 Token address
     * @param _tickSize The tick size
     * @param _minAmount The minimum amount (scaled by the tick size)
     * @param _maxAmount The maximum amount (scaled by the tick size)
     */
    function createPair(
        address _token0,
        address _token1,
        uint16 _tickSize,
        uint32 _minAmount,
        uint32 _maxAmount
    )
        public
        returns (uint256 _pairId)
    {
        (bool _success, bytes memory _pair) =
            _createPair.call(abi.encode(_token0, _token1, _tickSize, _minAmount, _maxAmount));
        require(_success, "Orderbook: Failed to create pair");
        _pairId = abi.decode(_pair, (uint256));
        pairs[_pairId] = Pair(_token0, _token1);
    }

    function addOrder(
        uint256 _pairId,
        uint256 _amountOut,
        uint256 _amount,
        bool _direction
    )
        public
        returns (uint256, uint256)
    {
        // Try to match the order first – and then add it

        Pair memory _pair = pairs[_pairId];

        if (_direction) {
            // Going from Token0 to Token1
            if (balances[msg.sender][ERC20(_pair.token0)] < _amount) {
                // Not enough balance
                revert("Orderbook: Deposit more to keep playing");
            }
        } else {
            // Going from Token1 to Token0
            if (balances[msg.sender][ERC20(_pair.token1)] < _amount) {
                // Not enough balance
                revert("Orderbook: Deposit more to keep playing");
            }
        }
        // Calculate the implied price
        uint256 _price = (_amountOut * 1e18) / _amount;

        (uint256 _receiveAmount, uint256 _inputAmount) = _matchOrder(_pairId, _price, _amount, _direction);

        _amount -= _inputAmount;
        _amountOut -= _receiveAmount;
        if (_amount == 0) {
            // We have matched the order
            return (_receiveAmount, 0);
        } else {
            // Add order to the orderbook
            (bool _success, bytes memory _data) =
                _addOrder.call(abi.encode(_pairId, _amount, _amountOut, _price, _direction));
            require(_success, "Orderbook: Failed to add order");
            uint256 _orderId = abi.decode(_data, (uint256));
            return (_receiveAmount, _orderId);
        }
    }

    function removeOrder(uint32 _id, uint256 _orderId) external {
        (bool _success,) = _removeOrder.call(abi.encode(_id, msg.sender, _orderId));
        require(_success, "Orderbook: Failed to remove order");
    }

    function _matchOrder(
        uint256 _pairId,
        uint256 _price,
        uint256 _amount,
        bool _direction
    )
        internal
        returns (uint256 _receiveAmount, uint256 _inputAmount)
    {
        (bool _success, bytes memory _data) = _clearOrder.call(abi.encode(_pairId, _price, _amount, _direction));
        Pair memory _pair = pairs[_pairId];
        require(_success, "Orderbook: Failed to clear order");
        (_receiveAmount, _inputAmount) = abi.decode(_data, (uint256, uint256));

        if (_amount < _inputAmount) {
            revert("Orderbook: Match done incorrectly");
        }

        if (_direction) {
            // Going from Token0 to Token1
            balances[msg.sender][ERC20(_pair.token0)] -= _inputAmount;
            balances[msg.sender][ERC20(_pair.token1)] += _receiveAmount;
        } else {
            // Going from Token1 to Token0
            balances[msg.sender][ERC20(_pair.token1)] -= _inputAmount;
            balances[msg.sender][ERC20(_pair.token0)] += _receiveAmount;
        }
    }

    function depositFunds(ERC20 _token, uint256 _amount) public {
        _token.transferFrom(msg.sender, address(this), _amount);
        balances[msg.sender][_token] += _amount;
    }

    function withdrawFunds(ERC20 _token, uint256 _amount) public {
        // Do some validation to remove user order that are now invalid
        _token.transfer(msg.sender, _amount);
        balances[msg.sender][_token] -= _amount;
    }
}
