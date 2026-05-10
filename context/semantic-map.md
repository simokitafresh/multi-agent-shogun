---
codd:
  node_id: design:semantic-map
  type: generated-index
  title: セマンティクスマップ
  modules:
    - semantic-index
---

# セマンティクスマップ

<!-- auto-generated from docs/semantic-index/index.md -->
<!-- do not edit directly; update docs/semantic-index/index.md and run codd propagate --update -->

| 概念 | 別名 | 主要ファイル | 教訓 |
|------|------|------------|------|
| 再計算パイプライン | fullrecalculate, recalc, 再計算フロー, recalculate_fast | `/mnt/c/Python_app/DM-signal/backend/app/jobs/recalculate_fast.py`, `context/dm-signal-core.md` §19.2, `docs/research/fullrecalculate-architecture-2026-03-28.md` | `L714` recalculate-sync acceptedでは完了判定にしない, `L715` recalculate-sync acceptedは完了ではない。DB recalculation_status confirmed必須 |
| セマンティック辞書構想 | セマンティック辞書, セマンティクスインデックス, 意味検索, 概念索引, セマンティクスインデックス候補除外精度, セマンティクスインデックス成長ループ構築 ノイズ除外 aliases自動拡張 参照切れ修正, セマンティクスインデックスaliases照合をcmd品質ゲートに接続 Level5化 | `docs/research/semantic_index_design.md`, `context/lord-conversation-index.md`, `scripts/semantic_map_generate.sh` | なし |
| gate迂回防止 | gate迂回, 滑り坂, 正規フロー, cmd_delegate | `scripts/cmd_delegate.sh`, `.claude/hooks/pre-bash-combined.sh` | `memory/deepdive_causal_tracing_20260415.md` Phase 6, `docs/research/lessons_shogun_v1_archive.md` LS049-LS052 |
| 用語辞書 | disambiguation, terminology, 曖昧性解消, 1語1意味, MECE定義辞書 | `/mnt/c/Python_app/DM-signal/docs/knowledge-base/terminology/disambiguation.md`, `/mnt/c/Python_app/DM-signal/context/dm-signal-terminology.md`, `docs/research/cmd_2555_disambiguation_design.md` | なし |
| 本番パリティ | パリティ検証, GS-本番パリティ, holding_signal, monthly_returns, golden data | `context/dm-signal-core.md` §19.3, `context/checklist-shin-v2-registration.md`, `docs/research/dmsignal_parity_verification_audit.md` | `context/dm-signal-core.md` L088-L129, `L717` 追加ベンチマークはticker_monthly_returnsだけでなくprices fallbackを確認せよ |
| deepdive原理 | deepdive, 追体験, why_chain, causal_tracing, 自動化×強制 | `context/training-cycle.md` | `memory/deepdive_why_chain_20260321.md`, `memory/deepdive_causal_tracing_20260415.md`, `memory/deepdive_karo_verification_20260405.md` |
| 学習ループ | 学習ループ, 成長ループ, 二値計測, 知見還流, ラルフループ, 三層学習ループ | `AGENTS.md` 学習ループ原則, `context/growth-loop.md`, `context/infrastructure.md` 知識サイクル現状 | なし |
| ALM研究 | ALM, Adaptive Lookback Momentum, ALM四神, ALM忍法, l1_alm_wf_engine, WF | `/mnt/c/Python_app/DM-signal/docs/research/alm-integration-design.md`, `context/gunshi-alm-38metrics-design.md`, `context/robustness-verification-catalog.md` | `L566` ALM吸収はシン吸収と異なりメトリクスが変わる(helpful_count:3) |
| 四神設計 | 四神, シン四神, L0, pf_stage_shijin, WF四神, 12体 | `context/dm-signal-core.md` §PFレイヤー, `context/checklist-shin-v2-registration.md`, `context/l3-robustness.md` §WF四神 | なし |
| 編成管理 | 編成, hensei, モデル編成, CLI切替, respawn, settings.yaml | `config/settings.yaml`, `context/infrastructure.md` CLIモデル指定とコンテキスト, `skills/shogun-all-codex-switch/SKILL.md` | なし |
| Visibility Tier制マスク | visibility, Visibility Settings, vis_L2, vis_L3, vis_L4, hide_signal, hide_components, hide_portfolio, Tier, 料金プラン, マスク | `/mnt/c/Python_app/DM-signal/backend/app/services/masking_service.py`, `/mnt/c/Python_app/DM-signal/backend/app/services/visibility_helpers.py`, `/mnt/c/Python_app/DM-signal/backend/app/services/page_visibility.py` | なし |
| 将軍Androidアプリ | Android, アプリ, モバイル, Kotlin, APK, com.shogun.android, 将軍アプリ | `android/`, `android/app/build.gradle.kts`, `android/app/src/main/java/com/shogun/android/` | なし |
| CDP(ブラウザ操作能力) | CDP, Chrome DevTools Protocol, ブラウザ操作, スクショ確認, 本番表示確認, cdp_cli, cdp_helper | `context/cdp-philosophy.md`, `scripts/cdp/cdp_cli.sh`, `scripts/cdp/cdp_server.py` | `memory/deepdive_why_chain_20260321.md` Phase 4 想像するな確認せよ |
| 防御階層原則(Level 1-5) | 防御階層, defense_level, Level5, Level 5, 事前コンテキスト提供, 入口側生成, 入口改善, ゲート不要化, 発火しないシステム, LG010, research tool explicit偽陽性修正 ACパス自動提案 Level5化, 放置タスク滞留検出 BLOCK昇格をstartup gateに追加 Level5化, 否定的前提主張の反証grep強制 LG033 Level5化, 教訓件数WARN閾値を31件に引き下げ Level5化, cmd間依存の明示強制 LS A14 Level5化, gate hook追加cmd検出時に既存強制フロー候補を自動表示 LG032 Level5化 | `context/growth-loop.md` §11, `projects/infra/lessons_gunshi.yaml` LG010, `instructions/gunshi.md` §Review Criteria 5.5 | なし |
