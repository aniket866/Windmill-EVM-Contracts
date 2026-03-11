// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {WindmillExchange} from "../src/core/WindmillExchange.sol";
import {Order} from "../src/types/OrderTypes.sol";
import {
    ZeroAddress,
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
} from "../src/core/WindmillExchange.sol";

contract MockERC20 {
    string  public name;
    string  public symbol;
    uint8   public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256)                     public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to,       uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol) {
        name   = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply    += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to]         += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        if (allowance[from][msg.sender] != type(uint256).max) {
            require(allowance[from][msg.sender] >= amount, "allowance");
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to]   += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
}

contract WindmillExchangeTest is Test {
    uint256 internal constant RAY = 1e27;

    WindmillExchange internal exchange;
    MockERC20        internal tokenA;
    MockERC20        internal tokenB;

    address internal alice  = makeAddr("alice");
    address internal bob    = makeAddr("bob");

    function setUp() public {
        exchange = new WindmillExchange();
        tokenA   = new MockERC20("TokenA", "TKNA");
        tokenB   = new MockERC20("TokenB", "TKNB");

        tokenA.mint(alice, 1_000_000 ether);
        tokenB.mint(bob,   1_000_000 ether);

        vm.prank(alice); tokenA.approve(address(exchange), type(uint256).max);
        vm.prank(alice); tokenB.approve(address(exchange), type(uint256).max);
        vm.prank(bob);   tokenA.approve(address(exchange), type(uint256).max);
        vm.prank(bob);   tokenB.approve(address(exchange), type(uint256).max);
    }

    function _createBuyOrder(address maker, uint256 amountIn, uint256 startPrice, int256 slope, uint256 expiry)
        internal returns (uint256)
    {
        vm.prank(maker);
        return exchange.createOrder(address(tokenA), address(tokenB), amountIn, startPrice, slope, 0, 0, expiry, true);
    }

    function _createSellOrder(address maker, uint256 amountIn, uint256 startPrice, int256 slope, uint256 expiry)
        internal returns (uint256)
    {
        vm.prank(maker);
        return exchange.createOrder(address(tokenB), address(tokenA), amountIn, startPrice, slope, 0, 0, expiry, false);
    }

    function test_createBuyOrder_success() public {
        uint256 amount     = 1000 ether;
        uint256 startPrice = 2 * RAY;

        vm.expectEmit(true, true, true, true);
        emit WindmillExchange.OrderCreated(1, alice, address(tokenA), address(tokenB), amount, true);

        uint256 id = _createBuyOrder(alice, amount, startPrice, 0, 0);

        assertEq(id, 1);

        Order memory o = exchange.getOrder(id);
        assertEq(o.maker,       alice);
        assertEq(o.tokenIn,     address(tokenA));
        assertEq(o.tokenOut,    address(tokenB));
        assertEq(o.amountIn,    amount);
        assertEq(o.remainingIn, amount);
        assertEq(o.startPrice,  startPrice);
        assertTrue(o.isBuy);
        assertTrue(o.active);

        assertEq(tokenA.balanceOf(address(exchange)), amount);
        assertEq(tokenA.balanceOf(alice), 1_000_000 ether - amount);
    }

    function test_createSellOrder_success() public {
        uint256 amount = 500 ether;
        uint256 id     = _createSellOrder(bob, amount, 2 * RAY, 0, 0);

        Order memory o = exchange.getOrder(id);
        assertFalse(o.isBuy);
        assertEq(o.tokenIn,  address(tokenB));
        assertEq(o.tokenOut, address(tokenA));
        assertEq(tokenB.balanceOf(address(exchange)), amount);
    }

    function test_createOrder_withExpiry() public {
        uint256 expiry = block.timestamp + 1 days;
        uint256 id = _createBuyOrder(alice, 100 ether, RAY, 0, expiry);
        assertEq(exchange.getOrder(id).expiry, expiry);
    }

    function test_createOrder_withSlope() public {
        int256 slope = int256(RAY / 1000);
        uint256 id = _createBuyOrder(alice, 100 ether, RAY, slope, 0);
        assertEq(exchange.getOrder(id).slope, slope);
    }

    function test_ordersByPair_registered() public {
        _createBuyOrder(alice, 100 ether, RAY, 0, 0);
        _createSellOrder(bob,  100 ether, RAY, 0, 0);
        assertEq(exchange.getOrdersByPair(address(tokenA), address(tokenB)).length, 2);
    }

    function test_createOrder_revert_zeroTokenIn() public {
        vm.prank(alice);
        vm.expectRevert(ZeroAddress.selector);
        exchange.createOrder(address(0), address(tokenB), 100 ether, RAY, 0, 0, 0, 0, true);
    }

    function test_createOrder_revert_zeroTokenOut() public {
        vm.prank(alice);
        vm.expectRevert(ZeroAddress.selector);
        exchange.createOrder(address(tokenA), address(0), 100 ether, RAY, 0, 0, 0, 0, true);
    }

    function test_createOrder_revert_sameToken() public {
        vm.prank(alice);
        vm.expectRevert(ZeroAddress.selector);
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
        exchange.createOrder(address(tokenA), address(tokenB), 100 ether, RAY, type(int128).max, 0, 0, 0, true);
    }

    function test_cancelOrder_success() public {
        uint256 amount = 200 ether;
        uint256 id = _createBuyOrder(alice, amount, RAY, 0, 0);
        uint256 balBefore = tokenA.balanceOf(alice);

        vm.expectEmit(true, true, false, true);
        emit WindmillExchange.OrderCancelled(id, alice, amount);

        vm.prank(alice);
        exchange.cancelOrder(id);

        assertFalse(exchange.getOrder(id).active);
        assertEq(tokenA.balanceOf(alice), balBefore + amount);
        assertEq(exchange.getOrdersByPair(address(tokenA), address(tokenB)).length, 0);
    }

    function test_cancelOrder_revert_notMaker() public {
        uint256 id = _createBuyOrder(alice, 100 ether, RAY, 0, 0);
        vm.prank(bob);
        vm.expectRevert(NotMaker.selector);
        exchange.cancelOrder(id);
    }

    function test_cancelOrder_revert_alreadyInactive() public {
        uint256 id = _createBuyOrder(alice, 100 ether, RAY, 0, 0);
        vm.prank(alice); exchange.cancelOrder(id);
        vm.prank(alice);
        vm.expectRevert(OrderInactive.selector);
        exchange.cancelOrder(id);
    }

    function testFuzz_escrow(uint96 amount) public {
        vm.assume(amount > 0);
        tokenA.mint(alice, amount);
        uint256 id = _createBuyOrder(alice, amount, RAY, 0, 0);
        assertEq(exchange.getOrder(id).remainingIn, amount);
    }
}
