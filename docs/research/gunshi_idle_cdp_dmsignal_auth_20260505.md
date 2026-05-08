# CDP DM-Signal FE認証手順 2026-05-05

## 概要

DM-Signal本番FEへのCDP経由認証方法。隔離プロファイルでAdmin認証を通す手順。

## 正解手順: cdp_cli.sh auth (API経由Cookie注入)

ブラウザのログインフォーム手動入力ではない。API経由でCookie注入。

### 具体手順

1. `.env.dm-signal`作成 (`/mnt/c/Python_app/auto-ops/.env.dm-signal`):
```
ADMIN_USER=simokitafresh
ADMIN_PASS=703
FRONTEND_URL=https://dm-signal-frontend.onrender.com
```

2. 認証実行:
```bash
cdp_cli.sh auth --env .env.dm-signal --port 9400
```

3. 内部フロー:
- POST /api/admin/login (Basic Auth) → Set-Cookie
- Network.setCookie でブラウザに注入

4. ブラウザでCompare Summaryページをリロード → 認証済み表示

## 根拠

- `/mnt/c/Python_app/auto-ops/cdp/README.md` L153-167: 認証フロー定義
- `backend/.env`: ADMIN_USER=simokitafresh, ADMIN_PASS=703
- Admin認証: Cookie+BasicAuth方式 (`context/dm-signal-frontend.md` L74)

## Invalid username or passwordの原因

CDPで開いたブラウザが隔離プロファイルのためCookieドメインが不一致。
cdp_cli.sh auth → Network.setCookie直接注入で回避可能。

## 汎用化(全PJ対応)設計

掲示板blt_20260505_212236_fb7c1eに設計提案済み:
- 3層基礎知識: primitives + PJ固有認証 + PJ固有ページ期待値
- Level 4-5埋込み: cmd_save.shでFE変更検出→CDP確認AC自動注入
- cdp_verify_fe.sh汎用スクリプト(auth+navigate+screenshot)
