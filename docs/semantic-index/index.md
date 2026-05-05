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
| aliases | セマンティック辞書, セマンティクスインデックス, 意味検索, 概念索引 |

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

## cdp_browser_capability — CDP(ブラウザ操作能力)

| 属性 | 値 |
|------|---|
| id | cdp_browser_capability |
| label | CDP(ブラウザ操作能力) |
| aliases | CDP, Chrome DevTools Protocol, ブラウザ操作, スクショ確認, 本番表示確認, cdp_cli, cdp_helper |

| 種別 | パス/参照 |
|------|----------|
| file | `MEMORY.md` §Technical Knowledge → CDP Browser Automation |
| file | `scripts/cdp/cdp_cli.sh` |
| file | `scripts/cdp/cdp_server.py` |
| file | `scripts/cdp/cdp_helper.py` |
| file | `/mnt/c/Python_app/auto-ops/cdp/cdp_helper.py` |
| file | `context/dm-signal-ops.md` §DM-Signal本番FE CDP確認手順 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-05T21:25 CDPの本質=LLMが人間同様にWebブラウザを使える能力 |
| lesson | `memory/deepdive_why_chain_20260321.md` Phase 4 想像するな確認せよ |

### 原理(殿定義 2026-05-05)

**CDPの本質 = LLMが人間と同じようにWebブラウザを使えること。**

1. ブラウザが閉じていれば開く(preflight_cdp_flow: 隔離プロファイル自動起動)
2. ログインが必要なサイトにはログインする(ui_login/cookie注入)
3. スクショを撮って目で見て状況を確認する(screenshot+画像認識)

人間がブラウザで確認するのと同じ行為をLLMが行う。APIレスポンスやコード確認ではなく、**ユーザーが実際に見る画面**を確認する。

**各論ではなく原理:** FE変更確認はこの能力の一応用例。任意のWebサイトの状態確認、ログイン、操作に汎用的に使える。PJ固有の認証方法はPJのcontextに書く。
| cmd | `cmd_2579` 実装 — CDP汎用ブラウザ操作スキル(ブラウザ起動+ログイン+スクショで状況確認) (`skills/cdp-browse/SKILL.md`) |

