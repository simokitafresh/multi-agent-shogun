# Script-speed same-environment A/B contract

## Decision

Historical ledger timings select candidates only. Adoption compares the last-good commit and candidate commit in one fixed environment with the exact same command; old baseline values never decide completion.

## Measurement protocol

1. Resolve immutable last-good and candidate commits and verify hook/gate health.
2. Fix command, inputs, working directory, environment variables, CPU-affinity policy, and timeout.
3. Warm up both revisions without recording those observations.
4. Alternate A/B order for at least 10 recorded samples per arm, swapping the first arm between pairs to reduce drift bias.
5. Store both commits, the exact command, sample count, and p50/p95 for both arms through `record-real`.

## Adoption and rollback

`completed` is allowed only when candidate p50 and p95 are each no slower than last-good and at least one is strictly faster. Missing A/B evidence, fewer than 10 samples per arm, historical-only comparison, unresolved hook/gate failure, or regression in either percentile blocks adoption. A non-improving candidate is recorded `saturated`; `commit` remains last-good, so `re-enqueue` cannot promote the regressing candidate.

The `record-real` command name and the existing ledger keys `before_real_ms`, `after_real_ms`, `real_measurement_command`, `test_result`, and `commit` remain available. Their values now mirror last-good p50, candidate p50, the shared command, validation evidence, and the adopted commit respectively; explicit A/B fields carry the full contract.
