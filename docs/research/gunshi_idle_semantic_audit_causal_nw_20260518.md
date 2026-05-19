# セマンティック監査: 因果NW導入後(cmd_2830-2845) — 2026-05-18

## 対象commit (9件)

| Hash | 内容 |
|------|------|
| a7ed1f04 | cmd_2840: lesson origin propagation |
| 3c0ce2d6 | fix: STALE_FIELDS追加 |
| 0b6df002 | cmd_2837: cmd_save warn FP削減 |
| f6df4874 | cmd_2833: function name除外 |
| d5743063 | cmd_2832: deploy task harden |
| 4dd195e2 | cmd_2831: file path keyword除外 |
| 5b8fdb06 | cmd_2830: nudge on exit |
| f933b82a | fix: semantic_search LLM disable + RFS dict保護 |
| c5b12b41 | fix: RFS assumption_invalidation dict保護(GP-240) |

## 5カテゴリ監査結果

### silent_failure
- **P1 偽陽性**: cmd_save.sh L610 `continue`がif外。検証結果: ループbody最終行のため冗長だが無害(データ消失しない)。`if in_assumptions:`ブロック内の正常フロー。エージェント判定は過剰
- **P2 低リスク**: deploy_task.sh L2567/2577 `timeout 5 | awk` — pipeがtimeout exit code(124)をマスク。ただし(1)SEMANTIC_DISABLE_LLM=1で実測62ms→timeoutほぼ発生しない (2)timeout時→matches空→概念注入なしで配備続行(補助機能)→影響限定的

### side_effect
- 全3 commit **CLEAN**。5パターン(return 1波及/set+eスコープ/フィルタ偽陰性/cap除外漏れ/非atomic更新)全て問題なし

### state_transition / race_condition / implicit_assumption
- 対象なし(新規状態遷移なし)

### semantic_index
- **Drift**: 0件(全参照ファイル存在確認)
- **Gap**: 3件(`lesson_write.sh`, `sync_lessons.sh`, `test_select.sh`未登録)。insight INS-20260518-000325280-c6b8に記録済み

## 因果チェーン

```
因果NW導入(cmd_2819-2823)
  → 新フィールド/スクリプト追加
  → cmd_save.sh origin regex ERE不備(P0 D0修正済み 948057bb)
  → lesson_write/sync_lessons/gate拡張(cmd_2840-2845)
  → セマンティック監査: 構造的バグなし(全commit clean)
```

## gate_sync重複書込み根因

review_logにgate_result重複(7件)が発生。根因: gate_gunshi_startup.sh内のgate_syncがYAML listエントリにgate_resultを追記する際、yaml_field_setはblock_id非対応(listエントリはblockではない)のため、grep+sedで行特定→追記する方式を使用。既にgate_resultが存在する行に再追記して重複化。対策: insightに記録済み(INS-20260517-235113675-1e0d)。cmd候補。
