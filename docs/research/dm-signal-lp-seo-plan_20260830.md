<!-- gist-master: 5edb5f6d5fab4e9578bc35fbfacf95b7 dm-signal-lp-seo-plan_20260830.md -->
# DM-Signal LP(dm-signal.com) SEO 案 v3 — 2026-08-31 14:52(v2 08-30 22:05 / v1 19:55)

> 作成: 将軍。殿指示 19:51『seo 案をまとめて gist に共有して』。前提=殿裁定 16:42『別サイト』、17:14 `.com`、17:59 SEO 案(JSON-LD/noindex/Search Console/月次シグナル頁)。
> 本文は結論+根拠。殿の裁定が要る箇所は **【裁定】** で明示。裁定後に cmd 化する(起票は裁定後、LS115)。
> **v3(08-31 14:52 本番 curl 再計測)**: v2 残バグ `og:image` 404 は **解消**(cmd_4426=静的 PNG `og-en.png`/`og-ja.png` 各 200 image/png)。FAQ EN=4427 済。docs/faq canonical=**殿裁定 14:36 で app 側維持に確定**(P1-2 裁定済)。殿裁定 14:32『LP に集中』体制下で走行=cmd_4432(列整理)→4433(hero static chart)→4434(FoF 訴求)。**新規未達の発見=app 側 `/free` が 200 だが noindex 0 件**(§3 の禁則が未実装)。残 P0=sitemap 送信・索引確認・Bing・Rich Results Test(いずれも画面 1 分級)。

## §0 AsIs(2026-08-30 22:02 本番 curl 一次で再計測。v1=19:52)

| 項目 | EN `/` | JA `/ja` | 判定 |
|---|---|---|---|
| title | `Dual Momentum signals & track record \| DM-Signal` | `デュアルモメンタムのシグナルと実績 \| DM-Signal` | ○ **P0-5 live**(4421。v1 案どおり) |
| meta description | `Explore Dual Momentum signals and a transparent track record since inception…` | あり | ○(検索語含有、4421) |
| canonical | `https://dm-signal.com/` | あり | ○(`.jp` 0 件、19:34 修正済) |
| hreflang | 3 件(en/ja/x-default) | 3 件 | ○(20:06 再確認: `hrefLang` camelCase で grep 漏れ。P0-2 は不要) |
| OG / Twitter card | og 10 件+twitter 7 件(`og:locale=en_US`、`twitter:card=summary_large_image`) | 同 | ○ **P0-4 live**(v3 14:50 再計測: cmd_4426 静的 PNG 化で `og-en.png`/`og-ja.png` 各 200 `image/png`。旧 `/opengraph-image.png` は 404 のままだが参照は新パスへ切替済み) |
| JSON-LD | `Organization`・`WebSite`・`FAQPage`(Q&A 3 組) | 同 3 型 | ○ **P0-3 live**(4421、`lp/components/structured-data.tsx`)。Rich Results Test は未実行 |
| sitemap.xml / robots.txt | 200(`/`, `/ja/` の 2 URL) | — | ○(lastmod 無し) |
| Search Console | **登録済**(20:01 殿が Cloudflare 自動確認で所有権確認) | — | ○ 残=sitemap 送信・索引 2/2 の確認(§2.1 Step 6・8) |
| app 側 `/login` | `noindex` 1(4420 live) | — | ○(LP が評価を受ける側) |
| 配信 | Cloudflare proxy、HTML `s-maxage=300` | — | ○(速い。更新は 5 分遅延) |
| 計測 | `lp_view` / `lp_cta_click` を backend へ POST(4419 live、201) | — | ○(区間計測の土台) |
| 外部導線 | href: note membership 6・`/login` 2・`/faq` 1(誤リンク修正 19:34 live) | 同 | ○ |
| Free CTA(4424) | `/free?from=lp` 導線は **未 live**(f9011787 は origin/main 未着) | — | — SEO 上は app 側 `/free` を noindex にする(§3 追記) |

## §1 方針(結論 3 行)

1. **入口は 1 つ(dm-signal.com)、評価も 1 つに集める。** app(`/login` 等)は noindex 維持、note 記事・X から LP へ被リンク。
2. **検索意図は「デュアルモメンタム シグナル / dual momentum signals」**。競合(個人ブログ・海外 ETF 系)に対し、**毎月更新される実績数値**(公開集計 EP)が唯一の差別化=鮮度で勝つ。
3. **計測なき施策は打たない。** Search Console(表示/クリック/掲載順位)+ `lp_view→lp_cta_click→login_view→ok` の区間表を週報に載せ、効いた区間だけ伸ばす(§2.5 の教え=経路修正)。

## §2 施策(優先度=ROI 順。P0 は今週、P1 は 9 月、P2 は任意)

### P0 — 土台(各 10 分以内、可逆)
| # | 施策 | 中身 | 二値 AC | 担当 |
|---|---|---|---|---|
| P0-1 | **Search Console 登録+sitemap 送信** | ドメインプロパティ(Cloudflare 自動確認) | Console に `dm-signal.com` 所有確認済 ∧ sitemap 取得成功 | **所有確認=済(20:01 殿)**。残=sitemap 送信(殿の画面 1 分)・索引 2/2 |
| P0-2 | hreflang 対称化 | `/` と `/ja` の双方に `en`・`ja`・`x-default` の 3 本 | 両ページ hreflang 3 件 | **不要(既に 3 本、20:06 確認)** |
| P0-3 | JSON-LD | `Organization`(+sameAs: note)、`WebSite`、FAQ 節に `FAQPage` | Rich Results Test で 3 型 valid | **live(4421、21:35 CLEAR)**。残=Rich Results Test 1 回(将軍) |
| P0-4 | OG/Twitter 完備 | `og:image`(1200×630、EN/JA)、`og:locale`、`twitter:card=summary_large_image` | 両ページ og 6 件以上 ∧ 画像 200 | meta=live(4421)、**画像 404=未達**→hotfix(§6)。画像は既定案(ブランド+タイトルのみ、数値なし)で実装済 |
| P0-5 | title/description に検索語 | EN `Dual Momentum signals & track record \| DM-Signal`、JA `デュアルモメンタムのシグナルと実績 \| DM-Signal` | grep 各 1 | **live(4421、既定案の文言)** |
| P0-6 | Bing Webmaster | Console からインポート(5 分) | 登録済 | 未(殿の画面。Console 登録済なので今できる) |

### P1 — 鮮度と面積(9 月)
| # | 施策 | 中身 | 効果の根拠 |
|---|---|---|---|
| P1-1 | **月次シグナル頁の自動生成** `/signals/2026-08`(EN/JA) | 公開集計 EP から「今月の Basic-DM 保有・プラン平均/ベスト・SPY/TQQQ 比較」を静的生成。sitemap に自動追加、lastmod 付与 | 毎月 2 URL 増える=クロール頻度と索引面積。数値は既存 §2.3 契約のまま(個別 PF 名・秘密数値は出さない) |
| P1-2 | docs/faq を LP 配下に鏡像 or canonical 統一 | 現状 app 側(`/docs` `/faq` 公開 200)。LP から内部リンク済。**【裁定】LP 配下へ移すか、app 側に canonical を残すか** | 説明ページの評価を LP ドメインに集約 |
| P1-3 | note 記事→LP 相互リンク | 既存 note 記事(tokyojibika)末尾に LP、LP フッタに note(済) | 被リンクの最短経路 |
| P1-4 | 用語ページ 3 本(EN/JA) | デュアルモメンタム / 相対・絶対モメンタム / ドローダウン(FAQ の拡張) | ロングテール |

### P2 — 技術(任意)
- Cloudflare: HTML の cache rule(`/` `/ja` は Edge TTL 60s or bypass)、`Cache-Control` は Render 側 header で調整。
- 画像 WebP・`loading=lazy`(表は文字なので現状影響小)。Core Web Vitals は静的サイトのため合格見込み(Console の CWV レポートで確認)。
- 404 頁・`/ja/` 末尾スラッシュ統一(sitemap は `/ja/`、リンクは `/ja`。どちらかに 301)。

## §2.1 P0-1 Search Console 登録 — ステップ・バイ・ステップ

> 役割: **殿=Step 1・2・5(Google 画面、計 5 分)**、将軍=Step 3・4・6(Cloudflare API と確認)。殿の操作は「プロパティ追加→TXT 文字列を将軍へ→確認ボタン」の 3 回だけ。

| Step | 誰 | 操作 | 所要 | 完了の二値 |
|---|---|---|---|---|
| 0 前提 | 将軍 | Cloudflare の新トークン(rotate 後)が `.env.cloudflare` に入り `GET /zones/{id}` が success | 1 分 | `tokens/verify` = active |
| 1 プロパティ追加 | **殿** | https://search.google.com/search-console → 左上「プロパティを追加」→ **左の「ドメイン」**(URL プレフィックスではない)に `dm-signal.com` → 続行 | 1 分 | 「DNS レコードでのドメイン所有権の確認」画面が出る |
| 2 TXT を将軍へ | **殿** | 画面の `google-site-verification=…` の文字列をコピーし、将軍へそのまま貼る(トークンではないので会話に貼って可) | 1 分 | 将軍が受領 |
| 3 TXT 追加 | 将軍 | Cloudflare API: `POST /zones/{zid}/dns_records {"type":"TXT","name":"dm-signal.com","content":"google-site-verification=…","ttl":1}`。既存の CNAME @ は触らない(TXT は apex に共存可) | 1 分 | API success=true ∧ `dig TXT dm-signal.com`(または `nslookup -type=TXT`)に値が出る |
| 4 伝播確認 | 将軍 | 公開リゾルバ 1.1.1.1 / 8.8.8.8 の両方で TXT が返るまで待つ(通常 1〜5 分) | 〜5 分 | 両リゾルバで一致 |
| 5 確認ボタン | **殿** | Step 1 の画面に戻り「確認」 | 1 分 | 「所有権を確認しました」。失敗なら Step 4 を再確認して再押下(TXT は消さない=以後の再確認にも使う) |
| 6 sitemap 送信 | 将軍(殿の画面でも可) | 左メニュー「サイトマップ」→ `https://dm-signal.com/sitemap.xml` を送信 | 1 分 | ステータス「成功しました」・検出 URL 2(→P1-1 で増加) |
| 7 初期設定 | 殿 | 「設定→ユーザーと権限」で将軍用に **フル権限ユーザー追加は不要**(週報は API でなく画面値を殿が転記 or 将軍が Console API 用 OAuth を後日) / 「国際ターゲティング」は hreflang 対称化(P0-2)後に自動 | 2 分 | — |
| 8 初回データ | 将軍 | 24〜48h 後に「ページのインデックス登録」で `/` `/ja/` が「登録済み」。未登録なら「URL 検査→インデックス登録をリクエスト」を 2 URL に手動実行 | 翌日 | 登録 2/2 |

- **実績(2026-08-30 20:01)**: 殿が Search Console の「DNS プロバイダで自動確認(Cloudflare)」を使い、Step 1〜5 を一括完了(Google が Cloudflare に TXT を自動追加・自動確認)。将軍の TXT 手作業(Step 3-4)は不要になった。残=Step 6 sitemap 送信・Step 8 索引確認。
- 補足 1: **「ドメイン」プロパティ**を選ぶ理由=`www`/`http`/`https`/サブドメイン(将来の `app.` `signals.`)を 1 つで束ねられる。URL プレフィックスだと LP・app で別プロパティになる。
- 補足 2: TXT 方式を選ぶ理由=Cloudflare が DNS 権威なので将軍が API で 1 手、LP の HTML(Render 静的出力)を触らずに済む。HTML タグ方式は deploy が要る。
- 補足 3: Bing Webmaster(P0-6)は Console 登録後に「Google Search Console からインポート」で 2 分。
- 補足 4: Console のデータは将軍が読めないため、週報の §4 指標は **殿が数値 3 つ(表示/クリック/平均掲載順位)を貼る** か、後日 Search Console API(OAuth、殿の 1 回承認)を将軍に許可するかの二択。既定=当面は殿が貼る。

## §3 やらないこと(禁則)
- 価格・無料期間の文言(`first month free`/`初月無料`/`free trial`)は書かない(殿裁定 13:41、設計書 v2 §4)。
- 個別 PF 名・Secret の数値を索引可能な頁に出さない(§2.3 契約)。
- 4〜5 桁 % の煽り見出し(信憑性を損なう。§6 未決 3 と同じ)。
- キーワード詰め込み・購入リンク。
- app 側の `/free`(4423/4424 の Google 登録入口)は `/login` と同じく `noindex`(入口は LP に集約、§1-1)。live 後に `curl /free | grep robots` で 1 件を確認する。

## §4 計測(週報に固定)
| 指標 | 出所 | 目標(初月) |
|---|---|---|
| 表示回数 / クリック / 平均掲載順位 | Search Console | 索引 2→6 URL、`dual momentum signals` 上位 30 位以内 |
| `lp_view→lp_cta_click` 率 | showcase_events(4419) | 5% |
| `lp_cta_click→login_view→ok` 率 | 同上 | 区間ごとに数え、最も落ちる区間を先に直す |

## §5 殿の裁定 4 点(v2: 状態)
1. Search Console の所有者=殿の Google アカウント → **決(20:01 殿が自動確認で登録)**。
2. title/description の文言 → 殿 20:04『進めてくれ』=既定案採用、**live**。
3. OG 画像に数値を載せるか → 既定案(載せない)で実装済。**画像 404 は 4426 で解消(v3 14:50 実測 200)**。殿実機の表現確認のみ残。
4. docs/faq を LP 配下へ移すか → **決(殿裁定 2026-08-31 14:36)**: 移さず app 側 canonical 維持、LP から内部リンク(knowledge:d1fb0c5aaf6d922c)。P1-2 の裁定は完了。

## §6 工程(v2: 状態)
| 手 | 内容 | 状態(v3 08-31 14:52) |
|---|---|---|
| cmd A | P0-3〜P0-5(cmd_4421、忍者 1 名) | **完了**: GATE CLEAR 21:35、DM main 71e0b94d、本番 live(§0) |
| hotfix | `og:image` 404 → 静的 PNG 化 | **完了**: cmd_4426 CLEAR。`og-en.png`/`og-ja.png` 200 `image/png`(14:50 実測) |
| FAQ EN | FAQ の EN 版 | **完了**: cmd_4427 CLEAR・live |
| LP 表示(殿裁定 14:00-14:36) | cmd_4432(Total return 削除+CAGR up to+列順)→cmd_4433(hero static chart)→cmd_4434(FoF 訴求 1 行) | **走行中**(kagemaru 実装中→直列 2 弾配備待ち)。SEO 面でも本文の検索語密度と視覚要素が向上 |
| **未達(v3 発見)** | app 側 `/free` が 200 だが **noindex 0 件**(§3 禁則の未実装)。`/login` は noindex 済 | **未起票**。次の軽量 cmd(meta robots 1 行+curl 検証)候補 |
| 将軍/殿 | Search Console sitemap 送信・索引 2/2(§2.1 Step 6・8)、P0-6 Bing、Rich Results Test | **殿確認済 08-31 16:11: Bing・Search Console 完了**(runbook gist e96628e3)。残=索引 2/2 の翌日確認・Rich Results Test |
| cmd B | P1-1 月次シグナル頁(EN/JA)+sitemap lastmod | 未起票(9 月)。P1-2 は殿裁定 14:36 で裁定済(app 側 canonical) |
| 週報 | §4 の 3 指標固定 | Console 初回データ後 |


origin: `[[殿裁定_LP別サイト_20260830_1642]] -> [[dm-signal.com_LP本番到達_20260830_1744]] -> [[SEO案_v1_20260830]]`
