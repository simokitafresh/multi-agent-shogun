# CoDD Spec: gate_wa_data_quality R2 (cmd_2503)

- Date: 2026-05-03
- Worker: hayate
- Target: `scripts/gates/gate_wa_data_quality.sh`
- Goal: restore the check-mode median to <=60ms while preserving `--fix` behavior.

## Phase 1: Baseline

Command:

```bash
for i in 1 2 3 4 5; do
  /usr/bin/time -f '%e' bash scripts/gates/gate_wa_data_quality.sh >/tmp/gate_wa_out_$i
  sleep 1
done
```

Result:

| Run | Exit | Time |
|-----|------|------|
| 1 | 1 | 0.12s |
| 2 | 1 | 0.13s |
| 3 | 1 | 0.11s |
| 4 | 1 | 0.12s |
| 5 | 1 | 0.10s |

Median: 0.12s (120ms). This misses the <=60ms acceptance criterion.

Observed output: `ISSUES: 95`, dominated by duplicate WA entries in `logs/karo_workarounds.yaml`.

## Phase 2: Bottleneck

The default check path launches Python and parses the full 6,538-line, 160KB YAML with PyYAML even though it only needs five scalar fields:

- `cmd_id`
- `ninja`
- `workaround`
- `category`
- `detail`

The `--fix` path still needs YAML round-trip behavior, but the normal check path only reports issues and never rewrites the file.

## Phase 3: Design

Use a split path:

- default check mode: line-oriented awk scan that extracts the required scalar fields and emits the same issue classes.
- `--fix` mode: keep the existing Python/PyYAML implementation, including wrapper dict preservation and atomic rewrite.

This keeps the mutation path conservative while moving the frequent read-only gate path away from Python startup and full YAML parsing.

## Phase 4: Implementation

Changed `scripts/gates/gate_wa_data_quality.sh`:

- added an early `FIX_MODE=false` awk scanner.
- preserved existing Python code for `--fix`.
- preserved output shape: `PASS`, `ISSUES`, issue lines, and `Run with --fix to auto-repair`.

Added coverage in `tests/unit/test_gate_meta_quality.bats`:

- check mode detects `FALSE_WA` and `DUPLICATE`.
- check mode does not rewrite the source file.

## Phase 5: After

Command:

```bash
for i in 1 2 3 4 5; do
  /usr/bin/time -f '%e' bash scripts/gates/gate_wa_data_quality.sh >/tmp/gate_wa_final_$i.out
  sleep 1
done
```

Result:

| Run | Exit | Time |
|-----|------|------|
| 1 | 1 | 0.06s |
| 2 | 1 | 0.06s |
| 3 | 1 | 0.05s |
| 4 | 1 | 0.05s |
| 5 | 1 | 0.05s |

Median: 0.05s (50ms), meeting the <=60ms acceptance criterion.

Validation:

```bash
bash -n scripts/gates/gate_wa_data_quality.sh
bats tests/unit/test_gate_meta_quality.bats --filter 'gate_wa_data_quality'
```

Result: syntax PASS, Bats 3/3 PASS.
