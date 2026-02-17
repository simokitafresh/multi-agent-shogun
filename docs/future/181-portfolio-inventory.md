# 本番DB ポートフォリオ棚卸しリスト

> 生成日: 2026-02-17 13:41
> ソース: 本番PostgreSQL (singapore-postgres.render.com)
> cmd: cmd_115 / subtask_115a
> 目的: 殿が削除/残留を判断するための一覧。削除は本タスクでは一切行わない。

## 1. サマリー

- **PF総数**: 73
  - standard: 56
  - fof: 17

### ファミリー別内訳

| ファミリー | PF数 | standard | fof |
|-----------|------|----------|-----|
| 青龍 | 1 | 1 | 0 |
| 青龍系 | 16 | 16 | 0 |
| 朱雀 | 1 | 1 | 0 |
| 朱雀系 | 8 | 8 | 0 |
| 白虎 | 1 | 1 | 0 |
| 白虎系 | 14 | 14 | 0 |
| 玄武 | 1 | 1 | 0 |
| 玄武系 | 9 | 9 | 0 |
| FoF | 17 | 0 | 17 |
| DM4系 | 1 | 1 | 0 |
| DM5系 | 2 | 2 | 0 |
| DM-safe系 | 2 | 2 | 0 |
| **合計** | **73** | **56** | **17** |

### レコード件数サマリー

| テーブル | 総件数 |
|---------|--------|
| signals | 287,201 |
| monthly_returns | 13,278 |
| drawdown_periods | 730 |
| rolling_returns_summary | 365 |
| rolling_returns_chart | 43,614 |
| trade_performance | 4,059 |
| portfolio_metrics | 146 |
| risk_management_metrics | 146 |

## 2. 青龍(DM2)ファミリー

### DM2 ⭐四神

| 項目 | 値 |
|------|-----|
| PF ID | `f8d70415-24f2-4b1a-a603-d0e86155255a` |
| タイプ | standard |
| 作成日 | 2025-12-21 17:47:29 |
| is_active | True |
| hide_portfolio | True |
| lookback | 252D(w0.6), 126D(w0.2), 42D(w0.2) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | LQD |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,902, monthly_returns=180, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=588, trade_performance=39, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,728 |
| **判定** | ＿＿＿＿ |

### DM2-test

| 項目 | 値 |
|------|-----|
| PF ID | `c7477396-07f1-445b-bdbe-15eff37e77a9` |
| タイプ | standard |
| 作成日 | 2026-01-12 09:08:42 |
| is_active | True |
| hide_portfolio | False |
| lookback | 252D(w0.5), 126D(w0.25), 42D(w0.25) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | TECL, TQQQ |
| absolute_asset | LQD |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,902, monthly_returns=180, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=588, trade_performance=37, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,726 |
| **判定** | ＿＿＿＿ |

### DM2-top

| 項目 | 値 |
|------|-----|
| PF ID | `694f7964-ccf2-4496-adcf-26e3c89aa4b4` |
| タイプ | standard |
| 作成日 | 2026-01-12 09:09:32 |
| is_active | True |
| hide_portfolio | False |
| lookback | 252D(w0.4), 147D(w0.3), 63D(w0.3) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | TECL, TQQQ |
| absolute_asset | LQD |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,902, monthly_returns=180, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=588, trade_performance=40, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,729 |
| **判定** | ＿＿＿＿ |

### DM2-20%

| 項目 | 値 |
|------|-----|
| PF ID | `8db65bd3-8fa8-44bb-b6be-f03b44bf608c` |
| タイプ | standard |
| 作成日 | 2026-01-12 18:28:38 |
| is_active | True |
| hide_portfolio | False |
| lookback | 252D(w0.4), 42D(w0.3), 10D(w0.3) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | TECL, TQQQ |
| absolute_asset | LQD |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,902, monthly_returns=180, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=588, trade_performance=40, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,729 |
| **判定** | ＿＿＿＿ |

### DM2-40%

| 項目 | 値 |
|------|-----|
| PF ID | `cd55a4f2-4e85-43ae-984c-a228e0c9b7c4` |
| タイプ | standard |
| 作成日 | 2026-01-12 18:30:06 |
| is_active | True |
| hide_portfolio | False |
| lookback | 252D(w0.4), 126D(w0.3), 42D(w0.3) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | TECL, TQQQ |
| absolute_asset | LQD |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,902, monthly_returns=180, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=588, trade_performance=39, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,728 |
| **判定** | ＿＿＿＿ |

### DM2-60%

| 項目 | 値 |
|------|-----|
| PF ID | `e4787792-eded-4bcf-8104-13329191212d` |
| タイプ | standard |
| 作成日 | 2026-01-12 18:31:02 |
| is_active | True |
| hide_portfolio | False |
| lookback | 378D(w0.5), 126D(w0.4), 63D(w0.1) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | TECL, TQQQ |
| absolute_asset | LQD |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,767, monthly_returns=174, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=558, trade_performance=22, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,540 |
| **判定** | ＿＿＿＿ |

### DM2-80%

| 項目 | 値 |
|------|-----|
| PF ID | `f051635a-2f9a-41f2-9056-238703af4384` |
| タイプ | standard |
| 作成日 | 2026-01-12 18:31:46 |
| is_active | True |
| hide_portfolio | False |
| lookback | 147D(w0.5), 10D(w0.5) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | TECL, TQQQ |
| absolute_asset | LQD |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,015, monthly_returns=186, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=618, trade_performance=46, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,884 |
| **判定** | ＿＿＿＿ |

### DM2_GS_Qj_G_TC_T1_10D

| 項目 | 値 |
|------|-----|
| PF ID | `0e622357-b789-4680-abb4-0ba0f75b80c4` |
| タイプ | standard |
| 作成日 | 2026-01-27 15:14:14 |
| is_active | True |
| hide_portfolio | False |
| lookback | 10D(w1.0) |
| rebalance | quarterly_jan |
| top_n | 1 |
| relative_assets | TECL |
| absolute_asset | LQD |
| safe_haven_asset | GLD |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,452, monthly_returns=206, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=718, trade_performance=26, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 5,421 |
| **判定** | ＿＿＿＿ |

### DM2_Qj_GLD_10D_T1

| 項目 | 値 |
|------|-----|
| PF ID | `9e0bb2b5-51ac-43a3-adb1-b94d5ecba5e7` |
| タイプ | standard |
| 作成日 | 2026-02-09 19:05:36 |
| is_active | True |
| hide_portfolio | True |
| lookback | 10D(w1.0) |
| rebalance | quarterly_jan |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | LQD |
| safe_haven_asset | GLD |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,162, monthly_returns=192, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=648, trade_performance=38, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 5,059 |
| **判定** | ＿＿＿＿ |

### DM2_Qj_XLU_11M_5M_1M_w50_30_20_T1

| 項目 | 値 |
|------|-----|
| PF ID | `3452e543-0d90-4010-a332-efccb0096f83` |
| タイプ | standard |
| 作成日 | 2026-02-09 19:05:36 |
| is_active | True |
| hide_portfolio | True |
| lookback | 231D(w0.5), 105D(w0.3), 21D(w0.2) |
| rebalance | quarterly_jan |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | LQD |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,925, monthly_returns=181, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=593, trade_performance=24, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,742 |
| **判定** | ＿＿＿＿ |

### DM2_Be_GLD_18M_7M_1M_w60_30_10_T1

| 項目 | 値 |
|------|-----|
| PF ID | `5e233ed1-764c-4df1-bc3d-c4b98f3e3756` |
| タイプ | standard |
| 作成日 | 2026-02-09 19:05:36 |
| is_active | True |
| hide_portfolio | True |
| lookback | 378D(w0.6), 147D(w0.3), 21D(w0.1) |
| rebalance | bimonthly_even |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | LQD |
| safe_haven_asset | GLD |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,767, monthly_returns=174, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=558, trade_performance=19, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,537 |
| **判定** | ＿＿＿＿ |

### original-青龍

| 項目 | 値 |
|------|-----|
| PF ID | `a766a878-6a26-4178-b1eb-1ac2681de813` |
| タイプ | standard |
| 作成日 | 2026-02-13 13:07:11 |
| is_active | True |
| hide_portfolio | False |
| lookback | 252D(w0.6), 126D(w0.2), 42D(w0.2) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | LQD |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,902, monthly_returns=180, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=588, trade_performance=39, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,728 |
| **判定** | ＿＿＿＿ |

### 青龍=C=So

| 項目 | 値 |
|------|-----|
| PF ID | `e26ce33b-5b36-4f5d-a87a-c0b1249abdec` |
| タイプ | standard |
| 作成日 | 2026-02-13 14:20:33 |
| is_active | True |
| hide_portfolio | False |
| lookback | 10D(w1.0) |
| rebalance | quarterly_jan |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | LQD |
| safe_haven_asset | GLD |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,162, monthly_returns=192, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=648, trade_performance=38, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 5,059 |
| **判定** | ＿＿＿＿ |

### So-青龍

| 項目 | 値 |
|------|-----|
| PF ID | `5b1ffb6f-815e-40cb-a83a-6824462ba3f7` |
| タイプ | standard |
| 作成日 | 2026-02-13 14:29:56 |
| is_active | True |
| hide_portfolio | False |
| lookback | 10D(w1.0) |
| rebalance | quarterly_jan |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | LQD |
| safe_haven_asset | GLD |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,162, monthly_returns=192, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=648, trade_performance=38, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 5,059 |
| **判定** | ＿＿＿＿ |

### Nh-青龍

| 項目 | 値 |
|------|-----|
| PF ID | `9177df25-1754-4f23-955f-89f1dd06d25f` |
| タイプ | standard |
| 作成日 | 2026-02-13 14:29:56 |
| is_active | True |
| hide_portfolio | False |
| lookback | 126D(w0.5), 42D(w0.4), 15D(w0.1) |
| rebalance | bimonthly_odd |
| top_n | 2 |
| relative_assets | TQQQ, TECL |
| absolute_asset | LQD |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,037, monthly_returns=187, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=623, trade_performance=25, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,891 |
| **判定** | ＿＿＿＿ |

### Ud-青龍

| 項目 | 値 |
|------|-----|
| PF ID | `f125d3e2-f384-41c9-8ab1-8681ea66d33b` |
| タイプ | standard |
| 作成日 | 2026-02-13 14:29:56 |
| is_active | True |
| hide_portfolio | False |
| lookback | 315D(w0.6), 84D(w0.4) |
| rebalance | bimonthly_even |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | LQD |
| safe_haven_asset | GLD |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,835, monthly_returns=177, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=573, trade_performance=20, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,624 |
| **判定** | ＿＿＿＿ |

### C-青龍

| 項目 | 値 |
|------|-----|
| PF ID | `983b54b7-33a2-4826-bd33-a323aa17fbbe` |
| タイプ | standard |
| 作成日 | 不明 |
| is_active | True |
| hide_portfolio | False |
| lookback | 10D(w1.0) |
| rebalance | quarterly_jan |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | LQD |
| safe_haven_asset | GLD |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,162, monthly_returns=192, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=648, trade_performance=38, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 5,059 |
| **判定** | ＿＿＿＿ |

## 3. 朱雀(DM3)ファミリー

### DM3 ⭐四神

| 項目 | 値 |
|------|-----|
| PF ID | `c55a7f68-6569-4abb-8df5-9acf3dc8e061` |
| タイプ | standard |
| 作成日 | 2025-12-21 17:47:29 |
| is_active | True |
| hide_portfolio | True |
| lookback | 20D(w1.0) |
| rebalance | bimonthly_odd |
| top_n | 1 |
| relative_assets | TECL, TQQQ |
| absolute_asset | TMF |
| safe_haven_asset | TMV |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,151, monthly_returns=192, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=648, trade_performance=65, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 5,075 |
| **判定** | ＿＿＿＿ |

### DM3_Qj_TMV_3M_15D_w50_50_T1

| 項目 | 値 |
|------|-----|
| PF ID | `20678a85-fafc-4bb5-bbcd-ece6a1a37125` |
| タイプ | standard |
| 作成日 | 2026-02-09 19:05:36 |
| is_active | True |
| hide_portfolio | True |
| lookback | NoneD(w0.5), 15D(w0.5) |
| rebalance | quarterly_jan |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | TMF |
| safe_haven_asset | TMV |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,105, monthly_returns=190, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=638, trade_performance=37, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,989 |
| **判定** | ＿＿＿＿ |

### DM3_M_TMV_4M_3M_20D_w50_40_10_T1

| 項目 | 値 |
|------|-----|
| PF ID | `8edc1993-00d0-4f06-94e1-7976e9c35288` |
| タイプ | standard |
| 作成日 | 2026-02-09 19:05:36 |
| is_active | True |
| hide_portfolio | True |
| lookback | 84D(w0.5), 63D(w0.4), 20D(w0.1) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | TMF |
| safe_haven_asset | TMV |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,082, monthly_returns=189, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=633, trade_performance=51, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,974 |
| **判定** | ＿＿＿＿ |

### original-朱雀

| 項目 | 値 |
|------|-----|
| PF ID | `b66619af-593c-4ffc-9f93-c5267124c7df` |
| タイプ | standard |
| 作成日 | 2026-02-13 13:07:11 |
| is_active | True |
| hide_portfolio | False |
| lookback | 20D(w1.0) |
| rebalance | bimonthly_odd |
| top_n | 1 |
| relative_assets | TECL, TQQQ |
| absolute_asset | TMF |
| safe_haven_asset | TMV |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,151, monthly_returns=192, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=648, trade_performance=65, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 5,075 |
| **判定** | ＿＿＿＿ |

### 朱雀=So

| 項目 | 値 |
|------|-----|
| PF ID | `1c509639-a04b-42ce-a5f3-43ba7b3a884c` |
| タイプ | standard |
| 作成日 | 2026-02-13 14:20:33 |
| is_active | True |
| hide_portfolio | False |
| lookback | 84D(w0.5), 63D(w0.4), 20D(w0.1) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | TMF |
| safe_haven_asset | TMV |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,082, monthly_returns=189, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=633, trade_performance=51, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,974 |
| **判定** | ＿＿＿＿ |

### So-朱雀

| 項目 | 値 |
|------|-----|
| PF ID | `07baef5b-313b-4d8e-8b0f-5ec7cfcb28fa` |
| タイプ | standard |
| 作成日 | 2026-02-13 14:29:56 |
| is_active | True |
| hide_portfolio | False |
| lookback | 84D(w0.5), 63D(w0.4), 20D(w0.1) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | TMF |
| safe_haven_asset | TMV |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,082, monthly_returns=189, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=633, trade_performance=51, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,974 |
| **判定** | ＿＿＿＿ |

### Nh-朱雀

| 項目 | 値 |
|------|-----|
| PF ID | `cc5830ab-b784-4638-a7c3-da1b4738b1c6` |
| タイプ | standard |
| 作成日 | 2026-02-13 14:29:56 |
| is_active | True |
| hide_portfolio | False |
| lookback | 378D(w0.4), 84D(w0.3), 63D(w0.3) |
| rebalance | bimonthly_odd |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | TMF |
| safe_haven_asset | TMV |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,767, monthly_returns=174, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=558, trade_performance=19, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,537 |
| **判定** | ＿＿＿＿ |

### Ud-朱雀

| 項目 | 値 |
|------|-----|
| PF ID | `c85edf9b-ff6a-4058-8f78-60e2c383cbe8` |
| タイプ | standard |
| 作成日 | 2026-02-13 14:29:56 |
| is_active | True |
| hide_portfolio | False |
| lookback | 252D(w0.4), 21D(w0.4), 15D(w0.2) |
| rebalance | bimonthly_odd |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | TMF |
| safe_haven_asset | TMV |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,902, monthly_returns=180, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=588, trade_performance=26, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,715 |
| **判定** | ＿＿＿＿ |

### C-朱雀

| 項目 | 値 |
|------|-----|
| PF ID | `345b29d8-2b96-445d-ae2f-a9797178d8de` |
| タイプ | standard |
| 作成日 | 不明 |
| is_active | True |
| hide_portfolio | False |
| lookback | 63D(w0.5), 15D(w0.5) |
| rebalance | quarterly_jan |
| top_n | 1 |
| relative_assets | TECL, TQQQ |
| absolute_asset | TMF |
| safe_haven_asset | TMV |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,105, monthly_returns=190, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=638, trade_performance=37, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,989 |
| **判定** | ＿＿＿＿ |

## 4. 白虎(DM6)ファミリー

### DM6 ⭐四神

| 項目 | 値 |
|------|-----|
| PF ID | `212e9eee-6acc-4f25-8a41-ea9fdf34a4e1` |
| タイプ | standard |
| 作成日 | 2025-12-21 17:47:29 |
| is_active | True |
| hide_portfolio | True |
| lookback | 15D(w1.0) |
| rebalance | quarterly_jan |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | ^VIX |
| safe_haven_asset | GLD |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,157, monthly_returns=192, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=648, trade_performance=44, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 5,060 |
| **判定** | ＿＿＿＿ |

### DM6-20%

| 項目 | 値 |
|------|-----|
| PF ID | `f0d3f891-c55c-412c-97c9-28c135a4b4a2` |
| タイプ | standard |
| 作成日 | 2026-01-12 18:33:31 |
| is_active | True |
| hide_portfolio | True |
| lookback | 126D(w0.4), 21D(w0.4), 20D(w0.2) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | ^VIX |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,037, monthly_returns=187, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=623, trade_performance=97, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,963 |
| **判定** | ＿＿＿＿ |

### DM6-Top

| 項目 | 値 |
|------|-----|
| PF ID | `0290ea4d-d332-4a00-9e95-1e219d485a43` |
| タイプ | standard |
| 作成日 | 2026-01-12 18:35:08 |
| is_active | True |
| hide_portfolio | True |
| lookback | 126D(w0.5), 21D(w0.5) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | ^VIX |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,037, monthly_returns=187, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=623, trade_performance=95, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,961 |
| **判定** | ＿＿＿＿ |

### DM6-40%

| 項目 | 値 |
|------|-----|
| PF ID | `64f8bdd8-51a9-4cde-b9ed-6834ccea00c7` |
| タイプ | standard |
| 作成日 | 2026-01-12 18:36:14 |
| is_active | True |
| hide_portfolio | True |
| lookback | 126D(w0.6), 21D(w0.4) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | ^VIX |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,037, monthly_returns=187, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=623, trade_performance=90, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,956 |
| **判定** | ＿＿＿＿ |

### DM6-60%

| 項目 | 値 |
|------|-----|
| PF ID | `142bdae7-a6fa-4f75-823e-86bca89552b6` |
| タイプ | standard |
| 作成日 | 2026-01-12 18:37:13 |
| is_active | True |
| hide_portfolio | True |
| lookback | 126D(w0.5), 21D(w0.4), 10D(w0.1) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | ^VIX |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,037, monthly_returns=187, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=623, trade_performance=97, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,963 |
| **判定** | ＿＿＿＿ |

### DM6-80%

| 項目 | 値 |
|------|-----|
| PF ID | `4256ae25-9fc8-443a-9a53-5d0fe0ca4faf` |
| タイプ | standard |
| 作成日 | 2026-01-12 18:38:08 |
| is_active | True |
| hide_portfolio | True |
| lookback | 126D(w0.5), 42D(w0.25), 20D(w0.25) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | ^VIX |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,037, monthly_returns=187, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=623, trade_performance=77, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,943 |
| **判定** | ＿＿＿＿ |

### DM6-5

| 項目 | 値 |
|------|-----|
| PF ID | `5c006db6-7c1e-45b8-82ce-e1f98c891895` |
| タイプ | standard |
| 作成日 | 2026-01-15 05:14:52 |
| is_active | True |
| hide_portfolio | True |
| lookback | 105D(w1.0) |
| rebalance | quarterly_jan |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | ^VIX |
| safe_haven_asset | GLD |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,060, monthly_returns=188, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=628, trade_performance=35, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,930 |
| **判定** | ＿＿＿＿ |

### DM6_Qj_XLU_15M_3M_w70_30_T2

| 項目 | 値 |
|------|-----|
| PF ID | `0026d389-8dd0-4916-a70c-459bd93fc5b1` |
| タイプ | standard |
| 作成日 | 2026-02-09 19:05:36 |
| is_active | True |
| hide_portfolio | True |
| lookback | 315D(w0.7), 63D(w0.3) |
| rebalance | quarterly_jan |
| top_n | 2 |
| relative_assets | TQQQ, TECL |
| absolute_asset | ^VIX |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,835, monthly_returns=177, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=573, trade_performance=29, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,633 |
| **判定** | ＿＿＿＿ |

### DM6_Qj_GLD_4M_1M_w50_50_T1

| 項目 | 値 |
|------|-----|
| PF ID | `6c9bfe2c-e118-4750-a966-cb7b17599f8c` |
| タイプ | standard |
| 作成日 | 2026-02-09 19:05:36 |
| is_active | True |
| hide_portfolio | True |
| lookback | 84D(w0.5), 20D(w0.5) |
| rebalance | quarterly_jan |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | ^VIX |
| safe_haven_asset | GLD |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,082, monthly_returns=189, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=633, trade_performance=32, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,955 |
| **判定** | ＿＿＿＿ |

### original-白虎

| 項目 | 値 |
|------|-----|
| PF ID | `61c333da-a20d-4801-85e1-53c6317f53a7` |
| タイプ | standard |
| 作成日 | 2026-02-13 13:07:11 |
| is_active | True |
| hide_portfolio | False |
| lookback | 15D(w1.0) |
| rebalance | quarterly_jan |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | ^VIX |
| safe_haven_asset | GLD |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,157, monthly_returns=192, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=648, trade_performance=44, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 5,060 |
| **判定** | ＿＿＿＿ |

### 白虎

| 項目 | 値 |
|------|-----|
| PF ID | `1400f299-804d-4ed4-b104-85ba9a4fbd01` |
| タイプ | standard |
| 作成日 | 2026-02-13 14:20:33 |
| is_active | True |
| hide_portfolio | False |
| lookback | 315D(w0.7), 63D(w0.3) |
| rebalance | quarterly_jan |
| top_n | 2 |
| relative_assets | TQQQ, TECL |
| absolute_asset | ^VIX |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,835, monthly_returns=177, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=573, trade_performance=29, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,633 |
| **判定** | ＿＿＿＿ |

### So-白虎

| 項目 | 値 |
|------|-----|
| PF ID | `0b615ce0-9299-4819-92ce-e674db5f4af9` |
| タイプ | standard |
| 作成日 | 2026-02-13 14:29:56 |
| is_active | True |
| hide_portfolio | False |
| lookback | 84D(w0.5), 21D(w0.5) |
| rebalance | quarterly_jan |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | ^VIX |
| safe_haven_asset | GLD |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,082, monthly_returns=189, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=633, trade_performance=32, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,955 |
| **判定** | ＿＿＿＿ |

### Nh-白虎

| 項目 | 値 |
|------|-----|
| PF ID | `e4388cd4-d96d-4757-bc04-d6e09313c4ce` |
| タイプ | standard |
| 作成日 | 2026-02-13 14:29:56 |
| is_active | True |
| hide_portfolio | False |
| lookback | 126D(w0.5), 63D(w0.4), 10D(w0.1) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | ^VIX |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,037, monthly_returns=187, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=623, trade_performance=86, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,952 |
| **判定** | ＿＿＿＿ |

### Ud-白虎

| 項目 | 値 |
|------|-----|
| PF ID | `b4f2c005-8f8c-464e-9d5a-54d7f1e6fee4` |
| タイプ | standard |
| 作成日 | 2026-02-13 14:29:56 |
| is_active | True |
| hide_portfolio | False |
| lookback | 105D(w0.4), 42D(w0.3), 10D(w0.3) |
| rebalance | quarterly_jan |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | ^VIX |
| safe_haven_asset | GLD |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,060, monthly_returns=188, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=628, trade_performance=35, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,930 |
| **判定** | ＿＿＿＿ |

### C-白虎

| 項目 | 値 |
|------|-----|
| PF ID | `b953ba4d-3ec8-48c1-9b76-cfb8468ae608` |
| タイプ | standard |
| 作成日 | 不明 |
| is_active | True |
| hide_portfolio | False |
| lookback | 105D(w0.4), 42D(w0.4), 10D(w0.2) |
| rebalance | quarterly_jan |
| top_n | 1 |
| relative_assets | TQQQ, TECL |
| absolute_asset | ^VIX |
| safe_haven_asset | GLD |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,060, monthly_returns=188, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=628, trade_performance=34, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,929 |
| **判定** | ＿＿＿＿ |

## 5. 玄武(DM7+)ファミリー

### DM7+ ⭐四神

| 項目 | 値 |
|------|-----|
| PF ID | `8650d48d-c60d-46de-b827-c4d38f276e37` |
| タイプ | standard |
| 作成日 | 2025-12-21 17:47:29 |
| is_active | True |
| hide_portfolio | True |
| lookback | 504D(w1.0) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | XLU |
| absolute_asset | SPXL |
| safe_haven_asset | TQQQ |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,632, monthly_returns=168, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=528, trade_performance=9, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,356 |
| **判定** | ＿＿＿＿ |

### DM7+_10D_X

| 項目 | 値 |
|------|-----|
| PF ID | `2246db9c-1627-4735-8a1c-94a38ca02673` |
| タイプ | standard |
| 作成日 | 2026-02-04 17:23:34 |
| is_active | True |
| hide_portfolio | True |
| lookback | 504D(w0.9), 10D(w0.1) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | XLU |
| absolute_asset | SPXL |
| safe_haven_asset | TQQQ |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,632, monthly_returns=168, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=528, trade_performance=11, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,358 |
| **判定** | ＿＿＿＿ |

### DM7+_10D_G_X_T1

| 項目 | 値 |
|------|-----|
| PF ID | `9c9f1f72-ee84-4d0e-a860-8569db3bf5ac` |
| タイプ | standard |
| 作成日 | 2026-02-04 17:30:07 |
| is_active | True |
| hide_portfolio | True |
| lookback | 504D(w0.9), 10D(w0.1) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | XLU, GLD |
| absolute_asset | SPXL |
| safe_haven_asset | TQQQ |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,632, monthly_returns=168, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=528, trade_performance=17, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,364 |
| **判定** | ＿＿＿＿ |

### DM7+_G

| 項目 | 値 |
|------|-----|
| PF ID | `abe1dfd4-41a5-4289-83c5-14ad23c6028e` |
| タイプ | standard |
| 作成日 | 2026-02-04 17:41:21 |
| is_active | True |
| hide_portfolio | True |
| lookback | 504D(w1.0) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | XLU, GLD |
| absolute_asset | SPXL |
| safe_haven_asset | TQQQ |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,632, monthly_returns=168, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=528, trade_performance=15, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,362 |
| **判定** | ＿＿＿＿ |

### C-玄武=Ud

| 項目 | 値 |
|------|-----|
| PF ID | `b5a9982b-9e34-4c3f-97fb-cf0f5bed53db` |
| タイプ | standard |
| 作成日 | 2026-02-11 18:59:19 |
| is_active | True |
| hide_portfolio | True |
| lookback | 504D(w1.0) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | XLU |
| absolute_asset | SPXL |
| safe_haven_asset | TQQQ |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,632, monthly_returns=168, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=528, trade_performance=9, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,356 |
| **判定** | ＿＿＿＿ |

### original-玄武

| 項目 | 値 |
|------|-----|
| PF ID | `1406db6d-97e0-4868-aa2e-eb37867d8c44` |
| タイプ | standard |
| 作成日 | 2026-02-13 13:07:11 |
| is_active | True |
| hide_portfolio | False |
| lookback | 504D(w1.0) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | XLU |
| absolute_asset | SPXL |
| safe_haven_asset | TQQQ |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,632, monthly_returns=168, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=528, trade_performance=9, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,356 |
| **判定** | ＿＿＿＿ |

### 玄武

| 項目 | 値 |
|------|-----|
| PF ID | `60c23ff7-0694-46d4-a848-f56e7d753f61` |
| タイプ | standard |
| 作成日 | 2026-02-13 14:20:33 |
| is_active | True |
| hide_portfolio | False |
| lookback | 252D(w1.0) |
| rebalance | quarterly_jan |
| top_n | 1 |
| relative_assets | XLU |
| absolute_asset | TECL |
| safe_haven_asset | TQQQ |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,902, monthly_returns=180, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=588, trade_performance=17, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,706 |
| **判定** | ＿＿＿＿ |

### So-玄武

| 項目 | 値 |
|------|-----|
| PF ID | `1350bc31-2eff-4da8-a865-0ab374c71474` |
| タイプ | standard |
| 作成日 | 2026-02-13 14:29:56 |
| is_active | True |
| hide_portfolio | False |
| lookback | 504D(w1.0) |
| rebalance | bimonthly_odd |
| top_n | 1 |
| relative_assets | XLU |
| absolute_asset | SPXL |
| safe_haven_asset | TQQQ |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,632, monthly_returns=168, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=528, trade_performance=5, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,352 |
| **判定** | ＿＿＿＿ |

### Nh-玄武

| 項目 | 値 |
|------|-----|
| PF ID | `ffcfcb6e-08cc-43f9-962d-35188f136724` |
| タイプ | standard |
| 作成日 | 2026-02-13 14:29:56 |
| is_active | True |
| hide_portfolio | False |
| lookback | 378D(w1.0) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | SPY |
| absolute_asset | TECL |
| safe_haven_asset | TQQQ |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,767, monthly_returns=174, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=558, trade_performance=12, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,530 |
| **判定** | ＿＿＿＿ |

### Ud-玄武

| 項目 | 値 |
|------|-----|
| PF ID | `34d12155-d1b3-4a0c-b951-67b124b45b95` |
| タイプ | standard |
| 作成日 | 2026-02-13 14:29:56 |
| is_active | True |
| hide_portfolio | False |
| lookback | 504D(w1.0) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | XLU |
| absolute_asset | SPXL |
| safe_haven_asset | TQQQ |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=3,632, monthly_returns=168, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=528, trade_performance=9, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,356 |
| **判定** | ＿＿＿＿ |

## 6. FoF(Fund of Funds)

### Ave-X

| 項目 | 値 |
|------|-----|
| PF ID | `a78887bf-25ae-4525-81af-cd4c630b3d36` |
| タイプ | fof |
| 作成日 | 2025-12-21 17:47:29 |
| is_active | True |
| hide_portfolio | False |
| 構成PF | DM2, DM6, DM7+, DM5, DM4, DM3 |
| rebalance | monthly |
| レコード件数 | signals=3,632, monthly_returns=168, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=528, trade_performance=148, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,495 |
| **判定** | ＿＿＿＿ |

### 裏Ave-X

| 項目 | 値 |
|------|-----|
| PF ID | `c1c80ace-8d1e-463a-860a-d0f40642a3a5` |
| タイプ | fof |
| 作成日 | 2026-01-02 18:52:21 |
| is_active | True |
| hide_portfolio | False |
| 構成PF | DM2, DM4, DM5, DM6 |
| rebalance | monthly |
| レコード件数 | signals=3,902, monthly_returns=180, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=588, trade_performance=157, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,846 |
| **判定** | ＿＿＿＿ |

### MIX3

| 項目 | 値 |
|------|-----|
| PF ID | `89011aa6-f245-4f32-855f-4f19f08bb041` |
| タイプ | fof |
| 作成日 | 2026-01-14 02:41:15 |
| is_active | True |
| hide_portfolio | False |
| 構成PF | DM2, DM3, DM4, DM5, DM6, DM7+, bam-2, bam-6 |
| rebalance | monthly |
| レコード件数 | signals=3,632, monthly_returns=168, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=528, trade_performance=82, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,429 |
| **判定** | ＿＿＿＿ |

### MIX2

| 項目 | 値 |
|------|-----|
| PF ID | `f0d925a8-49de-4c5a-bee7-f81f80615a35` |
| タイプ | fof |
| 作成日 | 2026-01-14 02:43:12 |
| is_active | True |
| hide_portfolio | False |
| 構成PF | DM2, DM3, DM4, DM5, DM6, DM7+, bam-2, bam-6 |
| rebalance | monthly |
| レコード件数 | signals=3,632, monthly_returns=168, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=528, trade_performance=44, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,391 |
| **判定** | ＿＿＿＿ |

### MIX4

| 項目 | 値 |
|------|-----|
| PF ID | `a6b4b39c-0def-4d25-985e-d83a1638e1fb` |
| タイプ | fof |
| 作成日 | 2026-01-14 02:43:37 |
| is_active | True |
| hide_portfolio | False |
| 構成PF | DM2, DM3, DM4, DM5, DM6, DM7+, bam-2, bam-6 |
| rebalance | monthly |
| レコード件数 | signals=3,632, monthly_returns=168, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=528, trade_performance=132, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,479 |
| **判定** | ＿＿＿＿ |

### MIX1

| 項目 | 値 |
|------|-----|
| PF ID | `899b3d8e-f5c6-43ef-ae5e-134e78952ee1` |
| タイプ | fof |
| 作成日 | 2026-01-14 02:44:03 |
| is_active | True |
| hide_portfolio | False |
| 構成PF | DM2, DM3, DM4, DM5, DM6, DM7+, bam-2, bam-6 |
| rebalance | monthly |
| レコード件数 | signals=3,632, monthly_returns=168, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=528, trade_performance=117, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,464 |
| **判定** | ＿＿＿＿ |

### 劇薬DMスムーズ

| 項目 | 値 |
|------|-----|
| PF ID | `7be147b9-77b7-44b7-b8ad-feb25d099c89` |
| タイプ | fof |
| 作成日 | 2026-01-15 10:19:25 |
| is_active | True |
| hide_portfolio | False |
| 構成PF | DM2-test, DM6, DM7+, DM-safe-2 |
| rebalance | monthly |
| レコード件数 | signals=3,632, monthly_returns=168, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=528, trade_performance=86, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,433 |
| **判定** | ＿＿＿＿ |

### 劇薬DMオリジナル

| 項目 | 値 |
|------|-----|
| PF ID | `4d1a7ae5-ecff-46c0-babb-2d210b568701` |
| タイプ | fof |
| 作成日 | 2026-01-15 13:44:27 |
| is_active | True |
| hide_portfolio | False |
| 構成PF | DM2-test, DM6, DM7+ |
| rebalance | monthly |
| レコード件数 | signals=3,632, monthly_returns=168, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=528, trade_performance=69, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,416 |
| **判定** | ＿＿＿＿ |

### bam-2

| 項目 | 値 |
|------|-----|
| PF ID | `f466a8d3-b6b3-482b-90ca-9b09e8b6165d` |
| タイプ | fof |
| 作成日 | 2026-01-15 14:20:44 |
| is_active | True |
| hide_portfolio | False |
| 構成PF | DM2-top, DM2-test, DM2-80%, DM2-60%, DM2-40%, DM2-20%, DM2 |
| rebalance | monthly |
| レコード件数 | signals=3,767, monthly_returns=174, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=558, trade_performance=81, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,599 |
| **判定** | ＿＿＿＿ |

### bam-6

| 項目 | 値 |
|------|-----|
| PF ID | `87fb78ca-74fe-4e94-9f9b-932aeb87b8eb` |
| タイプ | fof |
| 作成日 | 2026-01-15 17:29:18 |
| is_active | True |
| hide_portfolio | False |
| 構成PF | DM6, DM6-20%, DM6-40%, DM6-5, DM6-60%, DM6-80%, DM6-Top |
| rebalance | monthly |
| レコード件数 | signals=4,037, monthly_returns=187, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=623, trade_performance=144, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 5,010 |
| **判定** | ＿＿＿＿ |

### 劇薬bam

| 項目 | 値 |
|------|-----|
| PF ID | `9a33521c-0217-402e-894f-c3ca62265473` |
| タイプ | fof |
| 作成日 | 2026-01-16 05:31:56 |
| is_active | True |
| hide_portfolio | False |
| 構成PF | bam-2, bam-6, DM7+ |
| rebalance | monthly |
| レコード件数 | signals=3,632, monthly_returns=168, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=528, trade_performance=153, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,500 |
| **判定** | ＿＿＿＿ |

### 劇薬bam_solid

| 項目 | 値 |
|------|-----|
| PF ID | `dd247456-f800-4a71-933a-177ff112e0fa` |
| タイプ | fof |
| 作成日 | 2026-01-16 05:32:02 |
| is_active | True |
| hide_portfolio | False |
| 構成PF | bam-2, bam-6 |
| rebalance | monthly |
| レコード件数 | signals=3,767, monthly_returns=174, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=558, trade_performance=158, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,676 |
| **判定** | ＿＿＿＿ |

### 劇薬bam_guard

| 項目 | 値 |
|------|-----|
| PF ID | `1cc66240-692b-4f50-91a7-3b2830afd7bf` |
| タイプ | fof |
| 作成日 | 2026-01-16 05:32:23 |
| is_active | True |
| hide_portfolio | False |
| 構成PF | bam-2, bam-6, DM7+, DM-safe-2 |
| rebalance | monthly |
| レコード件数 | signals=3,632, monthly_returns=168, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=528, trade_performance=159, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,506 |
| **判定** | ＿＿＿＿ |

### 白虎_FoF_n2

| 項目 | 値 |
|------|-----|
| PF ID | `a23464f7-609f-41b6-824a-e5a9335d1d57` |
| タイプ | fof |
| 作成日 | 2026-02-09 19:05:36 |
| is_active | True |
| hide_portfolio | False |
| 構成PF | DM6_Qj_XLU_15M_3M_w70_30_T2, DM6_Qj_GLD_4M_1M_w50_50_T1 |
| rebalance | monthly |
| レコード件数 | signals=3,835, monthly_returns=177, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=573, trade_performance=46, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,650 |
| **判定** | ＿＿＿＿ |

### 朱雀_FoF_n2

| 項目 | 値 |
|------|-----|
| PF ID | `8300036e-714b-46b8-a7ab-101227702918` |
| タイプ | fof |
| 作成日 | 2026-02-09 19:05:36 |
| is_active | True |
| hide_portfolio | False |
| 構成PF | DM3_M_TMV_4M_3M_20D_w50_40_10_T1, DM3_Qj_TMV_3M_15D_w50_50_T1 |
| rebalance | monthly |
| レコード件数 | signals=4,082, monthly_returns=189, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=633, trade_performance=70, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,993 |
| **判定** | ＿＿＿＿ |

### 青龍_FoF_n3

| 項目 | 値 |
|------|-----|
| PF ID | `4db9a1f5-12d5-405e-8991-3ae29e07486a` |
| タイプ | fof |
| 作成日 | 2026-02-09 19:05:36 |
| is_active | True |
| hide_portfolio | False |
| 構成PF | DM2_Qj_GLD_10D_T1, DM2_Qj_XLU_11M_5M_1M_w50_30_20_T1, DM2_Be_GLD_18M_7M_1M_w60_30_10_T1 |
| rebalance | monthly |
| レコード件数 | signals=3,767, monthly_returns=174, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=558, trade_performance=55, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,573 |
| **判定** | ＿＿＿＿ |

### 加速-C

| 項目 | 値 |
|------|-----|
| PF ID | `bfbffa34-54f3-4c36-8c92-be63e14c71d1` |
| タイプ | fof |
| 作成日 | 2026-02-14 09:39:34 |
| is_active | True |
| hide_portfolio | False |
| 構成PF | 青龍=C=So, 朱雀=So, 白虎, 玄武, C-朱雀, C-白虎, C-玄武=Ud, Nh-青龍, Nh-朱雀, Nh-白虎, Nh-玄武 |
| rebalance | monthly |
| レコード件数 | signals=3,632, monthly_returns=168, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=528, trade_performance=77, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,424 |
| **判定** | ＿＿＿＿ |

## 7. その他(四神に属さないPF)

### DM4

| 項目 | 値 |
|------|-----|
| PF ID | `10ff2500-b3d2-479b-9b69-efd9d3949ee7` |
| タイプ | standard |
| 作成日 | 2025-12-21 17:47:29 |
| is_active | True |
| hide_portfolio | True |
| lookback | 20D(w1.0) |
| rebalance | monthly |
| top_n | 1 |
| relative_assets | TECL, TQQQ |
| absolute_asset | LQD |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,151, monthly_returns=192, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=648, trade_performance=131, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 5,141 |
| **判定** | ＿＿＿＿ |

### DM5

| 項目 | 値 |
|------|-----|
| PF ID | `9f919ebd-81ef-497f-9f88-7cb4a2ff665a` |
| タイプ | standard |
| 作成日 | 2025-12-21 17:47:29 |
| is_active | True |
| hide_portfolio | True |
| lookback | 20D(w1.0) |
| rebalance | bimonthly_odd |
| top_n | 1 |
| relative_assets | TECL, TQQQ |
| absolute_asset | LQD |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,151, monthly_returns=192, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=648, trade_performance=53, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 5,063 |
| **判定** | ＿＿＿＿ |

### DM5-006

| 項目 | 値 |
|------|-----|
| PF ID | `fb4e8f08-3c08-4c54-a0ca-c87c74b72e27` |
| タイプ | standard |
| 作成日 | 2025-12-21 17:47:29 |
| is_active | True |
| hide_portfolio | True |
| lookback | 126D(w1.0) |
| rebalance | bimonthly_odd |
| top_n | 1 |
| relative_assets | TECL, TQQQ |
| absolute_asset | LQD |
| safe_haven_asset | XLU |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,037, monthly_returns=187, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=623, trade_performance=33, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 4,899 |
| **判定** | ＿＿＿＿ |

### DM-safe

| 項目 | 値 |
|------|-----|
| PF ID | `45eb0c3a-a256-48f3-b3e3-d2a9d5c3bbfa` |
| タイプ | standard |
| 作成日 | 2025-12-21 17:47:29 |
| is_active | True |
| hide_portfolio | False |
| lookback | 252D(w0.6), 126D(w0.2), 42D(w0.2) |
| rebalance | monthly |
| top_n | 2 |
| relative_assets | QQQ, GLD, XLU |
| absolute_asset | LQD |
| safe_haven_asset | GLD |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,973, monthly_returns=230, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=838, trade_performance=63, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 6,123 |
| **判定** | ＿＿＿＿ |

### DM-safe-2

| 項目 | 値 |
|------|-----|
| PF ID | `fc5dc444-f14a-43d3-85c9-263c3220b658` |
| タイプ | standard |
| 作成日 | 2025-12-21 17:47:29 |
| is_active | True |
| hide_portfolio | True |
| lookback | 252D(w0.6), 42D(w0.2), 126D(w0.2) |
| rebalance | monthly |
| top_n | 2 |
| relative_assets | QLD, GDX, XLU |
| absolute_asset | LQD |
| safe_haven_asset | GLD |
| パイプライン | MomentumFilter → AbsoluteMomentumFilter → SafeHavenSwitch → EqualWeight |
| レコード件数 | signals=4,852, monthly_returns=224, drawdown_periods=10, rolling_returns_summary=5, rolling_returns_chart=808, trade_performance=62, portfolio_metrics=2, risk_management_metrics=2 |
| レコード合計 | 5,965 |
| **判定** | ＿＿＿＿ |
