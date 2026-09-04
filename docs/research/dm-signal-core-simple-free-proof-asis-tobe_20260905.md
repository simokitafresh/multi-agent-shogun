<!-- gist-master: e590a96ad0b1c541b2ec266d4c6a512b dm-signal-core-simple-free-proof-asis-tobe_20260905.md -->
# DM-Signal Core LP × Simple LP × Free Interactive Proof — AsIs/ToBe 設計書 v0.1(2026-09-05 02:55 起草)

> 殿指示 2026-09-05 02:42。目的=(1) dm-signal.com を SEO・ブランドの Core LP として完成 (2) 商品を変えずに Simple LP 1 本だけの価値を検証 (3) Google Auth→Free tier を Interactive Proof として使えるか確認 (4) Core vs Simple の流入差を計測可能に。**この段階では実装しない**(Simple LP 新設・Free 可視性変更・Tier 変更・sitemap/canonical 変更・Google Auth 変更は殿裁定後)。
> 優先順位=最新の殿裁定 → 最新正本 → 本番実測 → 現行コード → 古い設計書。正本: SEO v6(`dm-signal-lp-seo-plan_20260830.md`、gist 5edb5f6d)/入口 3 面 v3.2(`dm-login-showcase-asis-tobe_v3_20260830.md`、gist 901c36a5)/Free tier v3.3(`dm-free-tier-google-auth-asis-tobe_v3_20260830.md`、gist 897501e0)。
> **v0.1 の空欄**は cmd_4476(偵察、忍者 1 名)の一次結果で埋める。将軍が正本と本番で確認できた範囲だけを書き、未確認は「(4476)」と明記。

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

## §K 因果リンク
- ← [[dm-signal-lp-seo-plan_20260830]] v6(Core=母艦、分解しない) / ← [[dm-login-showcase-asis-tobe_v3_20260830]] / ← [[dm-free-tier-google-auth-asis-tobe_v3_20260830]]
- → [[cmd_4476]] 偵察 → 本書 v0.2
