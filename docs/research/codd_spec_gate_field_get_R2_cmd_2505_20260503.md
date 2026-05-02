# CoDD Spec: gate_field_get.sh R2

- cmd: `cmd_2505`
- worker: `saizo`
- target: `scripts/gates/gate_field_get.sh`, `scripts/lib/field_get.sh`
- phase: Phase 5 (spec + implementation + after verification)

## Purpose

Restore `gate_field_get.sh` to the CoDD target band by removing mutable live-YAML dependency and repeated large-file scans while preserving representative `field_get` / `field_get_multi` contract coverage.

## Before

Command:

```bash
bash scripts/gates/gate_field_get.sh
```

Observed 5-run wall time before changes:

```text
210ms, 180ms, 110ms, 80ms, 110ms
median: 110ms
```

The run also failed when `queue/tasks/hayate.yaml` had `status: assigned`; the gate allowed `pending|acknowledged|in_progress|completed|done|idle` but omitted the valid assigned state.

## Bottleneck

1. `gate_field_get.sh` read mutable live files (`queue/shogun_to_karo.yaml`, `queue/tasks/hayate.yaml`, `config/projects.yaml`, `config/settings.yaml`), so runtime depended on queue size and current agent state.
2. The live task status assertion was stale and rejected `assigned`.
3. `field_get` fallback for indented fields used `grep | awk`; missing or nested lookup paid two subprocesses.

## Implementation

1. Replaced live-file gate inputs with one deterministic YAML fixture under `/tmp`.
2. Read fixture scalar fields once with `field_get_multi`, then reused shell variables for assertions.
3. Kept direct `field_get` coverage for top-level scalar and block-array retrieval.
4. Changed `field_get` indented fallback from `grep | awk` to one `awk` scan.
5. Included `assigned` in the valid task status contract.

## After

Command:

```bash
for i in 1 2 3 4 5; do
  start=$(date +%s%N)
  bash scripts/gates/gate_field_get.sh >/dev/null
  end=$(date +%s%N)
  echo $(((end-start)/1000000))
done
```

Observed:

```text
32ms, 30ms, 40ms, 38ms, 46ms
median: 38ms
```

Result: `110ms → 38ms` (`-65.5%`), target `<=45ms` met.

## Verification

```bash
bash -n scripts/lib/field_get.sh scripts/gates/gate_field_get.sh
bash scripts/lib/field_get.sh --test
bash scripts/gates/gate_field_get.sh
bats tests/unit/test_field_get.bats
```

All passed.
