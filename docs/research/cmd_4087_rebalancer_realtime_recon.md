# cmd_4087 rebalancerリアルタイム価格偵察

実測: 2026-07-19 19:04 JST / Alpaca IEX無料枠。秘密値は記録していない。
origin: `[[Alpaca_IEX_WS二層構成偵察cmd_4087]] -> [[pull型ポーリング6分遅延]] -> [[Alpaca_push+EODHD確定値]]`

## §1 結論

18 ETFは全銘柄を単一IEX WebSocketで購読できる。無料枠の実測上限は30 symbols/connection（30成功、31はerror 405）。表示はAlpaca push、計算確定値は既存EODHD経路を維持する二層化が実現可能。

## §2 Alpaca実叩き

| 計器 | 実測 |
|---|---:|
| 認証 | success / 163.6 ms |
| TRACKED_TICKERS購読 | 18/18 success / 157.7 ms |
| 購読境界 | 19,20,25,30 success; 31 error code 405 |
| REST latest quotes | 18/18 / HTTP 200 / 532.7 ms |
| REST rate header | limit 200, remaining 199（1 request後） |
| live quote到達 | 8,006.3 ms待機で0件（米国市場閉場中） |
| latest quote age | min 133,592.778 s / median 137,167.396 s / max 137,171.373 s |

quote ageは閉場時の最終IEX quoteから実行時刻までであり、開場中の配信遅延ではない。開場中のevent timestamp→受信monotonic差は実装前最終checkpointで再計測が必要。

## §3 非ETFの現実解

| 対象 | 現行維持 | EODHD delayed | 代替 | 採用判断 |
|---|---|---|---|---|
| `^VIX` | yfinance polling | EODHD `VIX.INDX` intraday/EOD（契約プラン範囲を実装時確認） | CBOE公式delayed | リアルタイム表示のETF 18銘柄と分離し、当面現行維持。IEX株式feedへ混ぜない |
| `USDJPY` | Open Exchange Rates→ExchangeRate-API fallback | EODHD `USDJPY.FOREX` delayed/intraday | 専用FX WS | リバランス計算の確定値は現行経路維持。UI即時性が必要になった時だけ別stream |

## §4 置換設計

| 順序 | 変更対象（現行行） | 変更 | 波及・テスト |
|---:|---|---|---|
| 1 | `backend/app/config.py:7-19` | Alpaca feed、30-symbol上限、stale閾値を設定 | 18銘柄契約は`backend/tests/test_price_updater.py:17-42`を維持 |
| 2 | 新規 `backend/app/services/alpaca_stream.py` | 単一WS、auth→18 quotes subscribe、再接続backoff、event timestamp/sequence、latest map | 新contract test: 18購読、31 BLOCK、切断復帰、古いevent非上書き |
| 3 | `backend/app/services/market_data.py:200-337` | 読取をlatest map優先へ。yfinance直取得は緊急fallbackへ降格。EODHD確定値とのprovenanceを分離 | `backend/tests/test_price_updater.py:122-199`のfetch/cache mockをprovider境界へ更新 |
| 4 | `backend/app/services/price_updater.py:65-115` | 5分全銘柄pollをEODHD確定値refresh + WS health監視へ変更 | retry、閉場、stale fallback testを更新 |
| 5 | `backend/app/main.py:24-44,83-109` | lifespanでWS taskを開始し、`GET /api/market-stream` SSEを追加 | API disconnect/cancel、Last-Event-ID、CORS contract test |
| 6 | `frontend/lib/api-client.ts:20-75` | SSE clientを追加 | reconnect・duplicate event・cleanup unit test |
| 7 | `frontend/app/page.tsx:16-32,123-130` と `frontend/components/ResultsDisplay.tsx` | live表示用stateを追加。計算submitはEODHD確定snapshotを使用 | 表示価格と計算価格を混同しないUI test |

依存順序は provider→latest store→SSE→FE。WS受信前は確定cache、閉場時はlast quoteへ`stale=true`、切断時は指数backoff+jitter、429/405時は購読拡張禁止、event timestamp逆行時はdiscard。二層の`source`/`as_of`/`is_final`をAPI型で強制し、Alpaca表示値をリバランス計算へ暗黙流入させない。

## §5 D7

docs/data-only偵察のため実行testは免除。実装時は新behaviorなので、provider contract、SSE lifecycle、FE reconnectを新規/拡張contract testとして配置する。一時probeは成果物へ数値を転記後に削除する。
