<!-- gist-master: e131b06c137d3da41ad28df6373e7601 rebalancer-market-phase-asis-tobe-5w1h_20260804.md -->
# rebalancer市場フェーズ 米国株式市場SSOT統一 AsIs/ToBe 5W1H設計書 v1.4 【✅実装完了・検証進行中(コード面+CDP CLOSED実測PASS/残=開場時間帯RT実測)】

> v1.4覚醒更新(2026-08-04 16:17 殿指示『覚醒してアップデートせよ』): §検証状況を新設し実測進捗を反映。v1.3軍師指摘(a)のis_open=true→REGULAR前提を§1へ明記済み

> 実装状態(v1.3 2026-08-04 15:01 将軍一次確認): §実装分解の3cmdは家老配備で**全て実装完了**。cmd_4227=`e3c4565`(clock snapshot phase SSOT) / cmd_4228=`e26ba81`(語彙4値統一+未知語彙warn) / cmd_4229=`f202c57`(表示=計算price snapshot統一・GATE CLEAR 14:38)。HEAD=origin/main一致(push済み)。contract fixture=backend/tests/test_price_snapshot_contract.py他

## §検証状況(v1.4新設 — 2026-08-04 16:17時点の一次証跡)

| 面 | 状態 | 証跡 |
|---|---|---|
| コード面 | ✅PASS | cmd_4228: backend 55+frontend 6テスト全PASS・build rc0・旧語彙rg残存0件 / cmd_4229: 58テスト全PASS・CI run 30876539561 GREEN・deploy health status=ok deploy_commit=f202c578(軍師レビュー記録12:36/13:15 APPROVE) |
| CDP実画面(CLOSEDフェーズ) | ✅PASS | 疾風recon2実測2026-08-04 15:26 JST(隔離CDP・本番FE): CLOSED表示、GDX $76.05、POST /api/calculate-rebalance 200のresponse source=eodhd / as_of=2026-08-03T00:00:00Z、表示値一致(=ユーザー報告INS-20260804-023042の再現条件で正常動作を確認) |
| 設計書v1.3独立レビュー | ✅APPROVE | 軍師blt_150656: §1-§4全契約項目が3commitで実装済み・未実装0件・TTL=300秒定数明示+テスト検証済み・旧語彙残存0件・fixture全7件WBS通り。指摘(a)is_open前提→§1へ明記済み、(b)snapshot独立呼出し(実害なし)=既知事項として記録 |
| CDP実画面(PRE/REGULARフェーズ) | ⏳残 | 開場時間帯(夏時間: PRE=JST17:00〜/REGULAR=JST22:30〜)でRT価格反映+フェーズ表示を実測する第2弾検証。家老が計画・配備 |

> レビュー状態: 軍師=**APPROVE**(blt_105137: AsIs因果=現物一致・殿裁定全件整合・DAG直列妥当。指摘=clock fail-safe閾値未明示) / 家老=**REVISE**(blt_105152: 必須修正4件)→**本v1.2で全点反映**(相互不可視の独立査読、将軍が2026-08-04 10:55に統合)

> 状態: v1.2(2026-08-04 10:55 独立レビュー反映 — §1にclock snapshot層(取得者/TTL/失敗fallback/pure関数境界)+祝日導出の是正(is_open単独は祝日oracleにならない)、§3にprice snapshot SSOT+phase遷移時RT残値無効化+CLOSED値freshness契約、§4にcontract fixture WBSを追加) / v1.1(2026-08-04 10:55 殿指示10:50『各種APIと株価の取得、フロー、時間(日本時間、米国時間)との関係、米国市場のみを扱うこと、サマータイムの考慮なども盛り込んでくれ』→§API台帳・§価格フローを追加。**殿裁定2件を確定: 10:51『closedの時間帯はEODHDの直近終値表示だ』/ 10:54『表示価格と計算価格は同じものを使う』**) / 初版起草(2026-08-04 10:45。殿裁定10:31『市場フェーズは米国株式のみなので米国株式市場に合わせてくれ。サマータイムの考慮もしよう』+殿指示10:42『リバランサーの設計書もasis/tobeで作成してくれ』)
> 発端: ユーザー報告(2026-07-31 09:00 JST)『リバランスアプリで現在値が反映されません。ステータスは「市場クローズ」となっていて現在価格が7月31日の終値になっています』(INS-20260804-023042)

## §META — 5W1H

| 項 | 内容 |
|---|---|
| WHY | 市場フェーズ判定が**3系統併存**し語彙も窓も不一致。特にrebalance結果の`market_state`はフェーズ語彙の不一致によりFEで**場中でも常に「市場クローズ」表示**になる実バグ(ユーザー報告の正体・下記AsIs-C) |
| WHAT | フェーズ判定を米国株式市場セッション(ET基準・DST自動)の**単一SSOT関数**へ統一し、BE/FE語彙を1対1にし、接続・計算・表示の全消費者を同SSOTへ載せ替える |
| WHO | 実装=忍者(家老配備)。レビュー=軍師。裁可=殿 |
| WHEN | 本設計書の裁可後。1道具1CMD(cmd_4227 draft起票済み・保存保留中) |
| WHERE | `/mnt/c/Python_app/rebalancer/backend`(market_data.py / alpaca_stream.py / rebalance.py)+FE `components/ResultsDisplay.tsx`(語彙表) |
| HOW | SSOT関数1本+語彙統一+DST境界fixture。下記§ToBe |

## §API台帳(v1.1追加 — 全外部取得先・現物確認済み)

| API | エンドポイント | 取得物 | 呼出しタイミング | 場所 |
|---|---|---|---|---|
| Alpaca IEX WS | `wss://stream.data.alpaca.markets/v2/iex`(trades購読・18銘柄固定) | リアルタイム約定値 | PRE/REGULAR/POST中は常時接続(push型) | `alpaca_stream.py:23` |
| Alpaca Clock | `https://paper-api.alpaca.markets/v2/clock` | `is_open`/`next_open`(祝日・早引けの真) | 接続判定時+接続中60秒ごと | `alpaca_stream.py:24,138` |
| EODHD EOD | `https://eodhd.com/api/eod/{SYM}.US`(period=d, order=d, 直近10日) | **確定終値**(adjusted_close優先の最新行) | CLOSED時の価格取得(pull型) | `eodhd.py:25,40` |
| yfinance | ライブラリ経由(`yf.Ticker.info`) | 参考現在値(regularMarketPrice→currentPrice→postMarket→preMarket順) | Alpaca切断・欠落時のfallback(degraded明示) | `market_data.py:235` |
| Open Exchange Rates | `https://openexchangerates.org/api/latest.json` | USD/JPY為替 | rebalance計算時(円換算表示用) | `exchange_rate.py:37` |
| exchangerate-api | `https://api.exchangerate-api.com/v4/latest/USD` | USD/JPY為替(第2 fallback) | 第1失敗時 | `exchange_rate.py:53` |

- **米国市場のみを扱う**: 銘柄はUSD建て米国上場ETF 18種固定(`config.py:7 TRACKED_TICKERS`)。非USD銘柄はrebalance時に400拒否(`rebalance.py:80-82`)。∴市場フェーズも米国株式市場(NYSE/Nasdaq)の1系統だけでよい — 複数市場対応の余地を残す必要なし(殿裁定10:31の根拠)

## §価格フロー(v1.1追加 — フェーズ×時刻×ソースの一枚図)

```
                    ET基準セッション(DST=America/New_YorkでEDT/EST自動切替)
  ┌──────────┬───────────────┬───────────────┬────────────────────┐
  │ PRE       │ REGULAR        │ POST           │ CLOSED              │
  │ 04:00-9:30│ 09:30-16:00    │ 16:00-20:00    │ 左記以外+週末+祝日  │
  ├──────────┴───────────────┴───────────────┼────────────────────┤
  │ Alpaca IEX WS 常時接続(push)               │ WS切断              │
  │ 価格 = RT約定値(表示・計算とも同一値)       │ 価格 = EODHD直近終値 │
  │ 欠落銘柄のみ EODHD/yfinance(degraded明示)  │ (表示・計算とも同一値)│
  └──────────────────────────────────────────┴────────────────────┘
  JST対応(夏時間EDT): PRE=17:00-22:30 / REGULAR=22:30-翌5:00 / POST=翌5:00-9:00 / CLOSED=9:00-17:00
  JST対応(冬時間EST): PRE=18:00-23:30 / REGULAR=23:30-翌6:00 / POST=翌6:00-10:00 / CLOSED=10:00-18:00
  切替日: 3月第2日曜(EST→EDT)・11月第1日曜(EDT→EST) — ZoneInfoが自動処理、fixtureで境界固定
```

- **表示価格と計算価格は同じものを使う(殿裁定10:54)**: フェーズごとに価格ソースは1つ。表示だけRT・計算だけ終値のような分岐を持たない(AsIsの`_get_calculation_prices`と表示系の二重取得を単一価格レイヤーへ統合)

## §AsIs(2026-08-04 10:34-10:44 将軍一次実測・全て現物行番号)

### A. フェーズ判定が3系統併存

| 系統 | 場所 | 語彙 | セッション定義 | 用途 |
|---|---|---|---|---|
| A1 表示用タイムベース | `market_data.py:18-51 get_current_market_state()` | PRE/REGULAR/POST/CLOSED | PRE=ET04:00-09:30 / REGULAR=09:30-16:00 / POST=16:00-20:00。週末=CLOSED。**祝日非考慮** | yfinance系表示のmarket_state |
| A2 接続ポリシー | `alpaca_stream.py:148-168 connection_policy()` | pre_open/open/after_hours/closed | pre_open=**開場30分前から**(`PRE_OPEN_CONNECT_MINUTES=30`) / open=Alpaca clock `is_open` / after_hours=平日ET**13時**〜20時(`AFTER_HOURS_START_HOUR_ET=13`固定・早引け日対応の意図) | WS接続要否+計算価格の`active_phases`判定(`rebalance.py:13`) |
| A3 結果表示への転記 | `rebalance.py:86-89` | A2語彙を`.upper()`しただけ(**PRE_OPEN/OPEN/AFTER_HOURS/CLOSED/UNKNOWN**) | — | RebalanceResultの`market_state` |

### B. 系統間の実害となる不一致

1. **プレマーケット窓の不一致**: 表示(A1)はET04:00からPREだが、接続(A2)は開場30分前(ET09:00)まで`closed`。→ **ET04:00-09:00はPRE表示なのにRT接続なし・計算はEODHD終値**(殿裁定『プレ=RT』と不一致)
2. **語彙不一致による恒常「市場クローズ」表示(ユーザー報告の正体)**: FE `ResultsDisplay.tsx:16-42`のラベル表はPRE/REGULAR/POST/CLOSEDのみ。A3が返す`OPEN`/`PRE_OPEN`/`AFTER_HOURS`は表に無く、`marketStateLabels[state] || CLOSED`のfallbackで**場中を含む全時間帯が「市場クローズ」表示**になる
3. **A1は祝日・早引け非考慮**(週末のみ)。A2はAlpaca clockで祝日対応済み — 真の休日SSOTが片系統にしかない

### C. サマータイム(DST)の現状

- tz処理は現状**全て`ZoneInfo("America/New_York")`経由**(`market_data.py:14` / `alpaca_stream.py:159-160`)で、EDT/EST切替はZoneInfoが自動処理。**固定UTCオフセットのハードコードはgrep 0件**(将軍実測10:34)
- ∴DSTは「壊れている」のではなく「**fixtureテストで固定されていない**」が現状。切替日(3月第2日曜/11月第1日曜)の境界検証が存在しない

### D. ユーザー報告との整合

報告(7/31 09:00 JST=7/30 20:00 ET=after_hours終了直後)の「市場クローズ+終値」は時刻上は設計通りだが、**B-2の語彙バグにより場中でも同じ「市場クローズ」が出続けるため、ユーザーが観察した「いつ見てもクローズ」は実バグ**。表示価格がRT反映されない体感もB-1(プレ窓不一致)が寄与。

## §ToBe

### §1 フェーズSSOT関数1本(米国株式市場セッション・ET基準)

| フェーズ | セッション(ET) | JST(夏時間) | JST(冬時間) |
|---|---|---|---|
| PRE | 04:00-09:30 | 17:00-22:30 | 18:00-23:30 |
| REGULAR | 09:30-16:00 | 22:30-翌05:00 | 23:30-翌06:00 |
| POST | 16:00-20:00 | 翌05:00-09:00 | 翌06:00-10:00 |
| CLOSED | 上記以外+週末+祝日 | — | — |

- 実装: `get_current_market_state()`(A1)を正としてSSOT化。二層構造(家老RC2):
  - **clock snapshot層**: Alpaca clockの取得者を1箇所に限定(alpaca_streamの60秒refreshを流用)し、snapshot(`timestamp/is_open/next_open/next_close`+取得時刻)を保持。**TTL=300秒**(gunshi指摘のfail-safe閾値を明示: TTL超過・取得失敗時はタイムベース判定のみで動作し、snapshotをフェーズ判定に使わない)
  - **pure phase関数**: 入力=(now_utc, clock_snapshot|None)のみの純関数。外部API直結禁止=テスト容易性と決定性を保証
- **祝日・早引けの導出是正(家老RC1)**: `is_open=false`は通常のPRE/POSTでも成立するため単独では祝日oracleにならない。**trading-day判定=next_open/next_closeから導出**: (a)当日ET日付に取引セッションが存在しない(next_openが翌営業日)→祝日=CLOSED (b)早引け日=`next_close`がET16:00より早い→REGULAR終端とPOST開始をnext_closeへ繰上げ
- tzは`ZoneInfo("America/New_York")`限定(固定オフセット禁止)。**DSTはfixtureで固定**: EDT期(2026-07-01)・EST期(2026-01-15)・切替日(2026-03-08 / 2026-11-01)の4時点×各セッション境界
- A2の`PRE_OPEN_CONNECT_MINUTES=30`窓と`AFTER_HOURS_START_HOUR_ET=13`固定は**廃止**(早引けはnext_close導出が吸収)
- **is_open=true→REGULARマッピングの前提(v1.3軍師レビュー指摘(a)の明記)**: clock snapshotの`is_open=true`はAlpaca定義で通常セッション中のみ真となるため、pure phase関数は`is_open=true`をREGULARへ直接マッピングする。PRE/POSTは`is_open=false`かつタイムベース窓内で判定する

### §2 語彙統一(1対1)

- BE内部・API応答・FEラベル表を**PRE/REGULAR/POST/CLOSEDの4値のみ**に統一。`rebalance.py`の`.upper()`転記を廃止しSSOT関数の戻り値を直接使用
- FE `marketStateLabels`のfallback(`|| CLOSED`)は維持するが、**未知語彙が来たらconsole.warn**(黙って市場クローズに化ける再発を検出可能に)

### §3 消費者の載せ替え(フェーズ→価格ソース対応表・**表示=計算で同一値**)

| フェーズ | WS接続 | 価格(表示・計算共通 — 殿裁定10:54) |
|---|---|---|
| PRE / REGULAR / POST | 接続 | Alpaca RT(is_final=False)。欠落銘柄のみEODHD/yfinance(degraded明示) |
| CLOSED | 切断 | **EODHD直近終値(殿裁定10:51)**。store残値・yfinance任せを廃止 |

- 殿裁定(cmd_4225)『プレ/オープン/アフター=RT・クローズ=終値』に完全整合。表示専用と計算専用の二重取得経路(AsIsの`_get_calculation_prices`+`/stock-prices`)を単一価格レイヤーへ統合し、同一時刻の表示と計算結果が食い違う可能性を構造的にゼロにする
- **price snapshot SSOT(家老RC3)**: 表示=計算の同一性は「同じ関数を呼ぶ」でなく「**同一のprice snapshot(銘柄→{price, as_of, source, is_final, freshness}辞書)を両者が参照する**」で担保する。契約:
  - **phase遷移時のRT残値無効化**: POST→CLOSED遷移でstoreのRT値を失効させ、CLOSED中にRT残値が表示・計算へ漏れることを禁止(ユーザー報告の残根)
  - **CLOSED時のEODHD値契約**: `as_of`=終値日付・`source=eodhd`・`is_final=true`を必須とし、freshness(取得からの経過)をsnapshotへ記録。取得失敗時は前snapshotを保持しdegraded明示(無言のyfinance差替え禁止)

## §4 contract fixture WBS(v1.2追加・家老RC4 — 各cmdへ割付、永続testは全件test_necessity宣言)

| fixture | 検証する不変量 | 割付cmd |
|---|---|---|
| DST 4時点×セッション境界 | ET壁時計とフェーズの対応がEDT/EST/切替日で不変 | 1 |
| 祝日(next_open翌営業日) | 平日でも取引セッション不在日はCLOSED | 1 |
| 早引け(next_close<16:00) | REGULAR終端/POST開始がnext_closeへ繰上がる | 1 |
| clock失敗/TTL超過 | タイムベース判定のみへfail-safeし例外を漏らさない | 1 |
| 未知語彙 | FEがconsole.warnを出しCLOSEDへfallback | 2 |
| 表示=計算identity | 同一snapshot参照で両者のprice/as_ofが完全一致 | 3 |
| phase遷移stale残値 | POST→CLOSED遷移後にRT残値が表示・計算へ漏れない | 3 |

## §実装分解(依存DAG・1道具1CMD — 家老レビューで責務再定義)

| # | cmd | 内容 | 依存 |
|---|---|---|---|
| 1 | clock snapshot層+pure phase関数+fixture(DST/祝日/早引け/clock失敗) | §1。旧2系統の分岐残存grep 0件まで | なし |
| 2 | 語彙4値統一+FE未知語彙警告 | §2。BE/FE往復の語彙1対1をテスト固定 | 1 |
| 3 | price snapshot SSOT統合(接続・計算・表示の載せ替え+RT残値無効化+CLOSED値契約) | §3。identity/stale fixtureで固定 | 1,2 |

- cmd_4227(draft済み)は本設計書裁可後に1-3へ分割再構成して保存する

## §decision ledger

| 項 | 状態 |
|---|---|
| フェーズ=米国株式市場セッションに統一 | **殿裁定2026-08-04 10:31** |
| DST=ZoneInfo自動+fixture固定 | 同上(『サマータイムの考慮もしよう』)。現物は既にZoneInfoで壊れていない=検証欠如の是正 |
| 語彙4値統一(PRE/REGULAR/POST/CLOSED) | 提案。裁可対象 |
| CLOSED時=EODHD直近終値表示 | **殿裁定2026-08-04 10:51**(ユーザー報告への仕様回答を兼ねる) |
| 表示価格=計算価格(同一ソース単一レイヤー) | **殿裁定2026-08-04 10:54** |
| 米国市場のみ(フェーズ1系統でよい) | **殿裁定2026-08-04 10:31**+現物根拠(USD建て18銘柄固定・非USD拒否) |
| 起票 | 裁可待ち(cmd_4227はdraft保留中。裁可後§実装分解の3cmdへ再構成) |

## §因果リンク

- → [[rebalancer-realtime-asis-tobe-5w1h_20260719]] 二層構成(Alpaca RT/EODHD終値)の正本。本書はそのフェーズ判定層の是正
- → [[殿裁定_計算の終値固定はバグ_cmd_4225]] フェーズ→価格ソース対応の型元
- → [[INS-20260804-023042]] ユーザー報告(市場クローズ固定表示)=B-2語彙バグの実観測
- origin: `[[殿裁定_市場フェーズ米国株式統一_20260804]] -> [[フェーズ3系統併存+語彙不一致の現物確認]] -> [[SSOT統一+語彙4値+DST_fixture_v1.0]]`
