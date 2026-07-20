# Review経路の表示型摩擦実測（kagemaru）

- task: `cmd_karo_next_throughput_kagemaru_2207_normal`
- date: 2026-07-20
- 対象: `.claude/hooks/pre-bash-combined.sh` Guard LG058（正しい教訓番号はLG059だが、実装ラベルはLG058）
- 方法: production hookをそのまま読み、対象の`emit_deny`だけをprocess substitution上でadvisory出力へ置換したisolated fixture。実paneは変更・respawnしていない。

## 3回実測

| 条件 | run 1 | run 2 | run 3 | BLOCK | 事故シグナル | 通知欠落 |
|---|---:|---:|---:|---:|---|---:|
| 現行・不明alias | 793ms | 806ms | 912ms | 3/3 (rc=2) | stderr 3/3 | 3/3（durable通知なし） |
| advisory・不明alias | 1019ms | 550ms | 779ms | 0/3 (rc=0) | stderr WARN 3/3 | 3/3（現行同等） |
| 現行・正規alias | 311ms | 302ms | 292ms | 0/3 | 不要 | 3/3（現行仕様） |
| advisory・正規alias | 381ms | 400ms | 350ms | 0/3 | 不要 | 3/3（現行同等） |

## 二値判定

- 不明alias検出: 現行3/3 → advisory 3/3（品質差0）
- 正規alias偽陽性: 現行0/3 → advisory 0/3（品質差0）
- 不明aliasによる操作停止: 現行3/3 → advisory 0/3（表示型摩擦3件削減）
- durable通知: 現行0/3 → advisory 0/3（新たな欠落0、ただし既存欠落は維持）

## 採用候補

Guard LG058の`emit_deny`を非停止のstderr advisoryへ変える。モデルalias誤指定の事故シグナルは3/3維持しつつ、未知aliasを理由にrespawn操作そのものを止める表示型BLOCKを3/3除去できる。なお、実装ラベルLG058は教訓台帳上のLG059を指しており、番号不整合も併記して修正時の誤参照を防ぐ。
