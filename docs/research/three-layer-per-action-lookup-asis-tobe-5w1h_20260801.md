# 行動時三層確認(per-action lookup)設計書 — AsIs/ToBe 5W1H

- 版: v1.1 (2026-08-01 16:02 将軍自己敵対レビューで6穴を是正。v1.0=15:46起草)
- 発端: 殿指摘2026-08-01 15:40「三層確認が行われるのはどのタイミングか。俺はすべての行動の前だと指示した。修正はなぜ効果がないんだ」
- 状態: 設計のみ。実装凍結中(殿の指示があるまで実装しない)
- 関連: [[殿下知_修正のための修正禁止_20260801]](超速回転二問判定) / [[三層記憶根幹バグ]] / hidden-infra-rollback設計書(別件・並行)

## §0 結論(1行)

三層検索が「殿の入力語でターン冒頭に1回」しか走らない構造を、「各ツール実行前に、その行動の主題語で検索して結果を注入する」構造へ、既存three_layer_preflight/既存注入スロットの拡張のみで変える(新デーモン・新BLOCKなし)。

## §1 AsIs(現状 — 2026-08-01将軍が実装・実測で確定)

### 1.1 現在の三層確認タイミング(全4箇所)
| タイミング | 実体 | 検索が走るか | 読ませる力 |
|-----------|------|------------|----------|
| 殿入力時(UserPromptSubmit) | prompt_state_inject.sh→three_layer_preflight.sh issue: 三層検索+証跡発行+MEM雛形注入 | 走る(ターン1回) | 注入のみ(読み飛ばし可能) |
| Bash前(PreToolUse) | pre-bash-combined.sh: 証跡の存在検査(fail-closed)+prompt初回のみ証跡ダイジェスト再表示(3f07bb553 本日追加) | 走らない | 再表示のみ・初回1回 |
| Write/Edit前 | pre-write-edit-combined.sh: 証跡の存在検査のみ | 走らない | なし |
| 応答終了時(Stop) | stop_check_inbox.sh: [MEM:]引用タグ検査(BLOCK) | 走らない | 応答末尾のみ・全文再生成の副作用(殿への二重出力) |

### 1.2 構造的ギャップ(効果がない真因)
- **queryが殿の入力語から機械抽出した先頭1語で固定**。本日実測: 下問「Compare summary…CDPとコードで確認」→query='Compare'(CDPは{4,}文字フィルタでも先頭優先でも拾われず)。別ターンではquery='-'で三層とも空注入。
- **行動の主題はツール呼出しの瞬間に決まる**(CDP接続・fullrecalculate差配・inbox送信…)が、その主題で検索する箇所がゼロ。ターン冒頭検索では原理的に拾えない。
- 歴代修正の系譜: 07-10 011bc13d1(証跡強制導入)→07-27 ee2f4d75c(雛形へ原文同梱)→08-01 3f07bb553(初回ダイジェスト再表示)。**全てターン冒頭1回検索の強化**であり、行動時検索には一度も到達していない。
- 実害(本日3連発): CDP独自試行錯誤(正本knowledge:776999eeを引かず)→fullrecalculate誤差配(ETL cron設計knowledge未参照)→いずれも「その行動の主題で三層を引けば1手で正解に到達した」ことを事後確認済み。

### 1.25 v1.1追加 — 自己敵対レビューで確定した追加の穴(AsIsバグとして修正対象)
- **穴1(対象ツールの全数未列挙)**: v1.0はBash/Write/Editのみ想定。Skill・Task(Agent)・NotebookEdit等のPreToolUse hook配線の有無は**未検分**。実装前に.claude/settings.jsonのhook matcher全数を検分し、状態変更・外部作用を持つツールの対象範囲を確定する(検分自体をACへ昇格=AC4)
- **穴2(空注入バグ)**: 本日実測でquery='-'の時、ダイジェストが三層とも空のまま注入された(枠だけ表示=ノイズ)。ヒント0件時は沈黙する仕様をToBeに含める(R1から仕様へ昇格)
- **穴3(概念抽出の入力範囲が未定義)**: Bashのtool_inputはheredoc等で数KBになりうる。抽出対象は「コマンド先頭N文字(既定512)+cmd0のbasename+ファイルパス成分」に限定し、全文scanしない(コスト上限の明文化)
- **穴4(デバウンス単位が曖昧)**: 単位=agent×概念。同一概念はprompt跨ぎでも既定300s抑止。ダイジェスト(prompt単位)とは独立のmarker系列とし、相互干渉させない
- **穴5(二重注入ノイズ)**: ターン冒頭のpreflight証跡queryと同一概念のlookupはスキップ(冒頭注入で既に提示済みのため)。異なる概念のみ行動時に注入
- **穴6(Codex配線が抽象的)**: 忍者はCodex CLIでhook経路=`.codex/hooks.json`(Claude Codeスクリプト共有、BLOCK=exit 2)。additionalContext注入がCodex側で同義に機能するかは**未検証**であり、将軍(Claude)で実証後、Codex側は注入表示の実機確認を独立ACとして扱う

### 1.3 既存資産(車輪の再発明防止・再利用対象)
- 概念辞書: `context/semantic-map.md`+`docs/semantic-index/index.md`のalias表(semantic_search.shが使用中)
- 検索実行体: `scripts/hooks/three_layer_preflight.sh`(三層検索・キャッシュ・タイムアウト・証跡発行を保有)
- 注入スロット: pre-bash-combined.sh / pre-write-edit-combined.shのadditionalContext出力経路(grep注入・ダイジェスト注入で実績)
- デバウンス実装: pre_bash_memory_inject系のhash_file方式(30s/300s実績)
- 計測台帳: logs/defense_overhead.jsonl(wall_ms記録の既存契約)

## §2 ToBe(あるべき状態)

1. **すべての状態変更ツール実行前**(Bash/Write/Edit)に、そのtool_inputから行動主題の概念語を抽出し、三層検索した結果がadditionalContextとして注入される
2. 同一概念は債務なく再検索しない(概念単位デバウンス+DB指紋キャッシュ=既存方式)ため、超速回転を落とさない(1回あたり目標: キャッシュヒット時ほぼ0ms・ミス時も既存preflight実測11-772ms帯)
3. 注入はBLOCKしない情報提供(構造型: 読む材料が行動と同じ画面に必ず出る)。作文強要・停止は追加しない(殿裁定「削るな速くしろ」「表示型の作文強要は邪魔者」に適合)
4. 概念抽出はsemantic-mapのalias辞書との照合を第一とし、辞書ヒットなし時のみ汎用token抽出(アクロニム[A-Z]{2,}含む=INS-b670の既知穴も同時に塞ぐ)。入力はtool_input先頭512文字+cmd0 basename+パス成分に限定(穴3)
5. wall_msをdefense_overhead.jsonlへsource:per_action_lookupで記録し、台帳高速化レーンの監視対象に載る
6. ヒット0件時は沈黙(空枠の注入禁止=穴2)。冒頭preflightと同一概念はスキップ(二重注入禁止=穴5)。デバウンスはagent×概念で300s・ダイジェストのmarkerと独立(穴4)
7. 対象ツールは実装前のhook matcher全数検分で確定(穴1)。Codex側は注入表示の実機確認を独立に行う(穴6)

## §3 5W1H

- **WHY**: 殿指示「すべての行動の前に三層記憶を確認」が、現機構では「ターン冒頭に殿の入力語で1回」に縮退しており、行動主題の知識(CDP正本・ETL設計等)が原理的に届かない。本日3連発の実害で構造確定
- **WHAT**: §2の5項。実装対象は(1)three_layer_preflight.shへ`lookup <query>`サブコマンド追加(検索+キャッシュ+台帳記録、証跡発行とは独立) (2)pre-bash/pre-write-editの既存注入スロットに概念抽出→lookup呼出し→注入を追加 (3)概念抽出はsemantic-map alias照合→汎用token(アクロニム含む)の2段
- **WHEN**: hidden-infra rollback完了後(運用中核が健全化してから)。実装は殿の指示があるまで凍結
- **WHERE**: scripts/hooks/three_layer_preflight.sh、.claude/hooks/pre-bash-combined.sh、.claude/hooks/pre-write-edit-combined.sh(いずれも既存ファイルの拡張。新規ファイルなし)
- **WHO**: 実装=家老差配(忍者)。設計レビュー=家老+軍師敵対レビュー。検証=将軍が実ターンで注入の有無・内容適合を一次確認
- **HOW**: 既存grep注入・ダイジェスト注入と同形の関数追加→bats(発火1/非発火1/デバウンス/空query安全)→実ターンA/B検証(同一下問でlookupあり/なしの正本到達手数を比較)→defense_overhead台帳でwall_ms回帰監視

## §4 採用二値AC

- AC1: Bash/Write/Editの各PreToolUseで、tool_input由来の概念語による三層検索結果が注入される(発火fixture)一方、同一概念の連続実行では再検索されない(デバウンスfixture)か(yes/no)
- AC2: 本日の失敗2例の再現入力(CDPコマンド/fullrecalculate差配文)で、正本知識(knowledge:776999ee / ETL cron設計)が注入内容に含まれるか(yes/no)
- AC3: per_action_lookupのwall_msが台帳に記録され、キャッシュヒット時の追加コストが既存hook実測帯に収まるか(yes/no)
- AC4: .claude/settings.jsonのPreToolUse matcher全数検分の結果(対象ツール一覧と配線有無)が設計書に追記され、状態変更ツールで注入対象外のものが0か、または対象外の理由が明記されているか(yes/no)
- AC5: ヒット0件時に注入が発生しない(沈黙fixture)+冒頭preflightと同一概念でスキップされる(重複排除fixture)か(yes/no)

## §5 リスクと未解決

- R1: 概念抽出の精度 — 辞書ヒットなし+汎用tokenノイズで無関係知識が注入される可能性。対策: 注入は上位1概念に限定(沈黙・重複排除はToBe 6へ仕様昇格済み)
- R2: トークン消費増 — 概念単位デバウンス(既定300s)と1概念限定で抑制。台帳で実測し、超過なら閾値調整
- R3(未解決): 概念抽出をsemantic_search.shと共通化するか(SSOT)、hook内に軽量再実装するか — 起動コスト(WSL process+SQLite)の実測で決める
- R4(未解決): 家老・軍師への展開時期 — 将軍(Claude)で実証後。忍者(Codex)は穴6の実機確認が前提
- R5(v1.1追加・未解決): 注入を「読んだ」ことの検証は本設計でも未強制のまま(注入=読む材料の密着まで)。読んだかの計測は[MEM:]引用元とlookup注入内容の一致率で事後観測する案があるが、作文強要への転化リスクがあるため導入判断は運用実測後
- R6(v1.1追加): lookup検索自体の障害(DB lock・timeout)がツール実行を遅延させるリスク — lookupはtimeout付き(既定5s)+失敗時は沈黙でツール実行を妨げない(fail-open。証跡verifyのfail-closedとは役割が異なるため混同しない)

## 因果リンク
origin: [[殿指摘_三層確認タイミング_20260801]] -> [[ターン冒頭1回検索への縮退]] -> [[per_action_lookup設計]]
