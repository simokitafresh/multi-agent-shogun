# lesson_impact_analysis.sh CoDD Speed Note (2026-05-20)

## Scope

- Task: `cmd_training_speed_saizo_4`
- Target: `scripts/lesson_impact_analysis.sh`
- Mode measured for before/after: default summary mode, cold process execution.

## Before

Cold runs before implementation:

| run | rc | elapsed |
|-----|----|---------|
| 1 | 0 | 118ms |
| 2 | 0 | 135ms |
| 3 | 0 | 112ms |

Mode check before implementation:

| mode | elapsed |
|------|---------|
| summary | 150ms |
| `--detail L512` | 1200ms |
| `--sync-counters --dry-run` | 1335ms |

## Bottleneck Hypothesis

Default summary mode does not need lesson YAML parsing, but the script imported
`yaml`, `glob`, and `fcntl` at Python startup. Isolated startup checks showed
`import yaml` alone costs roughly 80-96ms on this WSL2 `/mnt/c` environment.

Expected low-risk improvement: lazy import PyYAML and filesystem helpers only in
the modes that need them (`--detail` and `--sync-counters`). Keep default summary
logic unchanged.

## CoDD Flow

Required flow attempted with timeout 1200:

```bash
codd extract --path . --source-dirs scripts --output .codd/extract/saizo_lesson_impact_20260520 --init
codd elicit --path . --format md
codd generate --path . --wave 1 --force
codd validate --path .
codd measure --path .
```

Observation: `codd extract` entered long-running full `scripts` extraction with
no output while other agents were running concurrent CoDD extracts. Final command
result is recorded in `/tmp/saizo_codd_lesson_impact_20260520.log`.

## Implementation

- Removed eager `glob` and `fcntl` imports from startup.
- Replaced eager PyYAML import with `require_yaml()`.
- Kept PyYAML required for `--detail` and `--sync-counters`.

## After

Cold runs after implementation:

| run | rc | elapsed |
|-----|----|---------|
| 1 | 0 | 118ms |
| 2 | 0 | 90ms |
| 3 | 0 | 81ms |
| 4 | 0 | 87ms |
| 5 | 0 | 69ms |

Median changed from 118ms to 87ms (`-26.3%`). The first after run was still
affected by concurrent CoDD work; runs 2-5 were 69-90ms.

## Verification

- `bash -n scripts/lesson_impact_analysis.sh`: PASS
- `bash scripts/lesson_impact_analysis.sh --detail L512`: PASS
- `bash scripts/lesson_impact_analysis.sh --sync-counters --dry-run`: PASS
- `bats tests/unit/test_test_select.bats`: 6/6 PASS, SKIP=0
