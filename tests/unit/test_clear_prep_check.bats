#!/usr/bin/env bats

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../scripts" && pwd)/clear_prep_check.sh"

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/clear_prep.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/queue" "$TEST_TMPDIR/context" "$TEST_TMPDIR/projects" "$TEST_TMPDIR/logs"
    cp "$SCRIPT" "$TEST_TMPDIR/scripts/clear_prep_check.sh"
    cp "$(dirname "$SCRIPT")/gates/gate_artifact_map.sh" "$TEST_TMPDIR/scripts/gates/gate_artifact_map.sh"
    chmod +x "$TEST_TMPDIR/scripts/clear_prep_check.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_artifact_map.sh"
    touch "$TEST_TMPDIR/queue/pending_decisions.yaml"
    printf '[]\n' > "$TEST_TMPDIR/queue/shogun_to_karo.yaml"
    cat > "$TEST_TMPDIR/dashboard.md" <<'EOF'
## 🚨 要対応

## Other
EOF
    cat > "$TEST_TMPDIR/queue/karo_snapshot.txt" <<'EOF'
idle|none
EOF
}

write_active_session_with_completed_cmd() {
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2026-05-17T09:00:00+09:00","direction":"session_summary","detail":"start"}
{"ts":"2026-05-17T09:05:00+09:00","direction":"inbound","detail":"clear前に強くてニューゲームせよ"}
{"ts":"2026-05-17T09:10:00+09:00","direction":"response","detail":"cmd_999 GATE CLEAR。完了。"}
EOF
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "Check 10 alerts when inbound decision is newer than projects yaml" {
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2026-05-10T09:00:00+09:00","direction":"inbound","detail":"この方針で進めよ"}
EOF
    cat > "$TEST_TMPDIR/projects/infra.yaml" <<'EOF'
project:
  id: infra
EOF
    touch -d '2026-05-10 08:00:00 +0900' "$TEST_TMPDIR/projects/infra.yaml"

    run bash "$TEST_TMPDIR/scripts/clear_prep_check.sh"

    [[ "$output" == *"[10.裁定反映] ALERT: 裁定キーワードinbound=1件"* ]]
    [[ "$output" == *"裁定projects未反映"* ]]
}

@test "Check 10 is OK when there is no inbound decision keyword" {
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2026-05-10T09:00:00+09:00","direction":"inbound","detail":"通常の確認です"}
EOF
    cat > "$TEST_TMPDIR/projects/infra.yaml" <<'EOF'
project:
  id: infra
EOF
    touch -d '2026-05-09 08:00:00 +0900' "$TEST_TMPDIR/projects/infra.yaml"

    run bash "$TEST_TMPDIR/scripts/clear_prep_check.sh"

    [[ "$output" == *"[10.裁定反映] OK: 裁定キーワードinbound=0件"* ]]
    [[ "$output" != *"裁定projects未反映"* ]]
}

@test "Check 5 warns when inbound exists only before latest session_summary" {
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2026-05-09T09:00:00+09:00","direction":"inbound","detail":"old"}
{"ts":"2026-05-09T10:00:00+09:00","direction":"session_summary","detail":"start"}
EOF

    run bash "$TEST_TMPDIR/scripts/clear_prep_check.sh"

    [[ "$output" == *"[5.会話記録] WARN: 殿の発言 inbound=0件(現セッション)"* ]]
    [[ "$output" == *"会話記録現セッションinbound=0"* ]]
}

@test "Check 5 accepts inbound after latest session_summary" {
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2026-05-09T09:00:00+09:00","direction":"inbound","detail":"old"}
{"ts":"2026-05-09T10:00:00+09:00","direction":"session_summary","detail":"start"}
{"ts":"2026-05-09T10:05:00+09:00","direction":"inbound","detail":"current"}
EOF

    run bash "$TEST_TMPDIR/scripts/clear_prep_check.sh"

    [[ "$output" == *"[5.会話記録] OK: 殿の発言 inbound=1件(現セッション)"* ]]
    [[ "$output" != *"会話記録現セッションinbound=0"* ]]
}

@test "Check 8 alerts on 5 pending insights when session has completed cmd" {
    write_active_session_with_completed_cmd
    cat > "$TEST_TMPDIR/queue/insights.yaml" <<'EOF'
insights:
- status: pending
- status: pending
- status: pending
- status: pending
- status: pending
EOF

    run bash "$TEST_TMPDIR/scripts/clear_prep_check.sh"

    [[ "$output" == *"(c)ALERT: セッション中cmd完了1件 + insights未処理5件"* ]]
    [[ "$output" == *"知識埋込み未確認"* ]]
}

@test "Check 8 alerts on stale semantic index when session has completed cmd" {
    write_active_session_with_completed_cmd
    mkdir -p "$TEST_TMPDIR/docs/semantic-index"
    touch -d '2026-05-16 08:00:00 +0900' "$TEST_TMPDIR/docs/semantic-index/index.md"

    run bash "$TEST_TMPDIR/scripts/clear_prep_check.sh"

    [[ "$output" == *"(b)ALERT: セッション中cmd完了1件 + semantic-index当日未更新"* ]]
    [[ "$output" == *"知識埋込み未確認"* ]]
}

@test "Check 8 alerts when cmd_save BLOCK exists and no shogun lesson was written" {
    write_active_session_with_completed_cmd
    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
- cmd_id: "cmd_999"
  gate_result: "BLOCK"
  source: "cmd_save"
  timestamp: "2026-05-17T00:10:00Z"
EOF

    run bash "$TEST_TMPDIR/scripts/clear_prep_check.sh"

    [[ "$output" == *"(a2)cmd_save BLOCK履歴: 1件(2026-05-17以降)"* ]]
    [[ "$output" == *"(a2)ALERT: cmd_save.sh BLOCK履歴あり + lesson_write_shogun.sh実行0件"* ]]
}

@test "Check 7 prints missing artifact file path" {
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2026-05-17T09:00:00+09:00","direction":"session_summary","detail":"start"}
{"ts":"2026-05-17T09:05:00+09:00","direction":"inbound","detail":"current"}
EOF
    cat > "$TEST_TMPDIR/context/l2-okugi-progress.md" <<'EOF'
| # | 忍法 | GS | 選出 | 成果物所在 | 完了日 |
| 1-1 | test | ✅ | — | GS: missing/path.csv | 2026-05-17 |
EOF

    run bash "$TEST_TMPDIR/scripts/clear_prep_check.sh"

    [[ "$output" == *"成果物ファイル不在: missing/path.csv"* ]]
}

@test "Check 11 appends session_summary from inbound lines" {
    write_active_session_with_completed_cmd

    run bash "$TEST_TMPDIR/scripts/clear_prep_check.sh"

    [[ "$output" == *"[11.session_summary] APPENDED: inbound=1"* ]]
    grep -q '"direction": "session_summary"' "$TEST_TMPDIR/queue/lord_conversation.jsonl"
    grep -q 'auto clear prep summary: inbound=1件' "$TEST_TMPDIR/queue/lord_conversation.jsonl"
}
