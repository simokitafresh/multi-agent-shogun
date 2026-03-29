#!/usr/bin/env bats
# test_gunshi_notify.bats — cmd_1527: 軍師自動レビュー通知テスト

load '../helpers/cmd_gate_scaffold'

setup_file() {
    cmd_gate_setup_file
    export SRC_NORMALIZE_SCRIPT="$PROJECT_ROOT/scripts/lib/normalize_report.sh"
    [ -f "$SRC_NORMALIZE_SCRIPT" ] || return 1
    export SRC_INBOX_WRITE_SCRIPT="$PROJECT_ROOT/scripts/inbox_write.sh"
    [ -f "$SRC_INBOX_WRITE_SCRIPT" ] || return 1
}

setup() {
    cmd_gate_scaffold "gunshi_notify"
    cp "$SRC_NORMALIZE_SCRIPT" "$TEST_PROJECT/scripts/lib/normalize_report.sh"
    chmod +x "$TEST_PROJECT/scripts/lib/normalize_report.sh"

    # inbox_write.sh stub: 引数をログに記録して成功終了
    cat > "$TEST_PROJECT/scripts/inbox_write.sh" <<'STUBEOF'
#!/usr/bin/env bash
echo "$@" >> "$SCRIPT_DIR/logs/inbox_write_calls.log"
exit 0
STUBEOF
    # SCRIPT_DIR参照を実テストプロジェクトに差し替え
    # inbox_write.shはSCRIPT_DIR不使用→直接書込み
    cat > "$TEST_PROJECT/scripts/inbox_write.sh" <<STUBEOF
#!/usr/bin/env bash
echo "\$@" >> "$TEST_PROJECT/logs/inbox_write_calls.log"
exit 0
STUBEOF
    chmod +x "$TEST_PROJECT/scripts/inbox_write.sh"

    cat > "$TEST_PROJECT/config/projects.yaml" <<EOF
projects:
  - id: infra
    path: $TEST_PROJECT
EOF

    cat > "$TEST_PROJECT/tasks/lessons.md" <<'EOF'
# Lessons
- **status**: confirmed
EOF

    cat > "$TEST_PROJECT/queue/inbox/karo.yaml" <<'EOF'
messages:
  - id: msg_test
    read: false
EOF
}

teardown() {
    cmd_gate_teardown
}

write_cmd_yaml() {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<EOF
commands:
  - id: $TEST_CMD_ID
    purpose: "gunshi notify test"
    project: infra
    status: delegated
    delegated_at: "2026-03-04T21:25:00"
EOF
}

write_task_yaml() {
    local ninja="$1"
    cat > "$TEST_PROJECT/queue/tasks/${ninja}.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: impl
  report_filename: ${ninja}_report_${TEST_CMD_ID}.yaml
  ac_version: 1
  related_lessons: []
EOF
}

write_report() {
    local ninja="$1"
    local status="${2:-completed}"
    cat > "$TEST_PROJECT/queue/reports/${ninja}_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: $ninja
task_id: ${TEST_CMD_ID}_impl
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-30T00:00:00"
status: $status
ac_version_read: 1
verdict: PASS
purpose_validation:
  fit: true
lesson_candidate:
  found: false
  no_lesson_reason: "test"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
EOF
}

@test "completed report triggers gunshi notification" {
    write_cmd_yaml
    write_task_yaml "sasuke"
    write_report "sasuke" "completed"

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"

    # inbox_write呼び出しログ確認
    [ -f "$TEST_PROJECT/logs/inbox_write_calls.log" ]
    grep -q "gunshi" "$TEST_PROJECT/logs/inbox_write_calls.log"
    grep -q "report_review" "$TEST_PROJECT/logs/inbox_write_calls.log"
    grep -q "sasuke" "$TEST_PROJECT/logs/inbox_write_calls.log"

    # フラグファイル作成確認
    [ -f "$TEST_PROJECT/queue/gates/${TEST_CMD_ID}/gunshi_notify_sasuke.done" ]

    # 出力確認
    [[ "$output" == *"gunshi_notify: SENT"* ]]
}

@test "training cmd skips gunshi notification" {
    local TRAIN_CMD_ID="cmd_training_structural_001"
    mkdir -p "$TEST_PROJECT/queue/gates/$TRAIN_CMD_ID"
    cat > "$TEST_PROJECT/queue/gates/$TRAIN_CMD_ID/archive.done" <<'EOF'
timestamp: 2026-03-04T00:00:00
source: test
EOF
    cat > "$TEST_PROJECT/queue/gates/$TRAIN_CMD_ID/lesson.done" <<'EOF'
timestamp: 2026-03-04T00:00:00
source: test
EOF

    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<EOF
commands:
  - id: $TRAIN_CMD_ID
    purpose: "training test"
    project: infra
    status: delegated
    delegated_at: "2026-03-04T21:25:00"
EOF

    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<EOF
task:
  parent_cmd: $TRAIN_CMD_ID
  task_type: impl
  report_filename: hayate_report_${TRAIN_CMD_ID}.yaml
  ac_version: 1
  related_lessons: []
EOF

    cat > "$TEST_PROJECT/queue/reports/hayate_report_${TRAIN_CMD_ID}.yaml" <<EOF
worker_id: hayate
task_id: ${TRAIN_CMD_ID}_impl
parent_cmd: $TRAIN_CMD_ID
timestamp: "2026-03-30T00:00:00"
status: completed
ac_version_read: 1
verdict: PASS
purpose_validation:
  fit: true
lesson_candidate:
  found: false
  no_lesson_reason: "test"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
EOF

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TRAIN_CMD_ID"

    # gunshi通知がスキップされたことを確認
    [[ "$output" == *"gunshi_notify: SKIP (training cmd:"* ]]

    # inbox_writeが呼ばれていないことを確認
    if [ -f "$TEST_PROJECT/logs/inbox_write_calls.log" ]; then
        ! grep -q "gunshi.*report_review" "$TEST_PROJECT/logs/inbox_write_calls.log"
    fi
}

@test "duplicate notification prevented by flag file" {
    write_cmd_yaml
    write_task_yaml "sasuke"
    write_report "sasuke" "completed"

    # 1回目: 通知送信
    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [[ "$output" == *"gunshi_notify: SENT"* ]]

    # ログをクリア
    > "$TEST_PROJECT/logs/inbox_write_calls.log"

    # 2回目: フラグ存在で重複通知なし（--forceで再検査）
    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID" --force
    # 2回目はSENTが出ない（フラグで抑制）
    ! [[ "$output" == *"gunshi_notify: SENT"* ]]
}
