# cmd_design_quality BLOCK率分析 2026-04-25

## メタデータ
- 分析者: 軍師(gunshi)
- 日付: 2026-04-25
- トリガー: idle自走 Step 5 (パターン発見→因果推論→行動)
- 対象: logs/cmd_design_quality.yaml 直近100件

## §1 計測結果

| gate_result | 件数 | 率 |
|-------------|------|-----|
| BLOCK | 50 | 50% |
| WARN | 36 | 36% |
| CLEAR | 14 | 14% |

CLEAR率推移(25件区切り): 8% → 16%（微増だが低水準）

## §2 BLOCK理由TOP5

| 理由 | 件数 | 対処状況 |
|------|------|---------|
| draft_lessons(教訓未登録) | 13 | 未対処。将軍のlesson_write_shogun.sh実行漏れ |
| report_format(忍者報告品質) | ~8 | gate_report_format.sh+autofixで改善中 |
| 設計書数値緩和FP | ~8 | **cmd_2279で修正済み**(カタログ参照除外) |
| WARN累計昇格 | 4 | WARNが3-4回蓄積してBLOCK化 |
| diagnosis形式不正 | 2 | テンプレート遵守の問題 |

## §3 WARN理由TOP5

| 理由 | 件数 | 対処状況 |
|------|------|---------|
| 設計書数値緩和 | 7 | cmd_2279で修正済み |
| q8_縮小表現 | 6 | 未対処。WHATが曖昧/縮小的 |
| q11既存代替確認なし | 5 | 未対処。既存実装の現物確認不足 |
| missing_prev_cmd_lesson | 9 | 未対処。前cmdのBLOCK教訓未記録 |
| assumptions日付なし | 3 | 未対処。claim日付欠落 |

## §4 因果分析

### draft_lessons(13件BLOCK) — 最大の改善ターゲット
因果鎖: cmdがBLOCK→将軍が修正→再保存→CLEARだが教訓未記録→次のcmd保存時にdraft_lessonsでBLOCK
→ 将軍のlesson_write_shogun.sh実行が意志依存(Phase 4)
→ 改善案: cmd_save.sh CLEAR後にlesson_write_shogun.sh実行を自動リマインド(WARN表示)

### missing_prev_cmd_lesson(9件WARN) — draft_lessonsの前兆
因果鎖: 前cmdでBLOCK→教訓記録せず→次cmd保存時WARN→蓄積でBLOCK昇格
→ draft_lessonsと同根因(教訓登録の意志依存)

### 複利の問い
- draft_lessons 13件 × 将軍の修正→再保存の時間 = 殿の時間浪費
- 10回繰り返したら: 130回のBLOCK→修正→再保存。負の複利
- 教訓登録自動化/リマインドで根絶可能 = 正の複利

## §5 推奨行動

1. **cmd_2279効果確認**: 次回以降の「設計書数値緩和」WARN/BLOCK件数を計測
2. **draft_lessons対策**: cmd_save.sh CLEAR時にpending教訓をWARN表示する仕組みを提案(GP候補)
3. **q8_縮小表現**: 具体的なFP/TP分析が必要(本当にq8が縮小表現か、FPか)
