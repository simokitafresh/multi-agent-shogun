# 設計書: ベンチマーク(TQQQ・SPY)Deterioration Monitor追加
<!-- link_id: benchmark_deterioration_design -->
<!-- origin: [[殿指示_20260625_1148]] -> [[TQQQ_SPY_deterioration不在]] -> [[ベンチマーク拡張設計]] -->
<!-- created: 2026-06-25 -->

## §1 殿の要求

> 「Compare Summary画面のTQQQとSPYのdeteration monitorの値がない。Deteration monitorページにSPYとTQQQを追加しよう。その結果をCompare summaryページにも反映。cronなどの設定も必要だ」
> — 殿 2026-06-25 11:48

## §2 現状(As-Is)

| 項目 | 現状 |
|------|------|
| P(det)計算対象 | **portfoliosテーブルのPFのみ** |
| TQQQ/SPY | ベンチマーク専用。portfoliosに未登録 |
| 計算式 | P(det)=Φ(-Z), Z=(d+δ)/SE_d, d=μ_recent-μ_long |
| 窓 | 6m(早期警戒)・12m(主判定)・24m(構造変化) |
| ラベル | DETERIORATING/WATCH/EARLY_WARNING/GOOD/MIXED/INSUFFICIENT_DATA |
| cron | `dm-signal-deterioration-batch` (Render cron `crn-d6kehqlm5p6s73dov630`, Oregon) |
| Compare Summary | PFのdeterioration値を表示。ベンチマーク行にはdeterioration列なし |

**根因**: deterioration計算パイプラインがportfoliosテーブルを起点に走る。TQQQ/SPYはベンチマーク→portfoliosに不在→計算対象外。

## §3 目標(To-Be)

1. **Deterioration Monitorページ**: SPY・TQQQのP(det)3窓+ラベルを表示
2. **Compare Summaryページ**: ベンチマーク行にもdeterioration値を表示
3. **cron**: 自動計算(PFと同一バッチ or 別バッチ)

## §4 設計案

### §4.0 最新仕様・実装根拠への接続

本書は初期設計メモであり、実装時の正本はDM-Signal側の最新specを参照する。
特に `[[deterioration-benchmark-extension.md]]` はレビュー2回分を反映済みの親仕様で、`[[deterioration-benchmark-extension-review-1.md]]` は `ticker_monthly_returns` 固定前提、`as_of` 統合、権限ゲート、バッチ失敗境界を実装前BLOCK事項として明文化している。

現物確認済みの接続先:

| 目的 | 参照先 |
|------|--------|
| 親仕様 | `/mnt/c/Python_app/DM-signal/docs/spec/deterioration-benchmark-extension.md` |
| レビュー1 | `/mnt/c/Python_app/DM-signal/docs/spec/deterioration-benchmark-extension-review-1.md` |
| レビュー2 | `/mnt/c/Python_app/DM-signal/docs/spec/deterioration-benchmark-extension-review-2.md` |
| バッチ実装 | `/mnt/c/Python_app/DM-signal/backend/app/jobs/deterioration_batch.py` |
| DBモデル | `/mnt/c/Python_app/DM-signal/backend/app/db/models.py` |

初期設計から更新すべき点:

1. 保存先は既存 `deterioration_snapshots` への同居ではなく、`benchmark_deterioration_snapshots` の別テーブル。
2. 月次リターン取得は `ticker_monthly_returns` 単独ではなく、`prices` fallback必須。
3. cronは新規追加ではなく、既存 `dm-signal-deterioration-batch` の同一バッチ拡張。
4. `/api/deterioration` はDeterioration MonitorだけでなくDashboard / Compare Summaryからも消費されるため、権限ゲートは消費ページ基準。

### §4.1 ベンチマーク月次リターンの取得

ベンチマークの価格データは既にDBに存在(benchmark_pricesテーブル or prices経由)。月次リターン算出は既存PFと同じロジック(月末終値の変化率)。

**更新**: 最新specでは `TickerMonthlyReturn` → `Price` fallbackの2経路に確定。`ticker_monthly_returns` が空でも `prices` があればSPY/TQQQのP(det)を生成する。

### §4.2 P(det)計算の拡張

既存のdeterioration計算関数にベンチマーク月次リターン系列を入力できるようにする。計算式自体は同一(P(det)=Φ(-Z))。違いは入力データソースのみ。

**設計選択肢**:
- **A**: portfoliosテーブルにTQQQ/SPYをPFとして登録(最小変更)
- **B**: deterioration計算関数をportfolios非依存にリファクタ(任意の月次リターン系列を受付)

→ **Bを推奨**。理由: Aはベンチマークの本質(PFではない)を歪める。Bなら将来の任意インデックス追加にも対応。

### §4.3 結果の保存

**更新**: `benchmark_deterioration_snapshots` 別テーブルに保存する方針で確定。`portfolio_id` FKを持つ既存 `deterioration_snapshots` にティッカーを混在させない。

### §4.4 API

**更新**: `/api/deterioration` の `portfolios[]` に `portfolio_id="benchmark-{SYMBOL}"`, `type="benchmark"`, `year_month` としてmergeする方針。`as_of` はPFとベンチマークをsource別に扱う。

### §4.5 FE表示

- Deterioration Monitorページ: ベンチマーク行を追加(SPY・TQQQ)
- Compare Summaryページ: ベンチマーク行のdeterioration列に値を表示

### §4.6 cron設定

既存cron `dm-signal-deterioration-batch` にベンチマーク計算を追加。同一バッチで実行(ベンチマーク2本の追加コストは微小)。ベンチマーク側の失敗でPF側のスナップショットを巻き戻さない失敗境界を維持する。

## §5 偵察が必要な項目

| # | 偵察対象 | 確認内容 |
|---|---------|---------|
| R1 | ベンチマーク月次リターン取得経路 | テーブル名・カラム・既存関数パス |
| R2 | deterioration結果保存先 | テーブル名・スキーマ・PF識別方法 |
| R3 | Deterioration Monitor API | エンドポイントパス・レスポンス構造 |
| R4 | Compare Summary API | deterioration値の取得元・表示ロジック |
| R5 | deterioration-batch cronジョブ | エントリポイント・PF列挙ロジック |

## §6 実装ステップ(案)

1. **偵察cmd**: R1-R5を1忍者で調査(§5全項目)
2. **BE実装cmd**: deterioration計算をportfolios非依存化 + ベンチマーク計算追加 + API拡張
3. **FE実装cmd**: Deterioration Monitor + Compare Summaryにベンチマーク表示追加
4. **cron設定cmd**: deterioration-batchにベンチマーク追加 + Render cron設定更新

## 因果リンク

- ← [[殿指示_20260625_1148]] Compare SummaryにTQQQ/SPYのdeterioration値がない
- ← [[deterioration_probability_design]] P(det)設計書(殿作成)
- → [[deterioration-benchmark-extension.md]] 最新の親仕様
- → [[deterioration-benchmark-extension-review-1.md]] 実装前BLOCK事項レビュー
- → [[robustness_common]] α6+5指標と合わせた包括的PF品質評価基盤
