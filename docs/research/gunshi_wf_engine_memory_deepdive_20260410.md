# l1_alm_wf_engine.py メモリ深掘り（第3弾+第4弾なぜなぜ）
<!-- gunshi 2026-04-10 殿指示: 更なる最適化を深掘れ + コード俯瞰 -->

## 結論
全経路のメモリ消費を現物計算。kasoku_diff(94万パターン)で:
- 最適化前: **13.9GB** (PrefixMomentCache 10.2GB + 中間配列3.7GB)
- Step 1-6(PrefixMomentCache廃止): **3.71GB**
- Step 1-7(中間配列dtype): **2.39GB**
- **Step 1-9(全最適化)**: **1.85GB** ← 目標到達点

## なぜなぜ7回

| # | なぜ | 答え（コード現物確認済み） |
|---|------|--------------------------|
| 1 | なぜPrefixMomentCache廃止後もoikaze 2GB？ | select_champions_multi_isの中間配列合計1.00GB(oikaze) |
| 2 | なぜ中間配列が1GB？ | segment_cum/suffix_max_runup/positive_suffix等の(L,P)配列が全パターン分永続保持 |
| 3 | なぜ全パターン分保持？ | nhf/tail/ltj/max_runupの事前計算が全K窓×全パターンで一括実行するため |
| 4 | なぜ一括実行？ | 速度最適化。L3キャッシュ内で全K窓を処理するCHUNK設計(L1254 CHUNK=12000) |
| 5 | なぜ全パターン同時に必要？ | nhf_precomp/tail_precomp/ltj_precompが(K,P)形状→全パターンのランキングに全パターンのスコアが必要 |
| 6 | なぜ(K,P)形状で保持？ | foldループ(L1342)でfold_idx→precomp[fold_idx]で参照。全fold分を事前計算して保持 |
| 7 | **根因**: 「全K窓×全パターンを事前計算→保持」のアーキテクチャが入力パターン数Pに比例してスケールする。P=12万で設計→P=94万で7.9倍→メモリ爆発 | **対策**: パターン方向のチャンク分割（列チャンク）。全パターン同時保持を避け、チャンク毎にチャンピオン候補を計算→最終マージ |

## メモリ消費全量マップ（kasoku_diff P=944,775, L=72, K=67）

### 永続配列（関数終了まで解放されない）

| 配列 | 行 | 形状 | dtype | サイズ |
|------|-----|------|-------|--------|
| segment | L1231 | (72, 944775) | f32 | 0.27 GB |
| segment_cum | L1232 | (72, 944775) | f64 | 0.54 GB |
| suffix_max_runup | L1233 | (72, 944775) | f64 | 0.54 GB |
| positive_suffix | L1234 | (72, 944775) | f32 | 0.27 GB |
| _sc_f32 (nhf) | L1253 | (72, 944775) | f32 | 0.27 GB |
| nhf_precomp | L1254 | (67, 944775) | f64 | 0.51 GB |
| tail_precomp | L1282 | (67, 944775) | f32 | 0.25 GB |
| ltj_precomp | L1301 | (67, 944775) | f64 | 0.51 GB |
| **永続合計** | | | | **3.16 GB** |

### 一時配列（foldループ毎に解放）

| 配列 | 行 | 形状 | dtype | サイズ |
|------|-----|------|-------|--------|
| _win_f64 | L1348 | (36, 944775) | f64 | 0.27 GB |
| fold_cum | L1370 | (~36, 944775) | f64 | 0.27 GB |
| **一時最大** | | | | **0.54 GB** |

### ピーク: 永続3.16GB + 一時0.54GB + その他0.56GB = **4.26 GB**

## 削減候補（実現可能性順）

### 候補1: segment_cumのfloat32化（-0.27GB、1行変更）
L1232: `np.cumprod(1.0 + segment, axis=0)` → `np.cumprod(np.float32(1.0) + segment, axis=0)`
- suffix_max_runup/drawdown計算の精度がfloat32で許容可能か要検証
- nhf計算(L1253)は既にfloat32でcumprod→一貫性あり
- 期待削減: 0.54→0.27 GB

### 候補2: suffix_max_runupのfloat32化（-0.27GB、L941-942変更）
L941: `np.zeros_like(segment_cum, dtype=np.float64)` → `dtype=np.float32`
- max_runupはランキング(相対比較)で使う→float32精度で十分
- 期待削減: 0.54→0.27 GB

### 候補3: nhf_precomp/ltj_precompのfloat32化（-0.51GB、2行変更）
L1254: `dtype=np.float64` → `np.float32`
L1301: `dtype=np.float64` → `np.float32`
- nhfは0-1のカウント比率、ltjは逆数→float32精度で十分
- 期待削減: 1.02→0.51 GB

### 候補4: 列チャンク分割（最大削減だが大改修）
全Pパターンを一度に処理せず、CHUNK=50000列ずつ処理。
各チャンクで全K窓のスコアを計算→チャンク間で最良候補をマージ。
- これにより永続配列が(L, CHUNK)サイズに→3.16GB → ~0.17GB
- ただしfoldループ×チャンクループの二重ループになり、コード変更大
- 元のCHUNK=12000設計(L1254)と同じ発想を外側に拡張

### 候補5: _sc_f32の廃止（-0.27GB）
L1253: `_sc_f32 = np.cumprod(np.float32(1.0) + segment, axis=0)`
- segment_cumと同じ計算をfloat32でやっている（nhf用）
- segment_cumをfloat32化(候補1)すれば_sc_f32は不要になる

### 候補6(Step 8): foldループ_win_f64のfloat32化（-0.27GB）
L1348: `_win_f64 = arr[_start:_end + 1].astype(np.float64)` → `.astype(np.float32)`
- mean/std計算はfloat32精度で相対ランキングに十分
- ただし**L1355 np.log1pの精度**に注意(float32 log1pの丸め誤差)
- fold_cum(L1370 drawdown用)もfloat32化可能

### 候補7(Step 9): segment_cum float32化によるsuffix/sc_f32統廃合
- segment_cum f32化(候補1) → suffix_max_runup f32(候補2自動達成) → _sc_f32廃止(候補5自動達成)
- 3配列が2配列に統合: segment_cum(f32) + suffix_max_runup(f32) = 0.54GB (元: 0.54+0.54+0.27=1.35GB)

## 全経路メモリ消費マップ（kasoku_diff P=944,775, L_full=150, L_seg=72, K=67）

| 経路 | 配列群 | 最適化前 | Step1-6後 | Step1-7後 | Step1-9後 |
|------|--------|---------|-----------|-----------|-----------|
| 経路2: PrefixMomentCache | metric_arr(f64) + 9配列 | 10.20 GB | **0 GB(廃止)** | 0 | 0 |
| 経路3: multi_is中間配列 | segment系 + precomp | 3.17 GB | 3.17 GB | **1.85 GB(f32)** | **1.58 GB(統廃合)** |
| 経路4: foldループ | _win_f64 + fold_cum | 0.54 GB | 0.54 GB | 0.54 GB | **0.27 GB(f32)** |
| **合計** | | **13.91 GB** | **3.71 GB** | **2.39 GB** | **1.85 GB** |

## 第4弾なぜなぜ7回（コード俯瞰）

| # | なぜ | 答え（コード現物確認） |
|---|------|----------------------|
| 1 | なぜStep1-7でもkasoku_diff 2.39GBか？ | 経路3(multi_is中間配列)1.85GB + 経路4(foldループ)0.54GB |
| 2 | なぜ経路3が1.85GBも消費？ | segment_cum(f32 0.27)+suffix_max_runup(f32 0.27)+precomp 3種(f32 0.76)+positive_suffix(0.27)+segment(0.27) |
| 3 | なぜsegment_cumとsuffix_max_runupが両方必要？ | max_runupメトリクスに使う。suffix_max_runupはsegment_cumから構築(L1233 _build_suffix_max_runup) |
| 4 | なぜ全K窓分のprecomp(K,P)を保持？ | foldループ(L1342)でfold_idx参照。nhf/tail/ltjは事前計算しないと各foldで再計算→速度低下 |
| 5 | なぜ経路4の_win_f64がfloat64？ | L1348 mean/std/cagr計算の精度。しかしチャンピオン選出は相対ランキング→float32で十分 |
| 6 | なぜ_sc_f32がsegment_cumと別に存在？ | nhf計算がfloat32 cumprodを要求(L1253)。segment_cumはfloat64だった(drawdown精度)→f32を別途生成。segment_cumをf32化すれば不要 |
| 7 | **根因**: float64がデフォルトの設計思想(精度優先)。パターン数P=12万で安全マージン内だったため、dtype最適化の必要がなかった。P=94万で全配列がP比例でスケール→メモリ爆発。**対策**: チャンピオン選出(相対ランキング)にはfloat32精度で十分。全中間配列のfloat32統一+重複配列の統廃合で1.85GBに削減 |

## 追加最適化の道（列チャンク分割 — 将来用）

上記Step1-9で1.85GB(kasoku_diff)。15GB環境で安全圏。
しかしuniverse体数がさらに増えた場合(例: 40体→P=750万)、1.85GBの10倍=18.5GBで再びOOM。

列チャンク分割(候補4)はその時の手段:
- 全Pパターンを50000列ずつ処理
- 各チャンクで全K窓スコア→チャンク間でbest候補マージ
- メモリはチャンクサイズに比例→Pに依存しない
- ただし大改修(30+行)。現時点ではROI不足

## 推奨: 候補1+2+3+5で即時-1.32GB

kasoku_diff: 4.26GB → **2.94GB**（+claude 3GB = 5.94GB/15GB）
oikaze: 1.00GB → **0.69GB**（AC3 < 1GB達成）

コード変更: 5行のdtype変更のみ。ロジック変更なし。リスク最小。
binary_check: bunshinで回帰テスト(allclose rtol=1e-4)。

候補4(列チャンク)はkasoku系で必要になった場合の次の手。現時点ではdtype最適化で十分。
