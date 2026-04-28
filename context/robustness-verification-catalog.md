# 長期ロバストネス検証カタログ
<!-- last_updated: 2026-04-28 Phase 7.1 L0実証+アルファ空間原則追加 -->

> 目的: WF四神 / 忍法 / 奥義について、3年 / 5年 / 10年スパンの頑健性をいつでも再検証できるよう、実行可能な手法を8種に整理した実務カタログ。

## §0. アルファ空間原則（殿裁定 2026-04-28）

> 「どこでもアルファがあるのなら、その中で何を選ぶかは過適合とは言わない。」

**ロバストネスの第一指標 = パラメータ空間全体のCAGR正率。**

- 正率100% → 戦略の構造自体にアルファがある。champion選びは「アルファ空間内の最適化」であり過適合ではない
- 正率が低い → アルファが特定パラメータに局在。champion選びが過適合リスクを持つ
- peak_ratio(champion/隣接比)は正率100%の空間では「孤立スパイク=過適合」を意味しない。「全体がアルファの中でさらに良い点を選んだ」だけ
- **この原則は7手法全ての前に適用する。** 正率100%なら7手法は「過適合でないことの確認」ではなく「最適点の安定性の確認」になる

## §1. 先に結論

| 手法 | 何を問うか | 主対象層 | 既存の現物 |
|---|---|---|---|
| **アルファ空間検証** | **パラメータ空間全体にアルファがあるか(CAGR正率)** | **L0/L1/L2** | **`scripts/analysis/gs_grid_robustness.py`** |
| デケイ分析 | 一度強かった champion が時間とともに弱っていないか | L0/L1/L2 | `scripts/analysis/deterioration/run_full_verification.py` |
| Vintage分析 | 違う時点で選ばれた champion 同士で OOS が再現するか | L0/L1/L2 | `scripts/oneshot/cmd_1846_selection_timeline.py`, `cmd_1848_is_oos_champion_analysis.py` |
| パラメータ近傍分析 | champion が孤立ピークでないか(§0正率100%なら安定性確認に読替え) | L0/L1/L2 | `scripts/analysis/gs_grid_robustness.py` (peak_ratio) |
| ストレステスト | 極端局面でも benchmark より壊れにくいか | L1/L2/奥義 | `scripts/analysis/nested_fof/r28d_stress_test.py` |
| foldパーセンタイル検証 | 固定 champion が各 fold の母集団内でランダム以上を維持するか | L0 | `scripts/oneshot/cmd_2214_wf_shin_fold_percentiles.py` |
| α6指標top安定性 | 計算期間短縮で top 集合が崩れないか | L0/L1 | `scripts/analysis/standard_pf_preprocessing/cmd_2215_wf_alm_top_stability.py` |
| レジーム条件付き検証 | Bull/Bear/Sideways すべてで α が保てるか | L2/L3 | `scripts/oneshot/cmd_1934_v2_fast.py` |

## §2. 共通前提

| 項目 | 内容 |
|---|---|
| 実行場所 | `cd /mnt/c/Python_app/DM-signal` |
| 必須データ | `backend/.env` の DB 接続、`outputs/grid_search/` と `outputs/analysis/` の既存成果物 |
| 期間の見方 | 3年=36ヶ月, 5年=60ヶ月, 10年=120ヶ月 |
| 判定の基本線 | 1手法だけで採否を決めない。7手法のうち複数を通るかで総合判断する |

## §3. 実施済みの足場

### 3.1 foldパーセンタイル検証の現物 (`cmd_2214`)

- `WFシン四神 champion 12体 × 30 fold = 360 datapoints`
- 全体中央値 percentile は `72.5`
- 一方で最悪 fold percentile は `0.4` まで落ちる体もある
- 含意: 「固定 champion が全 fold で強い」は false。body ごとに安定度の差が大きい

参照: `/mnt/c/Python_app/DM-signal/docs/research/cmd_2214_wf_shin_fold_percentiles.md`

### 3.2 α6指標top安定性の現物 (`cmd_2215`)

- 4 family 横断で最も安定: `UWP` (`combined avg Jaccard = 0.837`)
- 最も不安定: `CAGR` (`combined avg Jaccard = 0.497`)
- 含意: 「top1 が強い」だけでは不十分で、指標ごとに top 集合の崩れ方を見る必要がある

参照: `/mnt/c/Python_app/DM-signal/docs/research/cmd_2215_wf_alm_top_stability_20260421.md`

### 3.3 アルファ空間検証の現物 (`cmd_2357`, Phase 7.1)

- L0シン四神 4family × 全3,195パターン(DM7+は4) = **CAGR正率100%**
- どのlookbackを選んでも全てプラスのアルファ

| family | 全パターン | CAGR正率 | 最低CAGR | 中央CAGR | 最高CAGR |
|--------|----------|--------|---------|---------|---------|
| DM2 | 3,195 | 100% | 19.8% | 36.1% | 49.3% |
| DM3 | 3,195 | 100% | 4.2% | 16.8% | 37.9% |
| DM6 | 3,195 | 100% | 7.5% | 28.5% | 53.0% |
| DM7+ | 4 | 100% | 26.7% | 31.6% | 36.8% |

- 含意: L0四神は戦略構造自体にアルファがある。champion選びは過適合ではない(§0原則)
- L1/L2は未検証。Phase 9.1/11.1で同じ検証を実施予定

参照: `outputs/robustness/20260428/L0/robustness_summary.yaml`

## §4. 8手法カタログ

### 4.1 デケイ分析

| 項目 | 内容 |
|---|---|
| 目的 | 過去時点 champion の優位が経年で摩耗していないか、賞味期限を直接測る |
| 入力 | `monthly_returns` テーブル、または対象PFの月次リターン系列 |
| 手順 | 1. 対象PFの月次リターンを取得  2. 6/12/24ヶ月窓で `p_det_roll` と `p_erosion` を計算  3. 直近3年/5年/10年でラベル推移を見る |
| 判定基準 | `GOOD` 維持なら頑健。`WATCH` は要監視。`DETERIORATING` は賞味期限切れ候補 |
| 対象層 | L0/L1/L2 |
| 即実行例 | 既存エンジン `run_full_verification.py` を使う |

```bash
cd /mnt/c/Python_app/DM-signal
python3 scripts/analysis/deterioration/run_full_verification.py
python3 - <<'PY'
import pandas as pd
df = pd.read_csv("scripts/analysis/deterioration/output/full_verification_report.csv")
target = df[df["window"] == 12][["fund", "p_det_roll", "p_erosion", "label"]]
print(target.sort_values(["label", "p_det_roll"], ascending=[True, False]).head(30).to_string(index=False))
PY
```

補足: この手法は「今の系列が弱っているか」を見るもので、時点別 champion を直接比較したい場合は次の Vintage 分析を併用する。

### 4.2 Vintage分析

| 項目 | 内容 |
|---|---|
| 目的 | 「2018時点で選んだ champion」「2020時点で選んだ champion」など、選出 vintage の違いで OOS が再現するかを見る |
| 入力 | GS monthly return CSV / cache、selection timeline、champion ID |
| 手順 | 1. 各時点の top 選出を timeline 化  2. ある時点の champion を固定  3. その後半 OOS で 6指標を再計測  4. vintage 間で劣化率を比較 |
| 判定基準 | 古い vintage でも OOS 劣化が小さく、後続 vintage と結論が大きく変わらなければ頑健 |
| 対象層 | L0/L1/L2 |
| 即実行例 | まず `cmd_1846` で選出履歴を出し、`cmd_1848` で前半選出 vs 後半OOS の基準ケースを実行する |

```bash
cd /mnt/c/Python_app/DM-signal
python3 scripts/oneshot/cmd_1846_selection_timeline.py
python3 scripts/oneshot/cmd_1848_is_oos_champion_analysis.py
```

出力の見方:

- `cmd_1846`: 月ごとの「誰が選ばれたか」を可視化し、vintage 切替点を特定する
- `cmd_1848`: 前半ISで選んだ 21 champion を後半OOSへ持ち込み、`CAGR/NHF/MaxDD/MRU/Calmar/UWP` の劣化率を出す

### 4.3 パラメータ近傍分析

| 項目 | 内容 |
|---|---|
| 目的 | champion が一点豪華主義の孤立ピークか、近傍でも再現する broad peak かを測る |
| 入力 | champion 設定値、近傍パラメータ格子、monthly return 系列 |
| 手順 | 1. champion を基準に `±1 / ±2` 近傍を生成  2. one-at-a-time で再BT  3. Sharpe/CAGR/Calmar 等の落差を比較 |
| 判定基準 | 近傍で Sharpe 急落 `>20%` なら過適合疑い。落差が緩いなら broad peak |
| 対象層 | L0/L1/L2 |
| 即実行例 | `cmd_1012_overfit_check.py` |

```bash
cd /mnt/c/Python_app/DM-signal
python3 scripts/analysis/cmd_1012_overfit_check.py
sed -n '1,120p' outputs/analysis/cmd_1012_overfit_check.md
```

注: `cmd_1012` は 2段 champion の実装だが、判定ロジック自体は「近傍急落を見る」という本質にそのまま使える。

### 4.4 ストレステスト

| 項目 | 内容 |
|---|---|
| 目的 | COVID / 利上げ / 急落月のような極端局面で、平常時の見かけ性能が剥がれていないかを見る |
| 入力 | 対象PF月次リターン、benchmark(EW / Ward / buy-and-hold 等)、極端期間定義 |
| 手順 | 1. 極端局面の月を定義  2. downturn 中の平均 / 最悪月 / 勝率を比較  3. DD開始→底→回復の長さを見る |
| 判定基準 | downturn 平均で benchmark 以上、最悪月が同等以下、回復が遅すぎないなら頑健 |
| 対象層 | L1/L2/奥義 |
| 即実行例 | `r28d_stress_test.py` |

```bash
cd /mnt/c/Python_app/DM-signal
python3 scripts/analysis/nested_fof/r28d_stress_test.py
```

補足: 既存スクリプトは `EW monthly return < -5%` を downturn 条件にしている。3年/5年/10年比較では、期間固定 stress window を追加して同じ表を作ればよい。

### 4.5 foldパーセンタイル検証

| 項目 | 内容 |
|---|---|
| 目的 | 固定 champion が各 walk-forward fold の母集団内で「ランダム以上」を維持するかを見る |
| 入力 | WF fold 窓、各 family の GS CSV、固定 champion ID |
| 手順 | 1. 実WFの OOS fold を読む  2. 各 fold で champion CAGR を計算  3. 同 fold の全 pattern 母集団に対する percentile を出す |
| 判定基準 | 中央値 percentile `>=50` を最低線とする。`worst_fold_percentile` と `folds_below_50` で尾部の脆さを見る |
| 対象層 | L0 |
| 即実行例 | `cmd_2214_wf_shin_fold_percentiles.py` |

```bash
cd /mnt/c/Python_app/DM-signal
python3 scripts/oneshot/cmd_2214_wf_shin_fold_percentiles.py
sed -n '1,120p' docs/research/cmd_2214_wf_shin_fold_percentiles.md
```

既存結果の読み:

- 全体中央値 `72.5` なので「平均的にはランダム以上」
- ただし最悪 `0.4` があるので「全fold頑健」ではない

### 4.6 α6指標top安定性

| 項目 | 内容 |
|---|---|
| 目的 | 計算期間を 3M / 6M / 9M ... と削っても top 集合がどれだけ保たれるかを見る |
| 入力 | `.cache.arr.npy`, `.cache.columns.npy`, `.cache.index.npy`、6objective 定義 |
| 手順 | 1. full 期間で top10 / top50 を確定  2. trailing window を短縮  3. 各期間で overlap rate / Jaccard を計測 |
| 判定基準 | `combined_avg_jaccard >= 0.70` を頑健の目安、`<0.50` を不安定の目安とする |
| 対象層 | L0/L1 |
| 即実行例 | `cmd_2215_wf_alm_top_stability.py` |

```bash
cd /mnt/c/Python_app/DM-signal
python3 scripts/analysis/standard_pf_preprocessing/cmd_2215_wf_alm_top_stability.py
sed -n '1,160p' docs/research/cmd_2215_wf_alm_top_stability_20260421.md
```

既存結果の読み:

- `UWP` は `combined avg Jaccard 0.837` で頑健
- `CAGR` は `0.497` で top 入替が大きく不安定

### 4.7 レジーム条件付き検証

| 項目 | 内容 |
|---|---|
| 目的 | Bull / Bear / Sideways のいずれでも α が正かを見て、「特定局面依存の勝ち」を炙り出す |
| 入力 | 対象PF月次リターン、SPY月次リターン、レジーム閾値 |
| 手順 | 1. benchmark に対する α系列を作る  2. SPY月次で `bull > +2%`, `bear < -2%`, 他を sideways に分割  3. 各 regime の α CAGR を計算 |
| 判定基準 | `regime_all_positive = yes` を最低線とし、各 regime 月数が十分あるかも同時確認する |
| 対象層 | L2/L3 |
| 即実行例 | `cmd_1934_v2_fast.py` |

```bash
cd /mnt/c/Python_app/DM-signal
python3 scripts/oneshot/cmd_1934_v2_fast.py
sed -n '1,160p' outputs/analysis/alm_research/cmd_1934_v2_fast_summary.md
```

補足: 既存スクリプトは 3体EW の全量探索だが、`regime_bull_alpha_cagr / regime_bear_alpha_cagr / regime_sideways_alpha_cagr / regime_all_positive` を既に出しているため、将来の WF四神 / 忍法 / 奥義にも同じ判定軸を移植しやすい。

## §5. どの順で当てるか

| 優先 | 手法 | 理由 |
|---|---|---|
| **0** | **アルファ空間検証** | **CAGR正率で過適合リスクの有無を一発判定。100%なら以降は安定性確認に集中** |
| 1 | foldパーセンタイル | 固定 champion が fold 母集団でどれだけ保つかを最短で見られる |
| 2 | α6指標top安定性 | top 入替の大きさを一目で見られる |
| 3 | パラメータ近傍分析 | §0正率100%なら「安定性確認」に読替え。broad peakかを見る |
| 4 | Vintage分析 | 選出時点依存を直接見られる |
| 5 | ストレステスト | 極端局面だけの脆さを拾える |
| 6 | レジーム条件付き検証 | Bear / Sideways 依存の偽装強者を落とせる |
| 7 | デケイ分析 | 本番配備後の継続監視として最も効く |

## §6. 総合判定ルール

| 判定 | 目安 |
|---|---|
| GO | 7手法中 5手法以上で明確PASS、かつ stress / regime / vintage に致命傷なし |
| WATCH | 7手法中 3-4手法PASS、または CAGR系だけ崩れるが防御系は維持 |
| NO-GO | fold percentile / neighbor / vintage / stress のうち2つ以上で明確FAIL |

## §7. 次に追加すべき実装

1. `cmd_1848` を単一の前半/後半 split から、3年刻みの multi-vintage ladder に一般化する。
2. `cmd_1934` の regime 判定ロジックを WF四神 / 忍法 / 奥義へ共通化する。
3. stress test を固定イベント窓（COVID, 2022利上げ, 2025急変）で定型化する。
