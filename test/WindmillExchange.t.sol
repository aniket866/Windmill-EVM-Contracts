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
        uint256 amount = 100 ether;
        uint256 price = RAY; // 1:1

        uint256 aliceTokenABefore = tokenA.balanceOf(alice);
        uint256 bobTokenBBefore = tokenB.balanceOf(bob);

        uint256 buyId = _buy(alice, amount, price, 0, 0);
        uint256 sellId = _sell(bob, amount, price, 0, 0);

        address keeper = address(this);
        uint256 keeperTokenABefore = tokenA.balanceOf(keeper);

        exchange.matchOrders(buyId, sellId, block.timestamp + 1);

        // settlementPx = midpoint(RAY, RAY) = RAY -> filledAsset = 100e18, paymentOwed = 100e18
        uint256 expectedFee = amount / 1000; // 0.1 ether
        uint256 expectedPayment = amount - expectedFee; // 99.9 ether

        // Order state
        Order memory buyOrder = exchange.getOrder(buyId);
        Order memory sellOrder = exchange.getOrder(sellId);
        assertFalse(buyOrder.active, "buy must be inactive");
        assertFalse(sellOrder.active, "sell must be inactive");
        assertEq(buyOrder.remainingIn, amount, "buy.remainingIn unchanged on full fill");
        assertEq(sellOrder.remainingIn, amount, "sell.remainingIn unchanged on full fill");

        // Alice received exactly filledAsset tokenB; lost exactly paymentOwed tokenA
        assertEq(tokenB.balanceOf(alice), amount, "alice tokenB");
        assertEq(tokenA.balanceOf(alice), aliceTokenABefore - amount, "alice tokenA (escrowed)");

        // Bob received exactly paymentOwed - fee tokenA; lost filledAsset tokenB
        assertEq(tokenA.balanceOf(bob), expectedPayment, "bob tokenA");
        assertEq(tokenB.balanceOf(bob), bobTokenBBefore - amount, "bob tokenB");

        // Keeper received exactly fee
        assertEq(tokenA.balanceOf(keeper), keeperTokenABefore + expectedFee, "keeper fee");

        // Pair index cleared
        assertEq(
            exchange.getOrdersByPair(address(tokenA), address(tokenB), 0, type(uint256).max).length,
            0
        );
    }

    function test_matchOrders_partialFill() public {
        uint256 buyAmt = 50 ether;
        uint256 sellAmt = 100 ether;
        uint256 price = RAY;

        uint256 buyId = _buy(alice, buyAmt, price, 0, 0);
        uint256 sellId = _sell(bob, sellAmt, price, 0, 0);

        exchange.matchOrders(buyId, sellId, block.timestamp + 1);

        // paymentOwed = 50e18, filledAsset = 50e18, keeperFee = 0.05e18
        uint256 expectedFee = buyAmt / 1000;
        uint256 expectedSellRemaining = sellAmt - buyAmt; // 50 ether

        Order memory buyOrder = exchange.getOrder(buyId);
        Order memory sellOrder = exchange.getOrder(sellId);

        assertFalse(buyOrder.active, "buy fully filled -> inactive");
        assertTrue(sellOrder.active, "sell partially filled -> still active");

        assertEq(sellOrder.remainingIn, expectedSellRemaining, "sell.remainingIn exact");
        assertEq(sellOrder.createdAt, block.timestamp, "sell.createdAt re-anchored");

        assertEq(tokenB.balanceOf(alice), buyAmt, "alice tokenB exact");
        assertEq(tokenA.balanceOf(bob), buyAmt - expectedFee, "bob tokenA exact");
        assertEq(tokenA.balanceOf(address(this)), expectedFee, "keeper fee exact");
    }

    function test_matchOrders_revert_expired() public {
        vm.warp(1000);
        uint256 buyId = _buy(alice, 100 ether, RAY, 0, 1500);
        uint256 sellId = _sell(bob, 100 ether, RAY, 0, 0);
        vm.warp(1501);
        vm.expectRevert(OrderExpired.selector);
        exchange.matchOrders(buyId, sellId, block.timestamp + 1);
    }

    function test_matchOrders_revert_sellExpired() public {
        vm.warp(1000);
        uint256 buyId = _buy(alice, 100 ether, RAY, 0, 0);
        uint256 sellId = _sell(bob, 100 ether, RAY, 0, 1500);
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

    // ── pruneExpiredOrders ────────────────────────────────────────────────────

    function test_pruneExpiredOrders() public {
        vm.warp(1000);
        uint256 id1 = _buy(alice, 100 ether, RAY, 0, 1500); // expires at 1500
        uint256 id2 = _buy(alice, 100 ether, RAY, 0, 2000); // expires at 2000

        vm.warp(1600); // past id1 expiry, before id2

        exchange.pruneExpiredOrders(address(tokenA), address(tokenB), 10);

        assertFalse(exchange.getOrder(id1).active, "expired order pruned");
        assertTrue(exchange.getOrder(id2).active, "non-expired order untouched");

        uint256[] memory remaining =
            exchange.getOrdersByPair(address(tokenA), address(tokenB), 0, 10);
        assertEq(remaining.length, 1, "one order left in pair index");
        assertEq(remaining[0], id2, "correct order remains");
    }
}
