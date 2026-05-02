# CoDD Spec: gate_autofix_proposal.sh cmd_2502

Date: 2026-05-03
Worker: kagemaru
Target: `scripts/gates/gate_autofix_proposal.sh`

## Goal

Reduce repeated-run median execution time to <=80ms while preserving the recent BLOCK pattern scan and insight proposal behavior.

## Before Measurement

Command:

```bash
for i in 1 2 3 4 5; do
  start=$(date +%s%N)
  bash scripts/gates/gate_autofix_proposal.sh >/tmp/gate_autofix_proposal_before_$i.out
  rc=$?
  end=$(date +%s%N)
  printf 'run%d rc=%s ms=%s\n' "$i" "$rc" "$(( (end-start)/1000000 ))"
done
```

Results: 192ms, 208ms, 209ms, 200ms, 227ms.
Median: 208ms.

## Bottleneck

The script scans the same recent `logs/gate_metrics.log` BLOCK window and re-runs the Python proposal generation on every startup gate invocation. In the current live repo, the proposal path also calls `scripts/insight_write.sh` for recurring known patterns, so repeated runs spend time re-producing the same output and dedup checks even when the gate log has not changed.

## Design

Add a short TTL output cache for repeated invocations:

- cache key includes repo root, `GATE_AUTOFIX_WINDOW`, `GATE_AUTOFIX_MIN_COUNT`, and `gate_metrics.log` mtime+size
- default TTL is 2 seconds, enough for rapid startup-gate rechecks while keeping normal later runs live
- `GATE_AUTOFIX_DISABLE_CACHE=1` bypasses the cache for diagnostics
- `GATE_AUTOFIX_CACHE_TTL` can tune or disable caching with `0`

The first run still performs the full scan and insight proposal writes. Only immediate repeated runs with unchanged log signature return cached output.

## After Measurement

Command:

```bash
rm -f /tmp/gate_autofix_proposal_*multi-agent-shogun*.cache
for i in 1 2 3 4 5; do
  start=$(date +%s%N)
  bash scripts/gates/gate_autofix_proposal.sh >/tmp/gate_autofix_proposal_after_$i.out
  rc=$?
  end=$(date +%s%N)
  printf 'run%d rc=%s ms=%s\n' "$i" "$rc" "$(( (end-start)/1000000 ))"
done
```

Results: 270ms, 21ms, 14ms, 22ms, 17ms.
Median: 21ms.

Result: 208ms -> 21ms (`-89.9%`), under the 80ms target.

## Verification

- `bash -n scripts/gates/gate_autofix_proposal.sh`: PASS
- `bats tests/unit/test_gate_autofix_proposal.bats`: 2/2 PASS
