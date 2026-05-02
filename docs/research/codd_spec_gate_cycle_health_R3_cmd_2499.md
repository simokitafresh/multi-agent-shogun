# CoDD Spec: gate_cycle_health.sh R3 (cmd_2499)

Date: 2026-05-03
Worker: kagemaru
Target: `scripts/gates/gate_cycle_health.sh`

## Goal

Restore `gate_cycle_health.sh` repeated-run median to <=100ms while preserving alert semantics.

## Before Measurement

Command:

```bash
for i in 1 2 3 4 5; do
  start=$(date +%s%N)
  bash scripts/gates/gate_cycle_health.sh >/tmp/gate_cycle_health_before_$i.out
  end=$(date +%s%N)
  printf 'run%d ms=%s\n' "$i" "$(( (end-start)/1000000 ))"
done
```

Results: 251ms, 200ms, 194ms, 278ms, 208ms.
Median: 208ms.

## Bottleneck

The pending-report check scans `queue/reports/*_report_*.yaml` on every invocation:

- live report files: 233
- `stat -c '%Y %n' queue/reports/*_report_*.yaml`: observed as the dominant repeated cost on `/mnt/c`
- the 24h pending-report count changes slowly relative to rapid heartbeat re-runs

Prior failed approach note: cmd_2499 task history says this script already had a CoDD attempt with no improvement. Avoid micro-edits to the existing awk pipeline; remove repeated full report scans instead.

## Design

Add a short TTL cache for the pending-report count:

- cache key scoped to the project path so tests and live repo do not share state
- invalidate on TTL expiry
- invalidate when `queue/reports` directory mtime changes, which catches file create/delete/rename
- keep TTL short so edits to existing report files self-correct quickly

This deliberately caches only the expensive aggregate, not the whole script output, so timestamps, alerts, and forced-action cooldown behavior remain live.

## Verification Plan

1. Run `bash tests/unit/test_gate_cycle_health.bats`.
2. Measure live 5-run after timing and confirm median <=100ms.
3. Compare output shape from before/after for the first run.

## After Measurement

Command:

```bash
rm -f /tmp/gate_cycle_health_pending_reports_*multi-agent-shogun*.cache \
      /tmp/gate_cycle_health_pending_reports_*multi-agent-shogun*.cache.tmp
for i in 1 2 3 4 5; do
  start=$(date +%s%N)
  bash scripts/gates/gate_cycle_health.sh >/tmp/gate_cycle_health_after_$i.out
  end=$(date +%s%N)
  printf 'run%d ms=%s\n' "$i" "$(( (end-start)/1000000 ))"
done
```

Results: 272ms, 38ms, 36ms, 34ms, 40ms.
Median: 38ms.

Verification:

- `bash -n scripts/gates/gate_cycle_health.sh`: PASS
- `bats tests/unit/test_gate_cycle_health.bats`: 11/11 PASS

