# test_select.sh CoDD設計書

metadata:
- cmd: `cmd_2584`
- source_spec: `docs/research/test_select_refactor_spec_20260506.md`
- target: `scripts/test_select.sh`
- generated_at: `2026-05-06`
- codd_cli: `1.10.0`

## Requirements

`scripts/test_select.sh` must keep the existing diff-aware contract:

- stdout: affected bats files, one path per line, sorted.
- stderr: `[test_select]` INFO/WARN messages.
- exit code: 0 for successful selection, including no mapping.
- unknown files: WARN and no full-test fallback.
- gate/deploy/cmd/report special cases: preserve broad related-test mappings.

## Before Profile

| Input | Before average |
|-------|----------------|
| `scripts/deploy_task.sh` | 11827ms |
| `scripts/gates/gate_report_format.sh` | 10184ms |
| `scripts/test_select.sh` | 10014ms |
| `tests/unit/test_yaml_field_set.bats` | 10602ms |
| `README.md` | 10120ms |

The bottleneck is L2 static reference analysis. The old design executed a recursive `find` across `scripts` and `lib` for each shell reference found in tests.

## Design

### R1: Single Script Index

Build `SCRIPT_PATHS_BY_BASENAME` once:

```bash
while IFS= read -r script_path; do
    script_base=$(basename "$script_path")
    rel_path="${script_path#"$REPO_ROOT"/}"
    SCRIPT_PATHS_BY_BASENAME["$script_base"]+="$rel_path "
done < <(find "$REPO_ROOT/scripts" "$REPO_ROOT/lib" -name '*.sh' 2>/dev/null)
```

Then L2 resolves each parsed shell reference by associative-array lookup instead of recursive `find`.

### R2: Focused Contract Tests

Add `tests/unit/test_test_select.bats` covering:

- `scripts/test_select.sh` selects its direct regression test.
- `scripts/gates/gate_report_format.sh` selects gate report tests.
- `README.md` returns 0 with WARN and no selected tests.

## Impact

| Input | Before | After | Improvement |
|-------|--------|-------|-------------|
| `scripts/deploy_task.sh` | 11827ms | 3609ms | -69.5% |
| `scripts/gates/gate_report_format.sh` | 10184ms | 4092ms | -59.8% |
| `scripts/test_select.sh` | 10014ms | 3823ms | -61.8% |
| `tests/unit/test_yaml_field_set.bats` | 10602ms | 4089ms | -61.4% |
| `README.md` | 10120ms | 4058ms | -59.9% |

## Validation

- `bats tests/unit/test_test_select.bats` PASS.
- `codd init --project-name test-select-refactor --language bash --requirements docs/research/test_select_refactor_spec_20260506.md` succeeded in `/tmp/codd_refactor_test_select_*`.
- `codd validate` reported OK for configured Markdown files.
- `codd plan --init` returned invalid wave_config YAML from AI output; manual CoDD design is therefore saved here as the durable design artifact.
