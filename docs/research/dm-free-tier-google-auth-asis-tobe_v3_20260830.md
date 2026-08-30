<!-- gist-master: 897501e0162e556a682ae32a2eca19c3 dm-free-tier-google-auth-asis-tobe_v3_20260830.md -->
# DM-Signal Free tier(Google 登録→月次クーポン) AsIs/ToBe v3.3 — 2026-08-31 00:45(v3.2 23:20 / v3.1 22:30 / v3 骨子 08-30 20:20)

> 殿方向性 13:14(後回し)→20:15-20:18 具体化→**殿裁定 20:21『着手せよ』**→F1/F2/F3=cmd_4422/4423/4424 を並走配備(20:40-20:44)。SEO 案(v2、gist 5edb5f6d)とは別レーン。
> **v3.3(08-31 00:45)**: 殿指示 00:38『アップデートせよ』→ 4 cmd の **本番 live 到達を Render API・本番 curl・git 祖先の一次で突合**。F1(4422)+検証差替(4428)=backend live `ce3f7f09`(00:13 JST)、F2(4423)=frontend live `b853b762`(22:10 JST)、F3(4424)=LP live `4b305f49`(23:27 JST、CLEAR 00:26 より先に live=merge 経由)。deploy 前提 5/5 到達(env 3 種・Redirect URL・`VIEWER_PASSWORD_FREE`)。残=post_deploy_check 4 点(殿実機の Google サインイン)・Free tier 行の DB 目視・後段 cmd(`product_logins`/`/free` noindex)。
> **v3.3 追補(00:52)**: 殿実機 00:49『Googleサインインは現在設定されていません。と表示されるぞ』→一次: frontend live b853b762 の build は 22:09 JST、`NEXT_PUBLIC_SUPABASE_*` の投入は 22:52=**static export の build が env より先**で、live chunk に `supabase.co` 0 件・`isSupabaseConfigured=false`(`lib/supabase.ts:8`)の分岐文言(`app/free/page.tsx:94`)が出ていた。Render は env 変更で自動 redeploy しない(型十三弾-4 の frontend 版)。是正=将軍が可逆の再 deploy(clearCache、dep-daa535on74is739sdok0、ce3f7f096)を 00:50 発火→live 後に chunk の `supabase.co` 件数で証明。**契約**: `NEXT_PUBLIC_*` を使う static export は「env 投入→build」の順序が必須。deploy 前提の二値に『env 投入時刻 < live build 開始時刻』を加える(§1.5)。
> **v3.2(23:20)**: 殿指摘 22:54『リバランサーでできたことを俺に聞くな。できるはずだ』→一次(22:56 `git grep` rebalancer backend/app: supabase/jwt/bearer **0 件**)=rebalancer は backend で JWT を検証せず frontend supabase-js+RLS のみ。∴ DM も secret を持たない **Supabase Auth API 方式(`GET {SUPABASE_URL}/auth/v1/user`、apikey=anon key+Bearer)** へ差し替え=cmd_4428(23:08 delegated、4422 CLEAR 22:59 の後に backend 直列)。PD-140(殿へ JWT secret 投入依頼)は撤回・解決。
> **v3.1(22:30)**: 3 cmd の実装到達を報告 YAML・gate_metrics・本番 curl の一次で突合し §1.5/§2/§4/§5 に状態を記す。未 deploy(backend EP 404)・未決は殿の裁定/家老 lane の残として明示。

## §0 殿の要件(事実→制約→判断)
| 時刻 | 殿の言葉 | 判断 |
|---|---|---|
| 13:14 | 登録(Google auth)を rebalancer と同様にし、登録者に無料クーポン、Basic-DualMomentum のみ閲覧の Free tier | Free tier=既存 tier 機構の 1 行 |
| 20:15-16 | クーポンの有効期限・期間は他と同じで毎月変更 | クーポン=**Free tier の月次パスワード**(`ViewerTier.password_env_key`/`password_expires_at`)。既存ローテーションに 1 行足すだけ |
| 20:17 | 登録→ログインでクーポン表示、ワンクリックコピー、動線スムーズ、既存メンバーが誤解しない | `/free` 1 画面+入口の二分(Members/Free)+文言 |
| 20:18 | 登録者データは rebalancer と同じ Supabase 既存にまとめる | **新テーブル 0**。Supabase Auth(Google provider)の `auth.users` を共用 |
| 22:54 | リバランサーでできたことを俺に聞くな。できるはずだ | backend は secret を持たない(Supabase Auth API 方式)=cmd_4428。殿の手作業は agent が原理的に持てない権限(dashboard 設定)のみ |

## §1 AsIs(2026-08-30 20:19 一次)
- rebalancer: `frontend/lib/supabase.ts`(createClient、`NEXT_PUBLIC_SUPABASE_URL/ANON_KEY`)、`frontend/lib/auth-context.tsx:36 onAuthStateChange`、`:56 signInWithOAuth({provider:"google"})`=Google provider 設定済の Supabase プロジェクト。
- DM-signal backend: `backend/app/api/auth.py:23 verify_viewer`=`viewer_tiers` 全 tier の `password_env_key` を順に照合、`:45 is_password_expired(password_expires_at)`、一致で viewer_session cookie。**個人アカウント概念なし**。`models.py:666 ViewerTier`(`password_expires_at` L679、`last_rotated_at` L680、`hide_portfolio` 等)。
- DM-signal frontend: `/login`=4420 で最小化(ブランド+SignInCard+LP 導線、noindex)。文言は「note の当月パスワードもしくはクーポンコード」。
- LP(dm-signal.com): CTA=Sign in→`/login`、note membership→課金。計測 event step に `lp_view/lp_cta_click`(4419)。
- 5 tier は 08-31 失効→9 月パスワード配布(月次ローテーション運用は殿の手作業+env)。

## §1.5 実装到達(2026-08-31 00:45 一次: gate_metrics + 報告 YAML commit + Render API deploys + 本番 curl + git merge-base)
| cmd | 担当 | commit | GATE | 実装内容(報告 files_modified) | 本番(Render live sha と祖先判定) |
|---|---|---|---|---|---|
| F1 cmd_4422(backend) | 影丸 | 5b50424e | **CLEAR 22:59** | `public_showcase.py`: `GET /api/public/free-coupon` / `migrations.py`: Free tier 行+可視性初期化(冪等・restore SQL コメント) / contract test 6/6 SKIP 0 | **live**: backend `ce3f7f09`(00:13 JST)⊃5b50424e=yes。`GET /api/public/free-coupon` Bearer 無し **401**(00:44 curl) |
| 検証差替 cmd_4428(backend) | 影丸 | c385c9c7 | **CLEAR 00:06** | HS256+`SUPABASE_JWT_SECRET` を除去し `GET {SUPABASE_URL}/auth/v1/user`(apikey+Bearer、timeout 5s、5xx/timeout/設定欠落を MockTransport で契約) | **live**: `ce3f7f09`⊃c385c9c7=yes。commit に `/auth/v1/user` 1 件・`SUPABASE_JWT_SECRET` 0 件 |
| F2 cmd_4423(frontend) | 才蔵 | b853b762 | **CLEAR 22:17** | `app/free/page.tsx`(Google OAuth→クーポン表示・Copy・/login 導線) / `app/auth/callback/page.tsx` / `login/sign-in-card.tsx`(`?coupon=` プリフィル+Free リンク) / `login/login-copy.ts`(EN/JA 二分文言) / `route-access-boundary.tsx`(free・callback を未認証許可) / `lib/supabase.ts`+`@supabase/supabase-js` | **live**: frontend `b853b762`(22:10 JST)=同一 commit。`/free` 200(13.5KB、chunk `free/page-3b0dea00c71e5db1.js` 参照)、`/auth/callback` 200 |
| F3 cmd_4424(LP) | 半蔵 | f9011787 | **CLEAR 00:26**(BLOCK 22:11→RC で files_modified を対象 4 ファイルへ) | `components/landing-page.tsx`+`copy/{en,ja}.ts`: Members/Free 二分・Google Free CTA(`/free?from=lp`)・footer リンク・既存 `lp_cta_click` beacon(新 step 追加なし=AC2) | **live**: LP `4b305f49`(23:27 JST)⊃f9011787=yes(merge `0a820226 cmd_4424 integrate Free CTA into SEO landing page` 経由で CLEAR より先に live)。dm-signal.com の href に `https://dm-signal-frontend.onrender.com/free?from=lp` **1 件** |

- 設計との差分(正): F1 の検証は v3.2 の通り **Supabase Auth API 方式**(4428 で HS256 を除去、secret 不要)。F3 の event は `signup_google` でなく **既存 `lp_cta_click` を流用**(`from=lp` クエリが経路記録の起点)。§4-5 `product_logins` は **未実装**(後段 cmd)。
- deploy 前提 5 点(**v3.3: 5/5 到達**): frontend env `NEXT_PUBLIC_SUPABASE_URL/ANON_KEY`=投入済(22:52、rebalancer 正本と hash 一致) / backend env=`SUPABASE_URL`・`SUPABASE_ANON_KEY`(Render API env-vars 00:44 実測で存在) / `SUPABASE_JWT_SECRET`=**不要**(4428) / Supabase Auth Redirect URL `https://dm-signal-frontend.onrender.com/auth/callback`(殿実施、runbook gist e026b243) / `VIEWER_PASSWORD_FREE`(Render API env-vars 00:44 実測で存在=殿投入)。**6 点目(v3.3 追補)**: frontend の live build 開始時刻 > `NEXT_PUBLIC_SUPABASE_*` 投入時刻(22:09 < 22:52 で不成立→00:50 再 deploy。live 後に `/free` chunk の `supabase.co` ≥1 件で判定)。
- 未実測(post_deploy_check、家老 lane→殿実機): ①Google サインイン→`/free` にクーポン表示 ②Copy ③`/login?coupon=` プリフィル→Basic-DualMomentum のみ表示 ④既存 5 tier ログイン不変。加えて **Free tier 行の DB 実在**(migration は deploy 時に走る設計。admin 画面か DB で `viewer_tiers` に `Free` 1 行・`password_env_key=VIEWER_PASSWORD_FREE`・hide 設定を目視)。

## §2 ToBe(最小構成、既存機構不変) — v3.3: 1-5 すべて本番 live、検証待ち
1. **Free tier 1 行**(F1 live。DB 行の目視は未): `viewer_tiers` に `Free`(password_env_key=`VIEWER_PASSWORD_FREE`、hide=Basic-DualMomentum 以外すべて hide、`password_expires_at` は他 tier と同じ月末)。ローテーション運用に 1 行追加。
2. **`/free` ページ(frontend、static export)**(F2 live): `supabase-js` で `signInWithOAuth({provider:"google"})`(rebalancer と同じ env・同じプロジェクト)。セッション取得後、backend `GET /api/public/free-coupon`(Authorization: Bearer <supabase access_token>)を呼ぶ。
3. **backend EP `GET /api/public/free-coupon`**(F1+4428 live): Supabase Auth API `GET /auth/v1/user`(apikey=`SUPABASE_ANON_KEY`+Bearer access_token、timeout 5s)で本人性を検証(secret 不要)→`os.getenv(free_tier.password_env_key)` と `password_expires_at` を返す(未認証 401=本番実測、rate limit)。DB 書込み 0。登録者の記録は `auth.users`(Supabase)に既にある。任意で `showcase_events` に `signup_google`/`coupon_copy` step(計測)。
4. **UX**(F2 live): クーポンカード(コード・有効期限「〜YYYY-MM-DD」・「Basic-DualMomentum のみ」)+**Copy ボタン(navigator.clipboard)**+**「このクーポンでサインイン」ボタン=`/login?coupon=<code>` でプリフィル**(SignInCard は既存 input に初期値を入れるだけ、照合は従来の verify_viewer)。
5. **誤解防止(既存メンバー)**(F2 `/login` 二分=live、F3 LP 二分=live): LP と `/login` の入口を 2 枠に分ける — 「**Members**: note に記載の当月パスワード」/「**Free**: Google で登録して当月クーポン」。`/free` 冒頭に「Free は Basic-DualMomentum のみ。Basic/Standard/Premium の方は従来どおり note のパスワードをお使いください」。Free クーポンを有料導線(note 誘導文)に混ぜない。既存の 5 tier パスワードには一切触れない。

## §3 やらないこと
- 個人ごとのクーポン発行・DB 保存(全 Free 登録者に同一の月次コード=既存 tier 方式と同じ)。
- 課金・決済(note のまま)。既存 tier 認証の変更。初月無料/free trial の文言(§4 禁則、Free は「プラン」であり「無料期間」ではない)。

## §4 未決(殿裁定、既定案付き) — v3.3 状態
1. Supabase プロジェクトは rebalancer と**同一**(既定=同一。殿 20:18) → 既定で実装・live(F2 は rebalancer と同じ env 名、Redirect URL は殿が同プロジェクトへ追加)。
2. `/free` の置き場 → 既定=app で live(F2)。LP CTA は F3 live(`/free?from=lp`)。
3. Free tier の可視範囲 → 既定=両方で F1 migration に可視性初期化を実装・live(**admin で目視確認は未**=post_deploy_check に含める)。
4. 月次クーポンの切替日=他 tier と同日(既定) → F1 は `password_expires_at` を他 tier と同じ月末に設定。9 月ローテーション時に `VIEWER_PASSWORD_FREE` も他 5 tier と同じ手順で更新(殿の手作業に 1 行追加)。

5. **経路と利用の記録(殿 20:19-20:20)**(**未実装**。F3 の `from=lp` クエリのみ到達。後段 cmd で `product_logins` を足す) → 既定案=**Supabase プロジェクトは 1 つ**(1 人 1 アカウント)。**行で持ち、列で持たない**: 追記表 `product_logins(user_id, product, source, logged_in_at)`(product=`rebalancer`/`dm-signal`/将来の値、source=`lp`/`rebalancer`/`dm-login`/`direct`。RLS: 本人 insert のみ、集計は service role)。新サービスは `product` の値が増えるだけでスキーマ不変。見やすさは view `product_users(user_id, product, first_seen, last_seen, logins)` で列の形に(実体は行)。users/profile に `logged_in_xxx` 列を足す方式は、サービス追加ごとにスキーマ変更+RLS 更新が要り、回数・時期・経路が残らないため不採用。登録日は `auth.users.created_at` で既に分かる。指標=rebalancer→DM 転換率・LP→Free→note 転換率・両方利用率・月次継続(coupon_fetch)。

## §5 工程(v3.3 状態)
| 手 | 内容 | 状態(08-31 00:45) |
|---|---|---|
| 偵察 1 | Supabase provider/JWKS/`auth.users`/env 名 | 省略(殿 20:21『着手せよ』で F1-F3 を並走配備。前提は AsIs §1 で代替) |
| F1 cmd_4422 | Free tier 行+EP+contract test | **CLEAR 22:59** 5b50424e → **live** ce3f7f09 |
| 検証差替 cmd_4428 | HS256→Supabase Auth API(secret 不要) | **CLEAR 00:06** c385c9c7 → **live** ce3f7f09(00:13) |
| F2 cmd_4423 | `/free`+Copy+`/login?coupon=`+二分文言+callback | **CLEAR 22:17** b853b762 → **live**(22:10) |
| F3 cmd_4424 | LP CTA `/free?from=lp`+二分文言(既存 `lp_cta_click`) | **CLEAR 00:26** f9011787 → **live** 4b305f49(23:27) |
| deploy 前提 | Render env 2 種+frontend env 2 種+Supabase Redirect URL+`VIEWER_PASSWORD_FREE` | **5/5 到達**(00:44 Render API 実測+殿実施) |
| 家老 post_deploy_check→殿実機 | Google サインイン→クーポン表示→Copy→`/login?coupon=`→Basic-DM 表示 ∧ 既存 5 tier ログイン不変 ∧ `viewer_tiers` に Free 行 | **未**(家老 lane。将軍 00:12/00:29 の順序付き 1 通で生貼付を要請済) |
| 後段 cmd | `product_logins`(§4-5)+`/free` noindex(SEO 案 §3) | 未起票(post_deploy_check PASS 後) |

origin: `[[殿方向性_FreeTier_GoogleAuth_20260830_1314]] -> [[殿要件_クーポン月次同期_20260830_2016]] -> [[殿提案_Supabase共用_20260830_2018]] -> [[殿指摘_rebalancerでできた_20260830_2254]] -> [[cmd_4428_AuthAPI]] -> [[dm-free-tier-google-auth_v3]] -> [[FreeTier_本番live_5of5_20260831_0045]]`
