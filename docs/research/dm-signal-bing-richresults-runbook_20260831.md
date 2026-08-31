<!-- gist-master: e96628e3270d371ca6a87c214dea978e dm-signal-bing-richresults-runbook_20260831.md -->
# Bing Webmaster 登録 + Rich Results Test — 殿用ステップ・バイ・ステップ runbook

> 作成: 将軍 2026-08-31 15:12。対象=dm-signal.com。前提=Google Search Console 登録済み(2026-08-30 20:01 殿がCloudflare自動確認で完了)、sitemap.xml 200 application/xml・robots.txt に Sitemap 行あり(15:10 将軍実測)。
> 所要: Bing=約3分、Rich Results Test=約2分。どちらも殿のブラウザ画面のみで完結し、コード変更なし・完全に可逆。

## §1 Bing Webmaster 登録(Google Search Console からインポート=最短経路)

| Step | 操作 | 完了の目印 |
|---|---|---|
| 1 | https://www.bing.com/webmasters を開き、**Microsoftアカウント**でサインイン(なければ「作成」。Googleアカウントでのサインインも可) | ダッシュボードが出る |
| 2 | 初回画面の「**Google Search Console からインポート**」(右側の大きいボタン)を選ぶ | Googleのアカウント選択画面へ遷移 |
| 3 | Search Console を登録した **Google アカウント**(dm-signal.com を確認したもの)を選び、アクセスを「許可」 | Console のプロパティ一覧が表示される |
| 4 | 一覧から `dm-signal.com` にチェック → 「インポート」 | 「サイトが追加されました」表示。**所有権確認・sitemap も自動で引き継がれる**(TXT作業不要) |
| 5 | 左メニュー「**サイトマップ**」を開き、`https://dm-signal.com/sitemap.xml` が「成功」になっているか確認。無ければ「サイトマップの送信」に同URLを貼って送信 | ステータス=成功、検出URL 2(cmd_4436 live 後は4以上) |
| 6 | (任意)「URL検査」で `https://dm-signal.com/` を検査 →「インデックス登録をリクエスト」 | 「送信されました」 |

- なぜやるか: Bing は Google の約1/10 の流量だが、**ChatGPT/Copilot 系の回答エンジンが Bing 索引を参照する**ため、AI 経由の流入面で効く(Agent Readiness と同じ方向)。
- 失敗時: Step 2 のインポートボタンが出ない場合は「サイトを手動で追加」→ URL に `https://dm-signal.com` → 確認方法で「**CNAME/DNS**」を選ばず「**Google Search Console**」タブを選べば同じ流れに入る。

## §2 Rich Results Test(JSON-LD 3型の valid 確認)

| Step | 操作 | 完了の目印 |
|---|---|---|
| 1 | https://search.google.com/test/rich-results を開く(ログイン不要) | 入力欄が出る |
| 2 | URL欄に `https://dm-signal.com/` を貼り「**URLをテスト**」 | 30〜60秒でテスト完了 |
| 3 | 結果画面で「**検出された構造化データ**」を見る | **「FAQ」が 1 件 valid** で出れば合格(FAQPage が rich result 対象。Organization/WebSite は対象外型なので「検出項目なし」でも異常ではない) |
| 4 | エラー/警告が出た場合はスクショを将軍へ | 将軍が JSON-LD(structured-data.tsx)を修正 cmd 化 |
| 5 | 同様に `https://dm-signal.com/ja/` もテスト | JA 側も FAQ valid |

- 補足: Organization・WebSite 型は Rich Results Test の「リッチリザルト対象」に出ないのが正常(Google の対象型リストに含まれないため)。**構文検証まで見たい場合**は https://validator.schema.org/ に同 URL を貼れば 3 型全てのパース結果が出る(エラー0が合格)。
- 頻度: 一度 valid を確認すれば再実行不要。FAQ 文言を変えた deploy 後に 1 回だけ再テスト。

## §3 終わったら

- Bing: ダッシュボードに `dm-signal.com` が見えている(数値の初期表示は24〜48h後)
- Rich Results: EN/JA とも FAQ valid
- 以上 2 点を将軍へ一言(「bing済」「rich済」で十分)。SEO 案 v3 §6 の残 P0 を [x] 化して週報の計測土台が完成する。

origin: `[[SEO案v3_20260831_1452]] -> [[殿指示_2と3のrunbook_20260831_1511]] -> [[bing_richresults_runbook]]`
