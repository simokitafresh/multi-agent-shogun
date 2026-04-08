<!-- last_updated: 2026-04-09 -->
# 軍師OPT分析状態 (2026-03-29T01:00 cmd_1478反映)

## エグゼクティブサマリー (将軍復帰用)
- **★本番計測: 357.28s** (cmd_1478)。baseline 637.80s→**-44%**。pre-OPT 3566s→10.0x。初回11,818s→**97.0%削減**
- L2=109.47s(30.6%), L3=214.01s(59.9%)。signal=453,663(完全一致)。zero-signal=0。nested FoF回帰解消
- **ボトルネック転換**: L2 trade_perf推定~100-105s(profiling未発火) + L3 daily_loop(67.88s) + L3 mr_gen(55.21s)
- **⚠ trade_perf=0.00s問題**: Phase 5bのprofiling timerが発火しない。次期修正対象
- **次アクション**: trade_perf profiling修正 → 真のボトルネック構造把握 → `context/gunshi-fullrecalc-speed-analysis.md`

## 完了済み

### OPT-1/2 本番TimingData (3 runs)
| Run | Total | L2 (Standard) | L3 (FoF) | Note |
|-----|-------|---------------|----------|------|
| 105031 | 7285.72s | 6015.20s | 1115.23s | Before OPT-1/2 |
| 130535 | 3324.35s | 1854.10s | 1313.56s | After OPT-1/2 (1st) |
| **130758** | **2665.69s** | **1059.40s** | **1524.54s** | After OPT-1/2 (2nd) |

- **L2: 6015s → 1059s (82.4%削減)** — trade_perf: 4627s → 0.73s
- **L3: 1115s → 1524s (Ward FoF追加で増加)**
- WSL2計測: Before 7268s → After 3324.7s (54.2%減)
- **★OPT-A/6/perf_calc push後(cmd_1454実測)**: **260s** (L2=155s, L3=62s)。旧564s→260s = **54%削減**。初回11,818s→260s = **97.8%総削減**
- 全124PFで `monthly_query=0.000s, get_first_bday=0.000s` 確認

### Phase4 perf_calc orphaned code確認
- 実測: 351.34s = Standard PF calc 410sの**85.7%**
- `prev_perf_cache`はループ内のみ。ループ後に参照なし
- `signals_batch`に累積リターン値は含まれない
- `benchmark_cum_cache`はL872で独立構築(Phase4非依存)
- 除去で Standard PF calc: 410s → ~59s

### Trade Perf overhead 789s 内訳
- Signal個別クエリ (124PF × avg 2.6s): ~300s
- FoF signal_cache非共有 (59 FoF重複): ~200s
- Delete/Insert/Commit: ~180s
- Portfolio個別クエリ: ~26s

### FoF monthly_returns_gen 733.96s 内訳 (NEW)
- **FoF全体の55.9%を占める最大ボトルネック**
- Signal per-PFクエリ (monthly_returns.py L63-65): ~150s
- preload_fof_signals_recursive非共有 (L152): ~200s
- month_end_biz_cache per-PFクエリ (L124-135): ~30s
- TickerMonthlyReturn per-PFクエリ (L160-162): ~10s
- expand_portfolio_to_tickers × 月 (L231): ~170s
- DB UPSERT + commit (L348-371): ~170s
- **根因: recalculate_fof.py L224で構築済みsignal_cacheがL964の呼出しに渡されていない**

### OPT-A: FoF momentum_data月中縮小 (cmd_1450 GATE CLEAR)
- db_write: 5.56s/FoF → 2.60s/FoF (**53.3%削減**)
- リバランス日=完全版、月中={skipped:True}最小化
- signals.py weightsフォールバック追加(custom-weight FoF対応)

### 追い風-鉄壁 新知見
Before 236s → After 3.21s (98.6%減)。
FoF recalcがMonthlyReturnを再生成→OPT-2のキャッシュに乗り、229回fallback→2回に激減。
recalc文脈ではOPT-2がSignal=0問題を事実上解決。本番DB問題は残存。

## 実装完了・デプロイ待ち

### OPT-6: FoF monthly_returns_gen キャッシュ共有 (~275s削減, cmd_1452 LGTM)
- 全9変更点実装済み(kotaro)。軍師コードレビューLGTM
- AC3(fullrecalculate完全一致)はデプロイ時に検証(本番DB必要)
- テスト1242件PASS、既存機能への回帰なし
- **設計詳細: `docs/research/gunshi-opt6-fof-monthly-cache-design.md`**

## 作業中

### Phase4 perf_calc除去 (~131s削減, cmd_1449 kagemaru)
- acknowledged状態。recalculate_fast.pyのL1498-1622除去
- ガイド: `docs/research/gunshi-perf-calc-removal-guide.md`

## 実装完了（cmd_1455 push済み・未デプロイ）

### OPT-4/5: Signal+Portfolio一括ロード (cmd_1455, commit 1efce04f)
- Phase 4.5のStandard PFループ前にsignal_cache_opt6/portfolio_preload構築→_generate_monthly_returnsに渡し
- Phase 4.5にOPT-6キャッシュ適用 (183 DB query削減)
- recalculate_fast.py L1651-1679

## 設計済み（未実装）

### OPT-3: fallback business_days (~60s削減) → ✅ 実装済み (cmd_1464, commit cc0830a2)
- `calculate_monthly_return()` にbusiness_days Optional引数追加
- L123: `get_last_rebalance_month_end_business` → pure版に
- L126, L134: `get_month_first_business_day` → pure版に
- 248 fallback × 3 DB queries × ~80ms = ~59.5s節約
- **注記**: cmd仕様はgenerators/monthly_returns.pyと指定→実体はservices/return_calculator.py

## 詳細レポート
- 分析レポート: `docs/research/gunshi-opt12-fullrecalc-analysis.md`
- perf_calc除去ガイド: `docs/research/gunshi-perf-calc-removal-guide.md`
- OPT-6設計書: `docs/research/gunshi-opt6-fof-monthly-cache-design.md`
- **計算マッピング(統合版)**: `docs/research/fullrecalculate-calculation-map.md` [deleted] — 日次+月次の全Phase計算フロー+OPT適用状況+軍師改善提案(cmd_1462)
- 日次計算マッピング: `docs/research/fullrecalculate-daily-calc-map.md` [deleted] (半蔵偵察)
- 月次計算マッピング: `docs/research/fullrecalculate-monthly-calc-map.md` [deleted] (才蔵偵察)

## デプロイ準備 (将軍cmd起票用)

### cmd候補: OPT-6 commit+push+本番検証
- **commit対象**: `backend/app/jobs/generators/monthly_returns.py`, `backend/app/jobs/recalculate_fof.py`
- **commit msg案**: `perf: share signal/portfolio/month_end_biz caches in FoF monthly_returns (OPT-6)`
- **AC1**: 2ファイルのみステージング → commit → push
- **AC2**: 本番fullrecalculate実行 → L3 monthly_returns_gen計測(512.97s → 推定~238s)
- **AC3**: MonthlyReturn全件が変更前後で完全一致
- **依存**: cmd_1449(perf_calc除去)がrecalculate_fast.pyを変更中。競合なし(別ファイル)

### cmd候補: Phase 4.5 OPT-6適用 (低リスク追加)
- **対象**: `backend/app/jobs/recalculate_fast.py` L1662-1664
- **内容**: Phase 4.5ループ前にmonth_end_biz_cache/benchmark_ticker_returns/portfolio_cacheを構築→渡す
- **推定削減**: 2-5s (183 DB query削減)
- **注意**: cmd_1449がrecalculate_fast.pyを変更中。完了後に実施 or 同時commit
- OPT-6デプロイcmdに同梱 or 独立cmd、将軍判断

## 共有状況
- cmd_1448(OPT-1/2デプロイ): **GATE CLEAR** — 本番118s(L2のみ。全体798s, 89.1%削減)
- cmd_1449(perf_calc除去): kagemaru作業中(AC1/AC2完了、AC3残)
- cmd_1450(OPT-A): **GATE CLEAR** — db_write 53%削減
- cmd_1452(OPT-6): **LGTM** — デプロイ待ち(AC3=デプロイ時検証)
- cmd_1453(知識循環修正): **GATE CLEAR** — PI-016登録+gunshi保存先ルール
- cmd_1454(OPT-A/6/perf_calc push): **★260s実測(54%改善)**。L2=155s,L3=62s。AC3 FAIL(binary_check虚偽)
- cmd_1456(Ward scipy偵察): **★pipeline_exec 626s=anomaly(正常42s)**。キャッシュ効果0%
- cmd_1462(日次/月次マッピング): **LGTM** — Phase別時間分布+計算フロー完全マップ
- cmd_1463(crash-safety 0a/0b): **LGTM** — lifespan WARNING+recalculation_status DB永続化
- cmd_1464(OPT-3 pure版化): **LGTM** — business_days pure版分岐。43テスト全PASS
- cmd_1465(pg_advisory_lock排他): **LGTM** — 2層排他(threading.Lock+pg_advisory_lock)。fail-open設計。テスト15通過
- cmd_1466(全OPT計測): **★637.80s**(pre-OPT 3566s→5.6x)。L3 db_write+L2 trade_perfが新ボトルネック
- cmd_1467(L3 profiling gap偵察): **LGTM** — unmeasured正体=N+1(30-60s)+gc(5-15s)。db_write=signals_flush(80-100s)+component_weights(20-40s)
- cmd_1468(cmd_save ACパスチェック): **LGTM** — cmd_1464教訓の自動化。Check 10追加。65テスト全PASS
- cmd_1469(N+1 query排除): **LGTM** — 軍師提案#1★実装。shared_portfolio_cache活用。300-900個別クエリ→0。計測待ち
- cmd_1470(signals_flush deferred化): **LGTM** — per-FoF UPSERT×59commits→deferred INSERT×1commit+5000/batch。L3 db_write 80-100s→推定20-40s。計測待ち
- cmd_1471(trade_perf偵察): **LGTM** — 142.78s内訳3ボトルネック: load_business_days N+1(21-36s)+fallback calc(14-29s)+per-PF DB write(7-14s)。★del price_cache阻害発見
- cmd_1472(trade_perf N+1+バッチcommit): **LGTM** — Phase 5b前load_business_days 1回→全PF配布+skip_commit+20PFバッチcommit。推定28-50s削減。計測待ち
- cmd_1473(fallback price_cache保持): **LGTM** — del price_cache除去+calculate_monthly_returnにprice_cache引数→has_tickerでmissing tickerのみmerge load。推定14-29s削減。計測待ち
- OPT-12(軍師直接実装): **push済み**(commit 00fd5257) — gc.collect 59→5回(5-12s)+fof_signals dead code除去(1-3s)+profiling改善(dw_component_weights返却+trade_perf外れ値出力)。計測待ち
- cmd_1474(第2サイクル計測): **FAIL** — 380.53s(-40.3%)だが15 nested FoFゼロシグナル(406,988 vs 453,663)。**→OPT-13で修正済み**
- OPT-13(軍師直接実装): **push済み**(commit f3ff64a7) — nested FoF回帰修正。cmd_1470 deferred flushでcomponent FoFシグナルがDB未commit→signal_cacheからDB query補完。再計測必要
- OPT-14(軍師直接実装): **push済み**(commit 79663eda) — Standard PF signals flush cleanup_mode=True化。Phase 0で全Signal DELETE済み→UPSERT不要→INSERT化。推定2-5s削減。Tier 1 #1d
- OPT-15(軍師直接実装): **push済み**(commit 1e3401fd) — component_weights commit集約。per-FoF commit(59回)→10FoFごとcommit(6回)。skip_commitパラメータ追加。推定5-10s削減

## 本番内訳 (run_id=20260328_130758, 2665.69s)

### L2 (1059.40s, 61 Standard PFs)
- trade_perf: **610.24s (57.6%)** — OPT-4/5ターゲット
- perf_calc: **131.35s (12.4%)** — cmd_1449除去ターゲット
- metrics: 64.48s, phase45_mr: 57.13s, rolling_summary: 39.64s
- rolling_chart: 37.05s, drawdown: 24.46s, db_write: 24.27s

### L3 (1524.54s, 31 FoF)
- daily_loop: **636.38s (41.7%)** — pipeline_exec 626.55s (Ward FoF支配)
- monthly_returns_gen: **512.97s (33.6%)** — OPT-6ターゲット
- db_query: 243.25s (16.0%), db_write: 85.96s (signals_flush: 56.41s)
- ⚠ WSL2ではdaily_loop=42.12sだったが本番は636.38s (Ward FoF 15comp×3200日)

## 次期最適化優先順位 (本番データベース・OPT-A/6/perf_calc後の再評価)

| 順位 | 最適化 | 本番推定削減 | 状態 | 累積 |
|------|--------|------------|------|------|
| ~~5~~ | ~~OPT-A (momentum_data縮小)~~ | ~~-45s (L3)~~ | ✅ GATE CLEAR | 2621s |
| ~~3~~ | ~~OPT-6 (FoF MR cache共有)~~ | ~~-275s (L3)~~ | ✅ LGTM(デプロイ待) | 2346s |
| ~~2~~ | ~~Phase4 perf_calc除去~~ | ~~-131s (L2)~~ | 🔧 作業中 | 2215s |
| ~~NEW~~ | ~~L3 pipeline_exec (Ward scipy)~~ | ~~-300~500s~~ | ❌ 偵察で否定(正常42s) | — |
| 1 | OPT-4/5 (Trade Perf Signal一括) | -300s (L2) | 設計済み | 1915s |
| 4 | OPT-3 (fallback business_days) | -20s (L2) | ✅ cmd_1464 LGTM | 1895s |
| 4.5 | Phase 4.5 OPT-6適用 | -2~5s (L2) | 設計済み(軍師発見) | 1893~1890s |
| - | **合計** | **-773s** | | **~1893s (29%追加削減)** |

**⚠ 優先順位再転換(cmd_1456偵察)**: pipeline_exec 626sは**リソース競合anomaly**(正常42s)。Ward scipy最適化は不要。L2 trade_perf(610s)が唯一の大型ボトルネック。OPT-4/5が最優先。

## L3 pipeline_exec 偵察結果 (軍師分析 → cmd_1456偵察で更新)

**~~根因: Ward階層クラスタリングの計算量問題~~ → ❌ 否定(cmd_1456飛猿偵察)**

- 626sは**リソース競合anomaly**。同時実行の59 FoF run(3324s)と並走し全指標8-15x低速
- **正常時: pipeline_exec=42s** (59 FoFs, Ward ~280ms/call × 150リバランス)
- Ward FoF=**1体のみ**(旧忍法-Ward)。cross-FoFキャッシュ効果=0%
- same-FoF月間キャッシュも月窓シフトで効果=0%
- **Ward計算自体は十分高速。scipy最適化は不要**

Ward計算フロー(参考):
1. 相関行列計算(15comp×36month窓) → Lopez de Prado距離d=sqrt(0.5*(1-rho))
2. scipy linkage(condensed, method='ward')
3. fcluster(Z, t=5, criterion='maxclust')

**結論**: pipeline_exec最適化は投資対効果なし。L3最大ボトルネックはmonthly_returns_gen(正常127s, OPT-6で対処予定)。

## Phase 4.5 Standard PF 未適用OPT-6 (軍師発見)

recalculate_fast.py L1664: _generate_monthly_returns()にOPT-6キャッシュ未渡し
- 61 Standard PF × 3 DB queries(signal/month_end_biz/portfolio) = **183回の不要クエリ**
- 推定削減: **2-5s** (FoF比で小さいが低リスク。OPT-6デプロイcmdに同梱可能)
- FoFパスでは渡している(L1040-1047)のにStandard PFパスでは漏れ

Before: 7285s → OPT-1/2後: 2665s → OPT-A後: 2621s → OPT-6後(推定): **~2346s** → 全OPT後: **~1895s (74.0%総削減)**
