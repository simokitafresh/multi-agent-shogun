#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export HOOK="$PROJECT_ROOT/.claude/hooks/pre-edit-pi-inject.sh"
    [ -f "$HOOK" ] || return 1
}

setup() {
    # DM-Signal mock構造
    export TMP_DIR
    TMP_DIR="$(mktemp -d)"
    mkdir -p "$TMP_DIR/config"
    mkdir -p "$TMP_DIR/projects"

    # config/projects.yaml mock
    cat > "$TMP_DIR/config/projects.yaml" <<'EOF'
projects:
  - id: dm-signal
    name: "DM-Signal"
    path: "/tmp/dm-signal-test"
    priority: high
    status: active
  - id: infra
    type: platform
    name: "Multi-Agent Infrastructure"
    path: "/tmp/infra-test"
    priority: medium
    status: active
EOF

    # projects/dm-signal.yaml mock (production_invariants のみ)
    cat > "$TMP_DIR/projects/dm-signal.yaml" <<'EOF'
production_invariants:
  last_updated: "2026-04-26"
  entries:
    - id: PI-003
      fact: "standard PFのconfig JSONにはpipeline_configが必須"
      implication: "全てのDB登録に適用"
    - id: PI-013
      fact: "DB INSERT前にPydanticモデル(Portfolio)の全制約を事前検証必須"
      implication: "全てのデータ書込みに適用"
    - id: PI-018
      fact: "except Exceptionでデータ値をfallback返却する新規コード禁止"
      implication: "全てのエラーハンドリングに適用"
    - id: PI-021
      fact: "本番既存の表示・計算の変更は絶対禁止"
      implication: "全ての本番変更に適用"
    - id: PI-023
      fact: "本番DB変更後は即パリティ確認必須"
      implication: "全ての本番状態変更に適用"
    - id: PI-025
      fact: "upfront cleanup後にRender worker restartするとMonthlyReturn 0件が永続化する"
      implication: "全てのバッチ前処理に適用"
EOF

    mkdir -p "/tmp/dm-signal-test/backend/app/services"
    mkdir -p "/tmp/dm-signal-test/frontend/components"
}

teardown() {
    rm -rf "$TMP_DIR" || true
    rm -rf "/tmp/dm-signal-test" || true
}

_run_hook() {
    local payload="$1"
    run bash -c 'printf "%s" "$1" | \
        REPO_ROOT="$2" bash "$3"' \
        _ "$payload" "$TMP_DIR" "$HOOK"
}

# ─── AC1: backend/app/ Edit → PI表示 ───

@test "AC1: Edit on backend/app/ shows PI-003" {
    _run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/dm-signal-test/backend/app/services/signal_calc.py"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'PI-003'* ]]
    [[ "$output" == *'additionalContext'* ]]
}

@test "AC1: Edit on backend/app/ shows PI-013, PI-018, PI-023, PI-025" {
    _run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/dm-signal-test/backend/app/models.py"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'PI-013'* ]]
    [[ "$output" == *'PI-018'* ]]
    [[ "$output" == *'PI-023'* ]]
    [[ "$output" == *'PI-025'* ]]
}

@test "AC1: Write on backend/app/ shows PI context" {
    _run_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/dm-signal-test/backend/app/new_service.py"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'PI-003'* ]]
    [[ "$output" == *'backend/app'* ]]
}

# ─── AC2: frontend/ Edit → FE注意事項表示 ───

@test "AC2: Edit on frontend/ shows PI-021" {
    _run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/dm-signal-test/frontend/components/Chart.tsx"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'PI-021'* ]]
    [[ "$output" == *'static export'* ]]
    [[ "$output" == *'additionalContext'* ]]
}

@test "AC2: Write on frontend/ shows FE context" {
    _run_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/dm-signal-test/frontend/pages/new_page.tsx"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'PI-021'* ]]
    [[ "$output" == *'use client'* ]]
}

# ─── AC3: DM-Signal以外 → 無発火 ───

@test "AC3: infra path does not trigger hook" {
    _run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/mnt/c/tools/multi-agent-shogun/scripts/some_script.sh"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "AC3: non-DM-Signal path does not trigger hook" {
    _run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/other_project/app.py"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "AC3: DM-Signal sibling prefix path does not trigger hook" {
    _run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/dm-signal-test-old/backend/app/service.py"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "AC3: empty payload exits cleanly" {
    _run_hook '{}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "AC3: Bash tool does not trigger hook" {
    _run_hook '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── PI動的取得検証 ───

@test "PI dynamic load: fact text matches YAML content" {
    _run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/dm-signal-test/backend/app/services/svc.py"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'pipeline_configが必須'* ]]
}

@test "PI dynamic load: PI-021 fact text matches YAML content" {
    _run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/dm-signal-test/frontend/contexts/AuthContext.tsx"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'本番既存の表示'* ]]
}
