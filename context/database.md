# Stock Database Context

> cmd_865初回偵察完了(2026-03-12)。水平4名+垂直1名(2AC)で全容把握。

## §1 概要

- リポジトリ: `https://github.com/simokitafresh/database`
- ローカル: `/mnt/c/Python_app/database`
- Python 3.12 + FastAPI 0.111 + SQLAlchemy 2.0(async) + PostgreSQL(Supabase) + Render
- 殿の株式データベース。DM-Signalとは独立PJ
- コード11,478行、テスト3,647行（25ファイル）、サービス20モジュール

## §2 DB設計

6テーブル + 1 VIEW + 1関数。Alembic 11バージョン。RLSはコード上未定義。

| テーブル | PK | 用途 |
|---------|-----|------|
| symbols | symbol(TEXT) | 銘柄マスター |
| prices | (symbol, date) | 日次調整済みOHLCV。CHECK制約4個、FK→symbols |
| symbol_changes | (old_symbol, change_date) | 銘柄名変更(1ホップ解決) |
| fetch_jobs | job_id | バックグラウンドジョブ管理 |
| economic_indicators | (symbol, date) | 経済指標(FRED DTB3) |
| corporate_events | id(SERIAL) | 企業イベント(分割/配当検出・修正) |

- VIEW: `v_symbol_coverage`(カバレッジ集計)
- 関数: `get_prices_resolved()`(symbol_changes透過解決)
- → 詳細: `queue/reports/hanzo_report_cmd_865.yaml`

## §3 データフロー・ビジネスロジック

Yahoo Finance(yfinance) + FRED API → 正規化 → PostgreSQL(Supabase) UPSERT

- **取得**: yfinance(OHLCV adjusted, 認証不要, 2.0req/s) + FRED(DTB3, APIキー)
- **加工**: DataCleaner → OHLC正規化 → シンボル自動登録(3フェーズ) → UPSERT(2000行バッチ)
- **保存**: Supabase PostgreSQL(asyncpg) + Redis/メモリキャッシュ(TTL 4h)
- **Cron**: 平日23:00 JST — 全履歴再取得+FRED更新+価格調整チェック
- **API**: 21エンドポイント（9ルータ）。Cronのみ`X-Cron-Secret`認証、他は公開
- → 詳細: `queue/reports/kotaro_report_cmd_865.yaml`

## §4 Render構成

- web: Python runtime, gunicorn 2workers + uvicorn, Starter plan($7/月)
- cron: Docker runtime(ただし`Dockerfile.cron`不在 — ビルド不可)
- build: `pip install` → `alembic upgrade head` → gunicorn起動
- healthcheck: GET `/healthz`
- 問題: web=Python runtime vs Docker系ファイル(Dockerfile/entrypoint.sh)が混在。統一要
- L001: Render blueprintが実在しないDockerfileを参照 — manifest参照先存在確認が初手（cmd_865）
- → 詳細: `queue/reports/saizo_report_cmd_865.yaml`

## §5 DM-Signalとの関係

- **銘柄重複**: 10/11アクティブ銘柄がDM-Signal四神と重複
- **データソース差異**: database=yfinance(adjusted) vs DM-Signal=StockData API
- **補完可能**: DTB3(1954年〜)がDM-Signalリスクフリーレート補完に有用
- **推奨**: OPT-C(独立維持+DTB3共有のみ)が安全。統合にはclose価格差異検証が前提
- L002: databaseプロジェクトはDM-Signalと銘柄大幅重複だがデータソース異なる（cmd_865）
- → 詳細: `queue/reports/tobisaru_report_cmd_865.yaml`

## §6 既知の問題（改善余地）

**セキュリティ（緊急度高）**:
- `scripts/set_final_symbols.py:5-6` — DB接続URLハードコード
- `app/api/v1/cron.py:19-23` — CRON_SECRET_TOKEN未設定時フェイルオープン
- `Stockdata-API.env` がリポジトリルート存在(.gitignore対象外の可能性)
- `scripts/cron_command.sh:22` — シークレットフォールバック値ハードコード

**インフラ**:
- `render.yaml` cron→`Dockerfile.cron`不在
- `.github/workflows`がローカルに存在しない（CI状態不明）
- dependabotブランチ14本未マージ
- RLSポリシーがコード管理外

**コード品質**:
- `upsert.py:127` 重複return文
- `datetime.utcnow()`使用箇所あり
- テストギャップ: price_service.py, cache.py, redis_utils.py

## 教訓索引（自動追記）

- （L001-L002は振り分け済 → §4 Render構成(L001), §5 DM-Signalとの関係(L002)）
<!-- last_synced_lesson: L002 -->
