#!/usr/bin/env bats
# test_necessity: gate_wa_data_quality must detect every workaround=true/category=clean contradiction independent of detail, atomically repair only those contradictions, and leave valid clean and real-WA entries unchanged.

GATE="$BATS_TEST_DIRNAME/../../scripts/gates/gate_wa_data_quality.sh"

setup() {
    export TEST_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/wa-quality.XXXXXX")"
    export WA_FILE="$TEST_DIR/karo_workarounds.yaml"
}

teardown() {
    rm -rf "$TEST_DIR"
}

write_fixture() {
    : > "$WA_FILE"
    for i in $(seq 1 9); do
        cat >> "$WA_FILE" <<YAML
- cmd_id: cmd_bad_$i
  ninja: hanzo
  workaround: true
  category: clean
  detail: 'adversarial detail $i without clean keywords'
  root_cause: 'contradictory state'
YAML
    done
    cat >> "$WA_FILE" <<'YAML'
- cmd_id: cmd_valid_clean
  ninja: hanzo
  workaround: false
  category: clean
  detail: ''
  root_cause: ''
- cmd_id: cmd_valid_wa
  ninja: hanzo
  workaround: true
  category: report_yaml_format
  root_signature: 'report_yaml_format::schema_shape'
  detail: 'report schema was malformed'
  root_cause: 'setter contract bypassed'
YAML
}

@test "detects and atomically fixes 9 clean contradictions with FP0 FN0" {
    write_fixture
    valid_before=$(python3 - "$WA_FILE" <<'PY'
import hashlib, sys, yaml
rows = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
valid = [row for row in rows if row["cmd_id"].startswith("cmd_valid_")]
print(hashlib.sha256(repr(valid).encode()).hexdigest())
PY
)

    run env WA_FILE="$WA_FILE" bash "$GATE"
    [ "$status" -ne 0 ]
    [ "$(printf '%s\n' "$output" | grep -c 'CLEAN_CONTRADICTION\[')" -eq 9 ]
    [[ "$output" != *"cmd_valid_clean — workaround=true"* ]]
    [[ "$output" != *"cmd_valid_wa — workaround=true with category=clean"* ]]

    run env WA_FILE="$WA_FILE" bash "$GATE" --fix
    [ "$status" -ne 0 ]
    [[ "$output" == *"FIXED: 9 changes applied"* ]]

    run python3 - "$WA_FILE" "$valid_before" <<'PY'
import hashlib, sys, yaml
rows = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
bad = [row for row in rows if row.get("workaround") is True and row.get("category") == "clean"]
valid = [row for row in rows if row["cmd_id"].startswith("cmd_valid_")]
assert len(bad) == 0, bad
assert hashlib.sha256(repr(valid).encode()).hexdigest() == sys.argv[2]
assert sum(row.get("workaround") is False and row.get("category") == "clean" for row in rows) == 10
assert sum(row.get("workaround") is True and row.get("category") == "report_yaml_format" for row in rows) == 1
PY
    [ "$status" -eq 0 ]

    run env WA_FILE="$WA_FILE" bash "$GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: no data quality issues"* ]]
}
