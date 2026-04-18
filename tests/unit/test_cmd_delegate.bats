#!/usr/bin/env bats
# test_cmd_delegate.bats — cmd_delegate.sh + gate_cmd_state.sh ユニットテスト

# --- セットアップ ---

setup() {
    TEST_TMP="$(mktemp -d)"
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

    # テスト用ディレクトリ構造
    mkdir -p "${TEST_TMP}/queue/inbox"
    mkdir -p "${TEST_TMP}/scripts/lib"
    mkdir -p "${TEST_TMP}/scripts/gates"

    # yaml_field_set.sh をコピー
    cp "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "${TEST_TMP}/scripts/lib/"

    # cmd_save.sh のモック（成功する版）
    cat > "${TEST_TMP}/scripts/cmd_save.sh" << 'MOCK'
#!/bin/bash
echo "CMD_SAVE_CALLED: $1" >> "${TEST_TMP}/cmd_save_calls.log"
exit 0
MOCK
    chmod +x "${TEST_TMP}/scripts/cmd_save.sh"

    # cmd_save.sh のモック（失敗する版）
    cat > "${TEST_TMP}/scripts/cmd_save_fail.sh" << 'MOCK'
#!/bin/bash
echo "CMD_SAVE_CALLED: $1" >> "${TEST_TMP}/cmd_save_calls.log"
echo "BLOCK: mock cmd_save failure for $1" >&2
exit 1
MOCK
    chmod +x "${TEST_TMP}/scripts/cmd_save_fail.sh"

    # inbox_write.sh のモック（成功する版）
    cat > "${TEST_TMP}/scripts/inbox_write.sh" << 'MOCK'
#!/bin/bash
# Mock inbox_write.sh — メッセージをファイルに記録するだけ
echo "INBOX_CALLED: $*" >> "${TEST_TMP}/inbox_calls.log"
# karo inbox にエントリを追加（証跡チェック用）
mkdir -p "$(dirname "$0")/../queue/inbox"
INBOX="$(dirname "$0")/../queue/inbox/${1}.yaml"
if [ ! -f "$INBOX" ]; then
    echo "messages: []" > "$INBOX"
fi
cat >> "$INBOX" << EOF
  - id: mock_msg
    content: "$2"
    type: "$3"
    from: "$4"
    read: false
EOF
exit 0
MOCK
    chmod +x "${TEST_TMP}/scripts/inbox_write.sh"

    # inbox_write.sh のモック（失敗する版）
    cat > "${TEST_TMP}/scripts/inbox_write_fail.sh" << 'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "${TEST_TMP}/scripts/inbox_write_fail.sh"

    # cmd_delegate.sh をコピー（パスは環境変数オーバーライドで切り替える）
    cp "$PROJECT_ROOT/scripts/cmd_delegate.sh" "${TEST_TMP}/scripts/cmd_delegate.sh"
    chmod +x "${TEST_TMP}/scripts/cmd_delegate.sh"

    # gate_cmd_state.sh をコピーし、パスを調整
    sed "s|SCRIPT_DIR=\"\$(cd \"\$(dirname \"\$0\")/../..\" && pwd)\"|SCRIPT_DIR=\"${TEST_TMP}\"|" \
        "$PROJECT_ROOT/scripts/gates/gate_cmd_state.sh" \
        > "${TEST_TMP}/scripts/gates/gate_cmd_state.sh"
    chmod +x "${TEST_TMP}/scripts/gates/gate_cmd_state.sh"

    export TEST_TMP
    export INBOX_WRITE_TEST=1
    export CMD_DELEGATE_SCRIPT_DIR="${TEST_TMP}/scripts"
    export CMD_DELEGATE_PROJECT_DIR="${TEST_TMP}"
}

teardown() {
    rm -rf "$TEST_TMP"
}

# --- ヘルパー ---

create_shogun_yaml_with_pending() {
    cat > "${TEST_TMP}/queue/shogun_to_karo.yaml" << 'YAML'
commands:
  - id: cmd_100
    timestamp: "2026-03-04T10:00:00"
    title: "Test command"
    project: infra
    type: implement
    priority: high
    status: pending
    purpose: "Test purpose"
YAML
}

create_shogun_yaml_with_delegated() {
    cat > "${TEST_TMP}/queue/shogun_to_karo.yaml" << 'YAML'
commands:
  - id: cmd_100
    timestamp: "2026-03-04T10:00:00"
    title: "Test command"
    project: infra
    type: implement
    priority: high
    status: pending
    delegated_at: "2026-03-04T10:05:00"
    purpose: "Test purpose"
YAML
}

create_shogun_yaml_with_done() {
    cat > "${TEST_TMP}/queue/shogun_to_karo.yaml" << 'YAML'
commands:
  - id: cmd_100
    timestamp: "2026-03-04T10:00:00"
    title: "Test command"
    project: infra
    type: implement
    priority: high
    status: done
    purpose: "Test purpose"
YAML
}

create_shogun_yaml_multiple_pending() {
    cat > "${TEST_TMP}/queue/shogun_to_karo.yaml" << 'YAML'
commands:
  - id: cmd_100
    timestamp: "2026-03-04T10:00:00"
    title: "First command"
    project: infra
    type: implement
    priority: high
    status: pending
    delegated_at: "2026-03-04T10:05:00"
    purpose: "First purpose"
  - id: cmd_101
    timestamp: "2026-03-04T11:00:00"
    title: "Second command"
    project: infra
    type: implement
    priority: high
    status: pending
    purpose: "Second purpose"
YAML
}

# cmd_100: stuck (status=pending + delegated_at), cmd_101: new (status=pending, no delegated_at)
create_shogun_yaml_with_stuck_cmd() {
    cat > "${TEST_TMP}/queue/shogun_to_karo.yaml" << 'YAML'
commands:
  - id: cmd_100
    timestamp: "2026-03-04T10:00:00"
    title: "Stuck command"
    project: infra
    type: implement
    priority: high
    status: pending
    delegated_at: "2026-03-04T10:05:00"
    purpose: "Stuck purpose"
  - id: cmd_101
    timestamp: "2026-03-04T11:00:00"
    title: "New command"
    project: infra
    type: implement
    priority: high
    status: pending
    purpose: "New purpose"
YAML
}

# cmd_100: properly delegated (status=delegated), cmd_101: new (status=pending, no delegated_at)
create_shogun_yaml_all_delegated() {
    cat > "${TEST_TMP}/queue/shogun_to_karo.yaml" << 'YAML'
commands:
  - id: cmd_100
    timestamp: "2026-03-04T10:00:00"
    title: "Delegated command"
    project: infra
    type: implement
    priority: high
    status: delegated
    delegated_at: "2026-03-04T10:05:00"
    purpose: "Delegated purpose"
  - id: cmd_101
    timestamp: "2026-03-04T11:00:00"
    title: "New command"
    project: infra
    type: implement
    priority: high
    status: pending
    purpose: "New purpose"
YAML
}

# ============================================================
# cmd_delegate.sh テスト
# ============================================================

@test "cmd_delegate: 正常委任 — inbox + delegated_at設定" {
    create_shogun_yaml_with_pending

    run bash "${TEST_TMP}/scripts/cmd_delegate.sh" cmd_100 "cmd_100を書いた。配備せよ。"
    echo "output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DELEGATED: cmd_100 at"* ]]

    # delegated_at が設定されていることを確認
    run grep "delegated_at" "${TEST_TMP}/queue/shogun_to_karo.yaml"
    [ "$status" -eq 0 ]

    # cmd_save.sh が先に呼ばれたことを確認
    run cat "${TEST_TMP}/cmd_save_calls.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CMD_SAVE_CALLED: cmd_100"* ]]

    # inbox_write が呼ばれたことを確認
    run cat "${TEST_TMP}/inbox_calls.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"karo"* ]]
    [[ "$output" == *"cmd_new"* ]]
    [[ "$output" == *"shogun"* ]]
}

@test "cmd_delegate: 冪等性 — 二重実行でALREADY_DELEGATED" {
    create_shogun_yaml_with_delegated

    run bash "${TEST_TMP}/scripts/cmd_delegate.sh" cmd_100 "cmd_100を書いた。配備せよ。"
    echo "output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALREADY_DELEGATED: cmd_100 at 2026-03-04T10:05:00"* ]]

    # inbox_write は呼ばれないことを確認
    [ ! -f "${TEST_TMP}/inbox_calls.log" ]
    [ ! -f "${TEST_TMP}/cmd_save_calls.log" ]
}

@test "cmd_delegate: cmd_id未発見でエラー" {
    create_shogun_yaml_with_pending

    run bash "${TEST_TMP}/scripts/cmd_delegate.sh" cmd_999 "存在しないcmd"
    echo "output: $output"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"cmd_999"* ]]
}

@test "cmd_delegate: status!=pendingでエラー" {
    create_shogun_yaml_with_done

    run bash "${TEST_TMP}/scripts/cmd_delegate.sh" cmd_100 "完了済みcmdに委任"
    echo "output: $output"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"done"* ]]
}

@test "cmd_delegate: 引数不足でエラー" {
    run bash "${TEST_TMP}/scripts/cmd_delegate.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]

    run bash "${TEST_TMP}/scripts/cmd_delegate.sh" cmd_100
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "cmd_delegate: 異常系 — 未配備cmd(pending+delegated_at)検出でWARNING出力" {
    create_shogun_yaml_with_stuck_cmd

    run bash "${TEST_TMP}/scripts/cmd_delegate.sh" cmd_101 "cmd_101を書いた。配備せよ。"
    echo "output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DELEGATED: cmd_101 at"* ]]
    # cmd_100 (pending+delegated_at) についてWARNINGが出力されること
    [[ "$output" == *"WARN: 委任済みだが未配備のcmdを検出"* ]]
    [[ "$output" == *"cmd_100"* ]]
}

@test "cmd_delegate: 正常系 — 全cmd配備済み(status=delegated)でWARNINGなし" {
    create_shogun_yaml_all_delegated

    run bash "${TEST_TMP}/scripts/cmd_delegate.sh" cmd_101 "cmd_101を書いた。配備せよ。"
    echo "output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DELEGATED: cmd_101 at"* ]]
    # cmd_100 は status=delegated のためWARNING不要
    [[ "$output" != *"WARN: 委任済みだが未配備のcmdを検出"* ]]
}

@test "cmd_delegate: inbox_write失敗時エラー" {
    create_shogun_yaml_with_pending

    # 失敗版inbox_writeに差し替え
    cp "${TEST_TMP}/scripts/inbox_write_fail.sh" "${TEST_TMP}/scripts/inbox_write.sh"

    run bash "${TEST_TMP}/scripts/cmd_delegate.sh" cmd_100 "失敗するinbox"
    echo "output: $output"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"inbox_write"* ]]

    # cmd_new guardを通した事実は保持し、手動再送可能な状態を維持する
    run grep "delegated_at" "${TEST_TMP}/queue/shogun_to_karo.yaml"
    [ "$status" -eq 0 ]
    run grep "status: delegated" "${TEST_TMP}/queue/shogun_to_karo.yaml"
    [ "$status" -eq 0 ]
}

@test "cmd_delegate: cmd_save.sh BLOCK時は委任中止" {
    create_shogun_yaml_with_pending

    cp "${TEST_TMP}/scripts/cmd_save_fail.sh" "${TEST_TMP}/scripts/cmd_save.sh"

    run bash "${TEST_TMP}/scripts/cmd_delegate.sh" cmd_100 "保存失敗"
    echo "output: $output"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: mock cmd_save failure for cmd_100"* ]]
    [[ "$output" == *"GATE未通過。修正してからcmd_save.sh→inbox_writeを手動実行せよ"* ]]

    # inbox_write は呼ばれず、delegated_at も設定されない
    [ ! -f "${TEST_TMP}/inbox_calls.log" ]
    run grep "delegated_at" "${TEST_TMP}/queue/shogun_to_karo.yaml"
    [ "$status" -ne 0 ]
}

# ============================================================
# gate_cmd_state.sh テスト
# ============================================================

@test "gate_cmd_state: OK — delegated_at設定済み" {
    create_shogun_yaml_with_delegated

    run bash "${TEST_TMP}/scripts/gates/gate_cmd_state.sh"
    echo "output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: cmd_100"* ]]
    [[ "$output" == *"委任済み"* ]]
    [[ "$output" == *"総合判定: OK"* ]]
}

@test "gate_cmd_state: WARN — delegated_atなし+inbox証跡あり" {
    create_shogun_yaml_with_pending

    # karo inbox に cmd_100 の証跡を作成
    cat > "${TEST_TMP}/queue/inbox/karo.yaml" << 'YAML'
messages:
  - id: msg_001
    content: "cmd_100を書いた"
    type: cmd_new
    from: shogun
    read: true
YAML

    run bash "${TEST_TMP}/scripts/gates/gate_cmd_state.sh"
    echo "output: $output"
    [ "$status" -eq 2 ]
    [[ "$output" == *"WARN: cmd_100"* ]]
    [[ "$output" == *"二次証跡あり"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "gate_cmd_state: WARN — delegated_atなし+dashboard証跡あり" {
    create_shogun_yaml_with_pending

    # dashboard に cmd_100 の証跡を作成
    echo "# Dashboard" > "${TEST_TMP}/dashboard.md"
    echo "cmd_100: 進行中" >> "${TEST_TMP}/dashboard.md"

    run bash "${TEST_TMP}/scripts/gates/gate_cmd_state.sh"
    echo "output: $output"
    [ "$status" -eq 2 ]
    [[ "$output" == *"WARN: cmd_100"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "gate_cmd_state: WARN — delegated_atなし+snapshot証跡あり" {
    create_shogun_yaml_with_pending

    # snapshot に cmd_100 の証跡を作成
    echo "ninja|sasuke|cmd_100|in_progress|infra" > "${TEST_TMP}/queue/karo_snapshot.txt"

    run bash "${TEST_TMP}/scripts/gates/gate_cmd_state.sh"
    echo "output: $output"
    [ "$status" -eq 2 ]
    [[ "$output" == *"WARN: cmd_100"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "gate_cmd_state: ALERT — delegated_atなし+証跡なし" {
    create_shogun_yaml_with_pending
    # 証跡ファイルなし

    run bash "${TEST_TMP}/scripts/gates/gate_cmd_state.sh"
    echo "output: $output"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ALERT: cmd_100"* ]]
    [[ "$output" == *"未委任の可能性"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "gate_cmd_state: pending cmdなし → OK" {
    create_shogun_yaml_with_done

    run bash "${TEST_TMP}/scripts/gates/gate_cmd_state.sh"
    echo "output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pending cmd なし"* ]]
    [[ "$output" == *"総合判定: OK"* ]]
}

@test "gate_cmd_state: 複数cmd — OK+ALERT混在" {
    create_shogun_yaml_multiple_pending
    # cmd_100はdelegated_at済み、cmd_101はなし+証跡なし

    run bash "${TEST_TMP}/scripts/gates/gate_cmd_state.sh"
    echo "output: $output"
    [ "$status" -eq 1 ]
    [[ "$output" == *"OK: cmd_100"* ]]
    [[ "$output" == *"ALERT: cmd_101"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "gate_cmd_state: 後方互換 — shogun_to_karo.yaml未存在 → OK" {
    # ファイルなし
    run bash "${TEST_TMP}/scripts/gates/gate_cmd_state.sh"
    echo "output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"総合判定: OK"* ]]
}

# ============================================================
# 統合テスト: delegate → gate
# ============================================================

@test "統合: delegate実行後、gateでOK判定" {
    create_shogun_yaml_with_pending

    # 委任実行
    run bash "${TEST_TMP}/scripts/cmd_delegate.sh" cmd_100 "cmd_100を書いた。配備せよ。"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DELEGATED"* ]]

    # ゲートチェック
    run bash "${TEST_TMP}/scripts/gates/gate_cmd_state.sh"
    echo "output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: pending cmd なし"* ]]
}
