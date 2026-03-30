#!/usr/bin/env bats
# test_deploy_task_target_files.bats — cmd_1563 target_filesフィルタのユニットテスト

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/target_files.XXXXXX")"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# Helper: run target_files matching logic with given lessons + task files
run_target_files_filter() {
    local lessons_json="$1"
    local task_files_json="$2"
    python3 - "$lessons_json" "$task_files_json" <<'PY'
import fnmatch
import json
import os
import sys

lessons_json = sys.argv[1]
task_files_json = sys.argv[2]

confirmed_lessons = json.loads(lessons_json)
_all_task_files = json.loads(task_files_json)

def _target_files_match(lesson_target_files, task_files):
    """教訓のtarget_filesパターンがタスクファイルのいずれかにマッチするか判定"""
    for pattern in lesson_target_files:
        pattern = str(pattern).strip()
        if not pattern:
            continue
        for tf in task_files:
            if fnmatch.fnmatch(tf, pattern) or fnmatch.fnmatch(os.path.basename(tf), pattern):
                return True
            if fnmatch.fnmatch(os.path.basename(tf), os.path.basename(pattern)):
                return True
    return False

if _all_task_files:
    _tf_filtered = []
    for _l in confirmed_lessons:
        _ltf = _l.get('target_files', [])
        if not _ltf:
            _tf_filtered.append(_l)
            continue
        if isinstance(_ltf, str):
            _ltf = [_ltf]
        if _target_files_match(_ltf, _all_task_files):
            _tf_filtered.append(_l)
    confirmed_lessons = _tf_filtered

for l in confirmed_lessons:
    print(l['id'])
PY
}

@test "target_files: lesson without target_files passes through" {
    run run_target_files_filter \
        '[{"id": "L001", "tags": ["bash"]}, {"id": "L002", "tags": ["python"]}]' \
        '["/mnt/c/tools/scripts/deploy.sh"]'
    [ "$status" -eq 0 ]
    [[ "$output" == *"L001"* ]]
    [[ "$output" == *"L002"* ]]
}

@test "target_files: exact basename match includes lesson" {
    run run_target_files_filter \
        '[{"id": "L001", "target_files": ["deploy_task.sh"]}, {"id": "L002", "tags": ["python"]}]' \
        '["/mnt/c/tools/scripts/deploy_task.sh"]'
    [ "$status" -eq 0 ]
    [[ "$output" == *"L001"* ]]
    [[ "$output" == *"L002"* ]]
}

@test "target_files: non-matching target_files excludes lesson" {
    run run_target_files_filter \
        '[{"id": "L001", "target_files": ["ntfy.sh"]}, {"id": "L002", "tags": ["python"]}]' \
        '["/mnt/c/tools/scripts/deploy_task.sh"]'
    [ "$status" -eq 0 ]
    [[ "$output" != *"L001"* ]]
    [[ "$output" == *"L002"* ]]
}

@test "target_files: glob pattern *.py matches .py files" {
    run run_target_files_filter \
        '[{"id": "L001", "target_files": ["*.py"]}, {"id": "L002", "target_files": ["*.sh"]}]' \
        '["/mnt/c/tools/scripts/lib/inject.py"]'
    [ "$status" -eq 0 ]
    [[ "$output" == *"L001"* ]]
    [[ "$output" != *"L002"* ]]
}

@test "target_files: multiple task files match any" {
    run run_target_files_filter \
        '[{"id": "L001", "target_files": ["deploy_task.sh"]}, {"id": "L002", "target_files": ["inject.py"]}]' \
        '["/mnt/c/tools/scripts/deploy_task.sh", "/mnt/c/tools/scripts/lib/inject.py"]'
    [ "$status" -eq 0 ]
    [[ "$output" == *"L001"* ]]
    [[ "$output" == *"L002"* ]]
}

@test "target_files: empty task_files skips filter (all pass)" {
    run run_target_files_filter \
        '[{"id": "L001", "target_files": ["ntfy.sh"]}, {"id": "L002", "tags": ["python"]}]' \
        '[]'
    [ "$status" -eq 0 ]
    [[ "$output" == *"L001"* ]]
    [[ "$output" == *"L002"* ]]
}

@test "target_files: string target_files (not list) is handled" {
    run run_target_files_filter \
        '[{"id": "L001", "target_files": "deploy_task.sh"}]' \
        '["/mnt/c/tools/scripts/deploy_task.sh"]'
    [ "$status" -eq 0 ]
    [[ "$output" == *"L001"* ]]
}

@test "target_files: path with subdirectory pattern matches" {
    run run_target_files_filter \
        '[{"id": "L001", "target_files": ["scripts/lib/*.py"]}]' \
        '["/mnt/c/tools/multi-agent-shogun/scripts/lib/inject_task_modifiers.py"]'
    [ "$status" -eq 0 ]
    # basename of pattern ("*.py") should match basename of task file ("inject_task_modifiers.py")
    [[ "$output" == *"L001"* ]]
}
