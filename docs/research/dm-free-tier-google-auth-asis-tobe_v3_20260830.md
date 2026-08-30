<!-- gist-master: 897501e0162e556a682ae32a2eca19c3 dm-free-tier-google-auth-asis-tobe_v3_20260830.md -->
# DM-Signal Free tier(Google 登録→月次クーポン) AsIs/ToBe v3.2 — 2026-08-30 23:20(v3.1 22:30 / v3 骨子 20:20)

> 殿方向性 13:14(後回し)→20:15-20:18 具体化→**殿裁定 20:21『着手せよ』**→F1/F2/F3=cmd_4422/4423/4424 を並走配備(20:40-20:44)。SEO 案(v2、gist 5edb5f6d)とは別レーン。
> **v3.2(23:20)**: 殿指摘 22:54『リバランサーでできたことを俺に聞くな。できるはずだ』→一次(22:56 `git grep` rebalancer backend/app: supabase/jwt/bearer **0 件**)=rebalancer は backend で JWT を検証せず frontend supabase-js+RLS のみ。∴ DM も secret を持たない **Supabase Auth API 方式(`GET {SUPABASE_URL}/auth/v1/user`、apikey=anon key+Bearer)** へ差し替え=cmd_4428(23:08 delegated、4422 CLEAR 22:59 の後に backend 直列)。PD-140(殿へ JWT secret 投入依頼)は撤回・解決。
> **v3.1(22:30)**: 3 cmd の実装到達を報告 YAML・gate_metrics・本番 curl の一次で突合し §1.5/§2/§4/§5 に状態を記す。未 deploy(backend EP 404)・未決は殿の裁定/家老 lane の残として明示。

## §0 殿の要件(事実→制約→判断)
| 時刻 | 殿の言葉 | 判断 |
|---|---|---|
| 13:14 | 登録(Google auth)を rebalancer と同様にし、登録者に無料クーポン、Basic-DualMomentum のみ閲覧の Free tier | Free tier=既存 tier 機構の 1 行 |
| 20:15-16 | クーポンの有効期限・期間は他と同じで毎月変更 | クーポン=**Free tier の月次パスワード**(`ViewerTier.password_env_key`/`password_expires_at`)。既存ローテーションに 1 行足すだけ |
| 20:17 | 登録→ログインでクーポン表示、ワンクリックコピー、動線スムーズ、既存メンバーが誤解しない | `/free` 1 画面+入口の二分(Members/Free)+文言 |
| 20:18 | 登録者データは rebalancer と同じ Supabase 既存にまとめる | **新テーブル 0**。Supabase Auth(Google provider)の `auth.users` を共用 |

## §1 AsIs(2026-08-30 20:19 一次)
- rebalancer: `frontend/lib/supabase.ts`(createClient、`NEXT_PUBLIC_SUPABASE_URL/ANON_KEY`)、`frontend/lib/auth-context.tsx:36 onAuthStateChange`、`:56 signInWithOAuth({provider:"google"})`=Google provider 設定済の Supabase プロジェクト。
- DM-signal backend: `backend/app/api/auth.py:23 verify_viewer`=`viewer_tiers` 全 tier の `password_env_key` を順に照合、`:45 is_password_expired(password_expires_at)`、一致で viewer_session cookie。**個人アカウント概念なし**。`models.py:666 ViewerTier`(`password_expires_at` L679、`last_rotated_at` L680、`hide_portfolio` 等)。
- DM-signal frontend: `/login`=4420 で最小化(ブランド+SignInCard+LP 導線、noindex)。文言は「note の当月パスワードもしくはクーポンコード」。
- LP(dm-signal.com): CTA=Sign in→`/login`、note membership→課金。計測 event step に `lp_view/lp_cta_click`(4419)。
- 5 tier は 08-31 失効→9 月パスワード配布(月次ローテーション運用は殿の手作業+env)。

## §1.5 実装到達(2026-08-30 22:30 一次: 報告 YAML + gate_metrics + 本番 curl)
| cmd | 担当 | commit | GATE | 実装内容(報告 files_modified) | 本番 |
|---|---|---|---|---|---|
| F1 cmd_4422(backend) | 影丸 | 631bbc9c | **BLOCK 22:00** `command_files_modified_mismatch`(RC 中) | `public_showcase.py`: `GET /api/public/free-coupon`+Supabase **HS256** JWT 検証(`SUPABASE_JWT_SECRET`) / `migrations.py`: Free tier 行+可視性初期化(冪等・restore SQL コメント) / contract test(JWT・migration 2 回実行、6/6 PASS SKIP 0) | 未 deploy: backend `/api/public/free-coupon` **404** |
| F2 cmd_4423(frontend) | 才蔵 | b853b762 | **CLEAR 22:17** | `app/free/page.tsx`(Google OAuth→クーポン表示・Copy・/login 導線) / `app/auth/callback/page.tsx`(静的 PKCE callback→/free) / `login/sign-in-card.tsx`(`?coupon=` プリフィル+Free リンク) / `login/login-copy.ts`(EN/JA Members・Free 二分文言) / `route-access-boundary.tsx`(free・callback を未認証許可) / `lib/supabase.ts`+`@supabase/supabase-js` | 未 deploy(frontend `/free` は 200 だが static fallback。実体は deploy 後に確認) |
| F3 cmd_4424(LP) | 半蔵 | f9011787 | **BLOCK 22:11** `ninja_test_receipt_invalid`+`command_files_modified_mismatch`(RC 中。files_modified に lp/ の baseline 21 ファイルを列挙=対象 4 ファイルに絞る要) | `components/landing-page.tsx`+`copy/{en,ja}.ts`: Members/Free 二分・Google Free CTA(`/free?from=lp`)・footer リンク・既存 `lp_cta_click` beacon(新 step 追加なし=cmd AC2) | 未 deploy(dm-signal.com の href に `/free` 0 件) |

- 設計との差分(正): F1 は JWKS でなく **HS256+`SUPABASE_JWT_SECRET`**(Render env に要投入)。F3 の event は §5 v3 の `signup_google` でなく **既存 `lp_cta_click` を流用**(cmd_4424 AC2 で「新 step は追加しない」と明示。`from=lp` クエリが経路記録の起点)。§4-5 `product_logins` は 3 cmd のどれにも含まれず **未実装**(後段 cmd)。
- deploy 前提 4 点(v3.2 状態): frontend env `NEXT_PUBLIC_SUPABASE_URL/ANON_KEY`=**投入済(22:52、rebalancer 正本と hash 一致)** / backend env=`SUPABASE_URL`・`SUPABASE_ANON_KEY`(同値、家老投入。**`SUPABASE_JWT_SECRET` は不要**=4428) / Supabase Auth Redirect URL `https://dm-signal-frontend.onrender.com/auth/callback`(家老) / 殿 `VIEWER_PASSWORD_FREE`(月次クーポン値)。

## §2 ToBe(最小構成、既存機構不変)
1. **Free tier 1 行**(F1 実装済・未 deploy): `viewer_tiers` に `Free`(password_env_key=`VIEWER_PASSWORD_FREE`、hide=Basic-DualMomentum 以外すべて hide、`password_expires_at` は他 tier と同じ月末)。ローテーション運用に 1 行追加。
2. **`/free` ページ(frontend、static export)**(F2 実装済 CLEAR・未 deploy): `supabase-js` で `signInWithOAuth({provider:"google"})`(rebalancer と同じ env・同じプロジェクト)。セッション取得後、backend `GET /api/public/free-coupon`(Authorization: Bearer <supabase access_token>)を呼ぶ。
3. **backend EP `GET /api/public/free-coupon`**(F1 4422 CLEAR 22:59。検証方式は cmd_4428 で差し替え): Supabase Auth API `GET /auth/v1/user`(apikey=`SUPABASE_ANON_KEY`+Bearer access_token、timeout 5s)で本人性を検証(secret 不要。HS256+`SUPABASE_JWT_SECRET` は 4428 で除去)→`os.getenv(free_tier.password_env_key)` と `password_expires_at` を返す(未認証 401、rate limit)。DB 書込み 0。登録者の記録は `auth.users`(Supabase)に既にある。任意で `showcase_events` に `signup_google`/`coupon_copy` step(計測)。
4. **UX**(F2 実装済): クーポンカード(コード・有効期限「〜YYYY-MM-DD」・「Basic-DualMomentum のみ」)+**Copy ボタン(navigator.clipboard)**+**「このクーポンでサインイン」ボタン=`/login?coupon=<code>` でプリフィル**(SignInCard は既存 input に初期値を入れるだけ、照合は従来の verify_viewer)。
5. **誤解防止(既存メンバー)**(F2 `/login` 二分=実装済、F3 LP 二分=RC 中): LP と `/login` の入口を 2 枠に分ける — 「**Members**: note に記載の当月パスワード」/「**Free**: Google で登録して当月クーポン」。`/free` 冒頭に「Free は Basic-DualMomentum のみ。Basic/Standard/Premium の方は従来どおり note のパスワードをお使いください」。Free クーポンを有料導線(note 誘導文)に混ぜない。既存の 5 tier パスワードには一切触れない。

## §3 やらないこと
- 個人ごとのクーポン発行・DB 保存(全 Free 登録者に同一の月次コード=既存 tier 方式と同じ)。
- 課金・決済(note のまま)。既存 tier 認証の変更。初月無料/free trial の文言(§4 禁則、Free は「プラン」であり「無料期間」ではない)。

## §4 未決(殿裁定、既定案付き) — v3.1 状態
1. Supabase プロジェクトは rebalancer と**同一**(既定=同一。殿 20:18) → 既定で実装(F2 は rebalancer と同じ env 名)。
2. `/free` の置き場 → 既定=app で実装済(F2)。LP CTA は F3(RC 中)。
3. Free tier の可視範囲 → 既定=両方で F1 migration に可視性初期化を実装(deploy 後に admin で目視確認)。
4. 月次クーポンの切替日=他 tier と同日(既定) → F1 は `password_expires_at` を他 tier と同じ月末に設定。

5. **経路と利用の記録(殿 20:19-20:20)**(**未実装**。F3 の `from=lp` クエリのみ到達。後段 cmd で `product_logins` を足す) → 既定案=**Supabase プロジェクトは 1 つ**(1 人 1 アカウント)。**行で持ち、列で持たない**: 追記表 `product_logins(user_id, product, source, logged_in_at)`(product=`rebalancer`/`dm-signal`/将来の値、source=`lp`/`rebalancer`/`dm-login`/`direct`。RLS: 本人 insert のみ、集計は service role)。新サービスは `product` の値が増えるだけでスキーマ不変。見やすさは view `product_users(user_id, product, first_seen, last_seen, logins)` で列の形に(実体は行)。users/profile に `logged_in_xxx` 列を足す方式は、サービス追加ごとにスキーマ変更+RLS 更新が要り、回数・時期・経路が残らないため不採用。登録日は `auth.users.created_at` で既に分かる。指標=rebalancer→DM 転換率・LP→Free→note 転換率・両方利用率・月次継続(coupon_fetch)。

## §5 工程(v3.1 状態)
| 手 | 内容 | 状態(22:30) |
|---|---|---|
| 偵察 1 | Supabase provider/JWKS/`auth.users`/env 名 | 省略(殿 20:21『着手せよ』で F1-F3 を並走配備。前提は AsIs §1 で代替) |
| F1 cmd_4422 | Free tier 行+EP(HS256)+contract test | 実装済 631bbc9c、GATE BLOCK(files_modified mismatch)→RC 中 |
| F2 cmd_4423 | `/free`+Copy+`/login?coupon=`+二分文言+callback | **CLEAR 22:17** b853b762 |
| F3 cmd_4424 | LP CTA `/free?from=lp`+二分文言(既存 `lp_cta_click`) | 実装済 f9011787、GATE BLOCK(receipt invalid+files_modified 21 件)→RC 中 |
| deploy 前提 | Render env 3 種+Supabase Redirect URL+`VIEWER_PASSWORD_FREE` | 未着手(家老 lane。F1 CLEAR 前に並走可=可逆) |
| 家老 deploy→post_deploy_check | Google サインイン→クーポン表示→Copy→/login→Basic-DM 表示 ∧ 既存 5 tier ログイン不変 | 未(3 cmd CLEAR+前提後) |
| 後段 cmd | `product_logins`(§4-5)+`/free` noindex(SEO 案 §3) | 未起票 |

origin: `[[殿方向性_FreeTier_GoogleAuth_20260830_1314]] -> [[殿要件_クーポン月次同期_20260830_2016]] -> [[殿提案_Supabase共用_20260830_2018]] -> [[dm-free-tier-google-auth_v3]]`
