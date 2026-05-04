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
| 再計算パイプライン | fullrecalculate, recalc, 再計算フロー, recalculate_fast | `/mnt/c/Python_app/DM-signal/backend/app/jobs/recalculate_fast.py`, `context/dm-signal-core.md` §19.2, `docs/research/fullrecalculate-architecture-2026-03-28.md` | なし |
| セマンティック辞書構想 | セマンティック辞書, セマンティクスインデックス, 意味検索, 概念索引 | `docs/research/semantic_index_design.md`, `context/lord-conversation-index.md`, `scripts/semantic_map_generate.sh` | なし |
| gate迂回防止 | gate迂回, 滑り坂, 正規フロー, cmd_delegate | `scripts/cmd_delegate.sh`, `scripts/pre-bash-combined.sh` | `memory/deepdive_causal_tracing_20260415.md` Phase 6, `docs/research/lessons_shogun_v1_archive.md` LS049-LS052 |
| 用語辞書 | disambiguation, terminology, 曖昧性解消, 1語1意味, MECE定義辞書 | `/mnt/c/Python_app/DM-signal/docs/knowledge-base/terminology/disambiguation.md`, `/mnt/c/Python_app/DM-signal/context/dm-signal-terminology.md`, `docs/research/cmd_2555_disambiguation_design.md` | なし |
| 本番パリティ | パリティ検証, GS-本番パリティ, holding_signal, monthly_returns, golden data | `context/dm-signal-core.md` §19.3, `context/checklist-shin-v2-registration.md`, `docs/research/dmsignal_parity_verification_audit.md` | `context/dm-signal-core.md` L088-L129 |
| deepdive原理 | deepdive, 追体験, why_chain, causal_tracing, 自動化×強制 | `context/training-cycle.md` | `memory/deepdive_why_chain_20260321.md`, `memory/deepdive_causal_tracing_20260415.md`, `memory/deepdive_karo_verification_20260405.md` |
| 学習ループ | 学習ループ, 成長ループ, 二値計測, 知見還流, ラルフループ, 三層学習ループ | `AGENTS.md` 学習ループ原則, `context/growth-loop.md`, `context/infrastructure.md` 知識サイクル現状 | なし |
| 再計算パイプライン | fullrecalculate, recalc, 再計算フロー, recalculate_fast | `/mnt/c/Python_app/DM-signal/backend/app/jobs/recalculate_fast.py`, `context/dm-signal-core.md` §19.2, `docs/research/fullrecalculate-architecture-2026-03-28.md` | なし |
| セマンティック辞書構想 | セマンティック辞書, セマンティクスインデックス, 意味検索, 概念索引 | `docs/research/semantic_index_design.md`, `context/lord-conversation-index.md`, `scripts/semantic_map_generate.sh` | なし |
| gate迂回防止 | gate迂回, 滑り坂, 正規フロー, cmd_delegate | `scripts/cmd_delegate.sh`, `scripts/pre-bash-combined.sh` | `memory/deepdive_causal_tracing_20260415.md` Phase 6, `docs/research/lessons_shogun_v1_archive.md` LS049-LS052 |
| 用語辞書 | disambiguation, terminology, 曖昧性解消, 1語1意味, MECE定義辞書 | `/mnt/c/Python_app/DM-signal/docs/knowledge-base/terminology/disambiguation.md`, `/mnt/c/Python_app/DM-signal/context/dm-signal-terminology.md`, `docs/research/cmd_2555_disambiguation_design.md` | なし |
| 本番パリティ | パリティ検証, GS-本番パリティ, holding_signal, monthly_returns, golden data | `context/dm-signal-core.md` §19.3, `context/checklist-shin-v2-registration.md`, `docs/research/dmsignal_parity_verification_audit.md` | `context/dm-signal-core.md` L088-L129 |
| deepdive原理 | deepdive, 追体験, why_chain, causal_tracing, 自動化×強制 | `context/training-cycle.md` | `memory/deepdive_why_chain_20260321.md`, `memory/deepdive_causal_tracing_20260415.md`, `memory/deepdive_karo_verification_20260405.md` |
| 学習ループ | 学習ループ, 成長ループ, 二値計測, 知見還流, ラルフループ, 三層学習ループ | `AGENTS.md` 学習ループ原則, `context/growth-loop.md`, `context/infrastructure.md` 知識サイクル現状 | なし |
| ALM研究 | ALM, Adaptive Lookback Momentum, ALM四神, ALM忍法, l1_alm_wf_engine, WF | `/mnt/c/Python_app/DM-signal/docs/research/alm-integration-design.md`, `context/gunshi-alm-38metrics-design.md`, `context/robustness-verification-catalog.md` | なし |
| 四神設計 | 四神, シン四神, L0, pf_stage_shijin, WF四神, 12体 | `context/dm-signal-core.md` §PFレイヤー, `context/checklist-shin-v2-registration.md`, `context/l3-robustness.md` §WF四神 | なし |
| 編成管理 | 編成, hensei, モデル編成, CLI切替, respawn, settings.yaml | `config/settings.yaml`, `context/infrastructure.md` CLIモデル指定とコンテキスト, `skills/shogun-all-codex-switch/SKILL.md` | なし |
| ALM研究 | ALM, Adaptive Lookback Momentum, ALM四神, ALM忍法, l1_alm_wf_engine, WF | `/mnt/c/Python_app/DM-signal/docs/research/alm-integration-design.md`, `context/gunshi-alm-38metrics-design.md`, `context/robustness-verification-catalog.md` | なし |
| 四神設計 | 四神, シン四神, L0, pf_stage_shijin, WF四神, 12体 | `context/dm-signal-core.md` §PFレイヤー, `context/checklist-shin-v2-registration.md`, `context/l3-robustness.md` §WF四神 | なし |
| 編成管理 | 編成, hensei, モデル編成, CLI切替, respawn, settings.yaml | `config/settings.yaml`, `context/infrastructure.md` CLIモデル指定とコンテキスト, `skills/shogun-all-codex-switch/SKILL.md` | なし |
