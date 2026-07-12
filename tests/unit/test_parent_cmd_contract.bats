#!/usr/bin/env bats
setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd); T=$(mktemp -d)
  mkdir -p "$T/queue/tasks" "$T/queue/reports" "$T/queue/archive/cmds"
}
teardown() { rm -rf "$T"; }
parent() { cat > "$T/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_3869
    purpose: rotate safely
    acceptance_criteria:
      - {id: AC1, description: inventory}
      - {id: AC2, description: delete}
      - {id: AC3, description: rotate}
YAML
}
task() { cat > "$T/queue/tasks/ninja.yaml" <<'YAML'
task:
  parent_cmd: cmd_3869
  purpose: rotate safely
YAML
}
report() { printf 'parent_cmd: cmd_3869\nbinary_checks:\n%b\n' "$1" > "$T/queue/reports/ninja_report_cmd_3869.yaml"; }
@test "partial recon report cannot clear parent ACs" { parent; task; report '  AC1: [{check: inventory, result: yes}]'; run python3 "$ROOT/scripts/lib/parent_cmd_contract.py" cmd_3869 --root "$T"; [ "$status" -eq 1 ]; [[ "$output" == *'parent_ac_uncovered:AC2,AC3'* ]]; }
@test "missing SSOT and purpose mismatch fail closed" { task; report '  AC1: [{check: inventory, result: yes}]'; run python3 "$ROOT/scripts/lib/parent_cmd_contract.py" cmd_3869 --root "$T"; [ "$status" -eq 1 ]; parent; sed -i 's/rotate safely/wrong/' "$T/queue/tasks/ninja.yaml"; run python3 "$ROOT/scripts/lib/parent_cmd_contract.py" cmd_3869 --root "$T"; [ "$status" -eq 1 ]; [[ "$output" == *parent_purpose_unmatched* ]]; }
@test "complete single or multiple reports cover parent" { parent; task; report '  AC1: [{check: inventory, result: yes}]\n  AC2: [{check: delete, result: yes}]\n  AC3: [{check: rotate, result: yes}]'; run python3 "$ROOT/scripts/lib/parent_cmd_contract.py" cmd_3869 --root "$T"; [ "$status" -eq 0 ]; }
@test "direct hotfix is exempt" { run python3 "$ROOT/scripts/lib/parent_cmd_contract.py" cmd_karo_hotfix_x --root "$T"; [ "$status" -eq 0 ]; }
