# Test-speed campaign same-run A/B contract

## Cause and frozen contracts

Historical `best_so_far` came from a different run environment, so comparing a
new candidate directly with it could label noise as improvement. Keep
`MIN_ROUNDS=2`, `MAX_ROUNDS=3`, the `complete-deploy` callback, unique report
identity, FAIL0/SKIP0, and last-good rollback behavior unchanged.

## Round measurement protocol

1. Resolve immutable last-good and candidate commit IDs.
2. Fix command, host, environment variables, dependency state, and test target.
3. Warm each commit once; warmups are excluded.
4. Alternate A/B order, reversing the first side on successive pairs, for at
   least 10 measured samples per side.
5. Store commits, exact command, equal sample count, and p50/p95 in the campaign
   ledger.
6. Commits must differ, `order` must equal `alternating`, and `warmup_each` must
   be at least one. When a sequence is supplied it must be exactly L,C repeated.

## Adoption and stop rules

- Adopt candidate only when candidate p50 <= last-good p50 and candidate p95 <=
  last-good p95, with at least one strict inequality.
- Any missing/non-numeric evidence blocks before deployment.
- Any p50 or p95 regression, or complete equality, records
  `ab_not_improved` and retains last-good.
- FAIL or SKIP stops the campaign; round 3 remains the hard maximum.
- Historical best is selection context only, never acceptance evidence.
- Plateau means no strict same-run improvement after valid A/B; do not create a
  further round unless another dominant interval is identified within round 2.

## Regression entry

`tests/unit/test_test_speed_task_generator.bats` verifies generated task
injection, complete-deploy preservation, missing evidence BLOCK, dual-metric
adoption, either-metric regression, equality, quality stop, and max-three stop.

Origin: [[historical best false improvement]] -> [[same run interleaved AB]] -> [[noise resistant campaign adoption]]
