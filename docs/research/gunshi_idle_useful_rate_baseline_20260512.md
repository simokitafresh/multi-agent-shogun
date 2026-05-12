# 教訓注入useful率 baseline計測 — cmd_2685 CLEAR直後
<!-- generated: 2026-05-12T12:50:00+09:00 by gunshi idle analysis -->

## baseline (cmd_2685 CLEAR直後、効果計測用)

| 指標 | 値 | ソース |
|------|-----|--------|
| useful率(直近20cmd) | 28.4% (40/141) | gate_lesson_health.sh |
| referenced率(全期間) | 50.9% (148/291) | lesson_impact.tsv injected |
| 直近60件useful率 | 61.7% (37/60) | lesson_impact.tsv tail-60 |
| USEFUL_RATE_THRESHOLD | 0.40 (旧0.30) | deploy_task.sh L2763 |
| target_files自動付与 | 有効(cmd_2685) | auto_draft_lesson.sh |

## 変更内容(cmd_2685)

1. USEFUL_RATE_THRESHOLD 0.30→0.40: useful率<40%教訓のscore decay加速
2. lesson_write.sh --target-files: 新規登録教訓にtarget_filesメタデータ自動付与
3. auto_draft_lesson.sh: 報告YAMLのfiles_modifiedからtarget_files推定→lesson_write.sh連携

## 効果計測計画

- **いつ**: 次回5-10件の配備完了後
- **何を**: gate_lesson_health.sh再実行でuseful率を確認
- **期待**: useful率28.4%→35%+（target_files有教訓が増えフィルタ有効化）
- **計測コマンド**: `bash scripts/gates/gate_lesson_health.sh 2>&1 | grep 'useful率'`
