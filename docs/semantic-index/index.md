---
codd:
  type: semantic-index
  propagates_to:
    - context/semantic-map.md
---

# セマンティクスインデックス SSOT

<!-- created: 2026-05-04 | parent_cmd: cmd_2562 -->
<!-- scope: multi-agent-shogun conceptual reverse index -->

## recalculate_pipeline — 再計算パイプライン

| 属性 | 値 |
|------|---|
| id | recalculate_pipeline |
| label | 再計算パイプライン |
| aliases | fullrecalculate, recalc, 再計算フロー, recalculate_fast |

| 種別 | パス/参照 |
|------|----------|
| file | `/mnt/c/Python_app/DM-signal/backend/app/jobs/recalculate_fast.py` |
| file | `context/dm-signal-core.md` §19.2 |
| file | `docs/research/fullrecalculate-architecture-2026-03-28.md` |
| discussion | `queue/lord_conversation.jsonl` 2026-05-04T15:11 fullrecalculate 3566s→480s |
| discussion | `queue/lord_conversation.jsonl` 2026-05-05T14:29:03+09:00 正しいfullrecalculateの仕方は知識もない？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-05T15:02 fullrecalculate deploy後トリガー+完了確認 |
| cmd | `cmd_2573` 修正 — drawdowns.py limit撤廃(全DD格納)+fullrecalculate+パリティ検証 |
| lesson | `L714` recalculate-sync acceptedでは完了判定にしない |
| lesson | `L715` recalculate-sync acceptedは完了ではない。DB recalculation_status confirmed必須 |

## semantic_dictionary_design — セマンティック辞書構想

| 属性 | 値 |
|------|---|
| id | semantic_dictionary_design |
| label | セマンティック辞書構想 |
| aliases | セマンティック辞書, セマンティクスインデックス, 意味検索, 概念索引, セマンティクスインデックス候補除外精度, セマンティクスインデックス成長ループ構築 ノイズ除外 aliases自動拡張 参照切れ修正, セマンティクスインデックスaliases照合をcmd品質ゲートに接続 Level5化 |

| 種別 | パス/参照 |
|------|----------|
| file | `docs/research/semantic_index_design.md` |
| file | `context/lord-conversation-index.md` |
| file | `scripts/semantic_map_generate.sh` |
| discussion | `queue/lord_conversation.jsonl` 2026-05-04T20:10 セマンティック辞書と単語定義辞書 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-04T23:42 aliases照合+LLM照合 |
| cmd | `cmd_2563` セマンティック検索+鮮度gate実装 |
| cmd | `cmd_2564` セマンティックインデックス更新hook実装 |
| cmd | `cmd_2565` セマンティック検索LLMフォールバック実装 |
| cmd | `cmd_2566` セマンティックインデックス伝搬(CoDD propagate)実装 |
| cmd | `cmd_2567` セマンティックインデックス鮮度gate+導線埋込み |
| cmd | `cmd_2609` セマンティクスインデックス候補除外精度 |
| cmd | `cmd_2609` 修正 — セマンティクスインデックス成長ループ構築(ノイズ除外+aliases自動拡張+参照切れ修正) (`context/semantic-map.md`, `docs/semantic-index/index.md`) |
| cmd | `cmd_2620` 強化 — セマンティクスインデックスaliases照合をcmd品質ゲートに接続(Level5化) (`scripts/cmd_save.sh`, `tests/unit/test_cmd_save_semantic_index.bats`) |

## gate_bypass_prevention — gate迂回防止

| 属性 | 値 |
|------|---|
| id | gate_bypass_prevention |
| label | gate迂回防止 |
| aliases | gate迂回, 滑り坂, 正規フロー, cmd_delegate |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/cmd_delegate.sh` |
| file | `.claude/hooks/pre-bash-combined.sh` |
| deepdive | `memory/deepdive_causal_tracing_20260415.md` Phase 6 |
| lesson | `docs/research/lessons_shogun_v1_archive.md` LS049-LS052 |

## terminology_dictionary — 用語辞書

| 属性 | 値 |
|------|---|
| id | terminology_dictionary |
| label | 用語辞書 |
| aliases | disambiguation, terminology, 曖昧性解消, 1語1意味, MECE定義辞書 |

| 種別 | パス/参照 |
|------|----------|
| file | `/mnt/c/Python_app/DM-signal/docs/knowledge-base/terminology/disambiguation.md` |
| file | `/mnt/c/Python_app/DM-signal/context/dm-signal-terminology.md` |
| file | `docs/research/cmd_2555_disambiguation_design.md` |
| discussion | `queue/lord_conversation.jsonl` 2026-05-04T19:41 用語辞書について進めていこう |
| cmd | `cmd_2572` 修正 — UWP三指標の用語辞書登録(disambiguation.md+terminology.md) |

## production_parity — 本番パリティ

| 属性 | 値 |
|------|---|
| id | production_parity |
| label | 本番パリティ |
| aliases | パリティ検証, GS-本番パリティ, holding_signal, monthly_returns, golden data |

| 種別 | パス/参照 |
|------|----------|
| file | `context/dm-signal-core.md` §19.3 |
| file | `context/checklist-shin-v2-registration.md` |
| file | `docs/research/dmsignal_parity_verification_audit.md` |
| lesson | `context/dm-signal-core.md` L088-L129 |
| lesson | `L717` 追加ベンチマークはticker_monthly_returnsだけでなくprices fallbackを確認せよ |

## deepdive_principles — deepdive原理

| 属性 | 値 |
|------|---|
| id | deepdive_principles |
| label | deepdive原理 |
| aliases | deepdive, 追体験, why_chain, causal_tracing, 自動化×強制 |

| 種別 | パス/参照 |
|------|----------|
| deepdive | `memory/deepdive_why_chain_20260321.md` |
| deepdive | `memory/deepdive_causal_tracing_20260415.md` |
| deepdive | `memory/deepdive_karo_verification_20260405.md` |
| file | `context/training-cycle.md` |

## growth_loop — 学習ループ

| 属性 | 値 |
|------|---|
| id | growth_loop |
| label | 学習ループ |
| aliases | 学習ループ, 成長ループ, 二値計測, 知見還流, ラルフループ, 三層学習ループ |

| 種別 | パス/参照 |
|------|----------|
| file | `AGENTS.md` 学習ループ原則 |
| file | `context/growth-loop.md` |
| file | `context/infrastructure.md` 知識サイクル現状 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-04T08:57 三層ループALERT対策 |

## alm_research — ALM研究

| 属性 | 値 |
|------|---|
| id | alm_research |
| label | ALM研究 |
| aliases | ALM, Adaptive Lookback Momentum, ALM四神, ALM忍法, l1_alm_wf_engine, WF |

| 種別 | パス/参照 |
|------|----------|
| file | `/mnt/c/Python_app/DM-signal/docs/research/alm-integration-design.md` |
| file | `context/gunshi-alm-38metrics-design.md` |
| file | `context/robustness-verification-catalog.md` |
| discussion | `queue/lord_conversation.jsonl` 2026-05-04T15:11 ALM再構築 |
| lesson | `L566` ALM吸収はシン吸収と異なりメトリクスが変わる(helpful_count:3) |

## shin_shijin_design — 四神設計

| 属性 | 値 |
|------|---|
| id | shin_shijin_design |
| label | 四神設計 |
| aliases | 四神, シン四神, L0, pf_stage_shijin, WF四神, 12体 |

| 種別 | パス/参照 |
|------|----------|
| file | `context/dm-signal-core.md` §PFレイヤー |
| file | `context/checklist-shin-v2-registration.md` |
| file | `context/l3-robustness.md` §WF四神 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-04T16:46 L0は12体でシン四神 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-05T23:49:01+09:00 Average UWPとPTUについてnote記事を書きたい。SPY、TQQQ、Ave-X,劇薬DMオリジナル、とシン四神から特徴的な2体、シン忍法から特徴的な2体を選んで比較した記事を書きたい。まずは構成だけ考えよう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-05T23:55:13+09:00 シン忍法とシン四神からはPTU最強から1体、Average UWP最強から1体選ばないか？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-07T17:18:08+09:00 では記事を書いて。ベーシックはお試しプラン。standardは募集停止となったお得なプラン、アドオンもすでに募集停止となったスタンダードプランのアドオン。新しいスタンダードプランはシン四神を中心としたもの。プレミアムは特別な非公開プラン。限 |

## agent_formation_management — 編成管理

| 属性 | 値 |
|------|---|
| id | agent_formation_management |
| label | 編成管理 |
| aliases | 編成, hensei, モデル編成, CLI切替, respawn, settings.yaml |

| 種別 | パス/参照 |
|------|----------|
| file | `config/settings.yaml` |
| file | `context/infrastructure.md` CLIモデル指定とコンテキスト |
| file | `skills/shogun-all-codex-switch/SKILL.md` |
| file | `skills/shogun-peacetime-rollback/SKILL.md` |

## visibility_tier_masking — Visibility Tier制マスク

| 属性 | 値 |
|------|---|
| id | visibility_tier_masking |
| label | Visibility Tier制マスク |
| aliases | visibility, Visibility Settings, vis_L2, vis_L3, vis_L4, hide_signal, hide_components, hide_portfolio, Tier, 料金プラン, マスク |

| 種別 | パス/参照 |
|------|----------|
| file | `/mnt/c/Python_app/DM-signal/backend/app/services/masking_service.py` |
| file | `/mnt/c/Python_app/DM-signal/backend/app/services/visibility_helpers.py` |
| file | `/mnt/c/Python_app/DM-signal/backend/app/services/page_visibility.py` |
| file | `/mnt/c/Python_app/DM-signal/frontend/app/admin/visibility/page.tsx` |
| file | `docs/research/cmd_2597_visibility_ui_audit.md` |
| file | `projects/dm-signal.yaml` visibility_philosophy |
| terminology | `/mnt/c/Python_app/DM-signal/docs/knowledge-base/terminology/disambiguation.md` vis_L1-L4 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-07T14:05 Tier=料金プラン、シグナル=最も価値ある情報 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-07T14:09 L4=構成ticker(レシピ)を隠し知的財産保護 |

### ビジネス意図(殿定義 2026-05-07)

**DM-Signal = 保有シグナル＆バックテストビューワー。** Tier = 料金プラン。上位Tierほど多くのPF/シグナルにアクセス。

| Layer | 目的 | ビジネス意図 |
|-------|------|------------|
| vis_L2 | PF存在自体を隠す | このTierでは見せないPFを丸ごと非表示 |
| vis_L3 | 保有シグナルを隠す | バックテスト(餌)は見せて上位Tier誘導 |
| vis_L4 | 構成ticker(レシピ)を隠す | シグナルは公開、戦略の知的財産を保護 |
| cmd | `cmd_2598` 修正 — Monthly Trade vis_L4マスク時position表示バグ(cmd_2451リグレッション) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-07T23:35:09+09:00 You are matching a user query to a semantic index. Query: android Instructions: - Choose up to 3 most related concepts f |
| discussion | `queue/lord_conversation.jsonl` 2026-05-07T23:35:38+09:00 You are matching a user query to a semantic index. Query: アプリ Instructions: - Choose up to 3 most related concepts from  |

## shogun_android_app — 将軍Androidアプリ

| 属性 | 値 |
|------|---|
| id | shogun_android_app |
| label | 将軍Androidアプリ |
| aliases | Android, アプリ, モバイル, Kotlin, APK, com.shogun.android, 将軍アプリ |

| 種別 | パス/参照 |
|------|----------|
| file | `android/` |
| file | `android/app/build.gradle.kts` |
| file | `android/app/src/main/java/com/shogun/android/` |
| file | `context/infrastructure.md` §Android App |
| cmd | `cmd_2602` 環境埋込み — Android/アプリ/モバイルから将軍Androidアプリへ到達可能化 |
| cmd | `cmd_1809-1816,1924,1943,1945,2104` Androidアプリ改修・調査履歴 |
| cmd | `cmd_2602` 強化 — Androidアプリ知識の環境埋込み(セマンティクス+context+CLAUDE.md) (`AGENTS.md`, `CLAUDE.md`, `context/infrastructure.md`) |

## cdp_browser_capability — CDP(ブラウザ操作能力)

| 属性 | 値 |
|------|---|
| id | cdp_browser_capability |
| label | CDP(ブラウザ操作能力) |
| aliases | CDP, Chrome DevTools Protocol, ブラウザ操作, スクショ確認, 本番表示確認, cdp_cli, cdp_helper |

| 種別 | パス/参照 |
|------|----------|
| file | `context/cdp-philosophy.md` |
| file | `scripts/cdp/cdp_cli.sh` |
| file | `scripts/cdp/cdp_server.py` |
| file | `scripts/cdp/cdp_helper.py` |
| file | `/mnt/c/Python_app/auto-ops/cdp/cdp_helper.py` |
| file | `context/dm-signal-ops.md` §DM-Signal本番FE CDP確認手順 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-05T21:25 CDPの本質=LLMが人間同様にWebブラウザを使える能力 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-06T00:10 CDPスキル磨き指示(前セッション対話全文読め) |
| cmd | `cmd_2583` CDPスキルSKILL.mdに6つの罠(remote-allow-origins/nativeInputValueSetter/port9234等)追記 |
| cmd | `cmd_2592` cdp-browseスキル磨き(gate FAIL修正+allowed-tools+note実績+能動指針) |
| lesson | `memory/deepdive_why_chain_20260321.md` Phase 4 想像するな確認せよ |

### 原理(殿定義 2026-05-05)

**CDPの本質 = LLMが人間と同じようにWebブラウザを使えること。**

1. ブラウザが閉じていれば開く(preflight_cdp_flow: 隔離プロファイル自動起動)
2. ログインが必要なサイトにはログインする(ui_login/cookie注入)
3. スクショを撮って目で見て状況を確認する(screenshot+画像認識)

人間がブラウザで確認するのと同じ行為をLLMが行う。APIレスポンスやコード確認ではなく、**ユーザーが実際に見る画面**を確認する。

**各論ではなく原理:** FE変更確認はこの能力の一応用例。任意のWebサイトの状態確認、ログイン、操作に汎用的に使える。PJ固有の認証方法はPJのcontextに書く。
| cmd | `cmd_2579` 実装 — CDP汎用ブラウザ操作スキル(ブラウザ起動+ログイン+スクショで状況確認) (`skills/cdp-browse/SKILL.md`) |

## defense_hierarchy — 防御階層原則

| 属性 | 値 |
|------|---|
| id | defense_hierarchy |
| label | 防御階層原則(Level 1-5) |
| aliases | 防御階層, defense_level, Level5, Level 5, 事前コンテキスト提供, 入口側生成, 入口改善, ゲート不要化, 発火しないシステム, LG010, research tool explicit偽陽性修正 ACパス自動提案 Level5化, 放置タスク滞留検出 BLOCK昇格をstartup gateに追加 Level5化 |

| 種別 | パス/参照 |
|------|----------|
| file | `context/growth-loop.md` §11 |
| file | `projects/infra/lessons_gunshi.yaml` LG010 |
| file | `instructions/gunshi.md` §Review Criteria 5.5 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-09 殿「BLOCKされないように成長する=主軸。ゲートを通すのは枝葉」 |
| cmd | `cmd_2616` q11 WARN→BLOCK昇格(Level 4) |
| cmd | `cmd_2617` preflight q11自動grep(Level 5) |
| cmd | `cmd_2618` 未自動化教訓18件Level 5化計画(偵察) |
| cmd | `cmd_2619` research_tool_explicit FP修正+ACパス自動提案(Level 5) |

### 5段階定義(殿定義 2026-05-09)

| Level | 名称 | 本質 |
|-------|------|------|
| 1 | 事後検出 | 間違えた後にgateが検出 |
| 2 | 事前予防(doc) | ドキュメントに「こうせよ」と記載 |
| 3 | 事前強制(auto-gen) | テンプレート自動生成で正しい構造を強制 |
| 4 | フロー内BLOCK | 間違ったら即停止 |
| 5 | 事前コンテキスト提供 | 正しい入力を自動生成して渡す。間違える余地がない |

**Level 1-4 = 間違えてから止める。Level 5 = 間違える前に正しい答えを渡す。**
**ゲートの成功 = 未熟さの証拠。発火しないシステムが完成系。**
計測指標: Level 4:Level 5比率。2026-05-09時点 = 28:3。
| cmd | `cmd_2619` 強化 — research_tool_explicit偽陽性修正+ACパス自動提案(Level5化) (`scripts/cmd_save.sh`, `tests/unit/test_cmd_save_research_tool_explicit.bats`) |
| cmd | `cmd_2621` 強化 — 放置タスク滞留検出+BLOCK昇格をstartup gateに追加(Level5化) (`scripts/gates/gate_shogun_startup.sh`, `tests/unit/test_gate_shogun_startup.bats`) |

