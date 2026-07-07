#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export API_USAGE_SCRIPT="$PROJECT_ROOT/scripts/api_usage.sh"
    export TEST_DIR
    TEST_DIR="$(mktemp -d "$BATS_TMPDIR/usage_status.XXXXXX")"
    cp "$PROJECT_ROOT/scripts/usage_status.sh" "$TEST_DIR/usage_status.sh"
    chmod +x "$TEST_DIR/usage_status.sh"
    export MCAS_STATUS_INTERVAL=0
    export MCAS_CACHE_DIR="$TEST_DIR"
    rm -f "$TEST_DIR/mcas_usage_status_cache_claude" "$TEST_DIR/mcas_usage_status_cache_codex"
}

teardown() {
    rm -rf "$TEST_DIR"
}

write_monitor() {
    local body="$1"
    cat > "$TEST_DIR/usage_monitor.sh" <<EOF
#!/usr/bin/env bash
$body
EOF
    chmod +x "$TEST_DIR/usage_monitor.sh"
}

@test "malformed non-empty status does not overwrite valid cache" {
    echo "5H:██░░░ 40% 10am 7D:█░░░░ 20% Fri" > $TEST_DIR/mcas_usage_status_cache_claude
    write_monitor 'printf "oops\n"'

    run bash "$TEST_DIR/usage_status.sh" claude

    [ "$status" -eq 0 ]
    [ "$output" = "5H:██░░░ 40% 10am 7D:█░░░░ 20% Fri" ]
    [ "$(cat $TEST_DIR/mcas_usage_status_cache_claude)" = "5H:██░░░ 40% 10am 7D:█░░░░ 20% Fri" ]
}

@test "malformed status without cache returns provider-specific fallback" {
    write_monitor 'printf "12\tsoon\tbad\n"'

    run bash "$TEST_DIR/usage_status.sh" codex

    [ "$status" -eq 0 ]
    [ "$output" = "5H:----- --% left -- 7D:----- --% left --" ]
    [ ! -f $TEST_DIR/mcas_usage_status_cache_codex ]
}

@test "valid status writes formatted cache" {
    write_monitor 'printf "12\t10am\t34\tFri\n"'

    run bash "$TEST_DIR/usage_status.sh" claude

    [ "$status" -eq 0 ]
    [[ "$output" == "5H:"*" 12% 10am 7D:"*" 34% Fri" ]]
    [ "$(cat $TEST_DIR/mcas_usage_status_cache_claude)" = "$output" ]
}

@test "openai output reuses shared codex status for remaining budgets" {
    # cmd_3719: sqlite3 CLI依存除去に伴い、CLIをスタブ化する旧実装ではなく
    # python3のsqlite3モジュールで実DBを作成してテストする(実データ経路の回帰確認)。
    mkdir -p "$TEST_DIR/home/.codex"
    local now h5_ago_row d1_only_row d7_only_row
    now=$(date +%s)
    h5_ago_row=$((now - 600))       # 10分前: h5/d1/d7/active 全てに算入
    d1_only_row=$((now - 7200))     # 2時間前: h5/d1/d7に算入、activeには非算入
    d7_only_row=$((now - 3 * 86400)) # 3日前: d7のみに算入
    python3 - "$TEST_DIR/home/.codex/state_5.sqlite" "$h5_ago_row" "$d1_only_row" "$d7_only_row" <<'PY'
import sqlite3, sys
db_path, r1, r2, r3 = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
con = sqlite3.connect(db_path)
con.execute("CREATE TABLE threads (updated_at INTEGER, tokens_used INTEGER, model_provider TEXT)")
con.executemany(
    "INSERT INTO threads(updated_at, tokens_used, model_provider) VALUES (?, ?, 'openai')",
    [(r1, 40), (r2, 30), (r3, 50)],
)
con.commit()
con.close()
PY

    run env \
        HOME="$TEST_DIR/home" \
        TEST_DIR="$TEST_DIR" \
        CODEX_BUDGET_5H=100 \
        CODEX_BUDGET_7D=200 \
        bash "$API_USAGE_SCRIPT" openai

    [ "$status" -eq 0 ]
    [[ "$output" == *"| 5時間 | 70 | 2 |"* ]]
    [[ "$output" == *"| 24時間 | 70 | 2 |"* ]]
    [[ "$output" == *"| 7日間 | 120 | 3 |"* ]]
    [[ "$output" == *"- **5時間残量**: "* ]]
    [[ "$output" == *"- **7日間残量**: "* ]]
    [[ "$output" == *"- **アクティブセッション** (30分内): 1"* ]]
    [[ "$output" == *"Codex CLI ローカルDB + usage_monitor.sh"* ]]
}

@test "openai output explains missing codex data file" {
    # cmd_3719: sqlite3 CLI不在の前提チェックは廃止(python3のsqlite3モジュールに一本化)。
    # 残る graceful-degradation経路はCodexデータファイル自体が存在しないケース。
    run env \
        HOME="$TEST_DIR" \
        bash "$API_USAGE_SCRIPT" openai

    [ "$status" -eq 0 ]
    [[ "$output" == *"# OpenAI (Codex) Usage"* ]]
    [[ "$output" == *"Codex CLIデータが見つかりません"* ]]
}

@test "openai output explains malformed codex data file (not silent zero)" {
    # cmd_3719: threadsテーブル不在などのクエリ失敗時は無言の0扱いにせず明示エラーにする。
    mkdir -p "$TEST_DIR/home/.codex"
    : > "$TEST_DIR/home/.codex/state_5.sqlite"

    run env \
        HOME="$TEST_DIR/home" \
        bash "$API_USAGE_SCRIPT" openai

    [ "$status" -eq 0 ]
    [[ "$output" == *"# OpenAI (Codex) Usage"* ]]
    [[ "$output" == *"データ取得に失敗しました"* ]]
    [[ "$output" != *"| 5時間 | 0 | 0 |"* ]]
}
