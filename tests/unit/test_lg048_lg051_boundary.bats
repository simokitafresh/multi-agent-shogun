#!/usr/bin/env bats
# test_necessity: LG048/LG051検査の境界不変量
# 不変量: (A) LG048散文result+axis/recount/actual非空→PASS自動正規化、空欄→BLOCK維持
#         (C) LG051 non-test caller countがresult.detailsに記載されている場合もPASS

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

# --- (A) LG048 boundary tests ---

@test "LG048: semantic_validation.result=PASS → ERRORS=0" {
  # test_necessity: 二値PASSの既存動作が維持される不変量
  local fixture
  fixture=$(mktemp --suffix=.yaml)
  cat > "$fixture" <<'YAML'
worker_id: test
status: completed
verdict: PASS
ac_version_read: abc12345
result:
  summary: test
binary_checks:
  AC1:
  - check: test
    result: 'yes'
semantic_validation:
  classification_axis: axis_a vs axis_b
  recount: count=10
  actual: detail here
  result: PASS
files_modified:
- path: scripts/gates/test.sh
  change: test
YAML
  run bash "$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck.sh" "$fixture"
  [[ "$output" != *"BLOCK(LG048)"* ]]
  rm -f "$fixture"
}

@test "LG048: semantic_validation.result=散文+axis/recount/actual非空 → PASS自動正規化" {
  # test_necessity: 散文resultがaxis/recount/actual非空で自動正規化される不変量
  local fixture
  fixture=$(mktemp --suffix=.yaml)
  cat > "$fixture" <<'YAML'
worker_id: test
status: completed
verdict: PASS
ac_version_read: abc12345
result:
  summary: "3 items x 12 months = 36 total"
binary_checks:
  AC1:
  - check: test
    result: 'yes'
semantic_validation:
  classification_axis: axis_a vs axis_b
  recount: "items=3; months=12; total=36"
  actual: detail here
  result: classification consistent and matches expected
files_modified:
- path: scripts/gates/test.sh
  change: test
YAML
  run bash "$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck.sh" "$fixture"
  [[ "$output" == *"INFO(LG048): semantic_validation.resultが散文→PASS自動正規化"* ]]
  [[ "$output" != *"BLOCK(LG048)"* ]]
  rm -f "$fixture"
}

@test "LG048: semantic_validation.result=空欄 → BLOCK維持" {
  # test_necessity: 空欄resultがBLOCKされる不変量
  local fixture
  fixture=$(mktemp --suffix=.yaml)
  cat > "$fixture" <<'YAML'
worker_id: test
status: completed
verdict: PASS
ac_version_read: abc12345
result:
  summary: "3 items x 12 months = 36 total"
binary_checks:
  AC1:
  - check: test
    result: 'yes'
semantic_validation:
  classification_axis: axis_a vs axis_b
  recount: "items=3; months=12; total=36"
  actual: detail here
  result:
files_modified:
- path: scripts/gates/test.sh
  change: test
YAML
  run bash "$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck.sh" "$fixture"
  [[ "$output" == *"BLOCK(LG048): semantic_validation.resultが空欄"* ]]
  rm -f "$fixture"
}

# --- (C) LG051 boundary test ---

@test "LG051: non-test caller count in result.details → PASS" {
  # test_necessity: result.detailsにcaller countがある場合もLG051検査がPASSする不変量
  local fixture
  fixture=$(mktemp --suffix=.yaml)
  cat > "$fixture" <<'YAML'
worker_id: test
status: completed
verdict: PASS
ac_version_read: abc12345
result:
  summary: gate修正
  details: "non-test caller count: 8. gate updated."
causal_verification:
  cause_checked: checked
  design_intent_checked: checked
  evidence: rg command here
files_modified:
- path: scripts/gates/gate_test.sh
  change: updated gate
binary_checks:
  AC1:
  - check: test
    result: 'yes'
YAML
  run python3 "$REPO_ROOT/scripts/gates/gate_report_format_main.py" "$fixture"
  [[ "$output" != *"LG051"* ]]
  rm -f "$fixture"
}
