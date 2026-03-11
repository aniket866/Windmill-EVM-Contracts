// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Order} from "../types/OrderTypes.sol";

error OrderNotFound();

abstract contract OrderStorage {
    uint256 private _nextOrderId = 1;
    mapping(uint256 => Order) private _orders;
    mapping(uint256 => bool)  private _exists;

    function _storeOrder(Order memory order) internal returns (uint256 id) {
        id = _nextOrderId++;
        order.id = id;
        _orders[id] = order;
        _exists[id] = true;
    }

    function _getOrder(uint256 id) internal view returns (Order storage) {
        if (!_exists[id]) revert OrderNotFound();
        return _orders[id];
    }

    function _getOrderMem(uint256 id) internal view returns (Order memory) {
        if (!_exists[id]) revert OrderNotFound();
        return _orders[id];
    }

    function _updateRemainingIn(uint256 id, uint256 newRemaining) internal {
        _orders[id].remainingIn = newRemaining;
    }

    function _deactivateOrder(uint256 id) internal {
        _orders[id].active = false;
    }

    function getOrder(uint256 orderId) external view returns (Order memory) {
        return _getOrderMem(orderId);
    }

    function totalOrders() external view returns (uint256) {
        return _nextOrderId - 1;
    }
}
