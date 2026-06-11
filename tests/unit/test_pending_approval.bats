#!/usr/bin/env bats
# test_pending_approval.bats — cmd_3285: 保留レジストリ + Guard 12 ライフサイクルテスト
# AC1: スクリプト登録・解除が機械可読
# AC2: 保留中ファイルのcommit BLOCK / 保留外は通過
# AC3: 解除後は通過（登録→BLOCK→解除→通過のライフサイクル）

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export HOOK_SCRIPT="$PROJECT_ROOT/.claude/hooks/pre-bash-combined.sh"
    export PA_SCRIPT="$PROJECT_ROOT/scripts/pending_approval_set.sh"
    [ -f "$HOOK_SCRIPT" ] || return 1
    [ -f "$PA_SCRIPT" ]  || return 1
}

setup() {
    # テスト用の一時 pending_approval.yaml
    export PA_FILE="$BATS_TEST_TMPDIR/pending_approval.yaml"
    printf 'entries: []\n' > "$PA_FILE"
}

# ── ヘルパー ──────────────────────────────────────────────

_run_pa() {
    run env PENDING_APPROVAL_FILE="$PA_FILE" bash "$PA_SCRIPT" "$@"
}

# Guard 12 hookテスト: staged files は GUARD12_STAGED_FILES_OVERRIDE でmock
_run_hook_commit() {
    local cmd="$1"
    local staged_files="${2:-}"   # mock staged files (改行区切り)
    local payload
    payload="$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd")"
    run env \
        PENDING_APPROVAL_FILE="$PA_FILE" \
        GUARD12_STAGED_FILES_OVERRIDE="$staged_files" \
        bash "$HOOK_SCRIPT" <<< "$payload" 2>/dev/null
}

# ======================================================================
# AC1: スクリプト操作
# ======================================================================

@test "AC1: add が登録項目(path/reason/registered_by/registered_at)を含む機械可読 YAML を出力" {
    _run_pa add "queue/some_file.yaml" "軍師レビュー待ち" "hayate"
    [ "$status" -eq 0 ]
    [[ "$output" == *"registered"* ]]

    # YAML が機械可読であることを確認 (python yaml.safe_load)
    run python3 -c "
import yaml
with open('$PA_FILE') as f:
    data = yaml.safe_load(f)
e = data['entries'][0]
assert e['path'] == 'queue/some_file.yaml', f'path={e[\"path\"]}'
assert e['reason'] == '軍師レビュー待ち', f'reason={e[\"reason\"]}'
assert e['registered_by'] == 'hayate', f'registered_by={e[\"registered_by\"]}'
assert 'registered_at' in e and e['registered_at'], 'registered_at missing'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AC1: remove が登録エントリを削除する" {
    _run_pa add "queue/some_file.yaml" "テスト" "hayate"
    [ "$status" -eq 0 ]
    _run_pa remove "queue/some_file.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"removed"* ]]

    run python3 -c "
import yaml
with open('$PA_FILE') as f:
    data = yaml.safe_load(f)
assert data['entries'] == [], f'entries not empty: {data[\"entries\"]}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AC1: 同一ファイルを2回 add しても重複登録されない" {
    _run_pa add "queue/dup.yaml" "重複テスト" "hayate"
    [ "$status" -eq 0 ]
    _run_pa add "queue/dup.yaml" "重複テスト2" "hayate"
    [ "$status" -eq 0 ]
    run python3 -c "
import yaml
with open('$PA_FILE') as f:
    data = yaml.safe_load(f)
assert len(data['entries']) == 1, f'expected 1 entry, got {len(data[\"entries\"])}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AC1: list が登録エントリを出力する" {
    _run_pa add "queue/list_test.yaml" "一覧テスト" "hanzo"
    [ "$status" -eq 0 ]
    _run_pa list
    [ "$status" -eq 0 ]
    [[ "$output" == *"queue/list_test.yaml"* ]]
}

# ======================================================================
# AC2: Guard 12 BLOCK / ALLOW テスト (GUARD12_STAGED_FILES_OVERRIDE mock)
# ======================================================================

@test "AC2: 保留中ファイルが staged にある場合 git commit は BLOCKED" {
    _run_pa add "queue/blocked_file.yaml" "裁可待ち" "hayate"
    [ "$status" -eq 0 ]

    # staged に保留ファイルを含む mock
    _run_hook_commit "git commit -m test" "queue/blocked_file.yaml"

    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
    [[ "$output" == *"G12"* ]]
    [[ "$output" == *"queue/blocked_file.yaml"* ]]
}

@test "AC2: 保留ファイルが staged に無い場合 git commit は G12 で BLOCK されない" {
    _run_pa add "queue/other_file.yaml" "他ファイル保留" "hayate"
    [ "$status" -eq 0 ]

    # staged には保留と無関係なファイル
    _run_hook_commit "git commit -m test" "queue/safe_file.yaml"

    [[ "$output" != *"G12"* ]]
}

@test "AC2: pending_approval.yaml が空(entries: [])の場合 git commit は G12 で BLOCK されない" {
    _run_hook_commit "git commit -m test" "queue/some_file.yaml"

    [[ "$output" != *"G12"* ]]
}

@test "AC2: git commit 以外のコマンド(git push等)は Guard 12 の影響を受けない" {
    _run_pa add "queue/pushed_file.yaml" "保留テスト" "hayate"
    [ "$status" -eq 0 ]

    _run_hook_commit "git status" "queue/pushed_file.yaml"

    [[ "$output" != *"G12"* ]]
}

# ======================================================================
# AC3: 登録→BLOCK→解除→通過 のライフサイクル
# ======================================================================

@test "AC3: 解除後は同一ファイルの commit が通過する" {
    # 1. 登録 → BLOCK 確認
    _run_pa add "queue/lifecycle_test.yaml" "ライフサイクルテスト" "hayate"
    [ "$status" -eq 0 ]

    _run_hook_commit "git commit -m test" "queue/lifecycle_test.yaml"
    [ "$status" -ne 0 ]
    [[ "$output" == *"G12"* ]]

    # 2. 解除 → 通過 確認
    _run_pa remove "queue/lifecycle_test.yaml"
    [ "$status" -eq 0 ]

    _run_hook_commit "git commit -m test" "queue/lifecycle_test.yaml"
    [[ "$output" != *"G12"* ]]
}
