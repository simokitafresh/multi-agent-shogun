#!/usr/bin/env bats
# contract test: LG051 caller-evidence scope
# test_necessity: LG051のスコープ判定はbasename先頭一致ではなくトークン境界一致でなければ、
#                 cmd_complete_gate.sh のように語が中間・末尾にある実運用gateが検査対象外になる。
#                 同時に delegate/aggregate 等の部分文字列一致を拾って偽陽性を増やしてもならない。
# origin: [[cmd_karo_impl_lg051_scope_basename_20260725]] -> [[basename先頭一致による対象漏れ]] -> [[gate変更がcaller証跡なしで通過]]

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    MAIN="$REPO_ROOT/scripts/gates/gate_report_format_main.py"
    REPORT="$BATS_TEST_TMPDIR/report.yaml"
}

# $1=変更ファイルパス, $2=causal_verification.evidence
write_report() {
    cat > "$REPORT" <<YAML
worker_id: saizo
parent_cmd: cmd_lg051_fixture
ac_version_read: deadbeef
status: completed
files_modified:
  - path: $1
    change: fixture
causal_verification:
  cause_checked: fixture
  design_intent_checked: fixture
  evidence: "$2"
lesson_candidate:
  found: false
  no_lesson_reason: fixture
lessons_useful:
  - id: L001
    useful: false
    reason: fixture
binary_checks:
  AC1:
    - check: fixture
      result: "yes"
YAML
}

lg051_fired() {
    write_report "$1" "$2"
    run python3 "$MAIN" "$REPORT"
    [[ "$output" == *"LG051"* ]]
}

lg051_silent() {
    write_report "$1" "$2"
    run python3 "$MAIN" "$REPORT"
    [[ "$output" != *"LG051"* ]]
}

# 是正対象: 語がbasenameの中間・末尾にある実運用gate。旧regexでは対象外だった
@test "gate/hook token at the middle or tail of the basename is in scope" {
    lg051_fired "scripts/cmd_complete_gate.sh" ""
    lg051_fired "scripts/sync_git_hooks.sh" ""
    lg051_fired "scripts/lib/close_gate_alerts.py" ""
}

# 既存の正検出が壊れないこと(旧regexでも検出できていた形のみをここに置く)
@test "pre-existing detections still fire (gates/ hooks/ directory and gate-prefixed basename)" {
    lg051_fired "scripts/gates/gate_report_format.sh" ""
    lg051_fired "scripts/hooks/pre-commit.sh" ""
    lg051_fired "scripts/gate_alerts.sh" ""
}

# 偽陽性を増やさないこと: gateを部分文字列として含むだけの語は対象外
@test "substring-only matches stay out of scope (delegate/aggregate/propagate)" {
    lg051_silent "scripts/cmd_delegate.sh" ""
    lg051_silent "scripts/aggregate_metrics.sh" ""
    lg051_silent "scripts/deploy_task.sh" ""
}

# 証跡があれば対象でも通る(検査の緩和ではなく対象拡大であることの確認)
@test "in-scope change passes once non-test caller evidence is recorded" {
    lg051_silent "scripts/cmd_complete_gate.sh" "rg実測: non-test caller count: 8"
}

# test/fixtureは対象外。LG051が求めるのは「test/fixtureを除外した実運用caller数」であり
# test自身はgate実装ではない。トークン境界化でtestを巻き込みT-GP286-2をCI REDにした回帰の再発防止。
@test "test and fixture paths are out of scope even when the name contains gate/hook" {
    lg051_silent "tests/test_gate_report_format.bats" ""
    lg051_silent "tests/unit/test_cmd_complete_gate.bats" ""
    lg051_silent "tests/fixtures/gate_sample.sh" ""
}

# 除外は「置き場所」で判定する。basenameのtest_接頭辞で除外すると本番hookを取りこぼす
@test "production hooks named test_* stay in scope (location decides, not the prefix)" {
    lg051_fired "scripts/hooks/test_hooks.sh" ""
    lg051_fired "scripts/hooks/test_result_guard.sh" ""
}
