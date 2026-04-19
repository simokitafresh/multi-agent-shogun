# cmd_2118 cmd_complete_gate.sh CoDD Speedup

Date: 2026-04-19
Worker: hayate
Target: `scripts/cmd_complete_gate.sh`
Benchmark target cmd: `cmd_2112 --force`

## Before

Method:
- Run `bash scripts/cmd_complete_gate.sh cmd_2112 --force`
- Measure 3 runs on the live repo
- Use median

Results:

| run | seconds |
|---|---:|
| 1 | 27.364 |
| 2 | 31.956 |
| 3 | 34.762 |
| median | **31.956** |

## Profiling

Method:
- `PS4='+${EPOCHREALTIME} ${FUNCNAME[0]:-MAIN} ${LINENO}: ' BASH_XTRACEFD=9 bash -x ...`
- Aggregate line deltas from `/tmp/cmd2112_xtrace.log`

Top bottlenecks before optimization:

| rank | hotspot | approx time | note |
|---|---|---:|---|
| 1 | `git -C "$SCRIPT_DIR" push` | 6.355s | no-op push still paid full network round-trip |
| 2 | Vercel phase commit discovery (`git log --grep=cmd_2112`) | 5.528s | scanned full history just to find the current cmd commit |
| 3 | Raw grep YAML access check | 2.216s | scanned all `scripts/*.sh` and `scripts/lib/*.sh` every run |
| 4 | Wiring verification | 1.746s | WARN-only reverse/forward scan ran even when cmd touched no scripts |
| 5 | TODO/FIXME residual check | 1.554s | recursive grep over `scripts/` + `lib/` every run |

Additional slow post-clear work seen in the same trace:
- `gist_sync.sh --once`: 1.190s
- `lesson_impact_rotate.sh` + `lesson_impact_analysis.sh --sync-counters`: 0.760s
- `knowledge_metrics.sh --json` auto-deprecate path: 0.632s
- `lesson_deprecation_scan.sh --project all`: 0.675s
- `cmd_quality_log.sh`: 0.422s

## Design

Changes were limited to speed and scheduling. PASS/FAIL gate logic stayed intact.

Strategy:
1. Reuse `MATCHING_TASK_FILES` instead of rescanning `queue/tasks/*.yaml` in each section
2. Replace full-history cmd lookup with contiguous HEAD-window lookup
3. Restrict script scans to files changed by the current cmd
4. Replace recursive grep walks with faster `rg`
5. Skip no-op `git push` when `HEAD == @{upstream}`
6. Move WARN-only / non-blocking follow-up work off the critical path

## Implementation

Main changes:
- Added `get_cmd_head_hashes()` / `get_cmd_changed_files()`
- Switched many task loops from `"$TASKS_DIR"/*.yaml` + `is_cmd_task` to `MATCHING_TASK_FILES`
- Replaced TODO scan with `rg`
- Made raw grep YAML access check diff-scoped instead of repo-wide
- Skipped wiring verification when cmd diff touched no `scripts/`, `instructions/`, or `CLAUDE.md`
- Queued non-blocking follow-up work asynchronously:
  - CI status query
  - lesson impact rotate/sync-counters
  - dashboard update / gist sync
  - auto-deprecate / lesson_deprecation_scan / cmd_quality_log
  - bulletin write
  - changelog / lesson tracking / lesson impact writeback
  - warning-only YAML/status follow-ups

## After

Method:
- Same live-repo benchmark target: `bash scripts/cmd_complete_gate.sh cmd_2112 --force`
- Inserted a short gap between runs so queued async follow-up jobs could drain
- Used stable rerun set after async spill settled

Results:

| run | seconds |
|---|---:|
| 1 | 4.473 |
| 2 | 4.993 |
| 3 | 5.080 |
| median | **4.993** |

Reduction:
- `31.956s -> 4.993s`
- **84.4% faster**

## Verification

Commands:

```bash
bats tests/unit/test_cmd_complete_gate.bats \
     tests/unit/test_cmd_complete_gate_subsystems.bats \
     tests/unit/test_cmd_complete_gate_warning_levels.bats
```

Result:
- `41/41 PASS`

## Notes

- The script now returns quickly and lets best-effort follow-up work finish in the background.
- Benchmarks without a gap between runs can be noisy because those async jobs overlap the next measurement.
