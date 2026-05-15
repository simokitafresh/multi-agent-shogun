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
| skills | db-check |

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
| aliases | セマンティック辞書, セマンティクスインデックス, 意味検索, 概念索引, セマンティクスインデックス候補除外精度, セマンティクスインデックス成長ループ構築 ノイズ除外 aliases自動拡張 参照切れ修正, セマンティクスインデックスaliases照合をcmd品質ゲートに接続 Level5化, 今回の知識は, セマンティック辞書やインデックスに追加すべき内容を確認せよ, セマンティクスインデックスにL6化セッションの成果を反映, ではrebalancerの概要を教えてくれ, スキルTRIGGER照合をproject文脈対応 セマンティック辞書棚卸し, セマンティック辞書に未登録5概念を追加（暗黒物質可視化Phase ） |
| skills | なし |

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
| discussion | `queue/lord_conversation.jsonl` 2026-05-11T00:06:00+09:00 今回の知識は、クリア後も利用できるようにしよう。セマンティック辞書も更新してくれ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-11T02:40:15+09:00 セマンティック辞書やインデックスに追加すべき内容を確認せよ |
| cmd | `cmd_2679` セマンティクスインデックスにL6化セッションの成果を反映。defense_hierarchyとgrowth_loopにaliases+cmd参照を追加し、semantic_map_generate.shで伝搬する (`context/semantic-map.md`, `docs/semantic-index/index.md`) |
| cmd | `cmd_2690` 修正 — semantic-index file参照12件のDM-Signal外部パスを現行パスとして検証し、semantic_map_generate.shで再生成 (`docs/semantic-index/index.md`, `context/semantic-map.md`) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-14T16:45:43+09:00 ではrebalancerの概要を教えてくれ。セマンティック辞書にも登録しよう |
| cmd | `cmd_2739` 改善 — スキルTRIGGER照合をproject文脈対応+セマンティック辞書棚卸し (`scripts/hooks/prompt_state_inject.sh`, `skills/cdp-browse/SKILL.md`, `skills/codd/SKILL.md`) |
| cmd | `cmd_2776` 強化 — セマンティック辞書に未登録5概念を追加（暗黒物質可視化Phase 1） (`context/semantic-map.md`, `docs/semantic-index/index.md`) |

## codd_methodology — CoDD整合性駆動開発

| 属性 | 値 |
|------|---|
| id | codd_methodology |
| label | CoDD整合性駆動開発 |
| aliases | CoDD, Coherence-Driven Development, 整合性駆動開発, Harness Engineering, lexicon, elicit, phenomenon, PHENOMENON, codd fix, codd fix PHENOMENON, dag verify, dag-verify, auto-repair, brownfield, coherence-engine, coverage report, codd v2, v2.18.0, task notification task id btp9xyne3 task id tool use id tool, CoDDの効果は順調か？, なぜなぜ7回, 掲示板にCoDDの修行の話はなかったか？, codd yaml scan設定をリポジトリ構造に一致させhealth score 0を解消 |
| skills | codd, codd-refactor |

| 種別 | パス/参照 |
|------|----------|
| file | `context/codd.md` |
| file | `memory/reference_codd_oshio_articles.md` |
| file | `skills/codd/SKILL.md` |
| file | `skills/codd-refactor/SKILL.md` |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T11:57:14+09:00 CoDD v2.18.0 アップデート完了 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T12:02:18+09:00 CoDDを有効活用するための準備はできているか？ |
| cmd | `cmd_2760` CoDD v1.10.0時点の知識体系をv2.18.0に更新 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T20:31:24+09:00 by90fvbya toolu_01AsvZsDxzg3e4Xth1fevzM1 /tmp/claude-1000/-mnt-c-tools-multi-agent-shogun/23e2871c-af99-4a8b-a8c5-af194a |
| cmd | `cmd_2780` 強化 — Simple-OCRリポジトリ全体のCoDD brownfield設計書逆生成 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T03:24:18+09:00 なぜなぜ7回。CoDDできちんとやろう。品質は下げない。現在の出力は合格点だ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T07:27:25+09:00 掲示板にCoDDの修行の話はなかったか？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T07:29:14+09:00 CoDDのdoc_dirs設定整理が必要について、なぜなぜ7回。改善しよう |
| cmd | `cmd_2796` codd.yaml scan設定をリポジトリ構造に一致させhealth_score 0を解消 (`codd/codd.yaml`, `codd/scan/edges.jsonl`) |

## gate_bypass_prevention — gate迂回防止

| 属性 | 値 |
|------|---|
| id | gate_bypass_prevention |
| label | gate迂回防止 |
| aliases | gate迂回, 滑り坂, 正規フロー, cmd_delegate |
| skills | report-write, verdict-check |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/cmd_delegate.sh` |
| file | `.claude/hooks/pre-bash-combined.sh` |
| deepdive | `memory/deepdive_causal_tracing_20260415.md` Phase 6 |
| lesson | `docs/research/lessons_shogun_v1_archive.md` LS049-LS052 |
| file | `scripts/gates/gate_report_format.sh` 報告YAML品質gate |
| file | `scripts/gates/gate_report_format_main.py` 報告YAML検証エンジン |
| file | `scripts/report_field_set.sh` 報告YAML安全書込み(gate迂回防止) |

## terminology_dictionary — 用語辞書

| 属性 | 値 |
|------|---|
| id | terminology_dictionary |
| label | 用語辞書 |
| aliases | disambiguation, terminology, 曖昧性解消, 1語1意味, MECE定義辞書 |
| skills | なし |

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
| skills | db-check, pf-registration |

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
| skills | なし |

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
| aliases | 学習ループ, 成長ループ, 二値計測, 知見還流, ラルフループ, 三層学習ループ, 教訓統合, lessons_shogun v3統合, 将軍自身の学習ループは順調か？成長しているか？, 学習ループは順調か？, 自動成長ループは順調か？, 適したスキルを無視するのはバグ — TRIGGER条件合致時はSkill tool必須, 自動成長ループが構造的に阻害されている場所はないか？, 同様のコード修正までが一気通貫していないせいで, 今回のBLOCKで何を学習して, BLOCK後に環境埋込み判定を強制（自動成長ループ完結） |
| skills | lesson-sort, review-bundle, gate-sync, idle-persist |

| 種別 | パス/参照 |
|------|----------|
| file | `AGENTS.md` 学習ループ原則 |
| file | `context/growth-loop.md` |
| file | `context/infrastructure.md` 知識サイクル現状 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-04T08:57 三層ループALERT対策 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-10T15:18:24+09:00 将軍自身の学習ループは順調か？成長しているか？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-10T17:00:36+09:00 学習ループは順調か？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-10T17:46:10+09:00 自動成長ループは順調か？ |
| lesson | `L597` 適したスキルを無視するのはバグ — TRIGGER条件合致時はSkill tool必須 |
| file | `scripts/gates/gate_cycle_health.sh` 三層学習ループ健全性計測 |
| file | `scripts/karo_workaround_log.sh` WA記録(成績表フィードバック) |
| file | `scripts/ci_status_check.sh` CI状態チェック(品質フィードバック) |
| cmd | `cmd_2672` 教訓統合 — lessons_shogun v3統合 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-11T21:24:08+09:00 われらの軍のシステムをまとめるとどうなるのかな？三層学習ループ、セマンティックインデックス、レベル6、deepdiveなどかなり特徴があるよな。 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-12T13:58:42+09:00 自動成長ループが構造的に阻害されている場所はないか？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T09:10:02+09:00 スキルの自動成長ループは順調か？構造的な問題はないか？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T09:35:51+09:00 同様のコード修正までが一気通貫していないせいで、自動成長ループが構造的に阻害されているものがないか確認しよう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T09:50:13+09:00 三層学習ループに同様の構造的な阻害がないか確認しよう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T15:13:59+09:00 今回のBLOCKで何を学習して、クリアされても次回BLOCKされないために実際にどう自動成長した？自動成長できていないのならインフラバグか自動成長ループの仕組を修正するべきだ。 |
| cmd | `cmd_2779` 強化 — BLOCK後に環境埋込み判定を強制（自動成長ループ完結） (`scripts/cmd_save.sh`, `tests/unit/test_cmd_save_prev_cmd_lesson_warn.bats`) |

## alm_research — ALM研究

| 属性 | 値 |
|------|---|
| id | alm_research |
| label | ALM研究 |
| aliases | ALM, Adaptive Lookback Momentum, ALM四神, ALM忍法, l1_alm_wf_engine, WF, ALMはディスコンだから俺が明示的に言わない限り |
| skills | pf-registration, db-check |

| 種別 | パス/参照 |
|------|----------|
| file | `/mnt/c/Python_app/DM-signal/docs/research/alm-integration-design.md` |
| file | `context/gunshi-alm-38metrics-design.md` |
| file | `context/robustness-verification-catalog.md` |
| discussion | `queue/lord_conversation.jsonl` 2026-05-04T15:11 ALM再構築 |
| lesson | `L566` ALM吸収はシン吸収と異なりメトリクスが変わる(helpful_count:3) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-10T22:36:14+09:00 ALMはディスコンだから俺が明示的に言わない限り、話題に絶対出すな |

## shin_shijin_design — 四神設計

| 属性 | 値 |
|------|---|
| id | shin_shijin_design |
| label | 四神設計 |
| aliases | 四神, シン四神, L0, pf_stage_shijin, WF四神, 12体, step2のクライアントIDは取得した |
| skills | pf-registration, db-check |

| 種別 | パス/参照 |
|------|----------|
| file | `context/dm-signal-core.md` §PFレイヤー |
| file | `context/checklist-shin-v2-registration.md` |
| file | `context/l3-robustness.md` §WF四神 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-04T16:46 L0は12体でシン四神 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-05T23:49:01+09:00 Average UWPとPTUについてnote記事を書きたい。SPY、TQQQ、Ave-X,劇薬DMオリジナル、とシン四神から特徴的な2体、シン忍法から特徴的な2体を選んで比較した記事を書きたい。まずは構成だけ考えよう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-05T23:55:13+09:00 シン忍法とシン四神からはPTU最強から1体、Average UWP最強から1体選ばないか？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-07T17:18:08+09:00 では記事を書いて。ベーシックはお試しプラン。standardは募集停止となったお得なプラン、アドオンもすでに募集停止となったスタンダードプランのアドオン。新しいスタンダードプランはシン四神を中心としたもの。プレミアムは特別な非公開プラン。限 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-14T20:55:37+09:00 step2のクライアントIDは取得した。1020628824992-30qnh5airgml0vhqljh6nkrflo0dvcuk.apps.googleusercontent.com |

## gs_ninpo_research — GS忍法研究

| 属性 | 値 |
|------|---|
| id | gs_ninpo_research |
| label | GS忍法研究 |
| aliases | 忍法GS, GS忍法, グリッドサーチ忍法, run_077, 奥義GS, 忍法研究, GS高速化, パリティ完全一致, gs_engine, bunshin, oikaze, nukimi, kawarimi, kasoku, yotsume |
| skills | gs-bench-gate |

| 種別 | パス/参照 |
|------|----------|
| file | `context/gs-speedup-knowledge.md` |
| file | `context/gunshi-gs-speed-optimization-design.md` |
| file | `context/gunshi-gs-landscape-analysis.md` |
| file | `docs/research/gs-speedup-details.md` |
| file | `docs/research/gs-results-by-ninjutsu.md` |
| file | `docs/research/gunshi_nazenaze7_gs_speedup_20260414.md` |
| file | `scripts/oneshot/wf_profile.py` |
| file | `scripts/gates/gate_artifact_map.sh` |
| cmd | `cmd_2776` セマンティック辞書5概念追加 |

## silent_fallback_quality — Silent Fallback品質

| 属性 | 値 |
|------|---|
| id | silent_fallback_quality |
| label | Silent Fallback品質 |
| aliases | silent fallback, Silent Fallback, サイレントフォールバック, 無言フォールバック, Cash fallback, SPY fallback, fail-open, fail-closed, PI-018, gate_silent_fallback, データ偽装, fallback品質 |
| skills | なし |

| 種別 | パス/参照 |
|------|----------|
| file | `context/gunshi-silent-fallback-analysis.md` |
| file | `scripts/gates/gate_silent_fallback.sh` |
| file | `scripts/gates/gate_gunshi_cs_checklist.sh` |
| file | `scripts/gates/gate_gunshi_report_precheck.sh` |
| file | `scripts/gates/gate_gunshi_report_precheck_engine.py` |
| file | `context/dm-signal-core.md` |
| file | `context/dm-signal-ops.md` |
| cmd | `cmd_2776` セマンティック辞書5概念追加 |

## skill_design_rules — Skill設計ルール

| 属性 | 値 |
|------|---|
| id | skill_design_rules |
| label | Skill設計ルール |
| aliases | skill design, skill-design, スキル設計, SKILL.md, description 1024, What When NOT When, trigger設計, 誤発火防止, allowed-tools, skill creator, スキルTRIGGER, SKILL md 3件をscript変更に追従更新（3セッション連続WARN解消）, gate lesson health sh PHANTOM検出awk偽陽性修正 SKILL md 3件追従更新 |
| skills | skill-creator, skill-installer |

| 種別 | パス/参照 |
|------|----------|
| file | `context/skill-design-rules.md` |
| file | `docs/research/dream-skill-design.md` |
| file | `context/codd.md` |
| file | `skills/codd/SKILL.md` |
| file | `skills/codd-refactor/SKILL.md` |
| file | `skills/reset-layout/SKILL.md` |
| file | `skills/pf-registration/SKILL.md` |
| file | `docs/research/gstack-gbrain-skillify-2026-04.md` |
| cmd | `cmd_2739` スキルTRIGGER照合をproject文脈対応+セマンティック辞書棚卸し |
| cmd | `cmd_2776` セマンティック辞書5概念追加 |
| cmd | `cmd_2785` 強化 — SKILL.md 3件をscript変更に追従更新（3セッション連続WARN解消） (`skills/dream/SKILL.md`, `skills/gate-sync/SKILL.md`, `skills/idle-persist/SKILL.md`) |
| cmd | `cmd_2793` gate_lesson_health.sh PHANTOM検出awk偽陽性修正 + SKILL.md 3件追従更新 (`skills/dream/SKILL.md`, `skills/karo-direct/SKILL.md`, `skills/shogun-teire/SKILL.md`) |

## dmsignal_operations — DM-Signal運用

| 属性 | 値 |
|------|---|
| id | dmsignal_operations |
| label | DM-Signal運用 |
| aliases | DM-Signal運用, dm-signal ops, dmsignal ops, Render運用, 本番運用, recalculate運用, ETL運用, DB操作, PF登録, CDP確認, sync-standard, sync-fof, Render CLI |
| skills | db-check, pf-registration, cdp-browse |

| 種別 | パス/参照 |
|------|----------|
| file | `context/dm-signal.md` |
| file | `context/dm-signal-ops.md` |
| file | `context/dm-signal-core.md` |
| file | `context/dm-signal-frontend.md` |
| file | `context/dm-signal-research.md` |
| file | `context/checklist-shin-v2-registration.md` |
| file | `context/checklist-alm-registration.md` |
| file | `docs/research/ops-procedures.md` |
| file | `docs/research/ops-db-rules.md` |
| file | `docs/operations/daemon_runbook.md` |
| file | `docs/operations/profiling_runbook.md` |
| cmd | `cmd_2776` セマンティック辞書5概念追加 |

## google_classroom — Google Classroom Dashboard

| 属性 | 値 |
|------|---|
| id | google_classroom |
| label | Google Classroom Dashboard |
| aliases | Google Classroom, google classroom, Classroom, Classroom Dashboard, グーグルクラスルーム, classroom scraper, Classroomスクレイピング, auto_login, scrape_classroom |
| skills | なし |

| 種別 | パス/参照 |
|------|----------|
| file | `context/google-classroom.md` |
| file | `config/projects.yaml` google-classroom |
| file | `/mnt/c/Python_app/google_classroom` |
| file | `/mnt/c/Python_app/google_classroom/scripts/auto_login.py` |
| file | `/mnt/c/Python_app/google_classroom/scripts/scrape_classroom.py` |
| file | `/mnt/c/Python_app/google_classroom/server.py` |
| cmd | `cmd_2776` セマンティック辞書5概念追加 |

## agent_formation_management — 編成管理

| 属性 | 値 |
|------|---|
| id | agent_formation_management |
| label | 編成管理 |
| aliases | 編成, hensei, モデル編成, CLI切替, respawn, settings.yaml, 配備, deploy, deploy_task, 監視, monitor, ninja_monitor, auto-commit, auto-clear, report review受信時にkaro direct配備か通常配備かを確認せよ, 二重配備はstallの判断ミスだろうな, inbox write sh task assigned時の二重配備自動検査, 確かidle判定やstall判定が未熟で, task notification task id brdydjwk3 task id tool use id tool, task notification task id b1fseli4u task id tool use id tool, GATE BLOCK FAIL時の家老自動通知 再配備提案を追加 |
| skills | hensei, hensei-mixed, hensei-opus, karo-direct, recon-dual, reset-layout, shogun-all-codex-switch, shogun-peacetime-rollback, switch-to-codex, switch-to-opus |

| 種別 | パス/参照 |
|------|----------|
| file | `config/settings.yaml` |
| file | `context/infrastructure.md` CLIモデル指定とコンテキスト |
| file | `scripts/deploy_task.sh` |
| file | `scripts/ninja_monitor.sh` |
| file | `skills/shogun-all-codex-switch/SKILL.md` |
| file | `skills/shogun-peacetime-rollback/SKILL.md` |
| cmd | `cmd_2640` (`scripts/ninja_monitor.sh`, `tests/unit/test_ninja_monitor_stall.bats`) |
| cmd | `cmd_2644` 強化 — チェックリスト隣接Step自動注入(LG012 Level5化) (`queue/tasks/kotaro.yaml`, `scripts/deploy_task.sh`) |
| cmd | `cmd_2650` 強化 — deploy_task.shにcontext自動注入を一括追加(堅牢性カタログ/GS知見/用語辞書/修行サイクル) (`scripts/deploy_task.sh`, `tests/helpers/deploy_task_scaffold.bash`, `tests/unit/test_deploy_task_lifecycle.bats`) |
| cmd | `cmd_2649` 強化 — growth-loop防御階層を忍者タスクYAMLに自動注入 (`scripts/deploy_task.sh`, `tests/unit/test_deploy_task_growth_loop_defense.bats`) |
| lesson | `L587` report_review受信時にkaro_direct配備か通常配備かを確認せよ |
| cmd | `cmd_2659` 修正 — draft review SKIP根治(AC overwriteソース不在時fallback) (`tests/unit/test_deploy_task_lifecycle.bats`) |
| cmd | `cmd_2665` 修正 — lesson関連BLOCK根治(deploy_task.shデフォルト値prefill) (`scripts/deploy_task.sh`, `tests/unit/test_deploy_task_template_generation.bats`) |
| lesson | `L594` deploy_taskからinbox_writeをset -e直下で直接呼ぶと送信失敗が配備後処理全体を中断する |
| file | `scripts/hooks/stop_check_inbox.sh` Stop hook(Claude Code専用。Codex非対応) |
| file | `.codex/hooks.json` Codex hook設定(Stopなし。PreToolUse/PostToolUseのみ) |
| docs | `docs/research/gunshi_idle_codex_hook_analysis_20260511.md` Codex Stop hook撤去分析 |
| cmd | `cmd_karo_lk004_inbox_fix` (`tests/unit/test_deploy_task.bats`) |
| cmd | `cmd_karo_ci_fix_safe_inbox_test` (`tests/unit/test_deploy_task.bats`) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-12T01:05:43+09:00 二重配備はstallの判断ミスだろうな。家老の能力を上げるべきか仕組みを考えるべきか。なぜなぜ7回 |
| cmd | `cmd_2681` 強化 — deploy_task.sh二重配備ガードのレース条件修正+完了報告検知 (`queue/tasks/hayate.yaml`, `scripts/deploy_task.sh`, `tests/unit/test_deploy_task_lifecycle.bats`) |
| cmd | `cmd_2682` 強化 — ninja_monitor先行完了検知で後発忍者をauto-void (`scripts/ninja_monitor.sh`, `tests/unit/test_ninja_monitor_stall.bats`) |
| cmd | `cmd_2684` 強化 — inbox_write.sh task_assigned時の二重配備自動検査 (`scripts/inbox_write.sh`, `tests/unit/test_inbox_write.bats`) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-12T11:39:01+09:00 確かidle判定やstall判定が未熟で、すぐにninjyamonitorが/clearを送信→作業中にstartup再実行で無駄な重複が多かったからだった記憶がある |
| lesson | `L602` karo_directのtraining配備はdeploy_task.sh --directを使え。手動YAML方式はAC未注入を引き起こす |
| cmd | `cmd_2691` 修正 — karo_direct修行配備でAC/description未注入の修正 (`skills/karo-direct/SKILL.md`, `tests/unit/test_deploy_task.bats`) |
| lesson | `L603` karo_directのtraining配備はdeploy_task.sh --directを使え(手動YAML禁止) |
| cmd | `cmd_2693` 修正 — karo_direct配備のstale_report根因修正(reset_stale_fields相当追加) (`skills/karo-direct/SKILL.md`, `tests/unit/test_deploy_task_lifecycle.bats`) |
| cmd | `cmd_2694` 修正 — watcher起動時のASW_DISABLE_ESCALATION継承汚染を構造的に遮断 (`scripts/ninja_monitor.sh`, `scripts/restart_watchers.sh`, `tests/unit/test_inbox_watcher_health.bats`) |
| cmd | `cmd_2696` 強化 — 修行L4テンプレートに教訓参照ACを追加(参照率0%解消) (`scripts/deploy_task.sh`, `tests/unit/test_deploy_task.bats`) |
| cmd | `cmd_2695` 強化 — withheld悪循環の解消(MIN_SAMPLES未満教訓の初回注入保証) (`scripts/deploy_task.sh`, `tests/unit/test_deploy_task_ac_handling.bats`) |
| cmd | `cmd_2699` 修正 — draft_review SKIP: karo_direct配備時のac_countカウント修正 (`tests/unit/test_deploy_task_draft_review.bats`) |
| cmd | `cmd_2700` (`scripts/deploy_task.sh`, `tests/unit/test_deploy_task_ac_handling.bats`) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-14T21:41:57+09:00 brdydjwk3 toolu_01YSsdUNnkY3gBfM9r47hmEH /tmp/claude-1000/-mnt-c-tools-multi-agent-shogun/7142d797-600b-40f5-9c3d-85c755 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-14T21:43:04+09:00 b1fseli4u toolu_01TFhAEeMFFB8R8Hk6KbNrMW /tmp/claude-1000/-mnt-c-tools-multi-agent-shogun/7142d797-600b-40f5-9c3d-85c755 |
| cmd | `cmd_2734` 強化 — セマンティクスインデックスにスキル推奨列を追加し忍者タスクに自動注入 (`context/semantic-map.md`, `docs/semantic-index/index.md`, `scripts/deploy_task.sh`) |
| cmd | `cmd_2737` (`scripts/deploy_task.sh`, `scripts/gates/gate_karo_startup.sh`, `tests/helpers/deploy_task_scaffold.bash`) |
| cmd | `cmd_2746` 偵察 — deploy_task.sh配備後inbox未配信の根因調査 |
| cmd | `cmd_2754` 強化 — ninja_monitorに修行サイクル自動トリガーを追加 (`scripts/ninja_monitor.sh`) |
| cmd | `cmd_2755` 強化 — FAIL→PASS遷移率の定期計測をninja_monitorに追加 (`scripts/ninja_monitor.sh`) |
| cmd | `cmd_2757` 強化 — 教訓定期棄却の自動トリガーをninja_monitorに追加 (`scripts/lesson_deprecation_scan.sh`, `scripts/ninja_monitor.sh`, `tests/unit/test_lesson_deprecation_scan.bats`) |
| cmd | `cmd_2789` (`queue/tasks/hayate.yaml`, `tests/unit/test_deploy_task_draft_review.bats`) |
| lesson | `L613` deploy_task.sh: STKのac_assignedはinject関数で明示転記が必要 |
| cmd | `cmd_2790` 強化 — deploy_task.sh ac_assigned導入でbc注入範囲を担当ACに限定 (`scripts/deploy_task.sh`, `tests/helpers/deploy_task_scaffold.bash`, `tests/unit/test_deploy_task_ac_handling.bats`) |

## visibility_tier_masking — Visibility Tier制マスク

| 属性 | 値 |
|------|---|
| id | visibility_tier_masking |
| label | Visibility Tier制マスク |
| aliases | visibility, Visibility Settings, vis_L2, vis_L3, vis_L4, hide_signal, hide_components, hide_portfolio, Tier, 料金プラン, マスク, tierが課金プランに紐付いているのは理解しているか？, 料金プランとの対応は知識となっているか？, 前にどのtierがどのPFを閲覧できるかまとめたのは覚えているか？, プラン毎に1つ推奨PFを決めてあげると |
| skills | cdp-browse |

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
| discussion | `queue/lord_conversation.jsonl` 2026-05-10T18:07:04+09:00 tierが課金プランに紐付いているのは理解しているか？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-10T18:07:57+09:00 料金プランとの対応は知識となっているか？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-10T20:11:30+09:00 前にどのtierがどのPFを閲覧できるかまとめたのは覚えているか？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-10T20:13:43+09:00 プラン毎に1つ推奨PFを決めてあげると、メンバーは理解しやすい。理解しやすければ継続して課金してくれる。ビジネスモデルとして推奨PFがtier=plan毎に必要だ |

## shogun_android_app — 将軍Androidアプリ

| 属性 | 値 |
|------|---|
| id | shogun_android_app |
| label | 将軍Androidアプリ |
| aliases | Android, アプリ, モバイル, Kotlin, APK, com.shogun.android, 将軍アプリ, このアプリはGoogleで確認されていません」警告が出ても利用はできるよな？, モバイルレスポンシブ崩れ修正 ヘッダー テーブル 銘柄リスト, モバイルポートフォリオ入力をコンパクト横並び1行 銘柄に再設計, このアプリは原則的にお薬手帳用に開発した |
| skills | cdp-browse |

| 種別 | パス/参照 |
|------|----------|
| file | `android/` |
| file | `android/app/build.gradle.kts` |
| file | `android/app/src/main/java/com/shogun/android/` |
| file | `context/infrastructure.md` §Android App |
| cmd | `cmd_2602` 環境埋込み — Android/アプリ/モバイルから将軍Androidアプリへ到達可能化 |
| cmd | `cmd_1809-1816,1924,1943,1945,2104` Androidアプリ改修・調査履歴 |
| cmd | `cmd_2602` 強化 — Androidアプリ知識の環境埋込み(セマンティクス+context+CLAUDE.md) (`AGENTS.md`, `CLAUDE.md`, `context/infrastructure.md`) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-14T22:56:42+09:00 このアプリはGoogleで確認されていません」警告が出ても利用はできるよな？ |
| cmd | `cmd_2729` 修正 — モバイルレスポンシブ崩れ修正(ヘッダー+テーブル+銘柄リスト) |
| cmd | `cmd_2740` 修正 — モバイルポートフォリオ入力をコンパクト横並び1行/銘柄に再設計 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T23:25:57+09:00 このアプリは原則的にお薬手帳用に開発した。inbox2 |

## cdp_browser_capability — CDP(ブラウザ操作能力)

| 属性 | 値 |
|------|---|
| id | cdp_browser_capability |
| label | CDP(ブラウザ操作能力) |
| aliases | CDP, Chrome DevTools Protocol, ブラウザ操作, スクショ確認, 本番表示確認, cdp_cli, cdp_helper, CDPでこのページを確認すると知識を得られるはずだ, 完了したらCDPで確認しておいて, 続けて, task notification task id b0syhe3ag task id tool use id tool, task notification task id baa9kjrve task id tool use id tool, task notification task id bayxsdn2u task id tool use id tool, 毎回CDPのスキルを未使用とする例が多くてトラブルになることがある |
| skills | cdp-browse |

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
| cmd | `cmd_2642` 強化 — CDP本番確認をcmd完了フローに自動接続(FE変更時スクショ確認) (`scripts/cmd_complete_gate.sh`, `tests/unit/test_cmd_complete_gate.bats`) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-10T18:09:07+09:00 CDPでこのページを確認すると知識を得られるはずだ。https://note.com/membership/settings/manage |
| discussion | `queue/lord_conversation.jsonl` 2026-05-14T18:30:26+09:00 完了したらCDPで確認しておいて |
| discussion | `queue/lord_conversation.jsonl` 2026-05-14T19:48:59+09:00 続けて。CDPはスキルあるからスキル使うように。デプロイ済みか確認した？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-14T20:02:55+09:00 b0syhe3ag toolu_01LJWS89qVgHTT174GX6zi7S /tmp/claude-1000/-mnt-c-tools-multi-agent-shogun/7142d797-600b-40f5-9c3d-85c755 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-14T21:36:18+09:00 baa9kjrve toolu_01U5nU664haAHLzy196ras4u /tmp/claude-1000/-mnt-c-tools-multi-agent-shogun/7142d797-600b-40f5-9c3d-85c755 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-14T22:17:06+09:00 bayxsdn2u toolu_016qWPcnUxCj4Ym1yCHar8q7 /tmp/claude-1000/-mnt-c-tools-multi-agent-shogun/7142d797-600b-40f5-9c3d-85c755 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-14T23:46:50+09:00 続けて |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T00:03:29+09:00 毎回CDPのスキルを未使用とする例が多くてトラブルになることがある。DB-checkなどのスキルを実行しようとすることもあるな |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T22:56:22+09:00 続けて |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T23:06:43+09:00 続けて |

## defense_hierarchy — 防御階層原則

| 属性 | 値 |
|------|---|
| id | defense_hierarchy |
| label | 防御階層原則(Level 1-6) |
| aliases | 防御階層, defense_level, Level5, Level 5, Level6, Level 6, 学習速度最大化, 下限切り上げ, ラチェット, 事前コンテキスト提供, 入口側生成, 入口改善, ゲート不要化, 発火しないシステム, FAIL→PASS遷移率, L6化率, gate_fire_log解析, LG010, ninja_weak_points, previous_failures, 修行サイクル, research tool explicit偽陽性修正 ACパス自動提案 Level5化, 放置タスク滞留検出 BLOCK昇格をstartup gateに追加 Level5化, 否定的前提主張の反証grep強制 LG033 Level5化, 教訓件数WARN閾値を31件に引き下げ Level5化, cmd間依存の明示強制 LS A14 Level5化, gate hook追加cmd検出時に既存強制フロー候補を自動表示 LG032 Level5化, 計測 見積cmdにタイムボックス欄を自動要求 LG019 Level5化, AC command内の数値リテラルに再計算元表示を自動提案 LG020 Level5化, AC外作業検出INFO提案 LS A08 Level5化, 時間コスト関連cmdに環境差異欄を自動要求 LS A10 Level5化, gate vercel phase壊れ参照検出時に修正候補を自動提案 Level5化, Level1止まりgate6件に修正候補自動提案を追加 Level5化一括, ac param sufficiency WARN時にcontext projects yamlから候補値を自動提案 L |
| skills | なし |

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
| cmd | `cmd_2673` gate_context_freshness L1→L5化(stale TOP3自動提案) |
| cmd | `cmd_2668` L6追跡 |
| cmd | `cmd_2674` enforcement_audit L5化 |
| cmd | `cmd_2675` knowledge_freshness L5化 |
| cmd | `cmd_2676` wa_data_quality L5化 |
| file | `scripts/gates/gate_context_freshness.sh` L5到達(cmd_2673) |

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
| cmd | `cmd_2624` 強化 — 否定的前提主張の反証grep強制(LG033 Level5化) |
| cmd | `cmd_karo_level5_report_format` (`instructions/ashigaru-procedures.md`) |
| cmd | `cmd_karo_level5_bc_fail` (`instructions/ashigaru.md`, `instructions/generated/ashigaru.md`, `instructions/generated/claude-ashigaru.md`) |
| cmd | `cmd_2625` 強化 — 教訓件数WARN閾値を31件に引き下げ(Level5化) |
| cmd | `cmd_2627` 強化 — cmd間依存の明示強制(LS-A14 Level5化) (`scripts/cmd_save.sh`, `tests/unit/test_cmd_save_block_aggregation.bats`, `tests/unit/test_cmd_save_command_steps_vs_ac.bats`) |
| cmd | `cmd_2628` 強化 — gate/hook追加cmd検出時に既存強制フロー候補を自動表示(LG032 Level5化) (`scripts/cmd_save.sh`, `tests/unit/test_cmd_save.bats`) |
| cmd | `cmd_2630` 強化 — 計測/見積cmdにタイムボックス欄を自動要求(LG019 Level5化) |
| cmd | `cmd_2629` 強化 — AC/command内の数値リテラルに再計算元表示を自動提案(LG020 Level5化) (`scripts/cmd_save.sh`, `tests/unit/test_cmd_save.bats`) |
| cmd | `cmd_2631` 強化 — AC外作業検出INFO提案(LS-A08 Level5化) |
| cmd | `cmd_2634` 強化 — 時間コスト関連cmdに環境差異欄を自動要求(LS-A10 Level5化) (`scripts/cmd_save.sh`, `tests/unit/test_cmd_save.bats`) |
| cmd | `cmd_2638` 強化 — gate_vercel_phase壊れ参照検出時に修正候補を自動提案(Level5化) (`scripts/gates/gate_vercel_phase.sh`, `tests/unit/test_gate_vercel_phase.bats`) |
| cmd | `cmd_2643` 強化 — Level1止まりgate6件に修正候補自動提案を追加(Level5化一括) (`scripts/gates/gate_knowledge_freshness.sh`, `scripts/gates/gate_p_average_freshness.sh`, `scripts/gates/gate_silent_fallback.sh`) |
| cmd | `cmd_2651` 強化 — ac_param_sufficiency WARN時にcontext/projects.yamlから候補値を自動提案(Level5化) (`scripts/cmd_save.sh`, `tests/unit/test_cmd_save_warn_logging.bats`) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-11T02:40:48+09:00 You are matching a user query to a semantic index. Query: L6 学習速度 Instructions: - Choose up to 3 most related concepts f |
| discussion | `queue/lord_conversation.jsonl` 2026-05-12T12:55:59+09:00 You are matching a user query to a semantic index. Query: drift Instructions: - Choose up to 3 most related concepts fro |

## tier_plan_mapping — Tier-プラン対応

| 属性 | 値 |
|------|---|
| id | tier_plan_mapping |
| label | Tier-プラン対応 |
| aliases | tier, Tier, 料金プラン, プラン, plan, subscription, メンバーシップ, membership, viewer_tiers, Basic, Standard, NewStandard, AddOn, premium, ベーシック, スタンダード, アドオン, プレミアム, 古参スペシャル, 劇薬DM, ドクタープレミアム, 特にビジネスプランの話を今後するときにスムーズにやりたいな |
| skills | note-writer, cdp-browse |

| 種別 | パス/参照 |
|------|----------|
| file | `projects/dm-signal.yaml` tier_plan_mapping |
| file | `/mnt/c/Python_app/DM-signal/marketing-director/content/articles/note-tier-portfolio-guide.md` |
| file | `/mnt/c/Python_app/DM-signal/marketing-director/content/articles/note-premium-yotsume-gekiyaku.md` |
| file | `/mnt/c/Python_app/DM-signal/marketing-director/content/articles/note-standard-bunshin-avex.md` |
| file | `/mnt/c/Python_app/DM-signal/marketing-director/content/articles/note-basic-dual-momentum.md` |
| discussion | `queue/lord_conversation.jsonl` 2026-05-10 tier=料金プラン対応表確定(殿裁定) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-11T00:09:31+09:00 特にビジネスプランの話を今後するときにスムーズにやりたいな |

## alpha_6_metrics — α6指標

| 属性 | 値 |
|------|---|
| id | alpha_6_metrics |
| label | α6指標 |
| aliases | α6指標, alpha 6, 6指標α, alpha metrics, CAGR, NHF, MaxDD, MRU, Calmar, Avg UWP, ソルティノ, Sortino |
| skills | なし |

| 種別 | パス/参照 |
|------|----------|
| file | `projects/dm-signal.yaml` alpha_6_metrics |
| file | `context/l3-robustness.md` L299 |
| file | `context/robustness-verification-catalog.md` |
| discussion | `queue/lord_conversation.jsonl` 2026-05-10 UWP→Avg UWP変更(殿裁定) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-10 Sharpe→Sortino(殿: 上方ボラを罰するSharpeは好まない) |

## rebalancer_app — Rebalancerアプリ

| 属性 | 値 |
|------|---|
| id | rebalancer_app |
| label | Rebalancerアプリ |
| aliases | rebalancer, リバランス, リバランサー, Portfolio Rebalance App, dm-rebalancer, ポートフォリオリバランス, なるほど, アイデア出しをしよう, Project URL と anon keyは envで保存しておかなくていいのか？rebalancer内においておけば, C \Python app\rebalancer\frontend\ env local, リバランサーのスマホ画面でのレスポンシブ対応が完了していないようだ, リバランサーのスマホ画面だが, リバランサーのGoogleOauthはもう誰でも利用できる？ |
| skills | cdp-browse |

| 種別 | パス/参照 |
|------|----------|
| file | `projects/rebalancer.yaml` |
| file | `config/projects.yaml` rebalancer項目 |
| file | `/mnt/c/Python_app/rebalancer/backend/app/main.py` FastAPI entrypoint |
| file | `/mnt/c/Python_app/rebalancer/backend/app/config.py` 追跡銘柄18種定義 |
| file | `/mnt/c/Python_app/rebalancer/frontend/` Next.js 15 static export |
| file | `/mnt/c/Python_app/rebalancer/render.yaml` Render blueprint(Singapore) |
| file | `/mnt/c/Python_app/rebalancer/docs/research/cmd_2702_rebalancer_recon_summary.md` 万全偵察結果24件 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-14T12:45:20+09:00 このプロジェクトの改良に取り掛かる予定 |
| cmd | `cmd_2701` PJ登録(rebalancer) |
| cmd | `cmd_2702` 万全偵察(P0:3/P1:8/P2:13=24件) |
| cmd | `cmd_2705`-`cmd_2721` P0全3+P1全8+P2全6=改良21cmd |
| discussion | `queue/lord_conversation.jsonl` 2026-05-14T16:59:34+09:00 なるほど。それはリバランサー用のデザイン.mdだな。我らの軍に基本的なデザインルールがあるはずだ。確認してくれ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-14T20:06:52+09:00 アイデア出しをしよう。ログイン機能をつけたいな。前回の保有PFが保存できればリバランスが容易になる。 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-14T20:23:15+09:00 Project URL と anon keyは.envで保存しておかなくていいのか？rebalancer内においておけば便利では？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-14T20:37:45+09:00 C:\Python_app\rebalancer\frontend\.env.local |
| discussion | `queue/lord_conversation.jsonl` 2026-05-14T22:53:24+09:00 https://dm-rebalancer-frontend.onrender.com/guideは最新のコードと整合性が取れているか？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-14T23:56:47+09:00 リバランサーのスマホ画面でのレスポンシブ対応が完了していないようだ。確認して |
| cmd | `cmd_karo_ci_fix_rebalancer_audit` |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T02:18:51+09:00 リバランサーのスマホ画面だが、縦に長くカードが邪魔で一覧性を著しく損なっているな。デザインのUXが極端に悪い。まずは考えよう |
| cmd | `cmd_karo_rebalancer_push` |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T03:15:53+09:00 リバランサーのGoogleOauthはもう誰でも利用できる？ |
| cmd | `cmd_karo_rebalancer_push_2` |

## simple_ocr — Simple OCR（画像OCR Webアプリ）

| 属性 | 値 |
|------|---|
| id | simple_ocr |
| label | Simple OCR（画像OCR Webアプリ） |
| aliases | Simple-OCR, OCR, お薬手帳, 薬手帳OCR, Google Vision, Claude Vision, GPT Vision, OCRエンジン切替, two_stage, Stage 1.5, schedule検出, 構造化JSON, グルーピング, 横向き画像, ブロックフィルタ, prompt caching, Flask-SocketIO, QRコード連携, PC受信モード, スタンドアロンOCR, 除外パターン, exclusion_manager |
| skills | なし |

| 種別 | パス/参照 |
|------|----------|
| file | `projects/simple-ocr.yaml` |
| file | `projects/simple-ocr.yaml` |
| file | `/mnt/c/Python_app/Simple-OCR/ocr_engines.py` 5エンジン+Stage 1.5+Stage 3(650行) |
| file | `/mnt/c/Python_app/Simple-OCR/docs/two_stage_prompt_v3.txt` Stage 2プロンプト(スキーマ+ルール) |
| file | `/mnt/c/Python_app/Simple-OCR/tests/test_two_stage_prompt.py` 6サンプル×3回安定性テスト |
| file | `/mnt/c/Python_app/Simple-OCR/app.py` Flask+SocketIOエントリーポイント(デフォルト=two_stage) |
| file | `/mnt/c/Python_app/Simple-OCR/exclusion_manager.py` OCR結果除外パターン管理 |
| file | `/mnt/c/Python_app/Simple-OCR/docs/ocr-engine-switching-design.md` 設計書(コスト実測+全パイプライン) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T20:00:56+09:00 Simple-OCRを確認して。新しいプロジェクトだ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T20:06:43+09:00 お薬手帳のOCR精度が悪い。なにかいいアイデアはあるか？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T20:08:16+09:00 Claude VisionのコストとGPTを比較したい |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T20:11:38+09:00 切り替え可能にできるか？設計書作りが必要だ |
| cmd | `cmd_2780` Simple-OCR CoDD brownfield設計書逆生成 |
| cmd | `cmd_2781` 実装 — Simple-OCR OCRエンジン切替Phase 1-3（抽象化+3エンジン実装） |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T21:23:13+09:00 先にローカルで3エンジンの実際のOCR精度を試す |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T21:35:19+09:00 すくなくとも圧倒的にgoogle vision APIが優秀だな |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T21:41:51+09:00 https://github.com/ndl-lab/ndlocr-liteに役に立つ情報はないか？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T21:49:18+09:00 bqq5mjmxs toolu_01JLqHJC32Bq2EtNXo6VfzbB /tmp/claude-1000/-mnt-c-tools-multi-agent-shogun/23e2871c-af99-4a8b-a8c5-af194a |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T21:51:53+09:00 ほかのAPIも使ってみたいな。google visionAPiににたAPIはないのか？ |
| cmd | `cmd_2782` 実装 — Simple-OCR 座標付き二段構えOCRパイプライン（Google DOCUMENT_TEXT_DETECTION + Claude Haiku構造化） |
| cmd | `cmd_karo_ci_fix_simple_ocr_rebase` |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T23:12:17+09:00 ではsimple-OCRにもどろう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T23:17:51+09:00 よい。お薬手帳特有の整形は別レイヤーでやろう。もとのシステムでは別レイヤーでやっていた |
| cmd | `cmd_2787` 修正 — two-stage OCRプロンプトをレイアウト忠実復元に限定（お薬手帳解釈を分離） |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T23:29:40+09:00 exclusion_managerのskipは意図的にやっただろ？知識がすべて抜けているな |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T01:03:11+09:00 番号欠落は1の方針でよい。続けよう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T01:19:04+09:00 schedulだな。日本のお薬手帳の特徴は、グループの一番下に用法容量などが記載されている。これがグループ分けのヒントになると思う |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T02:33:10+09:00 サンプルを増やしてみよう。'/mnt/c/Users/simok/OneDrive/画像/スクリーンショット/お薬手帳サンプル/20250523_141641.jpg' '/mnt/c/Users/simok/OneDrive/画像/スクリ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T02:35:50+09:00 まず自分で丁寧に読み込んでみよう。C:\Python_app\Simple-OCR\testsに画像をコピーすることから始めたらどうだ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T02:42:37+09:00 '/mnt/c/Users/simok/OneDrive/画像/スクリーンショット/お薬手帳サンプル/20250524_141003.jpg' '/mnt/c/Users/simok/OneDrive/画像/スクリーンショット/お薬手帳サン |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T03:11:43+09:00 simple-OCRに問題を見つけた。用法が「分3」などを理解せずに「3」だけが残っている。平山トミ 令和7年1月11日 塩島内科医院 Dr.塩島俊也 アジスロマイシン錠500mg「トーワ」 1 朝食後服用 3日分 ツムラ麦門冬湯エキス顆粒 |

## kj_partshift — KJ Partshift Checker（シフト見える化MVP）

| 属性 | 値 |
|------|---|
| id | kj_partshift |
| label | KJ Partshift Checker（シフト見える化MVP） |
| aliases | kj-partshift, partshift, シフト見える化, シフト管理, パートシフト, 休診日, HTMX, 楽観ロック, メンバーマージ |
| skills | なし |

| 種別 | パス/参照 |
|------|----------|
| file | `projects/kj-partshift.yaml` |
| file | `/mnt/c/Python_app/kj-partshift-checker/app/` FastAPI+Jinja2+HTMX |
| file | `/mnt/c/Python_app/kj-partshift-checker/architecture.md` アーキテクチャ設計書 |
| file | `/mnt/c/Python_app/kj-partshift-checker/future-001.md` 将来の修正候補リスト(F014-F042) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T18:40:17+09:00 kj-partshift-checkerを読み込んで |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T18:43:28+09:00 このプロジェクトを登録して |

## destructive_operations — 破壊的操作安全機構

| 属性 | 値 |
|------|---|
| id | destructive_operations |
| label | 破壊的操作安全機構 |
| aliases | 破壊的操作, D001-D009, lord_approval, force push, reset --hard, git clean, Tier1, Tier2 |
| skills | なし |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/hooks/pre_bash_combined_guard.sh` 殿承認確認Guard(D010) |
| file | `tests/test_pre_bash_destructive_approval.bats` 破壊的操作テスト |
| file | `CLAUDE.md` Destructive Operation Safety (Tier1/Tier2/Tier3) |
| cmd | `cmd_2784` 破壊的操作の前に殿の明示的承認確認をpre-bash hookに追加 |
| lesson | `LK-A01 v6` 破壊的操作はremote現状確認+lord_conversation確認必須 |
