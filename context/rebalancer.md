# Rebalancer Context
<!-- last_updated: 2026-08-28 source_equivalent -->
<!-- source_commit:f240e99b52a0 reason:source_equivalent evidence:gate_context_freshness context=context/rebalancer.md source_commit=f240e99b52a0 reason=source_equivalent -->
<!-- source_commit:dd70cc05ffd2 reason:source_equivalent evidence:gate_context_freshness context=context/rebalancer.md source_commit=dd70cc05ffd2 reason=source_equivalent -->
<!-- source_commit:ff6f13e045ba reason:source_equivalent evidence:gate_context_freshness context=context/rebalancer.md source_commit=ff6f13e045ba reason=source_equivalent -->
<!-- source_commit:186669602f77 reason:source_equivalent evidence:gate_context_freshness context=context/rebalancer.md source_commit=186669602f77 reason=source_equivalent -->
<!-- source_commit:d31723a3573e reason:source_equivalent evidence:gate_context_freshness context=context/rebalancer.md source_commit=d31723a3573e reason=source_equivalent -->
<!-- source_commit:b75b555129a7 reason:source_equivalent evidence:gate_context_freshness context=context/rebalancer.md source_commit=b75b555129a7 reason=source_equivalent -->
<!-- source_commit:9ef55fb620f8 reason:source_equivalent evidence:gate_context_freshness context=context/rebalancer.md source_commit=9ef55fb620f8 reason=source_equivalent -->
<!-- source_commit:ea45534ba9c6 reason:source_equivalent evidence:gate_context_freshness context=context/rebalancer.md source_commit=ea45534ba9c6 reason=source_equivalent -->
<!-- source_commit:f66e319923b5 reason:source_equivalent evidence:gate_context_freshness context=context/rebalancer.md source_commit=f66e319923b5 reason=source_equivalent -->
<!-- source_commit:e3c456584109 reason:将軍誤断定の撤回: e3c456584109 は rebalancer 正準 repo(/mnt/c/Python_app/rebalancer)の cmd_4227 commit で origin/main 祖先。07:36 の marker 除去(a0b850188)は control repo で rev-parse した将軍の誤り evidence:git -C /mnt/c/Python_app/rebalancer cat-file -t e3c456584109 = commit; merge-base --is-ancestor origin/main = yes -->
<!-- source_commit:e26ba8187794 reason:DOC_LANE_REQUEST blt_042404 source_equivalent 内容変更なし境界のみ evidence:git log --oneline -1 e26ba8187794; reason=source_equivalent -->
<!-- source_commit:ea45534 reason:cmd_karo_rebalancer_guide_contrast_v19_20260805 reviewed source boundary evidence:cmd_complete_gate project=rebalancer context=context/rebalancer.md commit=ea45534 -->
<!-- source_commit:f66e319 reason:cmd_karo_hotfix_rebalancer_ux_card_20260805 evidence:reviewed -->
<!-- source_commit:f202c578e44ba99e1daf9232a18b905142e99615 reason:cmd_4229 reviewed source boundary evidence:shared price snapshot SSOT, phase-transition invalidation, CLOSED EODHD final-price contract, Render deploy_commit match -->
<!-- source_commit:e26ba81 reason:cmd_4228 reviewed source boundary evidence:cmd_complete_gate project=rebalancer context=context/rebalancer.md commit=e26ba81 -->
<!-- source_commit:e3c4565 reason:cmd_4227 reviewed source boundary evidence:cmd_complete_gate project=rebalancer context=context/rebalancer.md commit=e3c4565 -->
<!-- source_commit:9ef55fb reason:cmd_4226 reviewed source boundary evidence:cmd_complete_gate project=rebalancer context=context/rebalancer.md commit=9ef55fb -->
<!-- source_commit:1866696 reason:cmd_4225_backend_impl reviewed source boundary evidence:cmd_complete_gate project=rebalancer context=context/rebalancer.md commit=1866696 -->
<!-- source_commit:f541642 reason:cmd_karo_hotfix_rebalancer_health_deploy_identity_20260729 evidence:reviewed -->

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
| Price provenance | `backend/app/services/eodhd.py`, `backend/app/models.py` | 表示値(yfinance/Alpaca, `is_final=false`)と計算確定値(EODHD, `is_final=true`)を型分離。EODHDはdate最大の最新確定行を採用し、HTTP失敗はtoken/query/URL非露出の`EODHDRequestError`へ変換（cmd_4088、source commit `31d071c`） |

- L609: Next.js srcなし時は`app/components`を正としてテスト配置。find/rgで実体確認（cmd_2719）

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
- L608: `npm audit fix --omit=dev`はdevDependencies(@tailwindcss/postcss等)をnode_modulesから削除する（cmd_2707）

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

<!-- lesson-sort 2026-05-19: L608→§6既知の注意点, L609→§2アーキテクチャに振り分け -->
<!-- last_synced_lesson: L609 -->

## §8 2026-07-21 現行本番知識

| 項目 | 正本・事実 |
|------|------------|
| 表示価格 | AlpacaリアルタイムIEX WebSocket（表示用、`is_final=false`） |
| リバランス計算 | EODHD確定終値（`services/eodhd.py` / `api/rebalance.py`、`source='eodhd'`、`is_final=true`） |
| Render | `srv-d4jacrfpm1nc73dudmn0`。`ALPACA_API_KEY_ID` / `ALPACA_API_SECRET` / `EODHD_API_TOKEN`投入済み、再デプロイ後`market_phase=closed`で認証成立確認（2026-07-21） |
| 環境変数注意 | Stock Database `.env`は`ALPACA_API_SECRET_KEY`、rebalancerコードは`ALPACA_API_SECRET`を読むため名称不一致に注意 |
| EODHDトークン | 1アカウント1トークン、database PJと共有、graceful rotation不可 |
| 資格情報配置 | `rebalancer/backend/.env`へ複製済み |

## §9 2026-08-04 cmd_4229 価格スナップショットSSOT

| 項目 | 正本・契約 |
|------|------------|
| 共有境界 | `backend/app/services/price_snapshot.py` の `PriceSnapshotService` を表示API・SSE・リバランス計算で共有。表示値と計算値は同一snapshotの `price/as_of` を使う |
| ACTIVEフェーズ | `PRE/REGULAR/POST` はAlpaca RT storeを優先し、欠落銘柄のみEODHD確定値を `degraded` で補完 |
| フェーズ遷移 | `PRE/REGULAR/POST` から `CLOSED` へ遷移した時、RT storeをsnapshot保存後にclearし、RT残値をCLOSED表示・計算へ持ち越さない |
| CLOSED終値 | `CLOSED` はEODHDの `is_final=true` 最新確定終値を使用。取得失敗時のみ直前snapshotを `degraded` として復元し、障害状態を明示 |
| 本番反映 | Renderの `deploy_commit` が `f202c578e44ba99e1daf9232a18b905142e99615` と一致し、cmd_4229のGATE CLEARを確認済み |
| 契約テスト | `backend/tests/test_price_snapshot_contract.py` で表示・計算同値、POST→CLOSEDのRT残値無効化、CLOSED EODHD障害時のdegraded復元を検証 |
