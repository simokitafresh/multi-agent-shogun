# ALM四神 パリティDrift分析 — 2026-04-09

## なぜなぜ7回

| # | なぜ | 答え |
|---|------|------|
| 1 | なぜパリティ未達？ | ALM青龍-激攻: 0/182ヶ月一致。差異最大0.38 |
| 2 | なぜ0/182？ | 本番config(cagr/[1-24]/48) ≠ 研究SSOT(max_run_up/[1-12]/12) |
| 3 | なぜ異なる？ | alm_shijin_pipeline_configs.jsonの値が本番に正しく反映されていない |
| 4 | なぜ反映不備？ | 青龍-激攻1体だけ別パラメータで上書きされた可能性(11体は完全一致) |
| 5 | なぜ検出できない？ | 研究SSOT vs 本番configの「パラメータ忠実性検証」が不在 |
| 6 | なぜ不在？ | ALMは新機能。config投入後のdrift検知フローが未整備 |
| 7 | **根因** | 研究SSOT(pipeline_configs.json)と本番configのdrift検知が自動化されていない |

## 12体比較表

| PF | objective | candidates | is_window | fallback | 全一致 |
|----|-----------|------------|-----------|----------|--------|
| ALM青龍-常勝 | calmar ✓ | [1-12] ✓ | 48 ✓ | 6 ✓ | ✓ |
| **ALM青龍-激攻** | **max_run_up→cagr ✗** | **[1-12]→[1-24] ✗** | **12→48 ✗** | 12 ✓ | **✗** |
| ALM青龍-鉄壁 | underwater_period ✓ | [1-12] ✓ | 60 ✓ | 2 ✓ | ✓ |
| ALM朱雀-常勝 | calmar ✓ | [1-3] ✓ | 36 ✓ | 1 ✓ | ✓ |
| ALM朱雀-激攻 | max_run_up ✓ | [1-3] ✓ | 24 ✓ | 3 ✓ | ✓ |
| ALM朱雀-鉄壁 | underwater_period ✓ | [1-3] ✓ | 48 ✓ | 1 ✓ | ✓ |
| ALM白虎-常勝 | calmar ✓ | [1-6] ✓ | 48 ✓ | 2 ✓ | ✓ |
| ALM白虎-激攻 | max_run_up ✓ | [1-6] ✓ | 12 ✓ | 5 ✓ | ✓ |
| ALM白虎-鉄壁 | underwater_period ✓ | [1-6] ✓ | 24 ✓ | 5 ✓ | ✓ |
| ALM玄武-常勝 | calmar ✓ | [12-24] ✓ | 60 ✓ | 18 ✓ | ✓ |
| ALM玄武-激攻 | max_run_up ✓ | [12-24] ✓ | 48 ✓ | 15 ✓ | ✓ |
| ALM玄武-鉄壁 | underwater_period ✓ | [12-24] ✓ | 24 ✓ | 24 ✓ | ✓ |

**結論: 11/12体は研究SSOTと完全一致。ALM青龍-激攻1体のみ3フィールドDRIFT。**

## cmd_1818への影響

1. **前提「config=None」は誤り** — configは全12体で設定済み
2. **AC3の比較対象**: cmd_1818はcagr__DM2列と比較するが、研究SSOTのchampionはmax_run_up
3. **正しいアプローチ**: 本番configを研究SSOT(max_run_up/[1-12]/12)に戻す→fullrecalculate→max_run_up__DM2列と比較

## 自動化ターゲット

研究SSOT(alm_shijin_pipeline_configs.json)と本番config(portfolios.config)のdrift検知スクリプト。
fullrecalculate前gateまたは定期チェックで乖離をALERT。

## データソース
- 研究SSOT: `outputs/analysis/alm_research/alm_shijin_pipeline_configs.json` (generated_at確認)
- 本番DB: `portfolios.config.pipeline_config.selection_pipeline.blocks[].config.alm_config`
- 研究リターン: `outputs/analysis/alm_research/cmd_1747_alm_l0_returns_6obj.csv`
- 本番リターン: `tests/golden_data/all_pf_monthly_returns_golden.json`
