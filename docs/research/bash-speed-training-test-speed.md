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

## Cycle 2: idle-handler isolation

- Improvement 1 (implemented): [[test_bash_speed_training.bats]] test 15 exercised three unrelated pre-speed branches in `handle_confirmed_idle`; stub completion-check, reflux, and test-speed handlers so the test measures only the asserted speed-before-legacy ordering.
- Improvement 2: tests 14 and 15 each source [[ninja_monitor.sh]] in a fresh Bash; consider a shared focused fixture only if source time becomes dominant.
- Improvement 3: per-test ledger isolation still uses an ordinary copy; measure `cp --reflink=auto` before changing it because the fixture is already small and on ext4.

The production ordering remains anchored in [[ninja_monitor.sh]]: `_handle_test_speed_auto_deploy` precedes `_handle_speed_training_auto_deploy`, which precedes `_handle_training_auto_deploy`. The focused test still reaches the speed handler and asserts that legacy is never called.
