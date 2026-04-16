#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SOURCE_SCRIPT="$PROJECT_ROOT/scripts/lord_topic_index.py"
    [ -f "$SOURCE_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/lord_topic_index.XXXXXX")"
    mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/logs/lord_conversation_archive"

    cp "$SOURCE_SCRIPT" "$TEST_ROOT/scripts/lord_topic_index.py"
    chmod +x "$TEST_ROOT/scripts/lord_topic_index.py"
    export TEST_SCRIPT="$TEST_ROOT/scripts/lord_topic_index.py"
}

teardown() {
    [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"
}

@test "extracts frequent topics from inbound summaries only" {
    cat > "$TEST_ROOT/logs/lord_conversation_archive/2026-04-14.jsonl" <<'EOF'
{"direction":"inbound","summary":"研究日誌 Android TRF を確認せよ"}
{"direction":"inbound","summary":"研究日誌 Android をもう一度確認せよ"}
{"direction":"inbound","summary":"研究日誌 と TRF の差分を説明せよ"}
{"direction":"outbound","summary":"研究日誌 は把握した"}
EOF

    run python3 "$TEST_SCRIPT" --archive-dir "$TEST_ROOT/logs/lord_conversation_archive" --top 5
    [ "$status" -eq 0 ]
    [[ "$output" == *"会話トピック索引: inbound要約3件 / 1日"* ]]
    [[ "$output" == *"研究日誌 (3)"* ]]
    [[ "$output" == *"Android (2)"* ]]
    [[ "$output" == *"TRF (2)"* ]]
}

@test "missing archive directory returns INFO without failure" {
    run python3 "$TEST_SCRIPT" --archive-dir "$TEST_ROOT/logs/not_found" --top 5
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: lord_conversation_archiveディレクトリ不在"* ]]
}
