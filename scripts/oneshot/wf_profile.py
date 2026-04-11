#!/usr/bin/env python3
"""WFエンジン プロファイル計測スクリプト。
bunshin(最小CSV)でフェーズ別時間を計測し、kasoku_diff推定に使用。

使い方:
  cd /mnt/c/Python_app/DM-signal
  python3 /mnt/c/tools/multi-agent-shogun/scripts/oneshot/wf_profile.py
"""
import sys, time, os
sys.path.insert(0, "/mnt/c/Python_app/DM-signal")
os.chdir("/mnt/c/Python_app/DM-signal")

import numpy as np
import cProfile
import pstats
from io import StringIO

# bunshinで計測(最小CSV = 4,686パターン)
CSV = "outputs/grid_search/okugi_shin_ninpo_20body/cmd_1822_okugi_shin_ninpo_20body_bunshin_grid_monthly_20260409.csv"

from outputs.scripts.l1_alm_wf_engine import (
    load_data, generate_folds, generate_folds_multi_is,
    run_all_folds_np, run_multi_is_selection, select_champions,
    MULTI_IS_MIN, MULTI_IS_MAX, METRIC_NAMES, MINIMIZE_SET,
)
OBJECTIVES = METRIC_NAMES  # 6目的 = METRIC_NAMES

print("=== WF Profile: bunshin (4,686 patterns) ===")
print()

# Phase 1: load_data
t0 = time.perf_counter()
arr, columns, index = load_data(CSV, None, False)
t1 = time.perf_counter()
n_patterns = len(columns)
print(f"[Phase 1] load_data: {t1-t0:.3f}s  shape=({len(index)}, {n_patterns})")

arr_clean = np.array(arr, dtype=np.float32)
np.nan_to_num(arr_clean, copy=False)

# Phase 2: generate_folds
t2 = time.perf_counter()
folds = generate_folds(index)
is_candidates = list(range(MULTI_IS_MIN, MULTI_IS_MAX + 1))
multi_is_folds = generate_folds_multi_is(index, is_candidates)
t3 = time.perf_counter()
n_folds = len(folds)
n_multi_is = len(multi_is_folds)
print(f"[Phase 2] generate_folds: {t3-t2:.3f}s  folds={n_folds}  multi_is_groups={n_multi_is}")

# Phase 3: run_all_folds_np (38メトリクス計算)
t4 = time.perf_counter()
fold_metrics = run_all_folds_np(arr_clean, list(columns), index, folds, parallel=True, workers=6, progress=False)
t5 = time.perf_counter()
print(f"[Phase 3] run_all_folds_np(parallel=True, w=6): {t5-t4:.3f}s  ({n_folds} folds × {n_patterns} patterns)")

# Phase 3b: run_all_folds_np (--no-parallel比較)
t5b = time.perf_counter()
fold_metrics_seq = run_all_folds_np(arr_clean, list(columns), index, folds, parallel=False, workers=1, progress=False)
t5c = time.perf_counter()
print(f"[Phase 3b] run_all_folds_np(parallel=False): {t5c-t5b:.3f}s  (speedup: {(t5c-t5b)/(t5-t4):.1f}x)")

# Phase 4: run_multi_is_selection (チャンピオン選出)
t6 = time.perf_counter()
multi_is_results = run_multi_is_selection(
    arr_clean, list(columns), multi_is_folds, OBJECTIVES, MINIMIZE_SET,
    parallel=True, workers=6, progress=False,
)
t7 = time.perf_counter()
print(f"[Phase 4] run_multi_is_selection(parallel=True, w=6): {t7-t6:.3f}s  ({n_multi_is} IS windows)")

# Phase 4b: run_multi_is_selection (--no-parallel比較)
t7b = time.perf_counter()
multi_is_results_seq = run_multi_is_selection(
    arr_clean, list(columns), multi_is_folds, OBJECTIVES, MINIMIZE_SET,
    parallel=False, workers=1, progress=False,
)
t7c = time.perf_counter()
print(f"[Phase 4b] run_multi_is_selection(parallel=False): {t7c-t7b:.3f}s  (speedup: {(t7c-t7b)/(t7-t6):.1f}x)")

print()
print("=== サマリ ===")
total_par = (t1-t0) + (t3-t2) + (t5-t4) + (t7-t6)
total_seq = (t1-t0) + (t3-t2) + (t5c-t5b) + (t7c-t7b)
print(f"Total (parallel=True):  {total_par:.1f}s")
print(f"Total (parallel=False): {total_seq:.1f}s")
print(f"Parallel speedup: {total_seq/total_par:.1f}x")
print()
print("=== kasoku_diff推定 (944K patterns, bunshinの{:.0f}倍) ===".format(944775/n_patterns))
ratio = 944775 / n_patterns
print(f"Phase 3 (folds): bunshin {t5-t4:.1f}s × {ratio:.0f} = {(t5-t4)*ratio:.0f}s parallel")
print(f"Phase 4 (multi-is): bunshin {t7-t6:.1f}s × {ratio:.0f} = {(t7-t6)*ratio:.0f}s parallel")
print(f"Phase 3b (seq): bunshin {t5c-t5b:.1f}s × {ratio:.0f} = {(t5c-t5b)*ratio:.0f}s sequential")
print(f"Phase 4b (seq): bunshin {t7c-t7b:.1f}s × {ratio:.0f} = {(t7c-t7b)*ratio:.0f}s sequential")
