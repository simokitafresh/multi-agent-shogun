# l1_alm_wf_engine.py メモリ削減設計書
<!-- gunshi 設計 2026-04-10 -->
<!-- cmd_1826偵察→将軍設計依頼→cmd_1827(Step1-7)→cmd_1828(Step8-10) -->
<!-- 関連: gunshi_wf_engine_memory_deepdive_20260410.md (全量マップ+第3-4弾なぜなぜ) -->
<!-- 関連: gunshi_research_pipeline_meta_20260410.md (メタ視点: GS律速+4改善) -->

## 結論(v4)

| cmd | 対象 | kasoku_diff peak | 状態 |
|-----|------|-----------------|------|
| cmd_1827 | Step1-7: PrefixMomentCache廃止+中間配列f32 | **3.68GB**(実測) | ✅完了 |
| cmd_1828 | Step8-10: foldループf32+segment_cum統一+drawdown追従 | **2.66GB**(推定) | FAIL(Step9/10がcmd_1827で先取り。tracemalloc≠RSS設計穴) |

メタ視点: GS全体150min→**1.9min(79x)**。BATCH_CHUNK(30x)+横展開(14x)+gs_runner並列(12x)。新ボトルネック=CSV I/O(258s=91%)→savetxt 59x確認済み。→ `gunshi_research_pipeline_meta_20260410.md`

## なぜ今回OOMで以前は問題なかったか（なぜなぜ7回 第2弾）

| # | なぜ | 答え |
|---|------|------|
| 1 | なぜ今回OOMで以前は動いた？ | GS入力のuniverse構成体数が違う。前回12体→今回20体 |
| 2 | なぜ体数が増えるとOOMになる？ | GSパターン数がuniverse体数の組合せに依存。12体→20体でパターン数が**7.9倍**に膨張 |
| 3 | なぜ7.9倍？ | GS内部でtop_n×rolling_window×体数の組合せを生成。体数が1.67倍(20/12)だが組合せ爆発で7.9倍 |
| 4 | なぜCSVサイズが5.5倍に？ | パターン数7.9倍×月数減(171→150ヶ月)。kasoku_diff: 119,493→944,775パターン、328MB→1.8GB |
| 5 | なぜメモリが爆発？ | PrefixMomentCacheが全パターン分float64×9配列を一括構築。944,775×150×8byte×9=**10.2GB** |
| 6 | なぜ前回は問題なかった？ | 前回: 119,493×171×8byte×9=**1.47GB**。15GB環境で収まった。今回は10.2GBで超過 |
| 7 | **根因**: エンジンのメモリ消費がO(パターン数)でスケールし、パターン数がuniverse体数の組合せ爆発で増大する。前回は偶然収まっただけ | **対策**: fold毎構築+float32でO(IS窓パターン数)に削減済み(設計書本文) |

### データ比較表

| 忍法 | 前回パターン数(12体) | 今回パターン数(20体) | 倍率 | 前回CSV | 今回CSV | CSV倍率 |
|------|---------------------|---------------------|------|---------|---------|---------|
| kasoku_diff | 119,493 | 944,775 | 7.9x | 328MB | 1.8GB | 5.5x |
| kasoku_ratio | 119,493 | 944,775 | 7.9x | 332MB | 1.8GB | 5.4x |
| kawarimi | 28,116 | 222,300 | 7.9x | 86MB | 503MB | 5.8x |
| oikaze | 28,116 | 222,300 | 7.9x | 83MB | 468MB | 5.6x |
| nukimi | 60,918 | 481,650(推定) | 7.9x | 167MB | 941MB | 5.6x |
| yotsume | 4,686 | 37,050(推定) | 7.9x | 14MB | 79MB | 5.6x |

### メモリ見積り(PrefixMomentCache全データ一括float64×9)

- 前回kasoku_diff: 119,493 × 171 × 8byte × 9 = **1.47GB** → 15GB環境で収まった
- 今回kasoku_diff: 944,775 × 150 × 8byte × 9 = **10.2GB** → OOM確定
- 今回oikaze: 222,300 × 150 × 8byte × 9 = **2.4GB** → claude群常駐と合計で圧迫→OOM

### 教訓
エンジンがO(N)メモリのとき、入力Nの変動幅を見積もれ。前回動いた≠常に動く。universe体数の変更でNが7.9倍になるスケーリング特性を把握し、最大入力でのメモリ検証をACに含めよ。

## なぜなぜ7回（設計の穴）

| # | なぜ | 答え |
|---|------|------|
| 1 | なぜOOMが起きた？ | PrefixMomentCache.buildが全データ分float64×9配列を一括生成(1247MB) |
| 2 | なぜ全データ分を一括生成する？ | window_stats(start,end)でO(1)参照するためにprefix sumを事前計算 |
| 3 | なぜfold毎に構築しなかった？ | 速度最適化(build 1回 vs 30回)。だが94万パターンのメモリ量を想定外 |
| 4 | なぜ94万パターンを想定していなかった？ | cmd_wf_speedup時のテストはシン四神12体(小規模)。シン忍法20体は後続cmdで初使用 |
| 5 | なぜ大規模テストをしなかった？ | cmd_wf_speedupのACに「最大規模CSVでのメモリ検証」がなかった |
| 6 | なぜACにメモリ検証がない？ | 道具磨きcmdの品質ゲートにリソース特性(メモリ/CPU/ディスク)の検証が構造的に含まれていない |
| 7 | **根因**: 道具磨きcmdのACテンプレートにリソース検証ACが不在 | **対策**: cmd_save.shまたはdraft reviewで「道具磨きcmdにpeak RSS検証ACがあるか」をチェック |

## 現状の問題
- L2092: `metric_arr = np.asarray(arr, dtype=np.float64)` — 全データをfloat64化(+234MB)
- L2094: `prefix_cache = PrefixMomentCache.build(metric_arr)` — 全データ分float64×7+int32×2=1247MB一括生成
- peak RSS = 2010MB (baseline 82MB, 24.7倍)
- 468MB CSV(oikaze, 222300パターン)ですら13GBでOOM。kasoku系(1.8GB)は論外

## PrefixMomentCacheの使われ方

2つの呼出し元:
1. **L2094(main)**: 全データ分prefix_cacheを事前構築→各fold計算で`window_stats(start, end)`
2. **L795(fallback)**: prefix_cacheなし時にスライスから一時構築

main経路(L2094)が問題。ただし**単純にfold毎構築に変えるだけでは動かない経路がある**。

## 依存関係マップ（prefix_cache全参照箇所）

prefix_cacheを参照する全箇所とfold毎構築への影響:

| # | 箇所 | 行 | 参照方法 | fold毎構築で動くか | 並列影響 |
|---|------|----|----------|-------------------|---------|
| A | main事前構築 | L2094 | build(全データ) | **廃止対象** | — |
| B | AC3 fold[0]検証 | L2195 | window_stats(fold0) | OK。fold0分だけbuildすれば動く | なし |
| C | --validate検証 | L2110,2118 | validate_prefix_window_metrics | OK。fold毎buildで動く | なし |
| D | run_all_folds_np | L2246 | compute_metrics_np→fallback | OK。既にfold毎build(L795) | Pool並列: 各workerが独立buildで安全 |
| E | run_multi_is_selection | L2282-2288 | prefix_cache引数で渡す | **要注意**。下記参照 | Pool fork: prefix_cacheを全workerが共有(L1105) |
| F | select_champions_multi_is内 foldループ | L1335-1344 | prefix_cache.cumsum[_end]直接参照 | **NG。全データ分cacheが必要** | — |
| G | ltj_precomp計算 | L1309-1313 | prefix_cache.cumsum[_e], cumsq[_e] | **NG。全データ分cacheが必要** | — |

### 致命的依存: F + G（select_champions_multi_is）

L1309-1313 (ltj_precomp):
```python
_s1c = prefix_cache.cumsum[_e, _p0:_p1].copy()
_s2c = prefix_cache.cumsq[_e, _p0:_p1].copy()
if _s > 0:
    _s1c -= prefix_cache.cumsum[_s - 1, _p0:_p1]
    _s2c -= prefix_cache.cumsq[_s - 1, _p0:_p1]
```

L1335-1344 (foldループ内stats):
```python
_s1 = prefix_cache.cumsum[_end].copy()
_s2 = prefix_cache.cumsq[_end].copy()
_logt = prefix_cache.cumlog1p[_end].copy()
```

これらは**全データ分のprefix_cache配列に対してfold毎のstart/endでスライス**している。fold毎buildでは`_end`が全データ範囲のインデックスだが、fold毎cacheはIS窓サイズしかない→**IndexError**。

### 並列実行影響

| 並列モード | 影響 |
|------------|------|
| --parallel (Pool fork) run_all_folds_np | **影響なし**。各workerがcompute_metrics_np(prefix_cache不使用のフル版)を独立実行 |
| --parallel run_multi_is_selection | **影響大**。L1105: `initargs=(arr, prefix_cache, columns_arr)`でfork時に全workerが全データ分prefix_cacheを共有。fold毎構築に変更すると、各workerがbuildする必要がある→forkのメモリ共有が効かなくなる |
| --batch-csvs | **影響なし**。各CSV独立でmain()を呼ぶ |

## 設計(修正版): 2段階アプローチ

### 段階1: cumsum/cumsqのみ全データ分構築（他7配列廃止）

F+Gが依存するのは`cumsum`と`cumsq`（と`cumlog1p`）の**3配列のみ**。
残りの`cum3`, `cum4`, `cumneg_sq`, `cumpos_sum`, `cumpos_count`, `cumneg_count`の**6配列はF+Gで不使用**。

```python
# L2092-2094 変更後:
# 全データ分はcumsum/cumsq/cumlog1pの3配列のみ構築(float32)
arr_f32 = np.asarray(arr, dtype=np.float32)
np.nan_to_num(arr_f32, copy=False)
light_cumsum = np.cumsum(arr_f32, axis=0)        # 94万×171×4byte = 644MB
light_cumsq = np.cumsum(arr_f32**2, axis=0)      # 644MB
light_cumlog1p = np.cumsum(np.log1p(arr_f32), axis=0)  # 644MB
# peak: 644×3 = 1.93GB (現在1247MBより多いが、arr_f32の明示解放後は644×3のみ)
del arr_f32  # 一時f32コピーを解放
```

→ これでも**1.93GB**。kasoku系ではまだ多い。

### 段階2: 最終案 — F+Gをcumsum不使用に書き換え

根本解決: L1309-1313/L1335-1344がprefix_cacheを直接参照する理由は「O(1)でwindow sum/sqを取得するため」。これをfold毎のslice.sum()に置換すれば全データ分cacheが不要になる。

```python
# L1309-1313 変更後:
_win = arr_f32[_s:_e+1, _p0:_p1]  # fold窓スライス
_s1c = _win.sum(axis=0)
_s2c = (_win**2).sum(axis=0)
```

```python
# L1335-1344 変更後:
_win = arr_f32[_start:_end+1]
_s1 = _win.sum(axis=0)
_s2 = (_win**2).sum(axis=0)
_logt = np.log1p(_win).sum(axis=0)
```

速度影響: IS窓36ヶ月×94万パターンのsum()はO(36P)。cumsum参照はO(1)→O(2)。差は36×94万=3400万FLOP/fold。30fold×K候補窓で**数秒増加**。許容範囲。

これにより**全データ分prefix_cacheが完全に不要**になり、fold毎構築のみで動く。

### メモリ見積り(最終案・kasoku_diff 1.8GB)
- arr(mmap float32): 0MB
- fold毎f32スライス(94万×36×4byte): 129MB
- fold毎cache(6配列×129MB): **774MB** ← peak ~1.2GB
- segment_cum等の中間配列: ~200MB
- 合計: **~1.4GB** + claude群3GB = 4.4GB/15GB → 十分余裕

### 変更ファイル・行番号一覧

| ファイル | 行 | 変更内容 | 理由 |
|----------|-----|----------|------|
| l1_alm_wf_engine.py | L204 | `dtype=np.float64` → 入力dtype保持 | float32対応 |
| 同上 | L2092-2094 | 全データ分build削除 | OOM根因除去 |
| 同上 | L2195 | fold0分のみbuild | AC3検証 |
| 同上 | L2110,2118 | fold毎build | --validate |
| 同上 | L1309-1313 | cumsum参照→slice.sum() | 全データcache依存除去 |
| 同上 | L1335-1344 | cumsum/cumsq/cumlog1p参照→slice直接計算 | 同上 |
| 同上 | L1010-1013 | _init_multi_is_worker: prefix_cache引数廃止 | 不要化 |
| 同上 | L1048 | prefix_cache=_FOLD_WORKER_PREFIX廃止 | 同上 |
| 同上 | L1059,1077,1092,1105 | prefix_cache引数除去 | 同上 |
| 同上 | L2282-2288 | prefix_cache引数除去 | 同上 |

### 波及先(変更不要だが確認必須)

| 箇所 | 行 | 理由 |
|------|-----|------|
| compute_metrics_np_window fallback | L793-795 | 既にsliceからbuild。変更不要 |
| _compute_metrics_np_window_fast | L820-859 | prefix_cache引数→fold毎cacheに差し替わるが内部ロジック不変 |
| run_batch_mode | L2066-2067 | 各CSV独立でmain()呼出し。内部変更に自動追従 |
| nhf_precomp | L1246-1278 | segment_cumベース。prefix_cache不使用。変更不要 |
| tail_precomp | L1280-1295 | segment/positive_suffixベース。prefix_cache不使用。変更不要 |

## なぜなぜ（将軍指示の穴塞ぎ）

将軍指示: 「kasoku_diff/kasoku_ratio(94万パターン, 468MB CSV)が8GB環境でOOMしない」

| # | 穴 | 修正 |
|---|---|---|
| 1 | 「468MB」はoikaze。kasoku系は各**1.8GB** | 目標CSVサイズ=1.8GB |
| 2 | 「8GB環境」の根拠不明。free実測=15GB total | 目標=15GB total環境(claude群常駐含む)でOOMしない |
| 3 | fold毎f64でもkasoku系94万パターン×36ヶ月×9配列=2.3GB | float32 cacheで1.15GBに |
| 4 | CSV初回読込みのpandas read_csvピーク(~3.6GB)が考慮外 | 2回目以降mmapなので初回のみ。AC設計に注記 |

### kasoku_diff(1.8GB, 94万パターン×171ヶ月)のメモリ見積り

**fold毎f64(元の案3):**
- arr(mmap float32): 0MB
- fold毎f64スライス(94万×36×8byte): 257MB
- fold毎cache(9配列×257MB相当): **約2.3GB** ← peak 2.8GB
- claude群常駐: ~3GB → 合計5.8GB/15GB → 通るが余裕少ない

**fold毎float32(案1+案3ハイブリッド・推奨):**
- arr(mmap float32): 0MB
- fold毎f32スライス(94万×36×4byte): 129MB
- fold毎cache(9配列×129MB相当): **約1.15GB** ← peak 1.6GB
- claude群常駐: ~3GB → 合計4.6GB/15GB → 十分余裕あり

### 結論修正
**fold毎float32 cache(案1+案3ハイブリッド)を推奨に変更。**
桁落ちリスクはチャンピオン選出(相対ランキング)で許容。binary_checkでfloat64版との差 < 1e-4を検証。

## 目標(修正版 v3)
kasoku_diff/kasoku_ratio(94万パターン, **1.8GB** CSV)が**15GB total**(claude群常駐含む)環境でOOMしないこと。

| CSV | Step 1-6のみ | Step 1-7(推奨) |
|-----|-------------|---------------|
| oikaze (468MB, 222k) | ~1.0GB | **~0.69GB** (AC3 < 1GB達成) |
| kasoku_diff (1.8GB, 944k) | ~4.26GB | **~2.94GB** (安全圏) |

## ランブック（忍者向け実装手順）

### §1 前提確認
- 対象: `outputs/scripts/l1_alm_wf_engine.py`
- 入力: GS月次CSV (mmap float32キャッシュ)
- 変更範囲: L2092-2094(main), select_champions内foldループ, --validateモード
- arrはmmap_mode="r"で読込済み(load_data L1552)。float32。メモリ消費0

### §2 実装手順（依存順序厳守）

**Step 1: PrefixMomentCache.buildのdtype対応(L204)**
```python
# L204変更前: arr64 = np.asarray(arr, dtype=np.float64)
# L204変更後: arr_f = np.asarray(arr)  # 入力dtypeを保持
# L205-216: arr64→arr_fに一括置換
```
これが先。後続Step全てがfloat32 buildに依存。

**Step 2: select_champions_multi_is内のcumsum直接参照を除去(L1309-1313, L1335-1344)**
```python
# L1309-1313 変更後(ltj_precomp):
_win = arr[_s:_e+1, _p0:_p1]  # arrはfloat32 mmap
_s1c = _win.sum(axis=0).astype(np.float64)
_s2c = (_win.astype(np.float64)**2).sum(axis=0)

# L1335-1344 変更後(foldループ stats):
_win = arr[_start:_end+1]
_s1 = _win.sum(axis=0).astype(np.float64)
_s2 = (_win.astype(np.float64)**2).sum(axis=0)
_logt = np.log1p(_win.astype(np.float64)).sum(axis=0)
```
注意: mean/std計算はfloat64精度必要→sum時のみfloat64変換(全データ分ではなくfold窓分のみ)

**Step 3: prefix_cache引数の削除(関数シグネチャ変更)**
以下の全箇所からprefix_cache引数を除去:
- `select_champions_multi_is()` L1194
- `run_multi_is_selection()` L1059
- `_init_multi_is_worker()` L1010 (グローバル`_FOLD_WORKER_PREFIX`廃止)
- `_select_multi_is_fold_worker()` L1048
- Pool initargs L1105
- main() L2282-2288の呼出し

**Step 4: L2092-2094の全データ分build廃止**
```python
# 削除:
# metric_arr = np.asarray(arr, dtype=np.float64)
# np.nan_to_num(metric_arr, copy=False)
# prefix_cache = PrefixMomentCache.build(metric_arr)

# arrをnan_to_numしてからfold毎に渡す:
arr_clean = np.array(arr, dtype=np.float32)
np.nan_to_num(arr_clean, copy=False)
```

**Step 5: AC3検証(L2195)とvalidateモード(L2110,2118)をfold毎buildに変更**
```python
# L2195変更後:
fold0_slice = arr_clean[fold0.is_row_start:fold0.is_row_end + 1]
fold0_cache = PrefixMomentCache.build(fold0_slice)
metrics0_np = _compute_metrics_np_window_fast(
    fold0_slice, 0, len(fold0_slice)-1, fold0_cache, ...
)
del fold0_cache
```

**Step 6: compute_metrics_np_windowの呼出しをfold毎buildに変更(mainフロー全般)**

**Step 7: select_champions_multi_is中間配列のfloat32化（第2層最適化 -1.32GB）**

第3弾なぜなぜで発見。PrefixMomentCache廃止後もoikaze 2GBの原因。
詳細: `docs/research/gunshi_wf_engine_memory_deepdive_20260410.md`

```python
# L1232: segment_cum float64→float32
segment_cum = np.cumprod(np.float32(1.0) + segment, axis=0)  # was: 1.0 + segment → float64

# L941-942: suffix_max_runup float64→float32
suffix_runup = np.zeros_like(segment_cum, dtype=np.float32)  # was: np.float64
future_max = segment_cum[-1].astype(np.float32, copy=True)   # was: np.float64

# L1254: nhf_precomp float64→float32
nhf_precomp = np.zeros((_K, _P), dtype=np.float32)  # was: np.float64

# L1301: ltj_precomp float64→float32
ltj_precomp = np.zeros((_K, _P), dtype=np.float32)  # was: np.float64

# L1253: _sc_f32廃止（segment_cumがfloat32になるため不要）
# 削除: _sc_f32 = np.cumprod(np.float32(1.0) + segment, axis=0)
# nhf計算でsegment_cumを直接使用
```

**Step 8: foldループ_win_f64のfloat32化（-0.27GB）**
```python
# L1348変更前: _win_f64 = arr[_start:_end + 1].astype(np.float64)
# L1348変更後: _win_f32 = arr[_start:_end + 1].copy()  # float32のまま
# L1349-1355: _win_f64→_win_f32に置換。sum/log1pの精度はfloat32で相対ランキングに十分
# L1370のfold_cumもfloat32化: segment_cum[offset:fold_end_offset+1]（segment_cumがf32なら自動）
```

**Step 9: segment_cum float32化による統廃合（-0.27GB）**
```python
# L1232変更: segment_cum = np.cumprod(np.float32(1.0) + segment, axis=0)  # float32に統一
# これにより_sc_f32(L1253)と同一→_sc_f32廃止。suffix_max_runup(L941)もfloat32自動追従
# nhf計算(L1260)のsegment_cumとnhf用_sc_f32が統一される
```

**Step 10: _compute_drawdown_path_metrics内部配列のfloat32化（-0.68GB）**

ギャップ分析で発見（第4弾）。L583-612の隠れ配列:
```python
# _compute_drawdown_path_metrics をfloat32 cumulative入力対応に変更
# L587: running_peak → float32のまま(入力がf32なら自動)
# L589: drawdowns → float32(cumulative/running_peak)
# L595: masked_cumulative → float32(np.where)
# 入力fold_cumがfloat32なら全内部配列が自動的にfloat32
```
- 現在: fold_cum=f64→drawdown内部全てf64→0.92GB/fold
- 変更: fold_cum=f32→drawdown内部全てf32→0.46GB/fold
- ただしStep 9(segment_cum f32)が前提。segment_cumがf32ならfold_cumもf32

メモリ効果(kasoku_diff):
- Step 1-7(実測): 3.68GB
- Step 1-9: 2.93GB(推定)
- Step 1-10: **2.66GB**(推定) ← 究極到達点

完全メモリマップ(kasoku_diff P=944,775):

| 分類 | Step1-7実測 | Step1-10推定 |
|------|-----------|-------------|
| 永続配列(7種) | 1.85 GB | 1.85 GB |
| fold一時(win+cum+drawdown) | 1.46 GB | 0.51 GB |
| overhead | 0.37 GB | 0.30 GB |
| **合計** | **3.68 GB** | **2.66 GB** |
```

### §3 検証(binary_check) — cmd_1827+cmd_1828統合

**cmd_1827実測(Step1-7):**
| CSV | peak RSS | AC目標 | 結果 |
|-----|----------|--------|------|
| bunshin(16MB) | - | md5完全一致 | ✅PASS |
| oikaze(468MB) | **929MB** | < 1GB | ✅PASS |
| kasoku_diff(1.8GB) | **3.68GB** | < 4GB, OOMなし | ✅PASS |
| float64差 | 3.55e-15 | < 1e-4 | ✅PASS |

**cmd_1828目標(Step8-10):**
1. bunshin(16MB): allclose(rtol=1e-4) ← float32深化のため完全一致→allclose
2. oikaze(468MB): **peak RSS < 700MB**
3. kasoku_diff(1.8GB): **peak RSS < 3GB**

### §4 禁則
- `np.float64`への**全データ変換**を行うな（OOMの根因）。fold窓分のみfloat64変換は可
- `del`でfold毎オブジェクトを明示解放せよ
- `prefix_cache`を関数の引数として受け渡すな（廃止済み。各関数内でfold毎build）
- `--batch-csvs`モードのrun_batch_mode()は変更不要（各CSV独立でmain()を呼ぶ構造）
- CSV初回読込み(pandas read_csv)は避けられない一時ピーク。2回目以降はmmapキャッシュで回避
- L1309-1313/L1335-1344のsum計算はfloat64精度が必要。`.astype(np.float64)`をsum前に適用(fold窓サイズなのでメモリ影響軽微)
- **`--parallel`は全CSVで使用可能（mmapキャッシュ存在時）**:
  - mmapキャッシュ(.cache.arr.npy)が存在すれば、parent RSS≈0。workers×fold_data(~900MB/worker×4=3.5GB)で15GB環境に余裕あり
  - **キャッシュ不在時のみ`--no-parallel`が必要**（pd.read_csv 48倍膨張のリスク）
  - ~~旧指針: CSV>500MB→--no-parallel~~ **撤回(2026-04-10)**。半蔵OOM Killの真因はpd.read_csvキャッシュ不在であり、--parallel fold計算ではなかった。キャッシュ生成後は--parallelが安全かつ4-6倍速
  - ※ 軍師が根因を正しく特定しながらランブックに誤った制約(--no-parallel必須)を残した。根因→対策の一貫性検証を怠った

### §5 実行時の注意（AC3/AC4）

**実行コマンド例（正しい）:**
```bash
cd /mnt/c/Python_app/DM-signal
python3 outputs/scripts/l1_alm_wf_engine.py \
  --csv outputs/grid_search/okugi_shin_ninpo_20body/cmd_1822_okugi_shin_ninpo_20body_oikaze_grid_monthly_20260409.csv \
  --multi-is --cmd-id cmd_XXXX --progress \
  --out-dir outputs/analysis/alm_research/cmd_XXXX_oikaze
```
- `--parallel`はデフォルトON。**小CSV(≤500MB)はそのまま。大CSV(>500MB)は`--no-parallel`を付けよ**
- peak RSS計測: `/usr/bin/time -v` で包む
- `--skip-analysis`はselection_timeline+alm_returnsのみ出力（中間省略）。速度優先時に使用

**実行順序（小→大、メモリ段階確認）:**
1. bunshin (16MB) — 回帰テスト+動作確認
2. yotsume (79MB)
3. oikaze (468MB) — peak RSS < 1GB確認
4. kawarimi (503MB)
5. nukimi (941MB)
6. kasoku_diff (1.8GB) — **`--no-parallel`必須**。peak RSS < 4GB確認。**初回はmmapキャッシュ未生成→pandas read_csvピーク~3.6GB**。`free -h`でavailable > 6GB確認してから実行
7. kasoku_ratio (1.8GB) — 同上。**`--no-parallel`必須**

**速度目安(cmd_1827実測基準):**
- bunshin(--parallel): ~3秒
- oikaze(--parallel): ~3-5分。peak 929MB(Step1-7)→700MB目標(Step8-10)
- kasoku_diff(**--no-parallel**): ~30-60分。peak 3.68GB(Step1-7)→2.66GB目標(Step8-10)
- kasoku_ratio(**--no-parallel**): 同上
- **★GS実行(150分)がパイプライン全体の96%。WFの速度改善効果は全体の0.3%** → `gunshi_research_pipeline_meta_20260410.md`

**メタ視点の道具磨き到達点(2026-04-10):**
1. ~~cmd_1828(Step8-10)~~: FAIL(no-op。Step9/10がcmd_1827で先取り済み)
2. ~~GS並列ランナー(cmd_1831)~~: ✅CLEAR。22.7min→1.9min(12x)
3. ~~BATCH_CHUNK横展開(cmd_1830)~~: ✅CLEAR。kasoku_diff計算14x
4. ~~lazy import(cmd_1832)~~: ✅CLEAR。RSS 79.6MB削減
5. ~~CSV I/O偵察(cmd_1834)~~: ✅CLEAR。pandas270s→savetxt4.6s(59x)確認
6. ~~gs-bench-gate(cmd_1833)~~: ✅CLEAR。GSコード変更時WARN自動化
7. **次**: CSV I/O savetxt実装(未起票) → GS共通基盤抽出(未起票)
