# DM-Signal LP ドメイン runbook — dm-signal.com を Cloudflare Registrar で取得し Render LP に接続する（ステップ・バイ・ステップ）

> 版: 2026-08-30 17:22(殿裁定 16:42『別サイトでやろう』/17:14『.jp にこだわらない』)。旧 .jp 手順は廃止(このファイル名は gist URL 維持のため据え置き)。
> 役割分担: **殿=Step 1〜2 のみ(購入+API トークン)**。Step 3 以降は将軍/家老が実行し、殿は最後に確認だけ。
> 一次根拠: Render 公式 [Custom Domains](https://render.com/docs/custom-domains) / [Configure Cloudflare DNS](https://render.com/docs/configure-cloudflare-dns)、Cloudflare Registrar [対応 TLD](https://developers.cloudflare.com/registrar/top-level-domains/)。

## Step 0 — 前提(確認済み 17:14)
- `dm-signal.com` は `dig NS` で NS 無し=未登録の公算大(第 2 候補 `dmsignal.com`、第 3 `dm-signal.io`)。最終判定は Step 1 の検索画面。
- Render: FE `dm-signal-frontend.onrender.com`(app、変更なし)・BE `dm-signal-backend.onrender.com`。LP 用 static site は Step 4 で新設。
- .com は Cloudflare Registrar 対応=購入と同時にゾーン作成・NS 設定・SSL 発行まで Cloudflare 内で完結。

## Step 1 — 殿: ドメイン購入(5 分)
1. https://dash.cloudflare.com → 左メニュー **Domain Registration → Register Domains**。
2. 検索欄に `dm-signal.com` → 「Available」なら **Purchase**(価格は原価 ≈ US$10.5/年、マークアップ 0)。
3. 登録者情報(氏名・住所・メール)を入力。**Whois 代行は自動で ON**(Cloudflare が代理公開)。**Auto-renew ON**。
4. 支払い完了→ドメイン一覧に `dm-signal.com` が **Active** で並ぶ。ネームサーバーは Cloudflare 固定(変更不要)。
- 完了条件: Domain Registration の一覧に `dm-signal.com / Active`。

## Step 2 — 殿: 将軍用 API トークン発行(3 分。手動で DNS を打つなら省略可)
1. 右上アイコン → **My Profile → API Tokens → Create Token**。
2. テンプレート **「Edit zone DNS」** を選択 → Permissions に **Zone / SSL and Certificates / Edit** を 1 行追加。
3. Zone Resources: **Include / Specific zone / dm-signal.com**(このゾーンだけ)。
4. Continue → Create Token → 表示されたトークンを将軍へ(1 回しか表示されない)。
- 完了条件: トークン文字列を将軍が受領(将軍は `~/.bashrc` の `CLOUDFLARE_LP_TOKEN` に保存)。

## Step 3 — 将軍: Cloudflare DNS と SSL(API または画面。5 分)
Render 公式の Cloudflare 手順どおり **apex も www も CNAME**(A レコード IP は使わない)。
| Type | Name | Target | Proxy |
|---|---|---|---|
| CNAME | `@` | `dm-signal-lp.onrender.com`(Step 4 の LP サービス名) | **DNS only**(グレー雲) |
| CNAME | `www` | `dm-signal-lp.onrender.com` | **DNS only** |
- **AAAA レコードがあれば全削除**(Render は IPv6 未対応)。
- **SSL/TLS → Overview → 暗号化モード = Full**。
- API 例(将軍実行):
  ```bash
  Z=$(curl -s -H "Authorization: Bearer $CLOUDFLARE_LP_TOKEN" "https://api.cloudflare.com/client/v4/zones?name=dm-signal.com" | jq -r .result[0].id)
  for n in "@" "www"; do curl -s -X POST -H "Authorization: Bearer $CLOUDFLARE_LP_TOKEN" -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/zones/$Z/dns_records" \
    -d "{\"type\":\"CNAME\",\"name\":\"$n\",\"content\":\"dm-signal-lp.onrender.com\",\"proxied\":false,\"ttl\":1}"; done
  curl -s -X PATCH -H "Authorization: Bearer $CLOUDFLARE_LP_TOKEN" "https://api.cloudflare.com/client/v4/zones/$Z/settings/ssl" -d '{"value":"full"}'
  ```
- 完了条件: `dig +short CNAME www.dm-signal.com` が `dm-signal-lp.onrender.com.`、`dig +short dm-signal.com` が Render の IP を返す(CNAME flattening)。

## Step 4 — 家老: Render に LP static site を作る(10 分。cmd_4417 の CLEAR 後)
1. Render Dashboard → **New → Static Site** → repo `DM-Signal`、branch `main`。
2. **Root Directory = `lp`**、Build Command = `npm ci && npm run build`、Publish Directory = `out`。
3. 環境変数: `NEXT_PUBLIC_API_HOST=https://dm-signal-backend.onrender.com`、`NEXT_PUBLIC_APP_HOST=https://dm-signal-frontend.onrender.com`。
4. サービス名を `dm-signal-lp` にする(→ `dm-signal-lp.onrender.com`)。Deploy → `https://dm-signal-lp.onrender.com/` と `/ja` が 200。
- 完了条件: onrender URL で EN/JA が表示(表の数値・Sign in ボタン・hreflang)。

## Step 5 — 家老: Render に custom domain を付ける(5 分+証明書待ち)
1. LP サービス → **Settings → Custom Domains → Add**: `dm-signal.com` → 続けて `www.dm-signal.com`。
2. Render が DNS を検証(Step 3 が済んでいれば数分で **Verified**)→ TLS 証明書を自動発行・自動更新。HTTP→HTTPS は自動リダイレクト。
3. `curl -sI https://dm-signal.com/` と `https://www.dm-signal.com/ja` が 200。
- 完了条件: 両ドメインが Render で Verified、ブラウザで鍵マーク。
- 任意: 証明書発行後に Cloudflare の Proxy を **Proxied(オレンジ雲)** にすると WAF/キャッシュが使える(初期は DNS only のままでよい)。

## Step 6 — backend: CORS(cmd_4419、家老 deploy)
- `origins` に `https://dm-signal.com` と `https://www.dm-signal.com`(+ env `LP_ORIGINS`)が入った backend を deploy。
- 完了条件: `curl -sI -H "Origin: https://dm-signal.com" https://dm-signal-backend.onrender.com/api/public/showcase | grep -i access-control-allow-origin` が `https://dm-signal.com`。

## Step 7 — 将軍+殿: 検索エンジン(10 分)
1. 殿の Google アカウントで Search Console → **プロパティを追加 → ドメイン** → `dm-signal.com` → 表示される TXT 値を将軍へ。
2. 将軍が Cloudflare DNS に `TXT @ <値>` を追加(API 1 行)→ 殿が「確認」を押す。
3. サイトマップ `https://dm-signal.com/sitemap.xml` を送信(EN/JA の 2 URL、hreflang は各ページ内)。
- 完了条件: Search Console で所有権確認済み・サイトマップ「成功」。

## Step 8 — 殿: 実機確認(初見ユーザー通し、§2.5)
- シークレット窓×スマホで `https://dm-signal.com/` → 30 秒で分かるか、Sign in が画面内か、`/ja` に切替できるか、CTA が app の /login に着地するか。
- 気づきは区間(lp_view→lp_cta_click→login_view→submit→ok)で 1 箇所名指し(記事の教え: たいてい思っていた場所と違う)。

## 後日(任意)
- app を `app.dm-signal.com` に移す: Step 3 に `CNAME app → dm-signal-frontend.onrender.com` を 1 行、Render FE に custom domain 追加、LP の `NEXT_PUBLIC_APP_HOST` を差替え。ログイン機構は cookie 非依存なので影響なし。

## Sources(2026-08-30 17:00-17:22 確認)
- Render Custom Domains: https://render.com/docs/custom-domains
- Render × Cloudflare DNS(CNAME @/www、DNS only→Proxied、SSL=Full、AAAA 削除): https://render.com/docs/configure-cloudflare-dns
- Cloudflare Registrar 対応 TLD(.com 対応・.jp 非対応): https://developers.cloudflare.com/registrar/top-level-domains/ / https://www.cloudflare.com/tld-policies/
