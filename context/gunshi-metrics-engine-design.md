# Metrics Research Engine — Rolling拡張設計 (索引)
<!-- Vercel圧縮: 2026-04-13 980行→索引化 -->

> 詳細設計書 → `docs/research/gunshi-metrics-engine-design.md` (980行)
> 修行ナビ → `docs/research/gunshi-metrics-engine-training-nav.md`

## 結論

| 項目 | 結論 |
|------|------|
| 既存 | MetricsCalculator import + DTB3キャッシュ + 全PFメトリクス + パリティ検証 (cmd_1730 疾風実装済み) |
| 追加 | Rolling計算(lookback窓) + 3Dテンソル(65PF×170月×42メトリクス) + 数値メトリクスAPI |
| 設計 | §2 アーキテクチャ + §2.1 仮想戦略API + §2.2 L1シミュレーター |
| 修行 | R1速度計測→R2高速化→R3 Rolling計算→R4パリティ検証 |

## 数値メトリクス (34個)

→ `docs/research/gunshi-metrics-engine-design.md` §3

## 修行依存関係

R1(計測)→R2(高速化)→R3(Rolling)→R4(パリティ)。R1-R2は並列配備可能(忍者2名)。

## ランブック

→ `docs/research/gunshi-metrics-engine-design.md` §9
