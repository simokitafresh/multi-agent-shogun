# provenance設計書v2.3 軍師レビュー結果
# 対象: §5/§5.05/§5.06/§5.07 (v2.1-v2.3新設部)
# レビュー日: 2026-08-14T15:15+09:00

## (1) P7以前record-only主張の反証(P0.5 B2条件分岐+P3a migration)

**CONFIRM(条件付き)**

現物確認: `monthly_returns.py:613-619`のB2は現在「`year_month in benchmark_ticker_returns` → 無条件上書き」。P0.5はこれを「canonical月のみ」へ条件化する。§5.06はこれを「現挙動の固定」と明記し、regression fixtureで不変証明と設計済み。

技術的にはコード変更だが、TickerMonthlyReturnがcanonical月のみ存在すれば出力不変。

**★注意(レビュー条件)**: 非canonical月にTickerMonthlyReturnデータが万一存在する場合は出力変更になる。regression fixtureがこのエッジケースをカバーしていることをP0.5のAC検証時に確認必須。

P3a = nullable ADD COLUMN + WARN契約で既存挙動不変、record-only成立。

## (2) 依存DAG循環・欠落依存

**CONFIRM**

循環なし。DAGを書き出して検証:
```
P0 → {P0.5, P0.6, P3a}  (並列A, 影響範囲無競合)
P0.5 → P1a(B), P1b(直列), P2a(B)
P0.6 → P2a(B), P2b
P1b → P2b  (payload形式継承)
P3a → P3b(B)
{P1a,P1b,P2a,P2b,P3a,P3b} → P4 → P5 → {P6, P7}
```

- P2bのP1b依存 = payload形式継承で妥当
- P0.6 = read-only(コード読解のみ)でP2a/P2bの前提として位置適切
- 並列グループの影響範囲列に重複なし
- クリティカルパス = P0→P0.5→P1b→P2b→P4→P5 は正確

## (3) canary三値②「書けているか確認」の両経路成立

**CONFIRM**

「deploy後の次回再計算待ち」と「対象5PF再計算で即時確認」の両方で成立:

- 即時確認: cron世代切り直し(L3 sync-fof 01:40UTC)の影響を受けず安全
- 次回再計算待ち: cron後に世代が変わるが、record-only設計ゆえ書込み確認(SELECT非null/期待形)は世代に依存しない

**★推奨**: §5.07に「cron直前deployの場合は即時再計算経路を推奨」の一文を追加すると堅牢。

## (4) P1系「FoF null = AsIsで無害」の反証

**CONFIRM**

現物確認:
- provenanceはmomentum_data(JSONB)への埋め込み設計(§3.1)。Signalテーブルへの新カラム追加ではない
- §3.1の「未知キー無視契約」によりJSONスキーマの非対称は無害
- `signal_flush.py:390-400`のUPSET set_にprovenance直接参照なし
- API層(`signals.py`/`portfolios.py`)にprovenance読取りなし
- snapshot builder(`_build_month_start_input_snapshot`)はrecalculate_fast.py固有でFoF波及パスなし

FoF null = 現状維持 = AsIs equivalent 成立。

## 検証方法

全項目コード現物をgrepおよびReadで一次確認:
- `monthly_returns.py` B2セクション(benchmark上書きロジック)
- `recalculate_fof.py`(FoFループ/snapshot呼出し有無)
- `signal_flush.py`(UPSERT set_のprovenance参照有無)
- `models.py`(Signalテーブル定義/provenanceカラム有無)
- `sanitize.py`(sanitize_momentum_dataのallowlist)

origin: `[[殿指示_provenance設計書覚醒_20260814]] -> [[v2.3_4観点レビュー]] -> [[4/4 CONFIRM]]`
