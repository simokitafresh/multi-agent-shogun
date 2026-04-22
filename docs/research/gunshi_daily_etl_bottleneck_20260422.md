# daily_etl ボトルネック分析 — 将軍cmd起票用資料

> 軍師作成 2026-04-22。render logs実測データに基づく。

## 現状: daily_etl total = 約66分

前回成功job(d7k7k1cm0tmc73acvga0): 07:34→08:40 UTC = **66分**

## Phase別内訳(render logs 2026-04-22実測)

## Phase別内訳 — DB実測値(hanzo偵察 cmd_2233, recalculation_timings run_id=20260422_073701)

| Phase | 所要時間 | 割合 | 備考 |
|-------|---------|------|------|
| 前段3ステップ | **152s (2.5分)** | 3.8% | maintenance_check+DataFetcher(重複)+ticker_returns(重複) |
| **L2_portfolio** | **2382s (39.7分)** | **60.1%** | ★最大ボトルネック。standard PF計算+DB書込み |
| **L3_fof** | **1151s (19.2分)** | **29.1%** | 109 FoF処理 |
| Other | 270s (4.5分) | 6.8% | startup/exit等 |

## ボトルネック構造(実測値ベース)

```
daily_etl 66分 (3955s)
├── 前段3ステップ 152s (3.8%) ← 2/3が重複(sync cron先行)。maintenance_checkのみ必要
├── L2_portfolio 2382s (60.1%) ← ★★★最大ターゲット。CoDDで最適化すべき
├── L3_fof 1151s (29.1%) ← FoF処理。第2ターゲット
└── Other 270s (6.8%)
```

## 改善ターゲット(CoDDで設計すべき対象)

### Tier 1: recalculate_fof MonthlyReturn (推定効果: 30分→5分)
- 現状: FoF 1体ごとにMonthlyReturn生成+DB書込み
- 仮説: batch化(全FoF計算後にMonthlyReturn一括生成)で大幅削減
- 根拠: fullrecalculate Phase 4.5のMonthlyReturnは77 PFで162s=2.1s/PF。FoFでは17s/体→8倍遅い。DB round-trip/体が原因の可能性

### Tier 2: 旧忍法-Ward 24s (外れ値)
- 15 components(他FoFは3-4体)。components数に比例して遅い
- Pipeline loop 4.9s + DB write 19s = DB write支配

### Tier 3: FoF差分計算(fullrecalculateのように)
- 現状: 全FoF × 全日付(3000日)を毎回再計算
- 仮説: 最終計算日以降のみ計算すれば1日分で済む
- 根拠: daily ETLは毎日実行。前日までは計算済み

## 戦略: 本番が正。cronは本番に追従する(殿方針)

**本番のrecalculate_fofを最適化する。それが全て。**
cronは本番コードをクローンして動くため、本番が速くなればcronも速くなる。
cron固有の最適化は不要。本番を正とし、本番を磨くことに集中する。

## 計測に必要な追加情報

1. recalculate_fof.pyのMonthlyReturn生成部分のprofiling(per-FoF所要時間の内訳)
2. DB write回数/体(batch INSERT vs 逐次INSERT)
3. FoF差分計算の実装可能性(recalculate_fof.pyの引数/トリガー確認)

## 参考: fullrecalculate最適化実績

→ `context/gunshi-fullrecalc-speed-analysis.md`
- 11,818s → 357s (97%削減, 33x)
- CoDDで設計→忍者実装→計測の3サイクルで達成
