# cmd_2495 CoDD Spec — gate_silent_fallback.sh R3

## Scope

- Target: `scripts/gates/gate_silent_fallback.sh`
- Goal: restore the CoDD profiling fast path to <=30ms median 5run.
- Registry baseline: `docs/research/codd_refactor_registry.md` records `27ms -> 25ms` for the fast path.
- Current scout claim: `25ms -> 769ms` regression.

## Before Measurement

Measured on 2026-05-03 from `/mnt/c/tools/multi-agent-shogun`.

| Mode | Runs | Median | Notes |
|------|------|--------|-------|
| full audit, no args | `814, 781, 919, 644, 612ms` | `781ms` | Scans DM-Signal `backend/app`; matches cmd_2493 regression class |
| `--path /tmp/nonexistent` | `27, 31, 26, 17, 20ms` | `26ms` | Empty scan fast path |
| `--help` before | `6, 9, 6, 8, 6ms` | `6ms` | Incorrectly exited non-zero with `Unknown option: --help` |

## Bottleneck

The 769-781ms number is the full-audit path, not the previously registered fast path.
The full-audit path is dominated by WSL2 `/mnt/c` scan and block parsing, matching existing lesson L494:
`rg` is faster than `grep`, but block analysis and NTFS traversal dominate total runtime.

The actionable regression for the profiling contract is that `--help` was not implemented even though
`docs/research/codd_infra_script_profiling.md` profiles this script with `--help`.
That made the registry comparison ambiguous and allowed a full-audit measurement to be compared to a fast-path registry value.

## Design

1. Add a real `-h|--help` fast path before pattern arrays and scan setup.
2. Keep no-arg full-audit semantics unchanged. Changing no-arg behavior would hide PI-018 scan work.
3. Do not add a stale cache for full-audit. A cache can produce <=30ms but may hide newly introduced silent fallback violations.

## After Measurement

After implementing `--help`, median 5run:

```text
8ms rc=0
7ms rc=0
10ms rc=0
8ms rc=0
9ms rc=0
median: 8ms
```

Full-audit remains intentionally uncached and continues to report the existing five suspects.

## Validation

```bash
bash -n scripts/gates/gate_silent_fallback.sh
bash scripts/gates/gate_silent_fallback.sh --help
```
