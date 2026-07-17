#!/usr/bin/env bats

setup() {
    REPORT="$BATS_TEST_TMPDIR/report.yaml"
    eval "$(sed -n '/_sg_pre27_check()/,/^}/p' scripts/gates/gate_gunshi_report_precheck.sh)"
}

@test "SG-PRE27 blocks verify function evidence without a standalone command" {
    cat > "$REPORT" <<'YAML'
result:
  details: "verify_sheets() returned true"
operational_simulation:
  command: "echo copied evidence"
  actual: "true"
  result: PASS
YAML
    run _sg_pre27_check "$REPORT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"commandにverify_sheetsの単体実行証跡がない"* ]]
}

@test "SG-PRE27 passes matching standalone command with actual PASS evidence" {
    cat > "$REPORT" <<'YAML'
result:
  details: "verify_sheets() returned true"
operational_simulation:
  command: "bash -lc 'source scripts/check.sh; verify_sheets'"
  expected: "return 0"
  actual: "return 0; output=true"
  result: PASS
YAML
    run _sg_pre27_check "$REPORT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS(LG040)"* ]]
}

@test "SG-PRE27 does not accept a different verify function in command" {
    cat > "$REPORT" <<'YAML'
result:
  details: "verify_sheets() returned true"
operational_simulation:
  command: "verify_database"
  actual: "return 0"
  result: PASS
YAML
    run _sg_pre27_check "$REPORT"
    [ "$status" -eq 2 ]
}

@test "SG-PRE27 blocks a matching command whose measured result failed" {
    cat > "$REPORT" <<'YAML'
result:
  details: "validate_payload() was invoked"
operational_simulation:
  command: "validate_payload"
  actual: "return 1"
  result: FAIL
YAML
    run _sg_pre27_check "$REPORT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"resultがPASSではない"* ]]
}

@test "SG-PRE27 ignores prose that does not contain a bounded function call" {
    cat > "$REPORT" <<'YAML'
result:
  details: "verify_sheets の設計だけを説明した。not_verify_sheets()も対象外"
YAML
    run _sg_pre27_check "$REPORT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"対象外確認済み"* ]]
}

@test "SG-PRE27 requires actual return-value evidence" {
    cat > "$REPORT" <<'YAML'
result:
  details: "readback_rows() returned true"
operational_simulation:
  command: "readback_rows"
  actual: ""
  result: PASS
YAML
    run _sg_pre27_check "$REPORT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"戻り値の実測がない"* ]]
}
