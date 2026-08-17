# cmd_4353 GS FoF子PF選択 parity 偵察・実装証跡

- 検証日時: 2026-08-18 JST
- 対象HEAD: `63d1b3e0e1afe3b9642a9ca1ff21960f88b1b2c3`
- 本番oracle: `backend/app/services/pipeline/selection.py:223-259` の `select_top_n_deterministic`
- 対象: `run_077_*.py` 7本（bunshin / kasoku_diff / kasoku_ratio / kawarimi / nukimi / oikaze / weighted_yotsume）および `run_l1plus_backtest.py`

## 1. AsIs（実装前の一次検索）

|方式|ファイル・関数・行|実装前の選択|本番oracleとの差|
|---|---|---|---|
|bunshin|`run_077_bunshin.py:get_sim_context:250`|EqualWeightで候補全員を通過。子PF選択なし|差異なし（選択責務なし）|
|oikaze|`run_077_oikaze.py:get_sim_context:450-495`|top_n=1は`nanmax`、top_n>1は`build_picks_mask_cutoff`、同率は全包含|ε相対1e-9、12M/CAGR/MaxDD/現保有/設定来、component_orderの6段keyなし|
|nukimi|`run_077_nukimi.py:get_sim_context:487-528`|同上（SingleView）|同上|
|kasoku_diff|`run_077_kasoku_diff.py:get_kasoku_context:918-962`|加速score行列を`nanmax`/cutoffで選抜、同率全包含|同上。ratio/diffの一次score以降のkeyなし|
|kasoku_ratio|`run_077_kasoku_ratio.py:get_kasoku_context:734-778`|ratio score行列を`nanmax`/cutoffで選抜、同率全包含|同上|
|kawarimi|`run_077_kawarimi.py:get_sim_context:385-421`|3D argsortでtop[:N]+worst[-N:]をunion|top枝・bottom枝それぞれの6段keyなし。枝合成順だけは維持|
|weighted_yotsume|`run_077_weighted_yotsume.py:get_sim_context:487-514`|4視点ごとに`nanmax`/cutoff、同率全包含後にvote count|視点ごとの6段keyなし。視点→vote合成順は維持|
|l1 fast path|`run_l1plus_backtest.py:353-382` `run_backtest`|各blockの`execute`を逐次実行し`component_order`/`price_data`を渡す|独自選択算術なし。各production blockがoracleを使用|

共通波及先は、各 `get_sim_context` の `precomputed_picks`/`precomputed_masks`、各 `simulate_batch`（oikaze:941、nukimi:837、kasoku_diff:1231、kasoku_ratio:1038、kawarimi:716、weighted_yotsume:934）および `gs_numba_kernels.py` のpacked-mask/Numba return kernelである。旧方式はmaskを前方充填して翌月リターンへ渡すため、選抜差分が全下流リターン・monthly blob・metricsへ伝播する。

## 2. ToBe / 実装後の一次検索

`scripts/analysis/grid_search/gs_numba_kernels.py:78-194` に共通adapterを追加した。

- `build_picks_mask_deterministic`: 各月の候補を`components`順（production `component_order`）で構築し、`price_data`、target_date、previous_tickersを渡して本番`select_top_n_deterministic`を呼ぶ。
- `build_picks_mask_top_bottom_deterministic`: TrendReversalのtop枝とbottom枝を同じcommon selectorへ個別に渡し、最後にunionする。
- `build_monthly_price_data`: production cumulative_returnを優先してclose履歴DataFrameへ変換する。

呼出し波及は以下の通り。

|方式|実装後の呼出し|
|---|---|
|oikaze|`run_077_oikaze.py:473`（lookback視点ごと）|
|nukimi|`run_077_nukimi.py:506`（skip/effective視点ごと）|
|kasoku_diff|`run_077_kasoku_diff.py:939`（score keyごと）|
|kasoku_ratio|`run_077_kasoku_ratio.py:755`（score keyごと）|
|kawarimi|`run_077_kawarimi.py:401`（top/bottom枝ごと）|
|weighted_yotsume|`run_077_weighted_yotsume.py:502`（4視点ごと、後段vote count）|
|bunshin / l1|選択変更なし。bunshinは選択責務なし、l1はproduction blockを逐次実行|

依存順序は `score matrix → price_data/target_date/previous_tickers/component_order → common selector → view/branch union or vote → forward-fill → return kernel`。前段で候補集合を削らず、score欠損だけをproductionと同じく除外する。top_n=1のnanmax近道と同率全包含は廃止した。

## 3. 赤→緑 parity 計測

Contract test: `scripts/analysis/grid_search/test_cmd_4353_selection_parity.py`（全テストに`test_necessity`を明記）。

- 実装前方式の再現（legacy cutoff）: 36か月×4候補、legacy選択108セル、production oracle選択36セル、差分72セル（赤）。
- 実装後: `pytest -q scripts/analysis/grid_search/test_cmd_4353_selection_parity.py` → **3 passed, 0 failed, 0 skipped**（緑）。
- TrendReversal: top/bottomを個別selectorへ通したunionをcontract testで検証。
- full FoF運用時は各run_077の全候補PF×全月score matrixが同じadapterへ入る。DB oracle runの実行証跡はAC3のgs-bench-gate before/afterで収集する。

## 4. エッジケース・副作用・順序制約

1. 12M/CAGR/MaxDDは候補集合全員に履歴がある場合だけ比較し、欠損時はproduction selectorの集合単位skipへ委譲する。
2. 全6段同値は入力`components`順で決着する。setのiteration orderを使わない。
3. previous_tickersは月次選択結果を次月へ渡す。weighted_yotsumeは各視点を独立評価し、視点間ではprevious stateを混ぜず、最後にvoteする。
4. kawarimiはtop/bottomを別々に選び、union後に既存のforward-fillとリターン計算を行う。weighted_yotsumeはview選択後にvote countを計算する。合成順を逆転させない。
5. 本変更はGSスクリプト・GS共通kernel・contract test・研究成果物・設計書に限定し、`backend/app/services/pipeline/selection.py` とproduction pipeline blocksは変更しない。
