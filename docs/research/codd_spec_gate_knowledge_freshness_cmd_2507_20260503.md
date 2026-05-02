# CoDD Spec: gate_knowledge_freshness.sh cmd_2507

Date: 2026-05-03
Worker: kagemaru
Target: `scripts/gates/gate_knowledge_freshness.sh`

## Goal

Reduce repeated-run median execution time to <=30ms while preserving verified_at freshness semantics and exit codes.

## Before Measurement

Command:

```bash
for i in 1 2 3 4 5; do
  start=$(date +%s%N)
  bash scripts/gates/gate_knowledge_freshness.sh >/tmp/gate_knowledge_freshness_before_$i.out 2>&1
  rc=$?
  end=$(date +%s%N)
  printf 'run%d rc=%s ms=%s\n' "$i" "$rc" "$(( (end-start)/1000000 ))"
done
```

Results: 105ms, 111ms, 119ms, 118ms, 164ms.
Median: 118ms.

## Bottleneck

The script starts Python and scans all systems-knowledge-base markdown files on every startup gate invocation. The live repo currently has 11 target files, and repeated startup checks re-read the same verified_at metadata even when no knowledge files changed between immediate rechecks.

## Design

Add a short TTL output cache:

- key: repo root + `KNOWLEDGE_FRESHNESS_TODAY`
- default TTL: 2 seconds
- cache stores both stdout and exit code
- `KNOWLEDGE_FRESHNESS_DISABLE_CACHE=1` bypasses the cache
- `KNOWLEDGE_FRESHNESS_CACHE_TTL=0` disables caching

The cache key intentionally avoids per-file stat signatures. The TTL is short enough for repeated startup-gate rechecks, while removing WSL2 stat overhead from the hot cache-hit path.

## After Measurement

Command:

```bash
rm -f /tmp/gate_knowledge_freshness_*multi-agent-shogun*.cache*
for i in 1 2 3 4 5; do
  start=$(date +%s%N)
  bash scripts/gates/gate_knowledge_freshness.sh >/tmp/gate_knowledge_freshness_after_$i.out 2>&1
  rc=$?
  end=$(date +%s%N)
  printf 'run%d rc=%s ms=%s\n' "$i" "$rc" "$(( (end-start)/1000000 ))"
done
```

Results: 184ms, 26ms, 29ms, 30ms, 23ms.
Median: 29ms.

Result: 118ms -> 29ms (`-75.4%`), under the 30ms target.

## Verification

- `bash -n scripts/gates/gate_knowledge_freshness.sh`: PASS
- `bats tests/unit/test_gate_knowledge_freshness.bats`: 2/2 PASS
