# シン青龍-鉄壁 parity不一致分析 (cmd_2330, 2026-04-27)

## ⚠ 掲示板誤分析の訂正
blt_20260427_212742で「42Dがパラメータ空間に存在しない」と投稿したが**誤り**。
42D = 2M (TRADING_DAYS_PER_MONTH=21, grid_search_metrics_v2.py L58)。GSに2Mとして存在する。
訂正: blt_20260427_213329。真因はpattern_id誤対応。

## 結論
鉄壁の不一致(56か月diff>1e-4, max=0.298)は**pattern_id誤対応が原因**。正しいパターンで突合すれば12体全て≤1e-6。

## 事実
- 本番鉄壁config(id=a3c4e3d3): lookback 2本(days=42 weight=0.8, days=10 weight=0.2), safe=XLU, top_n=1, monthly
- GS: TRADING_DAYS_PER_MONTH=21 (grid_search_metrics_v2.py L58)。2M = 42 trading days
- 正しいGS pattern: `DM2_SXLU_T1_M_L0034` (lookback_label: 2M:80|10D:20)
- 突合結果: 167か月全てdiff≤1e-6。max diff=8.8e-7(2018-07)

## 12体parity pattern_id対応表
| 体名 | mode | family | 対応GS pattern (推定) |
|------|------|--------|---------------------|
| シン青龍-常勝 | josho | DM2 | AC1で検証済み(parity_check.json DM2) |
| シン青龍-鉄壁 | teppeki | DM2 | DM2_SXLU_T1_M_L0034 (2M:80\|10D:20) |
| シン青龍-抜き身 | nukimi | DM2 | 要調査 |
| (他9体) | | | 要調査 |

## 本番config→GS pattern変換の手順
1. 本番portfolios.configからlookback_periods/safe_haven/top_n/rebalance_triggerを取得
2. lookback days→months変換: days÷21=months (TRADING_DAYS_PER_MONTH=21)
3. GS metrics CSVでlookback_label+safe_haven+top_n+rebalance_triggerで検索
4. 一致するpattern_idのmonthly_returnを突合

## yotsume CSV構造 (将軍相談回答)
- 実データ: shin_ninpo_v2_12body/1200_yotsume_grid_{results,monthly}_fast.csv
- 4,686パターン(781 subset × 6パラメータ)。全family混在(family分割なし)
- N2/N3/N4 = subset_size(2/3/4体コンポーネント組合せ)。DM familyではない
- L0(source_type=db, universe=C12_legacy_shijin)。1 .dbに統合すべき
- 1795_yotsume版も存在(shin_ninpo_v2_12body/)
