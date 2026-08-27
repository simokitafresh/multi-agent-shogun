#!/usr/bin/env bats

# test_necessity: first_setupの初回案内、3項目入力、dry-run無変更境界を恒久的に守る。

setup() {
    ROOT="$BATS_TEST_DIRNAME/../.."
    SCRIPT="$ROOT/first_setup.sh"
    SETTINGS="$ROOT/config/settings.yaml"
}

@test "first_setup exposes Codex auth, ntfy/CLI inputs, and ext4 guidance" {
    run rg -n "codex login --device-auth|codex login status|read -r -p.*ntfy|read -r -p.*CLI|/mnt/c.*9p|9p_root_fix_runbook_20260827\.md" "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(grep -Fc 'read -r -p' "$SCRIPT")" -ge 3 ]
}

@test "first_setup dry-run is side-effect free and prints required guidance" {
    before="$(sha256sum "$SETTINGS" | awk '{print $1}')"
    run bash "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"codex login --device-auth"* ]]
    [[ "$output" == *"codex login status"* ]]
    [[ "$output" == *"ntfy topic"* ]]
    [[ "$output" == *"CLI"* ]]
    [[ "$output" == *"dry-run: インストーラー、設定、cron、HOME配下を変更しません"* ]]
    [ "$before" = "$(sha256sum "$SETTINGS" | awk '{print $1}')" ]
}
