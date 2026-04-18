#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMPDIR_CLI
    TEST_TMPDIR_CLI="$(mktemp -d)"

    cat > "${TEST_TMPDIR_CLI}/settings.yaml" <<'YAML'
cli:
  default: claude
  agents:
    hanzo: codex
    gunshi:
      type: claude
      model_name: claude-opus-4-6
    saizo:
      type: invalid_cli
YAML

    cat > "${TEST_TMPDIR_CLI}/cli_profiles.yaml" <<'YAML'
profiles:
  claude:
    launch_cmd: "/tmp/claude"
    busy_patterns:
      - "Running"
      - "Streaming"
  codex:
    launch_cmd: "codex --fast"
    busy_patterns:
      - "background terminal running"
      - "Streaming"
YAML
}

teardown_file() {
    rm -rf "$TEST_TMPDIR_CLI"
}

@test "cli_lookup: string形式agentを解決できる" {
    run env CLI_ADAPTER_SETTINGS="${TEST_TMPDIR_CLI}/settings.yaml" CLI_LOOKUP_PROFILES="${TEST_TMPDIR_CLI}/cli_profiles.yaml" \
        bash -lc "source '$PROJECT_ROOT/scripts/lib/cli_lookup.sh'; cli_type hanzo"
    [ "$status" -eq 0 ]
    [ "$output" = "codex" ]
}

@test "cli_lookup: 不正typeはclaudeへフォールバックする" {
    run env CLI_ADAPTER_SETTINGS="${TEST_TMPDIR_CLI}/settings.yaml" CLI_LOOKUP_PROFILES="${TEST_TMPDIR_CLI}/cli_profiles.yaml" \
        bash -lc "source '$PROJECT_ROOT/scripts/lib/cli_lookup.sh'; cli_type saizo"
    [ "$status" -eq 0 ]
    [ "$output" = "claude" ]
}

@test "cli_lookup: profile scalarを取得できる" {
    run env CLI_ADAPTER_SETTINGS="${TEST_TMPDIR_CLI}/settings.yaml" CLI_LOOKUP_PROFILES="${TEST_TMPDIR_CLI}/cli_profiles.yaml" \
        bash -lc "source '$PROJECT_ROOT/scripts/lib/cli_lookup.sh'; cli_profile_get hanzo launch_cmd"
    [ "$status" -eq 0 ]
    [ "$output" = "codex --fast" ]
}

@test "cli_lookup: profile listをパイプ区切りで返す" {
    run env CLI_ADAPTER_SETTINGS="${TEST_TMPDIR_CLI}/settings.yaml" CLI_LOOKUP_PROFILES="${TEST_TMPDIR_CLI}/cli_profiles.yaml" \
        bash -lc "source '$PROJECT_ROOT/scripts/lib/cli_lookup.sh'; cli_profile_get_for_type codex busy_patterns"
    [ "$status" -eq 0 ]
    [ "$output" = "background terminal running|Streaming" ]
}

@test "cli_lookup: profile間の空行をスキップしてcodex scalarを取得できる" {
    run env CLI_ADAPTER_SETTINGS="${TEST_TMPDIR_CLI}/settings.yaml" CLI_LOOKUP_PROFILES="$PROJECT_ROOT/config/cli_profiles.yaml" \
        bash -lc "source '$PROJECT_ROOT/scripts/lib/cli_lookup.sh'; cli_profile_get_for_type codex clear_cmd"
    [ "$status" -eq 0 ]
    [ "$output" = "/new" ]
}

@test "cli_lookup: profile間の空行をスキップしてcodex表示名を取得できる" {
    run env CLI_ADAPTER_SETTINGS="${TEST_TMPDIR_CLI}/settings.yaml" CLI_LOOKUP_PROFILES="$PROJECT_ROOT/config/cli_profiles.yaml" \
        bash -lc "source '$PROJECT_ROOT/scripts/lib/cli_lookup.sh'; cli_profile_get_for_type codex display_name"
    [ "$status" -eq 0 ]
    [ "$output" = "Codex" ]
}

@test "cli_lookup: claude clear_cmdに回帰がない" {
    run env CLI_ADAPTER_SETTINGS="${TEST_TMPDIR_CLI}/settings.yaml" CLI_LOOKUP_PROFILES="$PROJECT_ROOT/config/cli_profiles.yaml" \
        bash -lc "source '$PROJECT_ROOT/scripts/lib/cli_lookup.sh'; cli_profile_get_for_type claude clear_cmd"
    [ "$status" -eq 0 ]
    [ "$output" = "/clear" ]
}

@test "cli_lookup: model_nameを表示名へ変換できる" {
    run env CLI_ADAPTER_SETTINGS="${TEST_TMPDIR_CLI}/settings.yaml" CLI_LOOKUP_PROFILES="${TEST_TMPDIR_CLI}/cli_profiles.yaml" \
        bash -lc "source '$PROJECT_ROOT/scripts/lib/cli_lookup.sh'; cli_model_display gunshi"
    [ "$status" -eq 0 ]
    [ "$output" = "Opus 4.6" ]
}
