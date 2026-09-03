# X API 登録ランブック(バム @TokyoJibika の自動投稿用)v1.1

- 作成: 2026-09-03 15:35 将軍(殿指示 15:33『x API 登録のステップバイステップのランブック』)
- 目的: 設計書 `docs/research/x_account_ops_automation_asis_tobe_5w1h_20260903.md` §10/§11 の P1(下書き→gate→承認→X API 投稿)に必要な X API の登録・認可・トークン保管を、殿の操作と将軍側の作業に分けて 1 手ずつ書く
- 前提: 個人・単一アカウント・自分の投稿の書込みと自分の投稿指標の読取りのみ。他ユーザーのデータは取得しない(13:01 用途説明文のとおり)
- 所要: 殿 15〜25 分、将軍 10 分
- **v1.1(15:45)の訂正**: 2026 年の X API v2 は **従量課金(pay-per-usage、クレジット前払い)のみで、旧 Free/Basic/Pro の月額プランは無い**(docs.x.com/x-api/getting-started/pricing を 15:40 に確認)。殿が見た「Developer PPU パイロット契約」はこの従量課金への同意。入口は developer.x.com ではなく **console.x.com**(殿の account ページ= https://console.x.com/accounts/2095362144241930242)。以下は console.x.com 準拠に書き直した
- 用語: X API = X(旧 Twitter)の投稿・読取り API。xAI API(Grok)とは別物(設計書 §10)

---

## 0. 全体像(6 段)

| 段 | 誰 | 何を | 成果物 |
|---|---|---|---|
| 1 | 殿 | console.x.com に @TokyoJibika でサインインし Developer Agreement と PPU パイロット契約に同意、用途説明を提出 | account ページ(accounts/2095362144241930242)が開く |
| 2 | 殿 | クレジットを少額購入(従量課金の前払い) | Billing に残高 |
| 3 | 殿 | App を作る(New App) | App が 1 つ、Keys タブ |
| 4 | 殿 | App の OAuth 2.0 設定(User authentication settings) | Client ID と Client Secret |
| 5 | 殿+将軍 | 一度だけブラウザで認可(PKCE)→ access/refresh token | `config/x_api.env`(git-ignore) |
| 6 | 将軍 | 疎通(`GET /2/users/me`)→ 投稿は cmd_4472 の CLI 経由 | 200 |

### 費用の目安(15:40 実測の価格表)
| 操作 | 単価 | 本運用の月量 | 月額目安 |
|---|---|---|---|
| 投稿(URL 無し) | $0.015/回 | — | — |
| **投稿(URL 付き)** | **$0.200/回** | 週 3〜6 本=月 13〜26 本、ほぼ全て URL 付き | **$2.6〜5.2** |
| 自分の投稿の読取り(owned reads) | $0.001/件 | 週次で最大 30 件 | $0.1 未満 |
| 合計 | | | **月 $3〜6 程度**。初回は $10〜20 のクレジットで数か月持つ |

X API のクレジット購入額に応じて xAI API(Grok)のクレジットが 10〜20% 付与される(累計 $200 以上から)。本運用の額では対象外。

---

## 1. console.x.com のページの読み方(殿)

https://console.x.com/accounts/2095362144241930242 は殿の **developer account(組織)ページ**で、左のナビゲーションが次の構成になっている(15:40 の docs.x.com 確認。画面の文言が違う場合は近いものを選ぶ)。

| ナビ | 何をする所 | 本運用で使うか |
|---|---|---|
| **Apps**(または Projects & Apps) | App の作成・一覧・Keys(認証情報)・User authentication settings | **使う**(3 節・4 節) |
| **Billing / Credits** | クレジットの購入・残高・支払い方法 | **使う**(2 節) |
| **Usage** | リクエスト数とクレジット消費の実績 | 月 1 回見る |
| **Members / Team** | 組織のメンバー | 使わない(殿 1 人) |
| **Settings** | 組織名・用途説明・規約 | 用途説明の修正時のみ |

初回にこのページへ来た時点で「段 1」は済んでいる(サインインと同意が通っている)。用途説明が未提出なら Settings か上部のバナーから 13:01 の英文を貼る。

## 2. クレジット購入(殿)

1. Billing(または Credits)→ **Add credits / Buy credits**。
2. 金額は **$10〜$20** で足りる(上の費用表)。支払い方法はカード。
3. 購入後、残高が表示されればよい。残高 0 のままだと 6 節の投稿が `402` または `429` で失敗する。

## 3. App 作成(殿)

1. Apps → **New App**(または Create App)。
   - App name: `dm-signal-poster`(一意。重複なら末尾に数字)
   - Description: `Automated posting of my own research summaries to my own account`
   - Website: `https://dm-signal.com`
2. 作成直後に **Keys** タブに 4 種の認証情報が出る。**本運用で使うのは「Client ID & Secret(OAuth 2.0)」だけ**。Bearer Token・API Key/Secret・Access Token/Secret(OAuth 1.0a)は使わないので、画面を閉じてよい(必要なら後で Keys タブから再生成できる)。

## 4. User authentication settings(殿)

App の **Settings**(または Auth)タブ › **User authentication settings › Set up**(console.x.com では App 詳細の中にある)。

| 項目 | 値 |
|---|---|
| App permissions | **Read and write** |
| Type of App | **Web App, Automated App or Bot**(Confidential client) |
| Callback URI / Redirect URL | `http://127.0.0.1:8585/callback` |
| Website URL | `https://dm-signal.com` |
| Organization name(任意) | 空欄または DM-Signal |
| Terms of service / Privacy policy(任意) | 空欄で可 |

Save すると **OAuth 2.0 Client ID** と **Client Secret** が 1 度だけ表示される。Client Secret はこの画面でしか見えないので、**殿が将軍へ渡す前に自分の端末のパスワードマネージャへ保存**する。将軍へは次の 5 節の方法で渡す(チャットに貼らない)。

## 5. 一度だけの認可(PKCE)と token 保管(殿+将軍)

### 5.1 殿→将軍への Client ID/Secret の受け渡し

チャット・inbox・掲示板・gist には貼らない。WSL 側の git-ignore ファイルに殿が直接書く。

```bash
# 将軍 pane または任意のシェルで(殿が実行)
mkdir -p ~/multi-agent-shogun/config
cat > ~/multi-agent-shogun/config/x_api.env <<'ENV'
X_CLIENT_ID=ここに Client ID
X_CLIENT_SECRET=ここに Client Secret
X_REDIRECT_URI=http://127.0.0.1:8585/callback
X_SCOPES=tweet.read tweet.write users.read offline.access
ENV
chmod 600 ~/multi-agent-shogun/config/x_api.env
```

`config/x_api.env` は `.gitignore` 済み(将軍が 15:35 に `git check-ignore` で確認済み。未登録なら将軍が先に追加する)。

### 5.2 認可 URL の生成(将軍)

将軍が PKCE の `code_verifier` と `code_challenge` を作り、認可 URL を 1 本出す。

```bash
cd ~/multi-agent-shogun && set -a && . config/x_api.env && set +a
VERIFIER=$(openssl rand -base64 64 | tr -d '=+/\n' | cut -c1-96)
CHALLENGE=$(printf '%s' "$VERIFIER" | openssl dgst -sha256 -binary | openssl base64 | tr '+/' '-_' | tr -d '=\n')
STATE=$(openssl rand -hex 16)
echo "$VERIFIER" > /tmp/x_pkce_verifier.txt; chmod 600 /tmp/x_pkce_verifier.txt
python3 - "$X_CLIENT_ID" "$X_REDIRECT_URI" "$X_SCOPES" "$CHALLENGE" "$STATE" <<'PY'
import sys, urllib.parse
cid, uri, scopes, ch, st = sys.argv[1:]
q = dict(response_type='code', client_id=cid, redirect_uri=uri, scope=scopes, state=st, code_challenge=ch, code_challenge_method='S256')
print('https://x.com/i/oauth2/authorize?' + urllib.parse.urlencode(q))
PY
```

出力された URL を殿へ渡す(URL 自体に secret は含まれない)。

### 5.3 ブラウザで認可(殿)

1. 5.2 の URL を **@TokyoJibika でログインしているブラウザ**で開く。
2. 「Authorize app」を押す。
3. `http://127.0.0.1:8585/callback?state=...&code=...` へ飛び、ブラウザは「接続できません」と出る(ローカルに受け口が無いため正常)。**アドレスバーの URL 全体をコピー**して将軍へ渡す(`code` は 30 秒程度で失効するので、コピーしたらすぐ渡す)。
   - 代替: 将軍が 5.2 の直前に `python3 -m http.server 8585 --bind 127.0.0.1` を別 pane で立てておけば、アクセスログに `code=` が残る。

### 5.4 token 交換と保管(将軍)

```bash
cd ~/multi-agent-shogun && set -a && . config/x_api.env && set +a
CODE='殿から受け取った URL の code= の値'
curl -s -u "$X_CLIENT_ID:$X_CLIENT_SECRET" -X POST https://api.x.com/2/oauth2/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "grant_type=authorization_code" \
  --data-urlencode "code=$CODE" \
  --data-urlencode "redirect_uri=$X_REDIRECT_URI" \
  --data-urlencode "code_verifier=$(cat /tmp/x_pkce_verifier.txt)" \
  --data-urlencode "client_id=$X_CLIENT_ID" > /tmp/x_token.json
python3 -c "import json;d=json.load(open('/tmp/x_token.json'));print({k:(v if k in('token_type','expires_in','scope') else '***') for k,v in d.items()})"
```

`access_token`(2 時間有効)と `refresh_token`(offline.access で発行)を `config/x_api.env` に追記し、一時ファイルを消す。

```bash
python3 - <<'PY'
import json
d=json.load(open('/tmp/x_token.json'))
with open('config/x_api.env','a') as f:
    f.write(f"X_ACCESS_TOKEN={d['access_token']}\nX_REFRESH_TOKEN={d['refresh_token']}\n")
PY
rm -f /tmp/x_token.json /tmp/x_pkce_verifier.txt
```

### 5.5 refresh(将軍・cmd_4472 の CLI が自動で行う)

```bash
curl -s -u "$X_CLIENT_ID:$X_CLIENT_SECRET" -X POST https://api.x.com/2/oauth2/token \
  --data-urlencode "grant_type=refresh_token" \
  --data-urlencode "refresh_token=$X_REFRESH_TOKEN" \
  --data-urlencode "client_id=$X_CLIENT_ID"
```

refresh_token は使うたびに新しいものが返るので、返ってきた値で `config/x_api.env` を毎回上書きする(古い refresh_token は無効になる)。

## 6. 疎通確認と最初の投稿(将軍)

```bash
# 自分のアカウント(200 と @TokyoJibika の id が返れば OK)
curl -s -H "Authorization: Bearer $X_ACCESS_TOKEN" "https://api.x.com/2/users/me"
# 投稿(cmd_4472 の x_post.sh post が行う。手で確認する場合のみ)
curl -s -H "Authorization: Bearer $X_ACCESS_TOKEN" -H 'Content-Type: application/json' \
  -X POST https://api.x.com/2/tweets -d '{"text":"(gate PASS 済みの本文)"}'
```

201 と `data.id` が返れば成功。最初の 1 本は設計書 §11 の固定ポスト(完全ガイド / How to / dm-signal 登録無料・PF は Basic / 境界の一文)。

## 6b. XDK(公式 SDK)を使う場合(将軍、cmd_4472 の実装判断)

X 公式の Python/TypeScript SDK「XDK」がある(devcommunity の告知は要ログインで本文を取れず、docs.x.com/xdks で 15:40 に確認)。

```bash
pip install xdk
```

```python
from xdk.oauth2_auth import OAuth2PKCEAuth
from xdk import Client
auth = OAuth2PKCEAuth(client_id=..., redirect_uri="http://127.0.0.1:8585/callback",
                      scope="tweet.read tweet.write users.read offline.access")
print(auth.get_authorization_url())          # 5.2 と同じ URL
tokens = auth.fetch_token(authorization_response=callback_url)   # 5.4 と同じ
client = Client(token=tokens)                # token 辞書を渡すと自動 refresh
client.posts.create(post_data={"text": "..."})   # POST /2/tweets
```

判断: cmd_4472 の CLI は curl 直叩き(依存 0、fail-close が書きやすい)で先に作り、XDK は S6 の読取りや将来の media 添付で採用を検討する。どちらでも token の保管先は `config/x_api.env` で同じ。

## 7. 上限と注意

- 上限は月額プランではなくクレジット残高。投稿 1 本(URL 付き)= $0.20 なので、cmd_4472 の CLI は投稿前に残高不足を `402/429` で検知して停止する(fail-close)。
- 自分の投稿の指標(owned reads)は $0.001/件で読める。S6 の KPI 還流は API で足りる(設計書 §10 の『Free では読めない』は v1.1 で訂正)。
- `403 Forbidden` が出たら App permissions が Read のみ、または scope に `tweet.write` が無い。4 節と 5.2 を見直して再認可。
- `401 Unauthorized` は access_token 失効。5.5 の refresh。
- 用途説明で審査に落ちるのは「他ユーザーへの自動リプライ・フォロー・スクレイピング」。本運用には無い。

## 8. 完了判定(二値)

| # | 条件 | 確認 |
|---|---|---|
| 1 | `config/x_api.env` に Client ID/Secret/Access/Refresh の 4 値 | `grep -c '^X_' config/x_api.env` → 6 以上、`git check-ignore config/x_api.env` → 出力あり |
| 2 | `GET /2/users/me` が 200 で username=TokyoJibika | curl |
| 3 | secret 値が git・gist・inbox・掲示板・設計書に 0 件 | `git log -p -S'X_CLIENT_SECRET=' --all` → 0 |
| 4 | cmd_4472 の `x_post.sh post` が creds ありで 201(gate PASS 本文) | 家老 production_proof |

---

## v1.1 (2026-09-03 15:45)

AsIs 注釈: v1.0(15:35)は developer.x.com と Free tier を前提に書いた。ToBe 注釈: v1.1 は docs.x.com(pricing/getting-access/xdks)を 15:40 に確認し console.x.com・従量課金・XDK に揃えた。
