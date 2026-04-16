# cmd_1991 l1_alm_wf_engine.py リファクタリング仕様書

<!-- created: 2026-04-16 -->
<!-- worker: kotaro -->
<!-- parent_cmd: cmd_1991 -->
<!-- target: /mnt/c/Python_app/DM-signal/outputs/scripts/l1_alm_wf_engine.py (2546行) -->

## §1 Before計測 (cProfile)

### 実行コマンド
```bash
cd /mnt/c/Python_app/DM-signal
.venv/Scripts/python.exe -m cProfile -s cumtime outputs/scripts/l1_alm_wf_engine.py \
  --csv outputs/analysis/cmd1987_oikaze_DM2_grid_monthly_fast.csv \
  --subset-filter 0000_10D --skip-analysis
```
- 条件: subset 0000_10D (2列), 30fold, --skip-analysis
- 実行環境: Windows Python (.venv/Scripts/python.exe) on WSL2

### Before計測結果

| 関数 | ncalls | cumtime | percall |
|------|--------|---------|---------|
| `main` (L2064) | 1 | 0.801s | 0.801s |
| `reconstruct_alm_returns` (L1429) | 1 | 0.349s | 0.349s |
| `_compute_metric_values_for_pattern` (L925) | 176 | 0.276s | 0.002s |
| `run_all_folds_np` (L948) | 2/1 | 0.029s | - |

- cmd_1987実測値との比較: main 0.503s/0.801s, reconstruct 0.216s/0.349s, _compute 0.172s/0.276s
  (今回の値が高い理由: システム負荷・WSL2 I/O変動による)

### 支配構造
- `reconstruct_alm_returns` + `_compute_metric_values_for_pattern` ≈ 0.625s = main(0.801s)の78%を占有

## §2 codd extract結果

- 実行: `codd extract --source-dirs outputs/scripts`
- 結果: 0モジュール検出
- 理由: `outputs/scripts/` は `__init__.py` 不在の standalone script ディレクトリ。
  CoDDのPython extractはパッケージ構造を前提とするため、standalone scriptには適用不可。
- 出力先: `docs/research/cmd_1991_codd_extract/` (system-context.md, architecture-overview.mdの骨格のみ)
- **対応**: §3の手動specで代替 (Phase 3ハイブリッド方式の想定内)

## §3 ホットスポット分析

### Hot 1: `_compute_metric_values_for_pattern` (L925) — 176回×0.002s

```python
def _compute_metric_values_for_pattern(arr, fold, pattern_idx):
    year_slice = pd.date_range(fold.is_start, fold.is_end, freq="MS").year.to_numpy(dtype=np.int32)
    month_slice = pd.date_range(fold.is_start, fold.is_end, freq="MS").month.to_numpy(dtype=np.int32)
    # ↑ 同一引数で pd.date_range を2回作成 (冗長)
    ...
```

**問題**: 同一 `(fold.is_start, fold.is_end, freq="MS")` で `pd.date_range` を2回呼び出している。
`pd.date_range` のオーバーヘッドが176回×2 = 352回発生。

**修正方針**: `pd.date_range` を1回だけ呼び出し、`year`/`month` を同一オブジェクトから取得。

```python
# 修正後
def _compute_metric_values_for_pattern(arr, fold, pattern_idx):
    dr = pd.date_range(fold.is_start, fold.is_end, freq="MS")
    year_slice = dr.year.to_numpy(dtype=np.int32)
    month_slice = dr.month.to_numpy(dtype=np.int32)
    ...
```

**推定改善**: pd.date_range呼び出し回数を352→176に削減。この関数のtottime約50%削減見込み。

### Hot 2: `reconstruct_alm_returns` (L1429) — 1回×0.349s

```python
# 問題点1: iterrows() は pandas行イテレーション (遅い)
for _, row in obj_timeline.iterrows():
    ...
    # 問題点2: OOSループでスカラーアクセス+pd.Series×1個を毎回生成
    for ri in range(fold.oos_row_start, fold.oos_row_end + 1):
        month = index[ri]
        if month not in assigned_months:
            ret_val = float(arr[ri, col_i])
            pieces.append(pd.Series([ret_val], index=[month]))  # 毎回 Series 作成
            assigned_months.add(month)

# 問題点3: 多数の1要素Seriesをconcat (遅い)
combined = pd.concat(pieces).sort_index()
```

**問題**:
1. `iterrows()` がオブジェクト型変換+Seriesラップで遅い
2. OOSループ内で毎月1個の `pd.Series` を生成し `pieces` に追加 → 128ヶ月なら128個の1要素Seriesが生成される
3. `pd.concat(128個の1要素Series)` は連結オーバーヘッドが大きい
4. `arr[ri, col_i]` がスカラーアクセス (ループ内)

**修正方針**:
1. `iterrows()` → `itertuples()` (pandas行イテレーション高速化)
2. `pieces: list[pd.Series]` → `months_list: list`, `values_list: list` で個別要素を収集
3. 最後に1回 `pd.Series(values_list, index=pd.DatetimeIndex(months_list))` で構築
4. OOSスライスを一括取得 `arr[oos_start:oos_end+1, col_i]` でループ内スカラーアクセスを削減

```python
# 修正後の骨格
months_list: list = []
values_list: list = []
for row in obj_timeline.itertuples():
    champ = row.champion_pattern_id
    if champ is None or champ not in col_index:
        continue
    fold_idx = int(row.fold_idx)
    fold = folds[fold_idx]
    col_i = col_index[champ]
    oos_idx_slice = index[fold.oos_row_start : fold.oos_row_end + 1]
    oos_arr_slice = arr[fold.oos_row_start : fold.oos_row_end + 1, col_i]
    for i, month in enumerate(oos_idx_slice):
        if month not in assigned_months:
            months_list.append(month)
            values_list.append(float(oos_arr_slice[i]))
            assigned_months.add(month)
if months_list:
    combined = pd.Series(values_list, index=pd.DatetimeIndex(months_list)).sort_index()
```

**推定改善**: pd.concat削除+itertuples化で30-50%削減見込み。

## §4 実装計画

| 修正 | 対象行 | 変更規模 | 機能変更 |
|------|--------|---------|---------|
| `_compute_metric_values_for_pattern`: pd.date_range1回化 | L925-930 | 1行追加+2行変更 | なし |
| `reconstruct_alm_returns`: itertuples+list収集+1回Series構築 | L1453-1479 | 15行変更 | なし |

- 機能変更なし (出力の同一性をdiffで確認)
- テストなし (研究スクリプト、standalone)
- ロールバック: `git revert`

## §5 出力同一性確認方法

```bash
# before: ALMリターンCSVを保存
.venv/Scripts/python.exe outputs/scripts/l1_alm_wf_engine.py \
  --csv outputs/analysis/cmd1987_oikaze_DM2_grid_monthly_fast.csv \
  --subset-filter 0000_10D --skip-analysis \
  --cmd-id test_before
# -> outputs/test_before_*.csv に出力

# 実装後: after出力
.venv/Scripts/python.exe outputs/scripts/l1_alm_wf_engine.py \
  --csv outputs/analysis/cmd1987_oikaze_DM2_grid_monthly_fast.csv \
  --subset-filter 0000_10D --skip-analysis \
  --cmd-id test_after

# diff確認
diff outputs/test_before_alm_returns.csv outputs/test_after_alm_returns.csv
```
