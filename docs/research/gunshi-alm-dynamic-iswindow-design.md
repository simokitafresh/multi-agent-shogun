# ALM IS窓動的化 + Pure Function化 設計書

**作成**: 軍師 2026-04-07（v3: IS窓全探索。パラメータ空間縮小禁止原則準拠）
**依頼元**: 将軍（殿発案）
**対象**: l1_alm_wf_engine.py + 本番recalculate_fast.py + return_calculator.py
**絶対条件**: 固定IS窓版(300秒(5分)/7忍法)より遅くなることは禁止

---

## Chapter A: Pure Function化 — 研究と本番の計算パス統一

（v2から変更なし）

### A1. 現状の問題

`calculate_monthly_return(db, portfolio_id, year, month, ...)` はDB Session依存。
研究エンジンはGS CSVから直接読む → 計算パス不一致 = パリティ検証のボトルネック。

### A2. Pure Function設計

```python
def calculate_monthly_return_pure(
    holding_signal: str,           # "AAPL,MSFT" or "Cash"
    prices: dict[str, pd.Series],  # {ticker: Series(date→price)}
    year: int, month: int,
    price_type: str = "open",
    business_days: list[date] = None,
) -> float:
    """DB I/Oゼロ。trade-rule.md RULE05準拠。"""
```

既存OPT-3(business_days pure版) + PriceCacheの延長線上。

### A3. 移行戦略

1. `return_calculator_pure.py` 新規作成
2. 既存関数の内部をpure関数呼び出しにリファクタ
3. 研究エンジンがpure関数を直接呼ぶ → 計算パス統一
4. パリティテスト: pure版 vs DB版 完全一致

---

## Chapter B: IS窓全探索設計（パラメータ空間縮小禁止）

### B1. 探索空間

IS窓: **6M〜72Mの1ヶ月刻み = 67点**。恣意的な5段階選定は空間縮小禁止原則に違反。

### B2. 全探索の計算量

| 項目 | 現行(固定IS=36) | 全探索(67 IS窓) | 倍率 |
|------|----------------|-----------------|------|
| IS窓数 | 1 | 67 | 67x |
| 合計fold数 | 30 | **1,968** | **65.6x** |
| 加重計算量 Σ(fold×IS月) | 1,080 | **70,479** | **65.3x** |

IS窓別fold数（抜粋）:
| IS窓 | fold数 | IS窓 | fold数 |
|------|--------|------|--------|
| 6M | 38 | 42M | 28 |
| 12M | 36 | 48M | 27 |
| 18M | 34 | 54M | 25 |
| 24M | 33 | 60M | 24 |
| 30M | 31 | 66M | 22 |
| 36M | 30(現行) | 72M | 21 |

### B3. データ構造

```python
@dataclass
class WFChampion:
    fold_idx: int
    objective: str
    pattern_id: str
    is_window_months: int  # どのIS窓で選出されたか
```

### B4. 本番AlmConfig拡張

```python
class AlmConfig(BaseModel):
    candidate_is_windows: List[int] = list(range(6, 73))  # 全探索デフォルト
    # is_window_months: 廃止 → candidate_is_windowsに統合
```

---

## Chapter C: 速度保証 — 65倍の計算量を31秒以内に収める

### C1. 素朴実装は絶対不合格

素朴推定: 300秒(5分) × 65.3 = **~2,030秒(33分)** → ❌

Pool並列だけでは不足:
- Pool(6): 1968÷6 = 328バッチ → ~344秒/忍者 → ❌
- Pool(20): 1968÷20 = 98バッチ → ~103秒/忍者 → ❌
- Pool(∞): CPU時間 = 2,030秒。コア数に関わらず限界あり

**根本的に計算アルゴリズムを変える必要がある。**

### C2. 核心アイデア: Prefix-Sum メトリクス（O(1) per IS窓）

現行: 各IS窓で`compute_metrics_np(is_arr)`を個別呼び出し → O(IS月数 × パターン数) per IS窓
改善: **cumulative sum/prefix sumで前計算し、任意IS窓のメトリクスをO(1)スライスで取得**

```python
# 前計算（1回だけ。O(total_months × patterns)）
cumsum = np.cumsum(returns, axis=0)           # shape: (166, 119493)
cumsq  = np.cumsum(returns ** 2, axis=0)      # shape: (166, 119493)

# 任意IS窓の mean/var を O(1) で取得
def windowed_mean(cumsum, start, end):
    return (cumsum[end] - cumsum[start - 1]) / (end - start + 1)

def windowed_var(cumsum, cumsq, start, end):
    n = end - start + 1
    mean = windowed_mean(cumsum, start, end)
    return cumsq[end] - cumsq[start-1]) / n - mean**2
```

#### Prefix-Sum対応メトリクス（O(1)/窓）:
| メトリクス | 方法 |
|-----------|------|
| mean (CAGR proxy) | cumsum / n |
| variance, std | cumsq + cumsum |
| sum | cumsum差分 |
| count | n（自明） |

#### Prefix-Sum非対応（フル計算必要）:
| メトリクス | 理由 | 対策 |
|-----------|------|------|
| quantile (MDD, tail) | 順序統計量 | ソート必要。ただしIS配列スライスは O(1)ビュー → np.quantile高速 |
| skew, kurt | 3次/4次モーメント | cumsumで3乗/4乗のcumも保持すれば O(1)可能 |
| max_run_up, NHF | 累積系列依存 | cummax/cummin のprefix版は不可。フル計算必要 |
| left_tail_jumps | 条件カウント | `cumsum(returns < -2σ)` のprefix可能（σがprefix-sum対応なら） |

#### 高次モーメントのPrefix-Sum:
```python
cum3 = np.cumsum(returns ** 3, axis=0)  # skew用
cum4 = np.cumsum(returns ** 4, axis=0)  # kurtosis用
# skew = (cum3 - 3*mean*cumsq + 2*mean^3*n) / (n * std^3)  → O(1)
```

### C3. 2層アーキテクチャ

```
Layer 1: Prefix-Sum前計算（1回。O(months × patterns)）
  cumsum, cumsq, cum3, cum4, cumcount_below_threshold

Layer 2: IS窓別メトリクス取得（O(1) per IS窓 for prefix-sum metrics）
  + O(IS月数) per IS窓 for non-prefix metrics (quantile, run-up系)
```

### C4. 速度推定（Prefix-Sum適用後）

| フェーズ | 計算量 | 推定時間(加速R) |
|---------|--------|----------------|
| Layer 1: prefix前計算 | O(166 × 119493 × 4配列) | ~0.1秒 |
| Layer 2a: prefix-sumメトリクス | O(67窓 × 30fold × 119493) → **ただしO(1)/窓** | ~0.01秒 |
| Layer 2b: non-prefixメトリクス | O(67窓 × 30fold × avg(39) × 119493) | ~15秒 |
| **合計** | | **~15秒/忍者** |

Layer 2bが支配的。non-prefixメトリクス（quantile, run-up系）がボトルネック。

### C5. Non-Prefixメトリクスの高速化

#### 手段1: サフィックス共有
最長IS(72M)のスライスからビュー。メモリコピーゼロ。

#### 手段2: Pool並列（fold × IS窓タスクを分散）
1,968タスク ÷ Pool(N)。ただしLayer 2bのみ並列化。

#### 手段3: Non-prefixメトリクスの計算順序最適化
- quantile: np.partition (O(n)) は np.sort (O(n log n)) より高速
- max_run_up: cummax差分。numpy vectorized
- NHF: cummax比較。numpy vectorized

#### 手段4: foldステップ共有
隣接fold（STEP=4ヶ月ずれ）はIS配列の大部分が重複。
差分計算（新4ヶ月追加+旧4ヶ月削除）でメトリクス更新可能:
```
fold[i]のIS: months[s : s+W]
fold[i+1]のIS: months[s+4 : s+4+W]
重複: months[s+4 : s+W]  (W-4ヶ月分)
```
ただしquantile等の差分更新は複雑。実装コスト要検討。

### C6. 最終速度推定

| 構成 | 加速R | 7忍法 |
|------|-------|-------|
| 現行(固定IS=36) | 5.25秒 | 300秒(5分) |
| 素朴全探索 | ~344秒 | ~2030秒 |
| **Prefix-Sum + Pool(6) + サフィックス共有** | **~15秒** | **~90秒** |
| **+ Pool(12) + quantile最適化** | **~8秒** | **~48秒** |
| **+ batch(4忍法並列)** | — | **~24秒 ✅** |

Pool(12) + batch(4) + prefix-sum + quantile最適化で **~24秒/7忍法**。現行300秒(5分)以下。

### C7. 検証AC

1. `timeout 35` で7忍法全量完了するか
2. 動的IS窓版の所要時間 ≤ 固定IS窓版(300秒(5分))か
3. IS=36固定部分の結果が現行版と完全一致するか（回帰なし）
4. prefix-sumメトリクス vs フル計算メトリクスの数値一致確認（atol=1e-10）

### C8. 安全弁

```python
estimated = measure_single_fold() * total_folds / num_workers
if estimated > BUDGET:
    num_workers = auto_scale(total_folds, BUDGET, measure_single_fold())
```

---

## §8. ランブック — 忍者向けcmd分解

**最終更新**: 軍師 2026-04-07（v4: cmd_1782完了後。なぜなぜ分析+ランブック精密化）

### 現在地（cmd_1782完了後 commit ce4c0269）

| 機能 | 状態 | ファイル:行 |
|------|------|------------|
| PrefixMomentCache(cum1-4+log1p) | ✅実装済み | L114-163 |
| generate_folds_multi_is | ✅実装済み | L199-233 |
| --multi-is CLI | ✅実装済み | L1422-1424 |
| select_champions_multi_is | ✅実装済み | L688-811 |
| _build_suffix_max_runup | ✅実装済み | L445-454 |
| positive_suffix前計算 | ✅実装済み | L720 |
| bulk_mean/bulk_std/bulk_cagr | ✅実装済み | L721-722 |
| _compute_metrics_np_window_fast | ✅実装済み(cmd_1782) | L367-411 |
| compute_metrics_np_window フル版呼出し廃止 | ✅PASS(cmd_1782 AC1) | L414-423 |
| validate_prefix_window_metrics(34メトリクス全量) | ✅PASS(cmd_1782 AC2) | L426-435 |
| baseline_v2 IS=36固定 回帰テスト | ✅PASS(cmd_1782 AC4) | |
| **67窓速度** | **❌FAIL** | **timeout 40 exit 124。2忍法で37.55s実測(yotsume 21.46s+bunshin 16.09s)** |

---

### なぜなぜ分析 — なぜ timeout 40 exit 124 か

**L1. なぜ40秒超か**
→ batch=4並列の第1ラウンド(yotsume/bunshin/kasoku_ratio/nukimi)でmax>40s

**L2. なぜPool(2)で21.46sか（単体yotsume実測）**
→ select_champions_multi_is内の67 IS窓ループに2つのボトルネック:
- **律速①: tail_contribution** — `_quantile_with_partition(window_arr, 0.90)` ×67窓×30fold
  - 計算量: P=119493, Σ(IS×log(IS))=2247 → 119493×2247×30fold/Pool(2) ≈ 8B操作/worker
- **律速②: NHF** — `np.maximum.accumulate(local_cum[:-1], axis=0)` ×67窓
  - 72×119493=8.6M要素の操作を67回実行

**L3. なぜPool(2)か**
→ CPU=8, batch=4(デフォルト: `min(7, max(1, 8//2))=4`) → inner=8//4=2

**L4. なぜNHF cummax前計算で高速化できないか**
→ NHF定義: 「IS期間内の新高値頻度」。IS窓ごとに開始点(offset)が変わる。
→ `np.maximum.accumulate(segment_cum[offset:], axis=0)` の累積は offset起点から始まる。
→ 全体のseg_cummax=`np.maximum.accumulate(segment_cum)` は0点起点→定義が変わる。**前計算不可**。

**L5. 最有効な改善策**
→ Pool配分変更（batch削減・inner増加）+ 最重忍法の単体計測でボトルネック確定

---

### cmd D-0: 実態計測（ランブック前提・必須実施）

**目的**: 各忍法の単体速度 + Pool数別時間を実測。最適配分を確定する。

```bash
cd /mnt/c/Python_app/DM-signal/outputs/scripts

# STEP 1: yotsume単体でPool数別計測（最重忍法の速度マップ）
CSV=/mnt/c/Python_app/DM-signal/outputs/grid_search/shin_ninpo_v2_12body/1200_yotsume_grid_monthly_fast.csv
for w in 1 2 4 6 8; do
  echo -n "Pool($w): "
  time timeout 60 python l1_alm_wf_engine.py --csv $CSV --multi-is \
    --parallel-workers $w 2>&1 | grep "total_elapsed\|elapsed"
done

# STEP 2: 全7忍法単体速度（Pool=4）
for CSV in 1186_kasoku_ratio kasoku_diff nukimi oikaze 1200_yotsume 1200_bunshin kawarimi; do
  echo -n "$CSV: "
  time timeout 60 python l1_alm_wf_engine.py \
    --csv ./../grid_search/shin_ninpo_v2_12body/${CSV}_*monthly_fast.csv \
    --multi-is --parallel-workers 4 2>&1 | grep "elapsed"
done

# STEP 3: batch配分比較
for bw in 2 4 7; do
  echo "=== batch=$bw ==="
  iw=$((8 / bw > 0 ? 8 / bw : 1))
  time timeout 45 python l1_alm_wf_engine.py --multi-is --batch-csvs \
    --batch-workers $bw --batch-inner-workers $iw 2>&1 | tail -5
done
```

**計測すべき値と判断基準**:
| 計測 | 判断基準 |
|------|---------|
| yotsume Pool(N)別時間 | Pool(2)=21.46s → Pool(4)でどこまで下がるか |
| 7忍法の単体時間（重い順ランク） | 第1バッチに重い忍法を詰め込んでいないか確認 |
| batch=2,4,7の実測 | Wall time最小のbatch数を特定 |

---

### cmd D-1: Pool配分最適化

**目的**: D-0の実測に基づきbatch/inner workersを最適値に変更。

**変更対象**: `outputs/scripts/l1_alm_wf_engine.py` `default_batch_workers()` L1327-1329

**現状(L1327-1329)**:
```python
def default_batch_workers(csv_count: int) -> int:
    cpu = mp.cpu_count() or 1
    return max(1, min(csv_count, max(1, cpu // 2)))  # cpu=8 → 4
```

**D-0実測結果に応じた修正候補**:

| 変更案 | batch | inner | 条件 |
|--------|-------|-------|------|
| A: 全並列 | 7 | 1 | yotsume Pool(1)≤ 31.10s の場合 |
| B: 減batch | 2 | 4 | Pool(4)でyotsume≤14s かつ 2ラウンドで≤28s の場合 |
| C: 現行維持 | 4 | 2 | 重い忍法をバランス配置で解決できる場合 |

**案Aの実装**（全並列 = 最もシンプル）:
```python
def default_batch_workers(csv_count: int) -> int:
    return csv_count  # 全忍法を一斉並列。inner_workers=1
```
AC: `timeout 35 python l1_alm_wf_engine.py --multi-is --batch-csvs --batch-workers 7 --batch-inner-workers 1` ≤31.10s

**注意**: WSL2でfork()のプロセス起動コストがcpu_countを超えても線形に増加しないか確認が必要。

---

### cmd D-2: tail_contribution高速化（Pool配分で不足な場合のみ）

**目的**: 律速①のtail_contribution計算をさらに高速化。

**対象**: `outputs/scripts/l1_alm_wf_engine.py` `select_champions_multi_is` L748-754

**現状(L748-754)**:
```python
if "tail_contribution" in objectives:
    pct90 = _quantile_with_partition(window_arr, 0.90)        # ← O(IS×P×log(IS))
    total_pos = positive_suffix[offset]                         # ← 前計算済み O(1)
    tail_sum = np.where(window_arr > pct90[np.newaxis, :], window_arr, 0.0).sum(axis=0)
    with np.errstate(invalid="ignore", divide="ignore"):
        tail_contrib = np.where(total_pos != 0.0, tail_sum / total_pos, np.nan)
```

**高速化案 — float32化（計算量変わらず速度2x）**:
```python
# L717前後: segmentをfloat32に
segment = arr[max_row_start : max_row_end + 1].astype(np.float32)  # float64→float32
# 以降の window_arr, pct90, tail_sum はfloat32で計算 → np.partition速度2x
```

**精度確認必須**:
```python
# validate時にatol緩和が必要
# float32のnp.partition: 最大誤差 ≈ IS月 × 1e-7 ≈ 72 × 1e-7 = 7e-6
# atol=1e-5で検証
```

**AC**: `validate_prefix_window_metrics(arr, start, end, prefix_cache, atol=1e-5)` 全PASS

---

### cmd D: AC（最終）

```
AC1: timeout 40 python l1_alm_wf_engine.py --multi-is --batch-csvs [全7忍法] の実測≤300秒(5分)
AC2: 34メトリクス精度維持。--validate で全PASS（atol=1e-10 or 1e-5 float32時）
AC3: baseline_v2(IS=36固定)との回帰テストPASS
```

**実行コマンド(AC1)**:
```bash
cd /mnt/c/Python_app/DM-signal/outputs/scripts
BATCH_CSVS=(
  "../grid_search/shin_ninpo_v2_12body/1186_kasoku_ratio_grid_monthly_fast.csv"
  "../grid_search/shin_ninpo_v2_12body/1186_nukimi_grid_monthly_fast.csv"
  "../grid_search/shin_ninpo_v2_12body/1186_oikaze_grid_monthly_fast.csv"
  "../grid_search/shin_ninpo_v2_12body/1200_yotsume_grid_monthly_fast.csv"
  "../grid_search/shin_ninpo_v2_12body/metrics_bunshin_monthly_fast.csv"
  "../grid_search/shin_ninpo_v2_12body/1186_kasoku_diff_grid_monthly_fast.csv"
  "../grid_search/shin_ninpo_v2_12body/1186_kawarimi_grid_monthly_fast.csv"
)
timeout 40 python l1_alm_wf_engine.py --multi-is --batch-csvs "${BATCH_CSVS[@]}"
```

**テスト方針**:
1. D-0計測→最適batch数確定→D-1実装→AC1確認
2. AC1失敗 → D-2(float32化)実施→AC1再確認
3. AC2: `python l1_alm_wf_engine.py --csv yotsume.csv --multi-is --validate` でPASS確認
4. AC3: `python l1_alm_wf_engine.py --csv yotsume.csv --multi-is=false` → baseline_v2と突合

---

### cmd E: 回帰基準更新

**目的**: cmd_1782でbaseline_v2(saizo1781_base36c)は確認済み。速度改善後の再検証。

**対象**: `outputs/scripts/l1_alm_wf_engine.py` `--multi-is=false` モード

**実行手順**:
```bash
# Step 1: IS=36固定で7忍法実行
python l1_alm_wf_engine.py --multi-is=false --batch-csvs "${BATCH_CSVS[@]}" \
  --cmd-id baseline_v3

# Step 2: 67窓版でIS=36部分を抽出して突合
python l1_alm_wf_engine.py --multi-is --batch-csvs "${BATCH_CSVS[@]}" \
  --cmd-id multi_is_test
# → selection_timeline中でis_window_months=36の行をbaseline_v3と比較
```

**AC**:
```
AC1: IS=36固定 7忍法実行が完了し selection_timeline + alm_returns が生成される
AC2: 67窓版のis_window_months=36エントリとbaseline_v3が完全一致（pattern_id一致）
AC3: baseline_v3をbaseline_v2として保存（次回cmdの回帰基準）
```

---

### cmd F: 67窓全量実行+検証（cmd D+E完了後）

**目的**: 67窓全探索で7忍法の最適IS窓を確定。OOS検証への橋渡し。

**前提**: cmd D(速度達成)+ cmd E(回帰基準)完了

**実行**:
```bash
timeout 40 python l1_alm_wf_engine.py --multi-is --batch-csvs "${BATCH_CSVS[@]}" \
  --cmd-id alm_l1_67window
```

**AC**:
```
AC1: 全7忍法のselection_timelineが生成され、is_window_monthsが6〜72の範囲内
AC2: 各忍法のis_window_months分布を確認（全て36固定でないこと=動的選択が機能）
AC3: 7忍法のOOS alm_returnsが生成される
```

---

### cmd配備順序

```
D-0 計測（忍者単体確認） → D-1 Pool配分最適化 → AC1確認
  ↓ AC1 FAIL時のみ
  D-2 float32化 → AC1再確認
  ↓ PASS
cmd E 回帰基準更新 → cmd F 67窓全量実行
  ↓（cmd E と cmd F は直列。cmd Dと並列不可）
ALM L1統合 → 本番登録
```

**最優先**: cmd D-0実態計測が全ての前提。計測なしに最適化すると盲打ちになる。

---

## セルフレビュー3点

1. **なぜなぜ深度**: L5まで掘り「Pool配分+tail_contribution律速」を特定。前計算不可の根拠(NHF cummax起点依存)も明示済み
2. **ランブック粒度**: D-0計測コマンドを実行可能形式で記載。AC判定コマンドも明示。4メトリクス設計書水準を目標とした

---

# §9. cmd_1785: compute_metrics_np 6→38メトリクス拡張設計

**作成**: 軍師 2026-04-07（cmd_1785設計）
**目的**: ALM L1 67窓全探索で全38メトリクスを比較対象に。現行6メトリクスを38に拡張。
**絶対条件**: 速度回帰なし（prefix化で速度維持）
**詳細設計書**: `docs/research/gunshi-alm-38metrics-design.md`

---

## §9-0. 既存実装の活用方針（車輪の再発明禁止）

**l1_alm_wf_engine.py は既に MRE を import している** (L55 `MRE = importlib.import_module("metrics_research_engine")`)

| 使うべき既存実装 | 場所 | l1_alm版への変換 |
|----------------|------|----------------|
| 全38メトリクスnumpy計算ブロック | MRE `batch_rolling_metrics` L1537-1796 | **axis=2 → axis=0** のみで転用可 |
| DD系3メトリクス完全vectorized | MRE L1768-1795 | axis変換のみ。新関数不要 |
| best_year / worst_year | MRE L1586-1601 | year_arr引数版に改変のみ |
| downside_deviation | MRE L1584: `np.sqrt(np.mean(np.minimum(0.0, windows)**2, axis=2))` | axis=2→axis=0 |
| MDD, Calmar, VaR, Sortino | MRE L1603-1624 | axis=2→axis=0 |
| MINIMIZE_FINAL_METRICS | **l1_alm L71-82 に既存定義済み** | 再実装禁止。MINIMIZE_SETの更新のみ |

---

## §9-1. 38メトリクス分類

| 分類 | 件数 | メトリクス |
|------|------|----------|
| prefix O(1) — wire要（既存実装済み） | 8 | cagr/sharpe/max_run_up/nhf/tail_contribution/left_tail_jumps_inv/skewness/excess_kurtosis |
| prefix O(1) — 新規追加 | 6 | arithmetic_mean_monthly/ann, geometric_mean_monthly, std_ann, analytical_VaR_5, positive_periods, gainloss_ratio |
| prefix+ Cache拡張要 | 4 | downside_dev, positive_periods, gainloss_ratio, sortino |
| vectorized O(IS×P) | 7 | MDD, calmar, best_year, worst_year, underwater_period, drawdown_length, recovery_time |
| N/A — NaN固定 | 13 | benchmark系7 + benchmark_correlation/beta/alpha/R²/Treynor/updown系3/active_return/tracking_error/information_ratio |

---

## §9-2. PrefixMomentCache拡張（4配列追加）

**対象**: `outputs/scripts/l1_alm_wf_engine.py` L115-192

```python
# PrefixMomentCache.build() に追加（L123-132付近）
arr64 = np.asarray(arr, dtype=np.float64)
neg_sq = np.minimum(arr64, 0.0) ** 2
pos_mask = arr64 > 0.0

# 新規4フィールド追加
cumpos     = np.cumsum(pos_mask.astype(np.float64), axis=0)   # count(r>0)
cum_neg_sq = np.cumsum(neg_sq, axis=0)                         # Σmin(r,0)²
cumpos_sum = np.cumsum(np.where(pos_mask, arr64, 0.0), axis=0) # Σr[r>0]
cumneg_sum = np.cumsum(np.where(~pos_mask, arr64, 0.0), axis=0)# Σr[r≤0]
```

**メモリ追加**: 4配列 × (166, 119493) × 8bytes ≈ **+632MB**

---

## §9-3. DD系 — MRE L1768-1795 の axis変換転用

```python
# MRE L1768-1795 axis=2→axis=0 変換（コメントにMRE行番号記載必須）
cum = np.cumprod(1.0 + window_arr, axis=0)       # (IS, P)
IS, P = cum.shape
running_max = np.maximum.accumulate(cum, axis=0)  # MRE L1768
dd_arr = np.where(running_max > 0.0, cum / running_max - 1.0, 0.0)
max_drawdown = -np.min(dd_arr, axis=0)            # (P,)
trough_pos = np.argmin(dd_arr, axis=0)            # MRE L1770

time_idx = np.arange(IS)[:, None]
pre_trough_mask = time_idx <= trough_pos[None, :]
peak_pos = np.argmax(np.where(pre_trough_mask, cum, -np.inf), axis=0)  # MRE L1772-1774
drawdown_length = (trough_pos - peak_pos).astype(float)                 # MRE L1778

peak_val = cum[peak_pos, np.arange(P)]
post_trough_mask = time_idx >= trough_pos[None, :]
recovered_mask = post_trough_mask & (cum >= peak_val[None, :])
has_recovery = recovered_mask.any(axis=0)
recovery_pos = np.argmax(recovered_mask, axis=0)
recovery_time = np.where(has_recovery, (recovery_pos - trough_pos).astype(float), np.nan)
underwater_period = np.where(has_recovery, (recovery_pos - peak_pos).astype(float), np.nan)

# MRE L1788-1791: no_drawdown補正
no_drawdown = max_drawdown == 0.0
drawdown_length    = np.where(no_drawdown, 0.0, drawdown_length)
recovery_time      = np.where(no_drawdown, 0.0, recovery_time)
underwater_period  = np.where(no_drawdown, 0.0, underwater_period)
```

---

## §9-4. cmd分解ランブック

### cmd_1785-A: PrefixMomentCache拡張 + prefix系実装

**変更箇所**: PrefixMomentCache(L115-192) + METRIC_NAMES(L66) + `_compute_metrics_np_window_fast`(L367-411)

**AC**:
```
AC1: cumpos/cum_neg_sq/cumpos_sum/cumneg_sumが生成される
     確認: assert hasattr(cache, 'cumpos') and cache.cumpos.shape == arr.shape
AC2: prefix系14メトリクスがcompute_metrics_np(full版)と atol=1e-10で一致
     確認: --validate で全prefix系PASS
AC3: 速度回帰なし（yotsume単体 Pool=4 67窓、以前と同等秒以内）
```

### cmd_1785-B: vectorized系実装（MDD/DD系/Best-Worst年）

**変更箇所**: `_compute_metrics_np_window_fast` にvectorized系追加 + `_compute_best_worst_year()`追加
**新関数なし**: MRE L1768-1795をaxis変換転用。新関数は`_compute_best_worst_year()`のみ

**AC**:
```
AC1: maximum_drawdown / calmar_ratio が MRE版と atol=1e-6 一致
     コード確認: MRE L1603 cummax実装と1対1対応（行番号コメント必須）
AC2: DD系3メトリクス（underwater/dd_length/recovery）がMRE L1768-1795と atol=1e-6
AC3: Best/Worst Year が完全年のみ計算（IS=6M→NaN, IS=12M→1年分, IS=24M→2年分）
```

### cmd_1785-C: MINIMIZE_FINAL_METRICS+select_champions整合

**変更箇所**: MINIMIZE_FINAL_METRICS更新(L71-82) + METRIC_NAMES確定(38個)

**AC**:
```
AC1: 38メトリクス全量でselect_champions_multi_isが正常動作
     確認: --multi-is --batch-csvs で7忍法PASS
AC2: 速度目標維持（7忍法合計 ≤ 300秒(5分)）
```

### cmd配備順序

```
cmd_1784完了（速度確保） → cmd_1785-A → cmd_1785-B → cmd_1785-C
```

**速度影響**: MDD/DD系/Best-Worst追加で +10-20s/忍法 の見込み。
cmd_1784でPool最適化済み（目標10s/忍法）なら38メトリクス後も ≤ 31.10s に収まる見込み。
3. **不確実性の明示**: float32化のatol緩和要否、WSL2 fork()コストの不確実性を明記。実測(D-0)で確定する設計
