# cmd_1987 Level A cProfile Inventory

Date: 2026-04-16
Source design: `docs/research/codd_dmsignal_python_strategy.md` §2

## Summary

- 設計書§2の Level A 実体は **15本**。`find` で以下を確認し、設計書の明示対象と一致した。
- `run_077_*.py` 7本は全て実在。設計書の「レベルA(研究)」表に漏れはなかった。
- cProfile 実測を取得できたのは **10本**。残り **5本** は入力欠如・環境前提不足・Windows spawn 制約で完走不能だった。
- 優先度は「実測 cumtime」と「Level A本体であるか」を併記して整理した。

## AC1 Inventory

| Category | File | LOC | Find |
|---|---|---:|---|
| A-1 | `scripts/analysis/grid_search/grid_search_metrics_v2.py` | 2300 | present |
| A-2 | `outputs/scripts/l1_alm_wf_engine.py` | 2546 | present |
| A-3 | `scripts/analysis/standard_pf_preprocessing/metrics_research_engine.py` | 2645 | present |
| A-4 | `scripts/analysis/grid_search/run_077_bunshin.py` | 809 | present |
| A-4 | `scripts/analysis/grid_search/run_077_kasoku_diff.py` | 1880 | present |
| A-4 | `scripts/analysis/grid_search/run_077_kasoku_ratio.py` | 1868 | present |
| A-4 | `scripts/analysis/grid_search/run_077_kawarimi.py` | 1537 | present |
| A-4 | `scripts/analysis/grid_search/run_077_nukimi.py` | 1731 | present |
| A-4 | `scripts/analysis/grid_search/run_077_oikaze.py` | 1352 | present |
| A-4 | `scripts/analysis/grid_search/run_077_yotsume.py` | 1566 | present |
| A-5 | `scripts/analysis/grid_search/gs_benchmark.py` | 1045 | present |
| A-6 | `outputs/scripts/champion_selector.py` | 278 | present |
| Phase 1 | `outputs/scripts/cmd_1847_neighbor_analysis.py` | 349 | present |
| Phase 1 | `outputs/scripts/cmd_1869_2x2_factor_analysis.py` | 410 | present |
| Phase 1 | `backend/scripts/compare_snapshots.py` | 251 | present |

## AC2 cProfile Results

### Success / partial success

| File | Scope | Result |
|---|---|---|
| `run_077_yotsume.py` | inline serial hot path, first 100 patterns | `simulate_pattern` 5.304s > `MultiViewMomentumFilter.execute` 4.406s > `relativedelta.__rsub__` 1.839s |
| `run_077_nukimi.py` | inline serial hot path, first 100 patterns | `simulate_pattern` 3.428s > `SingleViewMomentumFilter.execute` 1.012s > import bootstrap 0.944s |
| `run_077_oikaze.py` | inline serial hot path, first 100 patterns | `simulate_pattern` 2.160s > `MomentumFilter.execute` 0.653s > `numpy.isclose` 0.505s |
| `run_077_bunshin.py` | full main under cProfile | baseline 0.097s / fast 0.948s / total 2.9s。inline hot pathでは `simulate_pattern` 0.690s |
| `run_077_kasoku_ratio.py` | inline batch hot path, first 100 patterns | `simulate_batch` 0.008s > `calc_metrics_fast` 0.007s > `get_kasoku_context` 0.004s |
| `run_077_kasoku_diff.py` | inline batch hot path, first 100 patterns | `simulate_batch` 0.006s > `calc_metrics_fast` 0.005s > `get_kasoku_context` 0.004s |
| `run_077_kawarimi.py` | inline batch hot path, first 100 patterns | `get_sim_context` 0.008s > `simulate_batch` 0.006s > `calc_metrics_fast` 0.005s |
| `outputs/scripts/l1_alm_wf_engine.py` | subset `0000_10D` (2 cols), `--skip-analysis` | `main` 0.503s > `reconstruct_alm_returns` 0.216s > `_compute_metric_values_for_pattern` 0.172s |
| `outputs/scripts/champion_selector.py` | `--csv-dir outputs/grid_search --cmd-id 246 --ninjutsu bunshin` | `main` 0.165s > `load_data` 0.145s > `find_npy_or_csv` 0.010s |
| `backend/scripts/compare_snapshots.py` | baseline/fullrecalc sample JSON | `main` 4.421s > `compare_tables` 3.409s > `compare_records` 3.326s。全テーブル parity PASS |

### Failed / blocked

| File | LOC | Failure point | 推定理由 |
|---|---:|---|---|
| `scripts/analysis/grid_search/grid_search_metrics_v2.py` | 2300 | `sqlite3.OperationalError: no such table: grid_search_candidates` | SQLite fixture不足。benchmark subcommandがローカル候補テーブル前提 |
| `scripts/analysis/grid_search/gs_benchmark.py` | 1045 | bunshin serial benchmarkが `max_run_up__DM2` KeyError で 0 pattern | adapter の data loader が `run_077_bunshin` 期待キーと不整合 |
| `scripts/analysis/standard_pf_preprocessing/metrics_research_engine.py` | 2645 | `ValueError: could not convert string to float: '17 months'` | flat row 抽出時に非数値フィールド混入 |
| `outputs/scripts/cmd_1847_neighbor_analysis.py` | 349 | `FileNotFoundError: results CSV not found: bunshin` | 前段成果物不在 |
| `outputs/scripts/cmd_1869_2x2_factor_analysis.py` | 410 | `FileNotFoundError: cmd_1867_1186_bunshin_l1_wf_alm_returns.csv` | 前段 WF 成果物不在 |

## AC3 Priority List

### Level A本体の優先順位

| Priority | File | Why |
|---|---|---|
| 1 | `run_077_yotsume.py` | 100 pattern 時点で 5.304s。`MultiViewMomentumFilter.execute` が 83% を占有 |
| 2 | `run_077_nukimi.py` | 3.428s。`SingleViewMomentumFilter.execute` が最大支配 |
| 3 | `run_077_oikaze.py` | 2.160s。`MomentumFilter.execute` と `numpy.isclose` が支配 |
| 4 | `outputs/scripts/l1_alm_wf_engine.py` | subset 2列でも `reconstruct_alm_returns` と metric 再計算が支配 |
| 5 | `run_077_bunshin.py` | full run total 2.9s。改善余地はあるが上位3本より小さい |
| 6 | `backend/scripts/compare_snapshots.py` | 4.421sだが Level A補助。`compare_records` と `make_key` が主要コスト |
| 7 | `run_077_kasoku_ratio.py` | 100 pattern hot path 0.008s。最適化優先度は低い |
| 8 | `run_077_kasoku_diff.py` | 100 pattern hot path 0.006s。最適化優先度は低い |
| 9 | `run_077_kawarimi.py` | 100 pattern hot path 0.008s。batch path は既に軽い |
| 10 | `outputs/scripts/champion_selector.py` | 0.165s。ボトルネックは CSV fallback load。優先度低 |

### 再実行前提の blockers

| Priority | File | Blocker |
|---|---|---|
| B1 | `metrics_research_engine.py` | numeric metric 抽出で文字列混入 |
| B2 | `grid_search_metrics_v2.py` | `grid_search_candidates` fixture / DB 作成が必要 |
| B3 | `gs_benchmark.py` | bunshin adapter の key 整合が必要 |
| B4 | `cmd_1869_2x2_factor_analysis.py` | `cmd_1867` WF 出力を再配置する必要 |
| B5 | `cmd_1847_neighbor_analysis.py` | bunshin results CSV を再生成する必要 |

## §2 Table Cross-check

| 設計書記載 | 実測コメント |
|---|---|
| A-1 `grid_search_metrics_v2.py` | 実在確認。cProfile は DB fixture不足で停止 |
| A-2 `l1_alm_wf_engine.py` | 実在確認。subset filter は doc 記載 `N2_0000` では 0列、実際は `0000_10D` で 2列抽出 |
| A-3 `metrics_research_engine.py` | 実在確認。cProfile は parity 段で非数値文字列混入により停止 |
| A-4 `run_077_*.py` 7本 | 7/7 実在確認。6本は hot path 取得、1本(bunshin)は full main+hot path 取得 |
| A-5 `gs_benchmark.py` | 実在確認。bunshin adapter 不整合で 0 pattern |
| A-6 `champion_selector.py` | 実在確認。CSV fallback 経路で測定 |
| Phase1 `cmd_1847` | 実在確認。入力 CSV 不在で停止 |
| Phase1 `cmd_1869` | 実在確認。前段 WF CSV 不在で停止 |
| Phase1 `compare_snapshots.py` | 実在確認。sample snapshot で parity PASS + cProfile 取得 |

## Notes

- Windows Python + `cProfile -m` で multiprocessing を含む `run_077_yotsume.py` / `run_077_kasoku_ratio.py` を直実行すると `spawn` の pickling error が出る。今回の hotspot は inline import + serial/batch hot path で代替取得した。
- `l1_alm_wf_engine.py` の `subset_filter` は実装 `_key = parts[2] + '_' + parts[3]` に従うため、`oikaze_N2_0000_10D_N1_R1` では `0000_10D` が正キー。docstring 例 `N2_0000` は現実装と不一致。
- `champion_selector.py` は `.npy` cache より前に `214_bunshin_grid_monthly_fast.csv` を拾った。`cmd-id 246` を与えても fallback pattern が広いため、旧成果物混入リスクがある。L625/L623 と同根。
