<!-- gist-master: 9559feb8b3dfebda5183d792c7edbade cloudflare_dm-signal_geo_language_runbook_20260831.md -->
# Cloudflare 手順 — dm-signal.com 地域別言語優先(日本→/ja/、その他→EN)+API トークン再発行 — 2026-08-31 01:55(**3 Step 完了 02:13**)

> 殿下問 01:44『日本からのアクセスは日本語表示優先、日本以外は英語優先にできるか？』→将軍推薦=Cloudflare Redirect Rule(コード変更 0・可逆)→殿 01:46『よい』。
> 一次(01:50 殿スクショ): DNS は `dm-signal.com`/`www` とも CNAME→`dm-signal-lp.onrender.com`、**プロキシ=DNS のみ(グレー雲)**。SSL/TLS=Full(08-30 19:54)。保管トークン(`.env.cloudflare`)は rotate 後で **Invalid API Token**、zone_id は仮値。
> 前提: EN=`https://dm-signal.com/`、JA=`https://dm-signal.com/ja/`(hreflang 3 本・言語切替リンクは LP 側に既存)。

## 全体像(3 Step、殿 6 分。各 Step 後に将軍が curl で到達確認)
| Step | 誰 | 何 | 可逆性 |
|---|---|---|---|
| 1 | 殿 | DNS 2 行をプロキシ済み(オレンジ雲)へ | 雲をグレーに戻せば即復旧 |
| 2 | 殿 | Redirect Rule `jp-to-ja` を 1 本作成 | ルール削除/無効化で復旧 |
| 3 | 殿 | API トークン再発行(Redirect 権限付き)→将軍へ | トークン失効で復旧。以後の Cloudflare 変更は将軍が API で実施 |

---

## Step 1 — DNS をプロキシ済みにする(1 分)
1. Cloudflare → `dm-signal.com` → 左メニュー **DNS → レコード**。
2. `dm-signal.com`(CNAME → dm-signal-lp.onrender.com)の行の右端 **編集** → **プロキシ ステータス** のトグルを ON(**プロキシ済み**・オレンジ雲)→ **保存**。
3. `www.dm-signal.com` も同様に **プロキシ済み** → 保存。
4. `TXT google-site-verification` は触らない。
- **なぜ**: Redirect Rule は Cloudflare を経由する通信にしか効かない。DNS のみ(グレー)だと Render へ直結してルールが動かない。
- **前提 OK**: SSL/TLS=Full 設定済(Cloudflare→Render 間を暗号化)、Render の証明書は発行済(https で live)。Render 公式も Cloudflare プロキシ+Full を許容。
- 完了条件(将軍が確認): `curl -sI https://dm-signal.com/` と `/ja/` が 200 ∧ 応答ヘッダに `server: cloudflare` ∧ `cf-ray` あり。
- 崩れた時: 2 行の雲をグレー(DNS のみ)へ戻す(反映 1-2 分)。

## Step 2 — Redirect Rule を作る(2 分)
1. 左メニュー **ルール(Rules) → リダイレクト ルール(Redirect Rules)** → **ルールを作成(Create rule)**。
2. **ルール名**: `jp-to-ja`
3. **受信リクエストが一致する場合**: **カスタム フィルター式(Custom filter expression)** を選び、**式の編集(Edit expression)** に下を貼る:
   ```
   (http.host eq "dm-signal.com" and http.request.uri.path eq "/" and ip.src.country eq "JP")
   ```
   - `http.request.uri.path eq "/"` = トップだけ。`/ja/` や `/faq` 等の直接アクセス・EN を選び直した人は対象外。
4. **次に(Then)**: タイプ **静的(Static)** / **URL** = `https://dm-signal.com/ja/` / **ステータス コード** = **302** / **クエリ文字列を保持(Preserve query string)** = ON(広告の UTM を残す)。
5. **デプロイ(Deploy)**。
- **なぜ 302**: 301 はブラウザに永久記憶され、EN に切り替えた後も JP から `/` を開くたび再び `/ja/` へ飛ぶが、これは 302 でも同じ挙動(毎回判定)。301 は検索エンジンが `/` の正規性を `/ja/` に移す恐れがあるため 302。
- **SEO**: Googlebot は主に US からなので `/` は EN のまま index。`/ja/` は hreflang で日本語版として既に宣言済。
- 完了条件: (a) 殿の日本回線で `https://dm-signal.com/` を開くと `/ja/` に着地 (b) 将軍の curl(海外扱いにならないため国判定は検証不能)で `/` が **200・EN のまま**、`/ja/` が 200。
- **確認のコツ**: 殿のブラウザで `/`→`/ja/` に飛んだ後、LP 上部の言語切替で EN を選ぶと `/` が EN で表示される(パスが `/` でも同じ 302 が再度効く点に注意 — EN を固定したい JP ユーザー向けには次段で cookie 例外を検討。今は最小構成)。
- 崩れた時: 同画面でルールを **無効化** or 削除。

## Step 3 — API トークン再発行(3 分。以後の Cloudflare 変更を将軍が API で行うため)
1. 右上アイコン → **マイ プロファイル → API トークン → トークンを作成**。
2. テンプレート **「ゾーン DNS を編集(Edit zone DNS)」** を選択。
3. **権限(Permissions)** に以下を追加(＋ 権限を追加):
   - `Zone` / `Zone Settings` / `Edit`(SSL モード等)
   - `Zone` / `Single Redirect` / `Edit`(Redirect Rule。表示名は「Single Redirect」または「Dynamic Redirect」)
   - (既定で入っている) `Zone` / `DNS` / `Edit`
4. **ゾーン リソース**: **含める / 特定のゾーン / dm-signal.com** のみ。
5. **概要に進む → トークンを作成** → 表示されたトークン文字列を将軍へ(1 回しか表示されない)。
6. 将軍側: `multi-agent-shogun/.env.cloudflare`(gitignore・chmod 600)の `CLOUDFLARE_LP_TOKEN` と `CLOUDFLARE_LP_ZONE_ID`(ゾーン概要ページ右下の **ゾーン ID**、32 桁)を更新し、`/user/tokens/verify`=active と `zones?name=dm-signal.com` の一致で受領確認。
- 旧トークン(`cfut…`、Invalid)は **API トークン一覧で削除**してよい。

## Step 4(任意・後日) — メール関連の推奨事項
- DNS 画面の推奨「メールが @dm-signal.com に届かず、なりすましの可能性」は LP ドメインでメールを使わないなら放置で実害なし。なりすまし防止だけ欲しければ TXT 2 行(`v=spf1 -all`、`_dmarc` に `v=DMARC1; p=reject`)。将軍 cmd で対応可。

## 完了の定義(二値)
- [x] Step 1(02:13 API 実測): CNAME 2 行 proxied=True、`server: cloudflare`・`cf-ray …-NRT`、`/ja/` 200
- [x] Step 2(02:13 API 実測): ruleset に 1 rule enabled、式一致、Static → https://dm-signal.com/ja/ 302。将軍 WSL(日本回線)の curl で `/`→302 `location: /ja/`(=JP 判定が効いている証跡)。EN 側は `/index.html` で 200(パス `/` のみ対象)
- [x] Step 3(02:12): 殿からトークン+ゾーン ID 受領→`.env.cloudflare` 更新(chmod 600・gitignore)、tokens/verify=active、zones/{id}=dm-signal.com active

origin: `[[殿下問_地域別言語優先_20260831_0144]] -> [[Cloudflare_Redirect_Rule_JP→ja]] -> [[DNSのみ→プロキシ済み]] -> [[トークンrotate未反映_Invalid_API_Token]]`
