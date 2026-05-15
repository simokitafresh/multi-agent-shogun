#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_WRITE="$PROJECT_ROOT/scripts/bulletin_write.sh"
    export SRC_CONFIRM="$PROJECT_ROOT/scripts/bulletin_confirm.sh"
    export SRC_CLOSE="$PROJECT_ROOT/scripts/bulletin_close.sh"
    export SRC_AGENT_CONFIG="$PROJECT_ROOT/scripts/lib/agent_config.sh"
    [ -f "$SRC_WRITE" ] || return 1
    [ -f "$SRC_CONFIRM" ] || return 1
    [ -f "$SRC_CLOSE" ] || return 1
    [ -f "$SRC_AGENT_CONFIG" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/bulletin.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/lib" "$TEST_TMPDIR/scripts/bin" "$TEST_TMPDIR/queue" "$TEST_TMPDIR/config"
    cp "$SRC_WRITE" "$TEST_TMPDIR/scripts/bulletin_write.sh"
    cp "$SRC_CONFIRM" "$TEST_TMPDIR/scripts/bulletin_confirm.sh"
    cp "$SRC_CLOSE" "$TEST_TMPDIR/scripts/bulletin_close.sh"
    cp "$SRC_AGENT_CONFIG" "$TEST_TMPDIR/scripts/lib/agent_config.sh"
    cat > "$TEST_TMPDIR/scripts/inbox_write.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "${INBOX_WRITE_LOG:?}"
EOF
    chmod +x "$TEST_TMPDIR/scripts/bulletin_write.sh" "$TEST_TMPDIR/scripts/bulletin_confirm.sh" "$TEST_TMPDIR/scripts/bulletin_close.sh" "$TEST_TMPDIR/scripts/inbox_write.sh"
    cat > "$TEST_TMPDIR/scripts/bin/tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${BULLETIN_TEST_AGENT_ID:-hayate}"
EOF
    chmod +x "$TEST_TMPDIR/scripts/bin/tmux"
    cat > "$TEST_TMPDIR/scripts/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$TEST_TMPDIR/scripts/bin/pgrep"
    export PATH="$TEST_TMPDIR/scripts/bin:$PATH"
    export TMUX_PANE="%999"
    cat > "$TEST_TMPDIR/config/settings.yaml" <<'YAML'
cli:
  agents:
    gunshi:
      role: gunshi
      japanese_name: 軍師
    saizo:
      role: ninja
      japanese_name: 才蔵
YAML
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "bulletin_write adds entry to bulletin YAML" {
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "共有連絡"
    [ "$status" -eq 0 ]
    [[ "$output" == blt_* ]]
    run cat "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"content: |-"* ]]
    [[ "$output" == *"共有連絡"* ]]
    [[ "$output" == *"posted_by: 'saizo'"* ]]
    [[ "$output" == *"confirmed_by: []"* ]]
}

@test "bulletin_write accepts explicit posted_by from shared agent config" {
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=hayate TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" saizo "名義指定"
    [ "$status" -eq 0 ]
    run cat "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"posted_by: 'saizo'"* ]]
    [[ "$output" == *"名義指定"* ]]
}

@test "bulletin_write accepts explicit posted_by without tmux agent_id" {
    run env -u TMUX_PANE BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" PATH="/usr/bin:/bin" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" saizo "tmuxなし名義指定"
    [ "$status" -eq 0 ]
    run cat "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"posted_by: 'saizo'"* ]]
    [[ "$output" == *"tmuxなし名義指定"* ]]
}

@test "bulletin_write trims BULLETIN_NOTIFY targets before notifying" {
    export INBOX_WRITE_LOG="$TEST_TMPDIR/inbox_write.log"
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo BULLETIN_NOTIFY="shogun, gunshi" TMUX_PANE="$TMUX_PANE" PATH="$PATH" INBOX_WRITE_LOG="$INBOX_WRITE_LOG" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "通知確認"
    [ "$status" -eq 0 ]
    run cat "$INBOX_WRITE_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"shogun|掲示板新規投稿("* ]]
    [[ "$output" == *"gunshi|掲示板新規投稿("* ]]
}

@test "bulletin_write prints entry id before watcher warning when watcher is absent" {
    export INBOX_WRITE_LOG="$TEST_TMPDIR/inbox_write.log"
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo BULLETIN_NOTIFY="shogun" TMUX_PANE="$TMUX_PANE" PATH="$PATH" INBOX_WRITE_LOG="$INBOX_WRITE_LOG" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "watcher不在"
    [ "$status" -eq 0 ]
    [[ "$output" == blt_* ]]
    [[ "$output" == *"[bulletin_write] WARN: inbox_watcher not running for shogun"* ]]
}

@test "bulletin_write rejects unknown requires_confirmation agents" {
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "確認先不正" "shogun, unknown_agent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown requires_confirmation agent"* ]]
    [ ! -f "$TEST_TMPDIR/queue/bulletin_board.yaml" ]
}

@test "bulletin_write rejects unknown single requires_confirmation agent" {
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "確認先不正" "unknown_agent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown requires_confirmation agent"* ]]
    [ ! -f "$TEST_TMPDIR/queue/bulletin_board.yaml" ]
}

@test "bulletin_write rejects misspelled explicit posted_by instead of writing malformed entry" {
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=hayate TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" saizoo "名義指定"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown requires_confirmation agent"* ]]
    [ ! -f "$TEST_TMPDIR/queue/bulletin_board.yaml" ]
}

@test "bulletin_write duplicate post does not notify again" {
    export INBOX_WRITE_LOG="$TEST_TMPDIR/inbox_write.log"
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo BULLETIN_NOTIFY="shogun,gunshi" TMUX_PANE="$TMUX_PANE" PATH="$PATH" INBOX_WRITE_LOG="$INBOX_WRITE_LOG" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "重複禁止"
    [ "$status" -eq 0 ]

    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo BULLETIN_NOTIFY="shogun,gunshi" TMUX_PANE="$TMUX_PANE" PATH="$PATH" INBOX_WRITE_LOG="$INBOX_WRITE_LOG" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "重複禁止"
    [ "$status" -eq 0 ]
    [[ "$output" == DEDUP:* ]]

    run wc -l "$INBOX_WRITE_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" == "2 $INBOX_WRITE_LOG" ]]
}

@test "bulletin_write warns when inbox_write fails" {
    cat > "$TEST_TMPDIR/scripts/inbox_write.sh" <<'EOF'
#!/usr/bin/env bash
exit 42
EOF
    chmod +x "$TEST_TMPDIR/scripts/inbox_write.sh"

    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo BULLETIN_NOTIFY="shogun" TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "通知失敗"
    [ "$status" -eq 0 ]
    [[ "$output" == blt_* ]]
    [[ "$output" == *"WARN: inbox_write failed for shogun"* ]]
    [[ "$output" != *"inbox_watcher not running for shogun"* ]]
}

@test "bulletin_confirm adds agent to confirmed_by" {
    entry_id="$(env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "確認対象")"
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" bash "$TEST_TMPDIR/scripts/bulletin_confirm.sh" saizo "$entry_id"
    [ "$status" -eq 0 ]
    [[ "$output" == *"|1|open" ]]
    run cat "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"- 'saizo'"* ]]
    [[ "$output" == *"status: 'open'"* ]]
}

@test "bulletin_confirm closes entry after all agents confirm" {
    entry_id="$(env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "全員確認" true)"
    for agent in shogun karo gunshi saizo; do
        run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" bash "$TEST_TMPDIR/scripts/bulletin_confirm.sh" "$agent" "$entry_id"
        [ "$status" -eq 0 ]
    done
    run cat "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"- 'shogun'"* ]]
    [[ "$output" == *"- 'karo'"* ]]
    [[ "$output" == *"- 'gunshi'"* ]]
    [[ "$output" == *"- 'saizo'"* ]]
    [[ "$output" == *"status: 'closed'"* ]]
}

@test "bulletin_close closes entry explicitly" {
    entry_id="$(env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" BULLETIN_TEST_AGENT_ID=saizo TMUX_PANE="$TMUX_PANE" PATH="$PATH" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" "手動クローズ")"
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" bash "$TEST_TMPDIR/scripts/bulletin_close.sh" "$entry_id"
    [ "$status" -eq 0 ]
    [ "$output" = "$entry_id" ]
    run cat "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"status: 'closed'"* ]]
}
