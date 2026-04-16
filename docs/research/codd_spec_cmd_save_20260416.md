# cmd_save.sh 高速化 spec/result (2026-04-16)

## 対象
- `scripts/cmd_save.sh`
- 目的: 将軍の高頻度起票パス短縮。機能変更なしで Check 1-22 と preflight を維持する。

## Before
- `cmd_1951` プロファイリング基準: `4016ms` (`timeout` 扱い)
- 本セッション実測(実運用 queue コピー, 3回):
  - `1.83s`
  - `1.87s`
  - `1.53s`
  - median: `1.83s`

## ボトルネック分析
| 箇所 | before実測 | 所見 |
|---|---:|---|
| `check_content_duplicate` | `0.54-0.93s` | archive 直近20件を毎回 metadata scan + parse。WSL2 `/mnt/c` の metadata I/O が支配的 |
| q11 docs/research 検索 | `0.16s` | `scripts/cmd_save.sh` と basename `cmd_save.sh` を別々に走査していた |
| `git diff --name-only -- scripts/ CLAUDE.md instructions/ config/` | `0.14s` | 未コミット警告のため必要。今回は未変更 |
| `show_pending_insights` | `0.07s` | pending insight 表示。副作用ありのため未変更 |
| Check 3 (`quality_gate`) | `0.22s` | 多重 `grep/awk` は残るが、今回の最大因子ではない |

## 最適化候補
1. archive duplicate scan を warm cache 化する
   - 直近20 archive のファイル一覧と `title/purpose` 抽出結果を `/tmp` に保持
   - dir mtime が不変なら metadata scan を再実行しない
2. q11 docs/research 検索を単一起動にまとめる
   - path と basename を別々に `rg` せず、`-e` で1回に統合
3. Check 3 の field 抽出を単一パスへ再構成する
   - 今回は未着手。残存 `~0.22s` の削減余地

## 実装
1. `check_content_duplicate`
   - `yaml.safe_load` 全読込を廃止し、`title/purpose` 専用の軽量 line parser に変更
   - archive 直近20件の一覧と抽出済み `commands` を `/tmp/cmd_save_content_dup_cache.json` に保存
   - warm path では dir mtime 一致時に recent 20 の metadata scan 自体を省略
2. q11 docs/research 検索
   - `scripts/cmd_save.sh` と `cmd_save.sh` の2回検索を1回に統合
   - `grep` fallback は重複除去が必要な場合のみ `sort -u`

## After
- full run 実測(cold 1回 + warm 3回):
  - cold: `1.93s`
  - warm: `1.06s`, `1.04s`, `1.07s`
  - warm median: `1.06s`
- 改善率:
  - session before median `1.83s` → warm median `1.06s`
  - `-42.1%`
- 局所改善:
  - `check_content_duplicate`: `0.54-0.93s` → `0.02s` warm
  - q11 docs/research 検索: `0.16s` → `0.09s`

## 検証
- `bats tests/test_cmd_save_ac_paths.bats tests/test_cmd_save_q7_branch.bats tests/test_cmd_save_content_dup.bats tests/unit/test_cmd_save*.bats`

## 残課題
- cold run は cache 生成コストで `~1.9s`。高頻度実運用では warm path 改善が効く。
- 500ms 目標に到達するには Check 3 / 初期 queue パースの subprocess 削減が次段候補。
