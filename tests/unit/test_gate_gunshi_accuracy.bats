#!/usr/bin/env bats
# test_gate_gunshi_accuracy.bats — gate_gunshi_accuracy.sh 公正計算テスト

setup() {
    TEST_ROOT="${BATS_TEST_DIRNAME}/../.."
    TEST_TMP="$BATS_TEST_TMPDIR"
    # 最小fixtureのreview_log
    cat > "$TEST_TMP/review_log.yaml" <<'YAML'
- cmd_id: test_lgtm_clear
  review_type: report
  verdict: LGTM
  gate_prediction: CLEAR
  gate_result: CLEAR
- cmd_id: test_fail_block_clear
  review_type: report
  verdict: FAIL
  gate_prediction: BLOCK
  gate_result: CLEAR
- cmd_id: test_lgtm_warn_clear
  review_type: report
  verdict: LGTM
  gate_prediction: WARN
  gate_result: CLEAR
- cmd_id: test_lgtm_clear2
  review_type: report
  verdict: LGTM
  gate_prediction: CLEAR
  gate_result: CLEAR
YAML
}

@test "FAIL→BLOCK→CLEAR is counted as correct" {
    run python3 - "$TEST_TMP/review_log.yaml" <<'PY'
import re, sys
with open(sys.argv[1]) as f:
    content = f.read()
entries = content.split("\n- cmd_id:")[1:]
for e in entries:
    cmd_m = re.search(r"^[:\s]*(\S+)", e)
    pred_m = re.search(r"gate_prediction:\s*(\S+)", e)
    result_m = re.search(r"gate_result:\s*(\S+)", e)
    verdict_m = re.search(r"verdict:\s*(\S+)", e)
    if not (pred_m and result_m): continue
    cmd = cmd_m.group(1)
    if cmd == "test_fail_block_clear":
        verdict = verdict_m.group(1)
        pred = pred_m.group(1)
        result = result_m.group(1)
        correct = (verdict == "FAIL" and pred == "BLOCK" and result == "CLEAR")
        print(f"correct={correct}")
        assert correct, f"FAIL→BLOCK→CLEAR should be correct"
        break
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"correct=True"* ]]
}

@test "LGTM→WARN→CLEAR is counted as incorrect" {
    run python3 - "$TEST_TMP/review_log.yaml" <<'PY'
import re, sys
with open(sys.argv[1]) as f:
    content = f.read()
entries = content.split("\n- cmd_id:")[1:]
for e in entries:
    cmd_m = re.search(r"^[:\s]*(\S+)", e)
    pred_m = re.search(r"gate_prediction:\s*(\S+)", e)
    result_m = re.search(r"gate_result:\s*(\S+)", e)
    verdict_m = re.search(r"verdict:\s*(\S+)", e)
    if not (pred_m and result_m): continue
    cmd = cmd_m.group(1)
    if cmd == "test_lgtm_warn_clear":
        pred = pred_m.group(1)
        result = result_m.group(1)
        correct = (pred == result)
        print(f"correct={correct}")
        assert not correct, f"LGTM→WARN→CLEAR should be incorrect"
        break
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"correct=False"* ]]
}

@test "overall accuracy on fixture is 3/4 = 75%" {
    run bash "$TEST_ROOT/scripts/gates/gate_gunshi_accuracy.sh" "$TEST_TMP/review_log.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"75%"* ]]
}
