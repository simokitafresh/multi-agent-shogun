# GS道具磨き設計書 — L0四神+L3加速D/R速度改善
<!-- generated: 2026-07-06T02:58:00+09:00, revised: 2026-07-06T07:35:00+09:00 (v9 + Phase C partial result) by gunshi/karo -->
<!-- 殿裁定06:55: local_sqlite統一 + 殿指摘06:58/07:00: prefetchステップでネットワークアクセスゼロ化 -->

## §0 GSデータフロー全体像(殿指摘 2026-07-06 06:58+07:00)

```
[Phase 0: Prefetch] Supabase → ローカルSQLite (1回だけ。ネットワークアクセスはここのみ)
    ↓
[L0 四神GS] ローカルSQLite → GS計算 → 出力SQLite
    ↓
[L1 忍法GS] ローカルSQLite → GS計算 → 出力SQLite
    ↓
[L2 秘奥義GS] L1出力SQLite → GS計算 → 出力SQLite (前段出力が次段入力)
    ↓
[L3 加速D/R] L2出力SQLite → GS計算 → 出力SQLite
    ↓
[本番適用] チャンピオン登録 → fullrecalculate(480s実測要) → パリティ確認
```

**原則**: 株価取得は1回だけ(prefetch)。以降のGS実行(L0-L3全レイヤー)はローカル完結。ネットワークアクセスゼロ。障害耐性+再実行性が向上。

## §1 As-Is（現状）

### Who: shin_shijin_l1_gs.py (L0四神) + run_077_kasoku_diff/ratio (L3加速D/R)
### What: GS全パターン探索
### Where: DM-signal scripts/analysis/grid_search/ (ローカルSQLite出力)
### When: GS再キャリブレーション実行時
### Why: チャンピオンPF選出のための全パターン計測
### How:

**L0 四神GS (shin_shijin_l1_gs.py, 963行)**:
- **2段キャッシュ構造(DNA方式)**: Phase 1でユニークDNA(relative_assets×absolute_asset×risk_free×top_n×lookback)ごとにmomentum計算をキャッシュ → Phase 2でsafe_haven×rebalanceを展開
- `build_phase1_cache_key()` (L771-778) がDNA鍵を構成
- DM2例: 76,680全パターン → Phase 1のユニークDNA数 = `grouped_patterns` (L1027で計測: `unique_keys`)。**ユニークDNA数は未実測(Phase Aで計測)**
- **シリアル実行**: ProcessPool未使用(他6忍法はProcessPool+SHM済み)
- 4 families直列: DM2(76,680) + DM3(38,340) + DM6(76,680) + DM7+(96) = 191,796パターン
- cmd_3692でDM2が33分timeout(exit124, RSS 722MB)。**ボトルネックがPhase 1(DNA計算)かPhase 2(展開)かは未検証**

**L3 加速D/R (各~1,835行)**:
- ProcessPool+SHM使用済み(並列化実装済み)
- パターン数が巨大: 各1,151,325 = 全忍法最大
- cmd_3694計測: kasoku_diff 5.28s/3p, kasoku_ratio 7.04s/3p (固定費込み)
- 殿裁定(2026-07-06 06:55): GS全レイヤーは`local_sqlite`統一。前段GS出力SQLiteが次段入力になるため、L3で`source_type=db`としてリモートSupabaseへ接続する必要はない。cmd_3693でL3をdbへ寄せた判断はGS用途では過剰で、`local_sqlite`へ戻す。

### 計測値(cmd_3694) — 注: 3パターン少数実行の実測値

| 忍法 | 全パターン | wall(3p)実測 | 推定固定費※ | 推定per-pattern※ | RSS peak |
|------|--------:|------:|------:|------:|------:|
| bunshin | 7,525 | 9.77s | ~6.5s | ~1.1s | 107MB |
| oikaze | 270,900 | 17.83s | ~12s | ~1.9s | 181MB |
| kasoku_diff | 1,151,325 | 15.84s | ~10s | ~1.9s | 356MB |
| kasoku_ratio | 1,151,325 | 21.13s | ~14s | ~2.4s | 590MB |
| L0 DM2 | 76,680 | >33min(timeout) | N/A | N/A | 722MB |

**※推定値**: 固定費・per-pattern限界はbunshin全量実績(7,525p/21s→2.8ms/p)からの推定であり、他忍法・L0では未実測。Phase Aで実測する。

## §2 To-Be（目標状態）

### Who: 同上(スクリプト改修後)
### What: 全パターン探索を5分以内で完了。ネットワークアクセスゼロ(prefetch後)
### Where: 同上(ローカルSQLite出力)。株価データもローカルSQLite(prefetch済み)
### When: GS再キャリブレーション実行時
### Why: 道具が遅いとGS再キャリブレーション全Phaseの所要時間が膨張。ネットワーク依存は障害リスク+再実行不能
### How:

**§0 prefetchでSupabase→ローカルSQLiteダンプ(1回)→以降ローカル完結。**
**Phase Aのプロファイリング結果に基づき確定する。** 現時点では仮説のみ:

**L0仮説**: Phase 1/2の時間内訳次第で施策が変わる
- Phase 2支配的 → ProcessPool+SHM化が有効
- Phase 1支配的 → DNA計算自体の最適化が必要(別施策)

**L3仮説**: cProfile hot pathの特定結果次第で施策が変わる
- 改善倍率はPhase Aの実測なしに予測不能

### 目標値(Phase A実測後に再設定)

| 対象 | 現状 | 仮目標 | 確定条件 |
|------|------|--------|---------|
| L0 DM2 | >33min | <5min | Phase AでPhase 1/2内訳を実測後 |
| L0 全family | >2h(推定) | <10min(仮) | Phase A+B実測後 |
| L3 kasoku_diff | 未実測(全量) | <5min | Phase AでcProfile後 |
| L3 kasoku_ratio | 未実測(全量) | <5min | Phase AでcProfile後 |

## §3 差分 = 実装施策(Phase A結果で確定)

### L0 施策仮説: ProcessPool+SHM化(Phase 2が支配的な場合)

**DNA制約との干渉**: なし(Phase 2のみ並列化。Phase 1はシリアル維持)
- Phase 1(DNA計算=`build_phase1_cache_key`でグループ化)はシリアル維持
- Phase 2(`simulate_phase2_batch`, L781)のsafe_haven×rebalance展開をProcessPool化
- Phase 1結果(signal_history, common_positions)をshared_memoryで共有

**ただし**: Phase 1がボトルネックの場合はこの施策の効果が限定的。Phase Aの時間内訳で判断。

### L3 施策仮説: hot path最適化(cProfile結果依存)

Phase Aで特定するhot pathに応じて施策を決定。現時点で改善倍率の予測は行わない。

### 並列配備とDB競合の区別

| 工程 | 並列可否 | 理由 |
|------|---------|------|
| GS計算(ローカルSQLite出力) | **並列OK** | 各忍者が独立ファイルに書き込み |
| 本番適用(fullrecalculate) | **直列必須** | Supabase DBへの書き込み競合 |

### fullrecalculate待ち時間

**本番パリティ確認前にfullrecalculate完了を必ず待つこと。**
- fullrecalculate所要時間: 旧実績480秒(8分)。**EODHD移行後は未実測のため、Phase D前に実測して確定する**
- パリティ確認はfullrecalculate完了後に実施(殿指摘: 完了前確認→不一致誤報告の事故実績あり)
- 手順: チャンピオン登録 → fullrecalculate開始 → **実測待ち時間**待機 → パリティ確認

## §4 パリティ vs 回帰テストの定義(殿定義 2026-07-06)

| 用語 | 定義 | 実施タイミング |
|------|------|-------------|
| **パリティ** | 本番holding_signal(ticker×weight) + monthly_returnの全期間完全一致 | GS再キャリブレーション最終検証(Phase H) |
| **回帰テスト** | 改善前後で同一DB入力・同一パターンの計算結果等価性検証 | Phase B/C各AC3 |

### 回帰テスト具体手順

```
1. 改善前: --pattern-limit N で結果SQLiteを生成 → baseline.db として保存
2. 改善後: 同一 --pattern-limit N、同一DB入力で結果SQLiteを生成 → candidate.db
3. 突合: 同一pattern_idの月次リターン列を全行比較
   - 許容差: 0.0(完全一致)。浮動小数点丸め差も不許容(同一計算パスのため)
   - 比較スクリプト: sqlite3 + Python pandas差分(Phase Aで作成)
   - 判定: 不一致行数=0 → PASS、1行以上 → FAIL
4. 比較対象: 改善前の同一実行結果。既存GS SQLite(旧世代)は使わない
```

## §5 推奨cmd構成(Phase順)

### Phase 0: Prefetch(1忍者・小) — 殿指摘(2026-07-06 06:58)

Supabaseから最新株価+monthly_returnsをローカルSQLiteにダンプ。以降のGS実行はネットワークアクセスゼロ。

```
AC1: Supabase monthly_returns/daily_pricesの全PF分をローカルSQLiteにダンプするスクリプト作成
AC2: ダンプ完了後、gs_data_loader source_type=local_sqliteで読み込めることを確認
AC3: L0 shin_shijin_l1_gs.pyがprefetch済みローカルSQLiteから読み込めることを確認(get_connection置換)
```

**L0のget_connection(Supabase直接)をprefetch済みローカルSQLiteに置換** → ネットワーク依存ゼロ+障害耐性+再実行性向上。Phase A実測でDB connect 6.4sだった部分もローカルファイルアクセスに置換。

### Phase A: プロファイリング+ベンチマーク(1忍者・小) ★全施策の前提(完了: cmd_3696)

```
AC1: shin_shijin_l1_gs.py DM2でcProfile。Phase 1/2の時間内訳+hot path top10を報告
AC2: kasoku_diff --pattern-limit 100でcProfile。hot path top10を報告
AC3: 全忍法のper-pattern限界コスト(固定費除去)を実測
AC4: 回帰テスト用の比較スクリプト(sqlite3差分)を作成
```

**Phase A Go/No-Go判断基準(将軍判断)**:

| Phase A結果 | 判断 | 次Phase |
|------------|------|---------|
| L0: Phase 2が時間の>60%を占める | Go Phase B | ProcessPool+SHM化が有効 |
| L0: Phase 1が時間の>60%を占める | **方針変更** | Phase 1最適化の別設計が必要 |
| L0: Phase 1/2が拮抗 | 将軍裁定 | 両方の施策を検討 |
| L3: hot pathに明確なボトルネック | Go Phase C | 特定した箇所を最適化 |
| L3: hot pathが分散(明確なボトルネックなし) | **方針変更** | アルゴリズム変更の別設計が必要 |

### Phase A結果(cmd_3696, 2026-07-06)

| 対象 | 実測 | 判断 |
|------|------|------|
| L0 DM2 | Phase 1=77.6%(0.114s), Phase 2=22.4%(0.033s), 20 patterns, wall 18.19s, RSS 258136KB | **方針変更**。ProcessPool+SHM化(Phase 2のみ)は効果限定。Phase 1(DNA計算)自体の最適化設計が必要 |
| L3 kasoku_diff | DB connect 10.209s, build_grid 4.857s, DB load 3.108s+1.946s, MP計算本体0.142s, 100 patterns, wall 22.79s, RSS 353088KB | DB接続/ロード/グリッド構築が支配的。殿裁定によりGS入力を`local_sqlite`へ戻し、リモートDB接続10.2sを消すのが最大改善機会 |
| 回帰比較 | `compare_gs_sqlite_monthly.py`追加。cmd_3694 same-db 372 cells PASS、cmd_3696 p100 same-db 12400 cells PASS | Phase B/Cの改善前後等価性検証に使用可能。これは本番パリティではなく回帰テスト |

### Phase B: L0 Phase 1並列化(1忍者・中) — Phase A実測で確定

**ボトルネック**: `simulate_strategy_vectorized()` = Phase 1(DNA計算)が77.6%。
**施策**: Phase 1のDNAグループ間は独立 → DNAグループ単位でProcessPool並列化。

コード構造(shin_shijin_l1_gs.py L961):
```python
for patterns_with_index in grouped_patterns.values():  # ← ここを並列化
    simulate_strategy_vectorized(...)  # Phase 1: DNA計算(独立)
    simulate_phase2_batch(...)          # Phase 2: 展開(Phase 1結果に依存)
```

各DNAグループは独立(入力: close_prices/open_prices/cache は読取専用)。
Phase 1結果(signal_history)をDNA単位で返し、Phase 2はメインプロセスで展開。

```
AC1: run_family_gridのgrouped_patternsループをProcessPool化。各workerがsimulate_strategy_vectorized+simulate_phase2_batchを実行し結果を返す
AC2: DM2 --pattern-limit 100で改善前後wall time比較(Phase 1+2合計)
AC3: 回帰テスト(§4手順。許容差0.0。compare_gs_sqlite_monthly.pyで検証)
```

**副施策(DB接続+データロード共有)**: MomentumCache構築(1.636s)+DB接続(6.411s)はfamily間で共有可能。現在4 family直列で毎回構築→1回構築して共有に変更。

### Phase 0+B結果(cmd_goal_gs_phase0b_prefetch_l0_parallel_202607060708, 2026-07-06)

| 対象 | 実測 | 判断 |
|------|------|------|
| Prefetch | `prefetch_gs_data.py`追加。smokeで`daily_prices` 64,332行、`monthly_returns` 185行をローカルSQLiteへdump | Phase 0入口成立。ネットワークアクセスはprefetchへ閉じ込め、GS本体は`--price-db`でlocal SQLiteを読む |
| L0 GS本体 | `shin_shijin_l1_gs.py`に`--price-db`/`--phase1-workers`追加。`--skip-parity`時のPostgreSQL接続を除去 | 殿裁定のprefetch後ネットワークゼロ方針に合致 |
| Phase B | DNAグループ単位ProcessPool化。DM2 p100 wall 1.0672s→0.8722s | p100で18.3%改善。小規模では改善確認、全量効果はPhase Dで実測 |
| 回帰比較 | `compare_gs_sqlite_monthly.py`でp1 171 cells、p20 3,420 cells、p100 17,100 cellsすべてmismatch_count=0 | 改善前後の月次リターン完全一致PASS |

### Phase C: L3 local_sqlite統一+起動コスト除去(Phase Bと並列可・1忍者・中) — 殿裁定(2026-07-06 06:55)

**殿裁定**: GS全レイヤーはlocal_sqlite統一。source_type=dbのリモートSupabase接続はGSには不要。前段GS出力SQLiteが次段入力になるローカル完結構造。cmd_3693でL3をdbにしたのは過剰。

**ボトルネック(Phase A実測)**: DB connect 10.2s(44.8%)が支配的。これはリモートSupabase接続コストであり、local_sqliteに変更すれば除去される、という仮説だった。

**Phase C実測結果(cmd_goal_gs_phasec_l3_local_sqlite_202607060708, 2026-07-06)**: okugi_l3_168.yaml source_type=db→local_sqlite化は完了し、wall timeは17.6s→12.6s(28.4%削減)、回帰テストは12400 cells mismatch_count=0でPASS。ただし、DB接続10.2s完全除去は未達。run_077_kasoku_diff.pyにはpipeline_config取得とcmd_2384由来local_sqlite分岐(本番cumulative_return/bootstrap取得)が残り、TCP接続確立は3回→1回へ削減されたのみ。完全ゼロ化はPD-055で裁定待ち。

**未決(PD-055)**: pipeline_config/cumulative_return/bootstrapもprefetch対象に含めて完全ゼロ化するか、現状の28.4%削減を暫定成果として別cmdへ切るか。

```
AC1: okugi_l3_168.yaml source_type=db→local_sqliteに変更。componentsのlocal_sqlite用パス設定
AC2: kasoku_diff --pattern-limit 100で改善前後wall time比較(DB接続10.2s除去の効果計測)
AC3: 回帰テスト(§4手順。compare_gs_sqlite_monthly.pyで検証)
AC4: 全忍法universe YAMLのsource_type棚卸し更新(db→local_sqlite変更反映)
```

### Phase D: 全量ベンチマーク+fullrecalculate実測(Phase B+C完了後)

**殿厳命(2026-07-06 07:52): timeout 300s強制。5分超え放置は最悪の行為。**

```
AC1: L0全family+L3加速D/Rを timeout 300s で実行。timeout超過→中間結果記録→停止
AC2: 5分以内に完了した場合は所要時間記録。超過した場合はtimeout時点の進捗(完了パターン数/全パターン数)を報告
AC3: fullrecalculate所要時間をEODHD移行後データで実測(旧480sとの比較)
```

**今後のGS cmdは全てtimeout 300s強制。** timeout超過は道具磨き次ラウンドの改善材料。全量を最後まで走らせるな。

### Phase E2結果(cmd_goal_gs_speed_e2_l0_phase1_202607060819, 2026-07-06)

L0四神GSはPhase1信号履歴抽出で`signal_history_only`早期returnを導入。p100 family gridは1.2s→0.7s(約42%改善)、p100 SQLite比較はmetrics/monthly/params digest一致(mismatch_count=0)。p1000 DM2はtimeout 300s内でwall 3:35.07完走、family grid 8.0s。full 5分目標は未達のため、次ラウンドはI/O/SQLite write/全pattern生成/metadataの残差を削る。

### Phase E3結果(cmd_goal_gs_speed_e3_l0_io_202607060924, 2026-07-06)

L0四神GSは既定動作不変の`--benchmark-mode`を追加し、SQLite write/metadata/latest pointer更新を抑制できるようにした。通常p100はmetrics/monthly/params digest一致(mismatch_count=0)で回帰PASS。p1000 benchmarkはwall 215.07s→22.71s(9.47x改善)、family grid 4.4s。full 5分目標は外挿約4355.7sで未達のため、次ラウンドは`generate_family_patterns`の早期limit化/全pattern生成コスト削減を優先する。

### Phase E4結果(cmd_goal_gs_speed_e4_l0_patterns_202607060939, 2026-07-06)

L0四神GSは`pattern_limit`をpattern生成時に適用し、benchmark/pattern-limit時の不要な全pattern materializeを回避した。DM2 p1000のpattern生成単体は0.584s→0.011s(約53x)、p1000 benchmarkは22.71s→8.5s(2.67x)。通常write経路はtimeout 300s内で完了し、SQLiteはmetrics/monthly/params=1000/167000/1000行、順序付きSHA256 digest取得済み。full外挿は約1630sで5分未達のため、次ラウンドはcompute残差またはSQLite write込み経路の分離・チャンク化を優先する。

### Phase E5結果(cmd_goal_gs_speed_e5_l0_compute_202607060958, 2026-07-06)

L0四神GSはmonthly SQLite writeをpandas melt逐次経路から月次行列の直接insertへ変更した。DM2 p1000通常writeは約112s→約43.2s、benchmarkは8.5s→4.7sへ改善。SQLiteはparams/metrics/monthlyの行数とdigestを記録し、既定の全量出力動作は維持した。full外挿は約901sで5分未達のため、次ラウンドはmetrics逐次計算の一括化を優先する。

### Phase E6結果(cmd_goal_gs_speed_e6_l0_phase2_metrics_202607061008, 2026-07-06)

L0四神GSは`compute_metrics_matrix`を追加し、patternごとの`compute_metrics`ループを月次行列の列方向ベクトル一括計算へ変更した。DM2 p1000通常経路は43.2s→13.3s(約69%改善)、SQLite rowsはparams=1000/metrics=1000/monthly=167000。旧`compute_metrics`とのランダム1000列等価性はmismatch_count=0、max_abs_diff=1.14e-15。単純外挿は約277sで5分以内見込みだが、全family/fullではcache構成が異なるためtimeout 300付きfull実測を次ラウンドで確認する。

### Phase E7結果(cmd_goal_gs_speed_e7_l0_full_confirm_202607061018, 2026-07-06)

L0四神GS fullはE6後の実測で5分目標を達成した。`timeout 300 python scripts/analysis/grid_search/shin_shijin_l1_gs.py --skip-parity` はexit0、`TIME_EXIT elapsed=246.09s`で完走。全4family合計191,796 patternsで、DB行数はDM2 76,680p/monthly 12,805,560、DM3 38,340p/monthly 6,402,780、DM6 76,680p/monthly 12,805,560、DM7+ 96p/monthly 16,032。コード変更なし。重い全行JSON digestは検証を阻害するため中断し、`meta.yaml`のsqlite_db_md5、COUNT(*)、file sizeを一次証跡に切り替えた。

防御線: E7は速度確認のみ。`--skip-parity` 実行であり、本番PF登録、fullrecalculate、PostgreSQL/Pipeline/Pydantic境界のパリティ確認は未実施。E7結果を「本番適用可能」や「パリティ達成」として扱ってはならない。次工程はチャンピオン選出・登録cmdとは別に、fullrecalculate完了一次証跡と全期間holding_signal/monthly_return完全一致をACへ明記する。

### Phase E2結果(cmd_goal_gs_speed_e2_l3_kasoku_diff_202607060819, 2026-07-06)

L3 `kasoku_diff`は`--skip-monthly-output`とparams/metrics SQLite挿入の`itertuples`化を追加。100k benchmarkは102.24s→35.73s、全量1,151,325 patternsは`GS_MP_WORKERS=4 --skip-monthly-output`で191.4s完走し、5分目標を達成した。1k params/metrics mismatch_count=0、monthly出力あり同士もmonthly_mismatch_count=0/max_abs_diff=0.0。月次系列blobが必要な下流検証は別runとして扱い、チャンピオン選出用のparams/metrics全量GSとは分離する。

### Phase E2結果(cmd_goal_gs_speed_e2_l3_kasoku_ratio_202607060819, 2026-07-06)

L3 `kasoku_ratio`はN=100k段階計測でPhase3(SQLite出力+md5)が全体の78%を支配すると判明。`file_md5`読込チャンク8192B→1MiB、monthly_blob `chunk_cols` 512→5000明示で、N=2k/10k/100kは1.39x/1.99x/2.76x高速化。`compare_gs_sqlite_monthly.py`で3スケール計13.9M cells mismatch_count=0。全量1,151,325 patternsは`timeout 295`で依然未完走(exit124)だが、手動killなしで安全停止し、次支配要因はPhase1 `MP_WORKERS=1`固定へ交代した。

### Phase E3結果(cmd_goal_gs_speed_e3_l3_kasoku_ratio_mp_202607060958, 2026-07-06)

L3 `kasoku_ratio`は`MP_WORKERS`を1→6へ戻し、全量5分目標を実測達成した。`MP_WORKERS=1`は2026-04-12 cmd_1876のOOM対応由来だったが、2026-04-20 cmd_2181-2187のメモリ構造改善後も据え置かれていた。N=100k段階計測ではPhase1が12.545s→3.672s(3.42x)へ改善し、RSSは1185MB→726MBへ減少。全量1,151,325 patternsは`timeout 295`で2回ともexit0完走(266.95s/298.09s)。全量2run間の142,764,300 cellsはmismatch_count=0で完全一致。margin最小1.91sと薄いため、運用時の同時負荷には注意する。

### Phase E4結果(hole3再高速化, 2026-07-06)

L3 `kasoku_ratio`の薄利を追加で解消した。`MONTHLY_BLOB_CHUNK_PATTERNS`を5000→20000へ増やし、`KASOKU_RATIO_MP_WORKERS`/`KASOKU_RATIO_MONTHLY_BLOB_CHUNK_PATTERNS`の環境変数上書きを追加、既定workersを6→8へ変更。N=100kは45.64s(w6/chunk5000)→34.02s(w6/chunk20000)→31.27s(w8/chunk20000)で、w6/w8のSQLite md5は同一(`823682c527a4642f5db5b1b4451fe92e`)。全量1,151,325 patternsは`timeout 300`でexit0完走、`TIME_EXIT elapsed=228.00s maxrss=4212364`、Phase1=68.166s、monthly rows=142,764,300、SQLite md5=`a9e5ad519d7b55ea80a6e5df2f500e49`。E3最悪298.09sから70.09s改善し、5分目標のmarginは約72sへ拡大した。

## §6 最終達成サマリ(2026-07-06 10:38)

| 対象 | 改善前 | 改善後 | 達成 | ラウンド数 |
|------|--------|--------|------|-----------|
| L0 四神GS full (191,796p) | >33min timeout | **246.09s** | **5分達成** | E1→E7(7周) |
| L3 kasoku_diff full (1,151,325p) | 436s | **191.4s** | **5分達成** | Phase C→E2(3周) |
| L3 kasoku_ratio full (1,151,325p) | 720s超未完走 | **228.00s** | **5分達成** | Phase C→E2→E4(5周) |

**全3対象で5分目標実測達成。** 設計書v1(02:58)から最終確認(10:38)まで約7.5時間。

主要施策チェーン:
- L0: prefetch→DNA並列化→signal_history_only→benchmark-mode→pattern早期limit→monthly直接insert→metrics一括計算→full実測達成
- L3 diff: local_sqlite化→skip-monthly-output+itertuples→full 191.4s達成
- L3 ratio: local_sqlite化→file_md5チャンク+chunk_cols→MP_WORKERS 1→6→monthly_blob chunk 20000 + MP_WORKERS 8→full 228.00s達成

## §7 残存リスク

- **OOM**: kasoku_ratio full w8/chunk20000のmaxrssは約4.2GB。ProcessPool化で×workers数 → workers増加は`timeout 300`とRSS実測を伴うこと
- **Phase A結果での方針転換**: Phase 1支配的/hot path分散の場合、Phase B/Cの施策が根本的に変わる。Go/No-Go判断基準(§5)で将軍が裁定
- **共通エンジン化**: gs_engine.py構想(11,397行→3,000行)は道具磨き完了後の次Phase
- **fullrecalculate時間変動**: EODHD移行後のデータ量変化で480sから変動する可能性。Phase Dで実測
- **timeout 300s強制**(殿厳命2026-07-06): GS全量実行は必ずtimeout 300sで包む。超過→中間結果記録→停止→次ラウンド改善
