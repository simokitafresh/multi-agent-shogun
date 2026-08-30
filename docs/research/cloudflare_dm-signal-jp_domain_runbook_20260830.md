<!-- gist-master: d2165f9b8fd4a3fbd464c101ab66f9e9 cloudflare_dm-signal-jp_domain_runbook_20260830.md -->
# DM-Signal LP ドメイン — Cloudflare Registrar 取得・DNS・Render 接続 runbook（2026-08-30 17:15 改版: 殿裁定『.jp にこだわらない』）

> 対象: DM-Signal LP 別サイト(設計書 v2 §9)。殿裁定 16:42『別サイトでやろう』/16:44『dm-signal.jp を Cloudflare で取ろう』。
> **一次確認で判明した前提修正**: **Cloudflare Registrar は .jp を扱えない**(サポート TLD 外。2025-07 時点の技術記事と 2026-08-30 の Cloudflare Registrar docs で一致)。∴ **取得は国内レジストラ、DNS/SSL 管理は Cloudflare(無料プラン)** の二段構成にする。.com/.net なら Cloudflare Registrar 一体で済む(参考: 代替案 §6)。

## §0a 改版（殿裁定 2026-08-30 17:14『.jp にこだわらない』）
- **Cloudflare Registrar 一体で完結する TLD を選ぶ**: 推薦 **`dm-signal.com`**(第 2 候補 `dmsignal.com`、第 3 `dm-signal.io`)。17:14 の `dig NS` で 6 候補(dm-signal.com / dmsignal.com / dm-signal.io / dm-signal.app / dm-signal.net / dmsignal.app)とも NS レコード無し=未登録の公算大(最終確認は Cloudflare の検索画面)。
- 費用: Cloudflare Registrar は原価販売(.com ≈ US$10.5/年、.io ≈ US$33/年、.app ≈ US$14/年。マークアップ 0、Whois 代行込み)。
- **殿の操作は 1 回**: Cloudflare ダッシュボード → Domain Registration → Register Domains → `dm-signal.com` を検索→購入(自動更新 ON)。購入と同時にゾーンが作られ、ネームサーバーは Cloudflare 固定=§1〜§3(国内レジストラ・NS 変更)は**不要**。
- 以後は §4(DNS: CNAME @ と www→`<lp>.onrender.com`、DNS only、AAAA 削除、SSL=Full)→§5(Render custom domain)→§7(将軍 API 代行=ゾーン限定トークン)の順。所要 30 分以内。
- app 側は後日 `app.dm-signal.com` に CNAME 1 行で移せる(§6)。

## §0 全体像（.jp を選ぶ場合の旧手順。§0a 採用後は §1-§3 不要）（殿の操作は §1 と §3 の 2 回だけ）
| # | 誰 | 何を | 所要 |
|---|---|---|---|
| 1 | 殿 | 国内レジストラで `dm-signal.jp` を取得 | 10 分 |
| 2 | 殿 | Cloudflare(無料)にサイト追加→ネームサーバー 2 本を控える | 5 分 |
| 3 | 殿 | レジストラ側でネームサーバーを Cloudflare の 2 本へ変更 | 5 分(反映 数分〜24h) |
| 4 | 将軍/家老 | Cloudflare DNS に Render 向け CNAME 2 行(DNS only)+AAAA 削除+SSL=Full | 5 分 |
| 5 | 家老 | Render LP static site に custom domain 2 件追加→TLS 自動発行→verify | 10 分 |
| 6 | 将軍 | Search Console 登録(TXT 1 行)、hreflang/sitemap 確認 | 10 分 |

## §1 取得（国内レジストラ）
- 候補: **Xserver ドメイン**(技術記事の実績あり、ネームサーバー変更が管理画面から可) / **Value-Domain** / お名前.com(更新時に「サービス維持調整費」10〜20% 上乗せの報告あり=避けたい)。
- 汎用 JP(`dm-signal.jp`)は**日本国内に住所があれば個人・法人どちらでも登録可**。登録者情報(氏名・住所)は Whois 代行が使える。
- 取得時の設定: **ネームサーバーは後で変えるので既定のまま**でよい。自動更新 ON。DNSSEC は OFF のまま(Cloudflare 移行後に必要なら Cloudflare 側で有効化)。
- 費用目安: 取得 ¥1,000〜3,000/年、更新 ¥3,000 前後/年(レジストラで差。表示価格に維持調整費が乗るかを確認)。

## §2 Cloudflare にサイト追加（無料プラン）
1. Cloudflare ダッシュボード → **Add a site** → `dm-signal.jp` → **Free** プラン。
2. Cloudflare が既存 DNS を走査して一覧を出す(新規ドメインなので空でよい)。
3. 表示される **ネームサーバー 2 本**(例: `xxx.ns.cloudflare.com` / `yyy.ns.cloudflare.com`)を控える。

## §3 レジストラでネームサーバー変更（殿）
- レジストラ管理画面 → ドメイン `dm-signal.jp` → ネームサーバー設定 → 「他社のネームサーバーを使う」→ §2 の 2 本を入力して保存。
- 確認: `nslookup -type=ns dm-signal.jp` が cloudflare の NS を返せば完了(反映は数分〜最大 24h。Cloudflare 側は「Active」表示になる)。

## §4 Cloudflare DNS（将軍/家老。Render 公式 docs 2026-08-30 版）
Render の Cloudflare 向け公式手順は **apex も www も CNAME**(Cloudflare の CNAME flattening で apex に CNAME を置ける)。A レコードの IP は使わない。
| Type | Name | Target | Proxy |
|---|---|---|---|
| CNAME | `@` | `<LP サービス名>.onrender.com`(例 `dm-signal-lp.onrender.com`) | **DNS only(グレー雲)** で開始 |
| CNAME | `www` | 同上 | **DNS only** で開始 |
- **AAAA レコードは全て削除**(Render は IPv6 未対応)。
- **SSL/TLS → Overview → 暗号化モード = Full**(Render 公式の指定。Full(strict) でも可だが公式は Full)。
- Render 側で証明書が発行され Verified になった**後**に、必要なら Proxy を **Proxied(オレンジ雲)** に切替可(WAF/キャッシュを使う場合)。初期は DNS only のまま運用してよい。
- Cloudflare の「Always Use HTTPS」は Render 側が HTTP→HTTPS リダイレクトするので ON にしても二重にならない。

## §5 Render 側（家老 post_deploy_check）
1. LP 用 **Static Site** を作成(repo=DM-Signal、Root Directory=`lp`、Build=`npm ci && npm run build`、Publish=`out`)。まず `dm-signal-lp.onrender.com` で動作確認。
2. Settings → **Custom Domains → Add**: `dm-signal.jp` と `www.dm-signal.jp` の 2 件。
3. Render が DNS を検証→**TLS 証明書を自動発行・自動更新**。HTTP は自動で HTTPS へリダイレクト。
4. 検証: `curl -sI https://dm-signal.jp/` と `https://www.dm-signal.jp/ja` が 200、証明書の発行者が Let's Encrypt/Google Trust。
5. 環境変数: `NEXT_PUBLIC_API_HOST=https://dm-signal-backend.onrender.com`、`NEXT_PUBLIC_APP_HOST=https://dm-signal-frontend.onrender.com`。backend の CORS に `https://dm-signal.jp`/`https://www.dm-signal.jp` を追加(cmd_4419)。

## §6 代替案（.jp にこだわらない場合）
- `dm-signal.com` 等なら **Cloudflare Registrar で取得〜DNS〜SSL が 1 画面**で完結(原価販売・上乗せなし)。§1/§3 が不要になる。
- app 側を後日 `app.dm-signal.jp` へ移す時は §4 に CNAME `app`→`dm-signal-frontend.onrender.com` を 1 行足し、Render FE に custom domain を追加するだけ(cookie 非依存なのでログイン機構に影響なし)。

## §7 将軍が API で代行できる範囲
- Cloudflare DNS の CNAME 追加/AAAA 削除/SSL モード変更: **Zone:DNS Edit + Zone:SSL and Certificates Edit** 権限の API トークン(対象ゾーン=dm-signal.jp のみ)があれば将軍が実行する。トークンは Cloudflare → My Profile → API Tokens → Create Token(テンプレ「Edit zone DNS」+ SSL 権限追加、対象ゾーン限定)。
- Render custom domain 追加/verify: 既存 `RENDER_API_KEY` で家老レーンが実行可。
- Search Console: 殿の Google アカウントで「ドメイン プロパティ」追加→表示される TXT を将軍が Cloudflare DNS に登録→殿が「確認」。

## Sources（2026-08-30 17:00-17:05 確認）
- Cloudflare Registrar 対応 TLD: https://developers.cloudflare.com/registrar/top-level-domains/ / https://www.cloudflare.com/tld-policies/ (.jp 非掲載=非対応)
- .jp を Cloudflare DNS で使う手順(Xserver ドメイン実績): https://zenn.dev/nanyanen/articles/9feea6e0bac1ed / https://izanami.dev/post/2aa15b13-7a82-42e0-b856-c8afea0cfb5a
- Render Custom Domains: https://render.com/docs/custom-domains
- Render × Cloudflare DNS(CNAME @/www、DNS only→Proxied、SSL=Full、AAAA 削除): https://render.com/docs/configure-cloudflare-dns
- お名前.com の維持調整費の言及: https://note.com/sphere_/n/nbdaae33112b2
