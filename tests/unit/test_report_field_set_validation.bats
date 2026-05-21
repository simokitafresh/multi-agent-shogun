#!/usr/bin/env bats
# test_report_field_set_validation.bats
# Purpose: report_field_set.sh の lessons_useful 型バリデーションテスト
# Origin: cmd_cycle_001 — dict/string形式BLOCK, list形式PASS

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SCRIPT="$PROJECT_ROOT/scripts/report_field_set.sh"
    [ -f "$SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/rfs_val.XXXXXX")"
    export TEST_REPORT="$TEST_TMPDIR/report.yaml"
    cat > "$TEST_REPORT" <<'EOF'
worker_id: hayate
parent_cmd: cmd_test
ac_version_read: abc12345
EOF
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "lessons_useful: dict形式入力はautofix→exit 0" {
    run bash -c "echo '{0: {id: L001, useful: true}, 1: {id: L002, useful: false}}' | bash '$SCRIPT' '$TEST_REPORT' lessons_useful - 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[autofix]"* ]]
}

@test "lessons_useful: string形式入力はexit 1" {
    run bash -c "bash '$SCRIPT' '$TEST_REPORT' lessons_useful 'L001をreviewで使用した' 2>&1"
    [ "$status" -eq 1 ]
}

@test "lessons_useful: 正しいlist形式入力はexit 0" {
    run bash -c "echo '- {id: L074, useful: true, reason: テストで使用}' | bash '$SCRIPT' '$TEST_REPORT' lessons_useful - 2>&1"
    [ "$status" -eq 0 ]
}

@test "lessons_useful: dict形式はautofixメッセージ表示" {
    run bash -c "echo '{0: {id: L001}}' | bash '$SCRIPT' '$TEST_REPORT' lessons_useful - 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[autofix]"* ]]
}

@test "lessons_useful: 空list入力はexit 0" {
    run bash -c "echo '[]' | bash '$SCRIPT' '$TEST_REPORT' lessons_useful - 2>&1"
    [ "$status" -eq 0 ]
}

@test "self_gate_check: トップレベルscalar書込みはexit 1" {
    run bash -c "bash '$SCRIPT' '$TEST_REPORT' self_gate_check PASS 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: self_gate_check へのトップレベル書込みは禁止"* ]]
    [[ "$output" == *"dict形式で再入力せよ"* ]]
    [[ "$output" == *"self_gate_check.lesson_ref PASS"* ]]
}

@test "lesson_candidate: string形式入力はexit 1 and preserves report" {
    run bash -c "bash '$SCRIPT' '$TEST_REPORT' lesson_candidate 'FILL_THIS' 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: lesson_candidate はdict形式必須"* ]]
    ! grep -Fq "lesson_candidate:" "$TEST_REPORT"
}

@test "lesson_candidate: found=trueの必須フィールド欠落はexit 1" {
    run bash -c "echo '{found: true, title: 発見タイトル, project: infra}' | bash '$SCRIPT' '$TEST_REPORT' lesson_candidate - 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: lesson_candidate.found=true だが必須フィールド欠落: detail"* ]]
    ! grep -Fq "lesson_candidate:" "$TEST_REPORT"
}

@test "lesson_candidate: found=falseのno_lesson_reason欠落はexit 1" {
    run bash -c "echo '{found: false}' | bash '$SCRIPT' '$TEST_REPORT' lesson_candidate - 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: lesson_candidate.found=false だが no_lesson_reason"* ]]
    ! grep -Fq "lesson_candidate:" "$TEST_REPORT"
}

@test "lesson_candidate: found=trueで必須フィールドありならexit 0" {
    run bash -c "echo '{found: true, title: 発見タイトル, detail: 詳細, project: infra}' | bash '$SCRIPT' '$TEST_REPORT' lesson_candidate - 2>&1"
    [ "$status" -eq 0 ]
    python3 - "$TEST_REPORT" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
lc = data.get("lesson_candidate")
assert lc["found"] is True, lc
assert lc["title"] == "発見タイトル", lc
assert lc["detail"] == "詳細", lc
assert lc["project"] == "infra", lc
PY
}

@test "self_gate_check: stdin string形式入力はexit 1" {
    run bash -c "echo 'all good' | bash '$SCRIPT' '$TEST_REPORT' self_gate_check - 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: self_gate_check へのトップレベル書込みは禁止"* ]]
    [[ "$output" == *"dict形式で再入力せよ"* ]]
}

@test "self_gate_check: dot notation書込みはdict構造を保持してexit 0" {
    run bash -c "bash '$SCRIPT' '$TEST_REPORT' self_gate_check.lesson_ref PASS 2>&1"
    [ "$status" -eq 0 ]
    python3 - "$TEST_REPORT" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
assert isinstance(data.get("self_gate_check"), dict), data
assert data["self_gate_check"]["lesson_ref"] == "PASS", data
PY
}

@test "self_gate_check: 未知キーtypoはexit 1" {
    run bash -c "bash '$SCRIPT' '$TEST_REPORT' self_gate_check.lessonref PASS 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: self_gate_check の未知キーは禁止"* ]]
    ! grep -Fq "lessonref" "$TEST_REPORT"
}

@test "assumption_invalidation: 欠落ブロックへのdot notation書込みは必須フィールドを補完する" {
    run bash -c "bash '$SCRIPT' '$TEST_REPORT' assumption_invalidation.found false 2>&1"
    [ "$status" -eq 0 ]
    python3 - "$TEST_REPORT" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
ai = data.get("assumption_invalidation")
assert isinstance(ai, dict), data
assert ai["found"] is False, ai
assert ai["affected_cmds"] == [], ai
assert ai["detail"] == "", ai
PY
}

@test "assumption_invalidation: top-level false write is normalized to dict" {
    run bash -c "bash '$SCRIPT' '$TEST_REPORT' assumption_invalidation false 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"assumption_invalidation scalar→dict変換"* ]]
    python3 - "$TEST_REPORT" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
ai = data.get("assumption_invalidation")
assert isinstance(ai, dict), data
assert ai["found"] is False, ai
assert ai["affected_cmds"] == [], ai
assert ai["detail"] == "", ai
PY
}

@test "assumption_invalidation: historical found false form is normalized to dict" {
    run bash -c "bash '$SCRIPT' '$TEST_REPORT' assumption_invalidation found false 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"assumption_invalidation.found = False"* ]]
    python3 - "$TEST_REPORT" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
ai = data.get("assumption_invalidation")
assert isinstance(ai, dict), data
assert ai["found"] is False, ai
assert ai["affected_cmds"] == [], ai
assert ai["detail"] == "", ai
PY
}

@test "assumption_invalidation: 既存affected_cmdsはdot notation書込み後も保持される" {
    cat >> "$TEST_REPORT" <<'YAML'
assumption_invalidation:
  found: true
  affected_cmds:
    - cmd_100
  detail: before
YAML
    run bash -c "bash '$SCRIPT' '$TEST_REPORT' assumption_invalidation.detail after 2>&1"
    [ "$status" -eq 0 ]
    python3 - "$TEST_REPORT" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
ai = data.get("assumption_invalidation")
assert ai["found"] is True, ai
assert ai["affected_cmds"] == ["cmd_100"], ai
assert ai["detail"] == "after", ai
PY
}

@test "origin: shorthand writes lesson_candidate.origin" {
    cat >> "$TEST_REPORT" <<'YAML'
lesson_candidate:
  found: true
  title: "既存タイトル"
  detail: "既存詳細"
  project: infra
YAML
    run bash -c "bash '$SCRIPT' '$TEST_REPORT' origin '[[cmd_test]] -> [[cause]] -> [[result]]' 2>&1"
    [ "$status" -eq 0 ]
    python3 - "$TEST_REPORT" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
lc = data.get("lesson_candidate")
assert isinstance(lc, dict), data
assert lc["origin"] == "[[cmd_test]] -> [[cause]] -> [[result]]", lc
assert lc["title"] == "既存タイトル", lc
PY
}

@test "origin: omitted value inherits origin from parent_cmd archive" {
    local archive_dir="$PROJECT_ROOT/queue/archive/cmds"
    local archive_file="$archive_dir/cmd_rfs_origin_auto_completed_20990101.yaml"
    mkdir -p "$archive_dir"
    cat > "$archive_file" <<'YAML'
id: cmd_rfs_origin_auto
origin: "[[cmd_parent]] -> [[auto_source]] -> [[auto_result]]"
YAML
    TEST_REPORT="$TEST_TMPDIR/rfsorigin_report_cmd_rfs_origin_auto.yaml"
    cat > "$TEST_REPORT" <<'YAML'
worker_id: rfsorigin
parent_cmd: cmd_rfs_origin_auto
ac_version_read: abc12345
lesson_candidate:
  found: false
  no_lesson_reason: existing
YAML

    run bash -c "bash '$SCRIPT' '$TEST_REPORT' origin 2>&1"
    rm -f "$archive_file"
    [ "$status" -eq 0 ]
    python3 - "$TEST_REPORT" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
lc = data.get("lesson_candidate")
assert lc["origin"] == "[[cmd_parent]] -> [[auto_source]] -> [[auto_result]]", lc
PY
}

@test "origin: omitted value stays empty when cmd origin is unavailable" {
    TEST_REPORT="$TEST_TMPDIR/rfsorigin_report_cmd_missing_origin.yaml"
    cat > "$TEST_REPORT" <<'YAML'
worker_id: rfsorigin
parent_cmd: cmd_missing_origin
ac_version_read: abc12345
lesson_candidate:
  found: false
  no_lesson_reason: existing
YAML

    run bash -c "bash '$SCRIPT' '$TEST_REPORT' origin 2>&1"
    [ "$status" -eq 0 ]
    python3 - "$TEST_REPORT" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
lc = data.get("lesson_candidate")
assert lc["origin"] == "", lc
PY
}
