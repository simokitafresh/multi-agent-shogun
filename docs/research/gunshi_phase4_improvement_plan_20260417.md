# Phase 4 fullrecalculate改善方針 v2 (両面作戦)

<!-- created: 2026-04-17 -->
<!-- v2 revised: 2026-04-17T01:40 殿指摘: 本番=Render(Singapore内RTT 1-5ms)、ローカル=WSL2(RTT 80ms) -->
<!-- source: cmd_1994 cProfile + cmd_1998偵察 + RTT実測 -->

## §0 前提(v2改訂)

| 項目 | 値 |
|------|-----|
| 対象 | `backend/app/jobs/recalculate_fast.py` (2960行) + 関連モジュール |
| **本番実測** | **480s** (Render Backend→Render PostgreSQL。同一リージョンSingapore) |
| cProfile計測(ローカル) | 1527s (WSL2→Singapore RTT 80ms + cProfile overhead 含む) |
| パリティツール | compare_recalc_results.py + compare_snapshots.py + --exclude-months (完成済み) |
| Phase 3パターン | A: precomputed masks (100x, monthly-only), B: キャッシュ+再利用 (3-5x) |

### ★ v1からの根本変更: 2環境の分離

| 環境 | DB RTT | cursor.execute 10298回 | DB I/O比率 | ボトルネック |
|------|--------|----------------------|-----------|------------|
| **本番(Render内)** | 1-5ms | 10-50s | **2-10%** | **Python計算(430-470s)** |
| ローカル(WSL2) | 80ms(実測) | 828s | **69%** | DB往復latency |

**v1の誤り**: cProfileのDB I/O 69%をそのまま本番に適用した。本番ではDB I/Oは支配的ではない。

### cmd_1998偵察で否定された仮説

| v1仮説 | 偵察結果 | 判定 |
|--------|---------|------|
| T1-1: signal_cache miss大量 | miss 0/26806 (0%) | **否定** |
| T1-2: fallback大量 | 436/26738 (1.63%, 全件partial_final_month) | **限定的** |
| T2-2: component_weights N+1 | N+1なし、既バッチ化(79405 INSERT削減) | **既達成** |

## §1 本番ボトルネック再分析

本番480sの内訳推定(Render内RTT 1-5ms前提):

| 区分 | cProfile時間 | DB RTT分 | **本番推定(純Python)** |
|------|-------------|---------|----------------------|
| _generate_trade_performance | 508s | ~(181×95ms)=17s | **~150s** |
| expand_portfolio_to_tickers | 384s | ~(cache hit=0ms) | **~120s** (ループ+辞書参照) |
| _recalculate_fof_history | 382s | ~30s(flush/write) | **~110s** |
| calculate_trade_period_return | 369s | ~(26738×数ms)=少 | **~115s** |
| calculate_monthly_return | 368s | ~少 | **~115s** |

※ cumtimeは親子重複あり。独立時間ではない。

**本番の真のボトルネック**: Pythonのループ処理(whileループ月走査、辞書lookup、オブジェクト生成)。DB I/Oではない。

## §2 両面作戦

### 面A: 本番改善(Render内。Python計算最適化)

目標: 480s → 240s (50%削減)

| # | 対象 | 改善手法 | 推定効果 | ROI |
|---|------|---------|---------|-----|
| **A1** | calculate_trade_period_return | whileループ→NumPy vectorized。月走査を配列操作に | **-50s~** | ★★★ |
| **A2** | _generate_trade_performance | PFループ内のオブジェクト生成削減。dict→namedtuple/dataclass slots | **-30s~** | ★★☆ |
| **A3** | expand_portfolio_to_tickers | 1.17M回呼出のループオーバーヘッド。呼出回数自体の削減(結果キャッシュ) | **-30s~** | ★★☆ |
| **A4** | _recalculate_fof_history | daily_loop残存ループ。月中日のバッチ処理(signal不変区間一括) | **-20s~** | ★☆☆ |
| **A5** | flush/write | PostgreSQL COPY Protocol(psycopg2 copy_expert)。INSERT→COPY | **-10s~** | ★☆☆ |

#### A1詳細: calculate_trade_period_return NumPy化

```
現状: whileループで月ごとに走査(26738回 × 月数ループ)
改善: monthly_returnsを全PF×全月のNumPy行列に変換
      → trade期間のスライス+cumsum で一括計算
      fallback 436回(1.63%)はpartial_final_month → MTD precomputeで0化可能
```

#### A3詳細: expand_portfolio_to_tickers呼出削減

```
現状: 1,168,384回呼出。cache hit 100%だが呼出自体のPythonオーバーヘッド
改善: 同一PF×同一月の結果をメモ化(月初signal不変→月中呼出は全て同一結果)
      monthly granularity cacheで呼出回数 1.17M → ~50K (月数×PF数)
```

### 面B: ローカル改善(WSL2→Singapore RTT削減)

目標: ローカルfullrecalculate開発時の快適性向上

| # | 対象 | 改善手法 | 推定効果 |
|---|------|---------|---------|
| **B1** | SELECT 7858回 | IN句バルク化。7858→100回 | **-620s** (ローカル) |
| **B2** | WRITE 1523回 | bulk INSERT/UPSERT統合 | **-120s** (ローカル) |
| **B3** | flush 3回×65s | flush分割(小バッチ×複数回) | 検証要 |

**B面の副次効果**: クエリ回数削減はRender本番でも1-5ms×回数分の改善がある(ただし主効果はA面)。

### A面・B面の関係

```
A面(Python計算最適化) → 本番480s改善の主レバレッジ
B面(クエリ回数削減)   → ローカル開発改善の主レバレッジ + 本番の副次効果
A1(NumPy化)はA面専用。B1(IN句バルク化)はB面専用。
A3(呼出回数削減)はA面+B面の両方に効く(ループ削減=Python計算+DB呼出の両方削減)
```

## §3 実装計画(cmd分割案 v2)

| 順序 | ID | 対象 | 面 | 推定本番効果 | AC |
|------|-----|------|---|-----------|-----|
| **偵察** | — | cProfile純Python時間の分離(DB wait除外) | A | 前提確認 | Render上cProfile or ローカルDB mock |
| **1** | A1 | calculate_trade_period_return NumPy化 | A | **-50s** | パリティPASS + fallback=0 |
| **2** | A3 | expand_portfolio_to_tickers 月粒度キャッシュ | A+B | **-30s** | パリティPASS + 呼出回数<100K |
| **3** | A2 | _generate_trade_performance オブジェクト軽量化 | A | **-30s** | パリティPASS |
| **4** | B1 | SELECT IN句バルク化 | B(+A副次) | **-5s本番/-620sローカル** | パリティPASS |
| (5) | A4 | daily_loop 月中バッチ | A | **-20s** | パリティPASS |

### 本番推定改善(v2)

| 状態 | 時間 |
|------|------|
| Phase 3完了(現在) | **480s** |
| A1+A3完了後 | **380-400s** |
| A2完了後 | **350-370s** |
| B1完了後 | **345-365s** (本番副次効果小) |
| A4完了後 | **320-350s** |
| 並列化(将来) | **150-200s** |

### 偵察先行(v2)

A面の精緻化に必要:
1. **純Python時間の分離**: Render上でcProfile実行、またはローカルでDB mockを使いDB waitをゼロにした計測
2. **calculate_trade_period_return内のwhileループ回数**: 26738回×平均何月走査か=総ループ回数
3. **expand_portfolio_to_tickers の月粒度重複率**: 1.17M回のうち同一PF×同一月の重複が何%か

## §4 cmd_2000(SQLクエリログ分類)の位置づけ

cmd_2000はB面(ローカル改善)の偵察として有効。SELECT/INSERT/UPDATE分類はB1(IN句バルク化)の設計材料になる。ただし**本番改善(A面)には直結しない**。A面偵察(純Python時間分離)を別途起票が必要。

## §5 掲示板投稿用要約

```
【Phase 4改善方針v2(両面作戦)】
★ v1の誤り: cProfile DB I/O 69%を本番に適用した。
  本番(Render内RTT 1-5ms)ではDB I/O=2-10%。ボトルネック=Python計算。
■ 面A(本番): Python計算最適化
  A1: calculate_trade_period_return NumPy化 → -50s
  A3: expand_portfolio_to_tickers 月粒度キャッシュ → -30s
  A2: _generate_trade_performance オブジェクト軽量化 → -30s
■ 面B(ローカル): クエリ回数削減
  B1: SELECT IN句バルク化 → -620s(ローカル)/-5s(本番副次)
■ 目標: 480s → 320-350s(A面完了) → 150-200s(並列化)
■ 偵察先行: 純Python時間分離(DB wait除外の計測)
→ docs/research/gunshi_phase4_improvement_plan_20260417.md
```
