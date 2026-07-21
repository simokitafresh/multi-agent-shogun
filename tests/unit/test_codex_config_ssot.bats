#!/usr/bin/env bats

# test_necessity: codex respawn paths must never restore a pre-SSOT config, and applying one agent's settings twice must be idempotent.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "scripts contain no codex_config_restore definition or call" {
    run bash -c 'if rg -n "codex_config_restore" "$1/scripts"; then exit 1; fi' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
}

@test "codex_config_apply_agent is idempotent for the same SSOT agent" {
    fixture="$(mktemp -d)"
    mkdir -p "$fixture/.codex"
    cat > "$fixture/.codex/config.toml" <<'EOF'
model = "gpt-5.6-sol"
model_reasoning_effort = "high"
service_tier = "fast"
EOF
    run env HOME="$fixture" PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        source "$PROJECT_ROOT/scripts/lib/cli_lookup.sh"
        codex_config_apply_agent hanzo
        first=$(sha256sum "$HOME/.codex/config.toml" | awk "{print \$1}")
        codex_config_apply_agent hanzo
        second=$(sha256sum "$HOME/.codex/config.toml" | awk "{print \$1}")
        test "$first" = "$second"
        grep -q "model_reasoning_effort = \"low\"" "$HOME/.codex/config.toml"
        grep -q "service_tier = \"default\"" "$HOME/.codex/config.toml"
    '
    rm -r "$fixture"
    [ "$status" -eq 0 ]
}
