<!-- Vercel圧縮: 2026-04-13 295行→索引化 -->
# CoDD (Coherence-Driven Development) vs 将軍システム分析 (索引)

> 詳細設計書 → `docs/research/gunshi-codd-analysis.md` (295行)
> 軍師分析 2026-03-29（v4: 実コード比較+定量データ検証済み）

## 結論

| 項目 | 結論 |
|------|------|
| 依存グラフ | 解くべき問題(context整合性破壊)がゼロ件。ROI不成立 |
| AIプロンプト設計 | 現時点で我が軍が上(deploy_task.sh 99関数 vs generator.py 単機能) |
| 出力サニタイゼーション | 問題ドメインが異なる(CoDD=メタ解説汚染 / 我が軍=YAML整合性) |
| 吸収済みパターン | `@generated-from`トレーサビリティ(§4)。CS観点プロトコル(§8.8→LG013) |

## +1改善候補(未着手)

| 改善 | 優先度 | 参照 |
|------|--------|------|
| hook出自コメント追加(追跡率11%→100%) | 低 | → §8.3 |
| gate_fire_log.yamlにgate_script名追加 | 中 | → §8.3 |

## 軍師教訓(7サイクル)

→ `docs/research/gunshi-codd-analysis.md` §7-§8.8
- CS観点プロトコル(LG013)の起源。殿指導下7サイクル。自己検出率0%→gate化
