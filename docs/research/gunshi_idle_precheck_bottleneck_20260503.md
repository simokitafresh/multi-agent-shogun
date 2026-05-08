# precheck WSL2タイムアウト ボトルネック分析

- 分析者: 軍師 (gunshi)
- 日付: 2026-05-03
- 起源: 本セッション8件中3件(37.5%)でprecheck 25秒タイムアウト

## 計測

| コンポーネント | 実測 |
|--------------|------|
| precheck全体 | 35.7s |
| engine.py | 0.08s |
| bash側(差分) | 35.6s |

## ボトルネック

bash -xで特定: PRE3(commit検証)+PRE14(revert検出)+PRE19(changed_lines)が**files_modifiedの各ファイルに個別git log**を実行。

- files_modified 4ファイルの場合:
  - PRE3: `git log --oneline -1 -- {file}` × 4 = 4回
  - PRE14: `git log --oneline -5 -- {file}` × 4 = 4回
  - PRE19: `git log --grep=cmd_id --numstat -- {file}` × 4 = 4回(加算+削除で2回ずつ)
  - 合計: 12-16回のgit log

WSL2 NTFSでgit log 1回 ≈ 2-3秒 → 12回 × 2.5s = 30s

## 改善案

1. **git log batch化**: 全files_modifiedを1回のgit logで処理(`git log -- file1 file2 ...`)
2. **PRE3/14/19統合**: 1回のgit log出力をawk/grepで分岐(3つのPREが同じデータを別々に取得)
3. **engine.pyに移管**: WSL2 git → subprocess 1回で全情報取得。bash → python移管

推奨: Option 2(既存bashの最小変更)。3つのPREが同一git logデータを共有すれば12回→1-2回に削減。推定35s→5s以下。

generated: 2026-05-03T02:33:00+09:00
trigger: 本セッション precheck タイムアウト3件(37.5%)
