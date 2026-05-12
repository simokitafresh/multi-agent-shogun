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
| セマンティック辞書構想 | セマンティック辞書, セマンティクスインデックス, 意味検索, 概念索引, セマンティクスインデックス候補除外精度, セマンティクスインデックス成長ループ構築 ノイズ除外 aliases自動拡張 参照切れ修正, セマンティクスインデックスaliases照合をcmd品質ゲートに接続 Level5化, 今回の知識は, セマンティック辞書やインデックスに追加すべき内容を確認せよ, セマンティクスインデックスにL6化セッションの成果を反映 | `docs/research/semantic_index_design.md`, `context/lord-conversation-index.md`, `scripts/semantic_map_generate.sh` | なし |
| gate迂回防止 | gate迂回, 滑り坂, 正規フロー, cmd_delegate | `scripts/cmd_delegate.sh`, `.claude/hooks/pre-bash-combined.sh`, `scripts/gates/gate_report_format.sh` 報告YAML品質gate | `memory/deepdive_causal_tracing_20260415.md` Phase 6, `docs/research/lessons_shogun_v1_archive.md` LS049-LS052 |
| 用語辞書 | disambiguation, terminology, 曖昧性解消, 1語1意味, MECE定義辞書 | `/mnt/c/Python_app/DM-signal/docs/knowledge-base/terminology/disambiguation.md`, `/mnt/c/Python_app/DM-signal/context/dm-signal-terminology.md`, `docs/research/cmd_2555_disambiguation_design.md` | なし |
| 本番パリティ | パリティ検証, GS-本番パリティ, holding_signal, monthly_returns, golden data | `context/dm-signal-core.md` §19.3, `context/checklist-shin-v2-registration.md`, `docs/research/dmsignal_parity_verification_audit.md` | `context/dm-signal-core.md` L088-L129, `L717` 追加ベンチマークはticker_monthly_returnsだけでなくprices fallbackを確認せよ |
| deepdive原理 | deepdive, 追体験, why_chain, causal_tracing, 自動化×強制 | `context/training-cycle.md` | `memory/deepdive_why_chain_20260321.md`, `memory/deepdive_causal_tracing_20260415.md`, `memory/deepdive_karo_verification_20260405.md` |
| 学習ループ | 学習ループ, 成長ループ, 二値計測, 知見還流, ラルフループ, 三層学習ループ, 教訓統合, lessons_shogun v3統合, 将軍自身の学習ループは順調か？成長しているか？, 学習ループは順調か？, 自動成長ループは順調か？, 適したスキルを無視するのはバグ — TRIGGER条件合致時はSkill tool必須 | `AGENTS.md` 学習ループ原則, `context/growth-loop.md`, `context/infrastructure.md` 知識サイクル現状 | `L597` 適したスキルを無視するのはバグ — TRIGGER条件合致時はSkill tool必須 |
| ALM研究 | ALM, Adaptive Lookback Momentum, ALM四神, ALM忍法, l1_alm_wf_engine, WF, ALMはディスコンだから俺が明示的に言わない限り | `/mnt/c/Python_app/DM-signal/docs/research/alm-integration-design.md`, `context/gunshi-alm-38metrics-design.md`, `context/robustness-verification-catalog.md` | `L566` ALM吸収はシン吸収と異なりメトリクスが変わる(helpful_count:3) |
| 四神設計 | 四神, シン四神, L0, pf_stage_shijin, WF四神, 12体 | `context/dm-signal-core.md` §PFレイヤー, `context/checklist-shin-v2-registration.md`, `context/l3-robustness.md` §WF四神 | なし |
| 編成管理 | 編成, hensei, モデル編成, CLI切替, respawn, settings.yaml, 配備, deploy, deploy_task, 監視, monitor, ninja_monitor, auto-commit, auto-clear, report review受信時にkaro direct配備か通常配備かを確認せよ, 二重配備はstallの判断ミスだろうな, inbox write sh task assigned時の二重配備自動検査, 確かidle判定やstall判定が未熟で | `config/settings.yaml`, `context/infrastructure.md` CLIモデル指定とコンテキスト, `scripts/deploy_task.sh` | `L587` report_review受信時にkaro_direct配備か通常配備かを確認せよ, `L594` deploy_taskからinbox_writeをset -e直下で直接呼ぶと送信失敗が配備後処理全体を中断する, `L602` karo_directのtraining配備はdeploy_task.sh --directを使え。手動YAML方式はAC未注入を引き起こす |
| Visibility Tier制マスク | visibility, Visibility Settings, vis_L2, vis_L3, vis_L4, hide_signal, hide_components, hide_portfolio, Tier, 料金プラン, マスク, tierが課金プランに紐付いているのは理解しているか？, 料金プランとの対応は知識となっているか？, 前にどのtierがどのPFを閲覧できるかまとめたのは覚えているか？, プラン毎に1つ推奨PFを決めてあげると | `/mnt/c/Python_app/DM-signal/backend/app/services/masking_service.py`, `/mnt/c/Python_app/DM-signal/backend/app/services/visibility_helpers.py`, `/mnt/c/Python_app/DM-signal/backend/app/services/page_visibility.py` | なし |
| 将軍Androidアプリ | Android, アプリ, モバイル, Kotlin, APK, com.shogun.android, 将軍アプリ | `android/`, `android/app/build.gradle.kts`, `android/app/src/main/java/com/shogun/android/` | なし |
| CDP(ブラウザ操作能力) | CDP, Chrome DevTools Protocol, ブラウザ操作, スクショ確認, 本番表示確認, cdp_cli, cdp_helper, CDPでこのページを確認すると知識を得られるはずだ | `context/cdp-philosophy.md`, `scripts/cdp/cdp_cli.sh`, `scripts/cdp/cdp_server.py` | `memory/deepdive_why_chain_20260321.md` Phase 4 想像するな確認せよ |
| 防御階層原則(Level 1-6) | 防御階層, defense_level, Level5, Level 5, Level6, Level 6, 学習速度最大化, 下限切り上げ, ラチェット, 事前コンテキスト提供, 入口側生成, 入口改善, ゲート不要化, 発火しないシステム, FAIL→PASS遷移率, L6化率, gate_fire_log解析, LG010, ninja_weak_points, previous_failures, 修行サイクル, research tool explicit偽陽性修正 ACパス自動提案 Level5化, 放置タスク滞留検出 BLOCK昇格をstartup gateに追加 Level5化, 否定的前提主張の反証grep強制 LG033 Level5化, 教訓件数WARN閾値を31件に引き下げ Level5化, cmd間依存の明示強制 LS A14 Level5化, gate hook追加cmd検出時に既存強制フロー候補を自動表示 LG032 Level5化, 計測 見積cmdにタイムボックス欄を自動要求 LG019 Level5化, AC command内の数値リテラルに再計算元表示を自動提案 LG020 Level5化, AC外作業検出INFO提案 LS A08 Level5化, 時間コスト関連cmdに環境差異欄を自動要求 LS A10 Level5化, gate vercel phase壊れ参照検出時に修正候補を自動提案 Level5化, Level1止まりgate6件に修正候補自動提案を追加 Level5化一括, ac param sufficiency WARN時にcontext projects yamlから候補値を自動提案 L | `context/growth-loop.md` §11, `projects/infra/lessons_gunshi.yaml` LG010, `instructions/gunshi.md` §Review Criteria 5.5 | なし |
| Tier-プラン対応 | tier, Tier, 料金プラン, プラン, plan, subscription, メンバーシップ, membership, viewer_tiers, Basic, Standard, NewStandard, AddOn, premium, ベーシック, スタンダード, アドオン, プレミアム, 古参スペシャル, 劇薬DM, ドクタープレミアム, 特にビジネスプランの話を今後するときにスムーズにやりたいな | `projects/dm-signal.yaml` tier_plan_mapping, `/mnt/c/Python_app/DM-signal/marketing-director/content/articles/note-tier-portfolio-guide.md`, `/mnt/c/Python_app/DM-signal/marketing-director/content/articles/note-premium-yotsume-gekiyaku.md` | なし |
| α6指標 | α6指標, alpha 6, 6指標α, alpha metrics, CAGR, NHF, MaxDD, MRU, Calmar, Avg UWP, ソルティノ, Sortino | `projects/dm-signal.yaml` alpha_6_metrics, `context/l3-robustness.md` L299, `context/robustness-verification-catalog.md` | なし |
