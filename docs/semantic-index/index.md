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
| cmd | `cmd_2893` 修正 — テスト削除4件+統合6件(偵察cmd_2892結果) (`tests/unit/test_agent_state.bats`, `tests/unit/test_agent_status.bats`, `tests/unit/test_api_usage.bats`) |
| causal | `cmd_2893` origin: [[cmd_2892]] -> [[test_is_debt]] -> [[test_cleanup]] |
| causal | `cmd_2893` depends_on: cmd_2892 |

## semantic_dictionary_design — セマンティック辞書構想

| 属性 | 値 |
|------|---|
| id | semantic_dictionary_design |
| label | セマンティック辞書構想 |
| aliases | セマンティック辞書, セマンティクスインデックス, 意味検索, 概念索引, 概念検索, aliases層, LLMフォールバック, セマンティクスインデックス候補除外精度, セマンティクスインデックス成長ループ構築 ノイズ除外 aliases自動拡張 参照切れ修正, セマンティクスインデックスaliases照合をcmd品質ゲートに接続 Level5化, 辞書育成, semantic index growth, ノイズalias除去, 自然言語alias拡充, 未カバー概念追加, 今回の知識は, セマンティック辞書やインデックスに追加すべき内容を確認せよ, セマンティクスインデックスにL6化セッションの成果を反映, ではrebalancerの概要を教えてくれ, スキルTRIGGER照合をproject文脈対応 セマンティック辞書棚卸し, セマンティック辞書に未登録5概念を追加（暗黒物質可視化Phase ）, ここまでの知識を記憶してセマンティクスインデックスにも保存せよ, obsidian, obsidianは有効活用できてるか？, 真の穴 INS 024911のセマンティック辞書未登録2件は対処すべき, obsidian×セマンティックインデックスの発展について, obsidian×セマンティックスインデックスは順調か？, obsidianのリンクは成長しているか？成長速度が遅くないか？, task notification task id bm5vc6kjt task id tool use id tool, obsidianのリンクが成長しないな, GATE CLEAR時にcmd因果辺をsemantic mapへ自動還流, 2905は送っているか？こういうことにobsidian セマンティックインデックスの仕組みがあるのでは？inbox1, まずやるべきは軍師提案の起票では？セマンティックインデックス×obsidianの複利効果はとてつもなくおおきい, 強化 GATE CLEAR時にoriginノードをセマンティクスインデックスへ自動還流 L7穴3 HOW, concept_auto_growth, 概念自動成長, L7, L7穴3, insight_write, insightsキュー, 気づき保存, L7tohanannda, L7の成長速度を最大化させるために何が必要か？なぜなぜ7回, 強化 L7計測基盤 — semantic searchのNO MATCHログ startup gate表示, L7を確認しよう, 強化 prompt state inject shにsemantic search NO MATCHカウント計測追加, 強化 cmd complete時にpurposeキーワードを既存概念aliasesに自動蓄積 aliases自動成長, 強化 L7ストレステストツール — semantic searchヒット率計測 aliases自動蓄積, そうだな, L7まで貫通させずに, 強化 L7ストレステスト3トリガー自動組込み aliases変更後計測 startup gate表示 idle蓄積, セマンティクスインデックスに埋め込んでるか？, stress_test, ストレステスト, ヒット率計測, hit_rate, NO_MATCH率, semantic_stress_test, aliases自動成長, 自動発火トリガー, 3トリガー, auto_promote, score閾値, L7加速, concept間リンク, related_concepts, 修行aliases鍛錬 |
| skills | なし |

| 種別 | パス/参照 |
|------|----------|
| file | `docs/research/semantic_index_design.md` |
| file | `context/lord-conversation-index.md` |
| file | `scripts/semantic_map_generate.sh` |
| file | `scripts/insight_write.sh` |
| file | `scripts/semantic_index_update.sh` |
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
| discussion | `queue/lord_conversation.jsonl` 2026-05-17T14:17:11+09:00 ここまでの知識を記憶してセマンティクスインデックスにも保存せよ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-17T20:28:24+09:00 obsidian、セマンティック辞書は活用できているか？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T12:35:26+09:00 obsidianは有効活用できてるか？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T12:36:10+09:00 obsidian×セマンティック辞書で可能性が広がると思う。なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T12:41:32+09:00 真の穴: INS-024911のセマンティック辞書未登録2件は対処すべき |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T13:57:03+09:00 obsidian×セマンティックインデックスの発展について、なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T14:01:24+09:00 Obsidian×セマンティック統合パイプライン(因果辺トラバース)の概念自体をセマンティック辞書に追加しよう |
| cmd | `cmd_2874` 強化 — セマンティック辞書ノイズ除去+カバレッジ拡充(辞書育成Phase 2) (`context/semantic-map.md`, `docs/semantic-index/index.md`) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T15:49:36+09:00 obsidian×セマンティックスインデックスは順調か？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T17:08:16+09:00 obsidianのリンクは成長しているか？成長速度が遅くないか？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T17:10:39+09:00 bm5vc6kjt toolu_01UHpBBvAq2dGwh9R2soynjz /tmp/claude-1000/-mnt-c-tools-multi-agent-shogun/23e2871c-af99-4a8b-a8c5-af194a |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T19:47:14+09:00 obsidianのリンクが成長しないな。なにかアイデアはあるか？ |
| cmd | `cmd_2885` 強化 — GATE CLEAR時にcmd因果辺をsemantic-mapへ自動還流 (`scripts/cmd_complete_gate.sh`, `scripts/semantic_index_update.sh`, `scripts/semantic_map_generate.sh`) |
| causal | `cmd_2885` origin: [[cmd_2818_causal_NW]] -> [[semantic_map_generate]] -> [[obsidian_link_stagnation]] |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T18:50:55+09:00 2905は送っているか？こういうことにobsidian+セマンティックインデックスの仕組みがあるのでは？inbox1 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T21:44:00+09:00 まずやるべきは軍師提案の起票では？セマンティックインデックス×obsidianの複利効果はとてつもなくおおきい。L7だよな |
| cmd | `cmd_2910` 強化: GATE CLEAR時にoriginノードをセマンティクスインデックスへ自動還流(L7穴3 HOW) (`scripts/semantic_index_update.sh`, `tests/unit/test_semantic_index_update.bats`) |
| causal | `cmd_2910` origin: [[L7_HOW]] -> [[origin_aliases_gap]] -> [[concept_auto_growth]] |
| cmd | `cmd_2912` 強化: pending概念の自動昇格でセマンティクスインデックスを自動成長(L7f) (`scripts/semantic_index_update.sh`, `tests/unit/test_semantic_index_update.bats`) |
| causal | `cmd_2912` origin: [[L7f_concept_auto_promote]] -> [[pending_insights_22]] -> [[semantic_index_auto_growth]] |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T23:24:55+09:00 L7tohanannda |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T23:29:43+09:00 L7の成長速度を最大化させるために何が必要か？なぜなぜ7回。 |
| cmd | `cmd_2915` 強化: L7計測基盤 — semantic searchのNO_MATCHログ+startup gate表示 (`tests/unit/test_semantic_no_match_metrics.bats`) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-21T00:20:39+09:00 L7を確認しよう |
| cmd | `cmd_2919` 強化: prompt_state_inject.shにsemantic search NO_MATCHカウント計測追加 (`tests/unit/test_session_state_hooks.bats`) |
| causal | `cmd_2919` origin: [[L7_lord_side_blind_spot]] -> [[prompt_state_no_match_silent]] -> [[lord_query_visibility]] |
| cmd | `cmd_2920` 強化: cmd_complete時にpurposeキーワードを既存概念aliasesに自動蓄積(L7 aliases自動成長) (`scripts/semantic_index_update.sh`, `tests/unit/test_semantic_index_update.bats`) |
| causal | `cmd_2920` origin: [[L7_aliases_auto_growth]] -> [[no_match_purpose_keywords]] -> [[aliases_quality_improvement]] |
| cmd | `cmd_2922` 強化: L7ストレステストツール — semantic searchヒット率計測+aliases自動蓄積 (`scripts/semantic_stress_test.sh`, `tests/unit/test_semantic_stress_test.bats`) |
| causal | `cmd_2922` origin: [[L7_growth_speed]] -> [[aliases_quality_bottleneck]] -> [[measurement_tool_absent]] |
| discussion | `queue/lord_conversation.jsonl` 2026-05-21T02:17:34+09:00 そうだな。L1-L7までを貫通させる。いい案だと思う。おまえらは死なないから無限に成長できる。俺ら人間と比べて能力は極端に劣るが、いつか追いこせるだろう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-21T02:19:15+09:00 L1-L7まで貫通させずに、放置しているものはないか？ |
| cmd | `cmd_2924` 強化: L7ストレステスト3トリガー自動組込み(aliases変更後計測+startup gate表示+idle蓄積) (`logs/archive/cmd_design_quality.yaml`, `logs/cmd_design_quality.yaml`, `logs/gunshi_review_log.yaml`) |
| causal | `cmd_2924` origin: [[cmd_2922]] -> [[manual_tool_phase4]] -> [[gunshi_5w1h_3trigger_design]] |
| causal | `cmd_2924` depends_on: cmd_2922 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-21T02:50:21+09:00 セマンティクスインデックスに埋め込んでるか？ |

## codd_methodology — CoDD整合性駆動開発

| 属性 | 値 |
|------|---|
| id | codd_methodology |
| label | CoDD整合性駆動開発 |
| aliases | CoDD, Coherence-Driven Development, 整合性駆動開発, Harness Engineering, lexicon, elicit, phenomenon, PHENOMENON, codd fix, codd fix PHENOMENON, dag verify, dag-verify, auto-repair, brownfield, coherence-engine, coverage report, codd v2, v2.18.0, CoDDの効果は順調か？, なぜなぜ7回, 掲示板にCoDDの修行の話はなかったか？, codd yaml scan設定をリポジトリ構造に一致させhealth score 0を解消, 自立自走 なぜなぜ7回 隠れたインフラ バグを探そう, 自立自走 なぜなぜ7回 続けろ, SKILL md追従7件更新 cmd complete gateにSKILL md追従WARN組込み, shogun clear prepのスキルをなぜなぜ7回でレベルアップしよう, 時系列×因果×ネットワーク×随時更新で因果ネットワークをどう維持して自動成長させるかは重要だ, そもそもobsidianを利用するアイデアはないのか？全てを独自実装する意味はないよな, 既存の情報や知識のリンクをつくったほうがいいのでは？なぜなぜ7回, まさにCoDDでやるのが理想的だよな, CoDDは遅いね, 根源をただそう, 気づきがあれば行動せよ, 全部やろう, SKILL md script参照9件一括追従更新, 再発を構造的に予防しよう, 軍師提案に対応しよう, これを成長させるためには何が必要だ？なぜなぜ7回, Gate並行実行のflock漏れをなぜなぜ7回, デーモン異常は頻出する, 将軍と家老で意見が違わないか？将軍は何を根拠に進捗を確認している？これはインフラバグか？なぜなぜ7回, やろう, 定休日扱い, CMDで対応しよう, 将軍のナッジ乱発を構造的に防ぐ仕組みも作ろう, さらに因果ネットワークの成長速度を構造的に加速しよう, 次に回すメリットはあるか？ないならいまやろう, 進もう, 全部起票しよう, L6化ができるものは可能な限り速く対応したほうがいい, スクリプトやフックなどの最適化が進めば, Codd台帳のタイムスタンプは確認したか？ 1msinbox1e, テストの数が多すぎる気がするな, 修行サイクルにCoDD最適化ラウンド追加, もっと統合整理できそうな気がするけど, CoDDで最初からやる修行がうまくいっていない, 将軍が定義内にbrownfield方式を明記せよ, 現状を確認, keyword score改善cmdを起票しよう, 起票しよう, 起票せよ, 直近N件で今回の対応はできたか？なぜなぜ7回, 止まるな修正して実行せよとナッジされているが, ではCMD起票しよう, 行動に変換しよう, 修正か追加が必要では？なぜなぜ7回, 穴をふさごう, Cを起票しよう, やるべきタイミングを忘れずにできるか？それならあとでやろう, 起票しようとした内容に関係のあるinboxを無視したよな, ヒントをやろう, 止まらず全てやろう |
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
| cmd | `cmd_2780` 強化 — Simple-OCRリポジトリ全体のCoDD brownfield設計書逆生成 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T03:24:18+09:00 なぜなぜ7回。CoDDできちんとやろう。品質は下げない。現在の出力は合格点だ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T07:27:25+09:00 掲示板にCoDDの修行の話はなかったか？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T07:29:14+09:00 CoDDのdoc_dirs設定整理が必要について、なぜなぜ7回。改善しよう |
| cmd | `cmd_2796` codd.yaml scan設定をリポジトリ構造に一致させhealth_score 0を解消 (`codd/codd.yaml`, `codd/scan/edges.jsonl`) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T08:03:21+09:00 自立自走 なぜなぜ7回 隠れたインフラ バグを探そう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T08:17:45+09:00 自立自走 なぜなぜ7回 続けろ |
| cmd | `cmd_2809` SKILL.md追従7件更新+cmd_complete_gateにSKILL.md追従WARN組込み (`scripts/cmd_complete_gate.sh`, `skills/codd-fix/SKILL.md`, `skills/dashboard-update/SKILL.md`) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-17T12:45:13+09:00 shogun-clear-prepのスキルをなぜなぜ7回でレベルアップしよう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-17T13:59:44+09:00 時系列×因果×ネットワーク×随時更新で因果ネットワークをどう維持して自動成長させるかは重要だ。なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-17T14:13:36+09:00 そもそもobsidianを利用するアイデアはないのか？全てを独自実装する意味はないよな。CoDDのように利用すればいい |
| discussion | `queue/lord_conversation.jsonl` 2026-05-17T19:35:15+09:00 既存の情報や知識のリンクをつくったほうがいいのでは？なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-18T11:36:52+09:00 まさにCoDDでやるのが理想的だよな |
| discussion | `queue/lord_conversation.jsonl` 2026-05-18T11:37:21+09:00 https://zenn.dev/shio_shoppaize/articles/codd-v2-17-milestone読んでみて |
| discussion | `queue/lord_conversation.jsonl` 2026-05-18T13:05:00+09:00 CoDDは遅いね。一回作ってからCoDDで設計書を後から作るほうが早そう。どう思う？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-18T20:57:45+09:00 なぜなぜ7回。根源をただそう。本質はデータを再入力可能なものだと気安く考えている点だな。お前の感覚は中国の焚書やポル・ポト派が仏像や遺跡を破壊するのと同じ発想だ。人の命もそうだが、失ったら未来永劫宇宙から消えてしまうものに対する敬意と恐怖が |
| discussion | `queue/lord_conversation.jsonl` 2026-05-18T21:04:30+09:00 なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T12:09:14+09:00 気づきがあれば行動せよ。なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T12:28:29+09:00 全部やろう。なぜなぜ7回 |
| cmd | `cmd_2859` 修正 — SKILL.md script参照9件一括追従更新 (`skills/codd-fix/SKILL.md`, `skills/dream/SKILL.md`, `skills/gate-sync/SKILL.md`) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T12:57:51+09:00 なぜなぜ7回。再発を構造的に予防しよう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T13:52:07+09:00 軍師提案に対応しよう。なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T14:02:03+09:00 これを成長させるためには何が必要だ？なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T14:12:21+09:00 さらに これを成長させるためには何が必要だ？なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T14:35:19+09:00 Gate並行実行のflock漏れをなぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T14:43:18+09:00 デーモン異常は頻出する。異常時に全再起動のセーフテーの仕組みはないのか？なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T14:46:38+09:00 将軍と家老で意見が違わないか？将軍は何を根拠に進捗を確認している？これはインフラバグか？なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T15:54:20+09:00 やろう。なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T16:02:00+09:00 You are matching a user query to a semantic index. Query: title: "修正 — kj-role-count 定休日入力不可+パート色消失修正" purpose: "殿の2要望:  |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T16:03:03+09:00 You are matching a user query to a semantic index. Query: title: "修正 — kj-role-count 定休日入力不可+パート色消失修正" purpose: "殿の2要望:  |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T16:03:16+09:00 You are matching a user query to a semantic index. Query: title: "修正 — kj-role-count 定休日入力不可+パート色消失修正" purpose: "殿の2要望:  |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T16:42:23+09:00 やろう。定休日扱い |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T17:14:34+09:00 CMDで対応しよう。レベルいくつだ？なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T17:16:37+09:00 将軍のナッジ乱発を構造的に防ぐ仕組みも作ろう。レベルいくつだ？なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T17:20:27+09:00 さらに因果ネットワークの成長速度を構造的に加速しよう。なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T18:55:53+09:00 次に回すメリットはあるか？ないならいまやろう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T19:10:55+09:00 You are matching a user query to a semantic index. Query: dashboard_update スキル FAIL率 改善 Instructions: - Choose up to 3 m |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T19:26:44+09:00 You are matching a user query to a semantic index. Query: title: "修正 — Gate20 FAIL率分母からテスト用cmdを除外" purpose: "cmd_2881偵察で |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T19:42:51+09:00 進もう。なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T19:46:06+09:00 You are matching a user query to a semantic index. Query: title: "強化 — 教訓フィードバック未記録を自動not_useful化" purpose: "教訓健全度ALERT( |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T19:51:15+09:00 全部起票しよう。なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T19:52:34+09:00 You are matching a user query to a semantic index. Query: title: "強化 — GATE CLEAR時にcmd因果辺をsemantic-mapへ自動還流" purpose: "O |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T19:57:20+09:00 You are matching a user query to a semantic index. Query: title: "修正 — report_review重複依頼の手動経路撤去" purpose: "毎セッション5-10件の重 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T19:57:32+09:00 You are matching a user query to a semantic index. Query: title: "修正 — report_review重複依頼の手動経路撤去" purpose: "毎セッション5-10件の重 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:05:41+09:00 L6化ができるものは可能な限り速く対応したほうがいい。早くやれば複利が最大化する。なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:11:50+09:00 You are matching a user query to a semantic index. Query: title: "強化 — WA復活即検出をstartup gateに組込み(L6化)" purpose: "WA全7カテゴリ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:12:07+09:00 You are matching a user query to a semantic index. Query: title: "強化 — WA復活即検出をstartup gateに組込み(L6化)" purpose: "WA全7カテゴリ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:12:24+09:00 You are matching a user query to a semantic index. Query: title: "強化 — WA復活即検出をstartup gateに組込み(L6化)" purpose: "WA全7カテゴリ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:12:36+09:00 You are matching a user query to a semantic index. Query: title: "強化 — WA復活即検出をstartup gateに組込み(L6化)" purpose: "WA全7カテゴリ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:14:13+09:00 スクリプトやフックなどの最適化が進めば、ボトルネックがなくなり滑らかにより早く成長できるのでは？Codd台帳を確認しよう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:16:32+09:00 Codd台帳のタイムスタンプは確認したか？0.1msinbox1e |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:18:46+09:00 すべてやろう。なぜなぜ7回、ＣＭＤ起票 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:24:01+09:00 テストの数が多すぎる気がするな。整理整頓して本当に必要なテストを選別するのはどうだ？なぜなぜ7回 |
| cmd | `cmd_2891` 強化 — 修行サイクルにCoDD最適化ラウンド追加 (`context/training-cycle.md`) |
| causal | `cmd_2891` origin: [[codd_refactor_registry_stale]] -> [[training_cycle]] -> [[L6_codd_auto_rotation]] |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:27:29+09:00 You are matching a user query to a semantic index. Query: title: "偵察 — テスト1766件の価値選別(3問検証)" purpose: "196ファイル1766テストが蓄積。 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:28:25+09:00 You are matching a user query to a semantic index. Query: title: "偵察 — テスト1766件の価値選別(3問検証)" purpose: "196ファイル1766テストが蓄積。 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:28:34+09:00 You are matching a user query to a semantic index. Query: title: "偵察 — テスト1766件の価値選別(3問検証)" purpose: "196ファイル1766テストが蓄積。 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:40:21+09:00 もっと統合整理できそうな気がするけど。なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:42:55+09:00 You are matching a user query to a semantic index. Query: title: "強化 — テスト62小ファイルをスクリプト単位統合(第2波)" purpose: "cmd_2892偵察の1 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:43:04+09:00 You are matching a user query to a semantic index. Query: title: "強化 — テスト62小ファイルをスクリプト単位統合(第2波)" purpose: "cmd_2892偵察の1 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:44:01+09:00 You are matching a user query to a semantic index. Query: title: "強化 — テスト新規ファイル作成時に既存統合を強制(L6化)" purpose: "テスト196ファイル蓄積 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:44:17+09:00 You are matching a user query to a semantic index. Query: title: "強化 — テスト新規ファイル作成時に既存統合を強制(L6化)" purpose: "テスト196ファイル蓄積 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:44:33+09:00 You are matching a user query to a semantic index. Query: title: "強化 — テスト新規ファイル作成時に既存統合を強制(L6化)" purpose: "テスト196ファイル蓄積 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:45:41+09:00 You are matching a user query to a semantic index. Query: title: "強化 — テスト新規ファイル作成時に既存統合を強制(L6化)" purpose: "テスト196ファイル蓄積 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:46:25+09:00 You are matching a user query to a semantic index. Query: title: "強化 — テスト追加ファイル作成時に既存統合を強制(L6化)" purpose: "テスト196ファイル蓄積 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:47:01+09:00 You are matching a user query to a semantic index. Query: title: "強化 — テスト追加ファイル追加時に既存統合を強制(L6化)" purpose: "テスト196ファイル蓄積 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:47:23+09:00 You are matching a user query to a semantic index. Query: title: "強化 — テスト追加ファイル追加時に既存統合を強制(L6化)" purpose: "テスト196ファイル蓄積 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:47:59+09:00 You are matching a user query to a semantic index. Query: title: "強化 — テスト追加ファイル追加時に既存統合を強制(L6化)" purpose: "テスト196ファイル蓄積 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:48:10+09:00 You are matching a user query to a semantic index. Query: title: "強化 — テスト追加ファイル追加時に既存統合を強制(L6化)" purpose: "テスト196ファイル蓄積 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:55:52+09:00 CoDDで最初からやる修行がうまくいっていない。とにかく遅いせいで進まないみたいだ。 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T21:00:28+09:00 将軍が定義内にbrownfield方式を明記せよ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T14:19:18+09:00 現状を確認。なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T14:47:06+09:00 You are matching a user query to a semantic index. Query: title: "強化 — cmd_save.sh BLOCK時に全トリガーワード位置マップを一括出力" purpose: " |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T14:52:07+09:00 You are matching a user query to a semantic index. Query: title: "強化 — cmd_save.sh BLOCK時に全トリガーワード位置マップを一括出力" purpose: " |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T14:52:31+09:00 You are matching a user query to a semantic index. Query: title: "強化 — cmd_save.sh BLOCK時に全トリガーワード位置マップを一括出力" purpose: " |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T15:06:08+09:00 You are matching a user query to a semantic index. Query: title: "infra — q8 WHY検出緩和テスト" purpose: "WHYが明示されていれば引用記号なしでも不 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T16:02:50+09:00 You are matching a user query to a semantic index. Query: title: "強化 — gws CLI知識体系化(Gmail操作+auth確認+フィルタ)" purpose: "gws  |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T16:16:12+09:00 keyword_score改善cmdを起票しよう。なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T16:24:55+09:00 起票しよう。なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T16:33:10+09:00 You are matching a user query to a semantic index. Query: title: "infra — q8 WHY検出緩和テスト" purpose: "WHYが明示されていれば引用記号なしでも不 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T18:38:23+09:00 起票せよ。なぜなぜ7回、真因をほれ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T18:42:16+09:00 真因までなぜなぜ7回、起票せよ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T18:47:47+09:00 直近N件で今回の対応はできたか？なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T19:47:46+09:00 止まるな修正して実行せよとナッジされているが、実際には停止してしまっているな。改善しよう。ナッジの場所が悪いのか？なぜなぜ7回。inbox1Error: Exit code 1 === [0/3] cmd_publish pre-fligh |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T22:21:10+09:00 やろう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T22:57:45+09:00 起票しよう。なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T23:51:41+09:00 ではCMD起票しよう。まずはAnomida |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T23:59:12+09:00 行動に変換しよう。なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-21T00:05:38+09:00 起票しよう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-21T00:24:09+09:00 修正か追加が必要では？なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-21T00:29:00+09:00 穴をふさごう。なぜなぜ7回 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-21T00:46:30+09:00 Cを起票しよう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-21T00:55:50+09:00 やるべきタイミングを忘れずにできるか？それならあとでやろう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-21T01:10:05+09:00 なぜなぜ7回、確認して必要なら起票せよ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-21T01:30:02+09:00 起票しよう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-21T01:47:59+09:00 起票しようとした内容に関係のあるinboxを無視したよな |
| discussion | `queue/lord_conversation.jsonl` 2026-05-21T02:00:10+09:00 ヒントをやろう。お前は起動時にどうしてる？inboxが届けば同じ事をやればいいのではない？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-21T02:20:41+09:00 止まらず全てやろう |

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
| file | `scripts/gate_improvement_trigger.sh` gate ALERT通知(家老inbox+ntfy。自動消火抑制) |

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
| aliases | deepdive, 追体験, why_chain, causal_tracing, 自動化×強制, 車輪再発明, 車輪防止, Guard通読, 俺との会話はdeepdiveを前提としていることが多くないかinbox1, 因果ネットワーク構想 Obsidian vault化 殿承認, 環境に埋め込むというのはレベル5以上の自動化×強制になっているか？, 強制レベルで埋め込んだか？記憶しても意味がないのはdeepdiveに書いてあっただろ？ |
| skills | なし |

| 種別 | パス/参照 |
|------|----------|
| deepdive | `memory/deepdive_why_chain_20260321.md` |
| deepdive | `memory/deepdive_causal_tracing_20260415.md` |
| deepdive | `memory/deepdive_karo_verification_20260405.md` |
| file | `context/training-cycle.md` |
| discussion | `queue/lord_conversation.jsonl` 2026-05-17T13:54:49+09:00 俺との会話はdeepdiveを前提としていることが多くないかinbox1 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-17T14:17:00+09:00 因果ネットワーク構想(Obsidian vault化)殿承認。根因=時系列×因果のネットワーク不在で外部記事に揺らぐ。解法=Obsidianをそのまま使い[[リンク]]で因果辺永続化。全エージェント利用可能な進化する前提知識ネットワーク。d |
| discussion | `queue/lord_conversation.jsonl` 2026-05-18T21:03:52+09:00 環境に埋め込むというのはレベル5以上の自動化×強制になっているか？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-21T02:13:43+09:00 強制レベルで埋め込んだか？記憶しても意味がないのはdeepdiveに書いてあっただろ？ |

## growth_loop — 学習ループ

| 属性 | 値 |
|------|---|
| id | growth_loop |
| label | 学習ループ |
| aliases | 学習ループ, 成長ループ, 二値計測, 知見還流, ラルフループ, 三層学習ループ, 教訓統合, lessons_shogun v3統合, 将軍自身の学習ループは順調か？成長しているか？, 学習ループは順調か？, 自動成長ループは順調か？, 適したスキルを無視するのはバグ — TRIGGER条件合致時はSkill tool必須, 自動成長ループが構造的に阻害されている場所はないか？, 同様のコード修正までが一気通貫していないせいで, 今回のBLOCKで何を学習して, BLOCK後に環境埋込み判定を強制（自動成長ループ完結）, 学習ループによる自動成長が我らの最大の特徴だ, いまどのような自動成長の学習ループがある？, 整備 lessons karo yaml上限到達に伴う教訓統合 LK A01 v8吸収 LK013統合 |
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
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:03:37+09:00 学習ループによる自動成長が我らの最大の特徴だ。そして自動成長の速度の最大化がinbox1レベル |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:04:10+09:00 いまどのような自動成長の学習ループがある？ |
| cmd | `cmd_2911` 整備: lessons_karo.yaml上限到達に伴う教訓統合(LK-A01 v8吸収+LK013統合) (`projects/infra/lessons_karo.yaml`) |
| causal | `cmd_2911` origin: [[lessons_karo_limit]] -> [[LK-A01_v8_absorption]] -> [[lesson_cycle_unblock]] |
| file | `scripts/lesson_impact_analysis.sh` 教訓効果分析(注入率/参照率/CLEAR-BLOCK A/B) |
| file | `scripts/ralph_loop_metrics.sh` ラルフループ定量計測(5指標: パターン再発/revert/完了速度/lesson-CLEAR相関/PI違反) |
| file | `scripts/knowledge_metrics.sh` 教訓有効性+陳腐化検出(JSON/TSV出力対応) |

## alm_research — ALM研究

| 属性 | 値 |
|------|---|
| id | alm_research |
| label | ALM研究 |
| aliases | ALM, Adaptive Lookback Momentum, ALM四神, ALM忍法, l1_alm_wf_engine, WF, ALMはディスコンだから俺が明示的に言わない限り, CI RED修正 cmd 2837のwf engine除外条件が正当WARNまで消した回帰修正 |
| skills | pf-registration, db-check |

| 種別 | パス/参照 |
|------|----------|
| file | `/mnt/c/Python_app/DM-signal/docs/research/alm-integration-design.md` |
| file | `context/gunshi-alm-38metrics-design.md` |
| file | `context/robustness-verification-catalog.md` |
| discussion | `queue/lord_conversation.jsonl` 2026-05-04T15:11 ALM再構築 |
| lesson | `L566` ALM吸収はシン吸収と異なりメトリクスが変わる(helpful_count:3) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-10T22:36:14+09:00 ALMはディスコンだから俺が明示的に言わない限り、話題に絶対出すな |
| cmd | `cmd_2839` CI RED修正(cmd_2837のwf_engine除外条件が正当WARNまで消した回帰修正) |

## shin_shijin_design — 四神設計

| 属性 | 値 |
|------|---|
| id | shin_shijin_design |
| label | 四神設計 |
| aliases | 四神, シン四神, L0, pf_stage_shijin, WF四神, 12体, step2のクライアントIDは取得した, inbox write sh将軍ナッジ防止Guard追加 task new →L5化 |
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
| cmd | `cmd_2879` 強化 — inbox_write.sh将軍ナッジ防止Guard追加(task_new L0→L5化) (`scripts/inbox_write.sh`, `tests/unit/test_inbox_write.bats`) |

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
| aliases | skill design, skill-design, スキル設計, SKILL.md, description 1024, What When NOT When, trigger設計, 誤発火防止, allowed-tools, skill creator, スキルTRIGGER, SKILL md 3件をscript変更に追従更新（3セッション連続WARN解消）, gate lesson health sh PHANTOM検出awk偽陽性修正 SKILL md 3件追従更新, SKILL md追従3件更新 dream karo direct shogun teire — script変更に追従, verdict計算値化 bcから自動導出, skill_gate_feedback, skill_auto_improve, スキル自動改善, skill_execution_log, スキル実行ログ, 修正 SKILL md 5件mtime更新 script参照偽陽性3セッション連続WARN解消, gate_skill_script_refs, script_refs, スキルスクリプト参照, SKILL.md追従, mtime同期 |
| skills | skill-creator, skill-installer |

| 種別 | パス/参照 |
|------|----------|
| file | `context/skill-design-rules.md` |
| file | `docs/research/dream-skill-design.md` |
| file | `scripts/skill_gate_feedback.sh` |
| file | `scripts/skill_auto_improve.sh` |
| file | `scripts/skill_execution_log.sh` |
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
| cmd | `cmd_2829` SKILL.md追従3件更新(dream/karo-direct/shogun-teire — script変更に追従) (`skills/dream/SKILL.md`, `skills/karo-direct/SKILL.md`, `skills/ninja-commit/SKILL.md`) |
| cmd | `cmd_2871` 強化 — verdict計算値化(bcから自動導出。手動記入廃止) (`scripts/gates/gate_report_autofix_main.py`, `skills/verdict-check/SKILL.md`, `tests/test_gate_report_format.bats`) |
| cmd | `cmd_karo_obs_required_check` (`scripts/gunshi_log_append.sh`, `skills/review-bundle/SKILL.md`) |
| cmd | `cmd_karo_skill_md_verdict_sync` (`skills/ninja-commit/SKILL.md`, `skills/report-write/SKILL.md`) |
| cmd | `cmd_2883` (`skills/idle-persist/SKILL.md`, `skills/karo-direct/SKILL.md`, `skills/ninja-commit/SKILL.md`) |
| cmd | `cmd_2899` (`skills/dashboard-update/SKILL.md`, `skills/gate-sync/SKILL.md`, `skills/idle-persist/SKILL.md`) |
| cmd | `cmd_2921` 修正: SKILL.md 5件mtime更新(script参照偽陽性3セッション連続WARN解消) |
| causal | `cmd_2921` origin: [[gate_skill_script_refs]] -> [[mtime_false_positive]] -> [[startup_block_escalation]] |

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
| aliases | 編成, hensei, モデル編成, CLI切替, respawn, settings.yaml, 配備, deploy, deploy_task, 監視, monitor, ninja_monitor, auto-commit, auto-clear, 教訓注入, lesson injection, useful率, score閾値, MIN_KEYWORD_SCORE, report review受信時にkaro direct配備か通常配備かを確認せよ, 二重配備はstallの判断ミスだろうな, inbox write sh task assigned時の二重配備自動検査, 確かidle判定やstall判定が未熟で, GATE BLOCK FAIL時の家老自動通知 再配備提案を追加, 配備が止まっていないか？, 同一バグを複数セッションが独立発見→auto commitで先行入り済みのパターン, report path未注入taskでは完了報告前にreport field setで報告YAMLを明示作成する, 外部PJなのでkaro directで家老に配備する, 穴をふさごう, task notification task id bja0fxnxt task id tool use id tool, clear_prep_check, build_instructions, instructions再生成 |
| skills | hensei, hensei-mixed, hensei-opus, karo-direct, recon-dual, reset-layout, shogun-all-codex-switch, shogun-peacetime-rollback, switch-to-codex, switch-to-opus |

| 種別 | パス/参照 |
|------|----------|
| file | `config/settings.yaml` |
| file | `context/infrastructure.md` CLIモデル指定とコンテキスト |
| file | `scripts/deploy_task.sh` |
| file | `scripts/ninja_monitor.sh` |
| file | `scripts/clear_prep_check.sh` |
| file | `scripts/build_instructions.sh` |
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
| cmd | `cmd_2734` 強化 — セマンティクスインデックスにスキル推奨列を追加し忍者タスクに自動注入 (`context/semantic-map.md`, `docs/semantic-index/index.md`, `scripts/deploy_task.sh`) |
| cmd | `cmd_2737` (`scripts/deploy_task.sh`, `scripts/gates/gate_karo_startup.sh`, `tests/helpers/deploy_task_scaffold.bash`) |
| cmd | `cmd_2746` 偵察 — deploy_task.sh配備後inbox未配信の根因調査 |
| cmd | `cmd_2754` 強化 — ninja_monitorに修行サイクル自動トリガーを追加 (`scripts/ninja_monitor.sh`) |
| cmd | `cmd_2755` 強化 — FAIL→PASS遷移率の定期計測をninja_monitorに追加 (`scripts/ninja_monitor.sh`) |
| cmd | `cmd_2757` 強化 — 教訓定期棄却の自動トリガーをninja_monitorに追加 (`scripts/lesson_deprecation_scan.sh`, `scripts/ninja_monitor.sh`, `tests/unit/test_lesson_deprecation_scan.bats`) |
| cmd | `cmd_2789` (`queue/tasks/hayate.yaml`, `tests/unit/test_deploy_task_draft_review.bats`) |
| lesson | `L613` deploy_task.sh: STKのac_assignedはinject関数で明示転記が必要 |
| cmd | `cmd_2790` 強化 — deploy_task.sh ac_assigned導入でbc注入範囲を担当ACに限定 (`scripts/deploy_task.sh`, `tests/helpers/deploy_task_scaffold.bash`, `tests/unit/test_deploy_task_ac_handling.bats`) |
| cmd | `cmd_2799` karo-direct/SKILL.md をdeploy_task.sh最新変更に追従更新 (`skills/karo-direct/SKILL.md`) |
| cmd | `cmd_2801` (`scripts/deploy_task.sh`, `tests/unit/test_deploy_task_yaml_injection.bats`) |
| cmd | `cmd_2804` (`scripts/deploy_task.sh`, `tests/unit/test_deploy_task_lifecycle.bats`) |
| cmd | `cmd_2806` (`queue/tasks/kotaro.yaml`, `tests/unit/test_ninja_monitor_clear_guard.bats`) |
| cmd | `cmd_2822` deploy_task.sh 因果リンク自動注入(忍者タスクに関連因果を自動化提供) (`scripts/deploy_task.sh`) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-17T16:49:55+09:00 配備が止まっていないか？ |
| cmd | `cmd_2827` report蓄積によるdeploy_task.sh timeout修正(archive overflow capのCMD_IDガード撤去) (`queue/reports/kotaro_report_cmd_2702_kotaro.yaml`, `queue/reports/kotaro_report_cmd_training_L4_auto_202605151325_kotaro_normal.yaml`, `queue/reports/kotaro_report_cmd_training_L4_auto_202605151346_kotaro_normal.yaml`) |
| cmd | `cmd_2830` deploy_task.sh nudge送信保証(trap EXITで途中kill/timeout時もnudge到達) (`scripts/deploy_task.sh`, `tests/unit/test_deploy_task.bats`) |
| cmd | `cmd_2832` deploy_task.sh隠れたインフラバグ3件修正(timeout保護+verify形骸化+gawk I/O削減) (`scripts/deploy_task.sh`, `tests/unit/test_deploy_task.bats`) |
| cmd | `cmd_2842` (`scripts/deploy_task.sh`, `tests/unit/test_deploy_task_same_ninja_redeploy.bats`) |
| lesson | `L620` 同一バグを複数セッションが独立発見→auto-commitで先行入り済みのパターン |
| lesson | `L622` _cleanup_stale_keysはcompound-keyを持つ全配列を網羅すべき |
| cmd | `cmd_training_L4_auto_202605181242_tobisaru` (`scripts/ninja_monitor.sh`) |
| lesson | `L625` report_path未注入taskでは完了報告前にreport_field_setで報告YAMLを明示作成する |
| discussion | `queue/lord_conversation.jsonl` 2026-05-18T21:06:34+09:00 外部PJなのでkaro_directで家老に配備する。とはなんだ？なぜ将軍がCMDを起票しない？説明して |
| cmd | `cmd_karo_backup_first_l5` (`tests/unit/test_cmd_save.bats`, `tests/unit/test_deploy_task_yaml_injection.bats`) |
| cmd | `cmd_2852` 修正 — deploy_task.sh inject関数のsed特殊文字エスケープ不足によるexit 1修正 (`scripts/deploy_task.sh`, `tests/helpers/deploy_task_scaffold.bash`, `tests/unit/test_deploy_task_lifecycle.bats`) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T12:40:38+09:00 穴をふさごう。2860はまだ未配備だな |
| cmd | `cmd_2864` 強化 — 教訓注入キーワードスコア最低閾値追加(score>=2で無関係注入削減) (`scripts/deploy_task.sh`, `tests/unit/test_deploy_task_lesson_scoring.bats`) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T16:35:00+09:00 bja0fxnxt toolu_019QPfn1mVGPze6AxmHBwpN1 /tmp/claude-1000/-mnt-c-tools-multi-agent-shogun/23e2871c-af99-4a8b-a8c5-af194a |
| cmd | `cmd_2887` 強化 — deploy_task.sh scope清掃テスト追加(再発防止) (`tests/unit/test_deploy_task_lifecycle.bats`) |
| causal | `cmd_2887` origin: [[LK-A02_v7]] -> [[scope_context_stale]] -> [[test_gap]] |
| cmd | `cmd_2894` 強化 — テスト62小ファイルをスクリプト単位統合(第2波) (`docs/research/codd_refactor_registry.md`, `tests/unit/test_auto_failure_lesson.bats`, `tests/unit/test_causal_backlinks.bats`) |
| causal | `cmd_2894` origin: [[cmd_2892]] -> [[test_file_granularity]] -> [[script_unit_consolidation]] |
| causal | `cmd_2894` depends_on: cmd_2893 |
| cmd | `cmd_2901` 修正 — deploy_task.sh keyword_scoreにtask_type別閾値導入 (`scripts/deploy_task.sh`, `tests/unit/test_deploy_task_lesson_scoring.bats`) |
| cmd | `cmd_2904` 修正 — Codex CLI idle時respawnループ根絶(task status分岐) (`scripts/ninja_monitor.sh`, `tests/unit/test_ninja_monitor_clear_guard.bats`) |
| causal | `cmd_2904` origin: [[codex_idle_respawn_198]] -> [[safe_send_clear_no_status_check]] -> [[task_status_branch_missing]] |
| cmd | `cmd_2906` 修正 — Codex idle時/new経路復旧(cmd_2904過剰抑止修正) (`tests/unit/test_ninja_monitor_clear_guard.bats`) |
| causal | `cmd_2906` origin: [[cmd_2904_overfix]] -> [[codex_idle_ctx_accumulation]] -> [[handle_auto_clear_wrong_layer]] |
| docs | `docs/research/gunshi_idle_infra_design_intent_catalog_20260520.md` 「バグに見えるが正しい」4パターン(codex delivery/STALL-GHOST/HOOK-STALE/LOOP-DEBOUNCE) |
| design_intent | **Codex idle時もrespawn-pane -k必須**(殿裁定2026-05-20): `/new`はCLI内部「task in progress」で拒否される。respawn-pane -kが唯一確実なリセット手段。cmd_2904/2906で/newに変更→3忍者CTX滞留で実証。[[cmd_2904_overfix]] -> [[codex_new_rejected]] -> [[respawn_is_correct_design]] |
| cmd | `cmd_2907` 修正: Codex idle時のrespawn-pane -k経路を復旧 (`tests/unit/test_ninja_monitor_clear_guard.bats`) |
| causal | `cmd_2907` origin: [[cmd_2906]] -> [[Codex_CLI_new_incompatible]] -> [[CTX_accumulation]] |
| cmd | `cmd_2917` 修正: deploy_task.sh exit 1時のdraft_review未送信フォールバック追加 (`scripts/deploy_task.sh`, `tests/unit/test_deploy_task_draft_review.bats`) |
| causal | `cmd_2917` origin: [[deploy_exit_1_no_draft_review]] -> [[success_path_only_notification]] -> [[review_flow_breakage]] |

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
| discussion | `queue/lord_conversation.jsonl` 2026-05-10T18:07:04+09:00 tierが課金プランに紐付いているのは理解しているか？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-10T18:07:57+09:00 料金プランとの対応は知識となっているか？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-10T20:11:30+09:00 前にどのtierがどのPFを閲覧できるかまとめたのは覚えているか？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-10T20:13:43+09:00 プラン毎に1つ推奨PFを決めてあげると、メンバーは理解しやすい。理解しやすければ継続して課金してくれる。ビジネスモデルとして推奨PFがtier=plan毎に必要だ |

## shogun_android_app — 将軍Androidアプリ

| 属性 | 値 |
|------|---|
| id | shogun_android_app |
| label | 将軍Androidアプリ |
| aliases | Android, アプリ, モバイル, Kotlin, APK, com.shogun.android, 将軍アプリ, このアプリはGoogleで確認されていません」警告が出ても利用はできるよな？, モバイルレスポンシブ崩れ修正 ヘッダー テーブル 銘柄リスト, モバイルポートフォリオ入力をコンパクト横並び1行 銘柄に再設計, このアプリは原則的にお薬手帳用に開発した, だいぶまとまて来たなアイコンは使わない |
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
| discussion | `queue/lord_conversation.jsonl` 2026-05-18T11:07:50+09:00 だいぶまとまて来たなアイコンは使わない。これは誰がいつやったかが明確にしなければならないのでtoiletアプリとは全く違う |

## cdp_browser_capability — CDP(ブラウザ操作能力)

| 属性 | 値 |
|------|---|
| id | cdp_browser_capability |
| label | CDP(ブラウザ操作能力) |
| aliases | CDP, Chrome DevTools Protocol, ブラウザ操作, スクショ確認, 本番表示確認, cdp_cli, cdp_helper, CDPでこのページを確認すると知識を得られるはずだ, 完了したらCDPで確認しておいて, 続けて, 毎回CDPのスキルを未使用とする例が多くてトラブルになることがある, 確認しよう, 他にも隠れたインフラバグや, 他に放置しているものがないか確認しよう, CDPで確認して, 効果が出ているか確認しよう, これ毎回俺がやるのはおかしいな, 起票する前に確認しよう, 陳腐化しているものがないか確認しよう |
| skills | cdp-browse |

| 種別 | パス/参照 |
|------|----------|
| file | `context/cdp-philosophy.md` |
| file | `scripts/cdp/cdp_cli.sh` |
| file | `scripts/cdp/cdp_measure.sh` |
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
| discussion | `queue/lord_conversation.jsonl` 2026-05-14T23:46:50+09:00 続けて |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T00:03:29+09:00 毎回CDPのスキルを未使用とする例が多くてトラブルになることがある。DB-checkなどのスキルを実行しようとすることもあるな |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T22:56:22+09:00 続けて |
| discussion | `queue/lord_conversation.jsonl` 2026-05-15T23:06:43+09:00 続けて |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T08:00:46+09:00 続けて |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T14:58:22+09:00 続けて |
| discussion | `queue/lord_conversation.jsonl` 2026-05-17T22:00:51+09:00 続けて |
| discussion | `queue/lord_conversation.jsonl` 2026-05-18T15:21:41+09:00 確認しよう。デプロイが終わったらCDPで確認しよう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T11:32:30+09:00 他にも隠れたインフラバグや、実行速度が極端に落ちたスクリプトがないか確認しよう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T12:45:57+09:00 他に放置しているものがないか確認しよう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T13:24:40+09:00 続けて |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T14:57:37+09:00 確認しよう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T16:29:45+09:00 CDPで確認して |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T18:51:10+09:00 効果が出ているか確認しよう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T19:57:06+09:00 続けて |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T15:55:12+09:00 これ毎回俺がやるのはおかしいな。CDPができるんだから将軍側でできるのでは？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T16:26:59+09:00 起票する前に確認しよう。書き直しが必要になるはずだ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T21:39:59+09:00 陳腐化しているものがないか確認しよう |

## defense_hierarchy — 防御階層原則

| 属性 | 値 |
|------|---|
| id | defense_hierarchy |
| label | 防御階層原則(Level 1-6) |
| aliases | 防御階層, defense_level, Level5, Level 5, Level6, Level 6, 学習速度最大化, 下限切り上げ, ラチェット, 事前コンテキスト提供, 入口側生成, 入口改善, ゲート不要化, 発火しないシステム, FAIL→PASS遷移率, L6化率, gate_fire_log解析, LG010, ninja_weak_points, previous_failures, 修行サイクル, training cycle, 忍者修行, 一発PASS率, BLOCK率, 修行レベル, L1 L2 L3 L4, research tool explicit偽陽性修正 ACパス自動提案 Level5化, 放置タスク滞留検出 BLOCK昇格をstartup gateに追加 Level5化, 否定的前提主張の反証grep強制 LG033 Level5化, 教訓件数WARN閾値を31件に引き下げ Level5化, cmd間依存の明示強制 LS A14 Level5化, gate hook追加cmd検出時に既存強制フロー候補を自動表示 LG032 Level5化, 計測 見積cmdにタイムボックス欄を自動要求 LG019 Level5化, AC command内の数値リテラルに再計算元表示を自動提案 LG020 Level5化, AC外作業検出INFO提案 LS A08 Level5化, 時間コスト関連cmdに環境差異欄を自動要求 LS A10 Level5化, gate vercel phase壊れ参照検出時に修正候補を自動提案 Level5化, Level1止まりgate6件に修正候補自動提案を追加 Level5化一括, ac param sufficiency WARN時にcontext projects yamlから候補値を自動提案 L, inject ninja weak points YAML注入失敗の根因調査 cmd 2801副作用 |
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
| cmd | `cmd_2807` inject_ninja_weak_points YAML注入失敗の根因調査(cmd_2801副作用) (`queue/tasks/tobisaru.yaml`, `tests/unit/test_dashboard_auto_context_freshness.bats`, `tests/unit/test_gate_meta_quality.bats`) |

## tier_plan_mapping — Tier-プラン対応

| 属性 | 値 |
|------|---|
| id | tier_plan_mapping |
| label | Tier-プラン対応 |
| aliases | tier, Tier, 料金プラン, プラン, plan, subscription, メンバーシップ, membership, viewer_tiers, Basic, Standard, NewStandard, AddOn, premium, ベーシック, スタンダード, アドオン, プレミアム, 古参スペシャル, 劇薬DM, ドクタープレミアム, 特にビジネスプランの話を今後するときにスムーズにやりたいな, starterplanにcold startあったっけ？, Render知識体系化 プラン別挙動 障害切り分け サービス一覧をcontext化, プレミアム会員優先 すし 㐂邑 きむら 追加枠のお知らせ OMAKASEなどがそうだ |
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
| discussion | `queue/lord_conversation.jsonl` 2026-05-17T20:07:46+09:00 starterplanにcold startあったっけ？ |
| cmd | `cmd_2824` Render知識体系化(プラン別挙動+障害切り分け+サービス一覧をcontext化) (`context/infrastructure.md`) |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T15:50:50+09:00 (プレミアム会員優先) すし 㐂邑 (きむら) 追加枠のお知らせ [OMAKASEなどがそうだ |

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
| aliases | rebalancer, リバランス, リバランサー, Portfolio Rebalance App, dm-rebalancer, ポートフォリオリバランス, なるほど, アイデア出しをしよう, Project URL と anon keyは envで保存しておかなくていいのか？rebalancer内においておけば, C \Python app\rebalancer\frontend\ env local, リバランサーのスマホ画面でのレスポンシブ対応が完了していないようだ, リバランサーのスマホ画面だが, リバランサーのGoogleOauthはもう誰でも利用できる？, なるほど精度はどうやって計測し |
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
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T20:15:21+09:00 なるほど精度はどうやって計測し、改善していくんだ？ |

## simple_ocr — Simple OCR（画像OCR Webアプリ）

| 属性 | 値 |
|------|---|
| id | simple_ocr |
| label | Simple OCR（画像OCR Webアプリ） |
| aliases | Simple-OCR, OCR, お薬手帳, 薬手帳OCR, Google Vision, Claude Vision, GPT Vision, OCRエンジン切替, two_stage, Stage 1.5, schedule検出, 構造化JSON, グルーピング, 横向き画像, ブロックフィルタ, prompt caching, Flask-SocketIO, QRコード連携, PC受信モード, スタンドアロンOCR, 除外パターン, exclusion_manager, OCR結果の題名に患者名にすることは可能？, 国立国会図書館のNDLOCR Liteもうまくいかなかったエピソードも必要だな |
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
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T15:20:15+09:00 simple-OCRの話をしよう |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T15:22:26+09:00 '/mnt/c/Users/simok/OneDrive/画像/Screenshots/スクリーンショット 2026-05-16 151944.png' '/mnt/c/Users/simok/OneDrive/画像/Screenshots |
| cmd | `cmd_2812` Simple-OCR UIデフォルトエンジンをtwo_stageに変更 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T15:34:04+09:00 [Image #2] 受信したOCR結果のinbox1 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T15:35:01+09:00 OCR結果の題名に患者名にすることは可能？ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T15:40:16+09:00 simple-OCRでフォーマットや段組みが様々なお薬手帳をOCRでテキストにするまでのフローを詳しく知りたい |
| cmd | `cmd_2813` Simple-OCR 結果カードのタイトルを患者名に変更 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T15:50:34+09:00 国立国会図書館のNDLOCR-Liteもうまくいかなかったエピソードも必要だな |
| discussion | `queue/lord_conversation.jsonl` 2026-05-16T15:54:07+09:00 ２と３は順序が逆だ。google vision api単独だと余分な情報が多すぎる→Google Vision API + 除外パターンマッチ→LLMの性能向上で解決できないかと思いClaude Vision / GPT-4o に画像を直接 |

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
| aliases | 破壊的操作, D001-D009, lord_approval, force push, reset --hard, git clean, Tier1, Tier2, 全ての作業で共通の内容だぞ |
| skills | なし |

| 種別 | パス/参照 |
|------|----------|
| file | `.claude/hooks/pre-bash-combined.sh` 殿承認確認Guard(D010) |
| file | `tests/unit/test_pre_bash_destructive_approval.bats` 破壊的操作テスト |
| file | `CLAUDE.md` Destructive Operation Safety (Tier1/Tier2/Tier3) |
| cmd | `cmd_2784` 破壊的操作の前に殿の明示的承認確認をpre-bash hookに追加 |
| lesson | `LK-A01 v6` 破壊的操作はremote現状確認+lord_conversation確認必須 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-18T21:03:06+09:00 全ての作業で共通の内容だぞ。各論にするな。破壊的操作を禁止するのはナンセンスで責任転換しているだけだ。人もLLMもミスをする。俺に判断を投げるという発想が根本的に間違っているな。 |

## cmd_quality_logging — cmd設計品質ログ

| 属性 | 値 |
|------|---|
| id | cmd_quality_logging |
| label | cmd設計品質ログ |
| aliases | cmd品質ログ, cmd_quality_log, cmd_design_quality, 品質記録, karo_rework, gunshi_verdict, ninja_blockers, supplementary_cmds, BLOCK率, CLEAR率, ac_count, FP率計算は累計昇格BLOCKを候補に含める, FP率計算は累計昇格BLOCKもFP候補に含める, archive_completed, cmd_publish, cmd完了処理 |
| skills | cmd-complete |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/cmd_quality_log.sh` |
| file | `scripts/archive_completed.sh` |
| file | `scripts/cmd_publish.sh` |
| file | `logs/cmd_design_quality.yaml` |
| file | `logs/archive/cmd_design_quality.yaml` |
| file | `scripts/gates/gate_shogun_startup.sh` |
| cmd | `cmd_2855` cmd_quality_log.sh高速化 |
| lesson | `L637` FP率計算は累計昇格BLOCKを候補に含める |
| lesson | `L638` FP率計算は累計昇格BLOCKもFP候補に含める |

## task_modifier_injection — タスク修飾子注入

| 属性 | 値 |
|------|---|
| id | task_modifier_injection |
| label | タスク修飾子注入 |
| aliases | inject_task_modifiers, タスク修飾子, engineering_preferences注入, reports_to_read注入, context注入, credential注入, report_template注入, execution_controls注入, DB変更検出 |
| skills | なし |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/lib/inject_task_modifiers.py` |
| file | `scripts/deploy_task.sh` |
| cmd | `cmd_1393` 7サブプロセス→1統合(inject_task_modifiers.py誕生) |

## training_cycle_quality — 忍者修行サイクル品質

| 属性 | 値 |
|------|---|
| id | training_cycle_quality |
| label | 忍者修行サイクル品質 |
| aliases | 修行サイクル, training cycle, 忍者修行, ダミータスク修行, gate BLOCK訓練, 一発PASS率, first pass rate, 修行レベル, L1修行, L2修行, L3修行, L4修行, gate_fire_log計測, BLOCKパターン学習 |
| skills | なし |

| 種別 | パス/参照 |
|------|----------|
| file | `context/training-cycle.md` |
| file | `logs/gate_fire_log.yaml` |
| file | `scripts/ninja_monitor.sh` |
| cmd | `cmd_2754` ninja_monitorに修行サイクル自動トリガーを追加 |
| cmd | `cmd_2755` FAIL→PASS遷移率の定期計測をninja_monitorに追加 |

## report_quality_protocol — 忍者報告品質プロトコル

| 属性 | 値 |
|------|---|
| id | report_quality_protocol |
| label | 忍者報告品質プロトコル |
| aliases | 報告品質, report quality, 報告YAML, report template, gate_report_format, binary_checks, lesson_candidate, lessons_useful, purpose_validation, verdict自動導出, report_field_set, 報告gate, SKIPはFAIL, status completed, AC二値チェック, verdict自動導出は免除文脈 waive reason をgate検出へ残す, gate report format sh skill execution log sh非同期化でPASSパスを87%高 |
| skills | report-write, verdict-check |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/gates/gate_report_format.sh` |
| file | `scripts/gates/gate_report_format_main.py` |
| file | `scripts/report_field_set.sh` |
| file | `context/training-cycle.md` |
| cmd | `cmd_2871` verdict計算値化(bcから自動導出) |
| lesson | `L625` report_path未注入taskでは完了報告前にreport_field_setで報告YAMLを明示作成する |
| lesson | `L633` verdict自動導出は免除文脈(waive_reason)をgate検出へ残す |
| cmd | `cmd_2880` 強化 — 報告YAML origin自動継承(cmd origin→報告origin零コスト転写) (`scripts/report_field_set.sh`, `tests/unit/test_report_field_set_validation.bats`) |
| lesson | `L643` gate_report_format.sh: skill_execution_log.sh非同期化でPASSパスを87%高速化(WSL2 python3起動コスト回避) |

## external_project_registry — 外部プロジェクト登録

| 属性 | 値 |
|------|---|
| id | external_project_registry |
| label | 外部プロジェクト登録 |
| aliases | 外部PJ, external project, project registry, projects yaml, config projects, PJ登録, プロジェクト登録, rebalancer, Simple-OCR, kj-partshift, Google Classroom, OpenPBX, プロジェクト核心知識, context project md |
| skills | なし |

| 種別 | パス/参照 |
|------|----------|
| file | `config/projects.yaml` |
| file | `projects/rebalancer.yaml` |
| file | `projects/simple-ocr.yaml` |
| file | `projects/kj-partshift.yaml` |
| cmd | `cmd_2701` rebalancer PJ登録 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-18T21:06:34+09:00 外部PJなのでkaro_directで家老に配備する。とはなんだ？ |

## daemon_supervision — デーモン監視と復旧

| 属性 | 値 |
|------|---|
| id | daemon_supervision |
| label | デーモン監視と復旧 |
| aliases | デーモン管理, daemon supervision, daemon_supervisor, watchdog, heartbeat, health check, 自動再起動, 全再起動セーフティ, stale daemon, ninja_monitor常駐, inbox_watcher常駐, ntfy_listener常駐, composite hash, プロセス復旧 |
| skills | reset-layout |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/daemon_supervisor.sh` |
| file | `scripts/ninja_monitor.sh` |
| file | `scripts/inbox_watcher.sh` |
| file | `docs/operations/daemon_runbook.md` |
| cmd | `cmd_2873` デーモン統一管理 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-19T14:43:18+09:00 デーモン異常は頻出する。異常時に全再起動のセーフテーの仕組みはないのか？ |
| file | `scripts/daemon_watchdog.sh` デーモンcron監視+自動再起動(ninja_monitor/ntfy_listener/inbox_watcher) |

## openpbx_reference — OpenPBX(コリ先生PBX MVP)

| 属性 | 値 |
|------|---|
| id | openpbx_reference |
| label | OpenPBX(コリ先生PBX MVP) |
| aliases | OpenPBX, コリ先生, tanimurahifukka, Asterisk PBX, command-room-ai, DAWN SERIES |
| skills | なし |

| 種別 | パス/参照 |
|------|----------|
| discussion | 2026-05-19 殿確認 |
| url | `https://github.com/tanimurahifukka/openpbx` |

## causal_traversal_pipeline — 因果辺トラバース統合パイプライン(Obsidian×セマンティック)

| 属性 | 値 |
|------|---|
| id | causal_traversal_pipeline |
| label | 因果辺トラバース統合パイプライン(Obsidian×セマンティック) |
| aliases | 因果辺トラバース, causal_traversal, 因果辺拡張, Obsidian統合パイプライン, backlink traverse, 概念拡張検索, semantic causal integration |
| skills | なし |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/semantic_search.sh` |
| file | `scripts/causal_backlinks.sh` |
| file | `scripts/semantic_map_generate.sh` |
| cmd | `cmd_2818` 因果NW導入 |
| cmd | `cmd_2860` 因果辺抽出 |
| cmd | `cmd_2866` 統合パイプライン |

## infrastructure_ops — インフラ運用基盤

| 属性 | 値 |
|------|---|
| id | infrastructure_ops |
| label | インフラ運用基盤 |
| aliases | flock, 並行安全, 排他制御, daemon, デーモン, daemon management, デーモン管理, daemon_supervisor, watchdog, auto restart, 自動再起動, heartbeat, health check, inbox_watcher, ninja_monitor, ntfy_listener, プロセス管理, 重複実行, WSL2 NTFS, デーモン異常, 全再起動セーフティ, デーモンが無事に再起動できているか確認せよ |
| skills | reset-layout |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/ninja_monitor.sh` |
| file | `scripts/inbox_watcher.sh` |
| file | `scripts/daemon_supervisor.sh` |
| file | `scripts/ntfy_listener.sh` |
| file | `context/infrastructure.md` |
| cmd | `cmd_2872` cmd_complete_gate flock追加 |
| cmd | `cmd_2873` デーモン統一管理 |
| file | `scripts/dashboard_auto_section.sh` ダッシュボードリアルタイムステータス自動生成 |
| file | `scripts/auto_deploy_next.sh` サブタスク自動連続配備(auto_deployフラグ/blocked_by/忍者空き制御) |
| file | `scripts/reset_layout.sh` agentsウィンドウペイン配置一発復元 |
| discussion | `queue/lord_conversation.jsonl` 2026-05-21T02:45:19+09:00 デーモンが無事に再起動できているか確認せよ |

## gate_quality_framework — ゲート品質統合フレームワーク

| 属性 | 値 |
|------|---|
| id | gate_quality_framework |
| label | ゲート品質統合フレームワーク |
| aliases | gate統合, startup gate, 起動チェック, gate_shogun_startup, gate_karo_startup, gate_gunshi_startup, gate_cmd_state, gate_lesson_health, gate_enforcement_audit, gate偽陽性, WARN集計, BLOCK集計, gate_fire_log, cmd_save, quality_gate, 品質ゲート, BLOCK理由一覧, トリガーマップ, sh origin空 noneをBLOCK化 因果NW強制, sh preflightにtarget path git log自動表示, context_freshness_check, コンテキスト鮮度 |
| skills | |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/gates/gate_shogun_startup.sh` |
| file | `scripts/gates/gate_karo_startup.sh` |
| file | `scripts/gates/gate_gunshi_startup.sh` |
| file | `scripts/gates/gate_cmd_state.sh` |
| file | `scripts/gates/gate_lesson_health.sh` |
| file | `scripts/gates/gate_enforcement_audit.sh` |
| file | `scripts/gates/gate_autofix_proposal.sh` |
| file | `scripts/context_freshness_check.sh` |
| file | `scripts/gates/gate_ninja_workaround_rate.sh` |
| file | `scripts/cmd_save.sh` |
| file | `context/growth-loop.md` |
| cmd | `cmd_2897` ac_phase_mixing commit FP除外 |
| cmd | `cmd_2898` cmd_save BLOCK時トリガーマップ一括表示 |
| cmd | `cmd_2902` 強化 — cmd_save.sh origin空/noneをBLOCK化(因果NW強制) (`tests/unit/test_cmd_save_block_aggregation.bats`, `tests/unit/test_cmd_save_command_steps_vs_ac.bats`, `tests/unit/test_cmd_save_diagnose.bats`) |
| causal | `cmd_2902` origin: [[origin_none_passthrough]] -> [[causal_edge_zero]] -> [[semantic_reflux_dead]] |
| cmd | `cmd_2905` 強化 — cmd_save.sh preflightにtarget_path git log自動表示 (`scripts/cmd_save.sh`, `tests/unit/test_cmd_save_bundle.bats`) |
| cmd | `cmd_2909` (`scripts/gates/gate_karo_startup.sh`, `tests/unit/test_gate_karo_startup.bats`) |
| file | `scripts/ac_physical_verify.sh` AC物理検証(ファイルパス/行番号/§実在確認) |
| file | `scripts/model_analysis.sh` モデル5軸分析(CLEAR率/コスト効率/専門性/安定性/cmd-CLEAR比) |
| cmd | `cmd_2918` 強化: 将軍startup gateにL7 NO_MATCH率計測セクション追加 (`queue/reports/kagemaru_report_cmd_2918.yaml`, `scripts/gates/gate_shogun_startup.sh`, `tests/unit/test_gate_shogun_startup.bats`) |
| causal | `cmd_2918` origin: [[L7_shogun_gate_blind_spot]] -> [[karo_only_no_match]] -> [[shogun_l7_visibility]] |

## lesson_lifecycle — 教訓ライフサイクル管理

| 属性 | 値 |
|------|---|
| id | lesson_lifecycle |
| label | 教訓ライフサイクル管理 |
| aliases | lesson_write, lesson登録, 教訓登録, 教訓退役, lesson_deprecate, lesson_harvest, lesson_effectiveness, 教訓効果, useful率, 教訓注入, related_lessons, lesson_candidate, 因果ネットワーク, origin, Obsidianリンク, 因果辺, origin_aliases_gap, lessons_karo_limit, LK-A01_v8_absorption, lesson_cycle_unblock, sync_lessons, auto_draft_lesson, draft教訓自動登録 |
| skills | |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/lesson_write.sh` |
| file | `scripts/auto_draft_lesson.sh` |
| file | `scripts/sync_lessons.sh` |
| file | `scripts/lesson_write_karo.sh` |
| file | `scripts/lesson_write_shogun.sh` |
| file | `scripts/lesson_effectiveness.sh` |
| file | `scripts/lesson_harvest.sh` |
| file | `scripts/lesson_deprecate.sh` |
| file | `scripts/lesson_deprecation_scan.sh` |
| file | `scripts/causal_backlinks.sh` |
| file | `projects/infra/lessons_gunshi.yaml` |
| file | `projects/infra/lessons_karo.yaml` |
| file | `projects/infra/lessons_shogun.yaml` |

## bulletin_communication — 掲示板通信基盤

| 属性 | 値 |
|------|---|
| id | bulletin_communication |
| label | 掲示板通信基盤 |
| aliases | bulletin_write, 掲示板, bulletin_board, BULLETIN_NOTIFY, 掲示板投稿, bulletin_archive, bulletin_close, bulletin_confirm, 将軍宛報告, 掲示板は陳腐化していないか？放置されていないか？, 掲示板を確認せよ |
| skills | |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/bulletin_write.sh` |
| file | `scripts/bulletin_archive.sh` |
| file | `scripts/bulletin_close.sh` |
| file | `scripts/bulletin_confirm.sh` |
| file | `queue/bulletin_board.yaml` |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T18:35:21+09:00 掲示板は陳腐化していないか？放置されていないか？ |
| cmd | `cmd_2903` 修正 — bulletin_archive.sh構文バグ+書込み時自動アーカイブ (`tests/unit/test_bulletin_board.bats`) |
| causal | `cmd_2903` origin: [[bulletin_100entries]] -> [[archive_syntax_bug]] -> [[manual_only_no_autopath]] |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T21:37:49+09:00 掲示板を確認せよ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T22:18:56+09:00 掲示板を確認せよ |
| discussion | `queue/lord_conversation.jsonl` 2026-05-20T22:56:21+09:00 掲示板を確認せよ |

## hook_automation_framework — Hook自動化フレームワーク

| 属性 | 値 |
|------|---|
| id | hook_automation_framework |
| label | Hook自動化フレームワーク |
| aliases | PreToolUse, PostToolUse, SessionStart, Stop, pre-bash-combined, post-bash-combined, pre-write-edit-combined, Guard, session_start_inject, stop_check_inbox, hook, フック, 自動化×強制 |
| skills | |

| 種別 | パス/参照 |
|------|----------|
| file | `.claude/hooks/pre-bash-combined.sh` |
| file | `.claude/hooks/post-bash-combined.sh` |
| file | `.claude/hooks/pre-write-edit-combined.sh` |
| file | `.claude/hooks/pre-write-read-tracker.sh` |
| file | `.claude/hooks/pre-edit-pi-inject.sh` |
| file | `.claude/hooks/post-write-edit-combined.sh` |
| file | `.claude/hooks/stop-lint-gate.sh` |
| file | `scripts/hooks/session_start_inject.sh` |
| file | `scripts/hooks/stop_check_inbox.sh` |
| file | `.claude/settings.json` |
| cmd | `cmd_2908` 修正: PostToolUse Guard 0のexit_code抽出バグ修正 (`.claude/hooks/post-bash-combined.sh`, `tests/unit/test_post_bash_combined.bats`) |
| causal | `cmd_2908` origin: [[cmd_2907]] -> [[Guard_0_exit_code_bug]] -> [[shogun_block_freeze]] |
| cmd | `cmd_2916` (`.claude/hooks/pre-write-edit-combined.sh`, `tests/unit/test_write_edit_combined_hooks.bats`) |

## test_quality_framework — テスト品質統合フレームワーク

| 属性 | 値 |
|------|---|
| id | test_quality_framework |
| label | テスト品質統合フレームワーク |
| aliases | テスト統合, test consolidation, テスト品質, test quality, テストファイル整理, 小ファイル統合, test_is_debt, test_cleanup, test_gap, test_file_granularity, script_unit_consolidation, テスト負債, @test境界, test_select, テスト選定 |
| skills | |

| 種別 | パス/参照 |
|------|----------|
| file | `tests/` |
| file | `scripts/test_select.sh` |
| file | `docs/test/acceptance_criteria.md` |
| cmd | `cmd_2893` テスト第1波(10件削除/統合) |
| cmd | `cmd_2894` テスト第2波(51件→6統合) |
| cmd | `cmd_2895` pre-commit WARN(テスト追加時) |
| lesson | テストは負債。3問検証(リグレッション/変更頻度/コスト) |

## semantic_causal_automation — セマンティック因果自動化

| 属性 | 値 |
|------|---|
| id | semantic_causal_automation |
| label | セマンティック因果自動化 |
| aliases | セマンティック因果自動化, 因果辺自動還流, obsidian自動リンク, semantic persistence, リンク滞留解消, 因果ネットワーク自動成長, obsidian_link_stagnation, semantic_map_generate, codd_refactor_registry_stale, semantic searchのヒット率を定量計測し |
| skills | |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/semantic_map_generate.sh` |
| file | `scripts/causal_backlinks.sh` |
| file | `docs/semantic-index/index.md` |
| cmd | `cmd_2885` cmd因果辺をsemantic-mapへ自動還流 |
| cmd | `cmd_2860` origin因果辺→辞書自動注入 |
| cmd | `cmd_2818` 因果NW導入 |

## infra_design_intent — インフラ設計意図カタログ

| 属性 | 値 |
|------|---|
| id | infra_design_intent |
| label | インフラ設計意図カタログ |
| aliases | バグに見える正しい設計, 設計意図, design intent, STALL-GHOST, HOOK-STALE-BUT-BUSY, codex delivery unverified, LOOP-HEALTH-DEBOUNCE, 安全弁, 誤報告防止, インフラバグ調査 |
| skills | |

| 種別 | パス/参照 |
|------|----------|
| file | `docs/research/gunshi_idle_infra_design_intent_catalog_20260520.md` |
| file | `scripts/ninja_monitor.sh` |
| file | `scripts/inbox_write.sh` |
| cmd | `cmd_1150` STALL-GHOSTフィルタ設計元 |
| cmd | `cmd_1445` HOOK-STALE-BUT-BUSY二重確認の設計元 |

## scope_integrity_lifecycle — スコープ鮮度ライフサイクル

| 属性 | 値 |
|------|---|
| id | scope_integrity_lifecycle |
| label | スコープ鮮度ライフサイクル |
| aliases | スコープ清掃, scope integrity, コンテキスト汚染, context contamination, scope_context_stale, 再発防止テンプレート, deploy scope, task scope mismatch |
| skills | |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/deploy_task.sh` |
| file | `queue/tasks/` |
| cmd | `cmd_2887` scope清掃テスト追加 |
| lesson | `LK-A02` スコープ外ファイル混入防止 |

## yaml_safe_write — YAML安全書込み

| 属性 | 値 |
|------|---|
| id | yaml_safe_write |
| label | YAML安全書込み |
| aliases | yaml_field_set, yaml_field_set_batch, yaml.dump禁止, flock, 運用YAML書込み, yaml_field_get, lock_path, YAML構文破壊, yaml safe write, report_field_set, inbox_mark_read, shogun_to_karo parse error |
| skills | |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/lib/yaml_field_set.sh` |
| file | `scripts/report_field_set.sh` |
| file | `scripts/inbox_mark_read.sh` |
| file | `scripts/inbox_write.sh` |
| cmd | `cmd_1399` yaml.dumpデータ消失事故 |
| lesson | `L548` 運用YAMLのyaml.dump禁止 |
| lesson | `L351` insight_write.shのyaml.dump事故 |

## inbox_processing_discipline — inbox処理規律

| 属性 | 値 |
|------|---|
| id | inbox_processing_discipline |
| label | inbox処理規律 |
| aliases | inbox既読スルー, mark_read, inbox無視, 読まずに既読, サボりの精神, Guard 0d, LS048, LS049, LS050 |

| 種別 | パス/参照 |
|------|----------|
| file | `.claude/hooks/pre-write-edit-combined.sh` Guard 0d |
| file | `scripts/hooks/stop_check_inbox.sh` |
| file | `scripts/inbox_mark_read.sh` |
| cmd | `cmd_2922` inbox既読スルー事故→Guard 0d実装 |

## inbox_watcher_process_model — inbox_watcherプロセスモデル

| 属性 | 値 |
|------|---|
| id | inbox_watcher_process_model |
| label | inbox_watcherプロセスモデル |
| aliases | watcher重複, watcher 2プロセス, pgrep 2件, 親子関係, restart_watchers, kill全滅, script change detection, PPID確認 |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/inbox_watcher.sh` |
| file | `scripts/restart_watchers.sh` |
| cmd | `cmd_2924` watcher親子関係誤判断→kill全滅事故 |
