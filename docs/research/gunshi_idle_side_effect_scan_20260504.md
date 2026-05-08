# 修正副作用スキャン結果 — cmd_2529-2547修正後(8スクリプト)

- 調査者: 軍師 (gunshi)
- 日付: 2026-05-04
- 手法: 5並列エージェント(5カテゴリ)
- 対象: scripts/archive_completed.sh, auto_draft_lesson.sh, bulletin_write.sh, cmd_absorb.sh, cmd_complete_gate.sh, cmd_save.sh, lib/yaml_field_set.sh, report_field_set.sh

## 結果サマリ

| カテゴリ | 検出数 | 実問題 | 判定 |
|---------|--------|--------|------|
| return 1波及 | 0 | 0 | CLEAN |
| set +eスコープ | 1(許容範囲) | 0 | CLEAN |
| フィルタ偽陰性 | 5 | 0(全FP) | CLEAN |
| 非atomic更新 | 0 | 0 | CLEAN(改善確認) |
| cap/threshold除外 | 0 | 0 | CLEAN |
| **合計** | **6** | **0** | **副作用なし** |

## False Positive 5件の詳細と棄却理由

### FP-1. cmd_complete_gate.sh L2031-2044 fallback_report_allowed False返却
- **エージェント指摘**: current_assignees空+report_parent空→常にFalse→正当報告除外
- **棄却理由**: L2042-2043のコメントが意図を明示(`avoid stale glob matches`)。新規タスク割当直後はcurrent_assigneesに値が入るため正当報告は除外されない
- **現物確認**: L2039-2040でcurrent_assigneesチェック→L2044は最終フォールバック

### FP-2. cmd_complete_gate.sh L1968-1972 タスク型誤分類
- **エージェント指摘**: `cmd_review_exact`→`exact`と分類され`review`にならない
- **棄却理由**: 実データのtask_idは`cmd_{数字}_{type}`形式。`cmd_review_exact`のような複合型IDは存在しない
- **現物確認**: deploy_task.shのtask_id生成を確認。`{cmd_id}_{scope_mode}`で生成

### FP-3. archive_completed.sh L986-991 新規cmdタイプ除外
- **エージェント指摘**: ハードコード3種(training/cycle/selfimprovement)以外の新cmdタイプが除外
- **棄却理由**: gate_complete()はarchive.done存在チェックであり、GATEフロー内のcmdは全てarchive.doneが生成される。3種はGATEフロー外の例外
- **現物確認**: cmd_complete_gate.shの最終ステップでarchive.done作成を確認

### FP-4. cmd_save.sh L1949-1982 AWK互換性
- **エージェント指摘**: AWK正規表現の`?`量指定子が古い実装で非対応
- **棄却理由**: WSL2環境のgawk 5.x+を使用。POSIX ERE互換。実際の問題報告なし
- **現物確認**: `awk --version`でgawk確認済み

### FP-5. yaml_field_set.sh L825 バックスラッシュ二重化
- **エージェント指摘**: 二重化でJSON/Windowsパスが壊れる
- **棄却理由**: awk `-v`のバックスラッシュ解釈対策。awk内でデコードされるため最終YAML値は正しい
- **現物確認**: yaml_field_set.shテスト(test_yaml_field_set.bats)でバックスラッシュ含む値のround-trip確認済み

## 前回比較

| 指標 | 前回(初回スキャン) | 今回(修正後) |
|------|------------------|-------------|
| 対象 | 12件修正後の5本 | 8件修正後の8本 |
| 実問題検出 | 5件(42%) | 0件(0%) |
| FP率 | 低 | 高(6/6=100%) |
| 理由 | 大規模修正で副作用多発 | 小規模テスト固定+最小修正中心 |

## 次回スキャンへのFP除外ヒント

- `fallback_report_allowed`のFalse返却は意図的設計(stale glob回避)
- `detect_task_type`のendswith優先は実データに複合型IDがないため安全
- awk `-v`のバックスラッシュ二重化は標準対策パターン
