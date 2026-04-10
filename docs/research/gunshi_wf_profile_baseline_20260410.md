# WFエンジン プロファイル計測結果(ベースライン)

## 日付
2026-04-10

## 計測環境
- bunshin CSV (6,175パターン × 151行)。mmapキャッシュ済み
- 6 workers (--parallel)
- WSL2 15GB

## フェーズ別計測結果

| フェーズ | parallel(6w) | sequential | speedup | 全体比率 |
|---------|-------------|-----------|---------|---------|
| load_data | 0.06s | 0.06s | 1.0x | <1% |
| generate_folds | 0.09s | 0.09s | 1.0x | <1% |
| run_all_folds_np | 1.3s | 2.6s | 2.0x | 7% |
| **select_champions_multi_is** | **18.1s** | **58.7s** | **3.2x** | **93%** |
| **合計** | **19.5s** | **61.4s** | **3.1x** | |

## ボトルネック: select_champions_multi_is

Phase 4が全体の93%。内部処理:
- 26 IS windows × 各窓: nhf_precomp + ltj_precomp + tail_precomp + foldループ(stats+drawdown)
- nhf_precomp: NHF_CHUNK=3000列ずつ(L, K, C) → L=72行ループ
- ltj_precomp: CHUNK=12000列ずつ(L, C) → K窓ループ
- foldループ: 各fold(67窓)で mean/std/sharpe/cagr + drawdown

## kasoku_diff推定 (944,775パターン = bunshinの153倍)

| モード | Phase 3 | Phase 4 | 合計 |
|--------|---------|---------|------|
| --parallel(6w) | 200s (3.3min) | 2764s (46min) | **49min** |
| --no-parallel | 392s (6.5min) | 8980s (150min) | **156min** |

注意: 線形スケーリング��定。**実測で大幅に外れた(下記)。**

## 実測値(cmd_1840 飛猿 --parallel 4workers)

| 忍法 | elapsed | peak RSS | 推定との乖離 |
|------|---------|----------|------------|
| kasoku_diff (944K pat) | **17m24s** | 5.3GB | 推定49min→実測17min(**2.9倍速**) |
| kasoku_ratio (944K pat) | **13m20s** | 5.3GB | 同上 |

線形スケーリング(bunshin 19.5s × 153倍 = 49min)が大幅に過大。
原因: bunshinの4,686パターンではprecomp計算のオーバーヘッドが支配的だが、
944Kパターンではnumpy vectorized演算のスループットが効いてパターン当たりコストが低下する(サブリニアスケーリング)。

## 並列効率

6 workers で 3.2x = 効率53%。理由:
- fork overhead + mmap CoW
- select_champions_multi_is内のprecomp計算(nhf/ltj/tail)はPython level → GIL影響なし(numpy)
- ただしimap(逐次dispatch)のため全workerが常にビジーではない

## 高速化余地

1. **precomp計算の列方向CHUNK最適化**: NHF_CHUNK=3000, CHUNK=12000は既にL3考慮。変更余地小
2. **IS窓間の重複計算排除**: 67窓のうち多くが同じsegment領域を共有。nhf_precompは全K窓同時処理済み
3. **--parallel-workers増加**: 6→12でさらに1.5-2x可能(WSL2 memory増加前提)
4. **Cython/numba化**: nhf_precompのL=72行ループをnumba @njitで10-50x可能(理論)
5. **foldループのvectorize化**: 67 fold × stats計算を(67, P)行列操作に変換

## プロファイルスクリプト
scripts/oneshot/wf_profile.py — 再実行可能。CSV変更でoikaze/nukimi/kasoku_diff実測も可
