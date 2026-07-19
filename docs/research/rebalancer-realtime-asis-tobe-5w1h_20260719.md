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
| リアルタイム表示 | **Alpaca IEX WebSocket(無料枠・公式)** | WS購読→backendメモリ→**SSEでFEへ即時配信**(end-to-end push) | **秒未満**(Render Singapore↔日本のRTT 100-200msを含む。実用上問題ない水準) |
| 確定値・モメンタム計算 | **EODHD現行プラン**(生値+自前調整、databaseと同一ソース) | 閉場中・月末計算はEOD確定値 | 日次確定 |
| ^VIX(指数) | Alpaca対象外 → 現行経路維持 or EODHD delayed(比較選定=cmd_4087 AC2) | 別枠 | 参考表示 |
| 為替USD/JPY | 同上(cmd_4087 AC2で選定) | 別枠 | — |

- yfinance経路は**表示専用フォールバックとして残置**(WS切断・レート超過時の自動退避)。**silent fallback禁止**: degraded/stale/sourceをUIへ明示し、**計算確定値には絶対に使用しない**(家老レビュー③)
- 閉場中はWSを止めEOD確定値へ切替(動かない値を流さない+月末open/close整合)
- **provenance境界(家老レビュー①)**: 表示値(Alpaca)と計算確定値(EODHD)を型とAPIで分離 — StockPriceResponse/RebalanceResultへsource/as_of/is_finalを追加し、Alpaca値の計算混入0件を型で強制。計算確定値はEODHD 100%

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
| Alpaca APIキーの失効・更新 | 現時点で有効期限なし(無料Basic)。将来のキー更新に備え、キーはStock Database PJ `.env`を正本とし両PJで同期する運用を注記 |
| 秘密配備(家老レビュー②) | rebalancer render.yamlにAlpaca/EODHD envは現状ない。database/.envのruntime参照は禁止し、**Render secretとして独立配備**+非ログ+rotation手順をACへ固定 |
| プロセスモデル(家老レビュー④) | 現global singletonはsingle uvicorn worker前提。**workers=1を不変量化**するかleader/fanout設計。restart時generation更新必須 |
| 市場カレンダー(家老レビュー⑤) | 現行の平日+時刻判定は祝日・early closeを誤る。**Alpaca clock APIまたは取引所calendarを正本**にし、pre-open接続・extended-hours方針を明記 |
| IEXのquote活発性 | 18/18購読可でも全銘柄で活発なquoteは保証されない。symbol別age/coverageとEOD乖離を監視。healthzはstream auth/subscription/freshness/degradedを分離 |
| SSE配信契約(家老レビューP2) | per-client bounded queue・heartbeat・slow consumer切離し・snapshot+generation+sequence・Last-Event-ID再開・restart時snapshot強制・CORS/接続上限を契約化。EventSourceのexactly-onceを仮定しない |

### §4.1 EODHD secret rotation runbook（単一token制・殿指摘2026-07-19 20:38で改訂）

**前提制約(殿確認)**: EODHDのAPI tokenは**1アカウント1つのみ**。再発行(regenerate)すると旧tokenは即失効し、新旧並行期間は存在しない。よって「新token発行→検証→旧失効」のgraceful rotationは**不可能**。

**方針: rotationは漏洩時の緊急手段のみ。日常運用ではrotationしない。第一防御は漏洩させないこと。**
- 漏洩防御(実装済み・恒久): tokenのログ/エラー/URL露出0件をP1a契約テストで固定(EODHDRequestError sanitize、cmd_4088 fix R1)。これが本線の防御
- 消費PJが増えるほど漏洩面が広がるため、token利用箇所は各PJのRender secret(独立配備)に限定し、コード・設計書・Gitへの記載は永久禁止

**緊急rotation手順(漏洩検知時のみ)**:
1. 影響同時性を受容する: regenerate実行の瞬間から全消費者(database本体・databaseのdaily cron・rebalancer backend)が401になる。EODは日次データのため、cron実行時刻(JST 08:00/17:00)を避けた時間帯に実施すれば実害は最小
2. EODHD管理画面でregenerate→新token値を取得(非ログ・非記載)
3. **両PJのRender secretを続けて更新**: database側`EODHD_API_KEY`等→rebalancer側`EODHD_API_TOKEN`→両backend再deploy
4. 検証: database側daily-update系のhealth+rebalancer側EOD取得18/18+既存テストFAIL0/SKIP0
5. rollbackは存在しない(旧token失効済み)ため、手順3-4を完了させることが唯一の復旧路。途中放置は片PJ 401継続=最悪状態
6. 事後: 漏洩経路の根治(ログ・エラー・履歴)を確認してからクローズ。漏洩検知→クローズまでを1セッションで完結

## §5 工程表(Phase名参照。cmd番号は起票時にLS086照合表へ記録)

家老レビュー(blt_20260719_191948)で「P1一括は責務過大」の指摘によりP1をa/b/cへ分割。

| Phase | 内容 | 起票cmd | 状態 |
|-------|------|---------|------|
| P0 偵察 | Alpaca実叩き実測+^VIX/為替選定+置換設計 | cmd_4087 | 完了(購読+設計の範囲でAC正規化。開場時遅延はP3へ) |
| P1a 型/確定値 | provenance型(source/as_of/is_final)+EODHD adapter+Render secret独立配備 | cmd_4088(+fix R1) | 完了(GATE CLEAR、commit 2023dbf/31d071c) |
| P1b ストリーム | Alpaca stream/latest store+calendar正本+health分離 | cmd_4089 | 完了(GATE CLEAR、commit f31c5a0) |
| P1c 耐障害 | resilience+fallback可視化(degraded/stale明示) | cmd_4090 | 完了(GATE CLEAR、commit df4ccf9) |
| P2 FE配信 | SSE契約(bounded queue/heartbeat/再開/snapshot)+FE受信化 | cmd_4091 | 起票済み |
| P3 本番検証(最終checkpoint) | 米国市場開場中の全銘柄subscription ACK+event→backend→SSE→browserの段階別p50/p95/max実測+WS強制切断・Render restart・SSE再接続のrecovery検証(duplicate0/out-of-order0)+終値EODHD突合+Alpaca計算混入0+秘密値ログ0の二値化 | 保留: P2完了かつ米国市場開場時間帯に起票(厳密さは最終checkpointへ集中) | — |

## 因果リンク

- ← [[殿発案_rebalancer価格経路_20260719_1803]] → [[EODHDプラン固定制約_1854]] → [[Alpaca_IEX_WS二層構成]]
- → [[cmd_4087]] P0偵察
- → [[self-improvement-loop-candidates-20260719]] P7 rebalancer(CI時間・価格更新成功率の台帳化と将来接続)
- → [[price-data-source-plan]] database側の価格ソース三本立て(EODHD+Tiingo+Alpaca)
