# GP-194: 分割配備時のbinary_checks AC範囲制限

## 問題
分割配備(同一cmdを複数忍者に異なるAC分担で配備)時、deploy_task.shが全ACのbinary_checksテンプレートを全忍者に注入。
担当外ACは忍者がresult:noで報告→gate FAIL→家老手動修正(WA)。

## 実績
cmd_1796で2件WA(kagemaru+tobisaru)。2026-04-08以降再発なし(分割配備自体が低頻度)。

## 根因
deploy_task.sh L1230-1296のAC stub生成がtask YAMLの全acceptance_criteriaを読む。
AC分担情報(ac_range/ac_subset)がtask YAMLに存在しない。

## 前提検証
- deploy_task.sh L1230: `awk 'BEGIN{in_ac=0}' ... "$task_file"` で全ACを走査（現物確認済み）
- ac_assignedフィールド: task YAML schema に現在不在（grep "ac_assigned" queue/tasks/*.yaml = 0件）
- 分割配備の仕組み: L3478-3509のsplit_deploy検出は二重配備BLOCKのみ。AC分担の概念なし
- 既存フィールドの流用可能性: scope_mode/ac_priority は存在するがAC ID列挙ではない

## 事前検死
1. ac_assignedが空の場合: 現行動作(全AC注入)をフォールバック。後方互換性確保
2. ac_assignedのAC IDがacceptance_criteriaに不在: stubが生成されない→忍者が空binary_checks→gate FAIL。ID照合チェック追加が必要
3. 分割配備でない単独配備にac_assignedが誤設定: 一部ACのみstub→残りnoで報告→FAIL。単独配備時はac_assigned無視がフェイルセーフ

## 提案
task YAMLに `ac_assigned: [AC1, AC2]` フィールドを追加。
deploy_task.shのbinary_checks生成でac_assignedが存在すれば該当ACのみstub生成。

## 防御レベル
Level 4 (フロー内埋込BLOCK相当 — 不正なcheck自体が生成されない)

## 複利の問い
分割配備×10回=10回手動修正(負の複利) → ac_assigned制御で0回(正の複利)

## 実装主体
家老(deploy_task.sh改修)。軍師self_executable=false。

## 優先度
低〜中。分割配備頻度が低く、現在の主要WA源ではない。他GPが完了次第で十分。
