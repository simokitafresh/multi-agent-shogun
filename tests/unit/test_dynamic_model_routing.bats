#!/usr/bin/env bats
# test_dynamic_model_routing.bats — Dynamic Model Routing ユニットテスト
# ローカル適応版: yohey-w/multi-agent-shogun から移植
#
# 有効テスト (7件):
#   TC-DMR-040: get_cli_type後方互換
#   TC-DMR-041: get_agent_model後方互換
#   TC-DMR-050: CLI_ADAPTER_SETTINGS注入（_cli_adapter_read_yamlで検証に適応）
#   TC-DMR-220: bloom_routing=auto読取
#   TC-DMR-221: bloom_routing=manual読取
#   TC-DMR-222: bloom_routing=off読取
#   TC-DMR-223: bloom_routing未定義 → off

# --- セットアップ ---

setup() {
    TEST_TMP="$(mktemp -d)"
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

    # capability_tiersセクション不在（後方互換テスト用: TC-DMR-040,041,050,223）
    cat > "${TEST_TMP}/settings_no_tiers.yaml" << 'YAML'
cli:
  default: claude
  agents:
    ashigaru1:
      type: codex
      model: gpt-5.3-codex-spark
YAML

    # bloom_routing設定テスト用
    cat > "${TEST_TMP}/settings_bloom_auto.yaml" << 'YAML'
bloom_routing: auto
YAML

    cat > "${TEST_TMP}/settings_bloom_manual.yaml" << 'YAML'
bloom_routing: manual
YAML

    cat > "${TEST_TMP}/settings_bloom_off.yaml" << 'YAML'
bloom_routing: "off"
YAML
}

teardown() {
    rm -rf "$TEST_TMP"
}

# ヘルパー: 特定のsettings.yamlでcli_adapterをロード
load_adapter_with() {
    local settings_file="$1"
    export CLI_ADAPTER_SETTINGS="$settings_file"
    export CLI_ADAPTER_PROJECT_ROOT="$PROJECT_ROOT"
    source "${PROJECT_ROOT}/lib/cli_adapter.sh"
}

# =============================================================================
# TC-DMR-040〜041: NFR-01 後方互換性
# =============================================================================

@test "TC-DMR-040: NFR-01 既存get_cli_type回帰なし" {
    load_adapter_with "${TEST_TMP}/settings_no_tiers.yaml"
    # 既存関数がcapability_tiers追加後も正常動作
    result=$(get_cli_type "ashigaru1")
    [ "$result" = "codex" ]
}

@test "TC-DMR-041: NFR-01 既存get_agent_model回帰なし" {
    load_adapter_with "${TEST_TMP}/settings_no_tiers.yaml"
    result=$(get_agent_model "ashigaru1")
    [ "$result" = "gpt-5.3-codex-spark" ]
}

# =============================================================================
# TC-DMR-050: NFR-05 テスト容易性
# 原版はget_capability_tier使用 → _cli_adapter_read_yamlで同概念を検証
# =============================================================================

@test "TC-DMR-050: NFR-05 CLI_ADAPTER_SETTINGS注入" {
    # 異なるsettingsファイルを注入してテスト可能なことを確認
    load_adapter_with "${TEST_TMP}/settings_bloom_auto.yaml"
    result1=$(_cli_adapter_read_yaml "bloom_routing" "off")
    [ "$result1" = "auto" ]

    load_adapter_with "${TEST_TMP}/settings_no_tiers.yaml"
    result2=$(_cli_adapter_read_yaml "bloom_routing" "off")
    [ "$result2" = "off" ]
}

# =============================================================================
# TC-DMR-220〜223: FR-09 bloom_routing設定
# _cli_adapter_read_yamlで読取テスト（ローカルに存在する関数）
# =============================================================================

@test "TC-DMR-220: FR-09 bloom_routing=auto読取" {
    load_adapter_with "${TEST_TMP}/settings_bloom_auto.yaml"
    result=$(_cli_adapter_read_yaml "bloom_routing" "off")
    [ "$result" = "auto" ]
}

@test "TC-DMR-221: FR-09 bloom_routing=manual読取" {
    load_adapter_with "${TEST_TMP}/settings_bloom_manual.yaml"
    result=$(_cli_adapter_read_yaml "bloom_routing" "off")
    [ "$result" = "manual" ]
}

@test "TC-DMR-222: FR-09 bloom_routing=off読取" {
    load_adapter_with "${TEST_TMP}/settings_bloom_off.yaml"
    result=$(_cli_adapter_read_yaml "bloom_routing" "off")
    [ "$result" = "off" ]
}

@test "TC-DMR-223: FR-09 bloom_routing未定義 → off" {
    load_adapter_with "${TEST_TMP}/settings_no_tiers.yaml"
    result=$(_cli_adapter_read_yaml "bloom_routing" "off")
    [ "$result" = "off" ]
}
