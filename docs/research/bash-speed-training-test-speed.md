# Bash speed training test speed

## Direct links

- Test contract: [[test_bash_speed_training.bats]]
- Production implementation: [[bash_speed_training.sh]]

## Verified design anchor

`tests/unit/test_bash_speed_training.bats:5` defines `FIXTURE_ROOT="$(mktemp -d)"` once for the suite. Per-test directories therefore derive from that isolated root instead of launching `mktemp` for every case; the ledger copy still preserves mutation isolation.
