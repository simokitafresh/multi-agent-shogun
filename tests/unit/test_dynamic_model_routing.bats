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
#
# コメントアウト (機能未実装):
#   TC-DMR-001〜003, 010〜017, 020〜029, 030〜033, 055,
#   100〜103, 110〜113, 120〜121, 130〜131, 140〜142,
#   200〜203, 210〜214, 224, 300〜303, 400〜423,
#   FAM-001〜009, PREF-001〜007
#
# SKIPPED理由:
#   DMR関数(get_capability_tier, get_cost_group, get_recommended_model,
#   needs_model_switch, get_switch_recommendation, can_model_switch,
#   validate_gunshi_analysis, should_trigger_bloom_analysis, get_bloom_routing,
#   append_model_performance, get_model_performance_summary,
#   get_available_cost_groups, validate_subscription_coverage,
#   find_agent_for_model)はローカルのlib/cli_adapter.shに未実装。
#   ローカルはget_cli_type, get_agent_model, _cli_adapter_read_yaml等の
#   基本関数のみ提供。

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

    # ─── 以下はコメントアウトされたテスト用フィクスチャ ───
    # 有効テストでは使用しない。yohey-w版完全移植時に有効化する。

    # # capability_tiers定義済み（TC-DMR-001〜029, 030〜033等）
    # cat > "${TEST_TMP}/settings_with_tiers.yaml" << 'YAML'
    # cli:
    #   default: claude
    #   agents:
    #     ashigaru1:
    #       type: codex
    #       model: gpt-5.3-codex-spark
    #     ashigaru2:
    #       type: claude
    #       model: claude-sonnet-4-5-20250929
    # capability_tiers:
    #   gpt-5.3-codex-spark:
    #     max_bloom: 3
    #     cost_group: chatgpt_pro
    #   gpt-5.3:
    #     max_bloom: 4
    #     cost_group: chatgpt_pro
    #   claude-sonnet-4-5-20250929:
    #     max_bloom: 5
    #     cost_group: claude_max
    #   claude-opus-4-6:
    #     max_bloom: 6
    #     cost_group: claude_max
    # YAML
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
# TC-DMR-001〜003: FR-01 settings.yaml capability_tiersセクション
# SKIPPED: 機能未実装 — get_capability_tier, get_cost_groupはローカル未実装
# =============================================================================

# @test "TC-DMR-001: FR-01 capability_tiers基本読取 — パースエラーなし" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     type get_capability_tier &>/dev/null
#     result=$(get_capability_tier "gpt-5.3-codex-spark")
#     [ "$result" = "3" ]
# }

# @test "TC-DMR-002: FR-01 capability_tiersセクション不在 — 後方互換" {
#     load_adapter_with "${TEST_TMP}/settings_no_tiers.yaml"
#     result=$(get_capability_tier "gpt-5.3-codex-spark")
#     [ "$result" = "6" ]
# }

# @test "TC-DMR-003: FR-01 cost_group読取" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_cost_group "gpt-5.3-codex-spark")
#     [ "$result" = "chatgpt_pro" ]
# }

# =============================================================================
# TC-DMR-010〜017: FR-02 get_capability_tier()
# SKIPPED: 機能未実装 — get_capability_tierはローカル未実装
# =============================================================================

# @test "TC-DMR-010: FR-02 Spark → 3" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_capability_tier "gpt-5.3-codex-spark")
#     [ "$result" = "3" ]
# }

# @test "TC-DMR-011: FR-02 Codex 5.3 → 4" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_capability_tier "gpt-5.3")
#     [ "$result" = "4" ]
# }

# @test "TC-DMR-012: FR-02 Sonnet Thinking → 5" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_capability_tier "claude-sonnet-4-5-20250929")
#     [ "$result" = "5" ]
# }

# @test "TC-DMR-013: FR-02 Opus Thinking → 6" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_capability_tier "claude-opus-4-6")
#     [ "$result" = "6" ]
# }

# @test "TC-DMR-014: FR-02 未定義モデル → 6" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_capability_tier "unknown-model")
#     [ "$result" = "6" ]
# }

# @test "TC-DMR-015: FR-02 capability_tiersセクション不在 → 6" {
#     load_adapter_with "${TEST_TMP}/settings_no_tiers.yaml"
#     result=$(get_capability_tier "gpt-5.3-codex-spark")
#     [ "$result" = "6" ]
# }

# @test "TC-DMR-016: FR-02 YAML破損 → 6" {
#     load_adapter_with "${TEST_TMP}/settings_broken.yaml"
#     result=$(get_capability_tier "gpt-5.3-codex-spark")
#     [ "$result" = "6" ]
# }

# @test "TC-DMR-017: FR-02 空文字入力 → 6" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_capability_tier "")
#     [ "$result" = "6" ]
# }

# =============================================================================
# TC-DMR-020〜029: FR-03 get_recommended_model()
# SKIPPED: 機能未実装 — get_recommended_modelはローカル未実装
# =============================================================================

# @test "TC-DMR-020: FR-03 L1 → Spark" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_recommended_model 1)
#     [ "$result" = "gpt-5.3-codex-spark" ]
# }

# @test "TC-DMR-021: FR-03 L2 → Spark" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_recommended_model 2)
#     [ "$result" = "gpt-5.3-codex-spark" ]
# }

# @test "TC-DMR-022: FR-03 L3 → Spark" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_recommended_model 3)
#     [ "$result" = "gpt-5.3-codex-spark" ]
# }

# @test "TC-DMR-023: FR-03 L4 → Codex 5.3" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_recommended_model 4)
#     [ "$result" = "gpt-5.3" ]
# }

# @test "TC-DMR-024: FR-03 L5 → Sonnet Thinking" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_recommended_model 5)
#     [ "$result" = "claude-sonnet-4-5-20250929" ]
# }

# @test "TC-DMR-025: FR-03 L6 → Opus Thinking" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_recommended_model 6)
#     [ "$result" = "claude-opus-4-6" ]
# }

# @test "TC-DMR-026: FR-03 capability_tiersセクション不在 → 空文字" {
#     load_adapter_with "${TEST_TMP}/settings_no_tiers.yaml"
#     result=$(get_recommended_model 3)
#     [ "$result" = "" ]
# }

# @test "TC-DMR-027: FR-03 範囲外(0) → exit 1" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     run get_recommended_model 0
#     [ "$status" -eq 1 ]
# }

# @test "TC-DMR-028: FR-03 範囲外(7) → exit 1" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     run get_recommended_model 7
#     [ "$status" -eq 1 ]
# }

# @test "TC-DMR-029: FR-03 コスト優先 — chatgpt_proが優先" {
#     load_adapter_with "${TEST_TMP}/settings_cost_priority.yaml"
#     result=$(get_recommended_model 4)
#     [ "$result" = "model-chatgpt-a" ]
# }

# =============================================================================
# TC-DMR-030〜033: FR-04 get_cost_group()
# SKIPPED: 機能未実装 — get_cost_groupはローカル未実装
# =============================================================================

# @test "TC-DMR-030: FR-04 Spark → chatgpt_pro" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_cost_group "gpt-5.3-codex-spark")
#     [ "$result" = "chatgpt_pro" ]
# }

# @test "TC-DMR-031: FR-04 Opus → claude_max" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_cost_group "claude-opus-4-6")
#     [ "$result" = "claude_max" ]
# }

# @test "TC-DMR-032: FR-04 未定義モデル → unknown" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_cost_group "unknown-model")
#     [ "$result" = "unknown" ]
# }

# @test "TC-DMR-033: FR-04 capability_tiersセクション不在 → unknown" {
#     load_adapter_with "${TEST_TMP}/settings_no_tiers.yaml"
#     result=$(get_cost_group "gpt-5.3-codex-spark")
#     [ "$result" = "unknown" ]
# }

# =============================================================================
# TC-DMR-040〜041: NFR-01 後方互換性 【有効】
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
# TC-DMR-050: NFR-05 テスト容易性 【有効・適応版】
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
# TC-DMR-055: NFR-06 冪等性
# SKIPPED: 機能未実装 — get_recommended_modelはローカル未実装
# =============================================================================

# @test "TC-DMR-055: NFR-06 get_recommended_model連続呼出で同一結果" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result1=$(get_recommended_model 4)
#     result2=$(get_recommended_model 4)
#     [ "$result1" = "$result2" ]
# }

# =============================================================================
# TC-DMR-100〜103: FR-05 model_switch判定
# SKIPPED: 機能未実装 — needs_model_switchはローカル未実装
# =============================================================================

# @test "TC-DMR-100: FR-05 switch不要 — bloom=3, model=spark" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     run needs_model_switch "gpt-5.3-codex-spark" 3
#     [ "$status" -eq 0 ]
#     [ "$output" = "no" ]
# }

# @test "TC-DMR-101: FR-05 switch必要 — bloom=4, model=spark" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     run needs_model_switch "gpt-5.3-codex-spark" 4
#     [ "$status" -eq 0 ]
#     [ "$output" = "yes" ]
# }

# @test "TC-DMR-102: FR-05 capability_tiers不在 → 判定スキップ" {
#     load_adapter_with "${TEST_TMP}/settings_no_tiers.yaml"
#     run needs_model_switch "gpt-5.3-codex-spark" 4
#     [ "$status" -eq 0 ]
#     [ "$output" = "skip" ]
# }

# @test "TC-DMR-103: FR-05 bloomフィールドなし → 判定スキップ" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     run needs_model_switch "gpt-5.3-codex-spark" ""
#     [ "$status" -eq 0 ]
#     [ "$output" = "skip" ]
# }

# =============================================================================
# TC-DMR-110〜113: FR-06 model_switch判定ロジック詳細
# SKIPPED: 機能未実装 — get_switch_recommendationはローカル未実装
# =============================================================================

# @test "TC-DMR-110: FR-06 同CLI内switch — codex spark→codex 5.3" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_switch_recommendation "gpt-5.3-codex-spark" 4)
#     [[ "$result" == *"gpt-5.3"* ]]
#     [[ "$result" == *"same_cost_group"* ]]
# }

# @test "TC-DMR-111: FR-06 CLI跨ぎ — bloom=5, codex足軽" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_switch_recommendation "gpt-5.3-codex-spark" 5)
#     [[ "$result" == *"claude-sonnet"* ]]
#     [[ "$result" == *"cross_cost_group"* ]]
# }

# @test "TC-DMR-112: FR-06 switch不要時は現モデル維持" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_switch_recommendation "gpt-5.3-codex-spark" 3)
#     [ "$result" = "no_switch" ]
# }

# @test "TC-DMR-113: FR-06 bloom=6でOpusに到達" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_switch_recommendation "gpt-5.3-codex-spark" 6)
#     [[ "$result" == *"claude-opus-4-6"* ]]
# }

# =============================================================================
# TC-DMR-120〜121: NFR-02 応答速度
# SKIPPED: 機能未実装 — get_capability_tier, get_recommended_modelはローカル未実装
# =============================================================================

# @test "TC-DMR-120: NFR-02 get_capability_tier応答速度 500ms以内" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     start=$(date +%s%N)
#     get_capability_tier "gpt-5.3-codex-spark" > /dev/null
#     end=$(date +%s%N)
#     elapsed_ms=$(( (end - start) / 1000000 ))
#     [ "$elapsed_ms" -lt 500 ]
# }

# @test "TC-DMR-121: NFR-02 get_recommended_model応答速度 500ms以内" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     start=$(date +%s%N)
#     get_recommended_model 4 > /dev/null
#     end=$(date +%s%N)
#     elapsed_ms=$(( (end - start) / 1000000 ))
#     [ "$elapsed_ms" -lt 500 ]
# }

# =============================================================================
# TC-DMR-130〜131: NFR-03 CLI互換性
# SKIPPED: 機能未実装 — can_model_switchはローカル未実装
# =============================================================================

# @test "TC-DMR-130: NFR-03 model_switchはClaude足軽のみ有効" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(can_model_switch "codex")
#     [ "$result" = "limited" ]
# }

# @test "TC-DMR-131: NFR-03 Claude足軽はfull switch可能" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(can_model_switch "claude")
#     [ "$result" = "full" ]
# }

# =============================================================================
# TC-DMR-140〜142: NFR-04 コスト最適化
# SKIPPED: 機能未実装 — get_recommended_modelはローカル未実装
# =============================================================================

# @test "TC-DMR-140: NFR-04 L3にOpus不使用" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_recommended_model 3)
#     [ "$result" != "claude-opus-4-6" ]
# }

# @test "TC-DMR-141: NFR-04 chatgpt_pro優先" {
#     load_adapter_with "${TEST_TMP}/settings_cost_priority.yaml"
#     result=$(get_recommended_model 4)
#     cg=$(get_cost_group "$result")
#     [ "$cg" = "chatgpt_pro" ]
# }

# @test "TC-DMR-142: NFR-04 不要switch抑制" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     run needs_model_switch "gpt-5.3" 4
#     [ "$output" = "no" ]
# }

# =============================================================================
# TC-DMR-200〜203: FR-07 gunshi_analysis.yaml スキーマ
# SKIPPED: 機能未実装 — validate_gunshi_analysisはローカル未実装
# =============================================================================

# @test "TC-DMR-200: FR-07 正常YAML — 全フィールド定義" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     run validate_gunshi_analysis "${TEST_TMP}/analysis_valid.yaml"
#     [ "$status" -eq 0 ]
#     [ "$output" = "valid" ]
# }

# @test "TC-DMR-201: FR-07 #48フィールド省略 — パースエラーなし" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     run validate_gunshi_analysis "${TEST_TMP}/analysis_no48.yaml"
#     [ "$status" -eq 0 ]
#     [ "$output" = "valid" ]
# }

# @test "TC-DMR-202: FR-07 bloom_level範囲外(0,7) — バリデーションエラー" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     run validate_gunshi_analysis "${TEST_TMP}/analysis_bad_bloom.yaml"
#     [ "$status" -eq 1 ]
#     [[ "$output" == *"bloom_level"* ]]
# }

# @test "TC-DMR-203: FR-07 confidence範囲外(-1, 2.0) — バリデーションエラー" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     run validate_gunshi_analysis "${TEST_TMP}/analysis_bad_confidence.yaml"
#     [ "$status" -eq 1 ]
#     [[ "$output" == *"confidence"* ]]
# }

# =============================================================================
# TC-DMR-210〜214: FR-08 Bloom分析トリガー判定ロジック
# SKIPPED: 機能未実装 — should_trigger_bloom_analysis, get_bloom_routingはローカル未実装
# =============================================================================

# @test "TC-DMR-210: FR-08 auto → 全タスク分析トリガー" {
#     load_adapter_with "${TEST_TMP}/settings_bloom_auto.yaml"
#     result=$(should_trigger_bloom_analysis "auto" "false")
#     [ "$result" = "yes" ]
# }

# @test "TC-DMR-211: FR-08 manual + required=true → 分析トリガー" {
#     load_adapter_with "${TEST_TMP}/settings_bloom_manual.yaml"
#     result=$(should_trigger_bloom_analysis "manual" "true")
#     [ "$result" = "yes" ]
# }

# @test "TC-DMR-211b: FR-08 manual + required=false → トリガーなし" {
#     load_adapter_with "${TEST_TMP}/settings_bloom_manual.yaml"
#     result=$(should_trigger_bloom_analysis "manual" "false")
#     [ "$result" = "no" ]
# }

# @test "TC-DMR-212: FR-08 off → 分析なし" {
#     load_adapter_with "${TEST_TMP}/settings_bloom_off.yaml"
#     result=$(should_trigger_bloom_analysis "off" "true")
#     [ "$result" = "no" ]
# }

# @test "TC-DMR-213: FR-08 bloom_routing未定義 → off扱い → 分析なし" {
#     load_adapter_with "${TEST_TMP}/settings_no_tiers.yaml"
#     routing=$(get_bloom_routing)
#     result=$(should_trigger_bloom_analysis "$routing" "true")
#     [ "$result" = "no" ]
# }

# @test "TC-DMR-214: FR-08 should_trigger_bloom_analysis fallback引数" {
#     load_adapter_with "${TEST_TMP}/settings_bloom_auto.yaml"
#     result=$(should_trigger_bloom_analysis "auto" "false" "no")
#     [ "$result" = "fallback" ]
# }

# =============================================================================
# TC-DMR-220〜223: FR-09 bloom_routing設定 【有効】
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

# =============================================================================
# TC-DMR-224: FR-09 不正値 → off + stderr警告
# SKIPPED: 機能未実装 — get_bloom_routingはローカル未実装
# =============================================================================

# @test "TC-DMR-224: FR-09 bloom_routing不正値 → off + stderr警告" {
#     load_adapter_with "${TEST_TMP}/settings_bloom_invalid.yaml"
#     result=$(get_bloom_routing 2>/tmp/dmr_stderr_test)
#     [ "$result" = "off" ]
#     grep -q "bloom_routing" /tmp/dmr_stderr_test || grep -q "invalid" /tmp/dmr_stderr_test
#     rm -f /tmp/dmr_stderr_test
# }

# =============================================================================
# TC-DMR-300〜303: FR-10 Full auto-selection (品質フィードバック)
# SKIPPED: 機能未実装 — append_model_performance, get_model_performance_summaryはローカル未実装
# =============================================================================

# @test "TC-DMR-300: FR-10 履歴追記 — model_performance.yamlに1行追記" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     local perf_file="${TEST_TMP}/model_performance.yaml"
#     run append_model_performance "$perf_file" "subtask_001" "seo_article" 3 "gpt-5.3-codex-spark" "pass" 0.85
#     [ "$status" -eq 0 ]
#     run "$CLI_ADAPTER_PROJECT_ROOT/.venv/bin/python3" -c "
# import yaml
# with open('${perf_file}') as f:
#     doc = yaml.safe_load(f)
# print(len(doc.get('history', [])))
# "
#     [ "$output" = "1" ]
# }

# @test "TC-DMR-301: FR-10 履歴読取 — task_type×bloom_level別の集計" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     local perf_file="${TEST_TMP}/model_performance.yaml"
#     append_model_performance "$perf_file" "subtask_001" "seo_article" 3 "gpt-5.3-codex-spark" "pass" 0.90
#     append_model_performance "$perf_file" "subtask_002" "seo_article" 3 "gpt-5.3-codex-spark" "pass" 0.85
#     append_model_performance "$perf_file" "subtask_003" "seo_article" 3 "gpt-5.3-codex-spark" "fail" 0.40
#     result=$(get_model_performance_summary "$perf_file" "seo_article" 3)
#     [[ "$result" == *"total:3"* ]]
#     [[ "$result" == *"pass:2"* ]]
# }

# @test "TC-DMR-302: FR-10 空ファイル — model_performance.yaml不在でもエラーなし" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     local perf_file="${TEST_TMP}/nonexistent_performance.yaml"
#     run get_model_performance_summary "$perf_file" "seo_article" 3
#     [ "$status" -eq 0 ]
#     [[ "$output" == *"total:0"* ]]
# }

# @test "TC-DMR-303: FR-10 適合度算出 — pass率が算出可能" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     local perf_file="${TEST_TMP}/model_performance.yaml"
#     append_model_performance "$perf_file" "subtask_001" "bugfix" 4 "gpt-5.3" "pass" 0.90
#     append_model_performance "$perf_file" "subtask_002" "bugfix" 4 "gpt-5.3" "pass" 0.85
#     append_model_performance "$perf_file" "subtask_003" "bugfix" 4 "gpt-5.3" "pass" 0.80
#     append_model_performance "$perf_file" "subtask_004" "bugfix" 4 "gpt-5.3" "fail" 0.30
#     result=$(get_model_performance_summary "$perf_file" "bugfix" 4)
#     [[ "$result" == *"pass_rate:0.75"* ]]
# }

# =============================================================================
# TC-DMR-400〜423: Subscription Patterns
# SKIPPED: 機能未実装 — get_available_cost_groups, validate_subscription_coverageはローカル未実装
# =============================================================================

# @test "TC-DMR-400: get_available_cost_groups — 明示定義 claude_maxのみ" {
#     load_adapter_with "${TEST_TMP}/settings_explicit_groups.yaml"
#     result=$(get_available_cost_groups)
#     [ "$result" = "claude_max" ]
# }

# @test "TC-DMR-401: get_available_cost_groups — 省略時はcapability_tiersから自動推定" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_available_cost_groups)
#     [[ "$result" == *"chatgpt_pro"* ]]
#     [[ "$result" == *"claude_max"* ]]
# }

# @test "TC-DMR-402: get_available_cost_groups — capability_tiers不在 → 空" {
#     load_adapter_with "${TEST_TMP}/settings_no_tiers.yaml"
#     result=$(get_available_cost_groups)
#     [ "$result" = "" ]
# }

# @test "TC-DMR-403: get_available_cost_groups — Claude onlyの自動推定" {
#     load_adapter_with "${TEST_TMP}/settings_claude_only.yaml"
#     result=$(get_available_cost_groups)
#     [ "$result" = "claude_max" ]
# }

# @test "TC-DMR-404: get_available_cost_groups — ChatGPT onlyの自動推定" {
#     load_adapter_with "${TEST_TMP}/settings_chatgpt_only.yaml"
#     result=$(get_available_cost_groups)
#     [ "$result" = "chatgpt_pro" ]
# }

# @test "TC-DMR-410: Claude only — L3 → sonnet + overqualified警告" {
#     load_adapter_with "${TEST_TMP}/settings_claude_only.yaml"
#     result=$(get_recommended_model 3 2>/tmp/dmr_410_stderr)
#     [ "$result" = "claude-sonnet-4-5-20250929" ]
#     grep -q "overqualified" /tmp/dmr_410_stderr
#     rm -f /tmp/dmr_410_stderr
# }

# @test "TC-DMR-411: ChatGPT only — L5 → gpt-5.3 + insufficient警告" {
#     load_adapter_with "${TEST_TMP}/settings_chatgpt_only.yaml"
#     result=$(get_recommended_model 5 2>/tmp/dmr_411_stderr)
#     [ "$result" = "gpt-5.3" ]
#     grep -q "insufficient" /tmp/dmr_411_stderr
#     rm -f /tmp/dmr_411_stderr
# }

# @test "TC-DMR-412: available_cost_groups=claude_max → chatgpt_proモデルを候補除外" {
#     load_adapter_with "${TEST_TMP}/settings_explicit_groups.yaml"
#     result=$(get_recommended_model 3)
#     [[ "$result" == "claude-sonnet-4-5-20250929" ]]
# }

# @test "TC-DMR-413: available_cost_groups=chatgpt_pro → claude_maxモデルを候補除外" {
#     load_adapter_with "${TEST_TMP}/settings_chatgpt_groups.yaml"
#     result=$(get_recommended_model 5 2>/dev/null)
#     [ "$result" = "gpt-5.3" ]
# }

# @test "TC-DMR-414: 両方契約 — L3 → Spark（従来通り最安選択）" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_recommended_model 3)
#     [ "$result" = "gpt-5.3-codex-spark" ]
# }

# @test "TC-DMR-420: validate_subscription_coverage — 全Bloomカバー → ok" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(validate_subscription_coverage)
#     [ "$result" = "ok" ]
# }

# @test "TC-DMR-421: validate_subscription_coverage — ChatGPT only → gap:5,6" {
#     load_adapter_with "${TEST_TMP}/settings_chatgpt_only.yaml"
#     result=$(validate_subscription_coverage)
#     [[ "$result" == *"gap"* ]]
#     [[ "$result" == *"5"* ]]
#     [[ "$result" == *"6"* ]]
# }

# @test "TC-DMR-422: validate_subscription_coverage — Claude only → カバー(L5+L6あり)" {
#     load_adapter_with "${TEST_TMP}/settings_claude_only.yaml"
#     result=$(validate_subscription_coverage)
#     [ "$result" = "ok" ]
# }

# @test "TC-DMR-423: validate_subscription_coverage — capability_tiers不在 → 未設定" {
#     load_adapter_with "${TEST_TMP}/settings_no_tiers.yaml"
#     result=$(validate_subscription_coverage)
#     [ "$result" = "unconfigured" ]
# }

# =============================================================================
# TC-FAM-001〜009: find_agent_for_model()
# SKIPPED: 機能未実装 — find_agent_for_modelはローカル未実装
# =============================================================================

# @test "TC-FAM-001: 完全一致の足軽が存在 → ashigaru1 を返す（Spark）" {
#     load_adapter_with "${TEST_TMP}/settings_mixed_cli.yaml"
#     result=$(find_agent_for_model "gpt-5.3-codex-spark")
#     [ "$result" = "ashigaru1" ]
# }

# @test "TC-FAM-002: Sonnet足軽が存在 → ashigaru4 を返す" {
#     load_adapter_with "${TEST_TMP}/settings_mixed_cli.yaml"
#     result=$(find_agent_for_model "claude-sonnet-4-6")
#     [ "$result" = "ashigaru4" ]
# }

# @test "TC-FAM-003: Opus足軽が存在 → ashigaru6 を返す" {
#     load_adapter_with "${TEST_TMP}/settings_mixed_cli.yaml"
#     result=$(find_agent_for_model "claude-opus-4-6")
#     [ "$result" = "ashigaru6" ]
# }

# @test "TC-FAM-004: 対応モデルの足軽がない → フォールバック" {
#     load_adapter_with "${TEST_TMP}/settings_mixed_cli.yaml"
#     result=$(find_agent_for_model "gpt-5.1-codex-max")
#     [ -n "$result" ]
#     [[ "$result" =~ ^ashigaru[0-9]+$ ]]
# }

# @test "TC-FAM-005: 引数なし → exit code 1" {
#     load_adapter_with "${TEST_TMP}/settings_mixed_cli.yaml"
#     run find_agent_for_model
#     [ "$status" -eq 1 ]
# }

# @test "TC-FAM-006: 空文字引数 → exit code 1" {
#     load_adapter_with "${TEST_TMP}/settings_mixed_cli.yaml"
#     run find_agent_for_model ""
#     [ "$status" -eq 1 ]
# }

# @test "TC-FAM-007: 複数の同モデル足軽 → 番号最小を返す" {
#     load_adapter_with "${TEST_TMP}/settings_all_spark.yaml"
#     result=$(find_agent_for_model "gpt-5.3-codex-spark")
#     [ "$result" = "ashigaru1" ]
# }

# @test "TC-FAM-008: capability_tiersなし設定でも動作する" {
#     load_adapter_with "${TEST_TMP}/settings_no_tiers.yaml"
#     result=$(find_agent_for_model "gpt-5.3-codex-spark")
#     [ "$result" = "ashigaru1" ]
# }

# @test "TC-FAM-009: 足軽のみ対象（karo, gunshiは除外）" {
#     load_adapter_with "${TEST_TMP}/settings_mixed_cli.yaml"
#     result=$(find_agent_for_model "claude-sonnet-4-5-20250929")
#     [[ "$result" =~ ^ashigaru[0-9]+$ ]]
# }

# =============================================================================
# TC-PREF-001〜007: bloom_model_preference ルーティング
# SKIPPED: 機能未実装 — get_recommended_model(preference対応版)はローカル未実装
# =============================================================================

# @test "TC-PREF-001: preference defined → first choice selected" {
#     load_adapter_with "${TEST_TMP}/settings_with_preference.yaml"
#     result=$(get_recommended_model 2)
#     [ "$result" = "gpt-5.3-codex-spark" ]
# }

# @test "TC-PREF-002: first preference capability insufficient → fallback to second" {
#     load_adapter_with "${TEST_TMP}/settings_preference_cap_fallback.yaml"
#     result=$(get_recommended_model 4)
#     [ "$result" = "claude-sonnet-4-6" ]
# }

# @test "TC-PREF-003: no preference defined → legacy cost_priority behavior" {
#     load_adapter_with "${TEST_TMP}/settings_with_tiers.yaml"
#     result=$(get_recommended_model 4)
#     [ "$result" = "gpt-5.3" ]
# }

# @test "TC-PREF-004: single key L3 matches bloom_level=3" {
#     load_adapter_with "${TEST_TMP}/settings_with_preference.yaml"
#     result=$(get_recommended_model 3)
#     [ "$result" = "gpt-5.3" ]
# }

# @test "TC-PREF-005: all preferred models unavailable → fallback to cost_priority" {
#     load_adapter_with "${TEST_TMP}/settings_preference_all_fail.yaml"
#     result=$(get_recommended_model 4 2>/dev/null)
#     [ "$result" = "claude-sonnet-4-6" ]
#     run bash -c "export CLI_ADAPTER_SETTINGS='${TEST_TMP}/settings_preference_all_fail.yaml'; export CLI_ADAPTER_PROJECT_ROOT='${PROJECT_ROOT}'; source '${PROJECT_ROOT}/lib/cli_adapter.sh' 2>/dev/null; get_recommended_model 4 2>&1 1>/dev/null"
#     [[ "$output" =~ "WARNING" ]]
# }

# @test "TC-PREF-006: available_cost_groups exclusion with preference" {
#     load_adapter_with "${TEST_TMP}/settings_preference_claude_only.yaml"
#     result=$(get_recommended_model 2)
#     [ "$result" = "claude-haiku-4-5-20251001" ]
# }

# @test "TC-PREF-007: no available_cost_groups → all models are candidates" {
#     load_adapter_with "${TEST_TMP}/settings_with_preference.yaml"
#     result=$(get_recommended_model 2)
#     [ "$result" = "gpt-5.3-codex-spark" ]
# }
