# ac_physical_verify.sh CoDD Speed Round (2026-05-20)

## Scope

- Agent: kagemaru
- Target: `scripts/ac_physical_verify.sh`
- Task: `cmd_training_speed_kagemaru_4`
- Method: brownfield-only CoDD speed improvement. `codd require` / `codd spec` were not used.

## Before Measurement

Command:

```bash
printf '%s\n' 'AC1 scripts/ac_physical_verify.sh L1 context/infrastructure.md §1' \
  | bash scripts/ac_physical_verify.sh -
```

Cold process runs:

| run | real |
|-----|------|
| 1 | 0.46s |
| 2 | 0.25s |
| 3 | 0.30s |
| 4 | 0.20s |
| 5 | 0.21s |

Median: 0.25s.

## Bottleneck Hypothesis

The script repeated fixed-cost work:

- Non-stdin cmd mode launched Python three times to read the same YAML file.
- The main verifier reopened and reread every extracted file for path counts, line references, and section references.
- `git check-ignore` was invoked once per path instead of once with `--stdin`.

This is a WSL2 `/mnt/c` fixed-cost pattern: process startup and repeated file reads dominate small shell tools more than the Python loop body.

## CoDD Execution

| Step | Command | Result |
|------|---------|--------|
| extract | `timeout 1200 /home/simokitafresh/.codd-venv/bin/codd extract --path . --source-dirs scripts --output codd/extracted/ac_physical_verify_20260520 --language bash` | exit 0; extracted 0 modules; wrote `codd/extracted/ac_physical_verify_20260520/` |
| elicit | `timeout 1200 /home/simokitafresh/.codd-venv/bin/codd elicit --path . --format md` | exit 0; `findings=10`, wrote `findings.md` |
| generate | `timeout 1200 /home/simokitafresh/.codd-venv/bin/codd generate --wave 1 --force --path .` | exit 0; generated `docs/test/acceptance_criteria.md` and `docs/governance/adr_yaml_batch_operations.md` |
| validate | `timeout 1200 /home/simokitafresh/.codd-venv/bin/codd validate --path .` | exit 1; pre-existing CoDD graph gaps: undefined `design:script:clear-prep-check` and wave_config nodes not generated under scanned doc dirs |
| measure | `timeout 1200 /home/simokitafresh/.codd-venv/bin/codd measure --path .` | exit 0; health score 85/100 |

## Implementation

Minimal change in `scripts/ac_physical_verify.sh`:

- Moved cmd YAML loading, project directory detection, and LG021 AC-count warning into the main Python verifier.
- Cached each verified file's lines once and reused them for line and section checks.
- Replaced per-path `git check-ignore -q` subprocesses with one `git check-ignore --stdin` batch.

No output contract was intentionally changed.

## After Measurement

Same command and fixture as before:

| run | real |
|-----|------|
| 1 | 0.20s |
| 2 | 0.18s |
| 3 | 0.19s |
| 4 | 0.21s |
| 5 | 0.25s |

Median: 0.20s.

Improvement: 0.25s -> 0.20s, -20.0%.

## Verification

| Check | Result |
|-------|--------|
| `bash -n scripts/ac_physical_verify.sh` | PASS |
| Representative smoke run | PASS |
| `bash scripts/test_select.sh scripts/ac_physical_verify.sh` | PASS with WARN: no direct mapping |
| `bats tests/unit/test_test_select.bats` | PASS, 6/6, SKIP=0 |

## Notes

The largest remaining fixed cost is the single Python verifier process and reading large referenced files for line/section output. Further improvement would require reducing optional output work or adding a fast mode, which would change the script contract and was outside this minimal round.
