<!-- gist-master: e590a96ad0b1c541b2ec266d4c6a512b dm-signal-core-simple-free-proof-asis-tobe_20260905.md -->
# DM-Signal Core LP × Simple LP × Free Interactive Proof — AsIs/ToBe 設計書 v0.4(2026-09-05 13:25、殿裁定 13:19: v0.3 の方向で確定・機能を増やさない・優先 5 段=identity 最小保持→campaign_id で Core/Simple→Tier×Page と user.id を Google 連携者だけ結ぶ→測れてから Simple LP 1 本→他は将来候補の記録のみ。原則『測るために必要な最小変更→実験→データを見て次を決める』)/ v0.3 09:30(殿指示 09:18: identity 層=Supabase user.id の保持価値・匿名 visitor_id/Tier 維持・Tier×Page analytics との最小接続・source 引継ぎ・3 サービス緩連携・PF→Rebalancer 導線。3 repo の origin/main を将軍が一次確認)/ v0.2 09:20 / v0.1 02:55

> 殿指示 2026-09-05 02:42。目的=(1) dm-signal.com を SEO・ブランドの Core LP として完成 (2) 商品を変えずに Simple LP 1 本だけの価値を検証 (3) Google Auth→Free tier を Interactive Proof として使えるか確認 (4) Core vs Simple の流入差を計測可能に。**この段階では実装しない**(Simple LP 新設・Free 可視性変更・Tier 変更・sitemap/canonical 変更・Google Auth 変更は殿裁定後)。
> 優先順位=最新の殿裁定 → 最新正本 → 本番実測 → 現行コード → 古い設計書。正本: SEO v6(`dm-signal-lp-seo-plan_20260830.md`、gist 5edb5f6d)/入口 3 面 v3.2(`dm-login-showcase-asis-tobe_v3_20260830.md`、gist 901c36a5)/Free tier v3.3(`dm-free-tier-google-auth-asis-tobe_v3_20260830.md`、gist 897501e0)。
> **v0.1 の空欄**は cmd_4476(偵察、忍者 1 名)の一次結果で埋める。将軍が正本と本番で確認できた範囲だけを書き、未確認は「(4476)」と明記。


## §0.0 前提条件と我らのスタイル(他の LLM・人がこの設計書を読む前に。殿指示 2026-09-05 13:21)

**この設計書を読む者への前提**
- 対象: DM-Signal(本番 https://dm-signal.com、backend=FastAPI+Postgres on Render、frontend=Next.js、LP=`lp/` 静的 export、認証=月次パスワード(Tier)+Google Auth(Supabase、Free tier のみ))。Rebalancer と DM-Fusion は同じ Supabase `auth.users` を共有する別サービス。
- 目的: LP の流入(Core/Simple)→Google Auth→Free 利用→再訪を**測れる**ようにすること。売る機能を増やすことではない。
- 決定権: 殿(オーナー)。将軍(この文書の筆者)は設計と検証まで。実装は殿の go の後に忍者が cmd 単位で行う。
- 現状の事実は §0.2/§A/§L-1 に「file:行番号」付きで書いてある。**推測と事実を混ぜない**。未確認は「(未確認)」と明記する。

**我らのスタイル(この設計書のすべての判断に適用)**
1. **あえて複雑にせず、シンプルに解決する。** 新しい表・新しい識別子・新しい認証経路を足す前に、既存の列や規約で表せないかを先に試す(例: source 列を作らず campaign_id の prefix で表す)。
2. **既存のコードがあればそれを使う。** `visitor-id.ts` と同型で `user-id.ts` を書く、`page_views` に列を足す、のように既に動いている型を複製する。別方式を並立させない。
3. **新規の複雑さを足さない。** 変更量に上限を置く(§M-2)。上限を超える案は「将来候補」に記録して止める。
4. **測るために必要な最小変更 → 実験 → データを見て次を決める。** 測れない実験はしない。Simple LP は計測が動いてから。
5. **壊さない。** 既存の cookie/Tier/password/Google 任意の契約は変えない。nullable 列と optional payload で後方互換を保つ。migration は down まで用意する。
6. **可逆に、小さく、1 cmd ずつ。** 1 cmd=1 段(または密結合の数段)、AC は二値(§M-1 の「完了の二値」列)。本番は readonly で事前確認し、失敗したら restore する。
7. **読み手が別の LLM でも同じ結論に至るように書く。** 事実(何がある)→制約(何を変えない)→判断(何をする)→効果(何が測れる)の順で、file と行番号を添える。

## §0.2 v0.2 で確定した事実(cmd_4476 小太郎、コード行+admin API 生出力。docs/research/cmd_4476_core_simple_free_asis_20260905.md)

| 事実 | 現物 | 設計への影響 |
|---|---|---|
| Free tier は Basic-DualMomentum を **全項目無条件公開** | `GET /api/admin/tiers/free-tier/visibility`: hide_portfolio=false / hide_signal=false / hide_components=false。Current signal・holdings・Components・Trade history・Metrics・Compare・Rolling・Drawdown・Annual/Monthly 全て見える | 「Free で Performance を触らせる Interactive Proof」は **Basic-DM については既に成立**(殿裁定 08-31 16:45『Basic-DM の閲覧は Free』の帰結)。v0.1 §H『無料なら全部は禁止』は Basic-DM 以外の PF に対する禁則として読む |
| L3(mask_signal)/L4(mask_components)の実装範囲 | `/api/signals` `/api/trades` `/api/history` `/api/metrics` `/api/performance` `/api/annual・monthly` には L3/L4 実装あり(hide フラグで有効化)。**`/api/rolling-returns` `/api/drawdowns` `/api/compare-returns` にはマスク機構が無い(L2 hide のみ or 皆無)** | 「代表 Standard/Premium PF の Performance を Free で見せてシグナルだけ隠す」は、Rolling/Drawdown/Compare Returns の 3 route に **新規のマスク実装が要る**(既存機構だけでは Tier leakage)。最小変更ではない |
| campaign_id の持ち回りは live | LP→`/free?campaign_id=`→`/login?coupon=&campaign_id=`→showcase_events(cmd_4474) | **source は新パラメータを作らず campaign_id に載せる**(例 `lp_core_*` / `lp_simple_*`)。Google Auth・coupon の契約に触らない |
| `from=lp` は受け取り処理なし | `free/page.tsx`・`free-experience.tsx` に処理なし(grep 0) | v0.1 §F の「from=lp を source に拡張」は誤り。campaign_id 経路に統一 |
| Google Auth 後の identity は backend で破棄 | `get_free_coupon` が Supabase user を `_` で捨てる。`ShowcaseEvent` に user 列なし。`product_logins` 不在 | 個人単位の retention/LTV は今は測れない(§J)。first/last touch を持つなら `product_logins` 新設(Free v3.3 §4-5 既定案)が唯一の経路 |
| 計測可否 | 今測れる=LP→CTA、LP→Auth 開始(`signup_google`)。少しの実装=Auth 完了(callback 成功分岐に event 1 行)、Auth→Free ログイン(verify-viewer 成功時 event)、Core/Simple 別(campaign 集計に prefix)。今は測れない=Free→note(href すら無い)、Paid/Plan mix(note 側)、retention/LTV | Primary Metric は **LP→Google Auth 完了率(source 別)**=event 1 行追加で取れる。第 2=Auth→Free ログイン率 |

**§E の改訂(v0.2)**: Free Interactive Proof の選択肢は 2 つ。
- **案 A(追加実装ゼロ)**: Basic-DualMomentum の全項目公開を「実物を触る Proof」としてそのまま使う。Simple LP の導線も Basic-DM へ。Standard/Premium は LP の表(CAGR/Sharpe/MDD)で示すのみ。
- **案 B(新規実装あり)**: 代表 Standard/Premium PF を Free に `hide_signal=true, hide_components=true` で開く。ただし Rolling/Drawdown/Compare Returns の 3 route にマスクを新設しないと保有シグナルが漏れる(Tier leakage)。実装は backend 3 route+contract test。
- 将軍の推奨=**まず案 A で Core vs Simple を走らせ、案 B は 4 週の計測結果を見てから**(殿原則『必要になるまで作らない』)。

**§F の改訂(v0.2)**: source=campaign_id の prefix 規則(`lp_core_<date>_<n>` / `lp_simple_<date>_<n>`)。LP が自分の lane の campaign_id を発行(X 由来は既存 `x_<date>_<slot>_<n>` のまま)。追加 event 2 語(`auth_completed`=callback 成功、`free_login`=verify-viewer 成功)。`product_logins` は案 B と同じく後段。

**§I の改訂(v0.2)**: 1 殿裁定(案 A/B、Simple LP 可否、文言方針)→ 2 attribution 最小(campaign_id prefix+event 2 語、frontend 2 file+backend 集計 1 箇所)→ 3 Simple LP 1 本(noindex)→ 4 4 週計測→ 5 案 B は結果次第。

## §A AsIs(将軍 02:16-02:50 一次: 本番 curl+正本 3 本+origin/main の file 一覧)

| 面 | 現物 | 出所 |
|---|---|---|
| Core LP `dm-signal.com` | EN `/`・JA `/ja/`、H1(JA)『次に保有すべきものを、明快に。』、Current signals 表(CAGR→Sharpe→MDD→×N)、hero svg、FoF 1、Members/Free 二分 CTA(`/free?from=lp`)、note membership、`/faq`、JSON-LD 3 型、sitemap 558(月次 Signals 2003-09〜2026-09×EN/JA) | 本番 curl 02:16-02:20、SEO v6 §0/§0.1 |
| 月次 Signals | `/signals/` `/ja/signals/` `/signals/YYYY-MM/`、1 頁 ≈770 字、unique title/description/canonical、prev/next・一覧リンク | 本番 curl、cmd_4436 |
| Free tier | `viewer_tiers` に Free 行(password_env_key=`VIEWER_PASSWORD_FREE`、Basic-DualMomentum 以外 hide、期限は他 tier と同じ月末)。殿実機 e2e PASS 08-31 01:38 | Free v3.3 §2-1、§1.5。**PF 別の可視性現物は未(4476)** |
| Google Auth | app `/free`(static export)→ Supabase `signInWithOAuth(google)`(rebalancer と同一プロジェクト)→ backend `GET /api/public/free-coupon`(Supabase Auth API で本人性検証、secret 不要)→ クーポン表示+Copy+`/login?coupon=` プリフィル | Free v3.3 §2-2〜4、cmd_4422/4423/4424/4428 |
| coupon | 全 Free 登録者に同一の月次コード(既存 tier 方式)。個人別発行なし。月次ローテーションは殿の手作業(+1 行) | Free v3.3 §3 §4-4 |
| visibility 機構 | L2 hide(PF 自体を隠す)/L3 mask_signal(保有シグナルを隠しバックテストは見せる)/L4 mask_components(シグナル公開・構成 ticker を隠す)。matrix 正本 `cmd_2596_visibility_matrix.md` は本 repo に不在(所在確認 4476) | projects/dm-signal.yaml visibility_philosophy |
| Performance 画面 | Rolling/Annual/Drawdown/Metrics/Compare の route と、それぞれがどの visibility 列で制御されるか **未確認(4476)** | — |
| analytics | `showcase_events` step 9 語(`lp_view`/`lp_cta_click` 等)+`campaign_id`(cmd_4474 live、本番 lp_view 1)+`from=lp`。Free 系 3 語(signup_google 等)は未。`product_logins` は Free v3.3 §4-5 で未実装と明記(現物 4476) | 入口 3 面 v3.2 §1.1、Free v3.3 §1.5 §4-5、cmd_4474 |
| note 導線 | LP→note membership(`marketing-info.md` 現物から)、/login→note の当月パスワード | 入口 3 面 v3.2 §0 18:19 |
| app ドメイン | `dm-signal-frontend.onrender.com`(`app.dm-signal.com` は殿裁定 08-31 14:36 で当面保留) | 入口 3 面 v3.2 §1.1 |

## §B 追加実装なしで既にできること
- Google Auth→Free クーポン→`/login?coupon=`→Basic-DualMomentum 閲覧(Free v3.3 live、殿実機 PASS)。
- LP→CTA→Free の経路記録: `lp_view`/`lp_cta_click`+`from=lp`+`campaign_id`(X 由来のみ発行)。
- Core LP の SEO 土台(v6 Already Good 12 項目)。
- **Free で見える範囲は「Basic-DualMomentum のみ」**。Performance 画面(Rolling/Annual/Drawdown/Metrics/Compare)が Free でどこまで見えるかは 4476 の実ログインで確定。

## §C 足りないもの(最小限。実装は裁定後)
1. Core/Simple の識別: `from=lp` を `source=core|simple` へ拡張(または campaign_id に lane を持たせる)。方式は 4476 の現物で決める。
2. Free 系 event 3 語(`signup_google`/`free_coupon_view`/`free_login`)=入口 3 面 v3.2 §2.6 P-E(未)。
3. Free Interactive Proof のための可視性変更(代表 PF の Performance を Free で開く)=**殿裁定事項**。既存 L3 mask_signal で「バックテストは見せてシグナルは隠す」が機構上可能かを 4476 で確認。
4. Simple LP 1 本(実装は裁定後。§D)。
5. `product_logins`(Free v3.3 §4-5 既定案: 行で持ち列で持たない)=first_touch/last_touch を持つならここ。

## §D Core vs Simple 設計(比較表。Simple は Core のコピーにしない)

| 要素 | Core LP(現行・変えない) | Simple LP(仮説。1 本のみ) |
|---|---|---|
| 役割 | SEO・ブランド母艦。DM-Signal とは何か/Dual Momentum/Current Signals/Track Record/Rules-based/Free・Membership 入口。検索意図『デュアルモメンタム シグナル』『dual momentum signals』 | Conversion 実験(Treatment)。『高度な投資システムだが日常運用は非常に簡単』を別の入口から見せる |
| 想定読者 | 検証・数字を見たい人 | 自分で判断できるが投資に時間を使いたくない人(医師専用にしない) |
| Hero/H1 | 『次に保有すべきものを、明快に。』+Current signals 表 | 『月に一度、見て、必要なら入れ替える。それだけ。』系(案。数字より運用の軽さ)。**「初心者でも簡単」「誰でも儲かる」禁止** |
| Subheading | Rules-based / 先出し実績 / 検証可能性 | 毎日相場を見ない/月 1 回 Dashboard/シグナルを見る/必要なら Rebalance/詳しく見たい時だけ詳細へ |
| First viewport | 表+svg | Dashboard の実スクショ(Simple な既存 Dashboard)+使用ステップ 4 つ |
| Proof | Current signals 表・CAGR/Sharpe/MDD・FoF・月次 Signals archive | **数字を並べない**。Free で実物を触る導線(Interactive Proof)+Core への『詳しい検証はこちら』リンク |
| Performance の扱い | 表で提示 | LP には最小(1 行)。Free tier 内で見せる(§E) |
| Free CTA / Membership CTA | Members/Free 二分 | 同じ `/free`・同じ note。source だけ違う |
| FAQ | FAQPage JSON-LD あり | 運用の手間に関する 3 問程度。JSON-LD は付けない(重複回避) |
| Core/Signals/note へのリンク | — | Core・Signals index・note へ各 1 本(archive を複製しない) |
| SEO | index、self-canonical、sitemap、hreflang | **最初は noindex で実験**(§G) |

## §E Free Interactive Proof(どの情報をどこまで Free で見せるか)
体験: Google Auth → Free クーポン → DM-Signal 本体 → 代表 PF を選ぶ → Performance(Rolling/Annual/Drawdown/Metrics/Compare) → Current Signal は Tier に応じて Locked。狙い=「数字を信じてもらう」ではなく「実物を自分で触って確認してもらう」=検証可能性のブランド思想と整合。
**表(4476 で現物を埋める。代表 PF は殿裁定)**: 項目 10=PF 名/Current holdings/Current signal/Components/Trade history/Metrics/Compare/Rolling Returns/Drawdown/Annual・Monthly Returns × 列 4=現行 visibility/Free 公開可否(どの列)/マーケティング価値/有料価値の毀損。原則=『無料なら全部』は禁止。L3 mask_signal(バックテストは見せ、シグナルは隠す)が既存機構にあるので、代表 PF に L3 を当てるのが最小変更の仮説(4476 で機構確認)。

## §F Attribution(Core/Simple の識別)
- 現行: `from=lp`(F3)、`campaign_id`(X→LP、cmd_4474)、`lp_view`/`lp_cta_click`。Google Auth 後の `auth.users` に source を持つ仕組みは未(product_logins 未実装)。
- 案(4476 の現物で確定): `source=core|simple` を LP→`/free?from=lp&source=`→`/login?coupon=`→viewer_session まで持ち回り、`product_logins(user_id, product, source, campaign_id, first_seen)` に **行で** 記録(Free v3.3 §4-5 既定案)。first_touch=最初の行、last_touch=最新行、campaign_id は X 由来のみ。Google Auth・coupon の既存契約は変えない。

## §G SEO 影響
- Simple LP は Conversion 実験であり SEO 母艦ではない。**最初は noindex, nofollow・sitemap 非登録・hreflang なし・self-canonical**。Core との重複率は §D の通り低く保つ(表・archive・Performance データを転載しない)。
- 独立した検索意図(例『投資 手間 月 1 回』)が実験後に確認できたら index を検討(v6 §1『入口は 1 つ、評価も 1 つに集める』を守り、Core の評価を分散させない)。
- Signals archive は複製しない。過去 Signal を書き換えない。

## §H リスク
| リスク | 内容 | 抑え |
|---|---|---|
| 有料価値の毀損 | Free で Performance を開きすぎる | §E 表で項目ごとに判断、Current signal/Components は Locked 維持 |
| SEO cannibalization | Simple が Core と同じ検索語で競合 | noindex で開始、重複率を低く |
| Auth 破壊 | source 持ち回りで OAuth/coupon 契約を壊す | 既存 EP・cookie は不変、行追加のみ |
| Tier leakage | 可視性変更で他 tier の設定が動く | 代表 PF のみ、readonly で事前確認、restore SQL |
| 過剰な無料公開 | 『無料なら全部』 | 禁則として §E に明記 |
| LP 肥大化 | Simple に説明を足し続ける | first viewport+ステップ 4+FAQ 3 で固定 |
| 計測不能 | source が途中で落ちる | §J の 3 分類で「今測れる」だけで Primary Metric を決める |

## §I 推奨実装順(最大 5、全て殿裁定後)
1. cmd_4476 偵察(AsIs 表・可視性×Free 表・attribution・計測可否)→本設計書 v0.2。
2. 殿裁定: 代表 PF/Free で開く項目/source 方式/Simple LP の可否と文言方針。
3. attribution 最小実装(`source=core|simple` 持ち回り+`product_logins`+Free 系 event 3 語)。**Simple LP より先**(測れない実験はしない)。
4. Free Interactive Proof(代表 PF に L3 相当の可視性、readonly 事前確認+restore)。
5. Simple LP 1 本(noindex)→4 週の Core vs Simple 計測→index 可否と継続を判断。

## §J Primary Metric(取得可否 3 分類。4476 で確定)
- 今測れる(見込み): LP→CTA(`lp_cta_click`)、LP→`/free` 到達(`from=lp`)、X 由来の campaign_id。
- 少しの実装で測れる: LP→Google Auth 完了(Free 系 event)、Auth→Free 利用(coupon でのログイン=product_logins)、Core/Simple 別の上記。
- 今は測れない: Free→note、Paid conversion、Plan mix、3M/6M/12M retention、LTV(課金は note 側。DM-Signal に個人課金データが無い)。→ Primary Metric の第 1 候補=**LP→Google Auth 完了率(source 別)**、第 2=Auth→Free ログイン率。CTR 単独で勝敗を決めない。


## §L Identity 層(v0.3、殿指示 09:18)— 「何を既に取得できているか」「何を足せばユーザー単位の分析になるか」

前提=実装しない。Simple LP より先に identity の整理。Google 連携は必須にしない(匿名 visitor_id と Tier/password 利用は維持)。

### L-1 既に取得できているもの(3 repo の origin/main を 09:20-09:28 に一次確認)

| 層 | 現物 | 識別子 | 保存先 | 個人と結びつくか |
|---|---|---|---|---|
| 匿名 visitor | `frontend/lib/visitor-id.ts`: `localStorage["dm_visitor_id"]`=`crypto.randomUUID()`(private browsing では null) | visitor_id(UUID) | `page_views.visitor_id`(`backend/app/db/models.py` L629、index あり) | ブラウザ単位。端末を跨がない |
| Tier × Page | `POST /api/analytics/pageview`(`analytics.py` L97-121): `_extract_tier_info` が **viewer_session cookie** から tier_id/tier_name を解決し、page/device/os/visitor_id と共に `page_views` へ | tier_id, tier_name | `page_views`(timestamp/page/tier_id/tier_name/device_type/os_type/visitor_id) | Tier 単位(同じ月次パスワードを使う全員が同一 tier)。**個人は無い** |
| viewer_session | `backend/app/auth.py` L97 `generate_viewer_token(tier_id, tier_name, expires)`=`ViewerToken` 行(月末失効)。cookie `viewer_session` | token(サーバ側行) | `viewer_tokens` | tier のみ。user 列なし |
| showcase funnel | `showcase_events`(`models.py` L634-646、append-only): step/campaign_id/ua_class/lang/occurred_at | campaign_id | `showcase_events` | 匿名。visitor_id も user も無い |
| campaign 持ち回り | LP `dm_signal_campaign_id`(sessionStorage、`landing-page.tsx` L69)→`/free?campaign_id=`→`free-experience.tsx` L192 で `/login?coupon=&campaign_id=`→`showcase-attribution.ts` が event payload に付与(L44-52) | campaign_id | showcase_events | **Auth 後(`/free`)まで届く。`/login` の verify-viewer と `page_views` には届かない**(auth.py に campaign 0 件、page_views に列なし) |
| Google Auth | `/free`: `signInWithOAuth(google)` → `GET /api/public/free-coupon`(Bearer)→ backend `_fetch_supabase_user`(`public_showcase.py` L181)で Supabase Auth API `GET /auth/v1/user` → **`get_free_coupon` L487 で user を `_` に捨てる** | Supabase `user.id`(UUID) | どこにも保存しない | 取得はしている。保持していない |
| Rebalancer | `frontend/lib/portfolio-storage.ts`: `saved_portfolios` を `user_id` で upsert/select(`onConflict: user_id`) | Supabase `user.id` | Supabase `public.saved_portfolios` | 個人 |
| DM-Fusion | `app/page.tsx` L593 `saved_fusions.eq("user_id", user.id)`、migration `20260629_create_saved_fusions.sql`: `user_id uuid references auth.users(id)`、RLS `auth.uid() = user_id` | Supabase `user.id` | Supabase `public.saved_fusions` | 個人 |
| Supabase プロジェクト | rebalancer `.env.local` と DM-Fusion `.env` の `NEXT_PUBLIC_SUPABASE_URL` は同一 project ref(`qydgtw…`)。DM-Signal frontend は Free v3.3 §1.5 で「rebalancer 正本と hash 一致」 | — | `auth.users` 1 つ | **3 サービスは同一 `auth.users` を既に共有**。user.id は同じ人に同じ値 |

**結論 L-1**: 個人単位の stable identity(Supabase user.id)は DM-Signal でも**取得済みだが未保持**。匿名(visitor_id)と Tier(cookie)の 2 層は既に動いており、これを壊さずに 3 層目として user.id を「行で」足せる状態。

### L-2 殿の 6 論点への回答(事実→判断)

1. **user.id を保持する価値**: あり。3 サービスが同一 `auth.users` なので、保持した瞬間に「DM-Signal の Free 登録者=Rebalancer/DM-Fusion のユーザー」が同一キーで見える。DM-Signal 内でも「Auth 完了→coupon 取得→(同じ月に)ログイン→どの page を見たか」を個人で追える唯一の鍵。**保持しなければ retention/LTV は永久に測れない**(§J)。
2. **匿名 visitor_id と Tier/password 利用は維持、Google 必須にしない**: 維持。user.id は Free(Google)経路にだけ自然に存在し、note メンバー(月次パスワード)には無い。∴ identity は **3 層の任意結合**=`visitor_id`(ブラウザ)⊂ `tier`(cookie)⊂ `user_id`(Google 経路のみ、null 可)。既存 EP・cookie・tier 認証は変えない。
3. **Tier × Page analytics と user.id の最小接続**(案。実装は裁定後):
   - (a) `page_views` に `user_id`(uuid, nullable, index)を 1 列追加。値の出所は **cookie ではなく localStorage** の `dm_user_id`(`/auth/callback` 成功時に `session.user.id` を保存。`visitor-id.ts` と同型の 10 行)。`api-client.ts` L1449 の pageview payload に `user_id` を同送、backend `PageViewPayload` に optional 追加。
   - (b) 突合は既存列で足りる: `visitor_id` が同じ行に `user_id` が付いた瞬間、その visitor の過去 page_views も遡って同一人物と見なせる(visitor_id→user_id の対応表を作らず、クエリで結合)。
   - (c) Tier は cookie 由来のまま(月次パスワードで入った note メンバーは user_id null、tier だけ)。
   - 変更点=frontend 2 file(callback、api-client)+backend model 1 列+migration 1 本(+reverse)。cookie・token・verify-viewer は不変。
4. **Core/Simple の source を Auth 後まで引き継げるか**: campaign_id は `/free`(Auth 後)まで届いている(L-1)。届いていないのは `/login` の verify-viewer と `page_views`。案=(a) `dm_signal_campaign_id` を sessionStorage から localStorage へ格上げ(端末内で月を跨ぐ)、(b) `page_views` に `campaign_id`(nullable)を同送、(c) `showcase_events` に `user_id`(nullable)を同送(Auth 後の step のみ値が入る)。これで **source(campaign_id の prefix `lp_core_`/`lp_simple_`)→Auth→coupon→ログイン→page** が 1 本でつながる。first_touch=その user_id の最古の campaign_id、last_touch=最新。専用 `product_logins` は不要になる(page_views+showcase_events の 2 列追加で代替)。
5. **3 サービスの緩連携**: 既に同一 `auth.users`。**結合キーを新設しない**のが最小。将来やるなら Supabase 側に `public.profiles(user_id pk, first_seen_service, first_campaign_id)` を 1 表(RLS `auth.uid()=user_id`)。DM-Signal backend は Supabase の service key を持たない方針(Free v3.3 §2-3)なので、DM-Signal からの書込みは frontend(anon key+RLS)経由=Rebalancer/DM-Fusion と同じ流儀。今回は記録のみ。
6. **選択中 PF → Rebalancer 導線(将来候補)**: 現行 Rebalancer に外部からの PF 受け取り口は無い(`frontend/app`/`lib` に dm-signal/searchParams 参照 0 件)。候補=DM-Signal の PF 画面に「この配分で Rebalancer を開く」リンク(`https://<rebalancer>/?from=dm-signal&pf=<id>&weights=<url-safe json>`)、Rebalancer 側で query を読んで `saved_portfolios` に upsert(user_id が同じなので本人のもとに保存される)。**記録のみ。実装しない**。

### L-3 「追加すれば個人単位の分析になる」最小差分(裁定用の一覧。優先順)

| # | 変更 | 影響 file | 契約への影響 | 得られるもの |
|---|---|---|---|---|
| 1 | `/auth/callback` 成功時に `localStorage["dm_user_id"]=session.user.id`+event `auth_completed` | frontend `app/auth/callback/page.tsx`(1-3 行) | なし | Auth 完了率(§J の第 1 候補) |
| 2 | `page_views.user_id` + `page_views.campaign_id`(nullable)、payload に同送 | backend `models.py`/`analytics.py`/migration、frontend `api-client.ts` | cookie/token 不変 | Tier×Page に個人と source が乗る。retention(同 user_id の月跨ぎ再訪)が測れる |
| 3 | `showcase_events.user_id`(nullable)、Auth 後 step に同送 | backend `models.py`/`public_showcase.py`、frontend `showcase-attribution.ts` | append-only 維持 | funnel を個人で結ぶ |
| 4 | `dm_signal_campaign_id` を localStorage へ | frontend `showcase-attribution.ts`/`landing-page.tsx` | なし | first/last touch |
| 5 | Rebalancer/DM-Fusion との横断分析 | Supabase 側 SQL(read)のみ | なし | 3 サービスの重なり(user_id 集合の交差) |

やらないこと: Google 必須化、Tier 認証の変更、個人別クーポン、`product_logins` 新設(2-3 で代替)、Supabase service key を backend に置く。

### L-4 cmd_4476 との整合
- 4476 §F「first_touch/last_touch の保持場所なし」「Supabase user id は backend で破棄」「ShowcaseEvent に user 列なし」=本節と一致。4476 は revision_requested(家老レビュー中)だが、本節は将軍が origin/main を直接確認した行番号で書いた。
- §I の順序は変わらない: 裁定 → attribution 最小(本節 #1-#4)→ Simple LP(noindex)→ 4 週計測。**identity 層は Simple LP より前**。

## §M 収束(v0.4、殿裁定 2026-09-05 13:19)— 実装可能な最小単位

**殿裁定(原文の要旨)**: v0.3 の方向性は良い。機能を増やしすぎない。優先順位は次の 5 つだけ。原則=「測るために必要な最小変更 → 実験 → データを見て次を決める」。設計をこれ以上広げず、実装可能な最小単位へ収束させる。

### M-1 5 段の優先順位 → 最小変更への写像(これが実装単位。順序固定、各段は前段の計測が動いてから)

| 段 | 殿の優先順位 | 最小変更(§L-3 の番号) | 触る file(origin/main 09:2x 確認) | 変えないもの | 完了の二値 |
|---|---|---|---|---|---|
| 1 | Google Auth 後の Supabase user.id を捨てず、匿名 visitor_id/password/Tier を壊さず保持 | L-3 #1: `/auth/callback` 成功時に `localStorage["dm_user_id"]=session.user.id`(`visitor-id.ts` と同型)+ event `auth_completed` | frontend `app/auth/callback/page.tsx`、`lib/visitor-id.ts` 隣に `lib/user-id.ts`(新規 10 行) | cookie `viewer_session`、`verify-viewer`、tier 認証、Google 任意、backend の `get_free_coupon`(user を保存しない現状のまま。保持は frontend 側) | private browsing 以外で `dm_user_id` が UUID で残る=yes/no。既存 Free 実機 e2e(殿 08-31 PASS 手順)が再 PASS=yes/no |
| 2 | 既存 campaign_id で Core/Simple の流入を識別 | L-3 #4: `dm_signal_campaign_id` を sessionStorage→localStorage(月跨ぎ)。**source 列は作らない**。Core=`lp_core_*`、Simple=`lp_simple_*` の prefix 規約を campaign_id に持たせる(X 由来は既存 `x_*` のまま) | frontend `lib/showcase-attribution.ts`、`components/landing-page.tsx` L69 | `showcase_events` schema、campaign_id 発行(cmd_4474) | LP を `?campaign_id=lp_core_test` で開き `/free` 到達時の event payload に同値=yes/no |
| 3 | 既存 Tier×Page analytics と、Google 連携ユーザーだけ user.id で結ぶ | L-3 #2+#3: `page_views.user_id`(uuid, nullable, index)+`page_views.campaign_id`(text, nullable)、`showcase_events.user_id`(nullable)。frontend は localStorage の 2 値を payload に同送(値が無ければ null) | backend `app/db/models.py` L629/L634-646、`app/api/analytics.py` L97-121 `PageViewPayload`、`app/api/public_showcase.py`、alembic migration 1 本(+downgrade)。frontend `lib/api-client.ts` L1449、`lib/showcase-attribution.ts` L44-52 | 既存列・既存 EP の応答・append-only。password/Tier 利用者は `user_id` null のまま計測対象 | migration up/down 往復=yes/no。Google 連携者 1 名の `page_views` に user_id が入り、password 利用者の行は null=yes/no。Primary Metric §J 第 1 候補(LP→Auth 完了率、campaign prefix 別)が SQL 1 本で出る=yes/no |
| 4 | ここまで測れてから Simple LP を 1 本だけ試す | §D の Simple 1 本(noindex、`lp_simple_01` を campaign_id に固定)。**段 3 の SQL が本番で 1 週間値を返してから起票** | `lp/` 新 route 1 本 | Core LP、sitemap、canonical、Tier | 4 週の Core vs Simple 比較表(LP→Auth 完了率/Auth→Free ログイン率)が出る=yes/no |
| 5 | Rebalancer/DM-Fusion 連携、Free 公開 PF 拡大、複雑な SSO 等 | **実装しない。M-3 に記録のみ** | — | — | — |

### M-2 確定した設計判断(これ以上広げない)
- source は **campaign_id の prefix 規約**で表す(`lp_core_`/`lp_simple_`/`x_`)。`source` 列・`product_logins` 表・`profiles` 表は作らない。
- identity は **3 層の任意結合**(visitor_id ⊂ tier ⊂ user_id、後者ほど null 可)。結合は保存時ではなくクエリで行う(対応表を作らない)。
- 保持場所は frontend localStorage(`dm_user_id`)。backend は Supabase service key を持たない方針(Free v3.3 §2-3)を維持し、Auth API の user 取得コードも変えない。
- 変更総量の上限: frontend 4 file(callback/user-id/api-client/showcase-attribution)+landing-page 1 行、backend 3 file+migration 1 本。これを超える提案は §M-3 行き。
- Free Interactive Proof の可視性拡大(§E の代表 PF・案 A/B)は **段 5(将来候補)**。今の Free=Basic-DualMomentum のみを維持。

### M-3 将来候補(記録のみ。起票しない)
1. PF→Rebalancer 導線(§L-2 6): DM-Signal PF 画面のリンク → Rebalancer が query を `saved_portfolios` へ upsert。
2. 3 サービス横断 `public.profiles(user_id, first_seen_service, first_campaign_id)`(§L-2 5)。まずは段 3 の SQL で `auth.users` 集合の交差を read するだけ。
3. Free 公開 PF の拡大・L3 mask_signal での Performance 開放(§E 案 A/B、代表 PF の選定)。
4. SSO/個人別クーポン/Google 必須化: やらない(殿 09:18・13:19)。
5. `product_logins`(Free v3.3 §4-5 既定案): 段 3 で代替済みとして閉じる。

### M-4 次の 1 手
- 起票単位は **段 1+2+3 を 1 cmd**(frontend+backend、migration 往復、readonly 事前確認、AC は M-1 の二値列)。段 4 は別 cmd(段 3 の本番 SQL が 1 週間値を返してから)。殿裁定 13:19 は「収束」であり実装 go ではないため、**起票は殿の go を待つ**(実装は殿の一言で開始できる状態まで設計を閉じた)。

## §K 因果リンク
- ← [[dm-signal-lp-seo-plan_20260830]] v6(Core=母艦、分解しない) / ← [[dm-login-showcase-asis-tobe_v3_20260830]] / ← [[dm-free-tier-google-auth-asis-tobe_v3_20260830]]
- → [[cmd_4476]] 偵察 → 本書 v0.2 / → [[殿裁定_LP_identity_最小収束_20260905_1319]] → §M / → [[rebalancer]] `saved_portfolios(user_id)` / → [[dm-fusion]] `saved_fusions(user_id)` 同一 auth.users
