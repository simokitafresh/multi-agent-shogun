<!-- last_updated: 2026-04-09 -->
# GS速度最適化 設計分析

<!-- 軍師分析(2026-04-03)。将軍相談への回答 -->

## §1 現状構造

| スクリプト | 行数 | 共通ライブラリ | 並列化 |
|-----------|------|--------------|--------|
| shin_shijin_l1_gs.py | 963 | grid_search_metrics_v2 | なし(シリアル) |
| run_077_bunshin.py | 805 | なし(EW単体) | なし |
| run_077_oikaze.py | 1304 | 独自実装 | ProcessPool+SHM |
| run_077_nukimi.py | 1677 | 独自実装 | ProcessPool+SHM |
| run_077_kawarimi.py | 1455 | 独自実装 | ProcessPool+SHM |
| run_077_kasoku_diff.py | 1835 | 独自実装 | ProcessPool+SHM |
| run_077_kasoku_ratio.py | 1845 | 独自実装 | ProcessPool+SHM |
| run_077_yotsume.py | 1513 | 独自実装 | ProcessPool+SHM |

**合計11,397行。6/7忍法スクリプトがProcessPool+shared_memory使用済み。**

## §2 相談回答

### (1) 下準備の優先順位

**パリティ基盤 → プロファイリング → ベンチマーク** の順。

理由: 最適化の正しさを検証する道具が先(道具を育てる原則)。プロファイリングなしの最適化は当て推量。

| 順 | 作業 | 成果物 | 所要 |
|----|------|--------|------|
| 1 | **パリティ基盤** | holding_signal dump+diff自動化スクリプト | 1忍者・小 |
| 2 | **プロファイリング** | cProfile/line_profiler結果。1忍法(oikaze推奨:中規模)で | 1忍者・小 |
| 3 | **ベンチマーク** | 現行実行時間の記録(8スクリプト全て) | 1忍者・小 |

### (2) research_engine知見の転用可能性

| 知見 | research_engine効果 | GS転用可能性 | 理由 |
|------|-------------------|------------|------|
| dict lookup (pd.loc→dict) | 43x | **要確認** | GS scriptのhot pathにpd.locが残っていれば効果大。NumPy化済みなら効果薄 |
| JSONキャッシュ (config) | 707x | **有効** | GS scriptは毎回DB configをロード。キャッシュすれば起動が速くなる |
| vectorize | 高速化の主柱 | **部分的** | 6/7が既にProcessPool+SHM。ただしsimulate_pattern内部にループが残っている可能性 |
| preprocess cache | N/A(研究用) | **最大の機会** | GS scriptは各パターンで全計算をやり直す。momentum cache(grid_search_metrics_v2のMomentumCache)の活用度を確認すべき |

**結論**: 低hanging fruitは (a) config JSONキャッシュ (b) hot pathのpd.loc残存チェック (c) momentum cacheの活用度。プロファイリングで特定。

### (3) 忍法7本の共通エンジン化 — **最大の改善機会**

6/7忍法が以下の関数を**独自に再実装**:
```
simulate_pattern / simulate_batch / _worker_init_shm / _process_chunk_fast_shm
_run_mp / calc_metrics_fast / build_monthly_returns_df / write_meta_yaml
append_data_catalog / configure_database_url_from_env / build_grid(構造のみ)
```

**唯一の差分**: selection block(どのmomentum計算を使うか) + grid定義(パラメータ空間)。

提案: `gs_engine.py` を新規作成。共通関数を集約。各忍法スクリプトは:
- `block_simulate(pattern, context)` — block固有のシミュレーション
- `build_grid()` — block固有のパラメータグリッド
の2関数のみ定義。残りはgs_engineからimport。

**効果**: 11,397行 → 推定3,000行(~74%削減)。保守コスト激減。速度最適化が1箇所で全忍法に波及(+1複利)。

### (4) パリティ検証の設計

| 項目 | 方法 |
|------|------|
| **holding_signal突合** | 最適化前後でholding_signal系列をJSON dump → `diff` or pytest assert |
| **自動化** | `gs_parity_check.py`: (a) 本番DB holding_signalロード (b) GS出力のholding_signal (c) 月次一致率100%を検証 |
| **回帰テスト** | 最適化commit前にparity check実行。FAIL→commit阻止(gate化) |
| **参照**: checklist Step1/2のmd5sum手順を`gs_parity_check.py`に内包 |

### (5) 進め方の提案

```
Phase 1: 道具作り（並列可・3忍者）
  ├ (a) パリティ基盤: gs_parity_check.py
  ├ (b) プロファイリング: oikaze 1本でcProfile
  └ (c) ベンチマーク: 8スクリプト現行時間記録

Phase 2: 共通エンジン（直列・1-2忍者）
  └ gs_engine.py抽出 + 1忍法(oikaze)を移行 + パリティ検証

Phase 3: 全忍法移行（並列可・6忍者。ファイル衝突なし）
  └ 残り6忍法をgs_engine.pyに移行 + 各パリティ検証

Phase 4: 速度最適化（Phase 1bのプロファイル結果に基づく）
  └ gs_engine.pyのhot path最適化 → 全忍法に自動波及
```

**Phase 2→3→4が道具を育てる構造**: gs_engine.pyへの最適化が全忍法に波及する。research_engineと同じパターン。

## §3 因果推論

```
現状: 7忍法が独自実装(11,397行) → 最適化が各スクリプト個別 → 1箇所改善しても6箇所に波及しない
改善: gs_engine.py共通化 → 最適化が1箇所で全忍法に波及 → +1点の複利 → パリティ基盤で品質保証
```

---
→ 参照: `context/gs-speedup-knowledge.md`(既存知見), `context/checklist-shin-v2-registration.md`(パリティ手順)
