<!-- gist-master: 901c36a5b617082128ffdce43ad25c10 dm-login-showcase-asis-tobe_v3_20260830.md -->
# DM-Signal 入口 3 面（LP / app 入口 / 公開 API）— AsIs / ToBe 設計書 v3.2（2026-08-30 22:45 起草 / 2026-08-31 19:20 全文再突合）

- 版: **AsIs v3.2（本番リアルタイム 2026-08-31 19:15-19:20 JST 実測: LP EN/JA HTML・showcase EP・app /free /faq・gate_metrics）/ ToBe v3.1（殿裁定 08-31 14:00-17:58 の LP 表示 5 点+チャート比較形式を追加）**
- v3.2 の変更点: §1 を 08-31 19:20 の現物へ全面更新（v2 差分は全て到達、契約 v3 実在を EP 応答で確認）、§2.4 に `hero.series`・SPY 系列（4439）を追記、§5 に LP 表示弾 4432〜4439 と infra 根治 4438 を反映、§6 全件解消済み、§7 因果に本日裁定を接続。SEO 案は同時に v4 へ更新（gist 5edb5f6d）。
- 前版: `docs/research/dm-login-showcase-asis-tobe_v2_20260830.md`（gist 3236e0df、`/login` 単一ページのショーウィンドウ設計）。v2 の ToBe は 13:10-21:10 に cmd_4413/4415/4416/4420 で実装されたが、殿裁定 16:42『別サイト』・17:53『LP と /login がほぼ同じ』・20:21『Free tier 着手』で **設計の単位が「/login 1 ページ」から「入口 3 面」へ変わった**。v2 は経緯の正本として残し、本版が現行の正本。
- 併読: SEO 案 v4 `docs/research/dm-signal-lp-seo-plan_20260830.md`（gist 5edb5f6d）/ Free tier v3.1 `docs/research/dm-free-tier-google-auth-asis-tobe_v3_20260830.md`（gist 897501e0）/ 第 0 段 `dm-login-boundary-asis-tobe_20260817.md`。**3 文書は本版 §2 の分担表に従属する**（重複する仕様は本版が正）。
- 原則（継承）: ToBe は理想（現実のコード名で縛らない）。AsIs は現物。殿裁定は「事実→制約→判断→効果」。AC は 2 層（忍者=隔離 clone、家老=post_deploy_check）。CI green を待たない（殿裁定 19:29）。

---

## §0 殿裁定（v2 §0 に加えて 13:14 以降。拘束条件）

| 08-30 | 殿の言葉(要旨) | 事実→制約→判断→効果 |
|---|---|---|
| 13:14 | Google auth で登録→無料クーポン→Basic-DM のみの Free tier（後回し） | 20:21『着手せよ』で着手。Free tier v3.1 §0 に詳細 |
| 13:25 | 日本語 LP と英語 LP を別々に。/login にも軽度な LP 効果。Docs/FAQ を /login からのリンクに | 事実=LP は広告・検索の着地、/login は会員の入口で役割が違う。判断=**LP（説明・表・プラン・FAQ 抜粋）と /login（入口）を分ける**。効果=§2 分担表 |
| 16:42 / 16:44 / 17:14 | 別サイトでやろう / Cloudflare でドメイン / `.jp` にこだわらない | 事実=app FE は static export で boundary が全ルートを包み、LP を app に置くと 1 文言修正に検分一式が要る。判断=**LP=別 Render static site `dm-signal.com`（EN `/`・JA `/ja`）**。効果=影響境界 0、cmd_4417/4418/4419 |
| 17:53 | LP と /login がほぼ同じで誤解を生む | 事実=将軍が v2 §2.2 の同構造を両方に複製した。判断=**1 ページ 1 目的: 表・プラン・説明は LP、/login は入口のみ**。効果=cmd_4420 で /login 最小化（型十六弾-5） |
| 18:19 | LP の note リンク誤り・Read the docs→FAQ | 事実=参考記事著者の URL を採用した。判断=外部導線は `marketing-info.md` 現物から引き、CLEAR 後に本番 curl で href を数える。効果=19:34 live 修正、型十六弾-8 |
| 19:29 | CI green を待つのはナンセンス | 判断=GATE の ci_readiness は記録のみ、CI RED は ci_fix lane で後追い。効果=型十六弾-9 |
| 19:51 / 20:04 | SEO 案をまとめて gist / やったぞ。進めてくれ | 判断=SEO 案 v1→P0 を cmd_4421 で実装（title・JSON-LD・OG）。Search Console は殿が Cloudflare 自動確認で登録（20:01） |
| 20:15-20:21 | Google 登録→クーポン表示→ワンクリックコピー、既存メンバーが誤解しないように、Supabase は rebalancer と共用、着手せよ | 判断=**Free tier=既存 tier 機構の 1 行+`/free`+`/api/public/free-coupon`+入口二分（Members / Free）**。効果=cmd_4422/4423/4424 並走 |
| 21:30 | なぜ 30 分放置で何でも許可するのか | 判断=時間経過の承認代行は撤去。停滞は名指し nudge（インフラ側。本設計の deploy は家老の明示 ACCEPT で進む） |
| **08-31** | | |
| 12:24-12:34 | Current signals 表の体裁（スクショ）: 招待制注記重複削除・JA up to・太字統一・TQQQ MDD 赤字・メンバーシップ表記・MDD/Sharpe 用語説明 | 効果=cmd_4431 CLEAR 13:36・live |
| 14:00-14:01 | Total return は冗長。CAGR を up to 形式に、列順 CAGR→Sharpe→MDD→×N | 効果=cmd_4432 CLEAR 15:03・live（19:20 実測 Total return 0 件） |
| 14:06 | 絵柄が地味。Basic-DM のチャートを compare chart と同じスタイルの static で | 効果=cmd_4433 CLEAR 16:40・live（`hero.series` 276 点、LP svg 1 件。custom-domain cache 5 分遅延で一時 0 に見えた=真因 cache、build/API 正常） |
| 14:32 | LP に集中しよう | 判断=LP lane 最優先、infra 新規・Agent Readiness L3 は保留 |
| 14:36 | 未決 4 本一括裁定（§6） | 効果=§6 全件解消、FoF 訴求=cmd_4434 |
| 14:56 | P1-1 月次シグナル頁は 9 月を待たず 8 月分から | 効果=cmd_4436 起票（月ハードコード禁止） |
| 16:45 | 数値は全て太字。Basic-DM の閲覧は Free。閲覧列も太字 | 効果=cmd_4437 起票（4434 直後直列） |
| 17:43 | つまりはバグだ。切り分けでなく根治せよ | 事実=BLOCK 3 連の真因が run_tests.sh の external scope 除外（frontend 限定）。効果=cmd_4438 根治 CLEAR 18:45 |
| 17:58 | チャートは comparison 形式（SPY 破線・x 表記対数目盛・年月軸・累積%凡例、スクショ） | 効果=cmd_4439 起票 |
| 18:48 | artifact はアカウント切替時 A 案（再公開+索引差替）で良い | 効果=runbook gist 2caac114 で運用、B 案（固定 URL）不採用 |

---

## §1 AsIs（本番リアルタイム 2026-08-31 19:15-19:20 一次: LP EN/JA HTML・showcase EP JSON・app /free /faq curl・gate_metrics。v3.0 の 08-30 22:02 実測は git 履歴に保存）

### 1.1 面の現物

| 面 | URL | 状態 | 現物（19:20） |
|---|---|---|---|
| **LP EN** | `https://dm-signal.com/` | live 200（Cloudflare proxy、Render static site `lp/`、`s-maxage=300`） | Current signals 表=列順 **CAGR→Sharpe→MDD→×N**（Total return 0 件、up to 10 箇所）、hero 行/プラン 3 行/Secret/SPY/TQQQ、閲覧列=Membership ×2・Invite-only・Hidden、hero 行の閲覧は **未 Free**（4437 待ち）、**static chart svg 1 件**（hero 単独線、4433）、**Fund of Funds 1 件**（4434 の commit は live、GATE は RC 中）、CTA=Sign in / Start free with Google（`/free?from=lp`）、note membership、Read the docs、`/faq` リンク（JA 既定）。title/description・JSON-LD 3 型（validator.schema.org エラー 0）・og-en.png 200・hreflang 3 本 |
| **LP JA** | `https://dm-signal.com/ja/` | live 200（JP からの `/` は Cloudflare 302 → `/ja/`） | 同構造。閲覧列=メンバーシップ/招待制/非表示、hero 行は **「表示」のまま**（4437 待ち）、svg 1・FoF 1・トータルリターン 0 |
| **app `/login`** | `dm-signal-frontend.onrender.com/login` | live 200（4420・4423） | noindex、SignInCard、Members/Free 二分、`?coupon=` プリフィル |
| **app `/free` `/auth/callback`** | 同 | live 200（4423・4428） | Google サインイン→クーポン。**noindex,nofollow 1 件（4435 CLEAR 18:47、19:20 実測）**。殿実機 e2e PASS 08-31 01:38 |
| **app `/docs` `/faq`** | 同 | live 200 | `/faq` = JA（`lang="ja"`）、**EN 版は `/faq/en/` 200**（4427。`/en/faq/` は 404）。LP からのリンクは `/faq`（JA 既定）=EN LP から EN FAQ への直リンクは未（§5 後日） |
| **app データページ** | `/` 他 | 従来どおり認証 | 変更なし |
| **backend `/api/public/showcase`** | `dm-signal-backend.onrender.com` | live 200 | keys=`as_of/benchmarks/blackout/hero/meta/plans/secret`。**契約 v3 到達**: `blackout{active:false, month_closed:true, n_signals:42}`（`until_hint` 廃止）、`plans[]{plan,n,avg_*,best_*,cagr_min,cagr_max,sharpe_best,mdd_best}`（`best_name`・`sharpe_avg` 0 件）、`hero{…, sharpe, mdd, series[276]}`（`series`=4433、`year_month/multiple`）、`benchmarks[]` SPY/TQQQ（**series なし=4439 で追加**） |
| **backend `/api/public/showcase/event`** | 同 | live | step 9 語（Free 系 3 語は未=P-E） |
| **backend `/api/public/free-coupon`** | 同 | live（4422+4428、Supabase Auth API 方式） | env `VIEWER_PASS_FREE`（Free tier v3.3） |
| **`app.dm-signal.com`** | — | 未設定 | **裁定 08-31 14:36: 当面 onrender のまま** |

### 1.2 v2/v3 ToBe との差分（GATE CLEAR ≠ ToBe 到達。19:20 の grep 突合）

| 約束 | 現物 | 判定 |
|---|---|---|
| §2.4 契約 v3（best_name 除去・mdd_best・blackout month_closed/n_signals） | EP 応答で全キー実在、禁止キー 0 | **到達**（4425+hotfix 10d59c8d） |
| §2.2 表（列順・up to・太字・赤字・用語説明） | 4430/4431/4432 live | **到達**（残=4437 の全太字+Free） |
| §2.2 チャート | hero 単独線 svg live | 到達（形式は 4439 で比較形式へ） |
| §2.2 FoF 訴求 | LP に Fund of Funds 1 件 | live（4434 GATE は RC 中） |
| §2.5 ブラックアウト帯 | EP に n_signals=42・month_closed=true。帯文言は /login 実装（未検分のまま） | EP 到達・UI 未検分 |
| §2.6 計測 | 9 step、Free 3 語未 | 部分（P-E） |
| §2.7 SEO | LP index・app noindex（/login・/free）・sitemap 2 URL・og 200・JSON-LD valid | 到達（面積は 4436 で拡張） |
| §2.2 docs/faq | /docs・/faq(JA)・/faq/en/ live | 到達（LP→EN FAQ 直リンクは未） |

### 1.3 走行中（19:20）
- LP lane 直列: **cmd_4434**（FoF、影丸 RC=receipt 再取得、19:10 再発行）→ **cmd_4437**（全太字+Free、4434 CLEAR 直後配備）→ **cmd_4439**（比較チャート。backend AC1/AC2 は先行分解可）→ **cmd_4436**（月次頁 `/signals/2026-08`）。
- infra 根治 3 本は CLEAR 済（review 世代 dedupe 18:13 / auto-push helper 18:43 / runner external scope **cmd_4438** 18:45）=BLOCK 3 連の類型は構造的に解消。auto-push は「remote CI GREEN 後に発火」契約。
- その他: hayate ci_fix（receipt_count_mismatch）、reflux 2 件。DM-Signal CI は GitHub billing 上限で job 未開始（コード正常、GATE は ci_readiness を記録のみ）。

---

## §2 ToBe v3.0（入口 3 面の分担と契約）

### 2.1 目的（v2 §2.1 を 3 面に拡張）
未認証訪問者が **(a) 何のサービスか (b) どこから入るか (c) なぜ会員になるか** を LP で 30 秒で理解し、**会員は /login、初見は /free（Google）** へ迷いなく分岐し、ログイン後の体験へ最短で進む。ブラックアウト週も「待てば入れる / note で取れる / Free なら今すぐ」が一目で分かる。

### 2.2 分担表（1 ページ 1 目的。殿裁定 17:53）

| 面 | 目的 | 置くもの | 置かないもの | index |
|---|---|---|---|---|
| **LP `/` `/ja`**（dm-signal.com） | 説明・証拠・分岐 | H1+リード、showcase 表（§2.4 契約の表示）、プラン 3 枚（金額なし）、FAQ 抜粋→app `/faq`、CTA 2 本 **Sign in**（Members）/ **Start free with Google**（Free、`/free?from=lp`）、note 導線、Read the docs | 入力欄・認証・価格・無料期間の文言 | index、hreflang、JSON-LD、og |
| **app `/login`** | 会員の入口 | SignInCard（当月パスワード or クーポン、`?coupon=` プリフィル）、入口二分の 2 行（Members=note の当月パスワード / Free=Google で登録して当月クーポン→`/free`）、ブラックアウト帯（§2.5）、LP へ戻る 1 リンク | 表・プラン・説明・価格 | noindex |
| **app `/free` → `/auth/callback`** | Free 登録とクーポン受取 | Google サインイン→クーポンカード（コード・有効期限・「Basic-DualMomentum のみ」）→Copy→「このクーポンでサインイン」→`/login?coupon=` | 有料導線の混在、初月無料/free trial 文言 | noindex |
| **app `/docs` `/faq`** | 公開ドキュメント | 現行 docs（EN）・FAQ（JA→EN 追加） | 認証 | index（LP から内部リンク。canonical は app 側=SEO 案 §5-4 既定） |
| **backend `/api/public/*`** | 認証不要の公開契約 | `showcase`（§2.4）、`showcase/event`（§2.6）、`free-coupon`（Free tier v3.1 §2-3） | パスワード・env key・個別 PF の holding/momentum（hero 以外） | — |

### 2.3 分岐の原則（既存メンバーが誤解しない。殿要件 20:17）
- 入口は常に **2 枠並列**（Members / Free）。LP・/login とも同じ 2 語・同じ順。Free の説明は「Google で登録して当月クーポン」「Basic-DualMomentum のみ」の 2 文に閉じ、Members 側の note 説明と混ぜない。
- Free クーポンは既存 5 tier のパスワードと **同じ入力欄・同じ照合**（`verify_viewer`）。UI で区別するのは入口の 2 枠だけ、認証機構は 1 本。
- 経路は URL に残す（`/free?from=lp` / `from=login`）。集計は event の `source` で数え、行で持つ（Free tier v3.1 §4-5 `product_logins` は後段）。

### 2.4 公開データ契約 `GET /api/public/showcase` v3.1（v2 §2.3 を殿裁定 12:46/12:48/12:49/12:58 の最終形で固定。**現物は v3 到達済み=§1.1、19:20 実測**。v3.1 で `hero.series` と benchmarks `series` を追加）
- `as_of{series_end, next_close, calculated_at}`
- `blackout{active, month_closed, n_signals}`（`until_hint` 廃止。active=`is_password_expired` と同じ JST 判定、month_closed=v2 §6.5 H4）
- `hero{name, holding, momentum, components, total_return, multiple, cagr, sharpe, inception, benchmark_total_return, mdd, series[]{year_month, multiple}}`（Basic-DM 完全公開。`series`=月次累積倍率、起点 1.0x、最終値=`multiple`。4433 で実装済み）
- `benchmarks[].series[]`（**4439 で追加**: SPY を hero と同一起点に正規化した月次累積。LP 比較チャートの破線系列）
- `plans[]{plan, n, avg_total_return, best_total_return, avg_multiple, best_multiple, cagr_min, cagr_max, sharpe_best, mdd_best}`（**best_name・sharpe_avg・*_best_name を返さない**。集合=hide_portfolio=false ∧ hide_signal=false を `visibility_helpers` 経由で）
- `benchmarks[]{symbol, since, total_return, multiple, cagr, sharpe, mdd}`（SPY 2003-10〜、TQQQ 2010-03〜）
- `secret{count, n, avg_total_return, best_total_return, avg_multiple, best_multiple, cagr_min, cagr_max, sharpe_best, mdd_best}`（名前なし）
- `meta{skipped}`（metrics 欠落 PF 数、v2 H13）
- 表示側（LP 表）は契約のキーだけを描く。契約に無いキー（best_name 等）が来ても描かない=**契約違反の値を UI で隠す状態を作らない**ため、EP 側で削る（§5 P-C）。

### 2.5 ブラックアウト表現（v2 §2.4 継承。日時ゼロ）
- LP: 表ヘッダ右に "Series through {series_end}"。帯は出さない（LP は説明の面）。
- /login: `blackout.active` のとき帯 "{Month} is closed. New signals for {next} are computed. The password unlocks them — announced on note." + "Get notified on note →"。**Free 導線を帯の下に 1 行**（"Or start free with Google — Basic-DualMomentum is open now"）=ブラックアウト中も入れる道を示す（Free tier は月次クーポンなので同時失効する場合は同文を出さない。判定は Free tier の `password_expires_at`）。
- 失効 401 は専用文（EN+JA）+note 誘導+Free 導線。

### 2.6 計測契約 `POST /api/public/showcase/event`
- step enum（現物 9）+ Free 系 3 語 **`signup_google` / `coupon_view` / `coupon_copy`** を追加（後段 cmd）。`source` ∈ {lp, login, direct, rebalancer}。
- 週報の区間表: `lp_view → lp_cta_click → (login_view → submit → ok | signup_google → coupon_view → coupon_copy → ok)`。落ち幅が最大の 1 区間だけを次弾にする（五十嵐記事の教え、v2 §2.5）。

### 2.7 SEO（SEO 案 v4 に従属。ここでは面ごとの規則だけ）
- index=LP 2 URL（+4436 で月次頁 EN/JA）+docs/faq（app 側 canonical、裁定 14:36）。noindex=/login・/free（**4435 live**）・/auth/callback・データページ。sitemap は LP 側（4436 で lastmod 付き自動追加、月ハードコード禁止）。`og:image` は静的 PNG（4426 live）。

### 2.8 LP 表とチャートの表示規則（08-31 裁定の確定形。cmd_4430〜4439 の契約）
- 列=`PF数 / CAGR / Sharpe / MDD / ×N / 閲覧`。Total return 列は置かない（14:00）。
- プラン行: CAGR・×N は `up to` 最良値（EN/JA とも up to）、Sharpe・MDD は最良 PF の値。**数値は全て太字**（16:45、4437）。SPY/TQQQ 行はイタリック細字のまま、TQQQ MDD は赤字。
- 閲覧列: hero=**Free**、プラン=Membership/メンバーシップ、Premium=Invite-only/招待制、Secret=Hidden/非表示。**閲覧列も太字**（16:45、4437）。リンク先は未裁定（12:32『この後で考える』）。
- Premium 行の左列に招待制注記を重ねない（12:24）。表下 tableNote に MDD/Sharpe の用語説明を 1 回。FoF 訴求 1 行を表近傍に（14:36、4434）。
- チャート: static（interactivity なし）。**比較形式**=Basic-DM 青実線+SPY グレー破線、対数 y 軸を x 表記（1-2-5 系列）、x 軸に年月、凡例に系列名+開始以来累積%（17:58、4439）。

---

## §3 影響境界（v2 §2.7 継承+LP・Free の追加）

| 層 | 触ってよいもの | 触らないもの |
|---|---|---|
| LP（別 repo dir `lp/`、別 Render） | 全て（app と独立） | app の deploy・CI を同乗させない |
| app frontend | `app/login/**`・`app/free/**`・`app/auth/callback/**`・`login-copy.ts`・boundary の **public 判定リスト**・`lib/supabase.ts` | boundary の認証分岐（`/login` 以外を replace する部分）・`viewer-auth`・7 層リセット・ログイン後ページ |
| backend | `api/public_showcase.py`（router `/api/public/*`）・Free tier migration（冪等）・新 test | `auth.py` の照合ロジック・既存 EP・既存テーブルのスキーマ |
| DB | `viewer_tiers` に Free 行（migration）・event 追記 | 既存 tier 行の変更 0（before/after 一致） |
| deploy | FE/BE とも live と origin/main の差分は本設計分のみ | — |
- 二値（忍者）: allowlist 外 diff 0 / 認証分岐 diff 0 / 既存 test diff 0 かつ PASS。**deploy 後（家老 post_deploy_check）**: 既存 5 tier ログイン→`/`→3 ページ 200、Google サインイン→クーポン表示→Copy→`/login?coupon=`→Basic-DM 表示、既存 EP smoke。

## §4 言語・文言規則（v2 §4 継承。追加 2 条）
- 禁則: 毎営業日/today、¥/円/yen、first month free/初月無料/free trial（Free は「プラン名」であり期間ではない）。
- **追加 3**: Members/Free の 2 語は EN/JA とも固定（Members / Free、メンバー / Free）。**追加 4**: Free の説明は 2 文以内、有料プランのカード内に Free の語を置かない。

---

## §5 工程（状態 2026-08-31 19:20。gate_metrics CLEAR 時刻で突合）

| 手 | 内容 | 状態 |
|---|---|---|
| 済(v2 期) | 4413 EP / 4416 /login / 4420 最小化(21:10) / 4417 LP / 4418 docs・faq / 4419 CORS+event / 4421 SEO P0(21:35) | CLEAR・live |
| 済(Free tier) | F1 4422(22:59)+4428(00:06)（backend・Supabase Auth API 方式）/ F2 4423(22:17) / F3 4424(00:26) | CLEAR・live。**殿実機 e2e PASS 08-31 01:38** |
| 済(P-C) | 4425(00:15)=契約 v3 再実装+hotfix 10d59c8d（hero sharpe） | **EP 応答で契約 v3 実在を 19:20 確認**（§1.1） |
| 済(P-F/P-G) | 4427 FAQ EN(01:52、`/faq/en/`) / 4426 og:image 静的 PNG(02:24) | CLEAR・live |
| 済(LP 表示) | 4430(11:00) up to・コントラスト・note CTA / 4431(13:36) 招待制重複削除・JA up to・太字・TQQQ 赤字・メンバーシップ・用語説明 / **4432(15:03) Total return 削除・CAGR up to・列順** / **4433(16:40) hero.series EP+static chart** | CLEAR・本番 curl 到達（§1.1） |
| 済(SEO 禁則) | **4435(18:47) app `/free` noindex** | CLEAR・本番 noindex 1 件実測 |
| 済(infra 根治) | **4438(18:45) run_tests.sh external scope 一般化**（frontend 限定→任意 package root、receipt 正規記録）+ review 世代 dedupe hotfix(18:13) + auto-push helper mode hotfix(18:43) | CLEAR。LP lane の BLOCK 3 連の根を除去 |
| 走行(LP 表示) | **4434** FoF 訴求 1 行（commit は live、GATE=receipt 再取得 RC 中） | 19:10 RC 再発行、影丸 |
| 待機(直列) | **4437** プラン数値全太字+閲覧列太字+hero 閲覧 Free → **4439** 比較チャート（SPY 系列 EP+描画）→ **4436** 月次シグナル頁 `/signals/2026-08` EN/JA+sitemap lastmod | 4434 CLEAR 起点で順次配備（4439 backend 部は先行分解可） |
| 済(周辺) | Cloudflare JP→/ja/ 302 / Agent Readiness L1 5/5・L2 3/3 / HSTS・security.txt・WAF / Search Console・Bing・schema.org 3 型 valid | roadmap v1.1（gist da1b7617）、SEO 案 v4 |
| 未起票 | P-E event 3 語（signup_google/coupon_view/coupon_copy+source） / LP → `/faq/en/` の言語別直リンク | 次弾候補（LP 集中裁定 14:32 の範囲内） |
| 未着手 | P-H product_logins（Free tier v3.3 §4-5、Supabase RLS） / SEO P1-4 用語頁 3 本 / P2 技術系 | 殿裁定待ち（LP 集中外は保留） |
| 後日 | メンバーシップ列のリンク先（殿 12:32『この後で考える』） / app.dm-signal.com は当面 onrender（裁定 14:36） | 殿裁定待ち |

## §6 未決（14:36 更新: **全件解消** — 殿裁定 2026-08-31 14:36 一括、knowledge:d1fb0c5aaf6d922c）
1. ~~app.dm-signal.com 移行~~ → **裁定: 当面 onrender のまま**（移す時は `NEXT_PUBLIC_APP_HOST` 1 手+Supabase Redirect URL 追加）。
2. ~~docs/faq を LP 配下へ~~ → **裁定: app 側 canonical 維持**、LP から内部リンク（SEO 案 §5-4）。
3. ~~cmd_4415 の未到達を P-C で再起票~~ → **解消**（4425 で再実装・CLEAR・origin 到達検分済み）。
4. ~~Free tier の可視範囲~~ → **裁定: パフォーマンス+シグナル両方**（Free tier v3.1 §4-3）。
5. ~~ブラックアウト中の Free 導線~~ → **裁定: 帯に出す**（Free tier が同時失効なら出さない）。
6. ~~FoF 訴求 1 行~~ → **裁定: 足す**（active 101 本中 77 本が FoF、殿 12:39『FoF がウリ』→ cmd_4434 で起票）。

## §7 因果リンク
- [[dm-login-showcase-asis-tobe_v2_20260830]] -> [[殿裁定_LP別サイト_20260830_1642]] -> [[殿実機_LPと/login同構造_20260830_1753]] -> [[殿裁定_FreeTier着手_20260830_2021]] -> **[[dm-login-showcase-asis-tobe_v3_20260830]]** <- [[dm-signal-lp-seo-plan_20260830]] / [[dm-free-tier-google-auth_v3]]
- ← [[dm-login-boundary-asis-tobe_20260817]]（第 0 段） / [[visibility_philosophy]]（projects/dm-signal.yaml）
- 08-31 裁定系譜: [[殿裁定_Current_signals体裁_20260831_1224]] -> [[殿裁定_Current_signals列整理_20260831_1401]] -> [[殿裁定_LP_hero_chart_20260831_1406]] -> [[殿裁定_LP集中_20260831_1432]] -> [[殿裁定_未決4本一括_20260831_1436]] -> [[殿裁定_Current_signals全太字Free_20260831_1645]] -> [[殿厳命_バグは根治_20260831_1743]] -> [[殿裁定_チャート比較形式_20260831_1758]]
- 関連: [[dm-signal-lp-seo-plan_20260830]]（v4） / [[bing_richresults_runbook]] / [[artifact_account_switch_runbook]] / [[cmd_4438_external_scope一般化]]
- 一次証拠（v3.2）: 本番 curl 19:15-19:20（dm-signal.com EN/JA HTML の grep: svg/FoF/Total return/up to/閲覧列文言、showcase EP JSON keys、onrender /free noindex・/faq lang・/faq/en/ 200）、gate_metrics CLEAR 行（4420〜4438）、karo_snapshot 19:13。v3.0 の 08-30 22:02 実測と v3.1 13:56 状態は git 履歴（c9597b01 以前）に保存
