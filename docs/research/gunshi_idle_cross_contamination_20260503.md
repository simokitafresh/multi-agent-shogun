# Cross-Contamination Pattern: auto-commitが他忍者の未commit変更を吸収する

## 発見日
2026-05-03 cmd_2492レビュー時

## 現象
- kagemaru が scripts/deploy_task.sh (+70行) を変更
- kagemaru が commit する**前に** hayate の /clear auto-commit (9add619b, 00:41:08) が発動
- hayate auto-commit が kagemaru の未commit変更を拾って commit
- kagemaru の cmd_2492 commit (2fbf4f46, 00:42:27) にはテストファイルのみ残存
- 結果: deploy_task.sh の変更は "chore: auto-commit before /clear (hayate) — 運用ファイル" に帰属

## 因果連鎖
```
kagemaru: deploy_task.sh 変更 → 未commit状態でワーキングツリーに残存
  → hayate: /clear発動 → auto-commit スクリプト起動
  → git add で kagemaru の変更も staged
  → hayate 名義で commit
  → kagemaru: commit 時に deploy_task.sh は既に committed → commit対象外
```

## 影響度
- **実害**: 低（コードは正しくリポジトリに存在し、テストもPASS）
- **帰属問題**: cmd_2492 の git log に deploy_task.sh 変更が紐付かない
- **レビュー影響**: SG-PRE3 (commit検証) がSKIPされた場合に見逃される

## 根本原因
auto-commit スクリプトが `git add` で**全ての未commit変更**をstageする。
忍者別のファイルスコープ制限がない。

## 検出方法（レビュー時）
1. files_modified のファイルが commit_hash の `git show --stat` に含まれるか確認
2. 含まれない場合 → 別commit(auto-commit等)への混入を疑う
3. `git log --oneline -3 -- {ファイル}` で最新commit者を確認

## 対策案（gate化候補）
- SG-PRE3 強化: commit_hash の --stat と files_modified を突合し、不一致をWARN
- auto-commit スコープ制限: 運用ファイル(queue/, logs/, context/)のみ対象にする

## 発生頻度
cmd_2492で初検出。稀だが、並行作業＋auto-commitタイミング次第で再現可能。
