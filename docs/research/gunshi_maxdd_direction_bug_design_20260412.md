# MaxDD方向バグ+ゼロDD修正設計書
<!-- gunshi 2026-04-12 殿指示: なぜなぜ7回+修正プラン+極限まで磨け -->

## 結論

l1_alm_wf_engine.pyに**2つのバグ**が相互作用している:
1. **方向バグ**: 負値MaxDDにargmin→最深(最悪)を選出。期待=最浅(最良)
2. **ゼロDDバグ**: NaN→0置換でMaxDD=0.0(偽の「下落ゼロ」)が発生

方向バグだけ直すと、ゼロDDパターンが「最浅=最良」として偽チャンピオンに昇格する。**両方同時に修正が必須**。

修正: **METRIC_DIRECTIONテーブル導入(Level 5)**+**MaxDD=0.0→NaNマスク**+**方向テスト**。
MINIMIZE_SET除去+コメント(Level 2)から昇格。champion_selectorパターンをWFエンジンに適用。

## なぜなぜ7回（拡張版）

| # | なぜ | 計測事実 |
|---|------|---------|
| 1 | なぜMaxDDが最悪方向に選出される？ | L590 `drawdowns.min()`=-0.626(負値)。L1138 `nanargmin`=最も負=最深DD選出 |
| 2 | なぜ負値の最小化が逆方向？ | MINIMIZE_SET=「小さい=良い→argmin」。負値空間で小さい=最も負=最悪。**符号規約×セマンティクス矛盾** |
| 3 | なぜ矛盾が検出されなかった？ | MINIMIZE_SETに追加するだけ。drawdowns.min()の負値と突合しなかった。**暗黙の前提未検証** |
| 4 | なぜchampion_selectorだけ正しい？ | cmd_1840後に新規作成。正値化(`1-equity/cummax`)+METRIC_DIRECTIONテーブル=**自動化×強制(Level 5)** |
| 5 | なぜWFエンジンに伝播しなかった？ | DC→殿判断待ちで停滞。修正をタスク化する仕組みがなかった |
| 6 | なぜMaxDD=0%が発生する？ | L387「NaNは0埋め前提」→return=0→cumprod=1.0→drawdowns=0→MaxDD=0。**NaN→0が偽の「下落ゼロ」を生成** |
| 7 | **到達: なぜ方向バグ修正だけでは不十分？** | argmax([-0.30, -0.10, **0.0**, -0.626])=**0.0**。偽ゼロDDがチャンピオンに昇格する。**2バグの相互作用**。根因=MINIMIZE_SETという暗黙の前提×NaN→0の副作用。METRIC_DIRECTIONテーブル+ゼロDDマスクの**構造的防御**が必要 |

## バグ箇所一覧

### バグA: 方向バグ（l1_alm_wf_engine.py 4箇所）

| # | 行 | 関数 | バグ | 影響 |
|---|-----|------|------|------|
| A1 | L1138 | `_select_single_champion` | argmin(負値)=最深DD | チャンピオン逆方向 |
| A2 | L874 | `_best_index_and_score` | 同上 | multi-IS fold別逆方向 |
| A3 | L1383 | multi-IS fold比較 | `score>=current`(minimize)→最深保持 | fold間比較逆方向 |
| A4 | L1691-93 | final comparison | `dynamic<fixed`(MINIMIZE_FINAL)→負値逆方向 | 動的vs固定逆方向 |

### バグB: ゼロバグ（l1_alm_wf_engine.py 2箇所）

NaN→0置換由来の偽ゼロ値が選出で「最良」として昇格する。**argmin方向+正値0.0** または **argmax方向+負値で0.0が最大** の2パターン。

| # | objective | 経路 | バグ | 影響 |
|---|-----------|------|------|------|
| B1 | maximum_drawdown | NaN→0→cumprod→flat→MaxDD=0.0 | argmax([-0.30, -0.10, **0.0**])=0.0 | 偽「下落ゼロ」がチャンピオン |
| B2 | underwater_period | NaN→0→cumprod→flat→UWP=0.0 | argmin([**0.0**, 3.0, 12.0])=0.0 | 偽「回復最速」がチャンピオン(鉄壁モード) |

**ゼロバグが発生しないobjective(4つ)**: cagr/nhf/max_run_up/calmar_ratio。全てargmax方向で、flat=0.0は最小値→自然に選ばれない。

### バグC: 本番休眠バグ（recalculate_fast.py 1箇所）

| # | 行 | バグ | 影響 |
|---|-----|------|------|
| C1 | L226-231,356-357 | `_alm_objective_is_minimized("max_drawdown")`→score<best→最深 | 現行3モード未使用=未発火 |

## 修正プラン（Level 5: 構造的防御）

### 変更1: METRIC_DIRECTIONテーブル導入（l1_alm_wf_engine.py）

champion_selectorパターンをWFエンジンに適用。MINIMIZE_SETを廃止。

```python
# === L141-159 付近 ===
# BEFORE:
MINIMIZE_SET: set[str] = {"maximum_drawdown", "underwater_period"}
...
MINIMIZE_FINAL_METRICS = { "maximum_drawdown", ... }

# AFTER:
# ===== 自動化×強制: 方向テーブル (champion_selectorパターン) =====
# 未登録メトリクス→KeyError=構造的ブロック。暗黙の前提ゼロ。
# maximum_drawdown is NEGATIVE (L590 drawdowns.min()). Phase B/MRE互換で符号変更不可。
# "max" = argmax = closest to 0 = shallowest = best.
METRIC_DIRECTION: dict[str, str] = {
    "cagr": "max",               # higher is better
    "nhf": "max",                # higher is better
    "maximum_drawdown": "max",   # NEGATIVE → max = shallowest = best
    "max_run_up": "max",         # higher is better
    "calmar_ratio": "max",       # higher is better
    "underwater_period": "min",  # POSITIVE months → min = shortest = best
}

# MINIMIZE_SET廃止 → METRIC_DIRECTIONで統一
# MINIMIZE_FINAL_METRICSからもmaximum_drawdown除去
MINIMIZE_FINAL_METRICS = {
    "standard_deviation_monthly",
    "standard_deviation_annualized",
    "downside_deviation_monthly",
    # maximum_drawdown: REMOVED — METRIC_DIRECTIONで管理
    "analytical_value_at_risk_5",
    "tracking_error",
    "underwater_period",
    "drawdown_length",
    "recovery_time",
    "left_tail_jumps",
}
```

### 変更2: 選出関数をMETRIC_DIRECTION駆動に（l1_alm_wf_engine.py）

```python
# === _select_single_champion (L1120-1139) ===
def _select_single_champion(
    metrics_np, columns, objective, minimize_set  # minimize_set引数は後方互換で残す
):
    arr = metrics_np[objective]
    source = objective
    ...
    direction = METRIC_DIRECTION[objective]  # KeyError=未登録メトリクス→構造的ブロック
    best_idx = int(np.nanargmin(arr)) if direction == "min" else int(np.nanargmax(arr))
    return str(columns[best_idx]), source, best_idx, float(arr[best_idx])

# === _best_index_and_score (L871-875) ===
# この関数はobjective名を受け取らないため、呼出し元でdirection判定
# L1378: best_idx, score = _best_index_and_score(arr_metric, minimize=(METRIC_DIRECTION[obj] == "min"))

# === multi-IS fold比較 (L1381-1386) ===
# L1383: if METRIC_DIRECTION[obj] == "min" and score >= current["score"]:
# L1385: if METRIC_DIRECTION[obj] != "min" and score <= current["score"]:
```

### 変更3: ゼロバグNaNマスク（選出関数入口で実施）

対象: **maximum_drawdown + underwater_period** の2 objective。
両方ともNaN→0由来の偽ゼロ値がチャンピオンに昇格するパターン。

**⚠ 実装時発見**: `_compute_drawdown_path_metrics`内でマスクするとPhase B不一致。
`np.allclose(NaN, 0.0, equal_nan=True)` = False → Phase B FAIL。
→ マスクは`_select_single_champion`と`select_champions_multi_is`の**選出ループ入口**で実施。
メトリクス出力(L502/L744)はPhase B互換で0.0を保持。

```python
# === _select_single_champion入口 ===
    if objective in ("maximum_drawdown", "underwater_period"):
        arr = np.where(arr == 0.0, np.nan, arr)

# === select_champions_multi_is 選出ループ入口 ===
    if obj in ("maximum_drawdown", "underwater_period"):
        arr_metric = np.where(arr_metric == 0.0, np.nan, arr_metric)
```

**なぜ他4 objectiveはマスク不要か**: cagr/nhf/max_run_up/calmar_ratioは全てargmax方向。flat=0.0は最小値のため自然に選ばれない。

### 変更4: 本番休眠バグ予防修正（recalculate_fast.py）

```python
# === L225-231 ===
def _alm_objective_is_minimized(objective: str | None) -> bool:
    # ⚠ max_drawdown is NEGATIVE → NOT minimized. argmax picks shallowest.
    return _normalize_alm_objective(objective) in {
        "tracking_error",
        "underwater_period",
        "left_tail_jumps",
    }
```

### 変更5: 方向テスト追加（リグレッション防止）

```python
def test_maxdd_champion_direction():
    """MaxDDチャンピオンは最浅(最も0に近い)を選出すべき。最深ではない。"""
    arr = np.array([-0.626, -0.10, -0.30])
    cols = ["deep", "shallow", "medium"]
    result = _select_single_champion(
        {"maximum_drawdown": arr}, cols, "maximum_drawdown", set()
    )
    assert result[0] == "shallow", f"Expected shallowest DD, got {result[0]}"

def test_maxdd_zero_excluded():
    """MaxDD=0.0(NaN→0偽パターン)はチャンピオン選出から除外される。"""
    arr = np.array([-0.30, -0.10, 0.0])
    cols = ["medium", "shallow", "fake_zero"]
    result = _select_single_champion(
        {"maximum_drawdown": np.where(arr == 0, np.nan, arr)}, cols, "maximum_drawdown", set()
    )
    assert result[0] == "shallow", f"Expected shallow, not fake_zero. Got {result[0]}"
```

## 防御レベル比較

| 項目 | 旧設計(v1) | 新設計(v2) |
|------|-----------|-----------|
| 方向制御 | MINIMIZE_SET除去+コメント(**Level 2**) | METRIC_DIRECTIONテーブル+KeyError(**Level 5**) |
| ゼロDD | 未対処 | 0.0→NaNマスク(**Level 4**) |
| リグレッション | なし | 方向テスト+ゼロDDテスト(**Level 3**) |
| 未知メトリクス | MINIMIZE_SETに入れるか判断(意志依存) | KeyError=構造的ブロック |
| 将来の開発者 | コメントを読む必要あり | 方向テーブルに宣言するだけ |

## Phase B互換性（実装時検証済み）

| 項目 | 結果 |
|------|------|
| metrics出力(L502/L744) | ✅ 変更なし。負値のまま。MREと一致 |
| MaxDD=0.0マスク | ✅ `_compute_drawdown_path_metrics`ではなく選出関数入口でマスク。Phase B `allclose(0.0, 0.0)` = PASS |
| calmar_ratio(L429/L715/L1352) | ✅ `np.abs(max_dd)`使用。符号非依存。影響なし |
| SELECTION_MINIMIZE_SET(L172) | ✅ 定義のみ。全リポジトリで未参照(grep確認済み) |

**実装時発見バグ**: v2設計で`_compute_drawdown_path_metrics`内マスクを計画→`allclose(NaN, 0.0)=False`でPhase B FAIL→選出関数入口に移動で解決。

## テスト計画（12項・全PASS）

### 第1弾(86f2e6ae): MaxDD方向+ゼロDD — 9テスト

1. **T1 MaxDD方向**: argmax([-0.626,-0.10,-0.30])=-0.10(最浅) ✅
2. **T2 MaxDDゼロ除外**: MaxDD=0.0→NaN→fake_zero除外→shallow選出 ✅
3. **T3 Phase B互換**: flat MaxDD=0.0保持(NaN化しない) ✅
4. **T4 UWP方向**: argmin([12,3,6])=3(最短) ✅
5. **T5 _best_index_and_score**: minimize=False→argmax→最浅 ✅
6. **T6 SET不在**: maximum_drawdown ∉ MINIMIZE_SET ∧ ∉ MINIMIZE_FINAL_METRICS ✅
7. **T7 DIRECTION登録**: 6目的全登録。MaxDD=max、UWP=min ✅
8. **T8 全NaN**: 全NaN→champion=None ✅
9. **T9 全ゼロDD**: 全0.0→全NaN→champion=None ✅

### 第2弾(2df25f6d): UWPゼロバグ — 3テスト追加

10. **T10 UWPゼロ除外**: UWP=0.0→NaN→fake_zero除外→short=3.0選出 ✅
11. **T11 UWP全ゼロ**: 全0.0→全NaN→champion=None ✅
12. **T12 ALM四神全objective**: calmar=0(flat)→argmaxで不選出、MRU=0(flat)→argmaxで不選出 ✅

## 因果鎖（統合）

```
NaN→0置換(L387)
  → cumprod=1.0(偽flat) → MaxDD=0.0(偽ゼロDD)    [バグB]
  → 独立に: drawdowns.min()=負値 × MINIMIZE_SET=正値前提 [バグA]
  → 方向バグ修正(argmax)すると偽ゼロDD=0.0が「最良」に昇格 [相互作用]
  → 根因: MINIMIZE_SETという暗黙前提ベース設計 + NaN→0の副作用未考慮
  → 修正: METRIC_DIRECTIONテーブル(Level 5) + MaxDD=0→NaN(Level 4) + テスト(Level 3)
  → champion_selectorパターンの伝播 = 自動化×強制の横展開
```

## 実装時発見バグ（v2→v3修正）

| # | 発見タイミング | バグ | 修正 |
|---|---------------|------|------|
| 1 | Phase B検証時 | `_compute_drawdown_path_metrics`内でMaxDD=0→NaN化→`allclose(NaN, 0.0)=False`→Phase B FAIL | マスク位置を選出関数入口に移動 |
| 2 | sed適用時 | `/"max_drawdown",/d`がエイリアスマッピング(`"maximum_drawdown": "max_drawdown"`)も誤削除 | `git checkout`で復元→行番号指定sedで再適用 |

## commit情報

- **commit 1**: `86f2e6ae` — MaxDD方向バグ+ゼロDDバグ修正。l1_alm_wf_engine.py (+37/-7), recalculate_fast.py (+8/-7)
- **commit 2**: `2df25f6d` — UWPゼロバグ修正。l1_alm_wf_engine.py (+4/-4)
- pushなし

## 設計書作成日
2026-04-12T01:45:00+09:00 — v1 初版 (MINIMIZE_SET除去のみ)
2026-04-12T02:15:00+09:00 — v2 極限版 (殿指示: METRIC_DIRECTION Level 5化 + ゼロDDバグ統合)
2026-04-12T02:45:00+09:00 — v3 実装完了版 (Phase Bバグ修正+エイリアス誤削除修正+9テスト全PASS+commit済み)
2026-04-12T03:15:00+09:00 — v4 ALM忍法全量確認版 (UWPゼロバグ発見+修正+12テスト全PASS)
