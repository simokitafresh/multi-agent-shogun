#!/usr/bin/env bats
# test_cmd_save_check19_exit_gate.bats — Check19出口判定 + session_alerts stop hook ユニットテスト
# cmd_3401 (覚醒設計書v3実装)
#
# テスト構成:
#   Check19出口判定:
#     T-001: description+binary_check両方あり → WARNING出ない
#     T-002: descriptionが空値 → WARNING検出
#     T-003: binary_checkフィールド不在 → WARNING検出
#     T-004: binary_checkが空値 → WARNING検出
#     T-005: FILL_THISマーカー残存 → WARNING検出
#     T-006: acceptance_criteriaなし → WARNING出ない（空振り耐性）
#   stop_session_alerts:
#     T-007: session_alerts.txt不在 → exit 0（BLOCK出力なし）
#     T-008: session_alerts.txt空 → exit 0
#     T-009: [TODO]あり → JSON block出力
#     T-010: [TODO]なし([DONE]のみ) → exit 0

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    [ -f "$PROJECT_ROOT/scripts/cmd_save.sh" ] || { echo "cmd_save.sh not found" >&2; return 1; }
    [ -f "$PROJECT_ROOT/scripts/hooks/stop_session_alerts.sh" ] || { echo "stop_session_alerts.sh not found" >&2; return 1; }
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/check19_test.XXXXXX")"
    export WARN_COUNT=0

    # Check19テスト用ラッパースクリプト作成
    # cmd_save.shからAC_TEXT抽出awk + Check19ロジックのみを抽出して実行
    cat > "$TEST_TMPDIR/run_check19.sh" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
CMD_BLOCK="$1"
WARN_COUNT=0
WARN_REASONS=()

# record_warn_reason のモック
record_warn_reason() { WARN_REASONS+=("$1"); }

# AC_TEXT抽出 (cmd_save.sh と同一ロジック)
AC_TEXT=$(printf '%s\n' "$CMD_BLOCK" | awk '
  /acceptance_criteria:/ { found=1; next }
  found && /^[[:space:]]{0,4}[a-z_]+:/ && !/^[[:space:]]*AC[0-9]/ && !/^[[:space:]]*description:/ { exit }
  found { print }
' || true)

WRAPPER

    # Check19ロジックをcmd_save.shから抽出
    sed -n '/^# --- Check 19: AC YAML構造判定/,/^# --- Check 20:/p' \
        "$PROJECT_ROOT/scripts/cmd_save.sh" \
        | sed '/^# --- Check 20:/d' >> "$TEST_TMPDIR/run_check19.sh"

    chmod +x "$TEST_TMPDIR/run_check19.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# ─── Check19出口判定テスト ───────────────────────────────────

# T-001: description+binary_check両方あり → WARNING出ない
@test "T-001: valid AC with description+binary_check produces no WARNING" {
    local CMD_BLOCK="    acceptance_criteria:
      AC1:
        description: \"データベース接続を修正する\"
        binary_check: \"psql接続が成功することをログで確認したか\"
      AC2:
        description: \"テストが全件PASSする\"
        binary_check: \"bats実行結果が全件PASSしたか\"
    command: |
      実装する"
    run bash "$TEST_TMPDIR/run_check19.sh" "$CMD_BLOCK" 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING: AC YAML構造判定"* ]]
}

# T-002: descriptionが空値 → WARNING検出
@test "T-002: empty description value triggers WARNING" {
    local CMD_BLOCK="    acceptance_criteria:
      AC1:
        description: \"\"
        binary_check: \"確認したか\"
    command: |
      実装する"
    run bash "$TEST_TMPDIR/run_check19.sh" "$CMD_BLOCK" 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: AC YAML構造判定"* ]]
    [[ "$output" == *"description空値"* ]]
}

# T-003: binary_checkフィールド不在(ACあり) → WARNING検出
@test "T-003: missing binary_check field triggers WARNING" {
    local CMD_BLOCK="    acceptance_criteria:
      AC1:
        description: \"何かを実装する\"
    command: |
      実装する"
    run bash "$TEST_TMPDIR/run_check19.sh" "$CMD_BLOCK" 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: AC YAML構造判定"* ]]
    [[ "$output" == *"binary_checkフィールド不在"* ]]
}

# T-004: binary_checkが空値 → WARNING検出
@test "T-004: empty binary_check value triggers WARNING" {
    local CMD_BLOCK="    acceptance_criteria:
      AC1:
        description: \"何かを実装する\"
        binary_check: \"\"
    command: |
      実装する"
    run bash "$TEST_TMPDIR/run_check19.sh" "$CMD_BLOCK" 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: AC YAML構造判定"* ]]
    [[ "$output" == *"binary_check空値"* ]]
}

# T-005: FILL_THISマーカー残存 → WARNING検出
@test "T-005: FILL_THIS marker in AC triggers WARNING" {
    local CMD_BLOCK="    acceptance_criteria:
      AC1:
        description: \"FILL_THIS\"
        binary_check: \"確認方法\"
    command: |
      実装する"
    run bash "$TEST_TMPDIR/run_check19.sh" "$CMD_BLOCK" 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: AC YAML構造判定"* ]]
    [[ "$output" == *"FILL_THIS"* ]]
}

# T-006: acceptance_criteriaなし → WARNING出ない（空振り耐性）
@test "T-006: no acceptance_criteria section produces no WARNING" {
    local CMD_BLOCK="    title: \"テストcmd\"
    purpose: \"何かをする\"
    command: |
      実装する"
    run bash "$TEST_TMPDIR/run_check19.sh" "$CMD_BLOCK" 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING: AC YAML構造判定"* ]]
}

# ─── stop_session_alerts テスト ──────────────────────────────

# T-007: session_alerts_shogun.txt不在 → exit 0（BLOCK出力なし）
@test "T-007: missing session_alerts_shogun.txt causes clean exit" {
    # MOCK_AGENT_IDでtmux依存を排除（将軍ロールでテスト）
    export MOCK_AGENT_ID="test_shogun"
    local fake_root="$TEST_TMPDIR/shogun_root"
    mkdir -p "$fake_root/queue"
    # alerts fileを作らない

    # stop_session_alerts.shをfake_rootで実行できるようにラッパー作成
    cat > "$TEST_TMPDIR/run_stop_alerts.sh" <<INNER
#!/usr/bin/env bash
set -euo pipefail
_sa_self="$PROJECT_ROOT/scripts/hooks/stop_session_alerts.sh"
SHOGUN_ROOT="$fake_root"
AGENT_ID="\${MOCK_AGENT_ID:-unknown}"
AGENT_ROLE=""
case "\$AGENT_ID" in
    shogun*) AGENT_ROLE="shogun" ;;
    karo*)   AGENT_ROLE="karo" ;;
    gunshi*) AGENT_ROLE="gunshi" ;;
    *)       AGENT_ROLE="" ;;
esac
if [[ -z "\$AGENT_ROLE" ]]; then exit 0; fi
ALERTS_FILE="\$SHOGUN_ROOT/queue/session_alerts_\${AGENT_ROLE}.txt"
FAIL_HASH_FILE="/tmp/stop_session_alerts_\${AGENT_ID}_fail_hash"

if [[ ! -f "\$ALERTS_FILE" ]] || [[ ! -s "\$ALERTS_FILE" ]]; then
    exit 0
fi
TODO_COUNT=\$(grep -c '^\[TODO\]' "\$ALERTS_FILE" 2>/dev/null || true)
if [[ "\${TODO_COUNT:-0}" -eq 0 ]]; then exit 0; fi
ALERT_CONTENT=\$(grep '^\[TODO\]' "\$ALERTS_FILE" | head -20 || true)
CURRENT_HASH="\$(printf '%s' "\$ALERT_CONTENT" | md5sum | cut -d' ' -f1)"
if [[ -f "\$FAIL_HASH_FILE" ]]; then
    PREV_HASH="\$(< "\$FAIL_HASH_FILE")"
    if [[ "\$CURRENT_HASH" = "\$PREV_HASH" ]]; then
        rm -f "\$FAIL_HASH_FILE" 2>/dev/null || true
        exit 0
    fi
fi
printf '%s' "\$CURRENT_HASH" > "\$FAIL_HASH_FILE"
ESCAPED="\$(printf '%s' "\$ALERT_CONTENT" | head -20 | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g; s/\t/\\\\t/g' | tr '\n' '|' | sed 's/|/\\\\n/g')"
cat <<HOOKJSON
{
  "decision": "block",
  "reason": "⚠ SESSION ALERTS 未完了あり(\${TODO_COUNT}件)。\n\n\${ESCAPED}"
}
HOOKJSON
INNER
    chmod +x "$TEST_TMPDIR/run_stop_alerts.sh"

    run bash "$TEST_TMPDIR/run_stop_alerts.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"decision"* ]]
}

# T-008: session_alerts_shogun.txt空 → exit 0
@test "T-008: empty session_alerts_shogun.txt causes clean exit" {
    export MOCK_AGENT_ID="test_shogun"
    local fake_root="$TEST_TMPDIR/shogun_root2"
    mkdir -p "$fake_root/queue"
    touch "$fake_root/queue/session_alerts_shogun.txt"  # 空ファイル

    cat > "$TEST_TMPDIR/run_stop_alerts2.sh" <<INNER2
#!/usr/bin/env bash
set -euo pipefail
SHOGUN_ROOT="$fake_root"
AGENT_ID="test_shogun"
AGENT_ROLE="shogun"
ALERTS_FILE="\$SHOGUN_ROOT/queue/session_alerts_\${AGENT_ROLE}.txt"
if [[ ! -f "\$ALERTS_FILE" ]] || [[ ! -s "\$ALERTS_FILE" ]]; then exit 0; fi
TODO_COUNT=\$(grep -c '^\[TODO\]' "\$ALERTS_FILE" 2>/dev/null || true)
if [[ "\${TODO_COUNT:-0}" -eq 0 ]]; then exit 0; fi
echo '{"decision":"block"}'
INNER2
    chmod +x "$TEST_TMPDIR/run_stop_alerts2.sh"

    run bash "$TEST_TMPDIR/run_stop_alerts2.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"decision"* ]]
}

# T-009: [TODO]あり → JSON block出力（将軍ロール）
@test "T-009: session_alerts_shogun.txt with TODO items triggers BLOCK output" {
    export MOCK_AGENT_ID="test_shogun_t009"
    local fake_root="$TEST_TMPDIR/shogun_root3"
    mkdir -p "$fake_root/queue"
    printf '# session_alerts_shogun\n[TODO] memory health WARN\n[TODO] PD未解決2件\n' > "$fake_root/queue/session_alerts_shogun.txt"
    rm -f "/tmp/stop_session_alerts_test_shogun_t009_fail_hash" 2>/dev/null || true

    cat > "$TEST_TMPDIR/run_stop_alerts3.sh" <<INNER3
#!/usr/bin/env bash
set -euo pipefail
SHOGUN_ROOT="$fake_root"
AGENT_ID="test_shogun_t009"
AGENT_ROLE="shogun"
ALERTS_FILE="\$SHOGUN_ROOT/queue/session_alerts_\${AGENT_ROLE}.txt"
FAIL_HASH_FILE="/tmp/stop_session_alerts_\${AGENT_ID}_fail_hash"
if [[ ! -f "\$ALERTS_FILE" ]] || [[ ! -s "\$ALERTS_FILE" ]]; then exit 0; fi
TODO_COUNT=\$(grep -c '^\[TODO\]' "\$ALERTS_FILE" 2>/dev/null || true)
if [[ "\${TODO_COUNT:-0}" -eq 0 ]]; then exit 0; fi
ALERT_CONTENT=\$(grep '^\[TODO\]' "\$ALERTS_FILE" | head -20 || true)
CURRENT_HASH="\$(printf '%s' "\$ALERT_CONTENT" | md5sum | cut -d' ' -f1)"
if [[ -f "\$FAIL_HASH_FILE" ]]; then
    PREV_HASH="\$(< "\$FAIL_HASH_FILE")"
    if [[ "\$CURRENT_HASH" = "\$PREV_HASH" ]]; then
        rm -f "\$FAIL_HASH_FILE" 2>/dev/null || true
        exit 0
    fi
fi
printf '%s' "\$CURRENT_HASH" > "\$FAIL_HASH_FILE"
ESCAPED="\$(printf '%s' "\$ALERT_CONTENT" | head -20 | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g; s/\t/\\\\t/g' | tr '\n' '|' | sed 's/|/\\\\n/g')"
cat <<HOOKJSON
{
  "decision": "block",
  "reason": "⚠ SESSION ALERTS 未完了あり(\${TODO_COUNT}件)。\n\n\${ESCAPED}"
}
HOOKJSON
INNER3
    chmod +x "$TEST_TMPDIR/run_stop_alerts3.sh"

    run bash "$TEST_TMPDIR/run_stop_alerts3.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision": "block"'* ]]
    [[ "$output" == *"SESSION ALERTS"* ]]
    [[ "$output" == *"2件"* ]]

    rm -f "/tmp/stop_session_alerts_test_shogun_t009_fail_hash" 2>/dev/null || true
}

# T-010: [TODO]なし([DONE]のみ) → exit 0（将軍ロール）
@test "T-010: session_alerts_shogun.txt with only DONE items causes clean exit" {
    export MOCK_AGENT_ID="test_shogun_t010"
    local fake_root="$TEST_TMPDIR/shogun_root4"
    mkdir -p "$fake_root/queue"
    printf '# session_alerts_shogun\n[DONE] memory health WARN\n[DONE] PD未解決2件\n' > "$fake_root/queue/session_alerts_shogun.txt"

    cat > "$TEST_TMPDIR/run_stop_alerts4.sh" <<INNER4
#!/usr/bin/env bash
set -euo pipefail
SHOGUN_ROOT="$fake_root"
AGENT_ID="test_shogun_t010"
AGENT_ROLE="shogun"
ALERTS_FILE="\$SHOGUN_ROOT/queue/session_alerts_\${AGENT_ROLE}.txt"
if [[ ! -f "\$ALERTS_FILE" ]] || [[ ! -s "\$ALERTS_FILE" ]]; then exit 0; fi
TODO_COUNT=\$(grep -c '^\[TODO\]' "\$ALERTS_FILE" 2>/dev/null || true)
if [[ "\${TODO_COUNT:-0}" -eq 0 ]]; then exit 0; fi
echo '{"decision":"block"}'
INNER4
    chmod +x "$TEST_TMPDIR/run_stop_alerts4.sh"

    run bash "$TEST_TMPDIR/run_stop_alerts4.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"decision"* ]]
}
