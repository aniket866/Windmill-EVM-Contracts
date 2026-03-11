// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Order} from "../types/OrderTypes.sol";
import {MathUtils} from "./MathUtils.sol";

library PriceCurve {
    using MathUtils for uint256;

    function currentPrice(Order storage order, uint256 timestamp) internal view returns (uint256) {
        return _compute(order.startPrice, order.slope, order.createdAt, order.minPrice, order.maxPrice, timestamp);
    }

    function currentPriceMem(Order memory order, uint256 timestamp) internal pure returns (uint256) {
        return _compute(order.startPrice, order.slope, order.createdAt, order.minPrice, order.maxPrice, timestamp);
    }

    function hasCrossed(Order memory buy, Order memory sell, uint256 timestamp) internal pure returns (bool) {
        return currentPriceMem(buy, timestamp) >= currentPriceMem(sell, timestamp);
    }

    function settlementPrice(Order memory buy, Order memory sell, uint256 timestamp) internal pure returns (uint256) {
        return MathUtils.midpoint(currentPriceMem(buy, timestamp), currentPriceMem(sell, timestamp));
    }

    function _compute(
        uint256 startPrice,
        int256  slope,
        uint256 createdAt,
        uint256 minPrice,
        uint256 maxPrice,
        uint256 timestamp
    ) private pure returns (uint256 price) {
        uint256 elapsed = timestamp > createdAt ? timestamp - createdAt : 0;

        if (slope == 0 || elapsed == 0) {
            price = startPrice;
        } else if (slope > 0) {
            uint256 slopeAbs = uint256(slope);
            unchecked {
                uint256 prod = slopeAbs * elapsed;
                if (elapsed != 0 && prod / elapsed != slopeAbs) {
                    price = maxPrice != 0 ? maxPrice : type(uint256).max;
                    return MathUtils.clamp(price, minPrice, maxPrice);
                }
                uint256 newPrice = startPrice + prod;
                price = newPrice < startPrice ? type(uint256).max : newPrice;
            }
        } else {
            uint256 slopeAbs = uint256(-slope);
            uint256 decrement;
            unchecked {
                decrement = slopeAbs * elapsed;
                if (elapsed != 0 && decrement / elapsed != slopeAbs) {
                    return MathUtils.clamp(minPrice, minPrice, maxPrice);
                }
            }
            price = decrement >= startPrice ? 0 : startPrice - decrement;
        }

        price = MathUtils.clamp(price, minPrice, maxPrice);
    }
}
