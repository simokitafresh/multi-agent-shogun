# gunshi CS checklist test speed

## Baseline

- Timing ledger: 41 tests, 21.329 seconds, FAIL 0, SKIP 0.
- New-note incoming backlink baseline: 0.
- New-note direct file-link baseline: 0.

## Improvement candidates

1. Initial candidate: all 41 tests copy the same 1,599-line gate from `/mnt/c`; cache the immutable source once in `setup_file()`. The first run reached 24.244 seconds, so this was not the runtime bottleneck.
2. Every test recreates the same directory skeleton; a shared immutable skeleton plus mutable overlay can reduce filesystem calls.
3. Large YAML heredocs repeat a common review-entry schema; a fixture builder can reduce parsing and maintenance while preserving each scenario.

## Implemented change

[[test_gate_gunshi_cs_checklist.bats]] caches the production gate under `BATS_FILE_TMPDIR` once per suite. Its `setup_file()` states: “Cache the immutable 1,500+ line gate once per suite.” Mutable logs and the executable copy remain isolated per test.

Because fixture caching plateaued, [[gate_gunshi_cs_checklist.sh]] now consumes each file digest directly instead of hashing the textual `sha256sum` output a second time. Cache invalidation remains content-based while removing four external hash/awk stages from every invocation.

This applies the immutable-fixture boundary documented by [[karo-workaround-validation-test-speed]] without weakening any expectation or scenario.
