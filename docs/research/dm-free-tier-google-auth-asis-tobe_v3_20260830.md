# DM-Signal Free tier(Google 登録→月次クーポン) AsIs/ToBe v3 骨子 — 2026-08-30 20:20

> 殿方向性 13:14(後回し)→20:15-20:18 具体化。SEO 案(v1)とは別レーン。実装は殿の着手裁定後。

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

## §2 ToBe(最小構成、既存機構不変)
1. **Free tier 1 行**: `viewer_tiers` に `Free`(password_env_key=`VIEWER_PASSWORD_FREE`、hide=Basic-DualMomentum 以外すべて hide、`password_expires_at` は他 tier と同じ月末)。ローテーション運用に 1 行追加。
2. **`/free` ページ(frontend、static export)**: `supabase-js` で `signInWithOAuth({provider:"google"})`(rebalancer と同じ env・同じプロジェクト)。セッション取得後、backend `GET /api/public/free-coupon`(Authorization: Bearer <supabase access_token>)を呼ぶ。
3. **backend EP `GET /api/public/free-coupon`**: Supabase の JWKS(または `SUPABASE_JWT_SECRET`)で JWT を検証→`os.getenv(free_tier.password_env_key)` と `password_expires_at` を返す(未認証 401、rate limit)。DB 書込み 0。登録者の記録は `auth.users`(Supabase)に既にある。任意で `showcase_events` に `signup_google`/`coupon_copy` step(計測)。
4. **UX**: クーポンカード(コード・有効期限「〜YYYY-MM-DD」・「Basic-DualMomentum のみ」)+**Copy ボタン(navigator.clipboard)**+**「このクーポンでサインイン」ボタン=`/login?coupon=<code>` でプリフィル**(SignInCard は既存 input に初期値を入れるだけ、照合は従来の verify_viewer)。
5. **誤解防止(既存メンバー)**: LP と `/login` の入口を 2 枠に分ける — 「**Members**: note に記載の当月パスワード」/「**Free**: Google で登録して当月クーポン」。`/free` 冒頭に「Free は Basic-DualMomentum のみ。Basic/Standard/Premium の方は従来どおり note のパスワードをお使いください」。Free クーポンを有料導線(note 誘導文)に混ぜない。既存の 5 tier パスワードには一切触れない。

## §3 やらないこと
- 個人ごとのクーポン発行・DB 保存(全 Free 登録者に同一の月次コード=既存 tier 方式と同じ)。
- 課金・決済(note のまま)。既存 tier 認証の変更。初月無料/free trial の文言(§4 禁則、Free は「プラン」であり「無料期間」ではない)。

## §4 未決(殿裁定、既定案付き)
1. Supabase プロジェクトは rebalancer と**同一**(既定=同一。殿 20:18)。
2. `/free` の置き場: app(dm-signal-frontend、既定)か LP か → 既定=app(認証セッションと同一オリジン)。LP からは CTA「Free で始める(Google)」を追加。
3. Free tier の可視範囲=Basic-DualMomentum の**パフォーマンス+シグナル**両方か、パフォーマンスのみか → 既定=両方(13:14『閲覧できる』)。
4. 月次クーポンの切替日=他 tier と同日(既定)。

## §5 工程(裁定後、各 10 分・可逆)
- 偵察 1: Supabase プロジェクトの Google provider 設定と JWKS URL、`auth.users` の件数、rebalancer の env 名(5 要件で報告)。
- cmd F1(backend): Free tier 行+`/api/public/free-coupon`(JWT 検証、contract test)。
- cmd F2(frontend): `/free` ページ+Copy+`/login?coupon=` プリフィル+入口二分文言。
- cmd F3(LP): CTA「Free で始める」+event step `signup_google`。
- 家老 deploy→post_deploy_check(Google サインイン→クーポン表示→コピー→/login→Basic-DM 表示)。

origin: `[[殿方向性_FreeTier_GoogleAuth_20260830_1314]] -> [[殿要件_クーポン月次同期_20260830_2016]] -> [[殿提案_Supabase共用_20260830_2018]] -> [[dm-free-tier-google-auth_v3]]`
