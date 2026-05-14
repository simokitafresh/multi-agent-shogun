# Rebalancer Context
<!-- last_updated: 2026-05-14 cmd_2701初回登録 -->

## §1 概要

- repo: `https://github.com/simokitafresh/rebalancer`
- path: `/mnt/c/Python_app/rebalancer`
- ポートフォリオリバランス計算アプリ v4.0。JPY/USD二重通貨、リアルタイム株価・USD/JPY為替、PWA対応。
- 技術スタック: Next.js 15 static export + React 18 + TypeScript + Tailwind CSS v4 + Serwist / Python 3.11 + FastAPI + yfinance + httpx。
- 核心知識: `projects/rebalancer.yaml`

## §2 アーキテクチャ

Frontendは `frontend/` のNext.js static export。Backendは `backend/app/main.py` のFastAPI。

| 領域 | 正本 | 要点 |
|------|------|------|
| Frontend | `frontend/package.json`, `frontend/next.config.ts` | `npm run build`で`frontend/out`生成。Render Static Siteで配信 |
| Backend | `backend/app/main.py` | lifespanで`PriceUpdaterService`を起動。CORSはlocalhostとRender frontend |
| Cache | `backend/app/services/cache.py` | disk JSON cache。Renderでは1GB diskを利用 |
| Rebalance | `backend/app/api/rebalance.py` | USD価格をJPY換算し、target_weight合計100%を検証してBUY/SELL/HOLDを返す |

## §3 API

| Method | Endpoint | 用途 |
|--------|----------|------|
| GET | `/`, `/healthz`, `/health` | health/status |
| GET | `/api/status` | 価格更新サービス状態 |
| GET | `/api/supported-tickers` | 対応銘柄一覧 |
| GET | `/api/exchange-rate` | USD/JPY取得 |
| POST | `/api/convert-currency` | USD/JPY変換 |
| POST | `/api/stock-price` | 単一銘柄価格取得 |
| POST | `/api/stock-prices` | 複数銘柄価格取得 |
| POST | `/api/calculate-rebalance` | リバランス計算 |

## §4 追跡銘柄・為替

Source of truthは `backend/app/config.py`。

| 種別 | 内容 |
|------|------|
| 追跡銘柄 | `GDX, GLD, GLDM, IEF, LQD, QLD, QQQ, SOXX, SPXL, SPY, TECL, TMF, TMV, TQQQ, XLE, XLK, XLU, XLV` |
| 注意 | READMEは17 ETFsと記載するが、現行実装は`GLDM`を含む18銘柄 |
| 為替 | `USD_JPY`。Open Exchange Rates優先、ExchangeRate-API fallback |
| 更新 | 5分間隔、cache TTL 10分、3回retry |

## §5 Render構成

`render.yaml` が正本。

| Service | Type | Runtime | Region/Publish |
|---------|------|---------|----------------|
| `dm-rebalancer-backend` | web | python 3.11.0 | Singapore / port 10000 / starter / 1GB disk |
| `dm-rebalancer-frontend` | web | static | `frontend/out`, `/* -> /index.html` |

- Frontend env: `NEXT_PUBLIC_API_BASE_URL=https://dm-rebalancer-backend.onrender.com`
- Backend URLs: `/health`, `/healthz`
- Userguide記載の `https://rebalancer-frontend.onrender.com` は現行render.yamlの `https://dm-rebalancer-frontend.onrender.com` と不一致。

## §6 既知の注意点

- Documentation drift: 対応銘柄数(17/18)とfrontend URLが文書間でズレている。
- `OPEN_EXCHANGE_RATES_APP_ID` はoptional。未設定時はExchangeRate-API fallback。
- Background updaterはFastAPI lifespan task。Render worker再起動時は初期取得から再開。

## 教訓索引（自動追記）

- （現在0件。初回登録のみ）
<!-- last_synced_lesson: none -->
