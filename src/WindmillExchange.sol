// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// ── Errors ────────────────────────────────────────────────────────────────────

error ZeroAddress();
error SameToken();
error ZeroAmount();
error ZeroStartPrice();
error InvalidExpiry();
error InvalidPriceBounds();
error SlopeOverflow();
error NotMaker();
error OrderInactive();
error OrderExpired();
error SelfMatch();
error NoCross();
error PairMismatch();
error ZeroSettlementPrice();
error OrderNotFound();
error TransferFailed();

// ── Types ─────────────────────────────────────────────────────────────────────

struct Order {
    uint256 id;
    address maker;
    bool isBuy;
    bool active;
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint256 remainingIn;
    uint256 startPrice;
    int256 slope;
    uint256 minPrice;
    uint256 maxPrice;
    uint256 createdAt;
    uint256 expiry;
}

// ── Math ──────────────────────────────────────────────────────────────────────

uint256 constant RAY = 1e27;

function mulDiv(uint256 a, uint256 b, uint256 denom) pure returns (uint256 result) {
    require(denom != 0, "div by zero");
    unchecked {
        uint256 prod0;
        uint256 prod1;
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }
        if (prod1 == 0) return prod0 / denom;
        require(prod1 < denom, "mulDiv overflow");
        uint256 remainder;
        assembly { remainder := mulmod(a, b, denom) }
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }
        uint256 twos = denom & (~denom + 1);
        assembly {
            denom := div(denom, twos)
            prod0 := div(prod0, twos)
            twos := add(div(sub(0, twos), twos), 1)
        }
        prod0 |= prod1 * twos;
        uint256 inv = (3 * denom) ^ 2;
        inv *= 2 - denom * inv;
        inv *= 2 - denom * inv;
        inv *= 2 - denom * inv;
        inv *= 2 - denom * inv;
        inv *= 2 - denom * inv;
        inv *= 2 - denom * inv;
        result = prod0 * inv;
    }
}

function midpoint(uint256 a, uint256 b) pure returns (uint256) {
    return (a & b) + ((a ^ b) >> 1);
}

/// @dev A bound of 0 means unbounded on that side.
function clamp(uint256 value, uint256 lo, uint256 hi) pure returns (uint256) {
    require(lo == 0 || hi == 0 || lo <= hi, "invalid bounds");
    if (lo != 0 && value < lo) return lo;
    if (hi != 0 && value > hi) return hi;
    return value;
}

function absInt(int256 x) pure returns (uint256) {
    if (x == type(int256).min) return 2 ** 255;
    return x >= 0 ? uint256(x) : uint256(-x);
}

// ── Price Curve ───────────────────────────────────────────────────────────────

function computePrice(
    uint256 startPrice,
    int256 slope,
    uint256 createdAt,
    uint256 minPrice,
    uint256 maxPrice,
    uint256 timestamp
) pure returns (uint256 price) {
    uint256 elapsed = timestamp > createdAt ? timestamp - createdAt : 0;

    if (slope == 0 || elapsed == 0) {
        price = startPrice;
    } else if (slope > 0) {
        uint256 slopeAbs = uint256(slope);
        unchecked {
            uint256 prod = slopeAbs * elapsed;
            if (prod / elapsed != slopeAbs) {
                return clamp(maxPrice != 0 ? maxPrice : type(uint256).max, minPrice, maxPrice);
            }
            uint256 newPrice = startPrice + prod;
            price = newPrice < startPrice ? type(uint256).max : newPrice;
        }
    } else {
        if (slope == type(int256).min) return clamp(minPrice, minPrice, maxPrice);
        uint256 slopeAbs = uint256(-slope);
        unchecked {
            uint256 dec = slopeAbs * elapsed;
            if (dec / elapsed != slopeAbs) return clamp(minPrice, minPrice, maxPrice);
            price = dec >= startPrice ? 0 : startPrice - dec;
        }
    }
    price = clamp(price, minPrice, maxPrice);
}

function orderPrice(Order memory o, uint256 ts) pure returns (uint256) {
    return computePrice(o.startPrice, o.slope, o.createdAt, o.minPrice, o.maxPrice, ts);
}

// ── Token Transfer ────────────────────────────────────────────────────────────

function safeTransfer(address token, address to, uint256 amount) {
    if (amount == 0) return;
    if (token.code.length == 0) revert TransferFailed();
    (bool ok, bytes memory data) =
        token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
    if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
}

function safeTransferFrom(address token, address from, address to, uint256 amount) {
    if (amount == 0) return;
    if (token.code.length == 0) revert TransferFailed();
    (bool ok, bytes memory data) = token.call(
        abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, amount)
    );
    if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
}

// ── Exchange ──────────────────────────────────────────────────────────────────

contract WindmillExchange {
    uint256 private _reentrancyStatus = 1;

    uint256 private _nextOrderId = 1;
    mapping(uint256 => Order) private _orders;

    mapping(bytes32 => uint256[]) private _pairOrders;
    mapping(bytes32 => mapping(uint256 => uint256)) private _pairIndex;

    uint256 private constant MAX_LIFETIME = 315_360_000;
    uint256 private constant SLOPE_ABS_LIMIT = type(uint128).max / MAX_LIFETIME;

    modifier nonReentrant() {
        require(_reentrancyStatus == 1, "reentrant call");
        _reentrancyStatus = 2;
        _;
        _reentrancyStatus = 1;
    }

    event OrderCreated(
        uint256 indexed orderId,
        address indexed maker,
        address indexed tokenIn,
        address tokenOut,
        uint256 amountIn,
        bool isBuy
    );
    event OrderCancelled(uint256 indexed orderId, address indexed maker, uint256 refund);
    event OrderMatched(
        uint256 indexed buyOrderId,
        uint256 indexed sellOrderId,
        address indexed keeper,
        uint256 settlementPrice,
        uint256 filledAmount
    );
    event OrderFilled(uint256 indexed orderId);
    event OrderPartiallyFilled(uint256 indexed orderId, uint256 remainingIn);

    // ── External ──────────────────────────────────────────────────────────────

    function createOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 startPrice,
        int256 slope,
        uint256 minPrice,
        uint256 maxPrice,
        uint256 expiry,
        bool isBuy
    ) external nonReentrant returns (uint256 orderId) {
        if (tokenIn == address(0) || tokenOut == address(0)) revert ZeroAddress();
        if (tokenIn == tokenOut) revert SameToken();
        if (amountIn == 0) revert ZeroAmount();
        if (startPrice == 0) revert ZeroStartPrice();
        if (expiry != 0 && expiry <= block.timestamp) revert InvalidExpiry();
        if (maxPrice != 0 && maxPrice < minPrice) revert InvalidPriceBounds();
        if (slope != 0 && absInt(slope) > SLOPE_ABS_LIMIT) revert SlopeOverflow();

        Order memory order = Order({
            id: 0,
            maker: msg.sender,
            isBuy: isBuy,
            active: true,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            remainingIn: amountIn,
            startPrice: startPrice,
            slope: slope,
            minPrice: minPrice,
            maxPrice: maxPrice,
            createdAt: block.timestamp,
            expiry: expiry
        });

        orderId = _nextOrderId++;
        order.id = orderId;
        _orders[orderId] = order;
        _pairAdd(tokenIn, tokenOut, orderId);

        safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        emit OrderCreated(orderId, msg.sender, tokenIn, tokenOut, amountIn, isBuy);
    }

    function cancelOrder(uint256 orderId) external nonReentrant {
        Order storage o = _order(orderId);
        if (o.maker != msg.sender) revert NotMaker();
        if (!o.active) revert OrderInactive();

        uint256 refund = o.remainingIn;
        address tokenIn = o.tokenIn;
        address tokenOut = o.tokenOut;

        o.active = false;
        _pairRemove(tokenIn, tokenOut, orderId);
        safeTransfer(tokenIn, msg.sender, refund);
        emit OrderCancelled(orderId, msg.sender, refund);
    }

    function matchOrders(uint256 buyOrderId, uint256 sellOrderId, uint256 deadline)
        external
        nonReentrant
    {
        require(block.timestamp <= deadline, "deadline expired");
        Order memory buy = _orderMem(buyOrderId);
        Order memory sell = _orderMem(sellOrderId);

        if (!buy.active || !sell.active) revert OrderInactive();
        if (buy.expiry != 0 && block.timestamp > buy.expiry) revert OrderExpired();
        if (sell.expiry != 0 && block.timestamp > sell.expiry) revert OrderExpired();
        if (!buy.isBuy || sell.isBuy) revert PairMismatch();
        if (buy.tokenOut != sell.tokenIn || buy.tokenIn != sell.tokenOut) revert PairMismatch();
        if (buy.maker == sell.maker) revert SelfMatch();
        if (orderPrice(buy, block.timestamp) < orderPrice(sell, block.timestamp)) revert NoCross();

        uint256 settlementPx =
            midpoint(orderPrice(buy, block.timestamp), orderPrice(sell, block.timestamp));
        if (settlementPx == 0) revert ZeroSettlementPrice();

        uint256 maxAsset = mulDiv(buy.remainingIn, settlementPx, RAY);
        uint256 filledAsset = maxAsset < sell.remainingIn ? maxAsset : sell.remainingIn;
        uint256 paymentOwed = mulDiv(filledAsset, RAY, settlementPx);
        filledAsset = mulDiv(paymentOwed, settlementPx, RAY);
        if (filledAsset == 0) revert ZeroAmount();

        bool buyFilled = (buy.remainingIn - paymentOwed) == 0;
        bool sellFilled = (sell.remainingIn - filledAsset) == 0;
        uint256 newBuyRemaining = buy.remainingIn - paymentOwed;
        uint256 newSellRemaining = sell.remainingIn - filledAsset;

        if (buyFilled) {
            _orders[buyOrderId].active = false;
            _pairRemove(buy.tokenIn, buy.tokenOut, buyOrderId);
        } else {
            _orders[buyOrderId].remainingIn = newBuyRemaining;
        }

        if (sellFilled) {
            _orders[sellOrderId].active = false;
            _pairRemove(sell.tokenIn, sell.tokenOut, sellOrderId);
        } else {
            _orders[sellOrderId].remainingIn = newSellRemaining;
        }

        uint256 keeperFee = paymentOwed / 1000;
        safeTransfer(sell.tokenIn, buy.maker, filledAsset);
        safeTransfer(buy.tokenIn, sell.maker, paymentOwed - keeperFee);
        safeTransfer(buy.tokenIn, msg.sender, keeperFee);

        emit OrderMatched(buyOrderId, sellOrderId, msg.sender, settlementPx, filledAsset);
        if (buyFilled) emit OrderFilled(buyOrderId);
        else emit OrderPartiallyFilled(buyOrderId, newBuyRemaining);
        if (sellFilled) emit OrderFilled(sellOrderId);
        else emit OrderPartiallyFilled(sellOrderId, newSellRemaining);
    }

    function currentPrice(uint256 orderId, uint256 timestamp) external view returns (uint256) {
        return orderPrice(_orderMem(orderId), timestamp);
    }

    function getOrder(uint256 orderId) external view returns (Order memory) {
        return _orderMem(orderId);
    }

    function getOrdersByPair(address tokenA, address tokenB, uint256 cursor, uint256 limit)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] storage all = _pairOrders[_pairKey(tokenA, tokenB)];
        uint256 total = all.length;
        if (cursor >= total) return new uint256[](0);
        uint256 size = (total - cursor) < limit ? (total - cursor) : limit;
        uint256[] memory result = new uint256[](size);
        for (uint256 i; i < size; i++) {
            result[i] = all[cursor + i];
        }
        return result;
    }

    function totalOrders() external view returns (uint256) {
        return _nextOrderId - 1;
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    function _order(uint256 id) private view returns (Order storage) {
        if (_orders[id].maker == address(0)) revert OrderNotFound();
        return _orders[id];
    }

    function _orderMem(uint256 id) private view returns (Order memory) {
        if (_orders[id].maker == address(0)) revert OrderNotFound();
        return _orders[id];
    }

    function _pairKey(address a, address b) private pure returns (bytes32) {
        (address t0, address t1) = a < b ? (a, b) : (b, a);
        return keccak256(abi.encodePacked(t0, t1));
    }

    function _pairAdd(address a, address b, uint256 id) private {
        bytes32 key = _pairKey(a, b);
        require(_pairIndex[key][id] == 0, "duplicate order");
        _pairOrders[key].push(id);
        _pairIndex[key][id] = _pairOrders[key].length;
    }

    function _pairRemove(address a, address b, uint256 id) private {
        bytes32 key = _pairKey(a, b);
        uint256 idx = _pairIndex[key][id];
        require(idx != 0, "order not in pair");
        uint256[] storage list = _pairOrders[key];
        uint256 last = list.length;
        if (idx != last) {
            uint256 lastId = list[last - 1];
            list[idx - 1] = lastId;
            _pairIndex[key][lastId] = idx;
        }
        list.pop();
        delete _pairIndex[key][id];
    }
}
