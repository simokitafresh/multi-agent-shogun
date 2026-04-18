# cmd_1992 CoDD Refactor Spec — run_077_bunshin.py

<!-- created: 2026-04-16 -->
<!-- cmd: cmd_1992 -->
<!-- worker: tobisaru -->
<!-- target: scripts/analysis/grid_search/run_077_bunshin.py (809 lines) -->

## §1 Before計測 (AC1)

### cProfile結果 (cmd_1987 Phase 2より)

| スコープ | 計測 | 値 |
|---------|------|-----|
| baseline phase (simulate_pattern_baseline × 781) | elapsed | **0.097s** |
| fast phase (simulate_pattern × 781) | elapsed | **0.948s** |
| simulate_pattern cumtime | cProfile | **0.690s** |
| full run total | time | **2.9s** |

補足: 初回cold import計測 (独立実行環境) = **1991ms** (backend.app モジュール群)

### ホットスポット特定

`simulate_pattern` (L444-473) が781回呼ばれるたびに以下を実行:

```python
_pe_root = str(ROOT)           # str変換 × 781
_pe_backend = str(ROOT / "backend")  # Path演算 + str変換 × 781
if _pe_root not in sys.path:   # O(N)リスト探索 × 781
    sys.path.insert(0, _pe_root)
if _pe_backend not in sys.path: # O(N)リスト探索 × 781
    sys.path.insert(0, _pe_backend)
from backend.app.services.pipeline.engine import PipelineEngine       # import × 781
from backend.app.services.pipeline.blocks.equal_weight import EqualWeightBlock  # import × 781
from backend.app.jobs.shared import get_pipeline_block_registry        # import × 781
```

**3つのimportは全て `# noqa: F401` (未使用)。PI-009コンプライアンス確認用。**
fast path overhead = 0.948 - 0.097 = **0.851s** (simulate_pattern_baselineと同一計算で差分がある)

## §2 codd extract結果 (AC1)

extract先: `codd/extracted_gs/modules/run-077-bunshin.md`

| 項目 | 値 |
|------|-----|
| ファイル | run_077_bunshin.py |
| 行数 | 809 |
| Layer | Infrastructure |
| Symbol count | 11 functions |
| Test coverage | 0.0 (0/11) |
| Key hotspot functions | `simulate_pattern`, `simulate_pattern_baseline`, `get_sim_context`, `calc_metrics_fast` |
| External dependencies | backend, numpy, pandas, sqlalchemy, yaml |
| DB dependency | portfolios テーブル (L608) |

## §3 改善方針 (AC2実装設計)

### 根本原因

`simulate_pattern` は 781回呼ばれるが、内部でやっていることは:
1. **一度だけやれば十分な作業** (sys.path設定 + 3 lazy import) を毎回実行
2. 実際の計算は `simulate_pattern_baseline` に委譲するだけ

### Fix設計

モジュールレベルに `_ensure_pipeline_ready()` 関数を追加し、
フラグ `_pipeline_ready` で一度だけ実行を保証する。

```python
# モジュールレベルに追加
_pipeline_ready: bool = False

def _ensure_pipeline_ready() -> None:
    """Pipeline modules を一度だけ lazy import する (PI-009)。"""
    global _pipeline_ready
    if _pipeline_ready:
        return
    _pe_root = str(ROOT)
    _pe_backend = str(ROOT / "backend")
    if _pe_root not in sys.path:
        sys.path.insert(0, _pe_root)
    if _pe_backend not in sys.path:
        sys.path.insert(0, _pe_backend)
    from backend.app.services.pipeline.engine import PipelineEngine  # noqa: F401
    from backend.app.services.pipeline.blocks.equal_weight import EqualWeightBlock  # noqa: F401
    from backend.app.jobs.shared import get_pipeline_block_registry  # noqa: F401
    _pipeline_ready = True

def simulate_pattern(...):
    _ensure_pipeline_ready()  # フラグ確認のみ (2回目以降は即return)
    return simulate_pattern_baseline(...)
```

### 機能変更なし確認

- sys.path設定: 同一の条件チェックを維持
- 3 lazy import: 同一モジュールを最初の1回でロード
- 戻り値: `simulate_pattern_baseline` への委譲は変わらず
- PI-009コンプライアンス: 全モジュールの初回ロードを保証

## §4 期待改善量

| 項目 | before | after (期待) |
|------|--------|-------------|
| simulate_pattern overhead/call | ~1.09ms | ~0.12μs (bool check only) |
| fast phase total | 0.948s | ~0.097s + cold_import |
| 削減量 | — | ~0.85s |

cold_importの初回コスト(~2s独立実行環境)は main() 実行前のサブシステム初期化で
吸収されている可能性が高い(実測: fast path = 0.948s < 初回cold import単体)。

## §5 After計測結果 (AC3)

### before/after overhead 比較 (synthetic benchmark, 781回 warm call)

| 指標 | before | after | 改善 |
|------|--------|-------|------|
| 781回 wrapper overhead mean | 0.622ms | 0.136ms | **-78%, 4.6x** |
| 781回 wrapper overhead min | 0.459ms | 0.025ms | — |
| Cold import (初回, 独立環境) | 2270ms | 変わらず(1回のみ) | — |

### 出力同一性確認

- `simulate_pattern` after fix: `_ensure_pipeline_ready()` → `simulate_pattern_baseline()`
- `simulate_pattern_baseline` の呼び出し引数・戻り値構造に変更なし
- PI-009: 3モジュールのロードは `_ensure_pipeline_ready()` で1回保証済み
- `_pipeline_ready` フラグ確認 = True (warm call後)

### codd measure結果 (AC4)

| 指標 | 値 |
|------|-----|
| Health Score | 0/100 |
| 備考 | pre-existing project状態。本改修とは無関係 |
| extract出力 | `codd/extracted_gs/modules/run-077-bunshin.md` |
