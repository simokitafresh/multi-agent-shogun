# lesson_find_duplicates.sh 速度改善修行 — before計測ノート

## 対象スクリプト
`scripts/lesson_find_duplicates.sh`

## before計測（cold 3回）

| Run | real | user |
|-----|------|------|
| 1   | 16.996s | 18.640s |
| 2   | 21.854s | 20.282s |
| 3   | 18.995s | 20.876s |
| **平均** | **~19.3s** | **~19.9s** |

## データ規模
- infra lessons.yaml: 9,178行
- Active lessons: 747件（deprecated/draft: 0件）
- 比較ペア数: 278,631ペア（O(n²)）
- 類似ペア（ratio≥0.5）: **36件**

## テキスト長分布
- min=22, p25=110, median=120, p75=131, max=277
- 平均: ~122文字

## ボトルネック分析

### プロファイル（1000ランダムペア）
- YAML load: 86.9ms（全体比 ~0.5%）
- Filter: 0.1ms（無視可）
- Text prep: 0.6ms（無視可）
- 1000ペア比較: 85.4ms → 85μs/ペア
- quick_ratio pass rate: 3.1%
- ratio pass rate: ~0%（サンプル）
- **推定総時間（全ペア）: ~23.8s（実測19-22sと整合）**

### 時間支配因子
278,631ペア × SequenceMatcher（set_seq2 + quick_ratio）の繰り返し呼び出し。
- SequenceMatcher.set_seq2(): 毎呼び出しでcharacter position dict再構築 O(L)
- quick_ratio(): character frequency比較 O(unique_chars)
- 合計: O(n² × L) = O(278,631 × 240) = 67M操作

### 試みた代替手法と評価

| 手法 | 推定時間 | 問題 |
|------|----------|------|
| Word-set Jaccard | 即時 | 日本語スペース分割不可（Jaccard=0のペアが多数） |
| Char bigram filter | ~6.3s | frozenset演算コストが高い |
| Counter pre-filter | ~5.4s | Counter.items()反復は純Pythonで低速 |
| Counter+SM fallback | ~9.7s | フィルタ工程が遅い |

## 最終最適化戦略

**multiprocessing.Pool（load-balanced 8プロセス）**

- Python純粋計算なのでGIL関係なく並列化可能
- forkモード（Linux/WSL2）: グローバル変数をCopy-on-writeで共有
- 負荷均等分散（各プロセス~34,716-35,378ペア）
- Worker内でCounter pre-filter + SM.ratio()

### 実測結果
| 手法 | 時間 | 発見ペア |
|------|------|----------|
| Original sequential | ~19-22s | 36 |
| Counter+SM 4プロセス | 3.46s | 36 |
| Counter+SM 8プロセス | 3.08s | 36 |
| Fork+global 8プロセス（均等分散） | **2.25s** | 36 |

→ **~8-9x speedup** 達成

## 正確性検証
- 全3手法とも36ペアを正確に発見（元と同一）
- quick_ratioと同一公式（Counter intersection sum）を使用するため、フィルタは同等
