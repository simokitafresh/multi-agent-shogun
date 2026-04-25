# 報告YAML破壊のインフラバグ全量分析

## 発見日
2026-04-24 殿指示による調査（2回目: 全量分析）

## 調査方法
- diagnose_reason全37件をパターン分類
- report_field_set.sh / gate_report_format_main.py / yaml_field_set.sh のコードを照合
- 各パターンの発生件数・根因・修正可否を判定

## 全8パターン（37件中）

| # | パターン | 件数 | 根因 | 修正状態 |
|---|---------|------|------|---------|
| P1 | 空文字→Usage exit | 6 | report_field_set.sh L36 `[ -z "$VALUE" ]` | **修正済み** (本セッション) |
| P2 | YAML特殊文字→パース破壊 | 2 | Edit直接書込み時クォート漏れ | **既存対処あり** (gate FAILで検出) |
| P3 | 更新順序→不整合 | 4 | 並列更新/verdict先行 | **修正済み** (本セッション P6統合) |
| P4 | chunk担当時AC空残 | 2 | assigned_acs未設定でchunk配備 | △ 仕組みあり(未使用) |
| P5 | lessons_useful list形式問題 | 5 | dot記法`L636.reason`→listは`0.reason` | **修正済み** (report_field_set.sh L172-175 BLOCKガード) |
| P6 | verdict先行書込み | 6 | bc未完了でverdict=PASS | **修正済み** (P3に統合) |
| P7 | assumption_invalidation必須フィールド漏れ | 3 | found=falseだけ書きaffected_cmds省略 | △ テンプレートで対処可 |
| P8 | report_path/parent_cmd不一致 | 3 | テンプレート再利用時の更新漏れ | △ deploy_taskで検出可 |

## 詳細

### P5: lessons_useful list形式問題（5件、未修正、最優先）
**現象**: 忍者が`report_field_set.sh report.yaml lessons_useful.L636.reason "not used"`を実行→L636はIDであってlist indexではない→FILL_THIS残存→gate BLOCK→やり直し
**根因**: lessons_usefulはYAML list(`- id: L636`)なのでdot記法は`lessons_useful.0.reason`が正しい。忍者はID名でアクセスしようとする
**修正案**: report_field_set.shでlessons_useful.{non-numeric}パターンを検出し、エラーメッセージでlist indexの使い方を案内
```
BLOCK: lessons_useful.L636.reason は不正。listなので lessons_useful.0.reason を使え
```

### P4: chunk担当時AC空残（2件）
**根因**: deploy_task.shがchunk配備時にassigned_acsを設定すれば、gate_report_format_main.py L269で担当外ACを自動スキップ
**対処**: deploy_task.shのchunk配備フローでassigned_acs自動設定。低頻度(2件)のため優先度低

### P7: assumption_invalidation必須フィールド漏れ（3件）
**根因**: found=falseでもaffected_cmds/detailが必須だが、report_field_set.shでガードなし
**対処**: verdict書込み時のチェック(L241-244)にassumption_invalidation.found=false→detail必須を追加

### P8: report_path/parent_cmd不一致（3件）
**根因**: テンプレート再利用時にparent_cmdだけ更新→report_pathが旧cmd
**対処**: deploy_task.shが報告テンプレート生成時にreport_path/parent_cmdの整合性を保証（既に実装済みのはず）

## 複利の問い
P5(5件)×やり直し時間(5-10分)= 25-50分。report_field_set.shの10行修正で以後全件防止。
P7(3件)は2行追加で防止。P4/P8は低頻度(各2-3件)で既存仕組みの活用で対処可。

## 優先順位（修正ROI）
1. **P5**: lessons_useful dot記法エラーメッセージ改善（5件、10行修正）
2. **P7**: assumption_invalidation必須フィールドガード（3件、5行追加）
3. P4: deploy_task assigned_acs自動設定（2件、低頻度）
4. P8: deploy_task整合性チェック強化（3件、既存仕組み活用）
