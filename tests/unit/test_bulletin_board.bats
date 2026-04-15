#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_WRITE="$PROJECT_ROOT/scripts/bulletin_write.sh"
    export SRC_CONFIRM="$PROJECT_ROOT/scripts/bulletin_confirm.sh"
    export SRC_AGENT_CONFIG="$PROJECT_ROOT/scripts/lib/agent_config.sh"
    [ -f "$SRC_WRITE" ] || return 1
    [ -f "$SRC_CONFIRM" ] || return 1
    [ -f "$SRC_AGENT_CONFIG" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/bulletin.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/lib" "$TEST_TMPDIR/queue" "$TEST_TMPDIR/config"
    cp "$SRC_WRITE" "$TEST_TMPDIR/scripts/bulletin_write.sh"
    cp "$SRC_CONFIRM" "$TEST_TMPDIR/scripts/bulletin_confirm.sh"
    cp "$SRC_AGENT_CONFIG" "$TEST_TMPDIR/scripts/lib/agent_config.sh"
    chmod +x "$TEST_TMPDIR/scripts/bulletin_write.sh" "$TEST_TMPDIR/scripts/bulletin_confirm.sh"
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
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" saizo "共有連絡"
    [ "$status" -eq 0 ]
    [[ "$output" == blt_* ]]
    run cat "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"content: |-"* ]]
    [[ "$output" == *"共有連絡"* ]]
    [[ "$output" == *"posted_by: 'saizo'"* ]]
    [[ "$output" == *"confirmed_by: []"* ]]
}

@test "bulletin_confirm adds agent to confirmed_by" {
    entry_id="$(env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" saizo "確認対象")"
    run env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" bash "$TEST_TMPDIR/scripts/bulletin_confirm.sh" saizo "$entry_id"
    [ "$status" -eq 0 ]
    [[ "$output" == *"|1|open" ]]
    run cat "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"- 'saizo'"* ]]
    [[ "$output" == *"status: 'open'"* ]]
}

@test "bulletin_confirm closes entry after all agents confirm" {
    entry_id="$(env BULLETIN_ROOT_OVERRIDE="$TEST_TMPDIR" bash "$TEST_TMPDIR/scripts/bulletin_write.sh" saizo "全員確認")"
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
