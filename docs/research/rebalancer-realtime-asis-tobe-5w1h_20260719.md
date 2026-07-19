# リバランサー改良 — 価格経路リアルタイム化 AsIs/ToBe 5W1H（2026-07-19）

殿発案(2026-07-19 18:03-18:56)→裁可(18:56)。制約: **EODHDプランは現行固定(アップグレードしない)**。
偵察: cmd_4087(Alpaca実叩き+設計、**完了LGTM 2026-07-19 19:11**)。本書は設計の正本。

**cmd_4087実測結果(一次証跡=docs/research/cmd_4087_rebalancer_realtime_recon.md)**:
- 追跡銘柄 **18/18購読成功**。無料枠上限=**30 symbols/connection**(31銘柄目でerror 405) — 現行18銘柄は余裕内
- 認証163.6ms・WS購読157.7ms・REST latest 18銘柄532.7ms・rate limit 200/min
- **開場時のlive配信遅延のみ未計測**(実叩きが日曜閉場のため)。実装前の最終checkpointで開場中に再計測する(厳密さは最終checkpointへ集中の原則どおり)
- 設計対象確定: config.py・alpaca_stream.py(新規)・market_data.py・price_updater.py・main.py・FE(api-client.ts/page.tsx/ResultsDisplay.tsx)

## §1 AsIs（現状の一次確認 2026-07-19）

| 項目 | 現状 | 一次確認 |
|------|------|---------|
| 価格ソース | yfinance直叩き(非公式・SLAなし) | `backend/app/services/market_data.py` L7 `import yfinance` |
| 取得方式 | pull型: PriceUpdaterServiceが**5分間隔ポーリング**、銘柄間2秒待ち×追跡18銘柄、リトライ3回 | `price_updater.py`(PRICE_UPDATE_INTERVAL_SECONDS=300) |
| 配信方式 | DiskCache(TTL)にbackendが書き、FEがキャッシュを読む | `cache.py` |
| 実効遅延 | **最悪≈6分**(5分間隔+取得約40秒)+yfinance自体の遅延(保証なし) | 構造から導出 |
| 市場状態判定 | yfinance marketStateが信頼できず時刻ベース判定で代替 | `market_data.py` docstring注記 |
| 月末open/close精度 | yfinance調整値。database/DM-Signal(EODHD生値+自前調整)と**ソース不一致** | `database/docs/price-data-source-plan.md` |
| 構造的限界 | pull型は「間隔短縮⇔レート制限」のトレードオフから抜けられない | — |

## §2 ToBe（二層構成）

| 層 | ソース | 経路 | 遅延目標 |
|----|--------|------|---------|
| リアルタイム表示 | **Alpaca IEX WebSocket(無料枠・公式)** | WS購読→backendメモリ→**SSEでFEへ即時配信**(end-to-end push) | **秒未満** |
| 確定値・モメンタム計算 | **EODHD現行プラン**(生値+自前調整、databaseと同一ソース) | 閉場中・月末計算はEOD確定値 | 日次確定 |
| ^VIX(指数) | Alpaca対象外 → 現行経路維持 or EODHD delayed(比較選定=cmd_4087 AC2) | 別枠 | 参考表示 |
| 為替USD/JPY | 同上(cmd_4087 AC2で選定) | 別枠 | — |

- yfinance経路は**フォールバックとして残置**(WS切断・レート超過時の自動退避)→置換は可逆
- 閉場中はWSを止めEOD確定値へ切替(動かない値を流さない+月末open/close整合)

## §3 5W1H

| 問 | 答 |
|----|-----|
| **Why** | pull型5分ポーリングの構造的遅延(≈6分)と非公式yfinance依存の排除。月末open/closeをdatabase/DM-Signal研究と同一ソースにしモメンタム計算の整合を取る(殿懸念2026-07-03) |
| **What** | 価格経路をpush型二層(Alpaca IEX WS=表示/EODHD=確定値)へ置換。FEはSSE受信 |
| **When** | cmd_4087偵察(実叩き実測)→実装cmd(可逆・フォールバック付き)→本番反映。急がず品質優先 |
| **Where** | `rebalancer/backend/app/services/market_data.py`+`price_updater.py`(置換)、FE(SSE受信)、Render(Singapore、WS常時接続) |
| **Who** | 偵察=忍者(cmd_4087実行中)、実装=忍者(家老配備)、検分=軍師+将軍、裁定=殿 |
| **How** | 追加課金ゼロ: AlpacaキーはStock Database PJ `.env`に登録済み(ALPACA_API_KEY_ID/SECRET、無料Basic)。WS購読→メモリ最新値→SSE。EODHDキーも既存契約流用 |
| **How much** | 追加$0(Alpaca無料+EODHD現行固定)。実装工数=偵察AC2で見積 |

## §4 リスクと対処

| リスク | 対処 |
|--------|------|
| IEXフィードはSIP統合値でない(IEX取引所の約定のみ) | 表示用途には十分。乖離監視はEOD確定値との日次突合で担保 |
| WS切断・レート超過 | yfinanceフォールバック自動退避+再接続バックオフ(設計=cmd_4087 AC2) |
| ^VIX・為替がAlpaca対象外 | 別経路比較表で選定(cmd_4087 AC2)。参考表示はdelayed許容 |
| Render無料/低プランのWS常時接続安定性 | 偵察で接続持続を実測。必要ならkeepalive設計 |
| FE側がポーリングのままだと効果ゼロ | SSE化をToBeの必須要素として同一設計に含める(end-to-end) |

## §5 工程表(Phase名参照。cmd番号は起票時にLS086照合表へ記録)

| Phase | 内容 | 起票cmd | 状態 |
|-------|------|---------|------|
| P0 偵察 | Alpaca実叩き実測+^VIX/為替選定+置換設計 | cmd_4087 | **実行中** |
| P1 backend置換 | market_data.py WS化+フォールバック+閉場切替 | 未起票(P0結果待ち) | — |
| P2 FE配信 | SSE受信化+表示更新 | 未起票 | — |
| P3 本番検証 | Render上でのWS安定性+遅延実測+EOD突合 | 未起票 | — |

## 因果リンク

- ← [[殿発案_rebalancer価格経路_20260719_1803]] → [[EODHDプラン固定制約_1854]] → [[Alpaca_IEX_WS二層構成]]
- → [[cmd_4087]] P0偵察
- → [[self-improvement-loop-candidates-20260719]] P7 rebalancer(CI時間・価格更新成功率の台帳化と将来接続)
- → [[price-data-source-plan]] database側の価格ソース三本立て(EODHD+Tiingo+Alpaca)
