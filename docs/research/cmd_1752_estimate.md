# cmd_1752: ALM本番組込み impl工数見積もり

**作成日**: 2026-04-06 / kotaro
**参照設計**: `docs/research/cmd_1750_alm_design.md`
**対象ファイル**: `backend/app/jobs/recalculate_fast.py` (2271行)

---

## AC1: 書込み競合分析（Pass2→Phase4.5→Phase5の安全性）

### フロー全体

```
Phase 4 Pass1 (日次ループ L1420-L1635)
  → final flush (L1637-1642)
  → OPT-4 signal_preload DB load (L1728-1741)  ← Pass1シグナルをDBから読取
  → signal_cache_opt6構築 (L1752-1756)          ← signal_preloadから生成
  → [2パス判定ブロック 新設 @L1763前]
      → ALM PF向け Pass1 monthly_returns先行生成 (partial Phase 4.5)
      → monthly_returns_cacheロード
      → Pass2 ALM選出+シグナル再計算
      → Pass2 signal flush (UPSERT)
  → Phase 4.5 (L1766-1779) _generate_monthly_returns (全standard PF)
  → Phase 5 FoF (L1789-1821)
```

### 競合リスク: signal_cache_opt6 陳腐化 **[CRITICAL]**

| 行番号 | 問題 | 影響 |
|--------|------|------|
| L1752-1756 | signal_cache_opt6 は Pass1 signals で構築済み | Phase 4.5でALM PFのmonthly_returns計算にPass1シグナルが使われる |
| L1772 | `_generate_monthly_returns(... signal_cache=signal_cache_opt6)` | ALM PFのMonthlyReturnがPass1(誤)シグナルで生成 |
| L1804 | `_recalculate_fof_history(db, ...)` | FoFがDBから誤MonthlyReturnを読取 |

**根本原因**: signal_cache_opt6 (L1752) は Phase 4 Pass1完了後に1回だけ構築。
Pass2シグナルがDB UPSERTされても signal_cache_opt6 は更新されない。

**修正必須**: Pass2 flush完了後、ALM PF IDに対して signal_cache_opt6 を再構築する。

```python
# 2パス判定ブロック内 Pass2完了直後に追加
for _alm_pf_id in _alm_pf_ids:
    _new_sigs = db.query(Signal).filter(
        Signal.portfolio_id == _alm_pf_id
    ).order_by(Signal.date).all()
    signal_cache_opt6[_alm_pf_id] = {
        s.date: build_signal_cache_value(s) for s in _new_sigs
    }
```

または、Pass2シグナルを計算した結果 dict (`{date: signal}`) から直接構築（DBクエリ不要・推奨）。

### Phase 4.5 → Phase 5 の安全性: **SAFE（条件付き）**

signal_cache_opt6 修正が完了すれば:
- Phase 4.5 (L1766) は Pass2正式シグナルでMonthlyReturn生成 → DB書込
- Phase 5 (L1789) はDB読取 (sequential) → 正しいMonthlyReturn参照
- 書込み競合なし（単一スレッド、逐次実行）

### flush順序制約

```
Pass1 final flush (L1637-1642)           ← BEFORE signal_preload load
Pass2 signal flush (新設, ~L1763)         ← BEFORE signal_cache_opt6 re-build
signal_cache_opt6 re-build (新設)         ← BEFORE Phase 4.5
Phase 4.5 MonthlyReturn write (L1766)    ← BEFORE Phase 5
Phase 5 FoF read (L1789)                 ← AFTER Phase 4.5
```

---

## AC2: 日次ETL ALM選出コスト見積もり

### Phase 3.7 事前計算コスト（fullrecalculate起動時）

| パラメータ | 値 |
|-----------|-----|
| 候補lookback数 | 24 (candidate_lookbacks=[1..24]) |
| 1 PF既存Phase 3.7コスト | ~0.05-0.1s/PF（30 PF × ~480s÷合計 ≈ 参考値） |
| ALM 1 PF追加コスト | 24× momentum計算 ≈ 1-3s/ALM PF |
| 全体480sに対する割合 | <0.7%/ALM PF |

追加メモリ: `alm_vectorized_signals` 1 ALM PF → 24 lb × 6500 date × (str signal ~10B) ≈ **1.6MB/ALM PF**

### Phase 4 日次ループコスト

- 月初以外: **追加コストゼロ** (alm_selected_lookbacks dict からO(1)参照)
- 月初リバランス時のみ:
  - DBクエリ: `SELECT year_month, monthly_return FROM monthly_returns WHERE portfolio_id=? ORDER BY year_month DESC LIMIT {is_window}` → **1クエリ/ALM PF** (36行)
  - 計算: O(candidate_lookbacks × is_window) = O(24×36) = O(864) float演算 → **<1ms**
  - 頻度: **月1回** (is_reb_month条件)

### クエリ行数詳細

`_build_alm_monthly_returns_cache(db, alm_pf_ids)`:
- SELECT monthly_return WHERE portfolio_id IN (...) ORDER BY year_month → 1クエリ、最大 `len(alm_pf_ids) × 183行`
- ALM PF 1-3体想定: 183-549行 → **軽微**

---

## AC3: Phase 3.7 関数化設計

### 現状

Phase 3.7 (L1039-L1332) は 293行のインラインブロック。
関数境界なし・ローカル変数 15種以上を内部で生成。

### 関数化設計

#### シグネチャ案

```python
def _compute_phase37_vectorized_signals(
    pipeline_cfg_cache: Dict[str, PipelineConfig],
    pipeline_momentum_caches: Dict[str, Dict[str, Any]],
    standard_portfolios: List,
    df_dtb3_raw: pd.DataFrame,
    df_dtb3: pd.DataFrame,
    db,  # PAverageResult query用 (P_BAR_SELECTION PFのみ)
) -> Tuple[
    Dict[str, Dict[date, str]],             # vectorized_pipeline_signals
    Dict[str, Dict[int, Dict[date, str]]],  # alm_vectorized_signals (新)
]:
```

#### 入力変数（外部依存）

| 変数 | 型 | 用途 |
|------|-----|------|
| pipeline_cfg_cache | Dict[str, PipelineConfig] | ALM設定含む全PF設定 |
| pipeline_momentum_caches | Dict[str, Dict] | 事前計算済みmomentum (ALM: `__alm`キー追加) |
| standard_portfolios | List[Portfolio] | PF ID→ ticker対応 |
| df_dtb3_raw | pd.DataFrame | DTB3参照threshold計算 |
| df_dtb3 | pd.DataFrame | フォールバック用 |
| db | Session | PAverageResult取得 (P_BAR_SELECTIONのみ) |

#### 内部変数（関数内で完結）

`_dtb3_ref_memo`, `_dtb3_ref_sk_memo`, `_pbar_cache`, `_pbar_rows`, `_vd`, `_vd_sk`, `_sample_index`

#### 代替案比較

| 案 | 説明 | 工数 | リスク |
|----|------|------|--------|
| **A: 関数化（推奨）** | Phase3.7全体を `_compute_phase37_vectorized_signals()` に抽出、ALMリターンを追加 | M (2h) | 中（293行リファクタ、パラメータ15種） |
| B: インライン拡張 | 既存Phase3.7ループ内にALM分岐追加 | S (1h) | 低（スコープ変更最小）|

**推奨: 案B（インライン拡張）を初回implに採用。**
理由: 関数化は293行リファクタリスクを伴う。ALMブロック追加後に安定確認してからの関数化が安全。

---

## AC4: impl cmd分割案 + 忍者配分 + 工数見積もり表

### 変更ファイル・行数サマリー

| ファイル | 変更種別 | 追加行数 | 修正行数 |
|---------|---------|---------|---------|
| `schemas/pipeline.py` (137行) | AlmConfig class + フィールド追加 | +17行 | +2行 |
| `recalculate_fast.py` (2271行) | ALM全面組込み | +345行 | +50行 |
| `recalculate_fof.py` (1183行) | Hook A不要 | 0 | 0 |
| `frontend/.../AlmConfigSection.tsx` (新規) | ALM UI コンポーネント | +120行 | — |
| `frontend/.../PortfolioEditor.tsx` (289行) | ALM設定セクション追加 | +30行 | +5行 |
| `tests/test_alm_parity.py` (新規) | ALM parityテスト | +100行 | — |
| `tests/test_alm_select_lookback.py` (新規) | 選出ロジック単体テスト | +80行 | — |
| `tests/test_alm_two_pass_fullrecalc.py` (新規) | 2パスfullrecalc整合性 | +120行 | — |
| `tests/test_alm_daily_etl.py` (新規) | 日次ETL月跨ぎ連続性 | +80行 | — |

### recalculate_fast.py 改修箇所詳細

| 行番号 | 内容 | 追加行数 |
|--------|------|---------|
| L902-L1018 | pipeline_momentum_caches: ALM候補全lb計算 (`block_cache[f"{id}__alm"]`) | +30行 |
| L1046 | `alm_vectorized_signals` 変数宣言 | +2行 |
| L1068-L1332 | Phase 3.7: ALM全候補lbシグナル事前計算ループ | +80行 |
| L1351付近 | `alm_selected_lookbacks` 変数宣言 | +2行 |
| L1499-L1511 | 月初リバランス: ALM選出ロジック挿入 | +30行 |
| L1528-L1533 | シグナル取得: ALM対応分岐 | +15行 |
| L1763前 | 2パス判定ブロック + signal_cache_opt6再構築 | +75行 |
| 新関数 `_select_alm_lookback()` | 月初ALM選出 | +50行 |
| 新関数 `_compute_alm_is_metrics()` | IS窓メトリクス計算 | +40行 |
| 新関数 `_build_alm_monthly_returns_cache()` | monthly_returns DB読取 | +21行 |
| **合計** | | **+345行** |

### 推奨 cmd 分割

```
cmd_A ─── cmd_B ─── cmd_C ─── cmd_D ─── cmd_E ─── cmd_G
            \                              ↑
             (cmd_A完了後 並列)         cmd_F─┘
```

| cmd | 内容 | 対象ファイル | 担当忍者数 | 規模 | 工数目安 |
|-----|------|-------------|-----------|------|---------|
| **A** | schemas/pipeline.py: AlmConfig class + PipelineConfig拡張 | pipeline.py | 1 | S | 0.5h |
| **B** | pipeline_momentum_caches ALM拡張 (L902-L1018) | recalculate_fast.py | 1 | S | 1h |
| **C** | Phase 3.7 ALM全候補lb事前計算 (L1039-L1332 inline拡張) | recalculate_fast.py | 1 | M | 2h |
| **D** | Phase 4 月初ALM選出 + シグナル分岐 + 3新関数 (L1499/L1528/新関数) | recalculate_fast.py | 1 | M | 2h |
| **E** | 2パス判定ブロック + signal_cache_opt6再構築 (L1763前) | recalculate_fast.py | 1 | L | 3h |
| **F** | FE Admin UI: AlmConfigSection.tsx + PortfolioEditor.tsx | frontend/ | 1 | M | 2h |
| **G** | テスト4本 (parity/select/two-pass/etl) | tests/ | 1 | M | 2h |

**依存関係制約**:
- B → cmd_A完了必須（AlmConfig型参照）
- C → cmd_B完了必須（`block_cache[f"{id}__alm"]`参照）
- D → cmd_C完了必須（`alm_vectorized_signals`参照）
- E → cmd_D完了必須（`_select_alm_lookback()`参照）
- F → cmd_A完了後に並列投入可（BEと独立）
- G → cmd_E完了必須（2パス含む全機能が対象）

**並列投入可能**:
- cmd_A + cmd_F は同時投入可（A=BE schemas, F=FE）
- クリティカルパス: A→B→C→D→E→G = **6 cmd逐次**

### 工数合計

| フェーズ | cmd | 工数 |
|---------|-----|------|
| BE基盤 | A+B | 1.5h |
| BE コア計算 | C+D | 4h |
| BE 2パス | E | 3h |
| FE | F | 2h |
| テスト | G | 2h |
| **合計** | A-G | **12.5h** |

並列化（A‖F後→B→C→D→E→G）でのウォールタイム: **約10.5h**

---

## 関連ファイル（参照）

- 設計詳細: `docs/research/cmd_1750_alm_design.md`
- 対象コード: `backend/app/jobs/recalculate_fast.py` (L902-L1018, L1039-L1332, L1499-L1533, L1763前)
- スキーマ: `backend/app/schemas/pipeline.py` (L69: PipelineConfig)
