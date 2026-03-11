// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

struct Order {
    uint256 id;
    address maker;
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint256 remainingIn;
    uint256 startPrice;
    int256  slope;
    uint256 minPrice;
    uint256 maxPrice;
    uint256 createdAt;
    uint256 expiry;
    bool isBuy;
    bool active;
}

struct PairKey {
    address token0;
    address token1;
}

function pairKeyOf(address tokenA, address tokenB) pure returns (bytes32) {
    (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    return keccak256(abi.encodePacked(t0, t1));
}
