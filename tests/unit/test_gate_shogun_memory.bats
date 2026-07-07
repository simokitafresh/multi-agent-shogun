#!/usr/bin/env bats
# test_gate_shogun_memory.bats — gate_shogun_memory.sh unit tests

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_shogun_memory.sh"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/shogun_memory.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" \
             "$TEST_TMPDIR/repo/queue" \
             "$TEST_TMPDIR/repo/logs" \
             "$TEST_TMPDIR/repo/memory" \
             "$TEST_TMPDIR/home"

    cp "$SRC_GATE_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_shogun_memory.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_shogun_memory.sh"

    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_shogun_memory.sh"
    export TEST_REPO="$TEST_TMPDIR/repo"
    export TEST_MEMORY_FILE="$TEST_TMPDIR/home/MEMORY.md"
    export TEST_CHANGELOG="$TEST_TMPDIR/repo/queue/completed_changelog.yaml"
    export TEST_PENDING="$TEST_TMPDIR/repo/queue/pending_decisions.yaml"
    export TEST_CLAUDE="$TEST_TMPDIR/repo/CLAUDE.md"

    cat > "$TEST_MEMORY_FILE" <<EOF
# MEMORY
Last curated: $(date '+%Y-%m-%d')
参照: memory/deepdive_why_chain_20260321.md
EOF
    echo "# deepdive" > "$TEST_TMPDIR/repo/memory/deepdive_why_chain_20260321.md"
    cat > "$TEST_CLAUDE" <<'EOF'
# CLAUDE
EOF
    : > "$TEST_CHANGELOG"
    : > "$TEST_PENDING"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

run_gate() {
    env \
        SHOGUN_MEMORY_SCRIPT_DIR="$TEST_REPO" \
        SHOGUN_MEMORY_FILE="$TEST_MEMORY_FILE" \
        SHOGUN_MEMORY_CLAUDE_MD="$TEST_CLAUDE" \
        SHOGUN_MEMORY_CHANGELOG="$TEST_CHANGELOG" \
        SHOGUN_MEMORY_PENDING_DECISIONS="$TEST_PENDING" \
        bash "$TEST_GATE"
}

@test "all checks pass → exit 0" {
    run run_gate
    [ "$status" -eq 0 ]
    [[ "$output" == *"総合判定: OK"* ]]
    [[ "$output" == *"参照ファイル実在: 1件全て存在"* ]]
}

@test "completed cmd left in MEMORY → WARN exit 2" {
    cat > "$TEST_MEMORY_FILE" <<EOF
# MEMORY
Last curated: $(date '+%Y-%m-%d')
cmd_999 完了メモ
参照: memory/deepdive_why_chain_20260321.md
EOF
    cat > "$TEST_CHANGELOG" <<'EOF'
- id: cmd_999
  status: completed
EOF

    run run_gate
    [ "$status" -eq 2 ]
    [[ "$output" == *"WARN: 陳腐化検出"* ]]
    [[ "$output" == *"cmd_999"* ]]
}

@test "tracker missing with staging entries → WARN exit 2" {
    cat > "$TEST_REPO/queue/mcp_sync_staging.yaml" <<'EOF'
entries:
  - project: infra
    observation: "share me"
EOF

    run env \
        SHOGUN_MEMORY_SCRIPT_DIR="$TEST_REPO" \
        SHOGUN_MEMORY_FILE="$TEST_MEMORY_FILE" \
        SHOGUN_MEMORY_CLAUDE_MD="$TEST_CLAUDE" \
        SHOGUN_MEMORY_CHANGELOG="$TEST_CHANGELOG" \
        SHOGUN_MEMORY_PENDING_DECISIONS="$TEST_PENDING" \
        SHOGUN_MEMORY_STAGING_FILE="$TEST_REPO/queue/mcp_sync_staging.yaml" \
        SHOGUN_MEMORY_TRACKER_FILE="$TEST_REPO/queue/mcp_sync_tracker.yaml" \
        bash "$TEST_GATE"
    [ "$status" -eq 2 ]
    [[ "$output" == *"WARN: MCP同期: tracker未作成。1件の未同期"* ]]
}

@test "進行中パイプライン欄の日付が閾値超過 → entry名と経過日数と詳細memory導線をWARN表示" {
    cat > "$TEST_MEMORY_FILE" <<'EOF'
# MEMORY
Last curated: 2099-01-01
参照: memory/deepdive_why_chain_20260321.md

## 進行中パイプライン

- [価格データソース多重化](project_price_data_source_plan.md) — Phase 0待ち(2000-01-01)
EOF

    run env \
        SHOGUN_MEMORY_SCRIPT_DIR="$TEST_REPO" \
        SHOGUN_MEMORY_FILE="$TEST_MEMORY_FILE" \
        SHOGUN_MEMORY_CLAUDE_MD="$TEST_CLAUDE" \
        SHOGUN_MEMORY_CHANGELOG="$TEST_CHANGELOG" \
        SHOGUN_MEMORY_PENDING_DECISIONS="$TEST_PENDING" \
        SHOGUN_MEMORY_PIPELINE_STALE_DAYS=1 \
        bash "$TEST_GATE"
    [ "$status" -eq 2 ]
    [[ "$output" == *"WARN: 進行中パイプライン鮮度: 価格データソース多重化 が"* ]]
    [[ "$output" == *"日前(>1日)"* ]]
    [[ "$output" == *"詳細: project_price_data_source_plan.md"* ]]
    [[ "$output" == *"進行中パイプライン欄と project_price_data_source_plan.md を照合"* ]]
}

@test "進行中パイプライン欄の日付なしentryはスキップし誤発火しない" {
    cat > "$TEST_MEMORY_FILE" <<'EOF'
# MEMORY
Last curated: 2099-01-01
参照: memory/deepdive_why_chain_20260321.md

## 進行中パイプライン

- [日付未記載の案件](project_without_date.md) — 状態確認中
EOF

    run env \
        SHOGUN_MEMORY_SCRIPT_DIR="$TEST_REPO" \
        SHOGUN_MEMORY_FILE="$TEST_MEMORY_FILE" \
        SHOGUN_MEMORY_CLAUDE_MD="$TEST_CLAUDE" \
        SHOGUN_MEMORY_CHANGELOG="$TEST_CHANGELOG" \
        SHOGUN_MEMORY_PENDING_DECISIONS="$TEST_PENDING" \
        SHOGUN_MEMORY_PIPELINE_STALE_DAYS=1 \
        bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: 進行中パイプライン鮮度: stale=0 checked=0 skipped_no_date=1 threshold=1日"* ]]
}

@test "missing referenced file → ALERT exit 1" {
    rm -f "$TEST_TMPDIR/repo/memory/deepdive_why_chain_20260321.md"

    run run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *"ALERT: 参照ファイル不在"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}
