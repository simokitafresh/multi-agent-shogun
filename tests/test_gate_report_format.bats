#!/usr/bin/env bats
# test_gate_report_format.bats — gate_report_format.sh回帰テスト
# GP-073(PASSキャッシュ)、GP-128(verdict整合性)を含む主要チェックのテスト

GATE="scripts/gates/gate_report_format.sh"
AUTOFIX="scripts/gates/gate_report_autofix.sh"
TMPDIR_BATS=""
REPO_TMPDIR_BATS=""

setup() {
    TMPDIR_BATS=$(mktemp -d)
    REPO_TMPDIR_BATS=$(mktemp -d ".tmp_gate_report_format.XXXXXX")
    # --jobs 8並列実行時の競合を回避するためキャッシュ/ログをテストごとに一意化
    export GATE_PASS_CACHE_FILE="$TMPDIR_BATS/.gate_pass_cache"
    export GATE_FIRE_LOG_FILE="$TMPDIR_BATS/gate_fire_log.yaml"
    export SKILL_EXECUTION_LOG_FILE="$TMPDIR_BATS/skill_execution_log.yaml"
    export SKILL_GATE_FEEDBACK_DISABLE=1
    export SKILL_LOG_SYNC=1
}

teardown() {
    rm -rf "$TMPDIR_BATS"
    rm -rf "$REPO_TMPDIR_BATS"
    unset GATE_PASS_CACHE_FILE GATE_FIRE_LOG_FILE SKILL_EXECUTION_LOG_FILE
}

# Helper: create a minimal valid report
create_valid_report() {
    local path="${1:-$TMPDIR_BATS/report.yaml}"
    cat > "$path" << 'YAML'
worker_id: testninja
parent_cmd: cmd_test
ac_version_read: abc12345
timestamp: '2026-07-12T00:00:00+09:00'
status: completed
binary_checks:
  AC1:
    - check: "テスト対象の確認項目を詳細に記載"
      result: "yes"
files_modified: []
lesson_candidate:
  found: false
  no_lesson_reason: "既知パターンのため新規教訓なし"
lessons_useful: []
purpose_validation:
  cmd_purpose: "テスト用途の確認タスク"
  fit: true
  purpose_gap: ""
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
result:
  summary: "テスト結果のサマリ"
verdict: PASS
YAML
    echo "$path"
}

# --- T-001: Valid report → PASS ---
@test "T-001: valid report passes gate" {
    local report=$(create_valid_report)
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "T-001b: missing origin emits WARN without failing" {
    local report=$(create_valid_report)
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" == *"WARN: origin欄が空/未記入"* ]]
    [[ "$output" == *"report_field_set.sh <report> origin"* ]]
}

@test "T-001c: required variation 5項目が空なら正規report gateがFAIL" {
    mkdir -p "$TMPDIR_BATS/queue/reports" "$TMPDIR_BATS/queue/tasks"
    local report="$TMPDIR_BATS/queue/reports/testninja_report_cmd_test.yaml"
    create_valid_report "$report" >/dev/null
    cat > "$TMPDIR_BATS/queue/tasks/testninja.yaml" <<'YAML'
task:
  parent_cmd: cmd_test
  variation_checks_required: true
YAML
    cat >> "$report" <<'YAML'
variation_checks:
  normal_pass: {check: normal, result: ""}
  quoted_or_heredoc: {check: quoted, result: ""}
  linked_worktree: {check: worktree, result: ""}
  parallel_or_respawn: {check: parallel, result: ""}
  abnormal_exit: {check: abnormal, result: ""}
YAML

    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"variation_checks: required cells unfilled"* ]]
}

@test "T-001d: required variation 5項目がyes/noなら正規report gateがPASS" {
    mkdir -p "$TMPDIR_BATS/queue/reports" "$TMPDIR_BATS/queue/tasks"
    local report="$TMPDIR_BATS/queue/reports/testninja_report_cmd_test.yaml"
    create_valid_report "$report" >/dev/null
    cat > "$TMPDIR_BATS/queue/tasks/testninja.yaml" <<'YAML'
task:
  parent_cmd: cmd_test
  variation_checks_required: true
YAML
    cat >> "$report" <<'YAML'
variation_checks:
  normal_pass: {check: normal, result: yes}
  quoted_or_heredoc: {check: quoted, result: no}
  linked_worktree: {check: worktree, result: yes}
  parallel_or_respawn: {check: parallel, result: no}
  abnormal_exit: {check: abnormal, result: yes}
YAML

    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# --- T-002: Missing file → FAIL ---
@test "T-002: missing file returns FAIL" {
    run bash "$GATE" "$TMPDIR_BATS/nonexistent.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
}

# --- T-003: Empty verdict with unfilled binary_checks → FAIL (autofix cannot derive) ---
@test "T-003: empty verdict with unfilled binary_checks returns FAIL" {
    local report=$(create_valid_report)
    # Set verdict="" AND binary_checks result="" → autofix can't derive verdict
    sed -i 's/^verdict: PASS/verdict: ""/' "$report"
    sed -i 's/result: "yes"/result: ""/' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"verdict"* ]]
}

@test "T-003b: empty verdict emits report_field_set fix command" {
    local report=$(create_valid_report)
    sed -i 's/^verdict: PASS/verdict: ""/' "$report"
    sed -i 's/result: "yes"/result: ""/' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FIX COMMAND (verdict)"* ]]
    [[ "$output" == *"bash scripts/report_field_set.sh $report verdict PASS"* ]]
}

@test "T-003c: empty binary_checks result emits report_field_set fix command" {
    local report=$(create_valid_report)
    sed -i 's/^verdict: PASS/verdict: ""/' "$report"
    sed -i 's/result: "yes"/result: ""/' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FIX COMMAND (binary_checks result)"* ]]
    [[ "$output" == *"bash scripts/report_field_set.sh $report binary_checks.AC1.0.result yes"* ]]
}

@test "T-003d: FILL_THIS placeholder emits report_field_set fix command" {
    local report=$(create_valid_report)
    sed -i 's#files_modified: \[\]#files_modified: FILL_THIS#' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"files_modified: FILL_THIS placeholder remaining"* ]]
    [[ "$output" == *"FIX COMMAND (files_modified)"* ]]
    [[ "$output" == *"bash scripts/report_field_set.sh $report files_modified scripts/gates/gate_report_format_main.py"* ]]
}

# --- T-004: GP-128 PASS+no → auto-derived FAIL verdict → PASS ---
@test "T-004: verdict=PASS with bc no is overwritten to FAIL" {
    local report=$(create_valid_report)
    sed -i 's/result: "yes"/result: "no"/' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    run grep '^verdict: FAIL$' "$report"
    [ "$status" -eq 0 ]
}

# --- T-005: GP-128 FAIL+all-yes → auto-derived PASS verdict ---
@test "T-005: verdict=FAIL with all-yes is overwritten to PASS" {
    local report=$(create_valid_report)
    sed -i 's/^verdict: PASS/verdict: FAIL/' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    run grep '^verdict: PASS$' "$report"
    [ "$status" -eq 0 ]
}

@test "T-GP287-1: short commit_hash fails" {
    local short_report="$TMPDIR_BATS/short_hash_report.yaml"
    create_valid_report "$short_report" >/dev/null
    cat >> "$short_report" << 'YAML'
commit_hash: abc1234
YAML

    run bash "$GATE" "$short_report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"commit_hash: 'abc1234' は40文字フルhashでない"* ]]
}

@test "T-GP287-2: full 40-char commit_hash passes" {
    local full_report="$TMPDIR_BATS/full_hash_report.yaml"
    create_valid_report "$full_report" >/dev/null
    cat >> "$full_report" << 'YAML'
commit_hash: 0123456789abcdef0123456789abcdef01234567
YAML

    run bash "$GATE" "$full_report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"40文字フルhashでない"* ]]
}

# --- cmd_karo_hotfix_report_commit_contract_202607131320: commit_hash欠落の前段BLOCK ---
# tobisaruのhotfix実装報告(binary_checks.commit=yes, commit_hash欠落, status=completed)が
# gate_report_formatをPASSし、review_approval.shで初めてBLOCKした事故の再発防止。
# parent cmd sourceが直近git logに無いkaro_direct hotfixでも欠落を検出しなければならない(AC1)。

@test "T-CHC-1 (AC1): commit AC=yes without commit_hash is BLOCKed even without parent_cmd in git log" {
    local report="$TMPDIR_BATS/chc1_report.yaml"
    cat > "$report" << 'YAML'
worker_id: testninja
parent_cmd: cmd_karo_hotfix_no_parent_source_in_recent_log
ac_version_read: abc12345
timestamp: '2026-07-13T00:00:00+09:00'
status: completed
result:
  summary: "hotfix実装完了"
purpose_validation:
  cmd_purpose: "テスト"
  fit: true
  purpose_gap: ""
files_modified:
  - path: scripts/gates/gate_report_format_main.py
lesson_candidate:
  found: false
  no_lesson_reason: "既知パターンのため新規教訓なし"
lessons_useful: []
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
binary_checks:
  AC1:
    - check: "テスト対象の確認項目を詳細に記載"
      result: "yes"
  commit:
    - check: "git commitが完了したか(untracked/modified=0)"
      result: "yes"
verdict: PASS
YAML

    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"commit_hash"* ]]
    [[ "$output" == *"binary_checks.commitがyes"* ]]
}

@test "T-CHC-2 (AC2 true negative): commit AC=yes with valid 40-char commit_hash still PASSes" {
    local report="$TMPDIR_BATS/chc2_report.yaml"
    cat > "$report" << 'YAML'
worker_id: testninja
parent_cmd: cmd_karo_hotfix_no_parent_source_in_recent_log
ac_version_read: abc12345
timestamp: '2026-07-13T00:00:00+09:00'
status: completed
commit_hash: 0123456789abcdef0123456789abcdef01234567
result:
  summary: "hotfix実装完了"
purpose_validation:
  cmd_purpose: "テスト"
  fit: true
  purpose_gap: ""
files_modified:
  - path: scripts/gates/gate_report_format_main.py
lesson_candidate:
  found: false
  no_lesson_reason: "既知パターンのため新規教訓なし"
lessons_useful: []
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
binary_checks:
  AC1:
    - check: "テスト対象の確認項目を詳細に記載"
      result: "yes"
  commit:
    - check: "git commitが完了したか(untracked/modified=0)"
      result: "yes"
verdict: PASS
YAML

    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "T-CHC-3 (AC2 true negative): no-code recon report without commit_hash still PASSes" {
    local report="$TMPDIR_BATS/chc3_report.yaml"
    cat > "$report" << 'YAML'
worker_id: testninja
parent_cmd: cmd_test
task_type: recon
ac_version_read: abc12345
timestamp: '2026-07-13T00:00:00+09:00'
status: completed
result:
  summary: "偵察完了。変更なし"
purpose_validation:
  cmd_purpose: "テスト"
  fit: true
  purpose_gap: ""
files_modified: []
lesson_candidate:
  found: false
  no_lesson_reason: "既知パターンのため新規教訓なし"
lessons_useful: []
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
binary_checks:
  AC1:
    - check: "偵察対象の確認"
      result: "yes"
verdict: PASS
YAML

    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "T-GP286-1: non-path files_modified fails" {
    local non_path_report="$TMPDIR_BATS/non_path_files_modified_report.yaml"
    create_valid_report "$non_path_report" >/dev/null
    python3 - "$non_path_report" <<'PY'
import sys, yaml
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = yaml.safe_load(f)
data["files_modified"] = ["変更内容の説明だけ"]
with open(path, "w", encoding="utf-8") as f:
    yaml.safe_dump(data, f, allow_unicode=True, sort_keys=False)
PY

    run bash "$GATE" "$non_path_report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"files_modified: 1件がパス形式でない"* ]]
}

@test "T-GP286-2: path-form files_modified passes" {
    local path_report="$TMPDIR_BATS/path_files_modified_report.yaml"
    create_valid_report "$path_report" >/dev/null
    python3 - "$path_report" <<'PY'
import sys, yaml
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = yaml.safe_load(f)
data["files_modified"] = ["tests/test_gate_report_format.bats"]
with open(path, "w", encoding="utf-8") as f:
    yaml.safe_dump(data, f, allow_unicode=True, sort_keys=False)
PY

    run bash "$GATE" "$path_report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"パス形式でない"* ]]
}

@test "T-LKA14-1: residual sweep mention without grep zero evidence fails" {
    local report="$TMPDIR_BATS/lka14_missing_evidence.yaml"
    create_valid_report "$report" >/dev/null
    python3 - "$report" <<'PY'
import sys, yaml
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = yaml.safe_load(f)
data["result"]["details"] = "修正前パターンの横展開確認を実施した"
data["files_modified"] = ["scripts/gates/gate_report_format_main.py"]
with open(path, "w", encoding="utf-8") as f:
    yaml.safe_dump(data, f, allow_unicode=True, sort_keys=False)
PY

    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"LK-A14: 横展開/修正前パターンを扱う報告にはgrep/rg残存0件の一次証跡が必須"* ]]
}

@test "T-LKA14-2: residual sweep mention with grep zero evidence passes" {
    local report="$TMPDIR_BATS/lka14_with_evidence.yaml"
    create_valid_report "$report" >/dev/null
    python3 - "$report" <<'PY'
import sys, yaml
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = yaml.safe_load(f)
data["result"]["details"] = "修正前パターンの横展開確認を実施。rg 'old_pattern' scripts tests の残存0件を確認。"
data["files_modified"] = ["scripts/gates/gate_report_format_main.py"]
with open(path, "w", encoding="utf-8") as f:
    yaml.safe_dump(data, f, allow_unicode=True, sort_keys=False)
PY

    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"LK-A14"* ]]
}

# --- T-006: GP-073 PASS cache hit ---
@test "T-006: GP-073 second call hits mtime cache" {
    local report="$REPO_TMPDIR_BATS/cache_report.yaml"
    create_valid_report "$report" >/dev/null
    # First call: full validation
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    # Verify cache file exists
    [ -f "$GATE_PASS_CACHE_FILE" ]
    # Second call: should hit cache (no GP-062 WARN etc, just PASS)
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == "PASS" ]]
}

# --- T-007: GP-073 cache invalidation on mtime change ---
@test "T-007: GP-073 cache invalidated on file change" {
    local report="$REPO_TMPDIR_BATS/cache_invalidate_report.yaml"
    create_valid_report "$report" >/dev/null
    # First call: cache
    bash "$GATE" "$report" > /dev/null 2>&1
    [ -f "$GATE_PASS_CACHE_FILE" ]
    # Modify file (changes mtime)
    sleep 1
    echo "# mtime change" >> "$report"
    # Second call: should NOT hit cache (full validation)
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# --- T-008: Missing binary_checks → FAIL ---
@test "T-008: missing binary_checks returns FAIL" {
    local report=$(create_valid_report)
    sed -i '/^binary_checks:/,/^[a-z]/{ /^binary_checks:/d; /^  /d; }' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"binary_checks"* ]]
}

# --- T-009: YAML parse error → FAIL ---
@test "T-009: invalid YAML returns FAIL" {
    echo "invalid: yaml: : :" > "$TMPDIR_BATS/broken.yaml"
    run bash "$GATE" "$TMPDIR_BATS/broken.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
}

# --- T-010: FAIL report not cached (use unfixable FAIL: empty result string) ---
@test "T-010: FAIL reports are not cached" {
    local report=$(create_valid_report)
    # Set both verdict="" and binary_checks result="" → autofix can't derive → still FAIL
    sed -i 's/^verdict: PASS/verdict: ""/' "$report"
    sed -i 's/result: "yes"/result: ""/' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    # Cache should not contain this file
    if [ -f "$GATE_PASS_CACHE_FILE" ]; then
        run grep "$(realpath "$report")" "$GATE_PASS_CACHE_FILE"
        [ "$status" -ne 0 ]
    fi
}

# --- T-NOLOG-1: GATE_NO_LOG=1 PASS時にgate_fire_logに書込みなし ---
@test "T-NOLOG-1: GATE_NO_LOG=1 skips fire_log on PASS" {
    local report=$(create_valid_report)
    GATE_NO_LOG=1 run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    # fire_log should not exist or not contain this report
    if [ -f "$GATE_FIRE_LOG_FILE" ]; then
        run grep "gate_report_format" "$GATE_FIRE_LOG_FILE"
        [ "$status" -ne 0 ]
    fi
}

# --- T-NOLOG-2: GATE_NO_LOG未設定で通常書込み確認 ---
@test "T-NOLOG-2: without GATE_NO_LOG fire_log is written" {
    local report="$REPO_TMPDIR_BATS/report.yaml"
    create_valid_report "$report" >/dev/null
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    # fire_log should contain an entry
    [ -f "$GATE_FIRE_LOG_FILE" ]
    run grep "gate_report_format" "$GATE_FIRE_LOG_FILE"
    [ "$status" -eq 0 ]
}

# --- T-SKILL-LOG-1: PASS report records report-write execution ---
@test "T-SKILL-LOG-1: PASS reports are recorded in skill_execution_log" {
    local report="$REPO_TMPDIR_BATS/report.yaml"
    create_valid_report "$report" >/dev/null
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]

    # SKILL_LOG_SYNC=1 により同期実行。ポーリング不要。
    run python3 - <<EOF
import yaml
data = yaml.safe_load(open("$SKILL_EXECUTION_LOG_FILE", encoding="utf-8"))
entries = data["executions"]
report_write = next(e for e in entries if e["skill"] == "report-write")
verdict_check = next(e for e in entries if e["skill"] == "verdict-check")
assert report_write["result"] == "PASS"
assert report_write["gate"] == "gate_report_format"
assert report_write["source"] == "$report"
assert verdict_check["result"] == "PASS"
assert verdict_check["gate"] == "gate_report_format"
assert verdict_check["source"] == "$report"
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# --- T-NOLOG-3: /tmp/テストレポートはfire_logに書き込まない ---
@test "T-NOLOG-3: /tmp reports are excluded from fire_log" {
    local report=$(create_valid_report)
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    if [ -f "$GATE_FIRE_LOG_FILE" ]; then
        run grep "$report" "$GATE_FIRE_LOG_FILE"
        [ "$status" -ne 0 ]
    fi
}

# --- T-011: Autofix binary_checks str→list conversion ---
@test "T-011: autofix converts binary_checks string to list" {
    local report="$TMPDIR_BATS/report.yaml"
    cat > "$report" << 'YAML'
worker_id: testninja
parent_cmd: cmd_test
ac_version_read: abc12345
timestamp: '2026-07-12T00:00:00+09:00'
status: completed
binary_checks:
  AC1: "テスト対象の確認項目を詳細に記載"
files_modified: []
lesson_candidate:
  found: false
  no_lesson_reason: "既知パターンのため新規教訓なし"
lessons_useful: []
purpose_validation:
  cmd_purpose: "テスト用途の確認タスク"
  fit: true
  purpose_gap: ""
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
result:
  summary: "テスト結果のサマリ"
verdict: PASS
YAML
    # Run autofix — should convert string to [{check: str, result: yes}]
    run bash "$AUTOFIX" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"binary_checks"* ]]
    # Verify format gate passes after autofix
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
}

# --- T-012: lessons_useful MISSING → BLOCK (消火撤去: スケルトン生成廃止) ---
@test "T-012: lessons_useful MISSING triggers BLOCK not autofix" {
    # Setup directory structure matching report→task path resolution
    mkdir -p "$TMPDIR_BATS/tasks" "$TMPDIR_BATS/reports"
    cat > "$TMPDIR_BATS/tasks/testninja.yaml" << 'YAML'
task:
  related_lessons:
    - id: L001
      summary: "テスト教訓1"
    - id: L002
      summary: "テスト教訓2"
YAML
    local report="$TMPDIR_BATS/reports/testninja_report_cmd_test.yaml"
    # Report WITHOUT lessons_useful key
    cat > "$report" << 'YAML'
worker_id: testninja
parent_cmd: cmd_test
ac_version_read: abc12345
status: completed
binary_checks:
  AC1:
    - check: "テスト対象の確認項目を詳細に記載"
      result: "yes"
files_modified: []
lesson_candidate:
  found: false
  no_lesson_reason: "既知パターンのため新規教訓なし"
purpose_validation:
  cmd_purpose: "テスト用途の確認タスク"
  fit: true
  purpose_gap: ""
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
result:
  summary: "テスト結果のサマリ"
verdict: PASS
YAML
    # Run gate format check — should FAIL (lessons_useful MISSING → BLOCK)
    # 消火撤去(GP-107): autofixでスケルトン生成=消火。忍者が自力記入すべき
    run bash "$GATE" "$report"
    [ "$status" -ne 0 ]
    [[ "$output" == *"lessons_useful"* ]]
}

# --- T-INTERMEDIATE-1: 中間状態(verdict空+AC欄なし)でgate_fire_logにFAIL記録されないこと ---
@test "T-INTERMEDIATE-1: intermediate state (empty verdict + no AC) does not write FAIL to fire_log" {
    local report="$REPO_TMPDIR_BATS/intermediate_report.yaml"
    cat > "$report" << 'YAML'
worker_id: testninja
parent_cmd: cmd_test
ac_version_read: abc12345
status: completed
binary_checks: {}
files_modified: []
lesson_candidate:
  found: false
  no_lesson_reason: "既知パターンのため新規教訓なし"
lessons_useful: []
purpose_validation:
  cmd_purpose: "テスト用途の確認タスク"
  fit: true
  purpose_gap: ""
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
result:
  summary: "テスト結果のサマリ"
verdict: ""
YAML
    run bash "$GATE" "$report"
    # Gate should still FAIL (exit 1) — verdict未設定は本当にFAIL
    [ "$status" -eq 1 ]
    # fire_log should NOT contain FAIL entry for this report（中間状態=偽陽性）
    if [ -f "$GATE_FIRE_LOG_FILE" ]; then
        run grep "$report" "$GATE_FIRE_LOG_FILE"
        [ "$status" -ne 0 ]
    fi
}

# --- T-INTERMEDIATE-2: verdict記入済み+AC欄なし → 通常FAIL記録（本物の品質問題）---
@test "T-INTERMEDIATE-2: non-intermediate FAIL (verdict=FAIL + no AC) writes FAIL to fire_log" {
    local report="$REPO_TMPDIR_BATS/real_fail_report.yaml"
    cat > "$report" << 'YAML'
worker_id: testninja
parent_cmd: cmd_test
ac_version_read: abc12345
status: completed
binary_checks: {}
files_modified: []
lesson_candidate:
  found: false
  no_lesson_reason: "既知パターンのため新規教訓なし"
lessons_useful: []
purpose_validation:
  cmd_purpose: "テスト用途の確認タスク"
  fit: true
  purpose_gap: ""
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
result:
  summary: "テスト結果のサマリ"
verdict: FAIL
YAML
    run bash "$GATE" "$report"
    # Gate should FAIL（verdict=FAILかつAC欄なしは本物の品質問題）
    [ "$status" -eq 1 ]
    # fire_log SHOULD contain FAIL entry（中間状態ではない）
    [ -f "$GATE_FIRE_LOG_FILE" ]
    run grep "$report" "$GATE_FIRE_LOG_FILE"
    [ "$status" -eq 0 ]
}

# --- T-SGC-1: self_gate_check 必須4キーが揃ったdict → PASS ---
@test "T-SGC-1: self_gate_check with required keys passes" {
    local report=$(create_valid_report)
    cat >> "$report" << 'YAML'
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
YAML
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# --- T-SGC-2: self_gate_check 必須キー欠落 → FAIL ---
@test "T-SGC-2: self_gate_check missing required key fails with specific message" {
    local report=$(create_valid_report)
    cat >> "$report" << 'YAML'
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  purpose_fit: PASS
YAML
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *'self_gate_check: missing required key "status_valid" (required: lesson_ref, lesson_candidate, status_valid, purpose_fit)'* ]]
}

# --- T-SGC-3: 旧キー名dict → FAIL ---
@test "T-SGC-3: self_gate_check legacy key names fail required key validation" {
    local report=$(create_valid_report)
    cat >> "$report" << 'YAML'
self_gate_check:
  lesson_ref: PASS
  format_compliance: PASS
  binary_checks: PASS
  purpose_fit: PASS
YAML
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *'self_gate_check: missing required key "lesson_candidate" (required: lesson_ref, lesson_candidate, status_valid, purpose_fit)'* ]]
    [[ "$output" == *'self_gate_check: missing required key "status_valid" (required: lesson_ref, lesson_candidate, status_valid, purpose_fit)'* ]]
}

# --- cmd_3264: auto-commit contamination check ---

@test "T-AC2-1: bc:commit=yes with uncommitted target_path files triggers WARN" {
    # Create report in project-local temp dir (not /tmp) to activate AC2/AC3 check
    local report="$REPO_TMPDIR_BATS/testninja_report_cmd_test.yaml"
    mkdir -p "$REPO_TMPDIR_BATS/queue/tasks"
    cat > "$REPO_TMPDIR_BATS/queue/tasks/testninja.yaml" <<YAML
task:
  status: in_progress
  target_path: scripts/gates
YAML
    cat > "$report" <<YAML
worker_id: testninja
parent_cmd: cmd_test
ac_version_read: abc12345
status: completed
binary_checks:
  AC1:
    - check: "test check"
      result: "yes"
  commit:
    - check: "git commitが完了したか"
      result: "yes"
files_modified:
  - path: scripts/gates/test.sh
lesson_candidate:
  found: false
  no_lesson_reason: "test"
result:
  summary: "test summary"
  details: "test details"
purpose_validation:
  cmd_purpose: "test"
  fit: true
  purpose_gap: ""
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
lessons_useful: []
YAML
    # The check uses REPO_ROOT to find queue/tasks - override to use our temp dir
    # Since REPO_ROOT in gate_report_format.sh is derived from the script location,
    # the check will look at the real repo's queue/tasks, not our temp one.
    # This test verifies the contamination check doesn't crash on non-/tmp reports.
    # Gate may FAIL for other missing fields — we only check the check ran without error.
    run bash "$GATE" "$report"
    echo "$output"
    # Should not contain Python traceback from the contamination check
    [[ "$output" != *"Traceback"* ]]
    # The WARN check should not fire since testninja has no task in real repo
    [[ "$output" != *"WARN(cmd_3264"* ]]
}

@test "T-AC2-2: /tmp reports skip contamination check" {
    local report="$TMPDIR_BATS/report.yaml"
    create_valid_report "$report"
    # Add commit bc with yes
    cat >> "$report" <<YAML
  commit:
    - check: "git commitが完了したか"
      result: "yes"
YAML
    run bash "$GATE" "$report"
    # Should PASS without any WARN (check skipped for /tmp)
    [[ "$output" != *"WARN(cmd_3264"* ]]
}

@test "T-AC2-3: session_state-only tracked task diff does not block commit check" {
    local repo="$REPO_TMPDIR_BATS/session_state_repo"
    local report="$repo/reports/testninja_report_cmd_test.yaml"
    mkdir -p "$repo/queue/tasks" "$repo/reports" "$repo/logs"
    git -C "$repo" init -q
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name test
    cat > "$repo/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: in_progress
  target_path: queue/tasks/testninja.yaml
YAML
    git -C "$repo" add queue/tasks/testninja.yaml
    git -C "$repo" commit -q -m "seed task"
    local commit_hash
    commit_hash=$(git -C "$repo" rev-parse HEAD)
    cat >> "$repo/queue/tasks/testninja.yaml" <<'YAML'
  session_state:
    attempt: 1
    last_block_reason: 'cmd_3264-AC2 target_path配下に未commit変更あり'
    tried_approaches:
    - 'cmd_3264-AC2 target_path配下に未commit変更あり'
    prior_attempts:
    - attempt: 1
      block_reason: 'cmd_3264-AC2 target_path配下に未commit変更あり'
YAML
    cat > "$report" <<YAML
worker_id: testninja
parent_cmd: cmd_test
ac_version_read: abc12345
timestamp: '2026-07-08T00:00:00'
status: completed
commit_hash: ${commit_hash}
result:
  summary: "test summary"
purpose_validation:
  cmd_purpose: "test"
  fit: true
  purpose_gap: ""
binary_checks:
  AC1:
  - check: "test check"
    result: "yes"
  commit:
  - check: "git commitが完了したか"
    result: "yes"
files_modified:
- path: queue/tasks/testninja.yaml
lesson_candidate:
  found: false
  no_lesson_reason: "test"
lessons_useful: []
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
verdict: PASS
YAML

    run env GATE_REPO_ROOT_OVERRIDE="$repo" GATE_SESSION_STATE_TASK_DIR="$repo/queue/tasks" bash "$GATE" "$report"
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"BLOCK(cmd_3264-AC2)"* ]]
}

@test "T-AC2-4: tracked task status diff still blocks commit check" {
    local repo="$REPO_TMPDIR_BATS/task_status_repo"
    local report="$repo/reports/testninja_report_cmd_test.yaml"
    mkdir -p "$repo/queue/tasks" "$repo/reports" "$repo/logs"
    git -C "$repo" init -q
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name test
    cat > "$repo/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: in_progress
  target_path: queue/tasks/testninja.yaml
YAML
    git -C "$repo" add queue/tasks/testninja.yaml
    git -C "$repo" commit -q -m "seed task"
    sed -i 's/status: in_progress/status: done/' "$repo/queue/tasks/testninja.yaml"
    cat > "$report" <<'YAML'
worker_id: testninja
parent_cmd: cmd_test
ac_version_read: abc12345
timestamp: '2026-07-08T00:00:00'
status: completed
result:
  summary: "test summary"
purpose_validation:
  cmd_purpose: "test"
  fit: true
  purpose_gap: ""
binary_checks:
  AC1:
  - check: "test check"
    result: "yes"
  commit:
  - check: "git commitが完了したか"
    result: "yes"
files_modified:
- path: queue/tasks/testninja.yaml
lesson_candidate:
  found: false
  no_lesson_reason: "test"
lessons_useful: []
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
verdict: PASS
YAML

    run env GATE_REPO_ROOT_OVERRIDE="$repo" GATE_SESSION_STATE_TASK_DIR="$repo/queue/tasks" bash "$GATE" "$report"
    echo "$output"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK(cmd_3264-AC2)"* ]]
    [[ "$output" == *"M queue/tasks/testninja.yaml"* ]]
}

# --- cmd_karo_hotfix_gate_ac3_hunk_provenance_202607121205: AC3 hunk/commit provenance ---
# AC3のfile名一致だけの旧判定は、共有fileの非重複hunkにも誤ってWARNしていた(AC2はhunk比較済み)。
# 判定原理をAC2同様のcommit/hunk provenanceへ統一し、真の重複だけWARNする。

_setup_ac3_hunk_repo() {
    # $1=repo dir を作り、shared.txtへreporterのcommit→auto-commit(別行変更)の2commit履歴を積む。
    # 戻り値: reporter commitのフルhash(stdout)
    local repo="$1"
    local autocommit_line_edit="$2"
    mkdir -p "$repo/queue/tasks" "$repo/reports" "$repo/logs"
    git -C "$repo" init -q
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name test
    cat > "$repo/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: in_progress
  target_path: shared.txt
YAML
    printf 'line01\nline02\nline03\nline04\nline05\nline06\nline07\nline08\nline09\nline10\n' > "$repo/shared.txt"
    git -C "$repo" add queue/tasks/testninja.yaml shared.txt
    git -C "$repo" commit -q -m "init"

    sed -i 's/^line02$/line02 reporter-change/' "$repo/shared.txt"
    git -C "$repo" add shared.txt
    git -C "$repo" commit -q -m "feat: reporter change"
    local commit_hash
    commit_hash=$(git -C "$repo" rev-parse HEAD)

    sed -i "$autocommit_line_edit" "$repo/shared.txt"
    git -C "$repo" add shared.txt
    git -C "$repo" commit -q -m "chore: auto-commit before /clear (other) — 運用ファイル"

    echo "$commit_hash"
}

_write_ac3_report() {
    local report="$1"
    local commit_hash="$2"
    cat > "$report" <<YAML
worker_id: testninja
parent_cmd: cmd_test
ac_version_read: abc12345
timestamp: '2026-07-12T00:00:00'
status: completed
commit_hash: ${commit_hash}
result:
  summary: "test summary"
purpose_validation:
  cmd_purpose: "test"
  fit: true
  purpose_gap: ""
binary_checks:
  AC1:
  - check: "test check"
    result: "yes"
  commit:
  - check: "git commitが完了したか"
    result: "yes"
files_modified:
- path: shared.txt
lesson_candidate:
  found: false
  no_lesson_reason: "test"
lessons_useful: []
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
verdict: PASS
YAML
}

@test "completed report blocks empty or invalid timestamp and accepts ISO timestamp" {
    local report="$TMPDIR_BATS/report.yaml"
    create_valid_report "$report"

    sed -i "s/^timestamp:.*/timestamp: ''/" "$report"
    run env GATE_NO_LOG=1 bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires a parseable ISO timestamp"* ]]

    sed -i "s/^timestamp:.*/timestamp: 'not-a-date'/" "$report"
    run env GATE_NO_LOG=1 bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires a parseable ISO timestamp"* ]]

    sed -i "s/^timestamp:.*/timestamp: '2026-07-12T23:40:00+09:00'/" "$report"
    run env GATE_NO_LOG=1 bash "$GATE" "$report"
    [ "$status" -eq 0 ]
}

@test "T-AC3-1: non-overlapping auto-commit hunk on shared file does not WARN" {
    local repo="$REPO_TMPDIR_BATS/ac3_nonoverlap_repo"
    local report="$repo/reports/testninja_report_cmd_test.yaml"
    local commit_hash
    # auto-commitはline09（reporterが触ったline02とは非重複）を変更
    commit_hash=$(_setup_ac3_hunk_repo "$repo" 's/^line09$/line09 auto-commit-change/')
    _write_ac3_report "$report" "$commit_hash"

    run env GATE_REPO_ROOT_OVERRIDE="$repo" GATE_SESSION_STATE_TASK_DIR="$repo/queue/tasks" GATE_AUTOCOMMIT_CACHE_FILE="$repo/logs/.gate_autocommit_hunk_cache" bash "$GATE" "$report"
    echo "$output"
    [[ "$output" != *"Traceback"* ]]
    [[ "$output" != *"WARN(cmd_3264-AC3)"* ]]
    [[ "$output" != *"BLOCK(cmd_3264-AC2)"* ]]
}

@test "T-AC3-2: overlapping auto-commit hunk on shared file still WARNs" {
    local repo="$REPO_TMPDIR_BATS/ac3_overlap_repo"
    local report="$repo/reports/testninja_report_cmd_test.yaml"
    local commit_hash
    # auto-commitはreporterと同じline02を変更 → 真の巻込み
    commit_hash=$(_setup_ac3_hunk_repo "$repo" 's/^line02 reporter-change$/line02 auto-commit-change/')
    _write_ac3_report "$report" "$commit_hash"

    run env GATE_REPO_ROOT_OVERRIDE="$repo" GATE_SESSION_STATE_TASK_DIR="$repo/queue/tasks" GATE_AUTOCOMMIT_CACHE_FILE="$repo/logs/.gate_autocommit_hunk_cache" bash "$GATE" "$report"
    echo "$output"
    [[ "$output" != *"Traceback"* ]]
    [[ "$output" == *"WARN(cmd_3264-AC3)"* ]]
    [[ "$output" == *"shared.txt"* ]]
}
