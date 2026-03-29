#!/usr/bin/env bats
# test_context_freshness_check.bats — context_freshness_check.sh unit tests
# cmd_1559: 鮮度判定ロジック/古いファイル検出/出力フォーマットのテスト可能分岐を検証

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/context_freshness_check.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cfc.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts" \
             "$TEST_TMPDIR/config" \
             "$TEST_TMPDIR/context" \
             "$TEST_TMPDIR/queue/archive/cmds" \
             "$TEST_TMPDIR/queue"

    # Copy the script under test
    cp "$SRC_SCRIPT" "$TEST_TMPDIR/scripts/context_freshness_check.sh"
    chmod +x "$TEST_TMPDIR/scripts/context_freshness_check.sh"

    # Default: one active project with context_file mapping
    cat > "$TEST_TMPDIR/config/projects.yaml" <<'PROJYAML'
projects:
  - id: dm-signal
    status: active
    context_file: context/dm-signal.md
    context_files:
      - file: context/dm-signal-core.md
  - id: infra
    status: active
    context_file: context/infrastructure.md
  - id: archived-proj
    status: archived
    context_file: context/archived-proj.md
PROJYAML

    # Helper: today and stale date strings
    TODAY="$(date +%Y-%m-%d)"
    STALE_DATE="$(date -d '30 days ago' +%Y-%m-%d 2>/dev/null || date -v-30d +%Y-%m-%d)"

    export TEST_SCRIPT="$TEST_TMPDIR/scripts/context_freshness_check.sh"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# ── Helper: create context file with last_updated ──
_create_context() {
    local rel_path="$1" updated_date="${2:-}"
    local abs_path="$TEST_TMPDIR/$rel_path"
    mkdir -p "$(dirname "$abs_path")"
    if [ -n "$updated_date" ]; then
        printf '<!-- last_updated: %s -->\n# Context\nSome content\n' "$updated_date" > "$abs_path"
    else
        printf '# Context\nSome content without last_updated\n' > "$abs_path"
    fi
}

# ── Helper: create archive cmd entry ──
_create_archive_cmd() {
    local cmd_id="$1" project="$2" status="${3:-completed}" completed_date="${4:-$TODAY}"
    local fname="${cmd_id}_${completed_date}.yaml"
    cat > "$TEST_TMPDIR/queue/archive/cmds/$fname" <<ARCHYAML
id: $cmd_id
project: $project
status: $status
completed_at: $completed_date
ARCHYAML
}

# ── Helper: create shogun_to_karo.yaml with cmd entry ──
_create_shogun_to_karo() {
    local cmd_id="$1" project="$2"
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<STKYAML
commands:
  - id: $cmd_id
    project: $project
    description: test command
STKYAML
}

# === Test 1: モード未指定 → exit 1 + usage ===
@test "no mode argument → exit 1 with usage" {
    run bash "$TEST_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# === Test 2: 不明モード → exit 1 + usage ===
@test "unknown mode → exit 1 with usage" {
    run bash "$TEST_SCRIPT" --invalid-mode
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# === Test 3: --cmd-warnings 引数なし → exit 1 ===
@test "--cmd-warnings without cmd_id → exit 1 with usage" {
    run bash "$TEST_SCRIPT" --cmd-warnings
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# === Test 4: --dashboard-warnings 鮮度OK → 警告なし ===
@test "--dashboard-warnings with fresh context → no warnings" {
    _create_context "context/dm-signal.md" "$TODAY"
    _create_context "context/dm-signal-core.md" "$TODAY"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# === Test 5: --dashboard-warnings 陳腐化ファイル → WARN出力 ===
@test "--dashboard-warnings with stale context → WARN output" {
    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN:"* ]]
    [[ "$output" == *"context/dm-signal.md"* ]]
    [[ "$output" == *"日前"* ]]
}

# === Test 6: --dashboard-warnings last_updated未記載 → WARN "未記載" ===
@test "--dashboard-warnings with missing last_updated → WARN 未記載" {
    _create_context "context/dm-signal.md"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN:"* ]]
    [[ "$output" == *"未記載"* ]]
}

# === Test 7: --cmd-warnings 有効cmd_id → 該当PJのWARN ===
@test "--cmd-warnings with valid cmd_id → warnings for that project" {
    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_context "context/infrastructure.md" "$STALE_DATE"
    _create_shogun_to_karo "cmd_500" "dm-signal"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_500
    [ "$status" -eq 0 ]
    [[ "$output" == *"context/dm-signal.md"* ]]
    # infra context should NOT appear (different project)
    [[ "$output" != *"infrastructure.md"* ]]
}

# === Test 8: CONTEXT_STALE_DAYS 環境変数オーバーライド ===
@test "CONTEXT_STALE_DAYS override changes threshold" {
    # 3日前のファイル: デフォルト7日では鮮度OK、2日閾値なら陳腐化
    local three_days_ago
    three_days_ago="$(date -d '3 days ago' +%Y-%m-%d 2>/dev/null || date -v-3d +%Y-%m-%d)"
    _create_context "context/dm-signal.md" "$three_days_ago"
    _create_context "context/dm-signal-core.md" "$TODAY"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"

    # デフォルト(7日): 3日前は鮮度OK → 警告なし
    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    # 閾値2日に変更: 3日前は陳腐化 → WARN
    CONTEXT_STALE_DAYS=2 run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN:"* ]]
}

# === Test 9: 最近の完了cmdなしPJ → 警告スキップ(dashboard) ===
@test "--dashboard-warnings skips projects without recent completed cmds" {
    _create_context "context/dm-signal.md" "$STALE_DATE"
    # archive空: dm-signalに最近の完了cmdなし

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
