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
    export MASTER_GATE_FIXTURE="$BATS_FILE_TMPDIR/gate_fixture"
    mkdir -p "$MASTER_GATE_FIXTURE/scripts/gates" "$MASTER_GATE_FIXTURE/scripts/lib"
    cp "$GATE_SCRIPT" "$MASTER_GATE_FIXTURE/scripts/gates/gate_report_format.sh"
    cp "$GATE_MAIN_SCRIPT" "$MASTER_GATE_FIXTURE/scripts/gates/gate_report_format_main.py"
    cp "$PROJECT_ROOT/scripts/lib/report_commit_identity.py" "$MASTER_GATE_FIXTURE/scripts/lib/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_combined.py" "$MASTER_GATE_FIXTURE/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_autofix_main.py" "$MASTER_GATE_FIXTURE/scripts/gates/"
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/pni_test.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/scripts/lib" \
             "$TEST_TMPDIR/queue/reports" \
             "$TEST_TMPDIR/queue/tasks" \
             "$TEST_TMPDIR/logs"
    cp -al "$MASTER_GATE_FIXTURE/." "$TEST_TMPDIR/"
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
causal_verification:
  cause_checked: regression fixture for report verdict handling
  design_intent_checked: exercise the production gate path
  evidence: "rg -n gate_report_format scripts --glob '!tests/**'; non-test caller count: 1"
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
operational_simulation:
  command: "bash scripts/gates/gate_report_format.sh queue/reports/tobisaru_report_cmd_2072.yaml"
  expected: "verdict follows binary-check improvement outcome"
  actual: "PASS or PASS_NO_IMPROVEMENT derived as expected"
  result: "PASS"
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

@test "same report generation validates once and byte change forces full validation" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_2072.yaml"
    local cache="$TEST_TMPDIR/logs/fingerprints"
    _write_base_pni_report "$rpath" "binary_checks:
  AC1:
    - check: テスト全PASS
      result: yes"

    run env GATE_FAST_EXIT=1 GATE_NO_LOG=1 GATE_FINGERPRINT_CACHE_FILE="$cache" bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    local fp
    fp=$(sha256sum "$rpath" | awk '{print $1}')
    [ "$(grep -cFx "$fp" "$cache")" -eq 1 ]

    run env GATE_VALIDATED_FINGERPRINT="$fp" GATE_FINGERPRINT_CACHE_FILE="$cache" bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS (fingerprint reuse)"* ]]

    printf '\n# changed generation\n' >> "$rpath"
    run env GATE_VALIDATED_FINGERPRINT="$fp" GATE_FAST_EXIT=1 GATE_NO_LOG=1 GATE_FINGERPRINT_CACHE_FILE="$cache" bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" != *"fingerprint reuse"* ]]
    [ "$(find "$TEST_TMPDIR/logs" -name fingerprints -type f | wc -l)" -eq 1 ]
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
    local workdir="$BATS_TEST_TMPDIR/gate_report_format_cmd3264_test"
    local task_path="$workdir/queue/tasks/${worker}.yaml"
    local rpath="$workdir/queue/reports/${worker}_report_cmd_3264.yaml"
    local gate="$workdir/scripts/gates/gate_report_format.sh"
    rm -rf "$workdir"
    mkdir -p "$workdir/scripts/gates" "$workdir/scripts/lib" "$workdir/queue/reports" "$workdir/queue/tasks" "$workdir/logs" "$workdir/target"
    cp -al "$MASTER_GATE_FIXTURE/." "$workdir/"
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
operational_simulation:
  command: "bash scripts/gates/gate_report_format.sh queue/reports/tobisaru_report_cmd_2072.yaml"
  expected: "PASS_NO_IMPROVEMENT is accepted for ninja reports"
  actual: "verdict validation completed"
  result: "PASS"
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
    local workdir="$BATS_TEST_TMPDIR/gate_report_format_cmd3264_readonly_test"
    local task_path="$workdir/queue/tasks/${worker}.yaml"
    local rpath="$workdir/queue/reports/${worker}_report_cmd_3264_readonly.yaml"
    local gate="$workdir/scripts/gates/gate_report_format.sh"
    rm -rf "$workdir"
    mkdir -p "$workdir/scripts/gates" "$workdir/scripts/lib" "$workdir/queue/reports" "$workdir/queue/tasks" "$workdir/logs" "$workdir/queue/tasks"
    cp -al "$MASTER_GATE_FIXTURE/." "$workdir/"
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
    local workdir="$BATS_TEST_TMPDIR/gate_report_format_cmd3264_root_test"
    local task_path="$workdir/queue/tasks/${worker}.yaml"
    local rpath="$workdir/queue/reports/${worker}_report_cmd_3264.yaml"
    local gate="$workdir/scripts/gates/gate_report_format.sh"
    rm -rf "$workdir"
    mkdir -p "$workdir/scripts/gates" "$workdir/scripts/lib" "$workdir/queue/reports" "$workdir/queue/tasks" "$workdir/logs" "$workdir/context"
    cp -al "$MASTER_GATE_FIXTURE/." "$workdir/"
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
    local workdir="$BATS_TEST_TMPDIR/gate_report_format_cmd3264_shared_test"
    local task_path="$workdir/queue/tasks/${worker}.yaml"
    local rpath="$workdir/queue/reports/${worker}_report_cmd_3264.yaml"
    local gate="$workdir/scripts/gates/gate_report_format.sh"
    rm -rf "$workdir"
    mkdir -p "$workdir/scripts/gates" "$workdir/scripts/lib" "$workdir/queue/reports" "$workdir/queue/tasks" "$workdir/logs" "$workdir/context"
    cp -al "$MASTER_GATE_FIXTURE/." "$workdir/"
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
    local workdir="$BATS_TEST_TMPDIR/gate_report_format_cmd3264_files_test"
    local task_path="$workdir/queue/tasks/${worker}.yaml"
    local rpath="$workdir/queue/reports/${worker}_report_cmd_3264.yaml"
    local gate="$workdir/scripts/gates/gate_report_format.sh"
    rm -rf "$workdir"
    mkdir -p "$workdir/scripts/gates" "$workdir/scripts/lib" "$workdir/queue/reports" "$workdir/queue/tasks" "$workdir/logs" "$workdir/target" "$workdir/context"
    cp -al "$MASTER_GATE_FIXTURE/." "$workdir/"
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
    local workdir="$BATS_TEST_TMPDIR/gate_report_format_cmd3264_nonoverlap_test"
    local task_path="$workdir/queue/tasks/${worker}.yaml"
    local rpath="$workdir/queue/reports/${worker}_report_cmd_3264.yaml"
    local gate="$workdir/scripts/gates/gate_report_format.sh"
    rm -rf "$workdir"
    mkdir -p "$workdir/scripts/gates" "$workdir/scripts/lib" "$workdir/queue/reports" "$workdir/queue/tasks" "$workdir/logs" "$workdir/context"
    cp -al "$MASTER_GATE_FIXTURE/." "$workdir/"
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

@test "cmd_3264 AC2 delegates exact shared review log ownership to SSOT" {
    run rg -n 'filter_report_commit_nonoverlap_uncommitted.*shared_path' "$PROJECT_ROOT/scripts/gates/gate_report_format.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *'filter_report_commit_nonoverlap_uncommitted'* ]]
}

_write_bulk_insights_fixture() {
    local workdir="$1"
    local report="$workdir/queue/reports/bulk_report.yaml"
    mkdir -p "$workdir/queue/archive" "$workdir/queue/reports"
    cat > "$workdir/queue/insights.yaml" <<'EOF'
insights:
  - id: INS-owned
    insight: worker-owned baseline
    priority: medium
    source: manual
    status: pending
    ts: '2026-08-08T00:00:00+09:00'
  - id: INS-retro
    insight: self retro baseline
    priority: low
    source: self_retro
    status: pending
    occurrence_count: 1
    last_seen: '2026-08-08T00:00:00+09:00'
    ts: '2026-08-08T00:00:00+09:00'
EOF
    cp "$workdir/queue/insights.yaml" "$workdir/queue/archive/insights_archive.yaml"
    git -C "$workdir" add queue/insights.yaml queue/archive/insights_archive.yaml
    git -C "$workdir" -c user.email=test@example.com -c user.name=test commit -q -m init
    printf '%s\n' "$report"
}

_write_bulk_report() {
    local report="$1"
    local commit_hash="$2"
    cat > "$report" <<EOF
worker_id: saizo
parent_cmd: cmd_karo_hotfix_insights_dirty_finish
task_id: cmd_karo_hotfix_insights_dirty_finish_normal
commit_hash: ${commit_hash}
task_contract_snapshot:
  acceptance_criteria:
    - id: AC1
      description: bulk queue integrity
  task_id: cmd_karo_hotfix_insights_dirty_finish_normal
reflux_commit_contract: null
EOF
}

# test_necessity: bulk queue dirty-finish must retain only producer-owned reflux
# additions and lifecycle metadata updates; otherwise report commit results can
# be silently replaced by a concurrent writer.
# regression_justification: the former snapshot_ids_empty sys.exit(0) accepted
# every concurrent edit, including ordinary existing-entry mutations.
@test "cmd_3264 bulk insights allows reflux new ID and lifecycle metadata refresh" {
    local workdir="$BATS_TEST_TMPDIR/gate_report_format_bulk_valid_test"
    local report
    rm -rf "$workdir"
    mkdir -p "$workdir/scripts/gates" "$workdir/scripts/lib"
    cp -al "$MASTER_GATE_FIXTURE/." "$workdir/"
    chmod +x "$workdir/scripts/gates/gate_report_format.sh"
    git -C "$workdir" init -q
    report=$(_write_bulk_insights_fixture "$workdir")
    python3 - "$workdir/queue/insights.yaml" <<'PY'
import sys, yaml
path = sys.argv[1]
data = yaml.safe_load(open(path, encoding='utf-8'))
data['insights'][1]['occurrence_count'] = 2
data['insights'][1]['last_seen'] = '2026-08-08T23:00:00+09:00'
data['insights'].append({
    'id': 'INS-auto', 'insight': 'automatic reflux entry', 'priority': 'low',
    'source': 'cmd_complete_gate:l6_horizontal:cmd_bulk', 'status': 'pending',
    'fix_known': False, 'ts': '2026-08-08T23:00:00+09:00'
})
with open(path, 'w', encoding='utf-8') as stream:
    yaml.safe_dump(data, stream, allow_unicode=True, sort_keys=False)
PY
    git -C "$workdir" add queue/insights.yaml
    git -C "$workdir" -c user.email=test@example.com -c user.name=test commit -q -m cmd_bulk
    local commit_hash
    commit_hash=$(git -C "$workdir" rev-parse HEAD)
    python3 - "$workdir/queue/insights.yaml" <<'PY'
import sys, yaml
path = sys.argv[1]
data = yaml.safe_load(open(path, encoding='utf-8'))
data['insights'][1]['occurrence_count'] = 3
data['insights'].append({
    'id': 'INS-auto-2', 'insight': 'automatic reflux entry 2', 'priority': 'low',
    'source': 'semantic_index_update', 'status': 'resolved',
    'resolved_reason': 'absorbed', 'action_artifact': 'index',
    'resolved_at': '2026-08-08T23:01:00+09:00', 'fix_known': False,
    'ts': '2026-08-08T23:01:00+09:00'
})
with open(path, 'w', encoding='utf-8') as stream:
    yaml.safe_dump(data, stream, allow_unicode=True, sort_keys=False)
PY
    _write_bulk_report "$report" "$commit_hash"

    run env GATE_REPORT_FORMAT_REFLUX_CONTRACT_TEST=1 \
        GATE_REPO_ROOT_OVERRIDE="$workdir" \
        GATE_REFLUX_UNCOMMITTED_PATHS=' M queue/insights.yaml' \
        bash "$workdir/scripts/gates/gate_report_format.sh" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" != *' M queue/insights.yaml'* ]]
}

# test_necessity: an existing insight body mutation is not a reflux lifecycle
# transition and must remain visible to the contamination gate.
# regression_justification: reproduces the false-PASS path introduced when
# bulk dirty-finish ownership checks were skipped.
@test "cmd_3264 bulk insights blocks hostile existing-entry body mutation" {
    local workdir="$BATS_TEST_TMPDIR/gate_report_format_bulk_hostile_test"
    local report
    rm -rf "$workdir"
    mkdir -p "$workdir/scripts/gates" "$workdir/scripts/lib"
    cp -al "$MASTER_GATE_FIXTURE/." "$workdir/"
    chmod +x "$workdir/scripts/gates/gate_report_format.sh"
    git -C "$workdir" init -q
    report=$(_write_bulk_insights_fixture "$workdir")
    printf '\n# worker commit\n' >> "$workdir/queue/insights.yaml"
    git -C "$workdir" add queue/insights.yaml
    git -C "$workdir" -c user.email=test@example.com -c user.name=test commit -q -m cmd_bulk
    local commit_hash
    commit_hash=$(git -C "$workdir" rev-parse HEAD)
    python3 - "$workdir/queue/insights.yaml" <<'PY'
import sys, yaml
path = sys.argv[1]
data = yaml.safe_load(open(path, encoding='utf-8'))
data['insights'][0]['insight'] = 'hostile body mutation'
with open(path, 'w', encoding='utf-8') as stream:
    yaml.safe_dump(data, stream, allow_unicode=True, sort_keys=False)
PY
    _write_bulk_report "$report" "$commit_hash"

    run env GATE_REPORT_FORMAT_REFLUX_CONTRACT_TEST=1 \
        GATE_REPO_ROOT_OVERRIDE="$workdir" \
        GATE_REFLUX_UNCOMMITTED_PATHS=' M queue/insights.yaml' \
        bash "$workdir/scripts/gates/gate_report_format.sh" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *' M queue/insights.yaml'* ]]
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
causal_verification:
  cause_checked: regression fixture for report verdict handling
  design_intent_checked: exercise the production gate path
  evidence: "rg -n gate_report_format scripts --glob '!tests/**'; non-test caller count: 1"
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
operational_simulation:
  command: "bash scripts/gates/gate_report_format.sh queue/reports/tobisaru_report_cmd_2072.yaml"
  expected: "PASS_NO_IMPROVEMENT is accepted for ninja reports"
  actual: "verdict validation completed"
  result: "PASS"
EOF

    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" != *"verdict:"*"is not valid"* ]]
}
