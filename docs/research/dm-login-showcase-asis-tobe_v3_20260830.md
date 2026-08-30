<!-- gist-master: 901c36a5b617082128ffdce43ad25c10 dm-login-showcase-asis-tobe_v3_20260830.md -->
# DM-Signal 入口 3 面（LP / app 入口 / 公開 API）— AsIs / ToBe 設計書 v3（2026-08-30 22:45）

- 版: **AsIs v3.0（本番リアルタイム 2026-08-30 22:02-22:40 JST 実測）/ ToBe v3.0**
- 前版: `docs/research/dm-login-showcase-asis-tobe_v2_20260830.md`（gist 3236e0df、`/login` 単一ページのショーウィンドウ設計）。v2 の ToBe は 13:10-21:10 に cmd_4413/4415/4416/4420 で実装されたが、殿裁定 16:42『別サイト』・17:53『LP と /login がほぼ同じ』・20:21『Free tier 着手』で **設計の単位が「/login 1 ページ」から「入口 3 面」へ変わった**。v2 は経緯の正本として残し、本版が現行の正本。
- 併読: SEO 案 v2 `docs/research/dm-signal-lp-seo-plan_20260830.md`（gist 5edb5f6d）/ Free tier v3.1 `docs/research/dm-free-tier-google-auth-asis-tobe_v3_20260830.md`（gist 897501e0）/ 第 0 段 `dm-login-boundary-asis-tobe_20260817.md`。**3 文書は本版 §2 の分担表に従属する**（重複する仕様は本版が正）。
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

---

## §1 AsIs（本番リアルタイム 2026-08-30 22:02-22:40 一次: 本番 curl・DM origin/main・gate_metrics・報告 YAML）

### 1.1 面の現物

| 面 | URL | 状態 | 現物 |
|---|---|---|---|
| **LP EN** | `https://dm-signal.com/` | live 200（Cloudflare proxy、Render static site `lp/`） | H1 "Know what to hold next."、showcase 表（+3,139% / +5,290%〜+11,321% / … / Secret / SPY / TQQQ）、プラン 3 枚（金額なし）、FAQ 抜粋、CTA=Sign in ×12・Read the docs ×6、note membership 6 本。title/description に検索語、JSON-LD 3 型、og/twitter meta 完備、hreflang 3 本。**`og:image` 404**（SEO 案 v2 §0） |
| **LP JA** | `https://dm-signal.com/ja/` | live 200 | 同構造、JA 文言 |
| **app `/login`** | `dm-signal-frontend.onrender.com/login` | live 200（cmd_4420 c14edb99） | metadata `DM-Signal — Sign in`、**noindex,follow**、静的 HTML 本文は "Checking access..."（boundary の client 判定後に SignInCard）。表・プランは無し（入口のみ）。cmd_4423 の Members/Free 二分文言と `?coupon=` プリフィルは **未 deploy** |
| **app `/free` `/auth/callback`** | 同 | 200 だが static fallback（cmd_4423 未 deploy） | origin/main には `app/free/page.tsx`・`app/auth/callback/page.tsx`・boundary public に `/free` `/auth/callback` `/docs` `/faq` |
| **app `/docs` `/faq`** | 同 | live 200（cmd_4418） | 公開済。FAQ は **JA のみ**（`lang="ja"`、EN 版なし） |
| **app データページ** | `/` 他 | 従来どおり認証 | 変更なし（§3 影響境界） |
| **backend `/api/public/showcase`** | `dm-signal-backend.onrender.com` | live 200 | `success/data`。`as_of{series_end 2026-07-31, next_close 2026-08-31}`、`blackout{active:false, until_hint:null}`、`hero`（Basic-DM: holding XLU、components、+3,139%、CAGR 16.4%）、`plans[]`（basic n=2 / standard n=16 / premium n=24、**`best_name`・`sharpe_avg`・`sharpe_best_name` が残存**）、`benchmarks[]`（SPY・TQQQ、sharpe あり）、`secret`（n=73、best_name null） |
| **backend `/api/public/showcase/event`** | 同 | live | step enum に `login_view/input_focus/submit/ok/expired/wrong/note_click/lp_view/lp_cta_click`（4419）。rate 30/min |
| **backend `/api/public/free-coupon`** | 同 | **404**（cmd_4422 未 deploy） | origin/main 未着（GATE BLOCK、RC 中） |
| **`app.dm-signal.com`** | — | 000（未設定） | 殿裁定待ち（第 15 便から継続） |

### 1.2 v2 ToBe との差分（GATE CLEAR ≠ ToBe 到達。型六弾-3 で grep 突合）

| v2 の約束 | 現物（origin/main / 本番） | 判定 |
|---|---|---|
| §2.3 契約 v1.0: `best_name` 除去（12:48）、Sharpe/MDD はベスト単値（12:49）、`mdd_best`・benchmarks `mdd`（12:46）、`blackout{active, month_closed, n_signals}`（12:58、`until_hint` 廃止） | `public_showcase.py`: `best_name`・`sharpe_avg`・`until_hint` 残存、`mdd`/`drawdown` **0 件**、`month_closed`/`n_signals` 0 件。cmd_4415 の最終 commit f8a33e00（CLEAR 16:30）は 3 行差分「reintegrate latest main showcase metrics」で契約変更を含まない | **未到達**（§5 で再起票。4415 は GATE CLEAR だが ToBe に届いていない） |
| §3.1 表 v3（MDD 列、レンジ表記、PF 名なし） | LP の表は EP の現物に従う（MDD 列なし、best_name は LP 側で非表示の可能性=要 grep） | 部分到達 |
| §2.4 ブラックアウト帯（日時ゼロ、note 誘導、`n_signals`） | EP に `n_signals` なし、`until_hint` 残存。帯の文言は 4416/4420 の実装に依存（未検分） | 未検分 |
| §2.5 区間計測 7 step | event EP に 9 step（LP 2 語追加） | 到達 |
| §2.6 ISR | 16:37 訂正で撤回→LP はビルド時 fetch で焼込み（LP HTML に数値あり=到達）、app は client fetch | 到達（形を変えて） |
| §2.7 影響境界 | boundary の public 判定に `/docs` `/faq` `/free` `/auth/callback` を追加（認証分岐は不変） | 到達 |
| §8.2 LP EN/JA・docs/faq 公開 | 4417/4418 live | 到達（FAQ EN は未） |
| §9 LP 別サイト | `dm-signal.com` live、Cloudflare、Search Console 登録 | 到達 |

### 1.3 走行中（22:40）
- cmd_4422（F1 backend, 影丸 631bbc9c）=GATE BLOCK `command_files_modified_mismatch` RC 中 / cmd_4423（F2 frontend, 才蔵 b853b762）=**CLEAR 22:17** / cmd_4424（F3 LP, 半蔵 f9011787）=BLOCK（receipt invalid+files_modified 21 件）RC 中。deploy 前提 4 点（Render env `SUPABASE_JWT_SECRET`・`NEXT_PUBLIC_SUPABASE_URL/ANON_KEY`・Supabase Redirect URL・`VIEWER_PASSWORD_FREE`）未着手。
- インフラ: push lane が CI RED 33312677956 で `ci_fix_active=0` 停止→才蔵 ci_fix 配備（22:26）。DM 側 deploy は家老 lane。

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

### 2.4 公開データ契約 `GET /api/public/showcase` v3（v2 §2.3 を殿裁定 12:46/12:48/12:49/12:58 の最終形で固定。**現物は v1 形のまま=§1.2**）
- `as_of{series_end, next_close, calculated_at}`
- `blackout{active, month_closed, n_signals}`（`until_hint` 廃止。active=`is_password_expired` と同じ JST 判定、month_closed=v2 §6.5 H4）
- `hero{name, holding, momentum, components, total_return, multiple, cagr, inception, benchmark_total_return, mdd}`（Basic-DM 完全公開）
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

### 2.7 SEO（SEO 案 v2 に従属。ここでは面ごとの規則だけ）
- index=LP 2 URL+docs/faq。noindex=/login・/free・/auth/callback・データページ。sitemap は LP 側（P1-1 月次シグナル頁で増える）。`og:image` は静的 PNG（SEO 案 §6 hotfix）。

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

## §5 工程（状態 22:45。1 unit=1 cmd・可逆・儀式なし）

| 手 | 内容 | 状態 |
|---|---|---|
| 済 | v2 P1（4413 EP）/ P2（4416 /login）/ 4420 最小化 / 4417 LP / 4418 docs・faq / 4419 CORS+event / 4421 SEO P0 | CLEAR・live |
| 走行 | F1 4422（RC）/ F2 4423（CLEAR、未 deploy）/ F3 4424（RC） | 家老 lane（22:12 順序 1 通） |
| deploy 前提 | Render env 3 種・Supabase Redirect URL・`VIEWER_PASSWORD_FREE` | 未着手（F1 CLEAR を待たず並走可=可逆） |
| post_deploy_check | §3 の deploy 後 2 経路+既存 EP smoke。殿実機（シークレット×スマホ） | 3 cmd deploy 後、家老 30 分以内に掲示板へ生貼付 |
| **P-C 契約 v3** | `public_showcase.py` を §2.4 へ（best_name/sharpe_avg/until_hint 除去、mdd_best・benchmarks mdd・blackout month_closed/n_signals・meta.skipped）+ contract test。LP 表に MDD 列 | **未起票**（4415 未到達の再起票。二値=未認証 curl に `best_name` 0 件 ∧ `mdd_best` 4 件（3 plan+secret）∧ benchmarks mdd 2 件） |
| P-E event 3 語 | `signup_google/coupon_view/coupon_copy`+`source` | 未起票（F2 deploy 後） |
| P-F FAQ EN | `/faq` EN 版（JA 459 行の翻訳）+hreflang | 未起票 |
| P-G og:image | SEO 案 §6 hotfix | 未起票（4424 と同 target） |
| P-H product_logins | Free tier v3.1 §4-5 | 未起票（Supabase 側、RLS） |
| 後日 | `app.dm-signal.com` 移行、P1-1 月次シグナル頁 | 殿裁定待ち / 9 月 |

## §6 未決（殿裁定待ち。既定案付き、返答なければ既定案）
1. `app.dm-signal.com` へ app を移すか（既定=当面 onrender のまま。移す時は LP の `NEXT_PUBLIC_APP_HOST` 1 手+Supabase Redirect URL 追加）。
2. docs/faq を LP 配下へ移すか（既定=app 側 canonical、LP から内部リンク。SEO 案 §5-4）。
3. **cmd_4415 の未到達（§1.2）を P-C で再起票してよいか**（既定=起票。GATE CLEAR は ToBe の証明ではない）。
4. Free tier の可視範囲（既定=パフォーマンス+シグナル両方。Free tier v3.1 §4-3）。
5. ブラックアウト中の Free 導線を帯に出すか（既定=出す。Free tier が同時失効なら出さない）。

## §7 因果リンク
- [[dm-login-showcase-asis-tobe_v2_20260830]] -> [[殿裁定_LP別サイト_20260830_1642]] -> [[殿実機_LPと/login同構造_20260830_1753]] -> [[殿裁定_FreeTier着手_20260830_2021]] -> **[[dm-login-showcase-asis-tobe_v3_20260830]]** <- [[dm-signal-lp-seo-plan_20260830]] / [[dm-free-tier-google-auth_v3]]
- ← [[dm-login-boundary-asis-tobe_20260817]]（第 0 段） / [[visibility_philosophy]]（projects/dm-signal.yaml）
- 一次証拠: 本番 curl（22:02-22:40: dm-signal.com / onrender login・docs・faq・free / showcase EP）、`git show origin/main:backend/app/api/public_showcase.py`（mdd 0 件、best_name 残存）、`git merge-base --is-ancestor f8a33e00 origin/main`=yes、gate_metrics（4413〜4423）、報告 YAML（4415/4422/4423/4424）
