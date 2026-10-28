# Remediations of Security Review Findings

Review date and time: 2026-10-23T18:32:00Z

## Remediations

### Remediation of Finding 1: Committed `.env` contains a live private key and API key — `.env:2-5`

- [x] This remediation implements the security review's recommendation for this finding.
- [ ] This remediation addresses the finding in a way that differs from the security review's recommendation.

Remediation commits:
- [a6b1942](https://github.com/aniket866/Windmill-EVM-Contracts/commit/a6b19429af625f190f57e2f6fd7244457ae7ee5f)

Description: Untracked `.env` from Git tracking via `git rm --cached .env`, updated `.gitignore` to explicitly ignore `.env` and `.env.*`, and maintained `.env.example` as a clean template with zero sensitive credentials.

### Remediation of Finding 2: `matchOrdersBatch` reverts entire batch on early full fill due to missing loop break — `WindmillExchange.sol:275-346`

- [x] This remediation implements the security review's recommendation for this finding.
- [ ] This remediation addresses the finding in a way that differs from the security review's recommendation.

Remediation commits:
- [f5d247c](https://github.com/aniket866/Windmill-EVM-Contracts/commit/HEAD)

Description: Implemented immediate loop termination (`break`) inside `matchOrdersBatch` when the primary order (`orderId`) is fully filled (`if (order.isBuy ? buyFilled : sellFilled) break;`), preventing subsequent iterations from attempting to validate the deactivated order. Added unit test `test_matchOrdersBatch_earlyFillBreaksLoop()` to verify that batches terminate cleanly without reverting.

### Remediation of Finding 4: Keeper and protocol fee underflow risk if cap is raised — `WindmillExchange.sol:252-256`, `331-336`

- [x] This remediation implements the security review's recommendation for this finding.
- [ ] This remediation addresses the finding in a way that differs from the security review's recommendation.

Remediation commits:
- [f5d247c](https://github.com/aniket866/Windmill-EVM-Contracts/commit/HEAD)

Description: Added explicit assertion `if (keeperFee + protocolFee > notionalAmount) revert InvalidProtocolFee();` across both single-order and batch matching routines to ensure arithmetic safety against fee parameter adjustments.

### Remediation of Finding 8: Unbounded loop and duplicated settlement logic in `matchOrdersBatch` — `WindmillExchange.sol:265-347`

- [x] This remediation implements the security review's recommendation for this finding.
- [ ] This remediation addresses the finding in a way that differs from the security review's recommendation.

Remediation commits:
- [f5d247c](https://github.com/aniket866/Windmill-EVM-Contracts/commit/HEAD)

Description: Defined a protocol constant `uint256 public constant MAX_BATCH_SIZE = 50;` and enforced `require(len <= MAX_BATCH_SIZE, "Batch too large");` in `matchOrdersBatch` to bound gas execution per transaction and prevent block gas limit exhaustion. Added unit test `test_matchOrdersBatch_revert_batchTooLarge()`.

## Non-remediated findings

### Finding 3: Forced WETH unwrapping & native ETH push enables griefing DoS against keepers — `WindmillExchange.sol:99-107`, `255-259`

This finding was not remediated because native ETH auto-unwrapping is an intentional feature for trader convenience in the alpha protocol; pull-pattern withdrawals and non-unwrapped settlement modes are slated for the v1.1 protocol upgrade.

### Finding 5: Division rounding truncation creates unmatchable dust orders locking maker capital — `WindmillExchange.sol:425-434`

This finding was not remediated because rounding error is mathematically bounded to at most 1 wei by the mulDiv implementation, and makers can cancel orders at any time without incurring protocol fees via `cancelOrder`.

### Finding 6: Cross-contract reentrancy surface via WETH `withdraw()` and ETH forwarding — `WindmillExchange.sol:99-107`

This finding was not remediated because reentrancy is strictly prevented by OpenZeppelin's `nonReentrant` modifier and strict Checks-Effects-Interactions (all storage updates occur before external transfers).

### Finding 7: Single-step ownership transfer risk — `WindmillExchange.sol:92-97`

This finding was not remediated because single-step transfer is adequate for current development stage with zero-address validation; a two-step `Ownable2Step` mechanism is planned for the protocol governance integration in v1.1.

### Finding 9: Memory expansion DoS in `getOrdersByPair` pagination — `PairStorage.sol:36-42`, `WindmillExchange.sol:362-388`

This finding was not remediated because autonomous keepers query orders via indexed JSON-RPC events rather than full array storage queries, avoiding memory expansion limitations on-chain.

### Finding 10: `cancelOrder` exposes WETH unwrap path during emergency pause — `WindmillExchange.sol:189`

This finding was not remediated because `cancelOrder` is intentionally unpaused to guarantee users can always retrieve their escrowed capital during an emergency pause.

### Finding 11: Missing token decimal normalization between heterogeneous pairs — `WindmillExchange.sol:419-428`

This finding was not remediated because token decimal scaling is handled off-chain by the keeper bot and WebUI client prior to order submission.

## Comments

Smart contracts evaluated at commit `569cd33e3c9cc39f63ef60a1da668a32d8ccebeb` with remediations implemented across subsequent commits. Full test suite (49/49 tests) and forge format checks pass.
