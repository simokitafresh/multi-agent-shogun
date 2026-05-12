# UWP三指標追加 設計書
<!-- created: 2026-05-05 | author: shogun | status: draft | rev: 5 -->
<!-- rev 2: limit=10問題発見(殿指摘)→全DD格納に変更 -->
<!-- rev 3: 軍師RC — limit=0はperiods[:0]=[]で全件削除の致命バグ。limit=Noneに修正 -->
<!-- rev 4: metrics偵察(cmd_2570)結果統合+signal計算パス保護ルール追加(殿指摘) -->
<!-- rev 5: DB構造変更アプローチを棄却。metrics_calculator.py内オンデマンド計算に全面書換え -->
<!-- rev 5 理由: limit撤廃→fullrecalculate 5回連続失敗事故(recalc#112-116)。真因はsignal_flush.py IN句肥大化だったが、そもそもDB構造変更が不要だった -->

## §1 背景

Compare Summary/MetricsページのUWPはMaxDD(rank=1)時のunderwater_monthsのみ表示。
MaxDDが浅くてもDD頻度が高いPFは総水没期間が長く投資体験が悪い。
平均UWP(Avg UWP)と総UWP(Total UWP)を追加し、PFの回復特性の全体像を可視化する。

殿指示: 2026-05-05

## §2 指標定義

| 指標 | FE表示名 | 内部変数 | 計算方法 | 単位 |
|------|---------|---------|---------|------|
| UWP (既存) | UWP (MaxDD) | `uwp_months` | MaxDD(rank=1)のunderwater_months | months |
| Avg UWP (新) | Avg UWP | `avg_uwp_months` | 全DDのunderwater期間の平均(小数第1位) | months |
| Total UWP (新) | Total UWP | `total_uwp_months` | 全DDのunderwater期間の合計 | months |

**既存UWPのラベル変更**: "UWP" → "UWP (MaxDD)" に変更し、3指標の区別を明示。

### Ongoing DD(未回復)の扱い

- **Avg UWP**: NULL除外で計算。ただしOngoing件数を注記表示（例: "5.2 months (1 ongoing)"）
- **Total UWP**: NULL除外で合計。同様にOngoing注記
- 理由: 仮計算(現在日-peak_date)はrecalculate時以外更新されず不正確。NULL除外+Ongoing件数表示が最も誠実

## §3 設計方針（rev 5で全面変更）

### 棄却したアプローチ（rev 2-4）

DrawdownPeriodテーブルのlimit=10を撤廃し全DD格納→テーブルから集計。
→ **棄却理由**: DB構造変更が不要。metrics_calculator.py内で全DDのunderwater期間は計算可能。
→ **事故実績**: limit撤廃がfullrecalculate事故(recalc#112-116)の間接的トリガーとなった。

### 採用するアプローチ

**既存UWP(MaxDD)と同じ構造: DrawdownPeriodテーブルから集計。limit撤廃で全DD格納。**

- 既存: `get_drawdown_stats_from_db()` → rank=1のみ参照 → "Underwater Period"
- 新規: 同関数を拡張 → 全rankからAVG/SUMを計算 → "Avg/Total Underwater Period"
- **DrawdownPeriodテーブルのlimit撤廃(limit=None)** — 全DDを格納
- signal_flush.py IN句バグは修正済み(5c8a9cf2)のためfullrecalculate安全
- 他のDD系metricsと同じデータソースで一貫性を維持+全DD精度

## §4 BE変更

### metrics_calculator.py

既存の`get_drawdown_stats_from_db()` L576を拡張。

**現在の構造**(変更しない):
```python
worst_dd = self.db.query(DrawdownPeriod).filter(
    DrawdownPeriod.portfolio_id == portfolio_id,
    DrawdownPeriod.rank == 1
).first()
```

**追加する集計**(同関数内に追記。limit撤廃後は全DD対象):
```python
all_dds = self.db.query(DrawdownPeriod).filter(
    DrawdownPeriod.portfolio_id == portfolio_id
).all()
completed = [dd for dd in all_dds if dd.underwater_months is not None]
ongoing_count = len(all_dds) - len(completed)
avg_uwp = sum(dd.underwater_months for dd in completed) / len(completed) if completed else None
total_uwp = sum(dd.underwater_months for dd in completed) if completed else None
```

**返却dictに追加**:
- `avg_uwp`: float or None
- `total_uwp`: int or None
- `ongoing_count`: int

**追加するadd_metric行**(L720 "Underwater Period"の直後):
```python
add_metric("Avg Underwater Period", p_dd_stats["avg_uwp_text"], b_dd_stats["avg_uwp_text"], fmt="text")
add_metric("Total Underwater Period", p_dd_stats["total_uwp_text"], b_dd_stats["total_uwp_text"], fmt="text")
```

format例: "5.2 months (1 ongoing)" / "42 months" / "N/A"

### 既存APIへの影響

- `/api/metrics/{portfolio_id}`: 2行追加(後方互換、追加のみ)
- `/api/drawdowns/{portfolio_id}`: 変更なし
- `/api/performance/{portfolio_id}`: 変更なし
- **fullrecalculateへの影響: なし**
- **signal計算パスへの影響: なし**

## §5 FE変更

### 5.1 Metricsページ

"Underwater Period"行の下にAvg UWP/Total UWPの2行追加。
BEが返すテキスト値をそのまま表示。

### 5.2 Compare Summary

`lib/types/compare-summary.ts`:
- `PortfolioSummary`に`avg_uwp_months`/`total_uwp_months`を追加
- `SORTABLE_METRIC_KEYS`に追加
- `METRICS_CONFIG`に2列追加(format: 'decimal1' / 'integer', sortOrder: 'lowToHigh')

`app/compare-summary/page.tsx`:
- `parseUnderwaterPeriodMonths()`で新指標もパース
- 既存`uwp_months`の列ラベルを"UWP"→"UWP (MaxDD)"に変更

### 5.3 Drawdowns Table

変更なし。

### 5.4 Terms

`components/docs/terms-content.tsx`:
- Avg UWP / Total UWPの定義を追加

## §6 用語辞書

cmd_2572で登録済み(disambiguation.md + terminology.md)。追加作業なし。

## §7 cmd分割（rev 5）

| cmd | 内容 | 依存 | signal影響 |
|-----|------|------|-----------|
| cmd_A | BE: drawdowns.py limit撤廃(limit=None)+fullrecalculate+パリティ検証 | なし | **なし**(IN句修正済みで安全) |
| cmd_B | BE: metrics_calculator.pyにavg_uwp/total_uwp集計追加+metrics APIレスポンス2行追加 | cmd_A | **なし**(metrics表示パスのみ) |
| cmd_C | FE: Metrics+Compare Summary+Terms表示追加+既存UWPラベル変更 | cmd_B | なし |

**前提**: signal_flush.py IN句修正(5c8a9cf2)が本番稼働中。cmd_Aのfullrecalculateは安全に通る。
用語辞書(cmd_D)はcmd_2572で完了済み。HIGH修正(E/F/G)は別プロジェクト。

## §8 signal計算パス保護ルール（殿厳命 2026-05-05、rev 4から継承）

**以下のファイル/関数はmetrics修正cmdで変更禁止:**

1. `backend/app/services/vectorized_momentum.py` — `calculate_risk_free_return_vectorized()`
2. `backend/app/services/pipeline/blocks/absolute_momentum.py` — `_calculate_reference_threshold()`
3. `backend/app/jobs/recalculate_fast.py` — signal計算ループ(L2097-2303)
4. `backend/app/jobs/flush/signal_flush.py` — `_flush_batch()`(今回のIN句修正済み。追加変更禁止)

**全BE変更cmdのACに必須記載:**
- "本番fullrecalculate後、signals.holding_signalの全PF×全日付が変更前と完全一致(diff 0件)"
- "本番fullrecalculate後、monthly_returns.monthly_returnの全PF×全year_monthが変更前と完全一致(diff 0件)"

## §9 なぜなぜ7回で発見した穴と対策

| # | 穴 | 対策 | status |
|---|-----|------|--------|
| 1 | Ongoing DD(underwater_months=NULL)の扱い | NULL除外+Ongoing件数注記表示 | 設計済み |
| 2 | 既存UWPラベルの曖昧化 | "UWP"→"UWP (MaxDD)"に変更 | 設計済み |
| 3 | Compare Summary列数増加(22→24) | UWP隣接配置でグルーピング自然 | 問題なし |
| 4 | FE計算 vs BE計算 | metricsページのデータソースはmetrics API→BE集計必須 | 設計済み |
| 5 | Ongoing仮計算(現在日-peak_date)の選択肢 | 棄却。NULL除外+注記が誠実 | 棄却 |
| 6 | DrawdownPeriod limit=10で全DDが格納されていない | **DB変更アプローチ棄却**。オンデマンド計算で全DD捕捉 | **rev 5で解決** |
| 7 | metrics修正がsignal計算パスに波及するリスク | §8保護ルール+本番パリティACで二重防御 | 設計済み |
| 8 | signal_flush.py IN句肥大化(66,500タプル)でstack depth超過 | **5c8a9cf2で修正済み**(1000件チャンク分割) | **修正済み** |

## §10 事故記録（2026-05-05）

- recalc #112-116: 5回連続StatementTooComplex (stack depth limit exceeded)
- 真因: signal_flush.py `_collect_signal_change_logs` L53のIN句が133PF×500日=66,500タプル
- 修正: 5c8a9cf2 (1000件チャンク分割)
- 復旧: recalc #119 completed (7分)
- 教訓: DB構造変更は最後の手段。まずオンデマンド計算で済むか検討。Renderログを最初に確認
