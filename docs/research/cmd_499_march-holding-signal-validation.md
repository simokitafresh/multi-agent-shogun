# cmd_499 March holding_signal Validation

- task_id: subtask_499_recon_holding_signal_march
- date: 2026-03-03
- agent: hanzo
- target_repo: /mnt/c/Python_app/DM-signal

## 0. Preflight

- `psql` 未導入を確認。
- `python3 3.12.3` + `sqlalchemy` + `psycopg2` 利用可能を確認。
- 本検証は `backend/.env` の `DATABASE_URL` を読み取り、PostgreSQL本番DBへ直接接続して実施。

## 1. AC1: RULE01-03 根拠 (trade-rule.md)

参照: `/mnt/c/Python_app/DM-signal/docs/rule/trade-rule.md`

- RULE01: `signal` と `holding_signal` は別物
  - L115-L118
- RULE02: `holding_signal` はリバランス月初のみ更新
  - L120-L122
- RULE03: リバランス月の `holding_signal` は前月末 `signal` を採用
  - L124-L126

## 2. AC2: recalculate_fast.py 実装照合

参照: `/mnt/c/Python_app/DM-signal/backend/app/jobs/recalculate_fast.py`

- 月変わり判定
  - `month_changed` / `is_reb_month` 判定: L1422-L1423
- リバランス月月初の `holding_signal` 更新
  - `if month_changed and is_reb_month:`: L1427
  - `current_holding_signals[...] = last_gen_signal`: L1430
  - コメントで「前月末シグナルを即時適用」明記: L1428-L1429
- 日次保存時の `holding_signal` 書込み
  - `signals_batch` へ `holding_signal` 保存: L1641-L1646
- 翌日状態更新
  - `last_generated_signals[...] = signal`: L1658
  - コメントで「月中のシグナル変化は保有に反映しない」明記: L1655-L1657

判定:
- RULE01-03 と `recalculate_fast.py` 実装は一致。
- 3/2(月初営業日)の `holding_signal` は、直前営業日 2/27 の `signal` を採用する実装。

## 3. AC3: 本番DB突合 (2/27 vs 3/2)

対象:
- portfolios: `type='standard'`, `is_active=true`, `rebalance_trigger='monthly'`
- signals: 2026-02-27 / 2026-03-02

比較条件:
- `3/2 holding_signal == 2/27 signal`

結果:
- 対象件数: 23 portfolio
- 一致: 23
- 不一致: 0
- 不一致一覧: なし

補助確認 (prices):
- 2026-02-27: 13 rows
- 2026-02-28: 0 rows
- 2026-03-01: 0 rows
- 2026-03-02: 13 rows

解釈:
- 2/28, 3/1 が非営業日で、3/2 は月跨ぎ後の最初の営業日。
- 実データ上も RULE03 想定どおり `3/2 holding_signal` が `2/27 signal` を採用。

## 4. AC4: 「1/30→2/27 固定か」days/months分類

分類方法:
- portfolios.config.lookback_periods の各要素を分類
- `days_only`: days>0 のみ
- `months_only`: months>0 のみ
- `mixed_days_months`: days>0 と months>0 が混在

集計 (monthly standard 23件):

| class | total | 1/30→2/27 fixed | changed |
|---|---:|---:|---:|
| days_only | 16 | 9 | 7 |
| months_only | 3 | 3 | 0 |
| mixed_days_months | 4 | 1 | 3 |

changed例:
- days_only: DM2, DM2-20%, DM2-40%, DM2-test, DM2-top, DM-safe, DM-safe-2
- mixed_days_months: L0-M_TMV_4M_10D_w50_50_T1, L0-M_TMV_4M_1M_15D_w60_30_10_T1, L0-M_XLU_6M_3M_10D_w50_40_10_T1

判定:
- 「1/30→2/27が固定」は全体では成立しない。
- months_only は今回 3/3 が固定、days_only/mixed は変化事例あり。
- ただし fixed/changed いずれでも、3/2 holding は 2/27 signal と一致 (23/23)。

## 5. 総合結論

- 2026-03-02 の monthly standard PF 全件で RULE03 準拠を確認。
- `recalculate_fast.py` 実装と本番DB実測は整合。
- cmd_499 の主検証命題「3/2 holding_signal == 2/27 signal」は不一致ゼロで成立。

## 6. 事象整理（バグ確定: 表示レイヤー）

### 6.1 事象（ユーザー報告）

- 2026-03-02 市場オープン前の表示で、3月保有ではなく2月保有が表示された。
- 2026-03-03 市場オープン前には表示が変化していた。

### 6.2 期待される挙動

- monthly portfolio の 3月保有は、2月最終営業日(2026-02-27)終値確定後の初回計算完了時点で確定する。
- したがって 2026-03-01 以降の UI 表示は、実約定前でも「3月保有（pending）」を一貫表示すべき。

### 6.3 実際の不一致（何がバグか）

- 本検証で確認したとおり、計算結果そのもの（`3/2 holding_signal == 2/27 signal`）は正しい。
- 一方、Signalページの current signal 表示は `as_of`（最新`signals.date`）依存で、月替わりの pending 投影を持たない。
- このため、閲覧時点の `as_of` が 2026-02-27 側に留まると、3月表示であるべきタイミングでも2月保有に見える。

判定:
- **計算バグではなく、表示仕様/表示実装のバグ**。

### 6.4 是正方針（ドキュメント化）

- Signalページ表示で monthly portfolio 向けに「月替わり pending 投影」を導入する。
- 具体的には、当月日付行が未生成でも、前月末signal由来の当月holdingを表示対象にする。
- Monthly Trade 画面と Signal 画面で「当月保有の見え方」を統一する。
