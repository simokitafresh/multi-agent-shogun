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
