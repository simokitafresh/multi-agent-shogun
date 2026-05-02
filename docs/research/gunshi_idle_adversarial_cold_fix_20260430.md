# Adversarial観点冷え分析+SG-PRE19実装

日付: 2026-04-30
軍師idle自走 Step 1-2 → 発見 → Step 6(即実装)

## 発見

gate_gunshi_startup.shのAdaptive Gating集計:
- ambiguity: 0/10件 (zero_streak=10)
- adversarial: 0/10件 (zero_streak=10)

## 根因分析

因果鎖:
1. review_logにchanged_linesフィールドが未記入(累計0件)
2. → gate_gunshi_cs_checklist.shのadversarial必要性トリガー(L160: `draft_changed_lines[i] >= 200`)が発火しない
3. → adversarial reviewが構造的にスキップされる
4. → 観点が冷える

データ:
- gunshi_review_log.yaml: changed_lines出現回数=0件/3739行
- adversarial_review出現回数=4件/3739行
- cmd_2425: 実際は+116/-701=817行だがchanged_lines未記入→adversarial未実施

## 対策: SG-PRE19

gate_gunshi_report_precheck.shにtotal changed_lines自動計算ブロック追加。
- git log --no-merges --grep=CMD_ID --numstat で追加/削除行数を集計
- DM-Signalプロジェクト: 外部リポジトリ(/mnt/c/Python_app/DM-Signal)も参照
- 200行超で★WARN → review_logへのchanged_lines記入を促す

検証: cmd_2425で+116/-701=817行→adversarial必須が正常検出。

commit: 3bf70385

## 残課題

1. ambiguity観点の冷え: cmd内容が明確な定型作業が続く→構造的に拾えない場面もある。だが惰性スキップとの区別が必要
2. changed_linesの記入: PRE19のWARN表示は「促す」のみ。意志依存が残る。review_logへの自動記入はawkでの既存パース構造に乗せるのが次のステップ
