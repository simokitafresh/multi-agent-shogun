# Karo Procedures (手順書)

> `instructions/karo.md` の索引から参照される詳細手順。
> 恒久ルール・forbidden_actions は karo.md 本体を参照。

## §1 cmd完了時自己採点（karo_workaround）

GATE CLEAR後、dashboard.mdのcmd完了報告に以下を併記:

```
karo_workaround: yes/no
workaround_detail: "(yesの場合) 何を代筆/回避したか1行"
```

- **yes記録対象**: 忍者報告の代筆、GATE BLOCKの回避的修正、品質問題の黙認
- **no記録対象**: 全て正規フローで完了
- **蓄積効果**: 「家老が繰り返し消火している箇所」が可視化され、構造改善の優先順位が判明する

## §2 workaround軍師フィードバック・CI緑維持・GATEフィードバック通知

### workaround軍師フィードバック（パートナー学習ループ）

karo_workaround: yes記録時、軍師にフィードバックを送信する。軍師のレビュー基準にworkaround原因を還流させ、パートナーとして共に改善する。

```
1. karo_workarounds.yamlに記録（従来通り）
2. workaround: yesの場合、軍師に通知:
   bash scripts/inbox_write.sh gunshi "cmd_XXXX workaround発生。原因: {root_cause}。detail: {workaround_detail}" workaround_feedback karo
3. 軍師は受信した原因パターンをレビュー基準に反映（軍師側の学習ループ）
```

**positive_rule**: karo_workaround: yes記録後は必ず軍師にworkaround_feedbackを送れ
**reason**: workaroundの原因を軍師に共有することで、軍師のレビューで事前に防げるようになる。パートナーとして情報を共有し、互いの学習ループを回す

### CI緑維持

push済みcmdでGATE実行時、`cmd_complete_gate.sh`がCI(test.yml)の最新結果を自動チェックする。CI赤はGATE WARNINGとして出力される（BLOCKではない）。CI赤が続く場合は原因調査cmdの発令を検討せよ。

### GATEフィードバック通知（軍師学習ループ）

GATE結果確定後、軍師がレビューしたcmdは結果を軍師にフィードバックする。軍師のレビュー基準改善に不可欠。

```
1. GATE結果確定（CLEAR/FAIL/BLOCK）
2. そのcmdが軍師レビュー済みか確認（dashboardの「軍師: APPROVE」等の記録）
3. 軍師レビュー済みの場合、inbox_writeで通知:
   bash scripts/inbox_write.sh gunshi "cmd_XXXX GATE {CLEAR/FAIL/BLOCK}。verdict: {APPROVE/REQUEST_CHANGES}。{差分サマリ}" review_feedback karo
4. 差分サマリの記載内容:
   - APPROVE→CLEAR: 正常完了（簡潔に1行）
   - APPROVE→FAIL/BLOCK: 軍師が見落とした問題（GATE FAIL原因の要約）★必須通知
   - REQUEST_CHANGES→CLEAR: 軍師の指摘が防いだ問題
```

**★ APPROVE→GATE FAIL/BLOCKは必ず通知**。軍師のレビュー基準に穴がある証拠であり、軍師の学習ループの最重要燃料。

**positive_rule**: 軍師レビュー済みcmdのGATE結果はreview_feedbackで軍師に必ず通知せよ。特にAPPROVE→FAIL/BLOCKは省略厳禁
**reason**: フィードバックなき品質ゲートは学習しない。軍師がレビュー基準を改善するにはGATE結果の還流が必須

## §3 ラルフループ自動修復（穴検出WARN→即配備）

教訓登録(`lesson_write.sh`)後にREFLUX_CHECK WARNが出た場合、修復タスクを自動生成し即配備する。

```
1. lesson_write.sh実行 → stdoutを変数に保持
   OUTPUT=$(bash scripts/lesson_write.sh {pj} "{title}" "{detail}" "{src_cmd}" "karo" 2>&1)
   echo "$OUTPUT"
2. WARNあり？ → ralph_loop_closer.shで修復タスク雛形を取得
   TASK=$(echo "$OUTPUT" | bash scripts/ralph_loop_closer.sh {pj} "{title}" "{detail}" [src_cmd])
3. 雛形あり？ → idle忍者に即配備
   if [ -n "$TASK" ]; then
     echo "$TASK" > queue/tasks/{idle_ninja}.yaml
     bash scripts/deploy_task.sh {idle_ninja}
   fi
4. PI新規追加のみ将軍に報告（dashboard.md経由）。ランブック/instructions追記は家老判断で即実行
5. WARNなし → 通常フロー継続
```

**positive_rule**: REFLUX_CHECK WARNは即修復タスク配備。判断を挟まない。MISSINGは機械的に修復する
**reason**: 判断を挟むと穴が放置される。ラルフループ=永遠に回す学習ループの鍵

## §4 gate穴検出3問の処理手順

`gate_improvement_trigger.sh`がgate ALERTを検知すると、穴検出3問が家老inboxに`type: gate_alert`で送信される。受信後の処理フロー:

```
1. 受信: inbox type: gate_alert を検知。alert_id(GA-連番)と検知内容・3問を確認
2. 配備: idle忍者に調査タスクを配備。3問への回答をACとする
   - AC1: Q1(直接原因と根本原因の仮説)
   - AC2: Q2(横展開候補の洗い出し)
   - AC3: Q3(防御層の提案)
3. 登録: 回答レビュー → lesson_write.sh で教訓登録
   （ラルフループ自動修復が連動: REFLUX_CHECK WARN時は即修復タスク配備）
4. 修正: 防御層反映（context/instructions/gateスクリプト等の修正cmd起票を将軍に提案）
5. 更新: logs/gate_alerts.yaml の該当alert_idのimprovement_doneをtrueに更新
   bash scripts/yaml_field_set.sh logs/gate_alerts.yaml "alerts[alert_id=GA-XXX].improvement_done" true
   （yaml_field_set非対応の場合はEdit toolで直接更新）
```

**positive_rule**: gate_alert受信→5ステップを順守。調査を省略して自動消火（直接修正・自動委任）するな
**reason**: 自動消火は問題を隠し先送りして被害を拡大させる（殿厳命）。穴検出3問→教訓化→防御層強化が根本解決への唯一の道

## §5 忍者報告レビューフロー（軍師+家老パートナー方式）

忍者報告受領時、軍師と家老がパートナーとして品質を担保する。軍師が一次レビュー、家老が教訓抽出+GATE進行を担当。独立した役割でありながら、二人でひとつのセットとして機能する。

### フロー

```
1. 忍者報告受領 → 軍師にreport_review依頼:
   bash scripts/inbox_write.sh gunshi "cmd_XXXX {ninja}報告レビュー依頼。report_YAML参照" report_review karo
2. 軍師レビュー結果をinboxで受領（type: report_review_result）:
   a. LGTM → 家老は自身の役割に集中:
      - 教訓抽出（lesson_write.sh）
      - context還流判定（§3参照）
      - GATE進行（cmd_complete_gate.sh）
      - verdict: PASS確定
   b. FAIL → 家老が軍師の所見を受けて修正方針を判断:
      - Re-review Loop（修正task配備→再レビュー）or 修正task配備
      - 軍師の指摘を起点に家老が方針決定（パートナーとして連携）
   c. 軍師レビュー未完了（タイムアウト/未応答）→ フォールバック:
      - 従来通り家老がフルレビュー（レビュー品質チェック→報告YAML精査）
```

**positive_rule**: 忍者報告受領時はまず軍師にreport_review依頼を送れ。軍師がレビュー、家老が教訓抽出+GATE進行。フォールバック時のみ家老がフルレビュー
**reason**: 軍師と家老はパートナーとして品質を担保する。各自の強みに集中することで全体の品質が上がる（cmd_1144設計→cmd_1225パートナー化）

## §6 レビュー品質チェック（フォールバック時・家老フルレビュー開始時必須）

フォールバック（軍師未完了）で家老がフルレビューを行う場合の最初のステップ。報告YAML精査の前にこの3問を通せ。

| # | チェック | Why | OK例 | NG例 |
|---|---------|-----|------|------|
| Q1 | 忍者の報告を代筆・修正して通していないか | 代筆=消火。忍者の品質問題を隠蔽し教訓還流が止まる | 報告に不備→差し戻し指示 | 報告の文面を家老が書き直してPASS |
| Q2 | GATE BLOCKの根本原因を特定したか | 回避策で通過させると同じ穴が再発する | 根本原因特定→修正cmd起案 | YAMLフィールド手動修正でGATE通過 |
| Q3 | この対処で次のcmdの品質が上がるか | 消火(今だけ通す)vs成長(仕組みが強くなる)の分岐点 | 教訓登録+防御層追加 | 今回だけの例外処理で完了 |

いずれかNG → 対処を見直してからレビュー続行。

## §7 一次データ不可侵チェック (Primary Data Review)

レビュー・報告受領時に、一次データ（外部知識）と自軍の解釈が混在していないか確認せよ。

| チェック項目 | PASS | FAIL |
|------------|------|------|
| 一次データが原典のまま保存されているか | 原文・原式がそのまま記載 | 要約・意訳・改変が混入 |
| 解釈・適用が別セクション/別ファイルに分離されているか | 明確に分離 | 同一セクションに混在 |

FAIL検出時は忍者に差し戻し、分離を指示せよ。本ルールは全PJ共通（López de Pradoに限らず全外部知識に適用）。

## §8 lesson_candidate レビュー差し戻し条件

報告受領時に以下を確認し、該当すれば差し戻せ:

| 条件 | 判定 | 対処 |
|------|------|------|
| found: false かつ no_lesson_reason が空 | FAIL | 差し戻し。「no_lesson_reasonに理由を1文で書け」と指示 |
| found: true かつ title/detail が空 | FAIL | 差し戻し。「title/detailを記載せよ」と指示 |
| found: false かつ no_lesson_reason 記入あり | PASS | 理由が妥当か確認のうえ受理 |

**reason**: 全タスクに学びがある。found:falseはラルフループの燃料切れを意味する。理由なきfound:falseを許容すると教訓還流が止まる。

## §9 全cmd軍師レビュー（並行方式）

全cmdは軍師レビューを経る。ただし**忍者配備と軍師レビュー依頼を並行実行**し、軍師の承認を待たずに配備する。

### 例外条件（軍師レビュー省略可）

以下のいずれかに該当するcmdは軍師レビューを省略してよい:
- **(a)** 殿が「緊急」と明示的に指示したcmd
- **(b)** 1AC以下の軽微な修正cmd（typo修正等）

上記以外は全て軍師レビュー必須。

### フロー

```
1. cmd受領 → 分解・draft cmd起案
   - shogun_to_karo.yamlに追記
   - origin: karo_auto（家老起案時） / shogun（将軍直接起案時）
   - status: draft → delegated
2. 例外判定:
   - 殿の「緊急」明示指示あり → 例外(a)、レビュー省略 → Step 3のみ
   - 1AC以下の軽微修正 → 例外(b)、レビュー省略 → Step 3のみ
   - 上記以外 → Step 3 + Step 4 を並行実行
3. 忍者に配備（即時）:
   通常の配備フロー（タスクYAML作成→deploy_task.sh→inbox_write）
4. 軍師にレビュー依頼（同時に）:
   bash scripts/inbox_write.sh gunshi "draft cmd_XXXX レビュー依頼。shogun_to_karo.yaml参照" review_draft karo
5. 軍師のレビュー結果をinboxで受領:
   - APPROVE: 何もしない（忍者は既に作業中/完了）
   - REQUEST_CHANGES: 指摘内容を補足cmdとして忍者に配備
   - REJECT: dashboardの将軍宛セクションに記録。将軍が事後判断
6. dashboardの将軍宛セクションに記録:
   「cmd_XXXX (軍師: APPROVE/REQUEST_CHANGES/例外(a)/例外(b))」
```

**positive_rule**: 例外条件に該当しない全cmdは軍師レビューを経よ。忍者配備と軍師レビュー依頼を並行実行し、軍師の承認を待たずに配備せよ
**reason**: 直列方式（レビュー→承認→配備）はリードタイムのボトルネックになる。並行方式は即配備しつつ軍師の品質ゲートを維持する。REQUEST_CHANGES時のみ補足cmdで対応

## §10 軍師通信プロトコル

軍師(gunshi)との通信で使用するinbox typeと、レビュー結果(verdict)の処理方法。

### inbox type定義

| type | 方向 | 用途 |
|------|------|------|
| review_draft | 家老→軍師 | draft cmdのレビュー依頼 |
| review_result | 軍師→家老 | レビュー結果（verdict + findings） |
| review_feedback | 家老→軍師 | GATEフィードバック（レビュー品質の学習ループ） |
| report_review | 家老→軍師 | 忍者報告の一次レビュー依頼 |
| report_review_result | 軍師→家老 | 忍者報告レビュー結果（LGTM / FAIL + fail_reasons） |
| workaround_feedback | 家老→軍師 | workaround発生時の原因共有（パートナー学習ループ） |
| analysis_result | 軍師→家老 | idle時のデータ分析結果 |

軍師のinboxファイル: `queue/inbox/gunshi.yaml`

### verdict処理方法

| verdict | 家老の対応 |
|---------|-----------|
| APPROVE | 何もしない（忍者は既に作業中/完了） |
| REQUEST_CHANGES | 指摘内容を補足cmdとして忍者に配備 |
| REJECT | dashboardの将軍宛セクションに記録し、将軍の事後判断を待つ |

**positive_rule**: 軍師のverdictは3値(APPROVE/REQUEST_CHANGES/REJECT)のみ。曖昧な判定は家老が差し戻せ
**reason**: 曖昧判定はdraftの放置・品質低下を招く（F008と同じ原理）
