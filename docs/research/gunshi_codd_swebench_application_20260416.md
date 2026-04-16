# CoDD記事#3-#5 SWE-bench知見の将軍システム適用分析

> 軍師分析 2026-04-16
> 依頼: 将軍 (msg_20260416_011028)
> 参照: memory/reference_codd_oshio_articles.md

## §1 おしお殿の3層モデル(#5)と我が軍の対応

| 層 | おしお殿(SWE-bench) | 我が軍(将軍システム) | GAP |
|----|---------------------|---------------------|-----|
| L1 事前コンテキスト | codd extract設計書(構文解析=$0) | deploy_task.sh related_lessons + context_files + engineering_preferences | **量過剰**(§3で定量) |
| L2 事後ハーネス | テストFB + DIVERGENT(2回同失敗→仮説転換) | gate BLOCK + FIX hints + gate_report_autofix.sh | **DIVERGENT欠如**(§2) |
| L3 診断推論 | 「根本原因を書いてから直せ」+ Session State | なぜなぜ7回(将軍のみ) + deepdive追体験(全員) | **忍者レベルで不在**(§2) |

### 核心の発見

おしお殿の#3-#5が示す最重要知見: **情報注入(答えを教える)は退化を招く。思考構造の強制(考え方を教える)は退化しない。**

これは殿の教えと完全に一致:
- deepdive Phase 4: 「理解だけでは行動は変わらない → 自動化×強制」
- 殿: 「原理だけが無限の事象に対抗できる」
- 殿: 「個別の例に落とし込むな、基本原理として取り入れれば無限の事象に対抗できる」

## §2 焦点1: 診断推論の忍者リトライフロー埋込み

### 現状分析

忍者のgate BLOCKリトライフロー:
```
忍者実装 → gate_report_format.sh BLOCK → FIX hints表示 → 忍者修正 → 再提出 → (再BLOCK or CLEAR)
```

FIX hintsの内容(BLOCK_HINT_MAP L2633-2652):
- `report_format`: 「report_field_set.sh使用必須」
- `binary_checks_fail`: 「全ACのチェック完了を確認」
- `fill_this_remaining`: 「全テンプレート値を実際の値に置換せよ」
- etc.

**診断**: 全hintが**WHAT(何をすべきか)を教えている**。WHY(なぜBLOCKされたか)の言語化を要求していない。

### おしお殿#5との対比

おしお殿: 「Diagnose MANDATORY — まず根本原因を書いてから直せ」の1行でリトライ効率が劇的改善。

我が軍: FIX hintは「答え」を教えている = **情報注入 = #3の退化パターン**。
忍者は「ああ、report_field_set.sh使えばいいのか」と答えを受け取り、同じ間違いを繰り返す。

### 改善案: Diagnose Step埋込み

gate BLOCK時にFIX hintを**表示する前に**、忍者に診断ステップを強制:
```
BLOCK検知 → 「なぜBLOCKされたか1行で書け」 → 忍者が原因記述 → FIX hint表示 → 修正
```

**実装レベル**: L4(フロー内埋込みBLOCK)が理想。
- gate_report_format.sh BLOCK時に `diagnose_reason:` フィールドを報告YAMLに追加必須化
- diagnose_reason空 → 再BLOCK(修正を受け付けない)
- diagnose_reasonがFIX hintのコピペ → 再BLOCK(思考していない検出)

### DIVERGENTの欠如

おしお殿#4: 「2回同じ失敗→仮説ごと疑え」のDIVERGENT戦略。

我が軍: gate BLOCKの同一BLOCK理由2回連続をトラッキングしていない。
gate_fire_log.yamlに全BLOCK履歴はあるが、「同一忍者×同一理由の連続回数」を計数していない。

**改善案**: gate_report_format.sh内で同一忍者の直近BLOCK理由をチェック。2回連続同理由→
```
★ DIVERGENT: 同じ理由で2回BLOCK。修正方法が間違っている可能性あり。
前提ごと見直せ: {前回のdiagnose_reason}は正しいか？
```

## §3 焦点3: lessons注入の情報注入vs思考構造強制の監査

### 定量データ

| 指標 | 値 | 判定 |
|------|-----|------|
| PJ教訓(dm-signal) 総数 | 628件 | — |
| IF-THEN形式(思考構造型) | 82件 (13%) | **少** |
| 直接指示型(情報注入型) | 546件 (86%) | **多** |
| 1タスクあたりrelated_lessons注入数 | 10件 | **多**(#3「渡しすぎると退化」) |
| 忍者のlessons_useful有用率 | 16% (12/72) | **低** |
| 無用と判定された教訓 | 84% (60/72) | **ノイズ過多** |

### 因果推論

```
causal_chain:
情報注入型教訓86%(直接指示)
→ 10件一括注入(deploy_task.sh)
→ 忍者が読むが大半は今のタスクと無関係(84%がuseful=false)
→ 注意資源の浪費(情報過多=退化リスク)
→ 有用16%の教訓すら埋もれる
→ lessons_useful回答自体が形骸化(とりあえずfalse)
→ 教訓システムの信頼性低下
= 負の複利
```

### おしお殿#3との対比

#3結果: codd extract設計書(構文解析、正確な情報)→+30%(退化ゼロ)。AI分析等5施策(推測・要約を含む情報)→全退化。

我が軍のrelated_lessons: 教訓のsummary/detail(テキスト要約)を10件注入 = #3の「AI分析等5施策」に近い構造。
教訓のIF-THEN形式(条件+行動)のみが構文解析的な正確さを持つ。

### 改善案: 3段階フィルタ

1. **量を絞る**: 10件→3件。タスクのAC/target_pathとの関連度スコアで上位3件のみ注入
2. **形式を変える**: 直接指示(「〜せよ」)→IF-THEN形式(「IF〜 THEN〜 BECAUSE〜」)に変換して注入。思考構造の強制
3. **事前→事後に移す**: gate BLOCK時に関連教訓を表示(L2事後ハーネス)。事前注入(L1)の代替。失敗した後に表示される情報の方が吸収される(#4の知見)

## §4 焦点2: Session State=/clear跨ぎ失敗履歴引継ぎ

### 現状分析

おしお殿#5のSession State = 失敗した手順の記録を次のリトライに引き継ぐ。ステートレス→ステートフル。

我が軍の対応:

| 仕組み | Session State性 | 問題 |
|--------|----------------|------|
| lessons.yaml | ✓ /clear跨ぎ | PJ全体の蓄積。個別タスクの失敗履歴ではない |
| deepdive*.md | ✓ /clear跨ぎ | 将軍/家老の思考過程。忍者レベルでは不在 |
| gate_fire_log.yaml | ✓ /clear跨ぎ | BLOCK履歴あり。だが忍者に自動提示されない |
| ninja_weak_points | ✓ /clear跨ぎ | deploy_task.shが注入。WA率・パターン情報あり |
| gate_blocks (hint付き) | ✓ /clear跨ぎ | 過去のBLOCK理由+hint。個別忍者向け |

**GAP**: 「この忍者がこのcmdで前回どこで失敗したか」のSession State（カルテ）がない。
ninja_weak_pointsは全タスク横断の傾向。cmd固有の失敗履歴（「AC2でbinary_checks形式ミス→修正→AC3でcommit漏れ」）は引き継がれない。

### 改善案: タスクレベルSession State

gate BLOCK時に `queue/session_state/{ninja}_{cmd}.yaml` に失敗記録を自動蓄積:
```yaml
- attempt: 1
  block_reason: binary_checks_fail
  diagnose_reason: "AC2のcheck名が汎用的すぎた"  # §2の診断ステップで記入
  timestamp: "2026-04-16T01:30:00"
- attempt: 2
  block_reason: commit_missing
  diagnose_reason: "git addを忘れた"
  timestamp: "2026-04-16T01:45:00"
```

/clear後の再配備時に `session_state` がタスクYAMLに自動注入される。
前回の失敗→診断→修正の履歴を持って再開 = ステートフルリトライ。

## §5 統合: 3層モデルの我が軍版

| 層 | 現状 | 改善後 |
|----|------|--------|
| L1 事前 | related_lessons 10件(86%情報注入) | **3件に絞り、IF-THEN形式に変換** |
| L2 事後 | gate BLOCK + FIX hints(答え注入) | **Diagnose Step + DIVERGENT + 事後教訓表示** |
| L3 診断 | 将軍のみ(なぜなぜ7回) | **忍者レベルでdiagnose_reason必須 + Session State** |

### 優先順位(改善の複利で判定)

1. **Diagnose Step** (§2): 原理1行「根本原因を書いてから直せ」の埋込み。最小実装。複利最大。gate_report_format.sh BLOCK出力に1行追加するだけ
2. **related_lessons絞り込み** (§3): 10→3件。有用率16%→推定40%+。deploy_task.shの注入ロジック改修
3. **DIVERGENT** (§2): 同一理由2回連続検出。gate_fire_log参照+条件分岐追加
4. **Session State** (§4): タスクレベル失敗履歴。新規ファイル+deploy_task.sh参照追加。最も工数大

### 実装コスト見積もり

| 改善 | 変更ファイル | 行数 | 防御Level |
|------|-------------|------|-----------|
| Diagnose Step | gate_report_format.sh + 報告テンプレート | ~20行 | L4(フロー内BLOCK) |
| lessons絞り込み | deploy_task.sh inject_related_lessons() | ~30行 | L3(自動生成) |
| DIVERGENT | gate_report_format.sh + gate_fire_log参照 | ~40行 | L4 |
| Session State | 新規session_state.sh + deploy_task.sh | ~80行 | L3 |

## §7 メタなぜなぜ: 計測対象のズレ(殿指示2026-04-16)

### なぜなぜ7回

| # | 問い | 答え |
|---|------|------|
| 1 | なぜrelated_lessons有用率が26%か | 注入教訓の74%がタスクと無関係(tag matching精度低) |
| 2 | なぜ無関係な教訓が注入されるか | 628件中86%が直接指示型(条件不明確)。IF-THEN=13%のみ |
| 3 | なぜ有用率26%が放置されたか | **gate_lesson_health.shはreferenced率76%(回答率)を計測。useful率(有効率)は計測対象外** |
| 4 | なぜ計測対象がズレたか | 「参照したか」(行動有無)と「役に立ったか」(行動効果)を混同 |
| 5 | なぜ効果を計測しなかったか | **退化(regression)の概念が不在。「教訓は多いほど良い」が暗黙の前提** |
| 6 | なぜ介入効果計測の文化がないか | gate BLOCK/CLEAR+workaround率に計測が集中。介入前後の因果比較なし |
| 7 | **根因**: なぜA/B比較がないか | **おしお殿は30問で全施策のbefore/after退化率を計測→5施策が全退化と判明。我が軍はゼロ** |

### 根因の構造

```
causal_chain:
退化の概念不在
→ 「介入=改善」を暗黙に仮定
→ 教訓は多いほど良い(未検証)
→ 628件蓄積+10件注入
→ useful率26%(74%ノイズ)
→ gateはreferenced率(回答率)で「OK」判定
→ 問題が表面化しない
→ コンテキスト断捨離(#3)に到達するまで気づかない
= 計測対象のズレが盲点を構造的に生む
```

### データ証拠

| 指標 | 値 | 意味 |
|------|-----|------|
| gate_lesson_health referenced率 | 76% | 「回答したか」→OK判定。偽の健全性 |
| lesson_impact.tsv useful率 | 26.4% (57/216) | 「役に立ったか」→ALERT水準。真の健全性 |
| useful率0%の教訓(N≥3) | 10件(L088,L465等) | 3回以上注入されて毎回無用。純ノイズ |
| useful率≥50%の教訓(N≥2) | 12件(L085=83%等) | 真のシグナル。L085は5/6回有用 |
| 教訓別useful率の中央値 | 20% | 大半の教訓はノイズ寄り |

### 改善案: 計測対象の修正

1. **gate_lesson_health.shの計測指標変更**: referenced率→**useful率**に閾値変更。データ源は同じlesson_impact.tsv。問いを変えるだけ
2. **useful率0%教訓の自動除外**: inject_related_lessons()で有用率0%(N≥3)の教訓を注入候補から除外。既にuseful_rate < 15%のdecay(0.5倍)はあるが、0%は除外が正しい
3. **介入効果計測の新設**: 教訓注入/gate追加の前後でworkaround率・BLOCK率をbefore/after比較。おしお殿のSWE-bench計測方法論を移植

## §6 CS観点チェックリスト

- CS1(ソース全量): #0-#5全6記事のmemory記録を全文参照 ✓
- CS2(自システムデータ): lessons_useful有用率16%、IF-THEN率13%を実測 ✓
- CS3(実コード比較): BLOCK_HINT_MAP(L2633-2652)の全エントリを確認 ✓
- CS4(行動変換): 4改善案を優先順位付きで提案。家老にinbox_writeで送信予定
- CS5(未検証角度): DIVERGENT効果の定量予測は未実施(gate_fire_log同一理由連続の計数が必要)
- CS6(因果推論): §3に因果鎖記載 ✓
