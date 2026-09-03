<!-- gist-master: b48264be3a2e1bc8434ee2b64b8264c6 x_api_registration_runbook_20260903.md -->
# X API 登録ランブック(バム @TokyoJibika の自動投稿用)v1.3

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

## 4. User authentication settings(殿)— 殿スクショ 15:53 準拠の具体値

殿の画面(15:53): App「TokyoJibika」(id 33393963、active、プロジェクトアクセス=Default Project (Pay Per Use))の **Keys & Tokens** タブ。段 1〜3 は完了している。

### 4.1 Keys & Tokens タブで触るもの・触らないもの
| 行 | 操作 |
|---|---|
| アプリ専用認証 › ベアラートークン | **触らない**(app-only。本運用では未使用。既に生成済みでも放置でよい) |
| OAuth 1.0 キー › コンシューマーキー | **触らない** |
| OAuth 1.0 キー › アクセストークン「生成する」 | **押さない**(OAuth 1.0a 用。今の権限「読む」で生成しても投稿できない) |
| OAuth 2.0 キー › ユーザー認証設定「セットアップ」 | **これだけ押す** → 4.2 の「認証設定」画面へ |

### 4.2 「認証設定」画面の入力値(上から順に)
| 項目 | 選ぶ・入れる値 | 理由 |
|---|---|---|
| アプリの権限(必須) | **「読み取りと書き込み」**(現在は「読む」が選ばれている→変更する) | 投稿には write が要る。DM は不要なので 3 つ目は選ばない |
| Request email from users | **OFF のまま** | ON にすると利用規約とプライバシーポリシーの URL が必須になる |
| アプリの種類(必須) | **「ウェブアプリ、自動化アプリまたはボット(機密クライアント)」**(現在は「ネイティブアプリ」→変更する) | 機密クライアントにすると Client Secret が発行され、5 節の token 交換で Basic 認証を使う設計に合う |
| コールバック URI / リダイレクト URL(必須) | `http://127.0.0.1:8585/callback` | 5.3 でブラウザがここへ飛ぶ。**この文字列と完全一致**が必要。保存時に http を拒否されたら `http://localhost:8585/callback` にして、5 節の `X_REDIRECT_URI` も同じ値にする |
| さらに追加する | 押さない | 1 本で足りる |
| ウェブサイト URL(必須) | `https://dm-signal.com` | 必須欄 |
| 組織名 | 空欄可(入れるなら `DM-Signal`) | 任意 |
| 組織の URL | 空欄可(入れるなら `https://dm-signal.com`) | 任意 |
| 利用規約 / プライバシーポリシー | **空欄** | Request email が OFF なら不要 |

最後に右下 **「変更を保存する」**。

### 4.3 保存直後に出る 2 値
保存すると **Client ID** と **Client Secret** が表示される(Secret はこの 1 回だけ)。
1. 両方を殿の端末のパスワードマネージャに保存する。
2. 将軍へは 5.1 の方法(WSL の `config/x_api.env` に殿が直接書く)で渡す。チャット・スクショに貼らない。
3. 画面を閉じてから Keys & Tokens に戻ると「OAuth 2.0 キー」の行に Client ID だけが見え、Secret は「再生成」でしか出ない(再生成すると旧 Secret は無効)。

### 4.4 よくある詰まり
- 「読み取りと書き込み」に変えて保存したのに投稿が 403 → 保存後に **5 節の認可をやり直す**(権限変更前に発行した token は read のまま)。
- コールバックで「無効な URL」→ 末尾のスラッシュ有無まで 5 節の値と同一にする。`http://127.0.0.1:8585/callback` が通らなければ `http://localhost:8585/callback`。
- プロジェクトアクセスが「Pay Per Use」と出ているのが正常。2 節のクレジット残高が 0 だと投稿時に 402/429。

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
X_SCOPES=tweet.read tweet.write users.read media.write offline.access
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

## 6b. XDK(公式 SDK)は必須(殿裁定 15:55『media 添付やるだろ、画像とか。XDK インストール必須』)

画像付き投稿(設計書 §7 の「体験 1 枚」「1 枚比較」)は v2 の chunked media upload(INIT→APPEND→FINALIZE→STATUS の 4 呼出し、画像 5 MB 上限、docs.x.com 15:57 確認)が要るため、curl 直叩きでは手順が増える。**cmd_4472 の CLI は XDK(公式 Python SDK)を標準にする**。

```bash
# 将軍または忍者(worktree の venv で)
pip install xdk
```

```python
from xdk.oauth2_auth import OAuth2PKCEAuth
from xdk import Client

auth = OAuth2PKCEAuth(client_id=CLIENT_ID, redirect_uri="http://127.0.0.1:8585/callback",
                      scope="tweet.read tweet.write users.read media.write offline.access")
print(auth.get_authorization_url())                       # 5.2 の代わり(URL を殿へ)
tokens = auth.fetch_token(authorization_response=callback_url)   # 5.4 の代わり(殿から受けた URL)
client = Client(token=tokens)                             # token 辞書を渡すと自動 refresh

# 画像付き投稿: MediaClient は initialize_upload / append_upload / finalize_upload(chunked)と
# 単発の upload を持つ。返る media_id を posts.create の media.media_ids に渡す
media_id = client.media.upload(...)                       # 画像(PNG/JPG、5 MB 以下)
client.posts.create(post_data={"text": "...", "media": {"media_ids": [media_id]}})
```

- scope に **`media.write`** を含める(4.2 の認証設定で scope 一覧が出る場合はチェック、出ない場合は 5.2 の URL の scope で指定)。含めずに発行した token では upload が 403 になる→再認可。
- token の保管先は `config/x_api.env` のまま(tokens 辞書を JSON で `X_TOKEN_JSON=` に入れるか、access/refresh を分けて入れる。cmd_4472 の実装で 1 つに決める)。
- 画像は cmd_4472 の S3(下書き)で生成せず、S1 台帳の `media/` に置いた既存 PNG(体験 1 枚=Basic 画面のスクショ、1 枚比較=Basic/safe/入門の表)だけを添付する。保有・ticker が写る画像は gate 規則 1 の対象(画像内文字の検査は P2)。

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

## v1.3 (2026-09-03 16:02)

AsIs 注釈: 殿裁定 15:55『media 添付やるだろ、XDK 必須』→§6b を XDK 必須+画像 upload(v2 chunked、5 MB)に置換、scope に media.write を追加。

## v1.2 (2026-09-03 15:58)

AsIs 注釈: 殿スクショ 15:53(Keys & Tokens、認証設定)を受け、§4 を画面の日本語文言と具体値に置換。

## v1.1 (2026-09-03 15:45)

AsIs 注釈: v1.0(15:35)は developer.x.com と Free tier を前提に書いた。ToBe 注釈: v1.1 は docs.x.com(pricing/getting-access/xdks)を 15:40 に確認し console.x.com・従量課金・XDK に揃えた。
