#!/usr/bin/env bats

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../scripts" && pwd)/clear_prep_check.sh"

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/clear_prep.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue" "$TEST_TMPDIR/context" "$TEST_TMPDIR/projects"
    cp "$SCRIPT" "$TEST_TMPDIR/scripts/clear_prep_check.sh"
    chmod +x "$TEST_TMPDIR/scripts/clear_prep_check.sh"
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
