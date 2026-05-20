# clear_prep_check.sh CoDD改善前計測

## before計測 (cold 3回)

| run | 実行時間 |
|-----|---------|
| 1   | 1.65s   |
| 2   | 1.74s   |
| 3   | 1.51s   |
| 平均 | **1.63s** |

## ボトルネック仮説

### 1位: check6 git status (~1.1s)
- `git -C $ROOT_DIR status --porcelain -- scripts/ instructions/ config/ context/ CLAUDE.md`
- WSL2 NTFS I/O オーバーヘッドが支配
- `-uno`フラグでも改善なし（1.11s→1.10s）
- `git diff HEAD --name-only` は0.82sとやや速い（~0.29s削減）
- **改善案**: `git diff HEAD --name-only` + pathspecフィルタに切替

### 2位: lord_conversation.jsonl 複数回パース (~0.6s合計)
- session_state check (L28-73): 0.18s
- check5 conv health (L249-279): 0.15s
- check10 decision check (L527-590): ~0.15s
- check11 session_summary (L619-680): ~0.15s
- 合計4回のpython3起動+同一ファイル読み込み → WSL2プロセス起動コスト×4
- **改善案**: 1回のpython3呼び出しで全データを一括取得

## 改善優先度

1. **lord_conversation複数python3→1本化**: ~0.45s削減見込み (3×0.15ms起動コスト+ファイル読み込み3回減)
2. **git status→git diff HEAD切替**: ~0.29s削減見込み
- 合計改善見込み: ~0.74s (45%高速化)

## 対象ファイル

- `scripts/clear_prep_check.sh` (696行)
