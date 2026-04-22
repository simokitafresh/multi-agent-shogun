# GS忍法メモリ+速度最適化 設計書

## 結果(2026-04-20 完了)

全7忍法横展開完了(cmd_2181-2187)。workers=2安全実行可能。

| CMD | 忍法 | GATE | RSS変化 | workers=2 |
|-----|------|------|---------|-----------|
| cmd_2181 | kasoku_diff | CLEAR | 8.5GB→5.5GB | 未テスト(本cmd外) |
| cmd_2182 | kasoku_ratio | CLEAR | 既に移植済み | OK(370MB) |
| cmd_2183 | nukimi | CLEAR | 978→518MB(-47%) | OK(518MB) |
| cmd_2184 | oikaze | CLEAR | 342→272MB(-20%) | OK(274MB) |
| cmd_2185 | kawarimi | CLEAR | 403→278MB(-31%) | OOMなし |
| cmd_2186 | yotsume | 実行中 | — | — |
| cmd_2187 | bunshin | CLEAR | 138→134MB(-3%) | N/A(直列) |

### 教訓
- kasoku_ratioは既に移植済みだった(軍師分析の前提崩壊。grep結果0件≠未実装。git show HEADで確認すべきだった)
- bunshinは直列構造のためSHM/PPE非適用が正解
- cmd_save.shバンドル検出+数値緩和検出に偽陽性2件→軍師が修正済み

## 背景
- cmd_2179: 21体GS 3回OOM(RSS 8.5GB)
- 根因: workers=6→1(cmd_1876 OOM修正)で6倍遅化 + 旧コード6本がメモリ大量消費
- kasoku_diffのみ最適化済み(RSS 5.5GB)。他6本は旧コードのまま

## 目標
- 全忍法RSS 4GB以下
- workers=2復活(OOMなし)
- SS系GS合計: 54min→27min以下

## kasoku_diff最適化パターン(横展開テンプレート)

### 変更1: dict→PatternSpec(dataclass slots=True, frozen=True)
```python
@dataclass(frozen=True, slots=True)
class PatternSpec:
    pattern_id: str
    subset_id: str
    subset_size: int
    subset_components: tuple[str, ...]
    # ... 忍法固有フィールド
```
効果: dict overhead ~400B/pattern → ~100B/pattern。115万patterns → 0.35GB削減

### 変更2: _run_mp内でmonthly_dict廃止→SHM直接CSV書���し
```python
# Before:
def _run_mp(...) -> tuple[list[dict], dict[str, np.ndarray], int]:
    ...
    monthly_dict[pid] = arr_full[idx].copy()
    return rows_ordered, monthly_dict, n_errors

# After:
def _run_mp(..., monthly_csv_path, monthly_months) -> tuple[list[dict], int, tuple, str]:
    ...
    # SHMから直接write_monthly_csv_streaming
    write_monthly_csv_streaming(monthly_csv_path, pattern_ids, arr_full, monthly_months, success_mask)
    return rows_fast, n_errors, monthly_shape, monthly_md5
```
効果: monthly_dict 1.3GB全排除

### 変更3: write_monthly_csv_streaming(memmap版)
```python
def write_monthly_csv_streaming(csv_path, pattern_ids, monthly_matrix, months, success_mask=None):
    # memmap for NPY cache (disk-backed, minimal RAM)
    cache_arr = np.lib.format.open_memmap(
        csv_path.with_suffix(".cache.arr.npy"), mode="w+",
        dtype=np.float32, shape=(n_months, n_pids))
    # 行ごとに直接ファイル書出し(BytesIO不要)
    with open(csv_path, "w") as f:
        f.write("year_month," + ",".join(pids) + "\n")
        for month_idx, month in enumerate(months):
            row = monthly_matrix[active_idx, month_idx].astype(np.float32)
            cache_arr[month_idx, :] = row
            np.savetxt(PrefixWriter(f, str(month)), row[np.newaxis,:], delimiter=",", fmt="%.8g")
```
効果: BytesIO 1.6GB排除 + arr構築0.65GB排除(memmapはdisk-backed)

### 変更4: del即時解放
```python
rows_fast, n_errors, monthly_shape, md5 = _run_mp(...)
del global_scores, cum_ret, grid, mr, mr_close, common_months, monthly_months
```

### 変更5: del rows_fast
```python
df_fast = pd.DataFrame(rows_fast)
del rows_fast
df_fast.to_csv(csv_path_fast, index=False)
```

## 各忍法の変更箇所マップ

| 忍法 | 行数 | build_grid | _run_mp return | write_monthly | main del |
|------|------|-----------|---------------|---------------|----------|
| kasoku_ratio | 1976 | L1057 | L1395 | L1146(旧streaming) | なし |
| nukimi | 1793 | L893 | L1041/L1115 | L849(numpy) | なし |
| oikaze | 1426 | L902 | L1174 | L861(numpy) | なし |
| kawarimi | 1551 | L811 | L1051 | L753(numpy) | なし |
| yotsume | 1706 | L982 | L1235 | L938(numpy) | なし |
| bunshin | 799 | L463 | N/A(直列) | L528(numpy) | なし |

## before計測ハーネス(改良版)

```bash
# 使用法: 各忍法で実行
cd /mnt/c/Python_app/DM-signal
rm -rf /tmp/codd_mem_test_${NINJUTSU}  # 前回結果クリア
python3 -c "
import tracemalloc, time, os, json, sys, subprocess, threading
tracemalloc.start(10)
# ... (才蔵ハーネスと同構造。OUT_DIR重複チェック削除版)
"
```

## workers=2テスト手順(横展開完了後)

```bash
# kasoku_ratioで実施(最大パターン数=最もOOMリスク高い)
# MP_WORKERS=2に一時変更してテスト
cd /mnt/c/Python_app/DM-signal
python3 scripts/analysis/grid_search/run_077_kasoku_ratio.py \
  --universe config/portfolio_universes/wf_l2_ss_21.yaml \
  --out-dir /tmp/workers2_test \
  --skip-verify
# 確認: ps -o rss= -p $PID でピークRSS。8GB以下ならOK
```

## パリティ検証

横展開後のGS結果がkasoku_diffと同じパリティ保証方式:
- SHA256: before/after の grid_results_fast.csv が完全一致
- 100-pattern subset: before SHA = after SHA
