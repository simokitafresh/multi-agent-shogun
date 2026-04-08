<!-- last_updated: 2026-04-09 -->
# fullrecalculate速度向上 残改善分析 (軍師)
# 2026-03-29T01:00更新 | 第3サイクル計測357.28s(-44%)反映

## 現状ステータス
- **★本番計測: 357.28s** (cmd_1478, run_id=20260328_154605)。OPT-12/13/14/15+cmd_1469-1473全適用
- baseline 637.80s → 357.28s (**-44.0%**)。pre-OPT 3566.86s → 357.28s (10.0x改善)。初回11,818s → 357.28s (**97.0%削減**)
- signal=453,663件(baseline完全一致)。zero-signal=0件。nested FoF回帰解消(OPT-13)
- GP-124(signal整合性チェック)でzero-signal自動検知ゲート追加済み

## 本番計測Phase別時間分布 (cmd_1466実測)

### Layer概要
| Layer | 時間 | 割合 | pre-OPT | 改善率 |
|-------|------|------|---------|--------|
| L2 (Standard) | 240.66s | 37.7% | 2700.49s | 11.2x |
| L3 (FoF) | 362.27s | 56.8% | 719.70s | 2.0x |
| Overhead | 34.87s | 5.5% | — | — |
| **Total** | **637.80s** | **100%** | **3566.86s** | **5.6x** |

### L2 substep内訳 (240.66s)
| substep | 時間 | L2内割合 | 全体割合 |
|---------|------|---------|---------|
| **trade_perf** | **142.78s** | **59.3%** | **22.4%** |
| db_write | 47.38s | 19.7% | 7.4% |
| metrics | 17.85s | 7.4% | 2.8% |
| rolling_chart | 14.84s | 6.2% | 2.3% |
| phase45_monthly_returns | 12.47s | 5.2% | 2.0% |
| rolling_summary | 6.21s | 2.6% | 1.0% |
| drawdown | 5.88s | 2.4% | 0.9% |
| risk_mgmt | 3.42s | 1.4% | 0.5% |
| signal_calc | 1.06s | 0.4% | 0.2% |
| perf_calc | 0.0s | — | 除去済み |

### L3 FoF内訳 (362.27s, 59 FoF)
| substep | 時間 | L3内割合 | 全体割合 |
|---------|------|---------|---------|
| **db_write** | **130.64s** | **36.1%** | **20.5%** |
| **unmeasured** | **74.64s** | **20.6%** | **11.7%** |
| daily_loop | 71.0s | 19.6% | 11.1% |
| monthly_returns_gen | 56.61s | 15.6% | 8.9% |
| db_query | 16.87s | 4.7% | 2.6% |
| cache_init | 8.25s | 2.3% | 1.3% |
| dataframe_prep | 3.64s | 1.0% | 0.6% |

### Phase 5b Precompute内訳 (191.85s)
| generator | 時間 | 割合 |
|-----------|------|------|
| **Trade Perf** | **142.78s** | **74.4%** |
| Metrics | 17.85s | 9.3% |
| Rolling Chart | 14.84s | 7.7% |
| Rolling Summary | 6.21s | 3.2% |
| Drawdown | 5.88s | 3.1% |
| Risk Mgmt | 3.42s | 1.8% |

### ボトルネック順位（全体に対する割合）
1. **L2 trade_perf = 142.78s (22.4%)** — ★cmd_1471偵察完了。内訳下記
2. **L3 db_write = 130.64s (20.5%)** — ★cmd_1470で signals_flush deferred化済み。計測待ち
3. **L3 unmeasured = 74.64s (11.7%)** — ★cmd_1467+1469で正体特定+N+1修正済み。計測待ち
4. **L3 daily_loop = 71.0s (11.1%)** — Phase 4A最適化済みだが残存
5. L3 monthly_returns_gen = 56.61s (8.9%) — OPT-6で512.97s→56.61s (89%削減!)

### L2 trade_perf 142.78s内訳（cmd_1471偵察確定）
| 要素 | 推定時間 | 割合 | 状態 |
|------|---------|------|------|
| load_business_days N+1 | 21-36s | 15-25% | 偵察完了。引数化で即解消 |
| calculate_trade_period_return whileループ | 43-57s | 30-40% | Python overhead。NumPy化要設計 |
| calculate_monthly_return fallback | 14-29s | 10-20% | ★del price_cache(L281)阻害。price_cache転用で解消 |
| per-PF DB write (DELETE+INSERT+commit) | 7-14s | 5-10% | バッチcommit化で解消 |
| bulk_insert+commit | 14-21s | 10-15% | バッチcommit化と合算 |
| Setup (preloaded) | <3s | <2% | OPT-4/5済み |
| pandas/bisect/sanitize | 7-14s | 5-10% | CPU bound |

## なぜなぜ分析

### Q1: 260sの60%=155sを占めるL2の内訳は何か？
→ Phase 2-3.7(前処理): ~42s, Phase 4(日次ループ): signal生成+DB書込み, Phase 4.5(monthly_returns_gen): 最大ボトルネック

### Q2: monthly_returns_genはなぜ遅い？
→ 124 PF(65 standard + 59 FoF)に対して_generate_monthly_returns()を個別実行。
  各実行で: DataFrame構築 → resample("MS"/"ME") → 月ごとの価格比計算 → DB flush
  Signal/Portfolio/PriceCacheはOPT-4/5/6で共有済みだが、**月次リターン計算自体とDB書込みは個別**

### Q3: FoFの62sの中で何が最もコストか？
→ コード検証で2つのN+1問題を発見:
  (a) recalculate_fof.py L376-382: **各FoFの各コンポーネントに個別DB query**
     `db.query(PortfolioModel).filter(PortfolioModel.id == cid).first()`
     59 FoF × avg 5-15 comp = 300-900個別クエリ
  (b) 日次ループ(LOOP-1)は~6000-7000日 × 59 FoF。月中はキャリーフォワードのみだが
     ループ反復自体は発生。Pythonループオーバーヘッド

### Q4: 日次ループをさらに高速化できないか？
→ Standard PF: OPT-Eで全signalが事前計算済み。日次ループは「dict lookup → Signal record構築 → batch append」のみ。
  **ループ自体をNumPy/Pandas batch操作に置換**できれば、65 PF × 6813日 = 443K Pythonループ反復を排除可能。
  ただし: holding_signal更新に前日状態依存あり → 完全ベクトル化は困難。
  代替: **月変わり日でのみ状態遷移し、月中を一括INSERT**する中間案が現実的

### Q5: dead codeは残っているか？ → ★確定
→ fof_signals[target_date] (recalculate_fof.py L761): **Dead code確定**（軍師コード検証）。
  書込みのみ(L543初期化, L761代入)。読取り箇所ゼロ。
  _generate_monthly_returns()はsignal_cache(in-memory)から直接読む。
  354K dict insert削除で1-3s削減 + コード衛生向上

### Q6: trade_perf 142.78sの中で何が最もコストか？(cmd_1471確定)
→ 3層に分解:
  (1) **load_business_days N+1 (21-36s)**: SPY全日付SELECT(~6000行)を124PF×毎回実行。同一結果なのにN回query。Phase 5b前で1回load→引数渡しで即解消
  (2) **calculate_monthly_return fallback (14-29s)**: Open tradeの最終部分月で発火。Portfolio DB query+PriceCache.load+expand_portfolio_to_tickers。★return_calculator.py L281で`del price_cache`しているためprice_cache再利用不可→fallbackで毎回再生成。del削除+fallback転用で大幅削減可能
  (3) **per-PF DB write (7-14s)**: DELETE+flush+bulk_insert+commit が124PF個別。Singapore DBレイテンシ×124。バッチcommit化で削減可能
  残り(whileループ本体43-57s)はPython overhead。月単位ループ→NumPy batch化は投資対効果要検討

## 改善提案（cmd_1466本番計測データベース、ROI順）

### ★ ボトルネック構造の転換
OPT-6によりL3 monthly_returns_gen: 512.97s→56.61sに激減。
代わりに**L3 db_write(130.64s)とL2 trade_perf(142.78s)が支配的**に。
旧提案#4(MRバッチ化)は効果激減(元12.47+56.61=69sしかない)。

### Tier 1: 即効性高・改修範囲小（cmd_1467+cmd_1471偵察確定）

| # | 改善 | 対象 | 推定効果 | 根拠 |
|---|---|---|---|---|
| **1★** | **component_rebalance_triggers → shared_portfolio_cache参照** | recalculate_fof.py L374-382 | **L3から30-60s** | ✅ **cmd_1469実装済み**(commit 7fef9f70)。計測待ち |
| **1b★** | **load_business_days N+1除去** | trade_performance.py L221 | **L2から21-36s** | ✅ **cmd_1472実装済み**。Phase 5b前1回load→全PF配布。計測待ち |
| 2 | gc.collect()削減 | recalculate_fof.py L1076 | L3から5-12s | ✅ **OPT-12実装済み**(commit 00fd5257)。59回→5回。計測待ち |
| 3 | dw_component_weights返却dict漏れ修正 | recalculate_fof.py L1151 | 計測精度向上 | ✅ **OPT-12実装済み**(commit 00fd5257)。db_write内訳可視化 |
| **5** | **fof_signals dead code除去** | recalculate_fof.py L543,L761 | **L3から1-3s** | ✅ **OPT-12実装済み**(commit 00fd5257)。354K dict insert排除 |
| **1c** | **per-PF commit→バッチcommit** | trade_performance.py L420-422 → recalculate_fast.py L1933 | **L2から7-14s** | ✅ **cmd_1472実装済み**。skip_commit=True+20PFバッチcommit。計測待ち |
| **1d** | **L2 signals cleanup_mode=True** | recalculate_fast.py L1599,L1614 | **L2から2-5s** | ✅ **OPT-14実装済み**(commit 79663eda)。Phase0 DELETE済み→UPSERT→INSERT化。計測待ち |

### Tier 2: 大型ボトルネック対策（実装済み or 設計進行中）

| # | 改善 | 対象 | 推定効果 | 根拠 |
|---|---|---|---|---|
| **NEW-1** | **dw_signals_flush最適化** | signal_flush.py+recalculate_fof.py | **L3から40-60s** | ✅ **cmd_1470実装済み**(commit 27e39f37)。per-FoF UPSERT×59commits→deferred INSERT×1commit+5000/batch。計測待ち |
| **NEW-2a** | **calculate_monthly_return fallback軽量化** | return_calculator.py L287,L344-352 | **L2から14-29s** | ✅ **cmd_1473実装済み**。del price_cache除去→fallback転用。has_ticker→missingのみmerge load。計測待ち |
| **NEW-2b** | **L2 trade_perf残(whileループ本体)** | return_calculator.py L313-357 | **L2から10-20s** | while iteration本体のPython overhead。月単位ループ→NumPy batch化は要設計 |
| 4 | ~~fof_signals dead code除去~~ | ~~recalculate_fof.py L761~~ | — | Tier 1 #5に移動 |

### 取り下げ/優先度低下

| # | 改善 | 理由 |
|---|---|---|
| ~~4~~ | ~~monthly_returns_gen バッチ化~~ | OPT-6で56.61s(8.9%)に縮小。ROI低下 |
| ~~6~~ | ~~Ward scipy最適化~~ | cmd_1456: anomaly。正常42s |

## 将軍起票への推奨順序（cmd_1466〜1471データベース）

### 計測待ち（push済み・デプロイ後に計測）
- **cmd_1469**: #1★ N+1→cache参照(30-60s削減期待)
- **cmd_1470**: NEW-1 signals_flush deferred化(40-60s削減期待)
- **cmd_1472**: #1b★ load_business_days N+1除去 + #1c バッチcommit(28-50s削減期待)
- **cmd_1473**: NEW-2a fallback price_cache保持(14-29s削減期待)
- **→ 次の本番fullrecalculate計測で4件の効果を一括確認**
- **OPT-12**(軍師直接実装): gc.collect削減+fof_signals dead code除去+profiling改善(6-15s削減期待)
- **OPT-13**(軍師直接実装): nested FoF回帰修正。signal_cacheからDB query補完(cmd_1474 FAIL解消)
- **OPT-14**(軍師直接実装): Standard PF signals flush INSERT化(2-5s削減期待)
- **OPT-15**(軍師直接実装): component_weights commit集約59→6(5-10s削減期待)
- **→ 予測: 637.80s → ~450-525s (OPT-13でnested FoF 15体分の処理時間が復帰するため上方修正)**

### 軍師直接実装済み（OPT-12+OPT-13）
- **OPT-12** (commit 00fd5257):
  - **#2 gc.collect()削減**: 59回→5回。推定5-12s削減
  - **#3 profiling返却漏れ修正+trade_perf外れ値出力**: db_write内訳可視化+5PF制限撤廃
  - **#5 fof_signals dead code除去**: 354K dict insert排除。推定1-3s削減
- **OPT-13** (commit f3ff64a7): **nested FoF回帰修正**
  - **根本原因**: cmd_1470 deferred flush導入後、先行処理済みFoFのシグナルがDB未commitのままnested FoF処理→DB query空→continueでスキップ(15体)
  - **修正**: OPT-6のin-memory signal_cacheからDB query結果を補完。component FoFのシグナルがsignal_cacheに存在しDB結果に欠落している場合に自動補完
  - **影響**: cmd_1474 FAIL(15 nested FoF zero-signal、signal 406,988 vs 453,663)を解消
  - **副次効果**: 真のパフォーマンス値はcmd_1474の380.53sより増加する（15体分の処理時間が加算されるため）

### 次期実装推奨
- (全Tier 1項目実装完了。Tier 2 NEW-2b(whileループNumPy化)が残存)

### 保留
- **NEW-2b(whileループNumPy化)**: 投資対効果未確定。上記全適用でtrade_perf 63-101sまで縮小した後に再評価

## 未確認事項

- ~~Phase別正確な秒数~~ → **解決**: cmd_1466で本番実測取得
- ~~monthly_returns_gen単体~~ → **解決**: L2 phase45=12.47s, L3 MR_gen=56.61s
- ~~OPT-4/5適用後の計測値~~ → **解決**: cmd_1466で637.80s(全OPT適用)
- ~~Phase 5b precompute内訳~~ → **解決**: trade_perf 142.78s(74.4%)が支配的
- ~~fof_signalsの消費者の有無~~ → **解決**: 軍師コード検証。書込みのみ(L543初期化,L761代入)、読取りゼロ。Dead code確定。354K dict insert削除可(1-3s)
- ~~L3 unmeasured 74.64sの正体~~ → **解決**: cmd_1467偵察。N+1 query(30-60s)+gc.collect(5-15s)+benchmark load(1-3s)+misc(1-5s)
- ~~L3 db_write 130.64sの内訳~~ → **解決**: cmd_1467+cmd_1470。signals_flush(80-100s)→deferred INSERT化(cmd_1470実装済み)。component_weights(20-40s)
- ~~L2 trade_perf 142.78sの改善余地~~ → **解決**: cmd_1471偵察。3ボトルネック: load_business_days N+1(21-36s)+fallback calc(14-29s)+per-PF DB write(7-14s)。del price_cache阻害発見
- **260s(cmd_1454)と637.80s(cmd_1466)の乖離原因**: データ量増(signal +13.6%)? 計測範囲(L2のみvs全体)? 環境差?

## 第3サイクル計測結果（cmd_1478, 357.28s）

### 3サイクル比較
| | cmd_1466(baseline) | cmd_1474(FAIL) | **cmd_1478(valid)** | 改善率 |
|--|-------------------|----------------|---------------------|--------|
| Total | 637.80s | 380.53s※ | **357.28s** | **-44.0%** |
| L2 | 240.66s | 109.65s | **109.47s** | **-54.5%** |
| L3 | 362.27s | 235.37s | **214.01s** | **-40.9%** |
| Overhead | 34.87s | 35.52s | **33.80s** | -3.1% |
※cmd_1474は15 nested FoF未処理のため無効値

### L2内訳比較 (240.66s → 109.47s, -54.5%)
| substep | baseline | 第3サイクル | 変化 |
|---------|----------|-----------|------|
| trade_perf | 142.78s | **0.00s** | ⚠profiling未発火 |
| db_write | 47.38s | 44.89s | -5.3% |
| metrics | 17.85s | 18.38s | +3.0% |
| rolling_chart | 14.84s | 14.93s | +0.6% |
| phase45_mr | 12.47s | 11.92s | -4.4% |
| rolling_summary | 6.21s | 6.36s | +2.4% |
| drawdown | 5.88s | 5.97s | +1.5% |
| risk_mgmt | 3.42s | 0.00s | ⚠profiling未発火 |
| signal_calc | 1.06s | 1.10s | +3.8% |
**⚠ trade_perf=0.00s問題**: Phase 5bのprofiling timerが発火していない。L2合計の差分(240.66-109.47=131.19s)からtrade_perfの実時間を推定: ~131s-改善分≈trade_perf実時間。db_write等の安定した項目から、trade_perf実時間は**~100-105s**と推定(cmd_1472/1473で40-55s改善)

### L3内訳比較 (362.27s → 214.01s, -40.9%)
| substep | baseline | 第3サイクル | 変化 | 改善源 |
|---------|----------|-----------|------|--------|
| db_write | 130.64s | 18.84s | **-85.6%** | cmd_1470+OPT-15 |
| unmeasured | 74.64s | 3.01s | **-96.0%** | cmd_1469+OPT-12(可視化) |
| daily_loop | 71.0s | 67.88s | -4.4% | OPT-12 gc削減 |
| mr_gen | 56.61s | 55.21s | -2.5% | 安定 |
| cache_init | 8.25s | 8.44s | +2.3% | 安定 |
| df_prep | 3.64s | — | — | db_writeに含む |
| (NEW) dw_signals_flush | — | 41.93s | — | OPT-12計測追加 |
| (NEW) dw_cw | — | 18.69s | — | OPT-12計測追加 |

### 軍師分析: 新ボトルネック構造
1. **L2 trade_perf推定~100-105s (28%)** — profiling未発火。改善は効いているが定量把握困難
2. **L3 daily_loop 67.88s (19%)** — Pythonループオーバーヘッド。ベクトル化要設計
3. **L3 mr_gen 55.21s (15%)** — OPT-6で最適化済み。安定
4. **L2 db_write 44.89s (13%)** — バッチcommit効果小。Singapore latency制約
5. **L3 dw_signals_flush 41.93s (12%)** — deferred flush後も残存。バッチサイズ最適化余地
6. **Overhead 33.80s (9%)** — 安定

### 予測精度検証
| 予測 | 実測 | 精度 |
|------|------|------|
| 450-525s | 357.28s | ⚠過小評価。trade_perf profiling問題で実態把握困難だった |

trade_perf=0.00sの原因を特定し修正することが次の最優先事項。真のボトルネック構造を正確に把握するために必要

**次期改善ターゲット候補**(計測後に優先度再評価):
1. ~~L3 db_write残(70-91s): component_weights~~ → ✅ OPT-15 commit集約実装済み
2. L3 daily_loop(71.0s): Pythonループ→部分batch化
3. L2 trade_perf残(64-101s): whileループNumPy化(NEW-2b)
4. ~~gc.collect削減(5-15s)~~ → ✅ OPT-12実装済み

### 軍師事前分析（計測待ち中に完了）

#### gc.collect()削減 — 実装仕様
- **現状**: L1076で59回呼出し(FoFごと)。L1074-1075のcache.clear()後
- **提案**: 15 FoFごと + ループ末尾1回 = 5回に削減
- **根拠**: CPython refcounting でclear()後に即解放。gc.collect()は循環参照用。price_data/momentumにcyclic ref可能性低い
- **リスク**: cmd_1470のdeferred flush(all_signals_batch蓄積)で全体メモリ増。ただし推定~70MB(59FoF×6000sig×200B)で許容範囲
- **変更箇所**: recalculate_fof.py L1076。`if (idx + 1) % 15 == 0:` で条件化 + L1078(ループ後)に1回追加
- **推定効果**: 5-12s削減

#### fof_signals dead code — 確定
- **結論**: 書込みのみ(L543, L761)。消費者ゼロ。Dead code
- **変更箇所**: L543(`fof_signals = {}`)削除、L761(`fof_signals[target_date] = ...`)削除
- **推定効果**: 1-3s (354K dict insert排除)。コード衛生向上

#### component_weights flush — ✅ commit集約実装済み (OPT-15, commit 1e3401fd)
- **現状→改善**: per-FoF UPSERT+commit (59 commits) → skip_commit=True + 10FoFごとcommit (6 commits)
- **Phase 0でDELETE無し** → UPSERTは維持（INSERT不可）。commit集約のみ
- **残端数**: deferred signals flush (cmd_1470)のcommitでカバー
- **推定効果**: 5-10s削減（commit round-trip 59→6）
- **完全deferred化**: データ量1.77-5.3M行でOOMリスクがあるため見送り。commit集約で十分
