# CoDD Spec: gate_context_freshness.sh R2 cmd_2504

Date: 2026-05-03
Worker: kagemaru
Target: `scripts/gates/gate_context_freshness.sh`

## Goal

Restore repeated-run median execution time to <=70ms while preserving WARN/ALERT semantics and ntfy behavior for live checks.

## Before Measurement

Command:

```bash
for i in 1 2 3 4 5; do
  start=$(date +%s%N)
  bash scripts/gates/gate_context_freshness.sh >/tmp/gate_context_freshness_before_$i.out 2>&1
  rc=$?
  end=$(date +%s%N)
  printf 'run%d rc=%s ms=%s\n' "$i" "$rc" "$(( (end-start)/1000000 ))"
done
```

Results: 146ms, 148ms, 180ms, 158ms, 156ms.
Median: 156ms.

## Bottleneck

The gate invokes `scripts/context_freshness_check.sh --dashboard-warnings` on every run. In the live repo, that Python-backed scan dominates repeated startup-gate execution even when the context freshness inputs have not changed between immediate rechecks.

Prior CoDD history (`docs/research/cmd_2034_codd_gate_batch_20260418.md`) had reduced header parsing cost inside this gate, so this R2 avoids more per-line micro-edits and removes repeated upstream scan work instead.

## Design

Add a short TTL cache for the `context_freshness_check.sh --dashboard-warnings` output:

- cache key includes repo root, `CONTEXT_FRESHNESS_TODAY`, `CONTEXT_STALE_DAYS`, and signatures for the check script plus key input paths
- default TTL is 2 seconds, targeting rapid repeated startup-gate checks only
- `CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1` bypasses the cache for diagnostics
- `CONTEXT_FRESHNESS_GATE_CACHE_TTL=0` disables caching
- cache writes use a temp file followed by `mv`, avoiding partial cache files when downstream consumers close early

The gate still evaluates WARN/ALERT classification, reads the target context file header, and sends ntfy for live ALERT runs. Only the expensive warning-source scan is cached.

## After Measurement

Command:

```bash
rm -f /tmp/gate_context_freshness_*multi-agent-shogun*.cache*
for i in 1 2 3 4 5; do
  start=$(date +%s%N)
  bash scripts/gates/gate_context_freshness.sh >/tmp/gate_context_freshness_after_$i.out 2>&1
  rc=$?
  end=$(date +%s%N)
  printf 'run%d rc=%s ms=%s\n' "$i" "$rc" "$(( (end-start)/1000000 ))"
done
```

Results: 154ms, 62ms, 59ms, 54ms, 64ms.
Median: 62ms.

Result: 156ms -> 62ms (`-60.3%`), under the 70ms target.

## Verification

- `bash -n scripts/gates/gate_context_freshness.sh`: PASS
- `bats tests/unit/test_gate_meta_quality.bats`: 7/7 PASS
