# Stale AC Contamination 分析 (2026-04-26)

## 発見

cmd_2286でAC5(target_dateがproduction fullrecalculateと同一)がtask YAMLに混入。
cmd原本(shogun_to_karo)にはAC1-AC4のみ。AC5はcheckフィールドなし。

## 調査結果

- deploy_task.log: `[AC_VERIFY] OK: AC count=4 ids match (parent_cmd=cmd_2286)` → deploy時点ではAC4個正常
- previous_failures: attempt: 2 → 再配備あり
- STALE_RESET実行済み(01:05:38)
- AC5混入タイミング: deploy後、忍者の1回目作業中または再配備の間

## 定量データ

- karo_workarounds全件: stale_ac_contamination 7件/112件(6.3%)
- GP-180/181(2026-04-11)以降: 今回1件のみ(0.9%)
- 頻度低下傾向

## 根因確定

deploy_task.shは正常(AC_OVERWRITE 4件+AC_VERIFY OK)。
根因: **忍者(影丸)がattempt 1作業中にtask YAMLにAC5を手動追加**。
証拠: AC5にcheckフィールドなし(deploy_task.shは常にcheck+description+id 3フィールドセットで注入)。
deployは1回のみ(再配備ログなし)。忍者がGATE BLOCK→自力修正→再提出(attempt 2)。

## 修正設計案

A案(推奨): gate_report_format.shにAC ID照合チェック追加(報告のbinary_checks AC ID ↔ cmdソースAC ID照合)
B案: AC_VERIFYをGATE直前にも再実行
C案: STALE_FIELDSにAC4-10追加(不適切: 正常ACも消える)

## 判断

A案をGP候補として保持。次回stale_ac再発時に実装。現頻度(0.9%)では対策ROI低い。
