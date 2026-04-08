# DM-Signal DB テーブル詳細
<!-- cmd_286 | 2026-02-23 | core.md §2から移動。experiments.db/dm_signal.db/PostgreSQLの全テーブル情報 -->

## experiments.db テーブル詳細

| テーブル | 行数 | 内容 | 信頼度 |
|---------|------|------|--------|
| daily_prices | 414K | OHLCV日次価格(86銘柄) | **価格ground truth** |
| monthly_returns | 14K | バックテスト月次リターン | 本番APIからDL済み |
| download_metadata | 3 | 最終DL日時 | — |
| signal_history | 0 | 空 | — |
| trades | 0 | 空 | — |

DLコマンド:
- 価格DL: `python scripts/analysis/data_sync/download_all_prices.py grid-search`
- 月次リターンDL: `python scripts/analysis/data_sync/download_prod_data.py monthly-returns`
- `download_prod_data.py prices` → 422エラー。**使うな。** `download_all_prices.py`を使え（cmd_042で判明）

## dm_signal.db テーブル詳細

| テーブル | 行数 | 内容 | 信頼度 |
|---------|------|------|--------|
| portfolios | 19 | PF設定(UUID, config JSON) | **PF設定ground truth** |
| signals | 30K | 日次シグナル+モメンタム | 本番ミラー |
| monthly_returns | 1.5K | 本番計算月次リターン | 本番ミラー |
| prices | **40** | テストデータのみ(AGG/SPY各20行) | **使うな** |
| performance | 42K | 日次パフォーマンス | 本番ミラー |

## 本番PostgreSQL接続情報

- ホスト: `dpg-d542chchg0os73979vg0-a.singapore-postgres.render.com`
- 接続文字列: `backend/.env` の `DATABASE_URL`

## UUID不一致警告

2つのDBのUUIDは**DM7+以外は異なる**。

| 四神 | dm_signal.db UUID | experiments.db UUID |
|------|-------------------|---------------------|
| 青龍(DM2) | f8d70415 | 4db9a1f5 |
| 朱雀(DM3) | c55a7f68 | 8300036e |
| 白虎(DM6) | 212e9eee | a23464f7 |
| 玄武(DM7+) | 8650d48d | **8650d48d(同一)** |
