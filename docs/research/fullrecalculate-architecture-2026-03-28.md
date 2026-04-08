# fullrecalculate アーキテクチャ全量解析
<!-- author: shogun | source: コード全文読了 -->
<!-- revision: v4 2026-03-28T04:50+09:00 — §9消費者完全分析追加+§8 signal記述修正+OPT-E momentum_data空問題発見 -->

## §1 概要
<!-- verified: 2026-03-28T03:20+09:00 recalculate_fast.py L1-2140, recalculate_fof.py L1-1053 全行読了 -->
<!-- verified: 2026-03-28T03:50+09:00 signals.py L88-305, monthly_trade_calculator.py L280-520 読了 -->
<!-- verified: 2026-03-28T04:10+09:00 constants.py, schemas/models.py L401-420, momentum_cache.py L44-55 読了 -->

fullrecalculate = DM-Signal本番バックエンドの全ポートフォリオ再計算エンジン。
- ファイル: `backend/app/jobs/recalculate_fast.py`(2140行) + `backend/app/jobs/recalculate_fof.py`(1053行)
- 最新本番計測: **349s / 124 PF**(2026-03-28 cmd_1444)
- 歴史: 初回11,818s → OPT-A/D/F 2,397s → OPT-E 389s → 現在349s

## §2 Phase構成(recalculate_fast.py)
<!-- verified: 2026-03-28T03:20+09:00 recalculate_fast.py 全行読了から構築 -->

| Phase | 行 | 内容 | ループ構造 | 推定時間 |
|-------|-----|------|-----------|---------|
| 0 | L692 | DELETE全計算データ(Signal/MonthlyReturn等) | 1回 | <1s |
| 1 | L700 | バルク価格データロード(load_prices_as_df) | 1回 | 数秒 |
| 1.5 | L738 | PF有効開始日バッチクエリ | 1回 | <1s |
| 2 | L824 | 前処理(symbol分割/daily_returns/PriceCache/ベンチ累積/pipeline_config検証/モメンタム事前計算) | PFあたり数十ms × ~100PF | 数秒 |
| 3.5 | L1025 | パイプラインブロック事前解決 | 1回 | <1s |
| 3.7(OPT-E) | L1038 | **ベクトル化シグナル事前計算** — 全PFの全日付シグナルをDataFrame演算で一括生成。O(1) dict lookup化 | 1回(全PF一括) | 0.53s |
| 3 | L1349 | 状態初期化(累積リターン=1.0) | PFごと | <1s |
| **4** | **L1440** | **日次ループ(本体)** — ~6800営業日 × ~100 standard PF | **~680K反復** | **主要ボトルネック** |
| 4.5 | L1782 | MonthlyReturn生成(standard PF) | PFごと | 数秒〜 |
| 5(FoF) | L1798 | FoF再計算(_recalculate_fof_history) | FoFごと | ~89s(旧値) |
| 5(precompute) | L1835 | Layer2生成(trade_perf/drawdown/rolling/metrics/risk) | PFごと | trade_perf 58.7s(旧値) |

## §2.5 ルックバック期間の定数（コード実測値）
<!-- verified: 2026-03-28T04:10+09:00 constants.py L15-28, schemas/models.py L401-420, momentum_cache.py L44-55 -->

| 定数 | 値 | 定義場所 |
|------|-----|---------|
| TRADING_DAYS_PER_MONTH | **21** | constants.py L26 |
| TRADING_DAYS_PER_YEAR | **252** | constants.py L15 |
| LOOKBACK_BUFFER_MULTIPLIER | **1.5** | constants.py L27 |
| LOOKBACK_EXTRA_BUFFER_DAYS | **60** | constants.py L28 |
| FOF_LOOKBACK_DAYS | **730**(カレンダー日≈2年) | jobs/constants.py L29 |
| HISTORY_DAYS | **4100**(≈11.2年) | constants.py L13 |

### ルックバック期間→営業日変換 (schemas/models.py L401-420)
```python
def lookback_to_trading_days(period: LookbackPeriod) -> int:
    if period.months == 0 and period.days is not None:
        return period.days                          # 日指定: そのまま
    if period.months > 0:
        return period.months * TRADING_DAYS_PER_MONTH  # 月指定: months × 21
```
- 1M = **21営業日**、2M = **42営業日**、12M = **252営業日**

### 営業日→カレンダー日変換 (recalculate_fast.py L817, recalculate_fof.py L389)
```python
lookback_calendar_days = int(lookback_trading_days * 1.5) + 10
```
- 21営業日 → **41カレンダー日**、252営業日 → **388カレンダー日**

### valid_start計算 (Phase 1.5)
```python
# Standard PF (recalculate_fast.py L817-819)
valid_start = common_start + timedelta(days=lookback_calendar_days)

# FoF (recalculate_fof.py L389-397)
fof_valid_start_date = signal_ready_date + timedelta(days=selection_lookback_cd)
```

**★月次化設計への影響**: ルックバック期間は営業日単位。セグメント構築時、有効開始日がセグメント(月)の途中になりうる。Partial月の扱いが必要。

## §3 DBスキーマ（日次/月次分析の前提）
<!-- verified: 2026-03-28T03:50+09:00 models.py L87-165 読了 -->

### Signalテーブル（日次レコード）
```
signals:
  portfolio_id  PK  String
  date          PK  Date
  signal        String   ← 生シグナル（パイプライン出力）
  holding_signal String  ← 保有シグナル（リバランス設定考慮）
  momentum_data  JSON   ← パイプライン診断データ。OPT-E PFでは {} が大半
  created_at     DateTime
```
**★ cumulative_returnカラムは存在しない。** Signal表はシグナル（保有銘柄）のみ記録。

### MonthlyReturnテーブル（月次レコード）
```
monthly_returns:
  portfolio_id       PK  String
  year_month         PK  String ('2024-12')
  cumulative_return       Float   ← 月末時点の累積リターン
  cumulative_return_open  Float
  monthly_return          Float   ← 当月リターン
  monthly_return_open     Float
  benchmark_cumulative    Float
  benchmark_cumulative_open Float
  benchmark_return        Float
  benchmark_return_open   Float
  in_market               Integer  ← Risk Management用(1=In/0=Out)
  holding_signal          String   ← 月末時点の保有シグナル
```
**cumulative_returnはMonthlyReturnにのみ存在。Phase 4.5の_generate_monthly_returns()が生成。**

### UIデータフロー（recalculate_fast.py L13-15コメント）
```
Level 2: MonthlyReturn.cumulative_return (Π(1 + Level 1))
補助  : MonthlyReturn.cumulative_return (日次チャートの代用)
```
→ UIのパフォーマンスチャートはMonthlyReturn（月次粒度）を参照。日次データではない。

## §4 Phase 4 日次ループ: 日次必須 vs 月次化可能の分離
<!-- verified: 2026-03-28T03:50+09:00 recalculate_fast.py L1440-1733 精読、signals_batch構造確認 -->

### Phase 4で毎日計算しているもの一覧

| # | 処理 | コード | 値の変動頻度 | DB保存先 | 月次化可否 |
|---|------|--------|-------------|---------|-----------|
| A | 月変わり検出+holding_signal更新 | L1472-1495 | **月初のみ** | — (メモリ状態) | ✅ 既に月初のみ実行 |
| B | holding_signalパース(ticker分割) | L1523-1532 | **月初のみ**(同じ文字列ならキャッシュヒット) | — | ✅ 月初1回でOK |
| C | **perf_calc(累積リターン計算)** | L1534-1622 | **毎日**(価格変動) | **保存されない** | ⚠️ 後述 |
| D | signal(生シグナル)取得 | L1629-1694 | **★毎日異なる**(OPT-E L1172: 全日計算済み) | Signal.signal | ❌ 毎日取得必要 |
| E | Signalレコード生成 | L1697-1706 | 毎日1レコード生成 | Signal表 | ⚠️ 後述 |
| F | 状態更新(T+1) | L1708-1715 | 毎日 | — | ⚠️ perf_calcに依存 |
| G | バッチDB書き込み | L1720-1731 | N日ごと | Signal表 | — |

**★重要: signalとholding_signalの違い**
<!-- verified: 2026-03-28T04:20+09:00 recalculate_fast.py L1168-1236 Phase 3.7 OPT-E全日計算確認 -->
- **signal(生値)**: Phase 3.7(OPT-E)で**全営業日分**事前計算(L1172: `for _ts in _sample_index`)。モメンタムランキングは毎日変わるため、**日ごとに異なる値**を持つ
- **holding_signal(保有値)**: リバランス月の月初にのみ更新。月内は同一値を維持
- 例: 12月の任意の日 → signal="SPY,GLD"(今日ならこう組む)、holding_signal="SPY"(12月はSPYを保有中)

### C: perf_calc — 最重要発見

**Phase 4のperf_calcで計算されるcumulative_returnはDBに一切保存されない。**

計算結果の用途:
1. `prev_perf_cache[portfolio.id] = (new_cum, new_cum_open, new_bench, new_bench_open)` — メモリ内のみ
2. 月変わり時に `segment_start_cum[portfolio.id] = prev_perf_cache[portfolio.id][0]` — 次セグメントの起点

つまりperf_calcの目的は**セグメント境界（月変わり）の起点値を正しく渡すこと**だけ。

**月次化が可能な理由**: セグメント終了値(=次セグメント起点)は以下で直接計算できる:
```
end_of_segment_cum = seg_start_cum × (month_end_price / seg_start_price)
```
中間日の計算は不要。PriceCacheから月末価格を直接取得すればよい。

### E: Signalレコード生成 — UI整合性の要

**Signalレコードは毎営業日分が必要。理由:**

1. `/api/signals` (signals.py L111): `Signal.date == as_of_date` でクエリ。as_of_dateは**任意の営業日**
2. FoF再計算(recalculate_fof.py L332-337): `Signal.date >= start_date AND Signal.date <= end_date` で全日クエリ → pivot → ffill
3. pending判定: monthly_trade_calculatorがSignal存在チェック

**ただし**: 月内のSignalレコードは以下の構造:
- **signal: 毎日異なる**(OPT-Eが日次モメンタムランキングを事前計算済み)
- **holding_signal: 月内同一**(月次リバランス)
- **momentum_data: OPT-E PFでは `{}`**(月内同一)

→ **perf_calcを除去した上で、Signal生成をセグメント単位バッチ化可能**:
  1. holding_signalはセグメント単位で固定(月初に1回決定)
  2. signalはOPT-E dict[pf_id][date]から日次取得(O(1) lookup、現行と同じ)
  3. momentum_dataは{}固定(OPT-E PF)
  4. **perf_calcの日次ループが不要になるのが最大の削減**

## §5 月次化設計: エッジケース深掘り
<!-- verified: 2026-03-28T04:00+09:00 signals.py L111, monthly_trade_calculator.py L286-360, recalculate_fof.py L332-408 -->

### 5.1 Partial月（最古月・開始月）

PFの有効開始日(valid_start)が月途中の場合:
- 例: valid_start = 2007-03-15 → 2007-03月は月初からデータなし
- Phase 4現行: `if valid_start and current_date < valid_start: continue` (L1467-1469)
- 月次化時: 初月のSignalレコード生成は**valid_start以降の営業日のみ**。月初からではない

**MonthlyReturn側**:
- monthly_trade_calculator L289-290: `is_partial = year_month == oldest_ym and not is_mtd`
- partial月はsignal_date=None, position_start_dateは運用開始日を使用(L293-302)
- MonthlyReturn.holding_signalはPhase 4のSignalから独立して生成される

**月次化リスク**: partial月の最初のSignalレコードのdateが月初でない場合、FoFの`df_sig_pivot.ffill()`で正しい値がforward-fillされるか → **OK**: pivot後のNaNはffillで埋まる。valid_start以前にデータがなくてもNaN→ffillで前月末が引き継がれる（前月もなければNaN維持）

### 5.2 MTD月（当月・未完了月）

当月(today含む月)はデータが途中まで:
- Phase 4現行: calc_end_date = end_date or date.today()。当月の営業日まで計算
- 月次化時: 当月は「月末日」が確定していないためセグメント終了値を計算できない
  - → 当月はpartialセグメントとして処理: today時点の価格でセグメント値を計算
  - Signalレコードは今日まで生成

**MonthlyReturn側**:
- monthly_trade_calculator L287: `is_mtd = year_month == current_ym`
- MTD月はcalculate_monthly_return()でリアルタイム計算(L352-354)
- position_end_dateをas_of_dateに差し替え(L345-347)

**月次化リスク**: MTD月のSignalレコードが月初〜today分存在しないと、as_of_date(=today)でのSignalクエリが空になる → **UIが「No Data」表示**。

### 5.3 月末月初の境界

**現行Phase 4のリバランス処理(L1483-1495)**:
```python
if month_changed and is_reb_month:
    current_holding_signals[portfolio.id] = last_gen_signal  # 前月末シグナルを適用
    segment_start_dates[portfolio.id] = current_date - _one_day  # 前日をセグメント開始に
    segment_start_cum[portfolio.id] = prev_perf_cache[portfolio.id][0]  # 前日の累積値
```

- **月末最終営業日**: 旧holding_signalのまま。signal=新シグナル(OPT-E生成)だがholding_signalは変わらない
- **月初最初の営業日**: holding_signalが更新される（リバランス実行）。セグメントリセット

**月次化時の注意**:
1. 月末日のSignalレコード: holding_signal=旧値, signal=新値(pipeline出力)
2. 月初日のSignalレコード: holding_signal=新値(リバランス後)
3. **月末日と月初日のholding_signalは異なる可能性がある** → 月単位の一括生成で誤って同じ値にしないこと

具体例(monthly PF):
```
2024-12-30: signal="SPY,GLD"(この日のモメンタム), holding_signal="SPY"  ← 12月の保有はSPY
2024-12-31: signal="GLD,SPY"(この日のモメンタム), holding_signal="SPY"  ← まだ12月
2025-01-02: signal="GLD,QQQ"(この日のモメンタム), holding_signal="GLD,SPY" ← 1月にリバランス(前月末signalを適用)
2025-01-03: signal="SPY,GLD"(この日のモメンタム), holding_signal="GLD,SPY" ← 1月内は同じholding
```
→ 月次バッチ生成では:
  - 12月の全営業日: holding_signal="SPY"(固定), signalは日ごとにOPT-E dictから取得
  - 1月の全営業日: holding_signal="GLD,SPY"(固定), signalは日ごとにOPT-E dictから取得
  - ★holding_signalの決定: 1月初の`last_gen_signal`=12月末のsignal(OPT-E dict[pf][12月末日])

### 5.4 複数リバランスパターン

| trigger | リバランス月 | 年間セグメント数 |
|---------|------------|---------------|
| monthly | 毎月 | 12 |
| quarterly | 1,4,7,10月 | 4 |
| semi_annual | 1,7月 | 2 |
| annual | 1月 | 1 |

`is_rebalance_month(rebalance_trigger, month)` (L1479)が判定。

**非リバランス月の扱い**:
- quarterly PFの2月: holding_signalは1月初に設定した値を継続
- signalは毎日新しい値がOPT-Eから出るが、holding_signalは変わらない
- つまり2月のSignalレコード: signal=2月のOPT-E値, holding_signal=1月初の値

**月次化時**: 非リバランス月でもsignal(生値)は月ごとに変わりうる(OPT-Eが月初に新値を出す)。ただしholding_signalは前回リバランス月の値を維持。
→ signalとholding_signalを別々に管理する必要あり

### 5.5 Pending表示との整合性

monthly_trade_calculator._get_pending_month() (L474-517):
1. 当月エントリ(MonthlyReturn)がない → 当月がpending候補
2. 当月エントリあり → 翌月がpending候補(リバランス月の場合)

_check_pending_for_month() (L519):
- Signalテーブルに「次月のリバランスに使うsignal」が存在するか確認
- 前月末のSignalが存在すれば「次月のシグナルは確定しているがまだ実行していない」= pending

**月次化時のリスク**: Signalレコードの生成順序が変わると、pending判定のタイミングに影響する可能性。ただしfullrecalculateは全期間一括なので、全Signal生成後にpending判定が走る → 問題なし。

### 5.6 `/api/signals`との整合性

signals.py L111: `Signal.date == as_of_date`

as_of_dateの決定: canonical_as_of.get_canonical_as_of() — 全PFのSignalの最新日付を取得。通常は直近営業日。

**月次化時**: 全営業日分のSignalレコードが存在すれば問題なし。レコード数は変わらず、生成方法が変わるだけ。

### 5.7 FoF再計算との整合性

recalculate_fof.py L332-362:
```python
sig_rows = db.execute(sig_query).scalars().all()  # 全日Signal取得
df_sig = pd.DataFrame(s_data)
df_sig_pivot = df_sig.pivot(index="date", columns="pid", values="sig").ffill()
```

FoFは構成PFのSignal(holding_signal)を全日読み取り、pivot+ffillで加工。

**月次化時の影響**:
- Signalレコードが全営業日分存在すれば同一結果
- holding_signalの値が月内で一定(=月次化の前提)なら、ffillの有無は結果に影響しない

## §6 Phase 5 FoF: 日次/月次分析
<!-- verified: 2026-03-28T03:30+09:00 recalculate_fof.py L593-872 全行読了 -->

FoF日次ループ(L593-872)の各ステップ:

| # | 処理 | 変動頻度 | DB保存 | 月次化可否 |
|---|------|---------|--------|-----------|
| A | リバランス判定 | 月初のみ | — | ✅ 既に月初のみ(Phase 4A最適化) |
| B | pipeline_engine.execute_pipeline() | **月初のみ** | — | ✅ 既に月初のみ実行 |
| C | holding_signal決定 | 月初のみ | Signal.holding_signal | ✅ 月初1回 |
| D | enhanced_momentum_data構築 | 毎日(ただしほぼ同内容) | Signal.momentum_data | ⚠️ skipped=True/Falseが異なる |
| E | Signalレコード生成 | 毎日 | Signal表 | ⚠️ §4 E同様 |
| F | rebalance_decisions_batch | 毎日 | debug用(条件付き) | ✅ ENABLE_FOF_DEBUG_LOGS=falseなら無影響 |
| G | component_weights_batch | 毎日(ただし月内同値) | fof_component_weights | ✅ 月初1回+fill |

FoFの最大ボトルネックはB(パイプライン実行)だが、**既にPhase 4A最適化で月初のみ実行**。残りは主にSignalレコード生成(E)とモメンタムデータ構築(D)のPythonループ。

## §7 Phase 5 Precompute: 日次/月次分析
<!-- verified: 2026-03-28T03:25+09:00 recalculate_fast.py L1835-2050 読了 -->

```python
precompute_profiling = {
    "ticker_returns": 0.0,    # ティッカー日次リターン → 日次必須(価格は毎日変わる)
    "monthly_returns": 0.0,   # MonthlyReturn生成 → 月次粒度(定義上)
    "drawdown_periods": 0.0,  # ドローダウン期間 → MonthlyReturnから月次計算
    "rolling_summary": 0.0,   # ローリングサマリー → MonthlyReturnから月次計算
    "rolling_chart": 0.0,     # ローリングチャート → MonthlyReturnから月次計算
    "metrics": 0.0,           # パフォーマンスメトリクス → MonthlyReturnから月次計算
    "trade_perf": 0.0,        # トレードパフォーマンス ★最大ボトルネック → MonthlyReturnから月次計算
    "risk_mgmt": 0.0,         # リスク管理 → MonthlyReturnから月次計算
}
```

Phase 5は既に月次粒度。日次ループは内包していない(trade_perfの内部構造は未確認)。

## §8 月次化設計: Phase 4の再構築案
<!-- designed: 2026-03-28T04:15+09:00 §2-7のコード実測値に基づく設計 -->

### 現行(Python日次ループ)
```python
for each_day in 6800_trading_days:          # 外側: 日次
    for pf in 100_portfolios:                # 内側: PFごと
        perf_calc(日次価格)                   # ← DBに保存されない
        signal = OPT-E_lookup(day)            # ← 毎日異なる(モメンタムランキング変動)
        Signal_record(day, signal, holding)   # ← signal毎日異なる, holding月内固定, momentum_data={}(OPT-E)
```

### 月次化案
```python
for pf in 100_portfolios:                    # 外側: PFごと
    segments = build_segments(pf)             # ~250セグメント(月次) or ~80(四半期)
    for seg in segments:
        # 1. セグメント起点値の決定（前セグメント終了値から）
        seg_start_cum = prev_segment_end_cum

        # 2. セグメント終了値の計算（月末価格から直接。★日次perf_calcループ不要）
        #    PriceCacheから月末(or today)の価格を取得、1回の乗算で完了
        end_cum = seg_start_cum × (seg_end_price / seg_start_price)  # close
        end_cum_open = seg_start_cum_open × (seg_end_open / seg_start_open)

        # 3. holding_signal はセグメント単位で固定
        holding = determine_holding_at_rebalance(pf, seg.start_date)

        # 4. Signal レコード一括生成（月の全営業日分）
        #    ★ signal(生値)は日ごとに異なる → OPT-E dictから日次取得(O(1))
        for day in seg.trading_days:
            signals_batch.append({
                portfolio_id, date=day,
                signal=vectorized_pipeline_signals[pf.id][day],  # 日次(OPT-E事前計算済み)
                holding_signal=holding,    # セグメント内固定
                momentum_data={}           # OPT-E PFでは空
            })

        prev_segment_end_cum = end_cum
```
**ベンチマーク累積も同様にセグメント単位計算。ベンチマークはリバランスしないため全期間1セグメント(L1599-1606)。**

### 反復回数の比較

セグメント数の見積り(コードから):
- 月次(monthly): ~6800営業日 / 21営業日/月 ≈ **324月** × 100PF → 32,400回
- 四半期(quarterly): 324月 / 3 ≈ **108セグメント** × PF数
- 半期(semi_annual): 324月 / 6 ≈ **54セグメント** × PF数
- ただしPFごとにvalid_startが異なり、ルックバック分(最大252営業日≈12ヶ月)差し引きが必要
- 実効セグメント数は**200-320/PF**(月次PF)。PFの開始年次に依存

| | 現行 | 月次化後 |
|--|------|---------|
| perf_calc | ~680K回(6800日×100PF) | ~25K回(月次250seg×100PF) |
| signal lookup | ~680K回 | ~680K回(レコード生成時) |
| Signalレコード生成 | ~680K回(1件ずつappend) | ~680K回(同左、ただしセグメント単位バッチ化可) |
| Python分岐判定(月変わり/valid_start/祝日) | ~680K回 | ~25K回(セグメント境界のみ) |

**perf_calcが約27倍削減**。signal lookupとレコード生成は回数同じだが、ループ構造が変わる: 現行の「日付(外)×PF(内)」→「PF(外)×セグメント(内)+セグメント内バッチ生成」。
- 重い分岐判定(月変わり/祝日スキップ/valid_start確認)がセグメント境界のみに集約
- Signal dict append は回数同じだが、セグメント内はデータが同一(holding_signal固定)なのでテンプレートコピーに簡略化可能

### エッジケース対応表

| ケース | 現行の処理 | 月次化での対応 |
|--------|-----------|--------------|
| Partial月(開始月) | valid_start以前はcontinue | セグメント開始日=valid_start。月初でない可能性あり |
| MTD月(当月) | today以降は処理しない | 最終セグメント終了日=today。月末価格=today価格 |
| 月末日→月初日 | holding_signal月末=旧値、月初=新値 | セグメント境界で自動的に分離。月末セグメント内は旧holding、月初セグメントは新holding |
| 非リバランス月(quarterly等) | holding_signal変わらず。signalは毎日OPT-E値 | セグメントが3ヶ月分(=1四半期)。signal_per_dayは日ごとにOPT-E値を取得 |
| signal ≠ holding_signal | signal=毎日の生値、holding=リバランス月のみ更新 | signalはOPT-E dictから日ごと取得。holdingはセグメント単位で固定 |
| Pending表示 | MonthlyReturn+Signal存在チェック | 全Signal生成後の判定→変わらず |
| FoF Signal読取 | 全日全PFをSELECT+pivot+ffill | 全日レコードが存在すれば同一結果 |
| ベンチマーク累積 | 毎日price_ratio計算(L1596-1619) | 月次化可能(ベンチマークもセグメント単位) |

## §9 Signal消費者完全分析 — 日次生成は必要か？
<!-- verified: 2026-03-28T04:50+09:00 全消費者のコード読了。grep結果+個別コード確認 -->

### 9.1 Signal.signal（生値）を直接読む消費者

| # | ファイル:行 | コード | 読取範囲 | 日次必要? |
|---|------------|--------|---------|----------|
| 1 | signals.py:79,82 | `raw_signal = sig.signal or holding_signal` / `return sig.signal, True`(pending時) | as_of_date **1日分のみ**(L111: `Signal.date == as_of_date`) | 1日分のみ |
| 2 | canonical_as_of.py:74,178 | `has_signal_cache = {pid: bool(sig.signal)}` / `db.query(Signal.signal).filter(date == as_of_date)` | as_of_date **1日分のみ**。truthy判定のみ(値不問) | 存在のみ |
| 3 | monthly_trade_calculator.py:262,329 | `signal_map = {s.date: s.signal}` → `signal_map.get(signal_date)` | `signal_date` = **前月最終営業日のみ**(L292-298で算出) | 月末のみ |
| 4 | **history.py:98** | `raw_signal = h.signal` | **全営業日**(L82-89: `Signal.date <= as_of_date`, days分) | **★全営業日** |
| 5 | debug.py:41 | `"signal": s.signal` | admin列挙 | 制約外 |

### 9.2 Signal.momentum_data を読む消費者

| # | ファイル:行 | コード | 読取範囲 | 日次必要? |
|---|------------|--------|---------|----------|
| 6 | **history.py:93-95** | `m_data["absolute"]["value"]`, `m_data["risk_free"]["value"]` | **全営業日** | **★全営業日** |
| 7 | signals.py:136-140 | `s.momentum_data.get("weights")` | as_of_date 1日分 | 1日分のみ |

**★重大発見**: OPT-E hitパス(recalculate_fast.py L1635)では`pm_data = {}`。
history.py L93-95は`m_data.get("absolute")`で安全に`None`→`0.0`を返す。
**→ OPT-E有効PFの履歴チャートでは、absolute_momentum/risk_free_momentumは既に0.0表示。**

### 9.3 fallbackパターン `holding_signal or signal` の消費者

| # | ファイル:行 | コード | signal依存度 |
|---|------------|--------|-------------|
| 8 | trades_calculator.py:171,324,383,880 | `holding = current_signal.holding_signal or current_signal.signal` | holding_signal優先。signalはNULL時fallback |
| 9 | fof/in_market.py:82,122 | `holding = sig.holding_signal or sig.signal` | 同上 |
| 10 | generators/monthly_returns.py:94 | `signal_map = {s.date: (s.holding_signal or s.signal)}` | 同上 |
| 11 | generators/trade_performance.py:164 | `signal_map = {s.date: (s.holding_signal or s.signal)}` | 同上 |
| 12 | history.py:97,181 | `display_signal = h.holding_signal if h.holding_signal else h.signal` | 同上 |

**B群(#8-12)は全てholding_signalが存在すればsignalを参照しない。** holding_signalは月境界でのみ変化するため、これらの消費者にとって日次signal生成は不要。

### 9.4 結論: 日次生成が不可避な理由と月次化の可能性

**日次生成が不可避な唯一の理由**: `/api/history` (history.py L82-89, L98)

- 全営業日のSignal行をSELECTし、`raw_signal = h.signal`を返す
- ただし: historyチャートの主要データは`display_signal`(=holding_signal)とmomentum値
- `raw_signal`はUI上で「実際の保有」vs「その日ならこう組む」の比較表示に使用

**月次化が計算値・表示を変えない根拠（コード確認済み）**:

| 消費者 | 月次化しても表示が変わらない理由 | コード根拠 |
|--------|------------------------------|-----------|
| /api/signals | as_of_date 1日分のみ読む。全営業日のSignal行が存在すれば同一結果 | signals.py L111 |
| canonical_as_of (pending) | bool(sig.signal)のみ。値が空でなければ同一結果 | canonical_as_of.py L74,178 |
| monthly_trade_calculator | 月末日のsignal.signalのみ読む。月末日のSignal行が存在すれば同一結果 | monthly_trade_calculator.py L262,329 (signal_date=前月末) |
| trades_calculator | holding_signal or signal。holding_signalが存在すればsignal不要 | trades_calculator.py L171等 |
| generators | 同上 | monthly_returns.py L94, trade_performance.py L164 |
| FoF recalculate | pivot+ffill。holding_signalが全営業日で存在すればsignal不要 | recalculate_fof.py L332-362 |
| /api/performance | MonthlyReturnのみ読む。Signalは参照しない | performance.py L88-147 |
| /api/mtd | price_ratio計算のみ。Signalは参照しない | performance.py L150-249 |

**唯一の変更点**: `/api/history` の`raw_signal`値。月次化案ではOPT-E dictから日ごとにsignal値を取得するため、**現行と同一の値**を返す(OPT-E事前計算結果は同一)。

### 9.5 Phase 4日次ループで真にボトルネックな処理

| 処理 | 反復回数 | 月次化後 | 削減率 |
|------|---------|---------|--------|
| **perf_calc** (L1534-1622) | ~680K | ~25K(セグメント境界のみ) | **96%削減** |
| signal lookup (OPT-E) | ~680K | ~680K(変わらず: 全日Signal生成に必要) | 0% |
| Python分岐判定 | ~680K | ~25K | 96%削減 |
| DB batch append | ~680K | ~680K(変わらず) | 0% |

**perf_calcが最大の削減対象。** セグメント終了値を月末価格の比率で直接計算することで、日次累積計算の6800反復が月次250反復に削減可能。

## §11 既存プロファイリングインフラ
<!-- verified: 2026-03-28T03:25+09:00 recalculate_fast.py L2020-2050, timing.py L1-60, check_timing_history.py L1-50 -->

コードには既に詳細なプロファイリングが組み込まれている:
- Phase 4: `stats["calc_time"]` + `std_profiling["perf_calc"/"signal_calc"/"db_write"]` + `088b per-day avg`
- Phase 5 FoF: `profiling` dictで8大項目+daily_loop内訳4項目+db_write内訳4項目
- Phase 5 precompute: `precompute_profiling` で8項目個別計測
- `layer_data`としてTimingDataテーブルに保存。`check_timing_history.py --details`で取得可能

**349sの内訳は本番TimingDataから取得可能**（次アクション）。

## §12 ローカル実測結果（2026-03-28T13:00 — 計装実行）
<!-- verified: 2026-03-28T13:00+09:00 ローカル実行(WSL2→Render DB)。7285.72s/124PF -->

### §12.1 全体ブレイクダウン

| フェーズ | 時間(s) | 比率 | 備考 |
|---|---|---|---|
| Phase 4 (signal calc) | 398 | 5.5% | OPT-E有効。signal_calc=1s |
| Phase 4.5 (MonthlyReturn gen) | 123 | 1.7% | 65 standard PF。**新規計測** |
| Phase 5 (FoF) | 1115 | 15.3% | 59 FoF |
| → FoF monthly_returns_gen | 635 | 8.7% | FoFの57% |
| → FoF DB Write | 160 | 2.2% | |
| → FoF DB Query | 218 | 3.0% | |
| Phase 6 (Precompute) | 5772 | 79.2% | **trade_perf支配的** |
| → trade_perf | 4627 | 63.5% | 113 PF(FoF含む) |
| **合計** | **7286** | 100% | ローカル(WSL2→Render DB) |

### §12.2 trade_perf内部ブレイクダウン（113 PF集計）

`calculate_trade_period_return()` L230-338 の内部計装結果:

| 項目 | 時間(s) | 比率 | 呼出回数 | 単価 |
|---|---|---|---|---|
| **get_month_first_business_day** | **3133** | **67.8%** | 39,676 | 79ms |
| MonthlyReturn DB query | 1073 | 23.2% | 13,616 | 79ms |
| calculate_monthly_return (fallback) | 414 | 9.0% | 453 | 913ms |
| overhead | 1 | 0.0% | — | — |
| **合計 (calc_total)** | **4621** | **100%** | — | — |

- `get_month_first_business_day`: whileループ各月で`func.min(Price.date)`をDBクエリ。**pure function版(L76+)が既存だが未使用**
- MonthlyReturn: 同一PFのデータを関数呼び出しごとに個別クエリ(calc_calls=13,616回)
- fallback: ほとんどのPFで2回(partial month)。**追い風-鉄壁は229回(異常: MonthlyReturn欠損多数)**

### §12.3 OPT-1/OPT-2 実装（2026-03-28T13:10）

| ID | 施策 | 対象 | 削減見込み |
|---|---|---|---|
| OPT-1 | `get_first_bday` pre-load: `load_business_days(db)`→dict lookup | return_calculator.py | -3133s |
| OPT-2 | MonthlyReturn PF一括取得: caller側で`{year_month: row}`構築→渡す | return_calculator.py | -1073s |

変更ファイル: `return_calculator.py`(business_days/monthly_returns_mapパラメータ追加), `trade_performance.py`(プリロード+渡し)
テスト: 166 passed, 0 failed

### §12.4 OPT-1/2 実測結果（2026-03-28T14:03 — フルラン完了）

**フルラン比較: 全124PF, WSL2→Render DB**

| 指標 | ベースライン | OPT-1/2 | 削減 |
|---|---|---|---|
| **fullrecalculate全体** | **7,286s** | **3,324s** | **54.4%** |
| trade_loop (124PF) | 4,627s | 242s | **94.8%** |
| get_first_bday | 3,133s (39,676 DBクエリ) | 0.000s (pre-load) | **~100%** |
| MonthlyReturn query | 1,073s (13,616 DBクエリ) | 0.000s (cache dict) | **~100%** |
| fallback_calc | 414s (453回) | 240s (248回) | 42% |

**同一PF比較(48PF)**: 全PFで94-98%の削減。平均40.9s/PF → 1.95s/PF。

**残存ボトルネック**: `fallback_calc`が trade_loop の98.9%を占有。248回 × 966ms/回。
- 各PF 2回(部分月: 計算期間の先頭・末尾)は正常動作。0回にはならない設計
- 追い風-鉄壁の229回(ベースライン時)は異常: MonthlyReturnデータ欠損

**本番推定**: WSL2→Render DB = 79ms/query。本番(co-located) ≈ 1-5ms/query。
- 本番ベースライン: ~349s (TimingData)
- 本番trade_perf: ~58K DBクエリ × ~3ms ≈ 174s → OPT-1/2で0s
- 本番推定after: 349 - 174 ≈ **175s** (50%削減)

### §12.5 本番TimingDataベースライン（2026-03-28T03:02 — run_id 20260328_030229）

**本番 793.3s (125PF, co-located DB)**

| Layer | Time(s) | % | 内訳 |
|---|---|---|---|
| **L3_fof** | **429.0** | **54%** | db_write=144.5, monthly_gen=120.8, daily_loop=73.5 |
| L2_portfolio | 326.5 | 41% | trade_perf=212.2, db_write=49.3, perf_calc=14.9, metrics=17.4 |
| Other | ~38 | 5% | L1 signal等 |

L3 daily_loop (73.5s): pipeline_exec=41.5, signal_gen=23.7, batch_append=6.3
L3 db_write (144.5s): signals_flush=86.3 (60%)

**本番での最適化優先度（降順）:**

| 施策 | 対象 | 本番削減(推定) | 比率 | cmd |
|---|---|---|---|---|
| OPT-1/2 | L2 trade_perf 53K DBクエリ除去 | -159s | 20% | cmd_1448 |
| OPT-A | L3 db_write momentum_data月中縮小 | -137s | 17% | cmd_1450 |
| OPT-? | L3 monthly_returns_gen | -120s? | 15% | 要調査 |
| OPT-? | L3 daily_loop pipeline_exec | -41s | 5% | 要調査 |
| perf_calc除去 | L2 perf_calc | -15s | 1.9% | cmd_1449 |

**注意**: ローカル(WSL2→Render DB)ではDB遅延79ms/queryがtrade_perfを膨張させ、OPT-1/2が94.8%削減に見える。本番(co-located)では3ms/queryのため効果は75%程度。ローカルとの比率差を常に意識すること。

### §12.6 次のアクション

1. ✅ ~~OPT-1/2効果検証~~: **94.8%削減確認(ローカル)**
2. **cmd_1448**: OPT-1/2本番デプロイ+検証（配備中）
3. **cmd_1449**: perf_calc除去検証（配備中。本番15sで低インパクトだが死コード除去として有価値）
4. **cmd_1450**: FoF OPT-A momentum_data月中縮小（起票済み。本番137s削減見込み）
5. **L3 monthly_returns_gen調査**: 120.8s。FoFのMonthlyReturn生成ロジック分析
6. **本番fullrecalculate後**: OPT-1/2のTRADE_CALC_PROFILINGで実測値確認
