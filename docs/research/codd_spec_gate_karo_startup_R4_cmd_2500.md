# CoDD Spec: gate_karo_startup.sh R4 (cmd_2500)

Date: 2026-05-03
Worker: saizo
Target: `scripts/gates/gate_karo_startup.sh`

## Goal

Restore startup gate median runtime to the historical 110ms class without dropping checks or weakening output semantics.

## Before Measurement

Command:

```bash
for i in 1 2 3 4 5; do
  rm -f /tmp/karo_wa_rate_cache /tmp/karo_ninja_wa_cache /tmp/deepdive_*.cache
  /usr/bin/time -f "%e" bash scripts/gates/gate_karo_startup.sh >/tmp/gate_karo_startup_before_$i.out
done
```

Result: `0.34, 0.37, 0.30, 0.37, 0.34` seconds. Median: **340ms**.

Warm-cache reference before this cmd:

```text
0.35, 0.33, 0.35, 0.31, 0.32 seconds
```

Median: **330ms**.

## Bottleneck Split

`PS4='+$EPOCHREALTIME:${LINENO}: ' bash -x scripts/gates/gate_karo_startup.sh` showed these dominant waits before implementation:

| Component | Cost | Cause |
|---|---:|---|
| `skill_execution_log.sh summary` | ~153ms | Full skill log summary is recomputed every startup. |
| six task status reads | ~70ms total | One `awk` process per ninja task YAML on `/mnt/c`. |
| scalar YAML/log checks | ~80ms total | inbox, GP pending, pending decisions, workaround trend, orphan cmd checks each spawned separate `awk`. |

The previous R3 attempts focused on WA-rate caching, but the current bottleneck had shifted to skill summary and many small `/mnt/c` reads.

## Design

1. Add a signature-keyed aggregate cache for the scalar YAML/log checks.
2. Compute task statuses, inbox unread count, GP pending count, pending decisions, workaround trend, and orphan cmd count in one `awk` pass.
3. Run the aggregate pass in parallel with existing metadata collection.
4. Add a signature-keyed cache for skill summary output so unchanged `logs/skill_execution_log.yaml` avoids the 150ms recomputation.

The aggregate cache key uses mtime+size of source files, so changed queue/log files invalidate the cache.

## After Measurement

Command:

```bash
bash scripts/gates/gate_karo_startup.sh >/tmp/warm_cache.out
for i in 1 2 3 4 5; do
  /usr/bin/time -f "%e" bash scripts/gates/gate_karo_startup.sh >/tmp/gate_karo_after_cached_alone_$i.out
done
```

Result: `0.19, 0.10, 0.10, 0.11, 0.12` seconds. Median: **110ms**.

AC threshold: **<=130ms**. Result: PASS.

## Verification

```bash
bash -n scripts/gates/gate_karo_startup.sh
bats tests/unit/test_gate_karo_startup.bats
```

Result: `16/16` tests passed.
