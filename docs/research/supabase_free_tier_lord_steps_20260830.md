<!-- gist-master: e026b24398cfb686a892f7650e479de2 supabase_free_tier_lord_steps_20260830.md -->
# Free tier deploy 前提 — 殿の Supabase ダッシュボード操作 2 手（ステップ・バイ・ステップ）— 2026-08-30 23:35

> 目的: DM-Signal Free tier(Google 登録→月次クーポン)を本番 deploy するために、**将軍・家老では書けない設定 2 つ**を殿が Supabase ダッシュボードで行う。所要 3 分。
> 前提(一次 2026-08-30 22:50-23:32 家老): Supabase プロジェクトは rebalancer と同一。Management API のアクセストークン 0・Supabase CLI ログイン 0=agent 側から Auth 設定は書けない。JWT secret は **不要になった**(cmd_4428: backend は `GET /auth/v1/user` で検証。rebalancer と同じく secret を持たない)。

## 手順 1: Auth Redirect URL の追加（必須。これが無いと Google サインイン後に `/free` へ戻れない）

| Step | 操作 | 完了の二値 |
|---|---|---|
| 1 | https://supabase.com/dashboard → rebalancer と同じプロジェクトを開く | プロジェクト名が rebalancer で使っているものと一致 |
| 2 | 左メニュー **Authentication** → **URL Configuration** | 「Site URL」と「Redirect URLs」の画面 |
| 3 | **Redirect URLs** の「Add URL」に次を 1 行追加して Save: `https://dm-signal-frontend.onrender.com/auth/callback` | 一覧に当該 URL が 1 行表示 |
| 4 | (任意・将来) `app.dm-signal.com` へ移す時は `https://app.dm-signal.com/auth/callback` も同様に追加 | — |

- 補足: Site URL は rebalancer のまま変えない(rebalancer のログインに影響しない)。Redirect URLs は複数登録できる=追加のみ。
- 確認(将軍が deploy 後に実施): `/free` で Google サインイン→`/auth/callback`→`/free` にクーポン表示。失敗時は Supabase の Auth ログに `redirect_to not allowed` が出る。

## 手順 2: Free tier の月次クーポン値（`VIEWER_PASSWORD_FREE`）を Render backend env へ

| Step | 操作 | 完了の二値 |
|---|---|---|
| 1 | 9 月分の Free クーポン文字列を決める(他 tier のパスワードと同じ運用。Basic-DualMomentum のみ閲覧) | 値を殿が保持 |
| 2 | https://dashboard.render.com → **dm-signal backend**(srv-d4ja7q15pdvs739a4q1g)→ Environment → Add: key `VIEWER_PASSWORD_FREE` = その値 → Save | env 一覧に key が 1 行 |
| 3 | 以後は毎月、他 tier のパスワードを差し替えるのと同じタイミングで値を更新 | — |

- 値は会話・inbox・掲示板に貼らない(Render 画面へ直接)。将軍・家老は key の存在だけを API で確認する。
- backend の他の env(`SUPABASE_URL`・`SUPABASE_ANON_KEY`)は家老が rebalancer と同値を投入する(殿の操作不要)。frontend の 2 key は 22:52 投入済。

## やらなくてよいこと
- JWT secret のコピー(cmd_4428 で不要化)。
- Google provider の設定(rebalancer で設定済み、同一プロジェクトなので共用)。

## post_deploy_check（Free tier、同一live revisionで上から順に二値確認）

1. **env→build順序**: Render APIでfrontend live deployの`createdAt`が`NEXT_PUBLIC_SUPABASE_URL`と`NEXT_PUBLIC_SUPABASE_ANON_KEY`の更新時刻より後である。後でなければBLOCKし、env更新後にclear-cache redeployする。
2. **static chunk焼込み**: `GET /free`のHTMLからpage chunk URLを抽出し、`curl`したchunk内の`supabase.co`一致が1件以上である。0件ならBLOCKし、Googleサインイン操作へ進まない。
3. **Googleサインイン→クーポン**: `/free`でGoogleサインインし、`/auth/callback`を経て`/free`へ戻り、クーポンコードと有効期限が表示される。
4. **Copy**: Copy押下後、クリップボード値が表示中のクーポンコードと完全一致する。
5. **クーポン引継ぎ**: 「このクーポンでサインイン」から`/login?coupon=`へ遷移し、入力欄が同じクーポン値でプリフィルされる。
6. **Free可視範囲**: クーポンでサインイン後、Basic-DualMomentumのみ表示される。併せて既存5 tierのログイン不変を確認する。

## 完了後
殿が「2 手やった」と一言 → 家老が F1/F2/F3(cmd_4422/4423/4424+4428)を deploy → post_deploy_check(Google サインイン→クーポン表示→Copy→`/login?coupon=`→Basic-DM 表示 ∧ 既存 5 tier ログイン不変)→ 掲示板へ生貼付。

origin: `[[殿指示_できないならgist_20260830_2254]] -> [[家老一次_management_token_0]] -> [[supabase_free_tier_lord_steps]]`
