#!/usr/bin/env bats
# test_gate_report_format_pass_no_improvement.bats
# cmd_2072: PASS_NO_IMPROVEMENT判定のテスト

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_report_format.sh"
    export GATE_MAIN_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_report_format_main.py"
    [ -f "$GATE_SCRIPT" ] || return 1
    [ -f "$GATE_MAIN_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/pni_test.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" \
             "$TEST_TMPDIR/queue/reports" \
             "$TEST_TMPDIR/queue/tasks" \
             "$TEST_TMPDIR/logs"
    cp "$GATE_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_report_format.sh"
    cp "$GATE_MAIN_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_report_format_main.py"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_combined.py" "$TEST_TMPDIR/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_autofix_main.py" "$TEST_TMPDIR/scripts/gates/"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_report_format.sh"
    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_report_format.sh"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# 共通ベース報告YAMLを書く(_write_base_pni_report <path> <binary_checks_yaml>)
_write_base_pni_report() {
    local rpath="$1"
    local bc_yaml="$2"
    cat > "$rpath" <<EOF
worker_id: tobisaru
parent_cmd: cmd_2072
ac_version_read: test_hash_abc
timestamp: 2026-07-13T00:00:00+09:00
status: completed
result:
  summary: "テスト用報告"
  details: "詳細"
purpose_validation:
  cmd_purpose: "テスト"
  fit: true
  purpose_gap: ""
files_modified:
  - scripts/gates/gate_report_format_cmd_2072.sh
lesson_candidate:
  found: false
  no_lesson_reason: "テスト用の報告であるため新規教訓なし"
  title: ""
  detail: ""
lessons_useful:
  - id: L001
    useful: true
    reason: helpful
${bc_yaml}
verdict: PASS
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
EOF
}

# === Test 1: 全AC revert → PASS_NO_IMPROVEMENT ===
@test "全ACがrevertを含む場合はPASS_NO_IMPROVEMENTを出力する" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_2072.yaml"
    _write_base_pni_report "$rpath" "binary_checks:
  AC1:
    - check: After>=Beforeなら即revert
      result: yes
  AC2:
    - check: revert済み確認
      result: yes"

    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS_NO_IMPROVEMENT"* ]]
    [[ "$output" == *"WARN"* ]]
}

# === Test 2: 部分 revert (1/3 AC = 33%) → PASS ===
@test "revertが全ACの33%の場合はPASSを出力する" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_2072.yaml"
    _write_base_pni_report "$rpath" "binary_checks:
  AC1:
    - check: After>=Beforeなら即revert
      result: yes
  AC2:
    - check: 改善実装完了
      result: yes
  AC3:
    - check: テスト全PASS
      result: yes"

    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"PASS_NO_IMPROVEMENT"* ]]
}

# === Test 3: revert なし → PASS ===
@test "revertなしの場合はPASSを出力する" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_2072.yaml"
    _write_base_pni_report "$rpath" "binary_checks:
  AC1:
    - check: 改善実装完了
      result: yes
  AC2:
    - check: テスト全PASS
      result: yes"

    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"PASS_NO_IMPROVEMENT"* ]]
}

@test "memory_references absence remains gate-compatible" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_2072.yaml"
    _write_base_pni_report "$rpath" "binary_checks:
  AC1:
    - check: 改善実装完了
      result: yes"

    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"memory_references"* ]]
}

@test "memory_references present validates used reason only when used true" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_2072.yaml"
    _write_base_pni_report "$rpath" "binary_checks:
  AC1:
    - check: 改善実装完了
      result: yes"
    python3 - "$rpath" <<'PY'
import sys, yaml
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = yaml.safe_load(f)
data["memory_references"] = [
    {
        "id": "MEM001",
        "source": "semantic_search",
        "query": "report template",
        "summary": "関連知識",
        "used": True,
        "useful": True,
        "reason": "",
    }
]
with open(path, "w", encoding="utf-8") as f:
    yaml.safe_dump(data, f, allow_unicode=True, sort_keys=False)
PY

    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 1 ]
    [[ "$output" == *"memory_references[0].reason: empty"* ]]
}

@test "dict形式task acceptance_criteriaのbinary_checks件数不足を検出する" {
    local tpath="$TEST_TMPDIR/queue/tasks/tobisaru.yaml"
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_2072.yaml"
    cat > "$tpath" <<'EOF'
task:
  acceptance_criteria:
    AC1:
      binary_checks:
        - "改善点を3つ特定したか: yes/no"
        - "各改善点に対象ファイル・根拠を添えたか: yes/no"
    AC2:
      binary_checks:
        - "最高インパクト1件を実装したか: yes/no"
        - "関連テストまたは明示的な検証を実行したか: yes/no"
EOF
    _write_base_pni_report "$rpath" "binary_checks:
  AC1:
    - check: 改善点を3つ特定したか
      result: yes"

    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 1 ] || {
        echo "Expected exit 1 but got $status"
        echo "$output"
        return 1
    }
    [[ "$output" == *"binary_checks: item count 1/4 (<50% of task template)"* ]]
}

@test "cmd_3264 AC2 target_path fallback uncommitted BLOCKs when files_modified is empty" {
    local worker="cmd3264test"
    local workdir="$PROJECT_ROOT/.codex_tmp/gate_report_format_cmd3264_test_$$"
    local task_path="$workdir/queue/tasks/${worker}.yaml"
    local rpath="$workdir/queue/reports/${worker}_report_cmd_3264.yaml"
    local gate="$workdir/scripts/gates/gate_report_format.sh"
    rm -rf "$workdir"
    mkdir -p "$workdir/scripts/gates" "$workdir/queue/reports" "$workdir/queue/tasks" "$workdir/logs" "$workdir/target"
    cp "$GATE_SCRIPT" "$gate"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_main.py" "$workdir/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_combined.py" "$workdir/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_autofix_main.py" "$workdir/scripts/gates/"
    chmod +x "$gate"
    git -C "$workdir" init -q
    cat > "$task_path" <<EOF
task:
  target_path: target
EOF
    echo "dirty" > "$workdir/target/dirty.txt"
    cat > "$rpath" <<EOF
worker_id: ${worker}
parent_cmd: cmd_3264
ac_version_read: test_hash_abc
timestamp: 2026-07-13T00:00:00+09:00
status: completed
result:
  summary: "テスト用報告"
  details: "詳細"
purpose_validation:
  cmd_purpose: "テスト"
  fit: true
  purpose_gap: ""
files_modified: []
lesson_candidate:
  found: false
  no_lesson_reason: "テスト用の報告であるため新規教訓なし"
  title: ""
  detail: ""
lessons_useful:
  - id: L001
    useful: true
    reason: helpful
binary_checks:
  AC1:
    - check: テスト完了
      result: yes
  commit:
    - check: git commitが完了したか
      result: yes
verdict: PASS
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
EOF

    run env GATE_NO_LOG=1 SKILL_EXECUTION_PASS_LOG_DISABLE=1 GATE_PASS_CACHE_FILE="$workdir/pass_cache" bash "$gate" "$rpath"

    [ "$status" -eq 1 ] || {
        echo "Expected exit 1 but got $status"
        echo "$output"
        echo "git status target:"
        git -C "$workdir" status --porcelain -- target || true
        echo "task:"
        cat "$task_path" || true
        echo "report commit check:"
        python3 - "$rpath" <<'PY' || true
import yaml, sys
d = yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}
print(d.get('worker_id'))
print((d.get('binary_checks') or {}).get('commit'))
PY
        rm -rf "$workdir"
        return 1
    }
    [[ "$output" == *"BLOCK(cmd_3264-AC2)"* ]]
    rm -rf "$workdir"
}

@test "cmd_3264 AC2 read-only commit-prohibited report does not BLOCK on task YAML dirtiness" {
    local worker="cmd3264readonly"
    local workdir="$PROJECT_ROOT/.codex_tmp/gate_report_format_cmd3264_readonly_test_$$"
    local task_path="$workdir/queue/tasks/${worker}.yaml"
    local rpath="$workdir/queue/reports/${worker}_report_cmd_3264_readonly.yaml"
    local gate="$workdir/scripts/gates/gate_report_format.sh"
    rm -rf "$workdir"
    mkdir -p "$workdir/scripts/gates" "$workdir/queue/reports" "$workdir/queue/tasks" "$workdir/logs" "$workdir/queue/tasks"
    cp "$GATE_SCRIPT" "$gate"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_main.py" "$workdir/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_combined.py" "$workdir/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_autofix_main.py" "$workdir/scripts/gates/"
    chmod +x "$gate"
    git -C "$workdir" init -q
    mkdir -p "$workdir/queue/tasks"
    cat > "$task_path" <<EOF
task:
  target_path: queue/tasks/${worker}.yaml
EOF
    git -C "$workdir" add "$task_path"
    git -C "$workdir" -c user.email=test@example.com -c user.name=test commit -q -m init
    cat >> "$task_path" <<EOF
  status: done
  progress: "AC1完了"
EOF
    cat > "$rpath" <<EOF
worker_id: ${worker}
parent_cmd: cmd_3264_readonly
ac_version_read: test_hash_abc
timestamp: 2026-07-13T00:00:00+09:00
status: completed
result:
  summary: "read-only triage"
  details: "詳細"
purpose_validation:
  cmd_purpose: "read-only triage"
  fit: true
  purpose_gap: ""
files_modified:
  - path: queue/tasks/${worker}.yaml
    change: task status/progress updated by recovery
lesson_candidate:
  found: false
  no_lesson_reason: "テスト用の報告であるため新規教訓なし"
  title: ""
  detail: ""
lessons_useful:
  - id: L001
    useful: true
    reason: helpful
binary_checks:
  AC1:
    - check: テスト完了
      result: yes
  commit:
    - check: read-only任務のためcommit禁止を守り、stage/commitを実行していないか
      result: yes
verdict: PASS
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
EOF

    run env GATE_NO_LOG=1 SKILL_EXECUTION_PASS_LOG_DISABLE=1 GATE_PASS_CACHE_FILE="$workdir/pass_cache" bash "$gate" "$rpath"

    [ "$status" -eq 0 ] || {
        echo "Expected exit 0 but got $status"
        echo "$output"
        echo "git status task:"
        git -C "$workdir" status --porcelain -- "queue/tasks/${worker}.yaml" || true
        rm -rf "$workdir"
        return 1
    }
    [[ "$output" != *"BLOCK(cmd_3264-AC2)"* ]]
    rm -rf "$workdir"
}

@test "cmd_3264 AC2 repo-root target_path ignores unrelated dirty files when files_modified is clean" {
    local worker="cmd3264root"
    local workdir="$PROJECT_ROOT/.codex_tmp/gate_report_format_cmd3264_root_test_$$"
    local task_path="$workdir/queue/tasks/${worker}.yaml"
    local rpath="$workdir/queue/reports/${worker}_report_cmd_3264.yaml"
    local gate="$workdir/scripts/gates/gate_report_format.sh"
    rm -rf "$workdir"
    mkdir -p "$workdir/scripts/gates" "$workdir/queue/reports" "$workdir/queue/tasks" "$workdir/logs" "$workdir/context"
    cp "$GATE_SCRIPT" "$gate"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_main.py" "$workdir/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_combined.py" "$workdir/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_autofix_main.py" "$workdir/scripts/gates/"
    chmod +x "$gate"
    git -C "$workdir" init -q
    cat > "$workdir/context/owned.md" <<EOF
owned
EOF
    git -C "$workdir" add context/owned.md
    git -C "$workdir" -c user.email=test@example.com -c user.name=test commit -q -m init
    local commit_hash
    commit_hash=$(git -C "$workdir" rev-parse HEAD)
    cat > "$task_path" <<EOF
task:
  target_path: $workdir
EOF
    echo "parallel dirty" > "$workdir/context/unrelated.md"
    cat > "$rpath" <<EOF
worker_id: ${worker}
parent_cmd: cmd_3264
ac_version_read: test_hash_abc
timestamp: 2026-07-13T00:00:00+09:00
status: completed
commit_hash: ${commit_hash}
result:
  summary: "テスト用報告"
  details: "詳細"
purpose_validation:
  cmd_purpose: "テスト"
  fit: true
  purpose_gap: ""
files_modified:
  - path: context/owned.md
    change: modified
lesson_candidate:
  found: false
  no_lesson_reason: "テスト用の報告であるため新規教訓なし"
  title: ""
  detail: ""
lessons_useful:
  - id: L001
    useful: true
    reason: helpful
binary_checks:
  AC1:
    - check: テスト完了
      result: yes
  commit:
    - check: git commitが完了したか
      result: yes
verdict: PASS
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
EOF

    run env GATE_NO_LOG=1 SKILL_EXECUTION_PASS_LOG_DISABLE=1 GATE_PASS_CACHE_FILE="$workdir/pass_cache" bash "$gate" "$rpath"

    [ "$status" -eq 0 ] || {
        echo "Expected exit 0 but got $status"
        echo "$output"
        echo "git status:"
        git -C "$workdir" status --porcelain || true
        rm -rf "$workdir"
        return 1
    }
    [[ "$output" != *"BLOCK(cmd_3264-AC2)"* ]]
    rm -rf "$workdir"
}

@test "cmd_3264 AC2 shared file target_path ignores unrelated dirty file when files_modified is clean" {
    local worker="cmd3264shared"
    local workdir="$PROJECT_ROOT/.codex_tmp/gate_report_format_cmd3264_shared_test_$$"
    local task_path="$workdir/queue/tasks/${worker}.yaml"
    local rpath="$workdir/queue/reports/${worker}_report_cmd_3264.yaml"
    local gate="$workdir/scripts/gates/gate_report_format.sh"
    rm -rf "$workdir"
    mkdir -p "$workdir/scripts/gates" "$workdir/queue/reports" "$workdir/queue/tasks" "$workdir/logs" "$workdir/context"
    cp "$GATE_SCRIPT" "$gate"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_main.py" "$workdir/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_combined.py" "$workdir/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_autofix_main.py" "$workdir/scripts/gates/"
    chmod +x "$gate"
    git -C "$workdir" init -q
    cat > "$workdir/context/shared.md" <<EOF
shared
EOF
    cat > "$workdir/context/owned.md" <<EOF
owned
EOF
    git -C "$workdir" add context/shared.md context/owned.md
    git -C "$workdir" -c user.email=test@example.com -c user.name=test commit -q -m init
    local commit_hash
    commit_hash=$(git -C "$workdir" rev-parse HEAD)
    cat > "$task_path" <<EOF
task:
  target_path: context/shared.md
EOF
    echo "parallel dirty" >> "$workdir/context/shared.md"
    cat > "$rpath" <<EOF
worker_id: ${worker}
parent_cmd: cmd_3264
ac_version_read: test_hash_abc
timestamp: 2026-07-13T00:00:00+09:00
status: completed
commit_hash: ${commit_hash}
result:
  summary: "テスト用報告"
  details: "詳細"
purpose_validation:
  cmd_purpose: "テスト"
  fit: true
  purpose_gap: ""
files_modified:
  - path: context/owned.md
    change: modified
lesson_candidate:
  found: false
  no_lesson_reason: "テスト用の報告であるため新規教訓なし"
  title: ""
  detail: ""
lessons_useful:
  - id: L001
    useful: true
    reason: helpful
binary_checks:
  AC1:
    - check: テスト完了
      result: yes
  commit:
    - check: git commitが完了したか
      result: yes
verdict: PASS
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
EOF

    run env GATE_NO_LOG=1 SKILL_EXECUTION_PASS_LOG_DISABLE=1 GATE_PASS_CACHE_FILE="$workdir/pass_cache" bash "$gate" "$rpath"

    [ "$status" -eq 0 ] || {
        echo "Expected exit 0 but got $status"
        echo "$output"
        echo "git status:"
        git -C "$workdir" status --porcelain || true
        rm -rf "$workdir"
        return 1
    }
    [[ "$output" != *"BLOCK(cmd_3264-AC2)"* ]]
    rm -rf "$workdir"
}

@test "cmd_3264 AC2 files_modified uncommitted BLOCKs even when target_path is clean" {
    local worker="cmd3264files"
    local workdir="$PROJECT_ROOT/.codex_tmp/gate_report_format_cmd3264_files_test_$$"
    local task_path="$workdir/queue/tasks/${worker}.yaml"
    local rpath="$workdir/queue/reports/${worker}_report_cmd_3264.yaml"
    local gate="$workdir/scripts/gates/gate_report_format.sh"
    rm -rf "$workdir"
    mkdir -p "$workdir/scripts/gates" "$workdir/queue/reports" "$workdir/queue/tasks" "$workdir/logs" "$workdir/target" "$workdir/context"
    cp "$GATE_SCRIPT" "$gate"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_main.py" "$workdir/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_combined.py" "$workdir/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_autofix_main.py" "$workdir/scripts/gates/"
    chmod +x "$gate"
    git -C "$workdir" init -q
    echo "clean" > "$workdir/target/clean.txt"
    echo "original" > "$workdir/context/reported.md"
    git -C "$workdir" add target/clean.txt context/reported.md
    git -C "$workdir" -c user.email=test@example.com -c user.name=test commit -q -m init
    cat > "$task_path" <<EOF
task:
  target_path: target
EOF
    echo "dirty" >> "$workdir/context/reported.md"
    cat > "$rpath" <<EOF
worker_id: ${worker}
parent_cmd: cmd_3264
ac_version_read: test_hash_abc
timestamp: 2026-07-13T00:00:00+09:00
status: completed
result:
  summary: "テスト用報告"
  details: "詳細"
purpose_validation:
  cmd_purpose: "テスト"
  fit: true
  purpose_gap: ""
files_modified:
  - path: context/reported.md
    change: modified
lesson_candidate:
  found: false
  no_lesson_reason: "テスト用の報告であるため新規教訓なし"
  title: ""
  detail: ""
lessons_useful:
  - id: L001
    useful: true
    reason: helpful
binary_checks:
  AC1:
    - check: テスト完了
      result: yes
  commit:
    - check: git commitが完了したか
      result: yes
verdict: PASS
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
EOF

    run env GATE_NO_LOG=1 SKILL_EXECUTION_PASS_LOG_DISABLE=1 GATE_PASS_CACHE_FILE="$workdir/pass_cache" bash "$gate" "$rpath"

    [ "$status" -eq 1 ] || {
        echo "Expected exit 1 but got $status"
        echo "$output"
        echo "git status context/reported.md:"
        git -C "$workdir" status --porcelain -- context/reported.md || true
        rm -rf "$workdir"
        return 1
    }
    [[ "$output" == *"BLOCK(cmd_3264-AC2)"* ]]
    rm -rf "$workdir"
}

@test "cmd_3264 AC2 commit_hash allows non-overlapping concurrent dirty hunk in same reported file" {
    local worker="cmd3264nonoverlap"
    local workdir="$PROJECT_ROOT/.codex_tmp/gate_report_format_cmd3264_nonoverlap_test_$$"
    local task_path="$workdir/queue/tasks/${worker}.yaml"
    local rpath="$workdir/queue/reports/${worker}_report_cmd_3264.yaml"
    local gate="$workdir/scripts/gates/gate_report_format.sh"
    rm -rf "$workdir"
    mkdir -p "$workdir/scripts/gates" "$workdir/queue/reports" "$workdir/queue/tasks" "$workdir/logs" "$workdir/context"
    cp "$GATE_SCRIPT" "$gate"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_main.py" "$workdir/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_combined.py" "$workdir/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_autofix_main.py" "$workdir/scripts/gates/"
    chmod +x "$gate"
    git -C "$workdir" init -q
    cat > "$workdir/context/reported.md" <<'EOF'
line 1
line 2
line 3
line 4
line 5
EOF
    git -C "$workdir" add context/reported.md
    git -C "$workdir" -c user.email=test@example.com -c user.name=test commit -q -m init
    perl -0pi -e 's/line 2/line 2 cmd change/' "$workdir/context/reported.md"
    git -C "$workdir" add context/reported.md
    git -C "$workdir" -c user.email=test@example.com -c user.name=test commit -q -m "cmd_3264: modify reported file"
    local commit_hash
    commit_hash="$(git -C "$workdir" rev-parse HEAD)"
    perl -0pi -e 's/line 5/line 5 concurrent change/' "$workdir/context/reported.md"
    cat > "$task_path" <<EOF
task:
  target_path: context/reported.md
EOF
    cat > "$rpath" <<EOF
worker_id: ${worker}
parent_cmd: cmd_3264
ac_version_read: test_hash_abc
timestamp: 2026-07-13T00:00:00+09:00
status: completed
commit_hash: ${commit_hash}
result:
  summary: "テスト用報告"
  details: "詳細"
purpose_validation:
  cmd_purpose: "テスト"
  fit: true
  purpose_gap: ""
files_modified:
  - path: context/reported.md
    change: modified
lesson_candidate:
  found: false
  no_lesson_reason: "テスト用の報告であるため新規教訓なし"
  title: ""
  detail: ""
lessons_useful:
  - id: L001
    useful: true
    reason: helpful
binary_checks:
  AC1:
    - check: テスト完了
      result: yes
  commit:
    - check: git commitが完了したか
      result: yes
verdict: PASS
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
EOF

    run env GATE_NO_LOG=1 SKILL_EXECUTION_PASS_LOG_DISABLE=1 GATE_PASS_CACHE_FILE="$workdir/pass_cache" bash "$gate" "$rpath"

    [ "$status" -eq 0 ] || {
        echo "Expected exit 0 but got $status"
        echo "$output"
        echo "git status context/reported.md:"
        git -C "$workdir" status --porcelain -- context/reported.md || true
        rm -rf "$workdir"
        return 1
    }
    [[ "$output" != *"BLOCK(cmd_3264-AC2)"* ]]
    rm -rf "$workdir"
}

# === Test 4: PASS_NO_IMPROVEMENT はゲートとしてexit 0 (PASSと同等) ===
@test "PASS_NO_IMPROVEMENTのときゲートはexit 0を返す" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_2072.yaml"
    _write_base_pni_report "$rpath" "binary_checks:
  AC1:
    - check: revert済みで改善なし
      result: yes
  AC2:
    - check: revert適用確認
      result: yes"

    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
}

# === Test 5: verdict=PASS_NO_IMPROVEMENT も有効なverdict として受け付ける ===
@test "verdict=PASS_NO_IMPROVEMENTをninja報告でも受け付ける" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_2072.yaml"
    cat > "$rpath" <<EOF
worker_id: tobisaru
parent_cmd: cmd_2072
ac_version_read: test_hash_abc
timestamp: 2026-07-13T00:00:00+09:00
status: completed
result:
  summary: "テスト用報告"
  details: "詳細"
purpose_validation:
  cmd_purpose: "テスト"
  fit: true
  purpose_gap: ""
files_modified:
  - scripts/gates/gate_report_format_cmd_2072.sh
lesson_candidate:
  found: false
  no_lesson_reason: "テスト用の報告であるため新規教訓なし"
  title: ""
  detail: ""
lessons_useful:
  - id: L001
    useful: true
    reason: helpful
binary_checks:
  AC1:
    - check: 改善実装完了
      result: yes
verdict: PASS_NO_IMPROVEMENT
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
EOF

    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" != *"verdict:"*"is not valid"* ]]
}
