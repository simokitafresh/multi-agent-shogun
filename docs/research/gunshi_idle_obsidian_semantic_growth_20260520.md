# Obsidian×セマンティックインデックス成長設計書

## 現状 (2026-05-20計測)

| 指標 | 値 | 備考 |
|------|---|------|
| セマンティック概念数 | 40件 (35→+5) | 本セッションで5概念追加 |
| [[リンク]]ユニークターゲット | 289件 | lessons/review_log/deepdive/reports全体 |
| スクリプトカバレッジ | 37.7% (77/204) | 17.6%→37.7%。暗黒物質127件残 |
| causal_backlinks利用回数 | 1回 (review_log言及) | --detail/--semantic拡張済み |
| origin付き教訓 | 97件 (gunshi33+karo35+shogun29) | 全lessons [[リンク]]付き |

## 本セッション実施項目

### 1. causal_backlinks.sh拡張 (commit含む 81826685)
- `--detail`: origin/causal_chain行を表示
- `--semantic`: セマンティック概念逆引き
- 3モード+複合テスト全PASS

### 2. セマンティックインデックス5概念追加

| 概念 | カバースクリプト数 | P0/P1分類 |
|------|-----------------|-----------|
| gate_quality_framework | 10件(gate系+cmd_save) | P0 |
| lesson_lifecycle | 11件(lesson_write系+causal_backlinks) | P1 |
| bulletin_communication | 5件(bulletin系) | P0 |
| hook_automation_framework | 10件(.claude/hooks系) | P1 |
| (infrastructure_opsに既存) | - | 既存拡張 |

### 3. 残課題(次サイクル用)

#### P2: スクリプト共通ライブラリ
- `scripts/lib/` 12件未カバー (agent_config, cli_lookup, ctx_utils, field_get等)
- 新概念候補: `script_commons_library`

#### P3: メトリクス・監視系
- 30件以上未カバー (chronicle_metrics, count_gate_metrics, skill_metrics等)
- 新概念候補: `comprehensive_metrics_pipeline`

#### [[リンク]]→概念マッピング
- 289ユニークリンクのうち大多数はcmd_id(概念化不要)
- session/deepdive系は既存deepdive_principles概念に含まれる
- 実効的な新概念候補: infra_tool/concept系のクラスタを特定する必要あり

### 4. ギャップ分析エージェント結果(3クラスタ追加)

| 概念 | リンク集中度 | 含まれるリンク |
|------|------------|--------------|
| test_quality_framework | 5件 | test_is_debt, test_cleanup, test_gap, test_file_granularity, script_unit_consolidation |
| semantic_causal_automation | 3件 | obsidian_link_stagnation, semantic_map_generate, codd_refactor_registry_stale |
| scope_integrity_lifecycle | 2件 | scope_context_stale, test_gap |

**核心指摘**: 因果NW成長が「cmd causalフィールド記入」に留まり、セマンティック概念化へのフィードバックループが未形成。cmd_complete_gateでcausalフィールド→semantic_index自動更新の強化が次Phase。

## 成長ロードマップ

| Phase | 目標 | カバレッジ予測 |
|-------|------|-------------|
| Phase 1 (完了) | P0空白解消+causal_backlinks拡張 | 37.7% |
| Phase 2 | P2 script_commons + P3 metrics | ~50% |
| Phase 3 | レビュー/配備フローにcausal_backlinks統合 | - |
| Phase 4 | deploy_task.shにcmd因果背景Level 5注入 | - |

## 因果リンク
- → [[semantic_dictionary_design]] セマンティック辞書構想の実行段階
- → [[causal_traversal_pipeline]] 因果辺トラバース統合パイプラインの道具強化
- → [[deepdive_why_chain_20260321]] Phase 8(利他): 全エージェントが使える道具を整備
- → [[growth_loop]] 学習ループ: semantic_searchとcausal_backlinksがレビュー/配備/自走の全局面で利用可能に
