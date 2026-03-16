// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { WindmillExchange, Order } from "../src/WindmillExchange.sol";
import {
    ZeroAddress,
    SameToken,
    ZeroAmount,
    ZeroStartPrice,
    InvalidExpiry,
    InvalidPriceBounds,
    SlopeOverflow,
    NotMaker,
    OrderInactive,
    OrderExpired,
    SelfMatch,
    NoCross,
    PairMismatch
} from "../src/WindmillExchange.sol";

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        if (allowance[from][msg.sender] != type(uint256).max) {
            require(allowance[from][msg.sender] >= amount, "allowance");
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract WindmillExchangeTest is Test {
    uint256 internal constant RAY = 1e27;

    WindmillExchange internal exchange;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        exchange = new WindmillExchange();
        tokenA = new MockERC20();
        tokenB = new MockERC20();

        tokenA.mint(alice, 1_000_000 ether);
        tokenB.mint(bob, 1_000_000 ether);

        vm.prank(alice);
        tokenA.approve(address(exchange), type(uint256).max);
        vm.prank(alice);
        tokenB.approve(address(exchange), type(uint256).max);
        vm.prank(bob);
        tokenA.approve(address(exchange), type(uint256).max);
        vm.prank(bob);
        tokenB.approve(address(exchange), type(uint256).max);
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    function _buy(address maker, uint256 amt, uint256 price, int256 slope, uint256 expiry)
        internal
        returns (uint256)
    {
        vm.prank(maker);
        return exchange.createOrder(
            address(tokenA), address(tokenB), amt, price, slope, 0, 0, expiry, true
        );
    }

    function _sell(address maker, uint256 amt, uint256 price, int256 slope, uint256 expiry)
        internal
        returns (uint256)
    {
        vm.prank(maker);
        return exchange.createOrder(
            address(tokenB), address(tokenA), amt, price, slope, 0, 0, expiry, false
        );
    }

    // ── createOrder ────────────────────────────────────────────────────────────

    function test_createBuyOrder() public {
        uint256 id = _buy(alice, 1000 ether, 2 * RAY, 0, 0);
        Order memory o = exchange.getOrder(id);
        assertEq(o.maker, alice);
        assertTrue(o.isBuy);
        assertTrue(o.active);
        assertEq(o.remainingIn, 1000 ether);
        assertEq(tokenA.balanceOf(address(exchange)), 1000 ether);
    }

    function test_createSellOrder() public {
        uint256 id = _sell(bob, 500 ether, 2 * RAY, 0, 0);
        Order memory o = exchange.getOrder(id);
        assertFalse(o.isBuy);
        assertEq(tokenB.balanceOf(address(exchange)), 500 ether);
    }

    function test_createOrder_revert_zeroAddress() public {
        vm.prank(alice);
        vm.expectRevert(ZeroAddress.selector);
        exchange.createOrder(address(0), address(tokenB), 100 ether, RAY, 0, 0, 0, 0, true);
    }

    function test_createOrder_revert_sameToken() public {
        vm.prank(alice);
        vm.expectRevert(SameToken.selector);
        exchange.createOrder(address(tokenA), address(tokenA), 100 ether, RAY, 0, 0, 0, 0, true);
    }

    function test_createOrder_revert_zeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(ZeroAmount.selector);
        exchange.createOrder(address(tokenA), address(tokenB), 0, RAY, 0, 0, 0, 0, true);
    }

    function test_createOrder_revert_zeroStartPrice() public {
        vm.prank(alice);
        vm.expectRevert(ZeroStartPrice.selector);
        exchange.createOrder(address(tokenA), address(tokenB), 100 ether, 0, 0, 0, 0, 0, true);
    }

    function test_createOrder_revert_expiryInPast() public {
        vm.warp(1000);
        vm.prank(alice);
        vm.expectRevert(InvalidExpiry.selector);
        exchange.createOrder(address(tokenA), address(tokenB), 100 ether, RAY, 0, 0, 0, 999, true);
    }

    function test_createOrder_revert_slopeOverflow() public {
        vm.prank(alice);
        vm.expectRevert(SlopeOverflow.selector);
        exchange.createOrder(
            address(tokenA), address(tokenB), 100 ether, RAY, type(int128).max, 0, 0, 0, true
        );
    }

    function test_createOrder_revert_invalidPriceBounds() public {
        vm.prank(alice);
        vm.expectRevert(InvalidPriceBounds.selector);
        exchange.createOrder(
            address(tokenA), address(tokenB), 100 ether, RAY, 0, 2 * RAY, RAY, 0, true
        );
    }

    // ── cancelOrder ───────────────────────────────────────────────────────────

    function test_cancelOrder() public {
        uint256 id = _buy(alice, 200 ether, RAY, 0, 0);
        uint256 balBefore = tokenA.balanceOf(alice);

        vm.prank(alice);
        exchange.cancelOrder(id);

        assertFalse(exchange.getOrder(id).active);
        assertEq(tokenA.balanceOf(alice), balBefore + 200 ether);
    }

    function test_cancelOrder_revert_notMaker() public {
        uint256 id = _buy(alice, 100 ether, RAY, 0, 0);
        vm.prank(bob);
        vm.expectRevert(NotMaker.selector);
        exchange.cancelOrder(id);
    }

    function test_cancelOrder_revert_alreadyInactive() public {
        uint256 id = _buy(alice, 100 ether, RAY, 0, 0);
        vm.prank(alice);
        exchange.cancelOrder(id);
        vm.prank(alice);
        vm.expectRevert(OrderInactive.selector);
        exchange.cancelOrder(id);
    }

    // ── matchOrders ───────────────────────────────────────────────────────────

    function test_matchOrders_fullFill() public {
        uint256 buyId = _buy(alice, 100 ether, RAY, 0, 0);
        uint256 sellId = _sell(bob, 100 ether, RAY, 0, 0);

        exchange.matchOrders(buyId, sellId, block.timestamp + 1);

        assertFalse(exchange.getOrder(buyId).active);
        assertFalse(exchange.getOrder(sellId).active);
        assertGt(tokenB.balanceOf(alice), 0);
        assertGt(tokenA.balanceOf(bob), 0);
    }

    function test_matchOrders_partialFill() public {
        uint256 buyId = _buy(alice, 50 ether, RAY, 0, 0);
        uint256 sellId = _sell(bob, 100 ether, RAY, 0, 0);

        exchange.matchOrders(buyId, sellId, block.timestamp + 1);

        assertFalse(exchange.getOrder(buyId).active);
        assertTrue(exchange.getOrder(sellId).active);
        assertLt(exchange.getOrder(sellId).remainingIn, 100 ether);
    }

    function test_matchOrders_revert_expired() public {
        vm.warp(1000);
        uint256 buyId = _buy(alice, 100 ether, RAY, 0, 1500);
        uint256 sellId = _sell(bob, 100 ether, RAY, 0, 0);
        vm.warp(1501);
        vm.expectRevert(OrderExpired.selector);
        exchange.matchOrders(buyId, sellId, block.timestamp + 1);
    }

    function test_matchOrders_revert_selfMatch() public {
        tokenB.mint(alice, 100 ether);
        vm.prank(alice);
        tokenB.approve(address(exchange), type(uint256).max);

        uint256 buyId = _buy(alice, 100 ether, RAY, 0, 0);
        vm.prank(alice);
        uint256 sellId = exchange.createOrder(
            address(tokenB), address(tokenA), 100 ether, RAY, 0, 0, 0, 0, false
        );

        vm.expectRevert(SelfMatch.selector);
        exchange.matchOrders(buyId, sellId, block.timestamp + 1);
    }

    function test_matchOrders_revert_noCross() public {
        uint256 buyId = _buy(alice, 100 ether, RAY / 2, 0, 0);
        uint256 sellId = _sell(bob, 100 ether, RAY * 2, 0, 0);
        vm.expectRevert(NoCross.selector);
        exchange.matchOrders(buyId, sellId, block.timestamp + 1);
    }

    function test_matchOrders_revert_pairMismatch() public {
        uint256 buyId = _buy(alice, 100 ether, RAY, 0, 0);
        tokenA.mint(bob, 100 ether);
        vm.prank(bob);
        tokenA.approve(address(exchange), type(uint256).max);
        vm.prank(bob);
        uint256 wrongId = exchange.createOrder(
            address(tokenA), address(tokenB), 100 ether, RAY, 0, 0, 0, 0, true
        );
        vm.expectRevert(PairMismatch.selector);
        exchange.matchOrders(buyId, wrongId, block.timestamp + 1);
    }

    // ── Fuzz ──────────────────────────────────────────────────────────────────

    function testFuzz_escrow(uint96 amount) public {
        vm.assume(amount > 0);
        tokenA.mint(alice, amount);
        uint256 id = _buy(alice, amount, RAY, 0, 0);
        assertEq(exchange.getOrder(id).remainingIn, amount);
    }
}
