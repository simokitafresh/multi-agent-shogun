# cmd_1750: ALM本番組込み改修設計

**偵察対象**: `backend/app/jobs/recalculate_fast.py` (2271行)
**参考スクリプト**: `scripts/analysis/standard_pf_preprocessing/cmd_1736_alm_research.py`
**cmd_1749参考ファイル**: 未生成（docs/research/cmd_1749_*.mdは存在しない）
**作成日**: 2026-04-06 / kotaro

---

## 前提確認

### ALMとは（研究スクリプトから逆引き）
Adaptive Lookback Momentum (ALM): 複数のlookback候補（1〜24ヶ月）の中から、
直前のIS窓（rolling_window_months: 12/24/36/48/60ヶ月）のmonthly_returnsを使って
最良のlookbackを毎月動的に選出し、そのlookbackのシグナルを当月保有に使用する機構。

### 現状: ALMはまだ本番コードに存在しない
- `schemas/pipeline.py` の `PipelineConfig` にALM設定フィールドなし
- `schemas/models.py` の `Portfolio` にALM設定なし
- 本番コードに `alm` / `adaptive_lookback` の参照なし
- 本タスクは「本番組込みのための設計偵察」= 設計から行う必要がある

---

## AC1: Phase 3.7 OPT-E事前計算のALM対応

### 現状コード（精読箇所）

| 箇所 | 行番号 | 役割 |
|------|--------|------|
| `pipeline_momentum_caches`構築 | L902-L1018 | 各ブロックの固定lookbackでmomentum Seriesを計算 |
| Phase 3.7ベクトル化シグナル計算 | L1039-L1332 | `pipeline_momentum_caches`を使い全日付シグナルを一括計算 |
| `vectorized_pipeline_signals` 宣言 | L1046 | `Dict[str, Dict[date, str]]` |

### 現状の問題
- L955-982（MOMENTUM_FILTER/REVERSAL_FILTER/ABSOLUTE_MOMENTUM_FILTER）:
  - `lp_raw = config.get("lookback_periods", [])` → 固定lookbackを1セットのみ計算
  - ALM PFでは複数候補lookback（例: 1〜24ヶ月）の全てのmomentum Seriesが必要

### 設計: ALM対応の追加変数と構造拡張

#### Step 1: PipelineConfigへのALM設定追加 (schemas/pipeline.py)

```python
# schemas/pipeline.py に追加
class AlmConfig(BaseModel):
    """Adaptive Lookback Momentum configuration."""
    candidate_lookbacks: List[int]        # 例: list(range(1, 25)) = [1..24]
    is_window_months: int                  # IS窓幅（月数）例: 36
    objective_metric: str = "max_run_up"  # 評価メトリクス（minimize/maximizeはMINIMIZE_METRICSセット参照）

class PipelineConfig(BaseModel):
    selection_pipeline: SelectionPipeline
    terminal_block: BlockDefinition
    alm_config: Optional[AlmConfig] = None  # ← 追加（NoneならALM無効＝従来動作）
```

#### Step 2: pipeline_momentum_caches構築のALM対応 (L902-L1018)

**変更対象行**: L950-L982（MOMENTUM_FILTER/REVERSAL_FILTER処理内）
```
L955-963: MOMENTUM_FILTER/REVERSAL_FILTER の固定lookback計算ブロック
→ ALM PFの場合、candidate_lookbacksの全lbに対してcalculate_composite_momentum_vectorizedを追加実行
```

**追加格納構造**:
```python
# 既存 block_cache[block_def.id] = {ticker: Series}  ← 固定lookback (ALM非対応PF)
# 追加 (ALM PFのMOMENTUM_FILTERブロック)
block_cache[block_def.id] = {ticker: Series}  # 固定lookback（後述の理由でも保持）
block_cache[f"{block_def.id}__alm"] = {
    lb: {ticker: Series}
    for lb in alm_config.candidate_lookbacks
}
# キー命名規則: "{block_id}__alm" = ALM候補全lookbackのmomentum cache
```

**メモリ・計算コスト見積もり**:
| パラメータ | 値 | 備考 |
|-----------|-----|------|
| N候補 | 24 | candidate_lookbacks=[1..24] |
| Tティッカー | 10 | 典型的なシン忍法1体のティッカー数 |
| D日数 | 6,500日 | 2000-2026年全期間 |
| 1 Series | float64×6,500 = 52KB | |
| 追加メモリ | N×T×52KB = 24×10×52KB ≈ **12.5 MB/ALM PF** | |
| 計算コスト | 既存の 24 倍のmomentum計算 | ベクトル化済みなのでabs時間は小（～1〜2s/PF） |

**既存PFへの影響**: `alm_config is None` の場合は従来コードパス走行。影響ゼロ。

#### Step 3: Phase 3.7でのALM全候補シグナル事前計算 (L1039-L1332)

**変更対象行**: L1068-L1325（pipeline PF毎のvectorized signal計算ループ）
```
L1068: for _vec_pf_id, _vec_cfg in pipeline_cfg_cache.items():
  ↓
  ALM PFかどうかを判定: _vec_cfg.alm_config is not None
  ALM PFの場合: 全候補lookbackのシグナルを計算し alm_vectorized_signals に格納
  非ALM PFの場合: 従来通り vectorized_pipeline_signals に格納
```

**新変数**:
```python
# L1046直下に追加宣言
alm_vectorized_signals: Dict[str, Dict[int, Dict[date, str]]] = {}
# portfolio_id → {lookback_months → {date → signal}}
```

**計算ロジック（L1068-L1325の拡張）**:
```python
if _vec_cfg.alm_config is not None:
    _alm_bc = pipeline_momentum_caches.get(_vec_pf_id, {})
    _alm_sigs_by_lb: Dict[int, Dict[date, str]] = {}
    for _lb in _vec_cfg.alm_config.candidate_lookbacks:
        # _alm_bc から candidate lookback lb のmomentum cacheを取り出す
        # 既存の _vd/_vd_sk構築ロジックを _alm_bc[f"{block_id}__alm"][_lb] で差し替え
        _pf_sigs_lb: Dict[date, str] = {}
        # ... (既存の全日付シグナル計算ループをlb用のcacheで実行)
        _alm_sigs_by_lb[_lb] = _pf_sigs_lb
    alm_vectorized_signals[_vec_pf_id] = _alm_sigs_by_lb
else:
    # 従来通り
    vectorized_pipeline_signals[_vec_pf_id] = _pf_sigs
```

---

## AC2: Phase 4 日次ループへの月次ALM選出差込み

### 差込み位置

**月初リバランス判定ブロック内**: L1499-L1511
```python
# L1499: if month_changed and is_reb_month:
#   L1502: current_holding_signals[portfolio.id] = last_gen_signal  # ← ここの前後に挿入
```

**差込み位置の根拠**: 月初リバランス時にholding_signalを更新する直前。
ALM選出によって「当月採用するlookback」が確定し、それに対応するシグナルをlast_gen_signalに使うため。

### 追加変数・dict構造拡張

```python
# Phase 3の初期化ブロック（L1351付近）に追加:
alm_selected_lookbacks: Dict[str, int] = {}  # portfolio_id → 選出されたlookback_months
# 初期値なし（最初のリバランス月まではデフォルトlookbackを使用）
```

### 月初判定との連携（L1499-L1511の修正）

```python
if month_changed and is_reb_month:
    # ─── ALM選出（ALM PFのみ） ───
    if portfolio.id in alm_vectorized_signals:
        _alm_cfg = pipeline_cfg_cache[portfolio.id].alm_config
        _selected_lb = _select_alm_lookback(
            portfolio_id=portfolio.id,
            current_date=current_date,
            alm_cfg=_alm_cfg,
            monthly_returns_cache=alm_monthly_returns_cache,  # ← 課題3で解決
        )
        alm_selected_lookbacks[portfolio.id] = _selected_lb
        # ALM選出したlookbackのシグナルで last_gen_signal を上書き
        _alm_pf_sigs = alm_vectorized_signals[portfolio.id].get(_selected_lb, {})
        _alm_signal = _alm_pf_sigs.get(current_date - _one_day)  # 前日シグナル
        if _alm_signal is not None:
            last_gen_signal = _alm_signal  # ← 月初に採用するシグナルをALM選出値に変更

    # 既存: current_holding_signals[portfolio.id] = last_gen_signal  (L1502)
    current_holding_signals[portfolio.id] = last_gen_signal
    # ... (以降既存処理)
```

### シグナル取得時の修正 (L1528-L1533)

```python
# 変更前: vectorized_pipeline_signalsのO(1) lookup
if portfolio.id in vectorized_pipeline_signals:
    _pre_sig = vectorized_pipeline_signals[portfolio.id].get(current_date)

# 変更後: ALM PFは選出lookbackで参照、非ALM PFは従来通り
if portfolio.id in alm_vectorized_signals:
    _lb = alm_selected_lookbacks.get(portfolio.id)
    if _lb is not None:
        _pre_sig = alm_vectorized_signals[portfolio.id].get(_lb, {}).get(current_date)
    else:
        # 最初のリバランス月前: デフォルト(最初の候補lb)を使用
        _default_lb = pipeline_cfg_cache[portfolio.id].alm_config.candidate_lookbacks[0]
        _pre_sig = alm_vectorized_signals[portfolio.id].get(_default_lb, {}).get(current_date)
elif portfolio.id in vectorized_pipeline_signals:  # 非ALM PF（従来通り）
    _pre_sig = vectorized_pipeline_signals[portfolio.id].get(current_date)
```

### `_select_alm_lookback` 関数の設計

```python
def _select_alm_lookback(
    portfolio_id: str,
    current_date: date,
    alm_cfg: AlmConfig,
    monthly_returns_cache: Dict[str, List[Tuple[str, float]]],  # portfolio_id → [(year_month, return)]
) -> int:
    """月初ALM選出: IS窓のmonthly_returnsで最良lookbackを選出.

    Returns:
        選出されたlookback_months（候補にない場合はcandidate_lookbacks[0]）
    """
    # 1. IS窓のmonthly_returnsを取得
    mr = monthly_returns_cache.get(portfolio_id, [])
    is_end = (current_date.year, current_date.month)  # 先月末まで
    is_start_month = _subtract_months(is_end, alm_cfg.is_window_months)
    is_returns = [(ym, r) for ym, r in mr if is_start_month <= ym < is_end]

    if len(is_returns) < alm_cfg.is_window_months // 2:  # IS窓の半分未満→fallback
        return alm_cfg.candidate_lookbacks[-1]  # 最長lookback（最も安定）

    # 2. 各候補lookbackのIS期間メトリクスを計算
    # ※ ALM研究(cmd_1736)と同一ロジック: build_score_wide + simulate_selection
    # 実装詳細は別関数 _compute_alm_is_metrics() に委譲
    best_lb = _compute_alm_is_metrics(
        is_returns=is_returns,
        candidate_lookbacks=alm_cfg.candidate_lookbacks,
        objective_metric=alm_cfg.objective_metric,
    )
    return best_lb
```

---

## AC3: fullrecalculate時の鶏と卵問題

### 問題の構造

```
Phase 4 (シグナル計算) → Phase 4.5 (monthly_returns生成)

ALM選出 @ 月初:
  └─ requires monthly_returns (IS窓分の過去データ)
  └─ monthly_returnsはPhase 4.5で生成される
  └─ fullrecalculate時: Phase 4.5実行前 → monthly_returns存在しない ← 鶏と卵
```

### 3案比較

| 方式 | 説明 | メリット | デメリット |
|------|------|---------|---------|
| **2パス（推奨）** | Pass1: 固定lb→月次return生成 / Pass2: ALM選出→正式シグナル | 正確。現行アーキと整合 | fullrecalculate時間が約2倍 |
| インターリーブ | 月ごとに(シグナル→monthly_returns→ALM選出→次月) | 正確・1パス | 日次ループを月ループに大改修。工数が大 |
| Priceから直算 | monthly_returnsをDBではなくPriceから直接計算してALM選出 | 1パス・追加依存なし | ALM選出ロジックが本番と研究で二重管理リスク |

### 推奨案: 2パス方式

#### 理由
1. 設計が明確でPhase 4.5との整合性が高い（既存の`_generate_monthly_returns`を再利用）
2. 日次ETLでは前月分のmonthly_returnsがDB済み→問題なし（追加コストゼロ）
3. fullrecalculate時のみ2パスが必要。ALM PFは少数（1〜3体の想定）なので時間増は軽微

#### fullrecalculate専用2パス実装骨格

**呼び出し箇所**: L1763-L1779（Phase 4.5直前に判定ブロックを挿入）

```python
# ─── 2パス判定 (fullrecalculate × ALM PF存在時のみ) ───
_alm_pf_ids = [p.id for p in standard_portfolios if p.id in alm_vectorized_signals]
_is_fullrecalc = (start_date <= date(2001, 1, 1))  # 2000-01-01から開始 = fullrecalculate
_needs_two_pass = _is_fullrecalc and len(_alm_pf_ids) > 0

if _needs_two_pass:
    logger.info(f"[ALM 2-pass] Pass1: generating monthly_returns for {len(_alm_pf_ids)} ALM PFs...")
    # Pass1: ALM PFについてdefault lookbackのmonthly_returnsを先行生成
    for p in standard_portfolios:
        if p.id in _alm_pf_ids:
            _generate_monthly_returns(db, p.id, price_cache=perf_price_cache, ...)

    # Pass1完了後: monthly_returns_cacheを構築
    alm_monthly_returns_cache = _build_alm_monthly_returns_cache(db, _alm_pf_ids)

    # Phase 4 再実行（ALM PFのみ）: ALM選出込みで正式シグナルを再計算
    logger.info(f"[ALM 2-pass] Pass2: recomputing signals with ALM selection...")
    _recompute_alm_signals(db, standard_portfolios, _alm_pf_ids, ...)
    logger.info(f"[ALM 2-pass] Pass2 complete.")

# ─── Phase 4.5: Generate Monthly Returns (全standard PF) ───
```

#### 日次ETLとの共通化

ALM選出ロジックを `_select_alm_lookback()` として共通関数化（AC2参照）。

- **fullrecalculate時**: Pass1のmonthly_returnsから`_build_alm_monthly_returns_cache()`で構築
- **日次ETL時**: DBの既存MonthlyReturnを`_build_alm_monthly_returns_cache()`でそのまま取得
- 同一関数`_select_alm_lookback()`を両パスで使用 → ロジック一本化

---

## 追加確認: recalculate_fof.pyのHook A

### 結論: Hook Aは不要

**根拠**:
- FoFはStandard PFのmonthly_returnsを `ComponentPriceBlock` 経由で参照
  （recalculate_fof.py L28: `from .generators.monthly_returns import _generate_monthly_returns`）
- ALM PFのmonthly_returnsが正確に生成されれば（= Phase 4.5完了）、FoFパイプラインは変更不要
- ALM PFのシグナル選択ロジックはFoFから不透明（ALM内部で完結）

### ただし注意点
- ALM PFのmonthly_returnsがPhase 4.5で正確に生成されるには、ALM選出済みシグナルが先に確定していること（2パス完了後）が前提
- Phase実行順序: `Phase 4(Pass1) → Phase 4.5(Pass1) → Phase 4(Pass2, ALM) → Phase 4.5(通常) → Phase 5(FoF)` となる

### ALM PF用テスト設計

| テスト | 内容 | 場所 |
|--------|------|------|
| `test_alm_pf_parity` | ALM PFの計算結果が非ALM固定lbと同等 | backend/tests/ |
| `test_alm_select_lookback` | `_select_alm_lookback()` の単体テスト（IS窓評価ロジック） | backend/tests/ |
| `test_alm_two_pass_fullrecalc` | 2パスfullrecalculate後のmonthly_returns整合性 | backend/tests/ |
| `test_alm_daily_etl_continuity` | 日次ETLでのALM選出が月をまたいでも連続する | backend/tests/ |

---

## AC4: 偵察一覧

### 変更対象ファイル+行番号

| ファイル | 行番号 | 変更内容 |
|---------|--------|---------|
| `schemas/pipeline.py` | 全体（末尾追加） | `AlmConfig` class追加 + `PipelineConfig.alm_config`フィールド追加 |
| `recalculate_fast.py` | L955-L982 | `pipeline_momentum_caches`構築: ALM候補全lb計算追加（`block_cache[f"{id}__alm"]`） |
| `recalculate_fast.py` | L1046 | `alm_vectorized_signals`変数宣言追加 |
| `recalculate_fast.py` | L1068-L1325 | Phase 3.7: ALM PFの全候補lbシグナル計算追加 |
| `recalculate_fast.py` | L1351付近 | Phase 3初期化: `alm_selected_lookbacks`変数追加 |
| `recalculate_fast.py` | L1499-L1511 | 月初リバランスブロック: ALM選出ロジック挿入 |
| `recalculate_fast.py` | L1528-L1533 | シグナル取得: ALM対応分岐追加 |
| `recalculate_fast.py` | L1763前後 | 2パス判定ブロック追加（fullrecalculate × ALM時） |

### 波及先ファイル

| ファイル | 波及内容 | 修正要否 |
|---------|---------|---------|
| `schemas/pipeline.py` | `AlmConfig`追加・`PipelineConfig`拡張 | **必須** |
| `db/models.py` | `portfolio_config`カラムへのALM設定保存 | 不要（pipeline_config JSONに追加で対応可） |
| `jobs/generators/monthly_returns.py` | ALM PF自体は標準monthly_returns生成 | **不要** |
| `recalculate_fof.py` | Hook A不要（ALM PFのmonthly_returnsが正確なら問題なし） | **不要** |
| `services/vectorized_momentum.py` | candidate_lookbackの計算に使う | **不要**（既存`calculate_composite_momentum_vectorized`を再利用） |

### テスト有無+修正要否

| テストファイル | 種別 | 対応要否 |
|-------------|------|---------|
| `tests/test_cmd_1736_alm_research.py` | 研究用（本番コードに無関係） | 不要 |
| `tests/test_cmd_1737_alm_oos_verification.py` | 研究用 | 不要 |
| `tests/test_recalculate_fast.py`（想定） | 本番テスト | ALM PFケース追加が必要 |

### エッジケース

1. **IS窓不足（初期月）**: IS窓（例：36ヶ月）分のmonthly_returnsが存在しない
   → fallback: `candidate_lookbacks[-1]`（最長lookback）を使用
2. **ALM候補が全てNaN**: 全候補で評価メトリクス計算不可
   → fallback: `candidate_lookbacks[0]`（最短lookback）
3. **月初判定 + ALM PF + Pass2でシグナル不整合**:
   → Pass2後に`signals_batch`をALM PF分だけ再構築する必要あり（DB UPSERTで上書き）
4. **ALM PF + 部分再計算（portfolio_ids指定）**:
   → 指定PFにALM PFが含まれる場合、monthly_returns依存判定が必要（is_fullrecalcフラグではなくDB確認）

### 依存関係・順序制約

```
[Phase 1] データロード (L700-L736)
  ↓
[Phase 1.5] 有効開始日計算 (L738付近)
  ↓
[既存OPT-6] pipeline_momentum_caches構築 (L902-L1018)
  ↓ ← ALM: candidate_lookbacks全て計算追加
[Phase 3.7] vectorized_pipeline_signals構築 (L1039-L1332)
  ↓ ← ALM: alm_vectorized_signals構築追加
[Phase 3] 状態初期化 (L1350-L1370)
  ↓ ← alm_selected_lookbacks追加
[Phase 4] 日次ループ (L1420-L1619)
  ↓ ← 月初にALM選出挿入 (L1499付近)
  ↓ ← シグナルO(1)lookup修正 (L1528付近)
[2パス判定] (L1763前) — fullrecalculate × ALM時のみ
  ↓ ← Pass1: ALM PFのmonthly_returns先行生成
  ↓ ← Pass2: ALM選出込みで正式シグナル再計算
[Phase 4.5] monthly_returns生成 (L1763-L1779)
  ↓
[Phase 5] FoF再計算 (L1787-L1821)  ← ALM PFのmonthly_returnsが完成している前提
```

**flush順序**: Pass2のシグナルはPass1シグナルをUPSERTで上書き → DB書き込み順序制約あり（Pass1 flush完了後にPass2 flush）

---

## 設計サマリー

| 課題 | 推奨改修方式 | 工数概算 |
|------|-----------|---------|
| Phase 3.7 ALM全候補事前計算 | `block_cache[f"{id}__alm"]` + `alm_vectorized_signals` 追加 | M（既存ループの拡張） |
| Phase 4 月次ALM選出差込み | 月初判定ブロックに `_select_alm_lookback()` 挿入 | M |
| fullrecalculate 2パス | 既存Phase 4.5前に判定ブロック追加 | L（2パス制御フロー） |
| schemas/pipeline.py拡張 | `AlmConfig` + `PipelineConfig.alm_config` フィールド追加 | S |
| テスト追加 | ALM PF parity + 月次選出 + 2パス整合 | M |
