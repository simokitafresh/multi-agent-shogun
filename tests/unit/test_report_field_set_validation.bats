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

@test "memory_references: 正しいlist形式入力はexit 0" {
    run bash -c "echo '- {id: MEM001, source: semantic_search, query: report template, used: false, useful: false, reason: 未使用}' | bash '$SCRIPT' '$TEST_REPORT' memory_references - 2>&1"
    [ "$status" -eq 0 ]
    python3 - "$TEST_REPORT" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
mr = data["memory_references"]
assert mr[0]["id"] == "MEM001", mr
assert mr[0]["used"] is False, mr
assert mr[0]["useful"] is False, mr
PY
}

@test "memory_references: dict形式入力はexit 1" {
    run bash -c "echo '{id: MEM001, source: semantic_search, query: q, used: false, useful: false, reason: r}' | bash '$SCRIPT' '$TEST_REPORT' memory_references - 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: memory_references must be YAML list format"* ]]
}

@test "memory_references: used/usefulの非boolはexit 1" {
    run bash -c "echo '- {id: MEM001, source: semantic_search, query: q, used: \"yes\", useful: false, reason: r}' | bash '$SCRIPT' '$TEST_REPORT' memory_references - 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"used/useful はbool必須"* ]]
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

@test "files_modified: 散文入力はautofix後にexit 1" {
    run bash -c "bash '$SCRIPT' '$TEST_REPORT' files_modified '変更なし。調査のみ' 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: files_modified はファイルパス形式のみ記入可"* ]]
    ! grep -Fq "変更なし。調査のみ" "$TEST_REPORT"
}

@test "files_modified: slashなし文字列リストはexit 1" {
    run bash -c "echo '[説明文, scripts/report_field_set.sh]' | bash '$SCRIPT' '$TEST_REPORT' files_modified - 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"不正値: 0: 説明文"* ]]
}

@test "files_modified: 正しいパス文字列はexit 0" {
    run bash -c "bash '$SCRIPT' '$TEST_REPORT' files_modified scripts/report_field_set.sh 2>&1"
    [ "$status" -eq 0 ]
    python3 - "$TEST_REPORT" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
assert data["files_modified"][0]["path"] == "scripts/report_field_set.sh", data
PY
}

@test "files_modified: reference_only dictはslashなしでもexit 0" {
    run bash -c "echo '[{path: report_notes, change: reference_only}]' | bash '$SCRIPT' '$TEST_REPORT' files_modified - 2>&1"
    [ "$status" -eq 0 ]
    python3 - "$TEST_REPORT" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
assert data["files_modified"][0]["path"] == "report_notes", data
assert data["files_modified"][0]["change"] == "reference_only", data
PY
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

@test "assumption_invalidation: top-level true without detail/cmds is blocked" {
    run bash -c "bash '$SCRIPT' '$TEST_REPORT' assumption_invalidation true 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: assumption_invalidation.found=true だが detail が空"* ]]
    ! grep -Fq "assumption_invalidation:" "$TEST_REPORT"
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

@test "assumption_invalidation: found true dot write is blocked until detail and affected_cmds exist" {
    run bash -c "bash '$SCRIPT' '$TEST_REPORT' assumption_invalidation.found true 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: assumption_invalidation.found=true だが detail が空"* ]]
    ! grep -Fq "assumption_invalidation:" "$TEST_REPORT"
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

@test "status completed: commit check未完了なら事前BLOCK" {
    cat >> "$TEST_REPORT" <<'YAML'
binary_checks:
  AC1:
    - check: behavior verified
      result: yes
  commit:
    - check: git commitが完了したか
      result: ""
YAML
    run bash -c "bash '$SCRIPT' '$TEST_REPORT' status completed 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: commit check未完了のまま status=completed は禁止"* ]]
    ! grep -Fq "status: completed" "$TEST_REPORT"
}

@test "status completed: commit check yesなら通す" {
    cat >> "$TEST_REPORT" <<'YAML'
binary_checks:
  AC1:
    - check: behavior verified
      result: yes
  commit:
    - check: git commitが完了したか
      result: yes
YAML
    run bash -c "bash '$SCRIPT' '$TEST_REPORT' status completed 2>&1"
    [ "$status" -eq 0 ]
    grep -Fq "status: completed" "$TEST_REPORT"
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

# === GP-258: commit_hash 40文字フルhex Level 4 BLOCK ===

@test "commit_hash: 40文字フルhex PASS" {
    run bash "$SCRIPT" "$TEST_REPORT" commit_hash "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
    [ "$status" -eq 0 ]
}

@test "commit_hash: 短縮hash(8文字) BLOCK" {
    run bash "$SCRIPT" "$TEST_REPORT" commit_hash "a1b2c3d4" 2>&1
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"40文字フルhex"* ]]
}

@test "commit_hash: 大文字混在 BLOCK" {
    run bash "$SCRIPT" "$TEST_REPORT" commit_hash "A1B2C3D4E5F6A7B8C9D0E1F2A3B4C5D6E7F8A9B0"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
}

@test "commit_hash: 付加文字列 BLOCK" {
    run bash "$SCRIPT" "$TEST_REPORT" commit_hash "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0_additional"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
}

@test "commit_hash: 複数hash(カンマ区切り) BLOCK" {
    run bash "$SCRIPT" "$TEST_REPORT" commit_hash "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0, b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
}
