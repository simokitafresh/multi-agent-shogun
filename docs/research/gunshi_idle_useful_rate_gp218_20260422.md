# GP-218: target_filesフィルタ空タスクファイルバイパス修正

## 問題
- useful率推移: 34.9% → 16.9%(GP-211/212後) → 9.9%(2026-04-22計測)
- 根因: deploy_task.sh L2153 `if _all_task_files:` にelseブランチなし
- タスクファイル(target_path/files_modified)がない場合、target_filesフィルタが完全バイパス
- 640教訓中328件(51%)のtarget_files持ち教訓がマッチ不可能なタスクに注入

## NOT_USEFUL Top3
| 教訓ID | target_files | NOT_USEFUL回数 | 理由 |
|--------|-------------|---------------|------|
| L229 | frontend/src/ | 6回 | backend系タスクに注入 |
| L220 | frontend/app/docs/page.tsx | 5回 | backend系タスクに注入 |
| L283 | backend/blocks/ | 5回 | blocks以外のbackendタスクに注入 |

## 修正
- deploy_task.sh L2153にelseブランチ追加: タスクファイルなし時、target_files設定あり教訓を除外
- テスト: 9/9 PASS (新規2件含む)
- commit: af8a2ebc

## 効果推定(直近20報告)
| 指標 | Before | After(推定) |
|------|--------|------------|
| useful率 | 9.9% | 41.7% |
| NOT_USEFUL除外 | 0件 | 77件(76%) |
| useful件数 | 10件 | 10件(不変) |

## 因果鎖
タスクファイルなし→if分岐のelseなし→_tf_excluded_ids空→post-filter除外0→全教訓注入→328件がマッチ不可能なタスクへ→NOT_USEFUL量産→useful率9.9%
