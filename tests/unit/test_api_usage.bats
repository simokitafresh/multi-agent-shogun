#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SCRIPT="$PROJECT_ROOT/scripts/api_usage.sh"
    [ -f "$SCRIPT" ] || return 1
    command -v sqlite3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_HOME
    TEST_HOME="$(mktemp -d "$BATS_TMPDIR/api_usage.XXXXXX")"
    export CODEX_DB="$TEST_HOME/.codex/state_5.sqlite"
    mkdir -p "$(dirname "$CODEX_DB")"

    local now
    now="$(date +%s)"

    sqlite3 "$CODEX_DB" <<SQL
CREATE TABLE threads (
  model_provider TEXT,
  updated_at INTEGER,
  tokens_used INTEGER
);
INSERT INTO threads(model_provider, updated_at, tokens_used) VALUES
  ('openai', $((now - 600)), 40),
  ('openai', $((now - 3600)), 30),
  ('openai', $((now - 2 * 86400)), 50),
  ('claude', $((now - 600)), 999);
SQL
}

teardown() {
    rm -rf "$TEST_HOME"
}

@test "openai output reuses shared codex status for remaining budgets" {
    run env \
        HOME="$TEST_HOME" \
        CODEX_DB="$CODEX_DB" \
        CODEX_BUDGET_5H=100 \
        CODEX_BUDGET_7D=200 \
        bash "$SCRIPT" openai

    [ "$status" -eq 0 ]
    [[ "$output" == *"| 5時間 | 70 | 2 |"* ]]
    [[ "$output" == *"| 24時間 | 70 | 2 |"* ]]
    [[ "$output" == *"| 7日間 | 120 | 3 |"* ]]
    # usage_monitor.sh is not available in test/CI, so budget falls back to "--"
    [[ "$output" == *"- **5時間残量**: "* ]]
    [[ "$output" == *"- **7日間残量**: "* ]]
    [[ "$output" == *"- **アクティブセッション** (30分内): 1"* ]]
    [[ "$output" == *"Codex CLI ローカルDB + usage_monitor.sh"* ]]
}

@test "openai output explains sqlite3 preflight failure" {
    # Create a minimal PATH that has bash but NOT sqlite3
    local safe_bin
    safe_bin="$(mktemp -d "$BATS_TMPDIR/nobin.XXXXXX")"
    ln -s "$(command -v bash)" "$safe_bin/bash"
    ln -s "$(command -v env)" "$safe_bin/env" 2>/dev/null || true
    # Add coreutils needed by the script (date, awk, etc.)
    for cmd in date awk cat; do
        local cmd_path
        cmd_path="$(command -v "$cmd" 2>/dev/null)" || true
        [ -n "$cmd_path" ] && ln -s "$cmd_path" "$safe_bin/$cmd" 2>/dev/null || true
    done

    run env \
        PATH="$safe_bin" \
        HOME="$TEST_HOME" \
        CODEX_DB="$CODEX_DB" \
        bash "$SCRIPT" openai

    [ "$status" -eq 0 ]
    [[ "$output" == *"# OpenAI (Codex) Usage"* ]]
    [[ "$output" == *"sqlite3"* ]]

    rm -rf "$safe_bin"
}
