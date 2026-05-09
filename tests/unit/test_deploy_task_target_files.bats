#!/usr/bin/env bats
# test_deploy_task_target_files.bats — cmd_1563 target_filesフィルタのユニットテスト

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    command -v python3 >/dev/null 2>&1 || return 1

    export TARGET_FILES_RESULTS_DIR
    TARGET_FILES_RESULTS_DIR="$(mktemp -d "$BATS_TMPDIR/target_files_results.XXXXXX")"

    python3 - "$TARGET_FILES_RESULTS_DIR" <<'PY'
import fnmatch
import json
import os
import re
import sys

results_dir = sys.argv[1]

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

def run_target_files_filter(lessons_json, task_files_json):
    confirmed_lessons = json.loads(lessons_json)
    _all_task_files = json.loads(task_files_json)

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
    else:
        # GP-218: no task files → exclude lessons WITH target_files
        _tf_filtered = []
        for _l in confirmed_lessons:
            _ltf = _l.get('target_files', [])
            if isinstance(_ltf, str):
                _ltf = [_ltf]
            if _ltf and any(str(p).strip() for p in _ltf):
                continue
            _tf_filtered.append(_l)
        confirmed_lessons = _tf_filtered

    return '\n'.join(l['id'] for l in confirmed_lessons)

ALIASES = {
    'frontend': 'fe', 'front': 'fe', 'ui': 'fe', 'fe': 'fe',
    'backend': 'be', 'back': 'be', 'api': 'be', 'be': 'be',
    'grid_search': 'gs', 'grid-search': 'gs', 'gridsearch': 'gs', 'gs': 'gs',
    'infra': 'infra', 'platform': 'infra',
}

def normalize_subdomains(value):
    if value is None or value == '':
        return set()
    if isinstance(value, str):
        raw_items = re.split(r'[, ]+', value)
    elif isinstance(value, list):
        raw_items = value
    else:
        raw_items = [value]
    return {ALIASES.get(str(item).lower().strip(), str(item).lower().strip()) for item in raw_items if str(item).strip()}

def infer_subdomains_from_paths(paths):
    inferred = set()
    for raw_path in paths:
        path = str(raw_path).replace('\\', '/').lower().strip()
        basename = os.path.basename(path)
        if '/frontend/' in path or path.startswith('frontend/'):
            inferred.add('fe')
        if '/backend/' in path or path.startswith('backend/') or '/app/api/' in path:
            inferred.add('be')
        if '/grid_search/' in path or '/outputs/grid_search/' in path or 'grid_search' in path or basename.startswith('run_077') or basename.startswith('gs_'):
            inferred.add('gs')
        if path.startswith(('scripts/', 'queue/', 'context/', 'instructions/', 'projects/', 'config/', 'tests/')) and not inferred:
            inferred.add('infra')
    return inferred

def run_subdomain_filter(lessons_json, task_files_json):
    confirmed_lessons = json.loads(lessons_json)
    task_files = json.loads(task_files_json)
    task_subdomains = infer_subdomains_from_paths(task_files)
    if task_subdomains:
        confirmed_lessons = [
            lesson for lesson in confirmed_lessons
            if not normalize_subdomains(lesson.get('subdomain')) or normalize_subdomains(lesson.get('subdomain')) & task_subdomains
        ]

    return '\n'.join(lesson['id'] for lesson in confirmed_lessons)

cases = {
    'target_no_tf': (
        run_target_files_filter,
        '[{"id": "L001", "tags": ["bash"]}, {"id": "L002", "tags": ["python"]}]',
        '["/mnt/c/tools/scripts/deploy.sh"]',
    ),
    'target_exact_basename': (
        run_target_files_filter,
        '[{"id": "L001", "target_files": ["deploy_task.sh"]}, {"id": "L002", "tags": ["python"]}]',
        '["/mnt/c/tools/scripts/deploy_task.sh"]',
    ),
    'target_non_matching': (
        run_target_files_filter,
        '[{"id": "L001", "target_files": ["ntfy.sh"]}, {"id": "L002", "tags": ["python"]}]',
        '["/mnt/c/tools/scripts/deploy_task.sh"]',
    ),
    'target_glob_py': (
        run_target_files_filter,
        '[{"id": "L001", "target_files": ["*.py"]}, {"id": "L002", "target_files": ["*.sh"]}]',
        '["/mnt/c/tools/scripts/lib/inject.py"]',
    ),
    'target_multiple_files': (
        run_target_files_filter,
        '[{"id": "L001", "target_files": ["deploy_task.sh"]}, {"id": "L002", "target_files": ["inject.py"]}]',
        '["/mnt/c/tools/scripts/deploy_task.sh", "/mnt/c/tools/scripts/lib/inject.py"]',
    ),
    'target_empty_excludes_with_tf': (
        run_target_files_filter,
        '[{"id": "L001", "target_files": ["ntfy.sh"]}, {"id": "L002", "tags": ["python"]}]',
        '[]',
    ),
    'target_empty_passes_without_tf': (
        run_target_files_filter,
        '[{"id": "L001", "tags": ["bash"]}, {"id": "L002", "target_files": ["frontend/src/"]}]',
        '[]',
    ),
    'target_string_tf': (
        run_target_files_filter,
        '[{"id": "L001", "target_files": "deploy_task.sh"}]',
        '["/mnt/c/tools/scripts/deploy_task.sh"]',
    ),
    'target_subdir_pattern': (
        run_target_files_filter,
        '[{"id": "L001", "target_files": ["scripts/lib/*.py"]}]',
        '["/mnt/c/tools/multi-agent-shogun/scripts/lib/inject_task_modifiers.py"]',
    ),
    'subdomain_frontend': (
        run_subdomain_filter,
        '[{"id": "L502", "subdomain": "gs"}, {"id": "L_FE", "subdomain": "fe"}, {"id": "L_OLD"}]',
        '["frontend/app/compare-summary/page.tsx"]',
    ),
}

for name, (runner, lessons_json, task_files_json) in cases.items():
    with open(os.path.join(results_dir, name), 'w', encoding='utf-8') as fh:
        result = runner(lessons_json, task_files_json)
        if result:
            fh.write(result)
            fh.write('\n')
PY
}

teardown_file() {
    [ -n "$TARGET_FILES_RESULTS_DIR" ] && [ -d "$TARGET_FILES_RESULTS_DIR" ] && rm -rf "$TARGET_FILES_RESULTS_DIR"
}

case_output() {
    cat "$TARGET_FILES_RESULTS_DIR/$1"
}

@test "target_files: lesson without target_files passes through" {
    output="$(case_output target_no_tf)"
    [[ "$output" == *"L001"* ]]
    [[ "$output" == *"L002"* ]]
}

@test "target_files: exact basename match includes lesson" {
    output="$(case_output target_exact_basename)"
    [[ "$output" == *"L001"* ]]
    [[ "$output" == *"L002"* ]]
}

@test "target_files: non-matching target_files excludes lesson" {
    output="$(case_output target_non_matching)"
    [[ "$output" != *"L001"* ]]
    [[ "$output" == *"L002"* ]]
}

@test "target_files: glob pattern *.py matches .py files" {
    output="$(case_output target_glob_py)"
    [[ "$output" == *"L001"* ]]
    [[ "$output" != *"L002"* ]]
}

@test "target_files: multiple task files match any" {
    output="$(case_output target_multiple_files)"
    [[ "$output" == *"L001"* ]]
    [[ "$output" == *"L002"* ]]
}

@test "target_files: empty task_files excludes lessons WITH target_files (GP-218)" {
    output="$(case_output target_empty_excludes_with_tf)"
    [[ "$output" != *"L001"* ]]
    [[ "$output" == *"L002"* ]]
}

@test "target_files: empty task_files passes lessons WITHOUT target_files (GP-218)" {
    output="$(case_output target_empty_passes_without_tf)"
    [[ "$output" == *"L001"* ]]
    [[ "$output" != *"L002"* ]]
}

@test "target_files: string target_files (not list) is handled" {
    output="$(case_output target_string_tf)"
    [[ "$output" == *"L001"* ]]
}

@test "target_files: path with subdirectory pattern matches" {
    output="$(case_output target_subdir_pattern)"
    # basename of pattern ("*.py") should match basename of task file ("inject_task_modifiers.py")
    [[ "$output" == *"L001"* ]]
}

@test "subdomain: frontend target excludes GS-specific lesson and keeps untagged lessons" {
    output="$(case_output subdomain_frontend)"
    [[ "$output" != *"L502"* ]]
    [[ "$output" == *"L_FE"* ]]
    [[ "$output" == *"L_OLD"* ]]
}
