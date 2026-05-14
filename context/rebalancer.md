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

- `OPEN_EXCHANGE_RATES_APP_ID` はoptional。未設定時はExchangeRate-API fallback。
- Background updaterはFastAPI lifespan task。Render worker再起動時は初期取得から再開。
- npm audit moderate 3件(postcss内蔵)はNo fix available。CI audit-level調整が必要（cmd_2715 decision_candidate）。
- rebalancer repo全体に大量の未commit変更が残存（前開発者の遺産）。各cmd scope内ファイルのみcommitし残りは残置。

## §7 2026-05-14 改善成果（cmd_2704〜cmd_2722、19cmd全CLEAR）

万全偵察(cmd_2702)でP0:3/P1:8/P2:13=24件の改良候補を特定し、P0〜P2-7の18件を1セッションで完了。

| 区分 | cmd | 内容 | 成果 |
|------|-----|------|------|
| P0-1 | cmd_2705 | Render永続disk+cache公開停止 | CACHE_DIR環境変数+/static除外。再起動後cache保持+セキュリティ |
| P0-2 | cmd_2706 | asyncテスト12件FAIL修正 | pytest-asyncio pin+asyncio_mode=auto。39→53テストPASS |
| P0-3 | cmd_2707 | Next.js脆弱性(RCE+auth bypass) | 15.0.3→15.5.18。critical/high=0。Serwist互換確認 |
| P1-1 | cmd_2711 | FEビルドゲート復元 | ignore=false。lint/型エラーがbuild時に遮断される |
| P1-2 | cmd_2715 | GitHub Actions CI構築 | BE pytest+FE lint/build/audit。全pushで品質自動検証 |
| P1-3+P1-5 | cmd_2709 | 入力検証+重複ticker拒否 | Pydanticバリデータ。unsupported/重複/負数/NaN→400 |
| P1-4 | cmd_2712 | 並列価格取得 | Semaphore(4)+cache hitスキップ。18銘柄逐次17s→並列 |
| P1-6 | cmd_2710 | DiskCache atomic化 | tmp→flush/fsync→os.replace。並行読み書き安全 |
| P1-7 | cmd_2708 | Toast onClose修正 | ×ボタンでerrorステートクリア。同一エラー再表示可能 |
| P1-8+P2-1 | cmd_2713 | SW precache+URL統一 | Linux再生成でバックスラッシュ解消+dm-rebalancer-frontend統一 |
| P2-2 | cmd_2718 | BE/FE依存pin | 46パッケージ全pin+npm minor/patch更新 |
| P2-3 | cmd_2714 | FE a11y改善 | button+aria-expanded/controls/label+flex-wrap |
| P2-4 | cmd_2716 | i18n完成 | BUY/SELL/HOLD+通貨フォーマット+APIエラー日本語化 |
| P2-5 | cmd_2719 | FEユニットテスト導入 | Vitest+Testing Library。4テストPASS |
| P2-6 | cmd_2721 | E2Eテスト導入 | Playwright。銘柄入力→計算→結果表示フロー検証 |
| P2-7 | cmd_2717 | BEテスト品質改善 | SPY/QQQ銘柄修正+エラーケース4種追加。53テストPASS |
| UI | cmd_2722 | UIデザイン刷新 | カード廃止→テーブル1銘柄1行+PC2カラム+WCAG AA準拠 |
| infra | cmd_2704 | scout_exempt修正 | inbox_write.sh git_uncommitted_gateがscout_exemptスキップ |
| infra | cmd_2720 | 遡及学習ack機構 | 既知BLOCKパターンの軽量確認記録。CTX浪費削減 |

## 教訓索引（自動追記）

- L608: npm audit fix --omit=devはdevDependencies削除する(cmd_2707)
- L609: Next.js srcなし時は実装実体のapp/componentsを正としてテスト配置(cmd_2719)
<!-- last_synced_lesson: L609 -->
