# モメンタム感度分析 第一弾 — 月末N営業日前(N感度) — AsIs/ToBe 5W1H設計書 v3.4 【✅完了】

> シリーズ: **第一弾=本書(N感度)** / 第二弾=執行日感度分析(`execution-delay-sensitivity-asis-tobe-5w1h_20260731.md`) / 第三弾=N×E二次元ロバストネス検証(`nxe-2d-robustness-asis-tobe-5w1h_20260801.md`)

## §0 セーブポイント

- 正本: 本ファイル
- 起点: 殿指示 2026-07-31「open to openだけ計算して結果を見てみたい」「DM2とDM6をやろう」「ローカルでやる。本番のコードは弄るな。GS用のコードを使ってもいいのでは？」「使えるものはできる限り既存のものを使おう」「FoFでもやらなければならない事は忘れるな」「累積資産曲線はいらない」
- v1.x系(6回レビュー): 過剰設計。殿指示で全面再構築
- v2.x: 実験ファースト化+殿の初期スクリーニング仕様追加
- v3.0-3.2: 軍師覚醒+殿7項目+プロット削除
- v3.3: 家老1往復目反映。ポジション変換ルール是正、DM6 quarterly_jan維持、分割境界一意化
- v3.4: 家老2往復目(最終FIX)反映。①DB接続2段階明記(本番→SQLite→load_prices) ②ポジション変換二値是正(absolute momentum>=DTB3) ③AC1比較先=monthly_return_open+holding/signal一致

## §1 やること

standard DM2（UUID: f8d70415-24f2-4b1a-a603-d0e86155255a）と standard DM6（UUID: 212e9eee-6acc-4f25-8a41-ea9fdf34a4e1）について:

signal endpointを月末からN営業日前にずらし、翌月openで執行した場合のopen-to-openリターンをN=0〜7で並べる。ベンチマーク（SPY）のopen-to-openリターンとの差（alpha）も出す。

## §2 用語

- signal endpoint: モメンタム計算の価格観測日。N=0=月末close（現行）。N=5=月末5営業日前close
- execution: 翌月初open。固定
- return: open-to-open。固定
- alpha: PF return_open − SPY return_open

## §3 実装方針

### 再利用する既存コード

DM-signal repo (`/mnt/c/Python_app/DM-signal`) の以下を再利用:

- **価格取得(2段階)**:
  1. `prefetch_gs_data.py` の `prefetch_daily_prices(engine, sqlite_conn, tickers)` — 本番DBからread-onlyで取得しローカルSQLite(`gs_prefetch.db`)へ書込み
  2. `grid_search_metrics_v2.py` の `load_prices(sqlite_conn)` — ローカルSQLiteからpivot済みDatetimeIndex DataFrameを返す(open/close)。`SELECT ticker,price_date,open,close FROM daily_prices`
  ※ load_pricesは本番DB接続を受け取らない(SQLite専用)
- **モメンタム計算**: `calculate_weighted_momentum_vectorized(prices, periods, weights, unit)` — close価格DataFrameから加重モメンタムを計算。unit='days'はnormalize_periodがそのまま返すため252/126/42/15は営業日そのもの
- **シグナル判定**: `simulate_strategy_vectorized()` にpipeline_config+PipelineEngineを渡して信号正本を再利用。手書き再実装を避ける
- **月初価格**: `get_month_start_open_prices(open_prices)` — execution price(翌月初open)

本番コードは変更しない。ローカルstandalone scriptで実装する。

### 核心のN-dayシフト

各calendar monthの実取引日列(prices.index)からmonth内最終取引日を特定し、そこからN日前を直接選ぶ:

```python
# calendar month groupでmonth-end取引日を特定
for year_month, group in prices.groupby(prices.index.to_period('M')):
    trading_days = group.index.sort_values()
    if len(trading_days) > N:
        signal_date = trading_days[-1 - N]
    # signal_dateのcloseでモメンタム計算
```

### シグナル→ポジション変換ルール（本番ロジック準拠）

DM2/DM6ともデュアルモメンタム(二値判定):
1. relative_assets(TQQQ, TECL)の加重モメンタムを計算
2. 上位top_n(=1)銘柄を選択
3. absolute_asset(DM2=LQD, DM6=^VIX)の加重モメンタムとrisk_free_asset(DTB3)の加重モメンタムを比較
4. **absolute_asset momentum >= DTB3 momentum** → relative選択を保持
5. **absolute_asset momentum < DTB3 momentum** → safe_haven(DM2=XLU, DM6=GLD)を保持
6. ※ 選択銘柄のmomentumとabsolute_assetは直接比較しない
7. **SPYはポジション変換に使わない**。SPYはalpha計算(PF return − SPY return)のbenchmarkのみ
8. 可能な限り`simulate_strategy_vectorized()`+pipeline_config+PipelineEngineを再利用し、手書き再実装を避ける

### リバランストリガー（本番準拠）

- **DM2**: rebalance_trigger=monthly → 毎月リバランス
- **DM6**: rebalance_trigger=quarterly_jan → 1,4,7,10月のみリバランス。非リバランス月はholding継続
- AC1 parityはこのトリガーを維持した上で検証する。毎月holding更新ではparity不能

### 最小実装

```
1. prefetch_daily_prices(engine,sqlite_conn)で本番DB→ローカルSQLiteへTQQQ,TECL,SPY,XLU,GLD,LQD,^VIX,DTB3を取得。load_prices(sqlite_conn)でDataFrame化
2. N=0〜7の各値について:
   a. 月末N営業日前のcloseを取得(上記シフトロジック)
   b. calculate_weighted_momentum_vectorizedでシグナル計算
      DM2: periods=[252,126,42], weights=[0.6,0.2,0.2], unit='days'
      DM6: periods=[15], weights=[1.0], unit='days'
   c. シグナル→ポジション変換(relative top_n→absolute_asset momentum >= DTB3 momentum?→保持/safe haven)
      simulate_strategy_vectorized+pipeline_configを再利用。リバランス月のみ判定。非リバランス月(DM6)はholding継続
   d. 翌月初openでリターン算出(open-to-open)
   e. SPY open-to-openリターンも算出
   f. alpha = PF return - SPY return
3. 全N結果をCSV出力
4. CAGR/Sharpe(rf=0)/MaxDD(月次)/累積リターン(数値)の比較表を生成
5. 結果をCSV+画面に出力
```

### 環境

- **ローカル完結**。本番コードは触らない
- DB接続: 本番pricesテーブルのread-only→ローカルSQLite(gs_prefetch.db)。DM-signal backend/.envのDATABASE_URL→prefetch→SQLite→load_prices
- Python venv: `/mnt/c/Python_app/DM-signal/.venv` (pandas,numpy,sqlalchemy)
- 出力: CSV + 画面表示

### 拡張性

本実験はDM2/DM6で先行するが、最終的にはFoF含む全PFに適用する。コードはPF IDをパラメータで受け取る設計にし、後でFoFに拡張できるようにする。

## §4 AC

- AC1: N=0 parity — DM2/DM6各PF × 当該PFの全データ月(DM2=2011-03〜, DM6=2010-03〜)について、本番`monthly_returns.monthly_return_open`と一致（abs<=1e-6）。**holding/signalも一致**（returnだけの偶然一致を防止）。mismatch=0。リバランストリガー(DM2=monthly, DM6=quarterly_jan)を維持した上で検証。不一致→N>0停止
- AC2: DM2/DM6それぞれについてN=0〜7のopen-to-open return + alpha(SPY対比)がCSV出力。CSV列: pf_id/year_month/N/signal/return_open/SPY_return_open/alpha（後段FoF入力にも再利用可能）
- AC3: N×PFのCAGR/Sharpe/MaxDD/累積リターン比較表(全期間) + 前半/後半の粗い期間分割比較表がdocs/researchに保存。N=0との差分も表示。分割境界=全期間の中央月(len//2で一意化。DM6: 98/99月, DM2: 92/93月)。方向逆転(前半改善/後半悪化またはその逆)の有無を二値記録

## §5 殿の初期スクリーニング仕様（殿直筆 2026-07-31 02:05）

### 目的

月末からN営業日前にモメンタムを計算したとき、成績がどのように変化するかを素早く確認する。この段階では、将来の本番採用可否や厳密なアルファ検定は行わない。

### 実施内容

- 代表的な2ポートフォリオ（standard DM2, standard DM6）を使う
- 既存の全期間バックテストをそのまま使う
- モメンタム計算日だけを変更する
- 執行日、執行価格、その他の条件は固定する
- N = 0を基準とする

N_VALUES = [0, 1, 2, 3, 4, 5, 6, 7]

### 最低限見る指標

- CAGR
- Sharpe ratio
- 最大ドローダウン
- 累積リターン（数値のみ。プロット不要）

必要ならN = 0との差分も表示する。

### 見るべきポイント（7項目）

1. **水準**: 各NのCAGR/Sharpe/MaxDDがどう変わるか。N=0を基準に差分で比較
2. **方向性**: Nを大きくするにつれて改善/悪化する傾向があるか。単調でなくても一貫した形があるか
3. **滑らかさ**: 隣接するNで成績が急激に飛ばないか。ギザギザ→ノイズや偶然を疑う
4. **安定領域**: N=3〜5など複数の連続したNで改善するか。最良の一点ではなく広い良好領域
5. **効果量**: 改善が実務的に意味のある大きさか（Sharpe 0.01改善は無意味、0.1以上は有意味）
6. **PF間一貫性**: 複数PFで似た形が出るか。一部PFだけが平均を押し上げていないか
7. **期間依存性**: 全期間だけでなく前半/後半の粗い期間分割で方向性が大きく逆転しないか（正式WFは不要）

**初期検証の問い**: Nを変えたとき、成績に滑らかで再現性のある変化が生じ、その変化量は実務的に意味があり、複数PFと粗い期間分割で共通しているか

## §6 PF構成情報（DB確認済み 2026-07-31）

- DM2: relative_assets=[TQQQ, TECL], absolute_asset=LQD, safe_haven=XLU, benchmark=SPY, top_n=1, rebalance=monthly, lookback=252日(0.6)+126日(0.2)+42日(0.2)加重
- DM6: relative_assets=[TQQQ, TECL], absolute_asset=^VIX, safe_haven=GLD, benchmark=SPY, top_n=1, rebalance=quarterly_jan, lookback=15日(1.0)
- DTB3: absolute momentum閾値の参照(risk_free_asset)。両PF共通
- データ期間: DM2=2011-03〜2026-07(185月), DM6=2010-03〜2026-07(197月)

## §7 因果リンク

- origin: `[[殿指示_open_to_open_20260731]] -> [[GS既存コード活用]] -> [[N日前感度分析v3.0_殿仕様貫通]]`
- ← [[Tranching_Dilemma_Zarattini_Pagani_2025]]（動機付け）

---

# 実験結果 (cmd_4198 GATE CLEAR 2026-07-31)

## §8 検証条件

- **Portfolio 1**: standard DM2 (UUID: `f8d70415-24f2-4b1a-a603-d0e86155255a`)
  - relative_assets: TQQQ, TECL
  - absolute_asset: LQD
  - safe_haven: XLU
  - benchmark: SPY
  - risk_free_asset: DTB3
  - top_n: 1
- **Portfolio 2**: standard DM6 (UUID: `212e9eee-6acc-4f25-8a41-ea9fdf34a4e1`)
  - relative_assets: TQQQ, TECL
  - absolute_asset: ^VIX
  - safe_haven: GLD
  - benchmark: SPY
  - risk_free_asset: DTB3
  - top_n: 1
- モメンタム計算: 加重モメンタム (`calculate_weighted_momentum_vectorized`)。close価格のリターンを指定期間で計算し重みで加重平均
- ルックバック: DM2=252日(0.6)+126日(0.2)+42日(0.2)、DM6=15日(1.0)
- デュアルモメンタム: relative(TQQQ vs TECL → top_n=1) + absolute(absolute_asset momentum >= DTB3 momentum → 保持/safe_haven)
- リバランス頻度: DM2=monthly、DM6=quarterly_jan(1,4,7,10月のみ)
- 検証期間: DM2=2011-03〜2026-07(185ヶ月)、DM6=2010-03〜2026-07(197ヶ月)
- 使用価格: シグナル=Close(株式分割調整済み)、執行=Open(翌月初取引日)
- リターン: open-to-open(月初open→翌月初open)
- ベンチマーク: SPY(open-to-open)
- リスクフリーレート: Sharpe計算でrf=0。DTB3はabsolute momentum閾値比較に使用
- シグナル計算日: 当月最終取引日からN営業日前のclose
- 執行日: 翌月初取引日のopen(全Nで固定)
- 執行価格: 翌月初取引日のopen price
- 売買コスト: 含めていない
- 配当: 価格データに反映済み(adjusted close相当のclose列)
- N以外に変更した条件: なし

## §9 Nの定義

- Nは**営業日(取引日)**。暦日ではない
- N=0: その月の最終取引日のclose
- 月末日: その月の最終取引日(暦月末ではない)
- N日前の計算: 当該月の実取引日列(prices.indexをcalendar month groupでフィルタ)の末尾から`-1-N`番目を選択
- 取引所カレンダー: 価格データの存在日で暗黙決定(NYSE準拠)
- 祝日・休場日: 価格データに存在しない日は自動スキップ
- 検証したN: `N_VALUES = [0, 1, 2, 3, 4, 5, 6, 7]`

実装: `prices.shift(n_days)` でDataFrame全体をN行シフト(L58)。close価格の時系列をN取引日分遅延させることと等価。

## §10 執行日の固定

- すべてのNで執行日は同一: **YES**。翌月初取引日のopen
- すべてのNで執行価格の定義は同一: **YES**。翌月初取引日のopen price
- Nを前倒しした場合もポジションは月初まで変更しなかった: **YES**
- シグナル形成日から執行日までシグナルを固定した: **YES**
- Nによって保有期間の開始日や終了日が変わっていない: **YES**。保有期間は常に「当月初open→翌月初open」

## §11 ルックアヘッドの確認

- N日前より後の価格をモメンタム計算に使用していないか: `prices.shift(n_days)`の正のshiftにより**先頭N行**がNaN化される。月末日付の行にはN取引日前の価格が配置されるため、月末後半の価格はシグナル計算に使われない
- 月末価格をN日前のシグナルに混入させていないか: NO。月末日付の行にはN取引日前の価格値が入り、月末当日〜N-1日前の価格は参照されない
- シグナル形成後の情報を資産選択に使用していないか: NO
- 執行価格をシグナル計算に使用していないか: NO(close=シグナル、open=執行は別列)
- Adjusted Closeに将来情報が入る可能性: 全Nで同一データ使用のためN間の相対比較には影響しない
- N=0が既存戦略と一致したか: **YES**(AC1 parityでreturn/holding/signal全月一致、mismatch=0)

3ヶ月の例示(NYSE営業日カレンダーに基づく推定):

| 月 | 月末最終取引日 | N | シグナル計算日 | 最終価格日 | 執行日 | 執行価格 |
|-----|------------|---|------------|----------|------|--------|
| 2023-06 | 2023-06-30(金) | 0 | 2023-06-30 | 2023-06-30 close | 2023-07-03(月) | open |
| 2023-06 | 2023-06-30(金) | 2 | 2023-06-28(水) | 2023-06-28 close | 2023-07-03(月) | open |
| 2023-06 | 2023-06-30(金) | 5 | 2023-06-23(金) | 2023-06-23 close | 2023-07-03(月) | open |
| 2024-01 | 2024-01-31(水) | 0 | 2024-01-31 | 2024-01-31 close | 2024-02-01(木) | open |
| 2024-01 | 2024-01-31(水) | 2 | 2024-01-29(月) | 2024-01-29 close | 2024-02-01(木) | open |
| 2024-01 | 2024-01-31(水) | 5 | 2024-01-24(水) | 2024-01-24 close | 2024-02-01(木) | open |
| 2025-03 | 2025-03-31(月) | 0 | 2025-03-31 | 2025-03-31 close | 2025-04-01(火) | open |
| 2025-03 | 2025-03-31(月) | 2 | 2025-03-27(木) | 2025-03-27 close | 2025-04-01(火) | open |
| 2025-03 | 2025-03-31(月) | 5 | 2025-03-24(月) | 2025-03-24 close | 2025-04-01(火) | open |

※ 日付はNYSE営業日カレンダー推定値。正確な日付はDBの取引日インデックスで決定。

## §12 ポートフォリオ別の全結果

SPYベンチマーク(DM2期間 2011-03〜2026-07, 185ヶ月): CAGR=0.1374、Sharpe=0.9545、MaxDD=-0.2331

### DM2 (185ヶ月)

| PF | N | CAGR | Ann.Vol | Sharpe | MaxDD | Cumul.Ret | Final Asset | Mo.Mean | Mo.Std | Corr SPY | BM CAGR | CAGR Excess | BM Sharpe | Sharpe Diff |
|----|---|------|---------|--------|-------|-----------|-------------|---------|--------|----------|---------|-------------|-----------|-------------|
| DM2 | 0 | 0.4512 | 0.4661 | 1.0376 | -0.6102 | 310.24 | 311.24 | 0.0403 | 0.1346 | 0.7331 | 0.1374 | 0.3137 | 0.9545 | 0.0832 |
| DM2 | 1 | 0.3713 | 0.4311 | 0.9599 | -0.6102 | 129.05 | 130.05 | 0.0345 | 0.1244 | 0.7255 | 0.1374 | 0.2339 | 0.9545 | 0.0054 |
| DM2 | 2 | 0.4069 | 0.4536 | 0.9836 | -0.6102 | 192.15 | 193.15 | 0.0372 | 0.1309 | 0.6927 | 0.1374 | 0.2695 | 0.9545 | 0.0291 |
| DM2 | 3 | 0.4508 | 0.4548 | 1.0526 | -0.6102 | 309.04 | 310.04 | 0.0399 | 0.1313 | 0.6852 | 0.1374 | 0.3134 | 0.9545 | 0.0982 |
| DM2 | 4 | 0.4125 | 0.4651 | 0.9792 | -0.6102 | 204.28 | 205.28 | 0.0380 | 0.1343 | 0.6903 | 0.1374 | 0.2751 | 0.9545 | 0.0247 |
| DM2 | 5 | 0.3867 | 0.4377 | 0.9721 | -0.6102 | 153.42 | 154.42 | 0.0355 | 0.1264 | 0.6499 | 0.1374 | 0.2492 | 0.9545 | 0.0176 |
| DM2 | 6 | 0.3726 | 0.4358 | 0.9502 | -0.6102 | 130.91 | 131.91 | 0.0345 | 0.1258 | 0.6573 | 0.1374 | 0.2351 | 0.9545 | -0.0043 |
| DM2 | 7 | 0.4137 | 0.4374 | 1.0174 | -0.6102 | 206.97 | 207.97 | 0.0371 | 0.1263 | 0.6473 | 0.1374 | 0.2763 | 0.9545 | 0.0630 |

※ Final Asset = 1 + Cumul.Ret（初期投資1に対する最終資産価値）

### DM6 (197ヶ月)

| PF | N | CAGR | Ann.Vol | Sharpe | MaxDD | Cumul.Ret | Final Asset | Mo.Mean | Mo.Std | Corr SPY | BM CAGR | CAGR Excess | BM Sharpe | Sharpe Diff |
|----|---|------|---------|--------|-------|-----------|-------------|---------|--------|----------|---------|-------------|-----------|-------------|
| DM6 | 0 | 0.5311 | 0.4585 | 1.1484 | -0.4999 | 1088.33 | 1089.33 | 0.0439 | 0.1324 | 0.5600 | 0.1426 | 0.3885 | 0.9712 | 0.1772 |
| DM6 | 1 | 0.5076 | 0.4181 | 1.1920 | -0.4999 | 843.82 | 844.82 | 0.0415 | 0.1207 | 0.5826 | 0.1426 | 0.3650 | 0.9712 | 0.2208 |
| DM6 | 2 | 0.5360 | 0.4560 | 1.1597 | -0.4999 | 1147.51 | 1148.51 | 0.0441 | 0.1316 | 0.5600 | 0.1426 | 0.3935 | 0.9712 | 0.1886 |
| DM6 | 3 | 0.5097 | 0.4538 | 1.1235 | -0.4999 | 863.48 | 864.48 | 0.0425 | 0.1310 | 0.5609 | 0.1426 | 0.3671 | 0.9712 | 0.1523 |
| DM6 | 4 | 0.5338 | 0.4574 | 1.1541 | -0.4999 | 1119.88 | 1120.88 | 0.0440 | 0.1320 | 0.5608 | 0.1426 | 0.3912 | 0.9712 | 0.1829 |
| DM6 | 5 | 0.5236 | 0.4551 | 1.1432 | -0.4270 | 1004.34 | 1005.34 | 0.0434 | 0.1314 | 0.5637 | 0.1426 | 0.3811 | 0.9712 | 0.1720 |
| DM6 | 6 | 0.5026 | 0.4538 | 1.1128 | -0.4999 | 799.47 | 800.47 | 0.0421 | 0.1310 | 0.5591 | 0.1426 | 0.3601 | 0.9712 | 0.1417 |
| DM6 | 7 | 0.5156 | 0.4531 | 1.1336 | -0.4999 | 920.36 | 921.36 | 0.0428 | 0.1308 | 0.5603 | 0.1426 | 0.3730 | 0.9712 | 0.1624 |

## §13 N=0との比較

### DM2

| PF | N | ΔCAGR vs N0 | ΔSharpe vs N0 | ΔMaxDD vs N0 | MaxDD変化 |
|----|---|-------------|---------------|-------------|----------|
| DM2 | 0 | 0.0000 | 0.0000 | 0.0000 | 基準 |
| DM2 | 1 | -0.0799 | -0.0778 | 0.0000 | 変化なし |
| DM2 | 2 | -0.0442 | -0.0541 | 0.0000 | 変化なし |
| DM2 | 3 | -0.0004 | +0.0150 | 0.0000 | 変化なし |
| DM2 | 4 | -0.0387 | -0.0585 | 0.0000 | 変化なし |
| DM2 | 5 | -0.0645 | -0.0655 | 0.0000 | 変化なし |
| DM2 | 6 | -0.0786 | -0.0874 | 0.0000 | 変化なし |
| DM2 | 7 | -0.0375 | -0.0202 | 0.0000 | 変化なし |

### DM6

| PF | N | ΔCAGR vs N0 | ΔSharpe vs N0 | ΔMaxDD vs N0 | MaxDD変化 |
|----|---|-------------|---------------|-------------|----------|
| DM6 | 0 | 0.0000 | 0.0000 | 0.0000 | 基準 |
| DM6 | 1 | -0.0235 | +0.0436 | 0.0000 | 変化なし |
| DM6 | 2 | +0.0049 | +0.0114 | 0.0000 | 変化なし |
| DM6 | 3 | -0.0214 | -0.0249 | 0.0000 | 変化なし |
| DM6 | 4 | +0.0027 | +0.0057 | 0.0000 | 変化なし |
| DM6 | 5 | -0.0075 | -0.0052 | +0.0729 | 改善 |
| DM6 | 6 | -0.0285 | -0.0355 | 0.0000 | 変化なし |
| DM6 | 7 | -0.0155 | -0.0148 | 0.0000 | 変化なし |

## §14 ベンチマーク優位性の確認

### DM2

- 全NでCAGRがベンチマークを上回ったか: **YES**(最低N=6: 0.3726 vs SPY 0.1374)
- 全NでSharpeがベンチマークを上回ったか: **7/8**(N=6: 0.9502 vs SPY 0.9545、差-0.004で実質同等)
- ベンチマークを下回ったN: SharpeでN=6のみ(差は0.0043)
- 最も悪いN: CAGR→N=6(0.3726)、Sharpe→N=6(0.9502)
- 最も悪いNでも優位性は維持されたか: CAGRでは明確に維持(+23.5pp)。Sharpeでは実質同等
- 性能崩壊によるベンチマーク優位性の消失: なし

### DM6

- 全NでCAGRがベンチマークを上回ったか: **YES**(最低N=6: 0.5026 vs SPY 0.1426)
- 全NでSharpeがベンチマークを上回ったか: **YES**(最低N=6: 1.1128 vs SPY 0.9712)
- ベンチマークを下回ったN: なし
- 最も悪いN: CAGR→N=6(0.5026)、Sharpe→N=6(1.1128)
- 最も悪いNでも優位性は維持されたか: **YES**(CAGR +36.0pp、Sharpe +0.142)
- 性能崩壊によるベンチマーク優位性の消失: なし

### 総括表

| PF | Tested N | N CAGR>BM | N Sharpe>BM | Worst N(CAGR) | Worst N(Sharpe) | Robust Across All N |
|----|----------|-----------|-------------|---------------|-----------------|---------------------|
| DM2 | 8 | 8/8 | 7/8 | N=6(0.3726) | N=6(0.9502) | YES |
| DM6 | 8 | 8/8 | 8/8 | N=6(0.5026) | N=6(1.1128) | YES |

「Robust Across All N」の判定基準:
1. すべてのNでCAGRがベンチマークを上回る
2. すべてのNでSharpeがベンチマークを上回る（DM2 N=6は差-0.004で実質同等と判断）
3. 特定のNで極端な性能崩壊がない（§16で確認）

## §15 Nに対する性能変動の大きさ

| PF | CAGR Min | CAGR Max | CAGR Range | Sharpe Min | Sharpe Max | Sharpe Range | MaxDD Best | MaxDD Worst | Std CAGR | Std Sharpe |
|----|----------|----------|------------|------------|------------|--------------|------------|-------------|----------|-----------|
| DM2 | 0.3713 | 0.4512 | 0.0799 | 0.9502 | 1.0526 | 0.1024 | -0.6102 | -0.6102 | 0.0292 | 0.0350 |
| DM6 | 0.5026 | 0.5360 | 0.0334 | 1.1128 | 1.1920 | 0.0791 | -0.4270 | -0.4999 | 0.0121 | 0.0228 |

DM6の変動はDM2の約半分(CAGR Range 3.3pp vs 8.0pp、Std 1.2pp vs 2.9pp)。

## §16 極端に悪いNの確認

- ベンチマークを下回るN: CAGRではなし。SharpeでDM2 N=6のみ(差0.004、実質同等)
- N=0よりCAGRが大幅に低下するN: DM2 N=1(-8.0pp)とN=6(-7.9pp)が最大乖離。DM6では最大N=6の-2.8pp
- N=0よりSharpeが大幅に低下するN: DM2 N=6(-0.087)が最大。DM6 N=6(-0.036)
- MaxDDが大幅に悪化するN: DM2は全N同一(-0.6102)。DM6も-0.4999以下(N=5のみ-0.4270で改善)
- 他のNから明らかに離れた外れ値: なし。DM2のN=1,6が最低圏だが他のNとの差は連続的

**判定: 性能崩壊と呼べる明確な外れ値は存在しない。**

## §17 期間別の確認

検証期間を機械的にlen//2で前半・後半に2分割。DM2: 前半92ヶ月/後半93ヶ月、DM6: 前半98ヶ月/後半99ヶ月。

### SPYベンチマーク（期間別）

| PF期間 | Period | Months | Range | SPY CAGR | SPY Sharpe | SPY MaxDD |
|--------|--------|--------|-------|----------|------------|-----------|
| DM2 | first_half | 92 | 2011-03..2018-10 | 0.1195 | 1.0787 | -0.1710 |
| DM2 | second_half | 93 | 2018-11..2026-07 | 0.1554 | 0.9136 | -0.2331 |
| DM6 | full | 197 | 2010-03..2026-07 | 0.1426 | 0.9712 | -0.2331 |
| DM6 | first_half | 98 | 2010-03..2018-04 | 0.1345 | 1.1077 | -0.1710 |
| DM6 | second_half | 99 | 2018-05..2026-07 | 0.1506 | 0.8992 | -0.2331 |

### DM2

SPY BM: first_half CAGR=0.1195, second_half CAGR=0.1554

| N | Period | CAGR | Sharpe | MaxDD | BM超過CAGR |
|---|--------|------|--------|-------|-----------|
| 0 | first_half | 0.4457 | 1.2351 | -0.3802 | +0.3262 |
| 0 | second_half | 0.4566 | 0.9545 | -0.6102 | +0.3012 |
| 1 | first_half | 0.4481 | 1.2396 | -0.3802 | +0.3286 |
| 1 | second_half | 0.2993 | 0.7858 | -0.6102 | +0.1439 |
| 2 | first_half | 0.4581 | 1.2649 | -0.3802 | +0.3386 |
| 2 | second_half | 0.3581 | 0.8355 | -0.6102 | +0.2027 |
| 3 | first_half | 0.4532 | 1.2558 | -0.3802 | +0.3337 |
| 3 | second_half | 0.4485 | 0.9588 | -0.6102 | +0.2931 |
| 4 | first_half | 0.4532 | 1.2558 | -0.3802 | +0.3337 |
| 4 | second_half | 0.3734 | 0.8459 | -0.6102 | +0.2180 |
| 5 | first_half | 0.4405 | 1.2225 | -0.3802 | +0.3210 |
| 5 | second_half | 0.3354 | 0.8244 | -0.6102 | +0.1800 |
| 6 | first_half | 0.4344 | 1.2123 | -0.3802 | +0.3149 |
| 6 | second_half | 0.3140 | 0.7935 | -0.6102 | +0.1586 |
| 7 | first_half | 0.3970 | 1.1263 | -0.3802 | +0.2775 |
| 7 | second_half | 0.4304 | 0.9651 | -0.6102 | +0.2750 |

**全N×両期間でSPY CAGRを上回る。** 最小超過=DM2 N=1 second_half +14.4pp。

### DM6

SPY BM: full CAGR=0.1426, first_half CAGR=0.1345, second_half CAGR=0.1506

| N | Period | CAGR | Sharpe | MaxDD | BM超過CAGR |
|---|--------|------|--------|-------|-----------|
| 0 | first_half | 0.3766 | 1.0651 | -0.3265 | +0.2421 |
| 0 | second_half | 0.7011 | 1.2422 | -0.4999 | +0.5505 |
| 1 | first_half | 0.3815 | 1.0875 | -0.3265 | +0.2470 |
| 1 | second_half | 0.6437 | 1.2909 | -0.4999 | +0.4931 |
| 2 | first_half | 0.3797 | 1.0823 | -0.3265 | +0.2452 |
| 2 | second_half | 0.7083 | 1.2518 | -0.4999 | +0.5577 |
| 3 | first_half | 0.3466 | 1.0211 | -0.3265 | +0.2121 |
| 3 | second_half | 0.6906 | 1.2326 | -0.4999 | +0.5400 |
| 4 | first_half | 0.3756 | 1.0663 | -0.3265 | +0.2411 |
| 4 | second_half | 0.7083 | 1.2518 | -0.4999 | +0.5577 |
| 5 | first_half | 0.3438 | 1.0133 | -0.3265 | +0.2093 |
| 5 | second_half | 0.7253 | 1.2719 | -0.4270 | +0.5747 |
| 6 | first_half | 0.3393 | 1.0033 | -0.3265 | +0.2048 |
| 6 | second_half | 0.6839 | 1.2259 | -0.4999 | +0.5333 |
| 7 | first_half | 0.3641 | 1.0619 | -0.3091 | +0.2296 |
| 7 | second_half | 0.6821 | 1.2226 | -0.4999 | +0.5315 |

**全N×両期間でSPY CAGRを大幅に上回る。** 最小超過=DM6 N=6 first_half +20.5pp。

方向逆転(前半で改善/後半で悪化またはその逆)は32行中14行(44%)。ただし全N×両期間でBM超過が確認されたため、**インデックス優位性は前半・後半のいずれでも消失していない。**

## §18 月次リターン系列

CSV存在: **YES**
- ファイル: `docs/research/cmd_4198_n_day_returns.csv`
- 行数: 3,056行(ヘッダ除く)
- 列: `pf_id, year_month, N, signal, return_open, SPY_return_open, alpha`
- 各PF×各N(0-7)の全月リターンを含む
- 第三者はこのCSVから全指標を再計算可能

関連CSV:
- `docs/research/cmd_4198_n_day_metrics.csv` — N×PFの集計指標(16行)
- `docs/research/cmd_4198_n_day_split_metrics.csv` — 前半/後半分割指標(32行)

## §19 結果の要約

### 最終判定文

月末から0〜7営業日前までシグナル形成日を変更した結果、DM2およびDM6のいずれにも性能崩壊は認められなかった。

DM2は全NでSPYを大幅に上回るCAGRを維持しており、戦略優位性という意味ではロバストである。ただし、CAGRのレンジが約8ポイントあり、特に後半期間ではNによる成績差が比較的大きいため、性能水準そのものには中程度の感度がある。

DM6はCAGRレンジ約3.3ポイント、Sharpeレンジ約0.08に収まり、全Nで高い絶対成績を維持しているため、Nに対して強くロバストである。

したがって、両戦略とも特定の月末計算日にのみ依存して成立している可能性は低い。ただし、DM2については形成日の変更が収益水準に与える影響を無視できるとは結論しない。

### Portfolio 1: DM2 (standard DM2)

- 全Nでベンチマーク超過(CAGR): **Yes**(最低N=6: +23.5pp)
- 全NでSharpeがベンチマーク超過: **No**(N=6のみ0.9502 vs BM 0.9545、差-0.004で実質同等)
- 極端に悪いN: **なし**（性能崩壊は認められない）
- Nに対する性能変動: **中程度**(CAGR Range 8.0pp、Std 2.9pp)
- 戦略優位性のロバストネス: **Yes**（全NでBM大幅超過、崩壊するNなし）
- 性能不変性のロバストネス: **中程度**（CAGR 8.0ppレンジ、後半期間でN依存性がより顕著: N=0 CAGR 45.7% vs N=1 29.9% vs N=6 31.4%）
- 判断根拠: Nを変えてもインデックスに対する優位性は維持されるが、収益水準には一定のN依存性がある

### Portfolio 2: DM6 (standard DM6)

- 全Nでベンチマーク超過(CAGR): **Yes**(最低N=6: +36.0pp)
- 全NでSharpeがベンチマーク超過: **Yes**(最低N=6: 1.1128 vs BM 0.9712、+0.142)
- 極端に悪いN: **なし**
- Nに対する性能変動: **小さい**(CAGR Range 3.3pp、Std 1.2pp)
- 戦略優位性のロバストネス: **Yes**
- 性能不変性のロバストネス: **強い**（CAGR 3.3ppレンジ、N=0の53.1%に対して6.2%）
- 判断根拠: N=0〜7のシグナル形成日に対して、収益性・リスク調整後成績の両面で強くロバスト
- 注記: DM6は四半期リバランス(quarterly_jan)のため、197ヶ月のリターン観測に対してNによって変わる独立シグナル更新は約65回。初期スクリーニングとしては問題ないが、後の統計検定では月次197件をすべて独立なN検証標本として扱わない方がよい

## §20 実験で確認しなかったこと

- 最良のNの推薦: 実施していない
- 正式なアルファ検定: 実施していない
- ウォークフォワード検証: 実施していない
- 売買コスト・回転率の精密分析: 実施していない
- DM6固有期間のSPYベンチマーク値: **算出済み**(§17)。DM6全期間SPY CAGR=0.1426(197ヶ月)、前半=0.1345(98ヶ月)、後半=0.1506(99ヶ月)。全N×両期間でBM超過を確認
- 前半/後半のSPYベンチマーク: **算出済み**(§17)。DM2前半SPY CAGR=0.1195/後半=0.1554、DM6前半=0.1345/後半=0.1506。全N×両期間×両PFでBM超過CAGR正を確認(最小超過=DM2 N=1 second_half +14.4pp)

## §21 実装コード

- スクリプト: `scripts/analysis/cmd_4198_month_end_n_day_sensitivity.py`(328行)
- 実行: `python3 scripts/analysis/cmd_4198_month_end_n_day_sensitivity.py --db gs_prefetch.db --production-signals production_signals.txt`
- 依存: `grid_search_metrics_v2.py`(simulate_strategy_vectorized, load_prices, MomentumCache, PORTFOLIO_CONFIGS)

## §22 用語の注記

- CSV列名`alpha`は`PF monthly return − SPY monthly return`であり、統計的な回帰アルファ(Jensen's alpha)ではない。正確にはexcess_return(超過リターン)またはactive_return(アクティブリターン)。初期スクリーニングでは回帰アルファの計算は不要であるため、CSV列名の変更は後段で必要になった際に実施する
