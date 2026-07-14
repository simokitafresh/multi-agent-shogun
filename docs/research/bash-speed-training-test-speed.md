# Bash speed training test speed

## Direct links

- Test contract: [[test_bash_speed_training.bats]]
- Production implementation: [[bash_speed_training.sh]]
- Training policy: [[training-cycle.md]]

## Verified design anchor

`tests/unit/test_bash_speed_training.bats:5` defines `FIXTURE_ROOT="$(mktemp -d)"` once for the suite. Per-test directories therefore derive from that isolated root instead of launching `mktemp` for every case; the ledger copy still preserves mutation isolation.

## Measured follow-up

- Baseline: 15 tests in 5.36 seconds after the shared-fixture change (original ledger baseline: 111.69 seconds).
- Improvement 1 (implemented): production `init-ledger` syntax inventory was the dominant cost. Raising its bounded default concurrency from 8 to 16 reduced isolated initialization from 4.38 seconds to 3.55 seconds. The 32-job probe reached 2.90 seconds in isolation but degraded the shared-host suite to 25.02 seconds, so it was rejected.
- Improvement 2: each setup still copies the shared ledger once; a future profile should confirm whether copy-on-write or selective reset beats this without leaking mutations.
- Improvement 3: each setup still sources `tools/bash_speed_training.sh`; optimize parse/source time only if a follow-up profile shows it has become dominant.

The governing constraint is quoted from [[training-cycle.md]]: “FAIL→即停止・原因報告。PASS→次ACへ。” Speed work must not weaken expectations or introduce SKIP.
