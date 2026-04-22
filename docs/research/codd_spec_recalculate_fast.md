# CoDD Refactor Spec — recalculate_fast.py

<!-- created: 2026-04-23 -->
<!-- cmd: cmd_2245 -->
<!-- worker: hanzo (観点A) -->
<!-- target: backend/app/jobs/recalculate_fast.py (3048 lines) -->

## §1 Phase1 実測値 (cmd_2233 偵察, recalculation_timings run_id=20260422_073701)

| Layer | 所要時間 | 割合 | 備考 |
|-------|---------|------|------|
| **L2_portfolio** | **2382s (39.7分)** | **60.1%** | ★最大ボトルネック。Phase4+4.5+メトリクス生成含む |
| **L3_fof** | **1151s (19.2分)** | **29.1%** | 109 FoF全期間再計算 |
| Other (startup/exit等) | ~270s (4.5分) | 6.8% | Phase0-2前処理含む |
| **recalculate_history_fast 合計** | **3803s (63.4分)** | **96.2%** | daily_etl全体(3955s)の96% |

直近成功job: `job-d7k7k1cm0tmc73acvga0` (2026-04-22, Render logs)

---

## §2 codd extract 結果 (静的解析)

**実行:** `codd extract --path . --source-dirs src` (sandbox: codd_cmd_2245_sandbox/)
**検出:** 1 modules, 1 files, 3048 lines

静的解析(Python)では**トップレベルシンボル2件のみ検出**（RecalculateMode + log_memory_usage）。
モジュールレベル関数群は型アノテーション付きだが、coddの静的ASTパーサーで捕捉されなかった。

> **注記:** codd extractの静的解析は3048行の関数構造を十分に捉えられなかった。
> 本specの§3以降は手動コード読解（grep + Read）による補完。

| 項目 | 値 |
|------|-----|
| 検出モジュール | recalculate_fast |
| 検出シンボル | 2 (RecalculateMode, log_memory_usage) |
| 実際のトップレベル関数 | 33+ (grep結果) |
| 外部依存 | gc, numpy, pandas, psutil, sqlalchemy |
| テストカバレッジ (codd) | 0.0 |

---

## §3 モジュール構造 (手動コード読解)

### 3.1 トップレベル関数・クラス一覧

| 行 | 名前 | 種別 | 用途 |
|----|------|------|------|
| L126 | `log_memory_usage` | func | psutilメモリ計測 |
| L142 | `RecalculateMode` | class(StrEnum) | FULL/TICKER/PORTFOLIO enum |
| L165 | `_extract_alm_config` | func | pipeline_configからALM設定抽出 |
| L187 | `_extract_alm_candidate_months` | func | ALM候補月リスト取得 |
| L212 | `_normalize_alm_objective` | func | ALM目的関数正規化 |
| L227 | `_alm_objective_is_minimized` | func | ALM目的関数の最小化判定 |
| L237 | `_subtract_months` | func | 年月減算ユーティリティ |
| L243 | `_compute_max_drawdown` | func | 月次リターンからMaxDD計算 |
| L253 | `_compute_underwater_period` | func | 水面下期間(UWP)計算 |
| L279 | `_compute_alm_score` | func | ALMスコア計算（目的関数別） |
| L326 | `_select_alm_lookback` | func | ALMルックバック期間選択 |
| L368 | `_holding_to_weight_map` | func | holdingシグナル→ウェイトdict変換 |
| L383 | `_lookup_precomputed_momentum_value` | func | 事前計算済みモメンタム値のdict検索 |
| L396 | `_build_alm_structured_momentum_data` | func | ALM構造化モメンタムデータ構築 |
| L471 | `_build_fixed_lookback_signal_rows` | func | 固定ルックバックシグナル行構築 |
| L518 | `_build_candidate_monthly_returns` | func | ALM候補月次リターン計算 |
| L562 | `_build_alm_candidate_monthly_returns_cache` | func | ALM候補月次リターンキャッシュ構築 |
| L605 | `_build_alm_second_pass_signal_rows` | func | ALM第2パスシグナル行構築 |
| L686 | `_reload_signal_cache_entries` | func | DBからシグナルキャッシュ再ロード |
| L707 | `_cleanup_before_recalculate` | func | 再計算前の既存データ削除 |
| L788 | `_load_ticker_daily_returns_from_db` | func | TickerDailyReturnをDBからロード |
| L841 | `_calculate_portfolio_value_at_date` | func | 特定日のポートフォリオ価値計算 |
| L910 | `_calculate_portfolio_value_at_date_both` | func | close+open両方の価値計算 |
| L972 | `_calculate_portfolio_value_fast` | func | 高速ポートフォリオ価値計算 |
| L1035 | `_dict_lookup_with_bisect` | func | bisectを使ったdict高速検索 |
| L1051 | `_compute_pipeline_signals` | func | Phase3.7ベクトル化シグナル計算コア |
| **L1209** | **`recalculate_history_fast`** | **func** | **★メイン関数 (1681行)** |
| L2890 | `_check_signal_integrity` | func | シグナル整合性チェック |
| L2961 | `_collect_all_symbols` | func | 全ポートフォリオのシンボル収集 |
| L2987 | `_normalize_price_cache_ticker` | func | PriceCacheティッカー正規化 |
| L3002 | `_collect_tickers_for_price_cache` | func | PriceCache用ティッカー収集 |

### 3.2 recalculate_history_fast フェーズ構造 (L1209-L2889, 1681行)

```
recalculate_history_fast(start_date, end_date, batch_size, portfolio_ids, mode)
│
├── Phase 0: クリーンアップ (L1374)
│   └── _cleanup_before_recalculate() — MonthlyReturn/DrawdownPeriod等を削除
│
├── Phase 1: データロード (L1382-L1418)  ← ~数秒
│   ├── load_prices_as_df() — 全シンボルの価格データ一括取得
│   └── load_economic_data_as_df() — DTB3ロード
│
├── Phase 1.5: 有効開始日計算 (L1420-L1519)  ← ~秒未満
│   └── batch_query (Price.min_date) — 083k最適化で単一バッチクエリ
│
├── Phase 2: 前処理 (L1520-L1602)  ← ~数秒
│   ├── price_by_symbol分割 (シンボル別DataFrame)
│   ├── _load_ticker_daily_returns_from_db() — TickerDailyReturnキャッシュ
│   ├── PriceCache.load() — Price Ratio計算用キャッシュ
│   ├── build_benchmark_cum_series() — ベンチマーク累積Series
│   ├── PipelineConfig事前バリデーション (最適化5)
│   └── pipeline_momentum_caches構築 (最適化6)
│
├── Phase 3.5: Pipelineブロック事前解決 (L1747)
├── Phase 3.7: ベクトル化シグナル事前計算 (L1762-L1977)  ← 最適化済み
│   └── _compute_pipeline_signals() — 全日付の{date:signal}dict構築
│
├── Phase 3: 状態初期化 (L1982-L2053)
│
├── ★Phase 4: 日次ループ (L2054-L2327)  ← **L2_portfolio主要部: 2382sの大半**
│   └── while current_date <= calc_end_date:
│       └── for portfolio in standard_portfolios:
│           ├── シグナル判定 (OPT-E: O(1) dict lookup)
│           ├── signals_batch.append()
│           └── batch_sizeごとに_flush_batch() → DB UPSERT
│
├── Phase 4.1: 月初signal自動作成 (L2328-L2384)
├── Phase 4.5: 標準PF MonthlyReturn生成 (L2432-L2459)
│   └── for p in standard_portfolios: _generate_monthly_returns()
├── Phase 4.6: ALM第2パス (L2461-L2520)
│
├── ★Phase 5: FoF再計算 (L2528-L2563)  ← **L3_fof: 1151s**
│   └── _recalculate_fof_history(db, fof_portfolios, 2000-01-01, today)
│       ※ 常に全期間再計算 (ウェイト状態未保存のため)
│
├── Phase 5.1+: メトリクステーブル生成 (L2565-L2820)
│   ├── generate_ticker_monthly_returns() [FULL/TICKERモードのみ]
│   ├── _generate_monthly_returns() [各PF]
│   ├── _generate_drawdown_periods()
│   ├── _generate_rolling_returns_summary/chart()
│   ├── _generate_portfolio_metrics()
│   ├── _generate_risk_management_metrics()
│   └── _generate_trade_performance()
│
└── LayerTimer保存 (L2826-L2870)
```

---

## §4 ボトルネック分析

### 4.1 L2_portfolio (2382s = 60.1%) — Phase 4 日次ループ

**計算量:** O(PF × TradingDays) = O(21 PFs × ~6,813 days) ≈ **143,073 iterations**

内部分解:
- `signal_calc`: OPT-E vectorized dict lookupで O(1)。ほぼ無視できる
- `db_write`: `_flush_batch()` BATCH_COMMIT_SIZE間隔のUPSERT。DB round-tripが支配
- `phase45_monthly_returns`: 標準PF全数の MonthlyReturn 逐次生成

**DB書込み規模:**
- Signal行数 = 21 PF × 6,813 days ≈ **143,073行**
- MonthlyReturn行数 = 21 PF × ~300ヶ月 ≈ **6,300行**

### 4.2 L3_fof (1151s = 29.1%) — Phase 5 FoF全期間再計算

**根因:** FoFのウェイト状態(drift-based)が永続化されていない → 毎回 2000-01-01 から全期間再計算 (L2545)

```python
fof_full_start = date(2000, 1, 1)  # 全期間再計算用の開始日 (L2545)
fof_profiling = _recalculate_fof_history(db, fof_portfolios, fof_full_start, ...)
```

**規模:** 109 FoF × 6,813 days × N components(平均3-4, 旧忍法-Wardは15)

参照: `gunshi_daily_etl_bottleneck_20260422.md`:
- fullrecalculate Phase 4.5: 2.1s/PF
- FoF: 17s/体 → 8倍遅い (DB round-trip/体が原因の可能性)

---

## §5 リファクタ候補

### Tier 1: FoFウェイト状態永続化 → 増分計算 (推定効果: 1151s → 100s以下)

**現状:** FoFは毎日 `date(2000, 1, 1)` から全期間再計算 (L2545)
**原因:** drift-based ウェイト計算でウェイト状態を保存していないため、途中再開不可
**改善案:**
1. `recalculate_fof_state` テーブルを追加（最終計算日 + ウェイト状態を保存）
2. 前日のウェイト状態を読み込んで当日分のみ計算 (O(FoF × 1day))

**注意:** drift計算の中断・再開ロジックの実装が複雑。設計書作成後に実装。

### Tier 2: FoF MonthlyReturn バッチ生成 (推定効果: 30%短縮)

**現状:** FoF 1体ごとに MonthlyReturn を逐次生成（_recalculate_fof_history内部）
**改善案:** 全FoFシグナル確定後に MonthlyReturn を一括バッチ生成
**根拠:** gunshi調査: 17s/体 vs 2.1s/PF。DB round-trip/体の回数が原因の可能性

### Tier 3: 旧忍法-Ward 24s の components数最適化

**現状:** Ward FoF = 15 components (他は3-4体)
**改善案:** componentsに比例するためWardの構成変更またはキャッシュ共有

### Tier 4: Phase 4.5 MonthlyReturn 並列化 (推定効果: 10-20%短縮)

**現状:** `for p in standard_portfolios: _generate_monthly_returns()` — 逐次 (L2441-2453)
**改善案:** threadpool/asyncioで並列実行
**リスク:** DB sessionのスレッド安全性確認必要

### Tier 5: signal_flushバッチサイズ最適化

**現状:** `BATCH_COMMIT_SIZE = shared.py` に定義。デフォルト値要確認
**改善案:** バッチサイズを大きくしてDB round-trip回数を削減

---

## §6 CoDD 適用可能性

| 対象 | CoDD適用 | 理由 |
|------|---------|------|
| Phase 4 日次ループ | ✅ 適用可 | Python, IO-bound, 計測済み |
| Phase 5 FoF全期間再計算 | ✅ 適用可 (Tier 1) | 設計変更が必要。CoDD specで安全に設計 |
| Phase 4.5 MonthlyReturn | ✅ 適用可 (Tier 4) | Python並列化パターン |
| Phase 2 前処理 | △ 既最適化 | 083k/OPT-G等の最適化済み |

---

## §7 次アクション推奨

1. **FoFウェイト状態永続化のCoDD spec作成** (Tier 1)
   - spec: FoF状態テーブル設計 + 増分計算ロジック
   - 期待効果: L3_fof 1151s → 100s以下 (90%削減)

2. **FoF MonthlyReturn batch化のCoDD spec作成** (Tier 2)
   - spec: _recalculate_fof_history内の MonthlyReturn生成を最後にまとめる
   - 期待効果: 30-50%短縮 (17s/体 → 2-3s/体へ)

3. **Phase 4 standard PFループのprofiling取得**
   - 本番Renderログで signal_calc / db_write の実測内訳を取得
   - Tier 4 (Phase 4.5並列化) の優先度判断に必要

---

> 参照:
> - `docs/research/codd_etl_cron_bottleneck_20260422.md` — daily_etl前段3ステップ分析 (hanzo, cmd_2233)
> - `docs/research/gunshi_daily_etl_bottleneck_20260422.md` — ボトルネック構造+改善ターゲット (gunshi)
> - `docs/research/gunshi_gs_memory_speed_optimization_20260420.md` — fullrecalculate最適化実績
> - codd extract出力: `codd_cmd_2245_sandbox/codd/extracted/` (DM-signal repo内)
