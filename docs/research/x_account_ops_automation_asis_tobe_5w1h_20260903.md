<!-- gist-master: 8e1336f8b297ccd9bd5f407444844434 x_account_ops_automation_asis_tobe_5w1h_20260903.md -->
# X アカウント運用(バム @TokyoJibika)の Grok 包装→API 自動化 — AsIs / ToBe / 5W1H 設計書 v0.11(2026-09-03 17:55 覚醒更新=P1 実装現在値・§13 実装進捗台帳新設。v0.10=16:02、殿裁定 15:55: 画像添付あり→S5 は XDK 必須、scope media.write、S1 台帳に media/。v0.9=15:45、§10 訂正=X API は従量課金のみ(投稿 URL 付き $0.20)・入口 console.x.com・XDK、ランブック docs/research/x_api_registration_runbook_20260903.md。v0.8=13:00 §12 E 軸ドリーム。v0.7=12:40 §11 マニュアル v4 取込。v0.6=11:22 §10 X API と xAI API の違い+P1 手順。v0.5=11:05、§9 Grok 質問状への回答=コピペ用、殿指示 10:57。v0.4=09:55、P0 完了=cmd_4467 CLEAR 09:48: ストック台帳 50 entry・slot calendar・包装 gate 6 規則+bats 8、将軍が gate を本番 API で突合。v0.3=04:00 cmd_4463 実測 §1c。v0.2=03:35、殿回答 B-1〜B-10 を §1b/§2/§5 へ反映。v0.1=03:20、殿発案 03:13『grok によるアカウント運用は今後 API などで自動化まで持って行きたい。新しい設計書にしないか』)

## §0 一文定義
Grok 作成の「届け方マニュアル」(中身固定・包装のみ変更)を、**ストック記事→スロット→LLM 包装→品質 gate→X API 投稿→KPI 還流**の 1 本の pipeline として段階的に自動化する。戦略・検証・有料層の中身は一切変えない(マニュアル §1 Non-negotiables を pipeline の不変条件として機械化する)。

## §1 AsIs(2026-09-03 一次確認)
| 項目 | 現状 | 出典 |
|---|---|---|
| マニュアル | Grok 作成 `docs/research/bam_delivery_manual_grok_20260902.md`(433 行、§0-§14)。実測で精度を上げる質問集 `bam_delivery_manual_questions_20260902.md`(A 公開 6 問/B 本人 10 問/C 法務 5 問/D 反映先) | 殿デスクトップ 09-02 21:05/21:06、将軍複写 9198f53a0 |
| 投稿 | 殿の手動。不規則(マニュアル §2『接触回数が医師スケジュール』) | マニュアル §2 |
| Grok API | `config/xai_api.env` に XAI_API_KEY。x_search を `skills/x-research`・`skills/x-thread-fetch`・`skills/weekly-report-writer` が使用(読み専用) | skills/*/SKILL.md |
| X 投稿 API | **整備済(09-03 17:17 時点)**。`config/x_api.env`(git-ignore、600、client id/secret+access/refresh token、scope 5=tweet.read tweet.write users.read media.write offline.access、認可 16:53 受け口 `scripts/x_ops/x_oauth_listener.py`)。`scripts/x_ops/x_post.sh`(draft/gate/approve/post 4 段、影丸 fd6b8c633)+`x_post_gate.sh`(規則 1-6+blocklist fail-close 2fa437a9c)+`x_post_ledger_lookup.py`。投稿実績 **0**(draft A は gate PASS だが手直し版のため承認保留、§13) | ls scripts/x_ops、/tmp/x_oauth_listener.log 16:53 token ok |
| note | `skills/note-writer`(CDP 経由の下書き作成、ProseMirror 制約)、`/prose-polish` | skills/note-writer/SKILL.md、CLAUDE.md |
| 素材 | 完全ガイド(note n171daa7f92a1)、How to マガジン(mb4377418b422)、dm-signal.com(LP EN/JA、月次頁 /signals/YYYY-MM/、Basic 無料)、堅牢性レポート、showcase API(hero/series/plans) | マニュアル §1、dm-signal-lp-seo-plan_20260830.md v5 |
| KPI | 未計測(X 側は pay-per-usage の owned reads $0.001 で取得可、§10)。Search Console/Bing は SEO lane で登録済(T201)。X analytics 未接続 | seo-plan v5 |
| 制約 | 医師の可用時間(週 90 分未満想定、B-1 未回答)、助言規制(マニュアル §10)、有料中身の非公開 | マニュアル §5 §10 |

## §1b 殿回答(2026-09-03 03:31、原文要旨。質問集 §B の 10 問)
| # | 回答 | 設計への反映 |
|---|---|---|
| B-1 可用時間 | 『自動化するから関係ない』 | §5 週次枠の上限を人手ではなく API cap で決める(P2 の週 3 投稿 cap は維持、上限は殿裁定で可変) |
| B-2 読者構成 | 不明。医師 40% 程度と推定、DM 経験者は少ない | 第一文は『忙しい専門職』寄りだが、初心者比率が高い前提で S3 の第一文に『相対+絶対の 2 部品』を必ず入れる(マニュアル §4) |
| B-3 有料化前の記事 | note の記事(特定 3 本は不明) | cmd_4463 A-4(再掲比)と S6 KPI(note ビュー→dm-signal 到達)で実測 |
| B-4 初回質問 | 不明 | cmd_4463 では公開リプから推定、以後 S6 で収集(質問集『いちばん効く 3 問』の 3) |
| B-5 Basic 到達 | 『今後調べたい』 | S6 の必須指標に昇格: dm-signal showcase_events(step/ua_class/lang)を月次集計する cmd を P1 で出す |
| **B-6 数字ホワイトリスト** | **保有シグナル・構成 ticker など模倣可能な情報は排除。metrics は全 PF 公開可。無料公開の Basic DualMomentum だけはポジションまで公開可** | **S4 gate の核心規則(§2 不変条件 (3) を改定)**: 出してよい=全 PF の CAGR/MaxDD/Sharpe/期間/ベンチ+Basic の保有。出してはいけない=Basic 以外の保有シグナル・構成 ticker・FoF の重み。blocklist は dm-signal 有料 PF 名ではなく『holding/ticker/weight』の値そのもの |
| B-7 倍率・劇薬・戦国 | どちらでもよい | マニュアル既定(A 面第一文には出さない、B 面可)を採用 |
| B-8 メンバーシップ | note のメンバーシップ | 公開文面は note の規約に従う。§10 法務は note メンバーシップ前提で書く |
| B-9 二次利用 | 保有シグナル・構成 ticker 以外は可 | 要約スレッド・図の転載・引用 RT・切り抜きは可。S4 の同じ blocklist で二次利用素材も検査 |
| B-10 成功指標 | エンゲージメント | §11 KPI の主指標=エンゲージメント(表示・いいね・リポスト・リンククリック)。マニュアルの『フォロワーを捨てる』は維持しつつ、理解到達 KPI は副指標 |

## §1c 公開情報の実測(cmd_4463 飛猿、観測日 2026-09-02、正本 `docs/research/x_account_asis_measurement_20260903.md` 795dbd37a。不明 19 項目は API/表示の構造的制約で、推測は 0)
| 項目 | 実測 | 設計への反映 |
|---|---|---|
| X @TokyoJibika | フォロワー 4,434。直近 30 日の投稿数・表示・いいね中央値は x_search では取れない(本人 Analytics のみ) | S6 KPI は X API(Basic 以上)か本人 Analytics の CSV 取込が必要→D2 の判断材料 |
| note | How to マガジン 49 本、完全ガイド スキ 53(公開 2025-09-25)。フォロワー数・コメント数は表示なし | S1 ストック台帳の初期母集団=49 本+完全ガイド |
| メンバーシップ | note: ベーシック ¥1,000/月・スタンダード ¥8,000/月。dm-signal 側は Basic/Standard/Premium(招待)/Secret の 4 段。人数は非公開 | 公開文面は note の 2 プラン名で統一(§10) |
| dm-signal.com 無料範囲 | Basic-DualMomentum は sign-in 不要で CAGR/Sharpe/MDD と 2003-09〜の長期チャートまで見える | 殿 B-6 と一致=Basic は保有まで公開可 |
| 入口(A-2) | note 2 種+旧ブログ 2 種(livedoor/hatena)+dm-signal の 5 種が並存し初見が迷う | §3 の『入口 3 つ固定』は実測で裏付け。旧ブログ 2 種は目次上位を完全ガイドへ揃える(マニュアル §9) |
| 検索(A-3) | 『デュアルモメンタム』上位は書籍販売・解説ブログ・動画が占め、完全ガイドは定義系の意図で勝ち、ツール/実績系で負ける(詳細は正本 §A3) | SEO lane(T201)の狙い語=定義系。実績系は LP 月次頁で取る |
| 再掲比(A-4) | 06-30〜09-02 でユニーク記事 18 本中、2 回以上貼られたのは 3 本(How to マガジン/『1 年続けられない人は向いてない』/アパート記事)、1 回のみ 15 本=約 1:5 | マニュアル §2『反復がない』を数値で確認。S2 の枠 A(教材再掲)の初期対象=完全ガイド+How to+堅牢性記事 |
| 類似アカウント(A-5) | 医師×投資 5 例中 4 例は間口の広いテーマ(インデックス/日本株)で医師以外も取込 | DM 特化は市場が狭い=フォロワーでなくエンゲージメント KPI(殿 B-10)が妥当 |
| 海外ツール(A-6) | Allocate Smartly/Optimal Momentum/PV の無料説明は『定義→ルール→バックテスト条件→限界→免責』の順 | S3 の包装順(マニュアル §4)と同型。見出し順をそのまま S3 のテンプレに使う |

## §2 ToBe(pipeline 6 段。各段の入出力を固定し、段ごとに手動→半自動→自動へ)
```
[S1 ストック台帳] 無料記事・図・数字ホワイトリスト(YAML)
   ↓
[S2 スロット計画] 週次 4 スロット(v4: A 教材 4 週ローテ / B 検証・比較 / C 体験=登録誘導・毎回 / D 境界=隔週)+月次 E ドリーム(§12、分身と四つ目は別投稿) → 予約 calendar(YAML)。週 1 は必ず登録誘導
   ↓
[S3 LLM 包装] マニュアル v4 §11「他 LLM 用プロンプト」をシステム文に固定して Grok(または Claude)に生成。構成=結論→2 部品→セット数字→体験(登録)→境界→免責。入力=記事 URL+スロット+切り口+使ってよい数字
   ↓
[S4 品質 gate] 規則 1-6(実装済 2fa437a9c)+v4 追加規則 7-9(up to/×N/Secret 行の主語化禁止・数字セット完全性・記事 17.2% と サイト 16.1% の混在禁止)。FAIL=投稿しない(fail-close)
   ↓
[S5 投稿] X API v2 POST /2/tweets(スレッドは reply chain)。予約は cron。P1 までは『下書き→殿承認→投稿』、P2 で自動
   ↓
[S6 KPI 還流] X API の tweet metrics+note ビュー+LP(Search Console)を週次で台帳へ。赤信号(§11)を検知したら S2 の切り口を変える
```
不変条件(機械化する Non-negotiables): (1) 戦略・パラメータ・新シグナルを生成しない(S3 のシステム文+S4 の diff 検査=素材にない数字を出さない) (2) 公開 URL は 3 つ固定 (3) Basic DualMomentum 以外の保有シグナル・構成 ticker・FoF 重みを出さない(殿 B-6。S4 は showcase API の holding/ticker/weight 値を blocklist に使う。metrics は全 PF 可) (4) 免責 1 行必須 (5) 数字は期間/CAGR/MaxDD/ベンチのセットのみ(単独倍率 regex で FAIL)。

## §3 段階(Phase)と可逆性
| Phase | 内容 | 自動化度 | 可逆 | 完了条件(二値) |
|---|---|---|---|---|
| P0 | ✅ **完了 09-03 09:48(cmd_4467 飛猿、ce1ca2cb1)**: `skills/x-post-pipeline/stock_ledger.yaml`(50 entry=How to 49+完全ガイド、記事本文にある数字セットのみ)、`slot_calendar.yaml`(4 週×枠 A/B/C+月次 D)、`SKILL.md`(28 行)、`scripts/x_ops/x_post_gate.sh`(6 規則: Basic 以外の保有/ticker blocklist を showcase API から生成、単独倍率、URL 3 種、免責、禁止語、第一文の内部用語)+`tests/unit/test_x_post_gate.bats` 8 本。将軍突合: 包装ルール通りの下書き rc=0、禁止語/内部用語/単独倍率は FAIL。**穴(09:58 発見)**: 規則 1 の blocklist を公開 showcase API から作るため非公開 PF の holding が blocklist に入らず、空なら PASS(沈黙フォールバック)→家老 hotfix: 認証付き /api/signals の全 PF holding(Basic 除外)を正本に、取得失敗は FAIL | 手動 | file 削除 | 台帳 1 file、gate PASS/FAIL 例 |
| P1 | **実装中(09-03)**: S4 gate=script 化済(P0)、S5=`x_post.sh` draft→gate→approve(殿 y→将軍が approved marker)→post(XDK、201 で posted marker+URL)。認可完了 16:53。残=生成契約 hotfix(既定 LLM を latest CLI、エラー/40 byte 未満/メタ文/280 字超は fail-close、本文 140 字+URL+固定免責)→slot A 再生成→gate PASS→ntfy→殿『y』→post 201 が cmd_4472 production_proof | 半自動 | 投稿は取消可、API key 失効で停止 | gate 偽陽性 0/12、承認→投稿 1 本が API で成功(**現在 0/1**) |
| P2 | cron で S2→S3→S4→S5 を無人実行。殿は週 15 分の KPI 確認のみ | 自動 | flag file で即停止(単一 publisher と同型) | 4 週連続で週 3 投稿・gate FAIL 0・殿介入 0 |
| P3 | S6 KPI 還流で切り口を自動選択(A の 4 切り口の rotation を metrics で重み付け) | 自動 | rotation を固定に戻す | 赤信号 0、理解到達 KPI が 4 週連続上昇 |

## §4 5W1H
- **WHY**: 良い記事が 1 回で終わり反復がない(マニュアル §2)。医師の時間では週 3 枠を手で回せない。中身は完成しているので届け方だけを機械に任せる。
- **WHAT**: §2 の 6 段 pipeline。P0-P3。
- **WHEN**: P0 は殿の B 質問回答後すぐ(数字ホワイトリスト B-6 が前提)。P1 は X API 発行後。P2 は P1 の 4 週実績後。
- **WHERE**: `multi-agent-shogun/skills/x-post-pipeline/`(新 skill)+`docs/research/x_stock_ledger.yaml`(台帳)+cron。投稿 API key は `config/x_api.env`(git-ignore)。
- **WHO**: 殿=B 質問回答・承認(P1)・KPI 確認。将軍=設計・cmd 起票。忍者=S1/S4/S5 の実装。Grok=S3 包装(x_search で反応も収集)。
- **HOW**: 単一 publisher と同じ型=flag file で ON/OFF、fail-close、1 batch 1 commit、canary は積まない(殿 09-03 01:30)。

## §5 未決事項(殿裁定が必要。返答なければ既定案)
| # | 論点 | 既定案 |
|---|---|---|
| D1 | S3 の LLM は Grok か Claude か | **確定=Claude**(x_post.sh の LLM_CMD。pinned 2.1.87 は API 400 で無効出力 15 byte→既定を latest CLI へ hotfix 中)。Grok は x_search 収集+A 面の別案生成に使う |
| D2 | X API のプラン | **確定=pay-per-usage のみ**(§10 訂正 15:45。投稿 $0.015、URL 付き $0.20、owned reads $0.001)。console.x.com でクレジット前払い。登録完了 16:53 |
| D3 | 殿承認の UI(P1) | **確定=ntfy に本文を送り殿『y』→将軍が approved marker を置く→家老 `x_post.sh post`**。手直し draft は承認対象外(家老 17:17 訂正 ntfy 済) |
| D4 | B 質問 10 問の回答 | **回答済 03:31(§1b)**。残り実測=B-3/B-4/B-5 は cmd_4463 と S6 で埋める |
| D5 | A 質問 6 問の偵察 cmd を先に出すか | 既定=出す(cmd_4463、忍者 1 名、Grok x_search+web) |
| D6 | 法務 C 5 問 | 既定=偵察 cmd に含めず、P1 前に別 cmd で一般論を集める |

## §6 リスクと検知
| リスク | 検知 | 処置 |
|---|---|---|
| LLM が新ルール・倍率を生成 | S4 の『素材にない数字』diff、regex | fail-close、下書きを捨てる |
| 有料の中身漏れ | dm-signal 有料名 blocklist | 同上 |
| 助言に見える表現 | 命令形+銘柄名の共起 regex | 同上+免責付与 |
| API 上限・失効 | HTTP 4xx | 停止 flag+ntfy |
| 殿不在時の暴走 | P2 の週 3 上限をハード cap | cap 超過は投稿しない |

## §7 最初の cmd(P0 の前)
- cmd_4463(偵察): マニュアル質問集 A-1〜A-6 を Grok x_search+web で埋め、`docs/research/x_account_asis_measurement_20260903.md` に表で残す(出典 URL+観測日、不明は不明)。
- 殿へ: B-1〜B-10(本人にしか答えられない)。特に B-6 数字ホワイトリストが S3 の入力になる。


## §9 Grok 質問状への回答(コピペ用。殿指示 09-03 10:57『答えられない質問には無理に答えなくていい』。出典=cmd_4463 実測 09-02、殿回答 09-03 03:31、ストック台帳 cmd_4467。不明は不明と書く)

```
共通前置き: 対象=バム(@TokyoJibika / note.com/tokyojibika)。中身(戦略・有料本文)は変えず届け方だけ改良する。以下は 2026-09-02〜03 の実測と本人回答。推測は書いていない。不明は不明。

## A. 公開情報(観測日 2026-09-02、出典 URL は各行)

A-1 公開指標
- X フォロワー: 4,434(https://x.com/TokyoJibika、x_user_search)
- X 直近 30 日の投稿数・表示中央値・いいね中央値: 不明(x_search は直近ヒット分のみで全数走査不可。本人 Analytics でのみ取得可)
- note フォロワー: 不明(プロフィールにフォロワー数の表示なし)
- 無料「How to デュアルモメンタム」マガジン: 49 本(https://note.com/tokyojibika/m/mb4377418b422)
- 完全ガイド(https://note.com/tokyojibika/n/n171daa7f92a1): スキ 53、公開 2025-09-25、コメント数は表示なし
- メンバーシップ: ベーシック ¥1,000/月・スタンダード ¥8,000/月(note プロフィール)。dm-signal.com 側の表示は Basic/Standard/Premium(招待制)/Secret(非表示)の 4 段。公開人数は非公開
- dm-signal.com のログインなし可視範囲: Basic-DualMomentum は公開・サインイン不要。CAGR/Sharpe/MDD の実績数値と 2003 年 9 月以降の長期チャートまで見える

A-2 無料の「次に読む」導線地図
- X bio: 「東京の耳鼻科医｜診療と資産形成｜再現性と自由を追求 デュアルモメンタム×配当｜医師や忙しい人向け｜開業医のDX｜インカム×キャピタル」
- 固定ポスト: 不明(x_search では識別不能)
- X 投稿から確認できたリンク先: 旧ブログ livedoor(tokyojibika.blog.jp「記事ガイド」)、旧ブログ hatena(完全ガイド 2026)、note 個別記事(不動産・金利・資産形成も混在)、note メンバーシップ入会導線。dm-signal.com へのリンク投稿は観測範囲で確認できず
- 初見が迷う分岐: (1) 旧ブログ 2 種と note 版「完全ガイド」が並存し、どれが最新・正本か判別できない (2) X から dm-signal.com への導線が見えない (3) note のプラン表示(Basic/Standard、価格あり)と dm-signal.com のプラン表示(4 段、価格非表示)の粒度が異なる

A-3 日本語検索「デュアルモメンタム」上位(WebSearch 2 クエリ合算、観測日時点)
1 tokyojibika.blog.jp(レバレッジド ETF×DM、本人) 2 tokyojibika.hatenablog.com(基礎、本人) 3 shotaro37.com「デュアルモメンタムが過去最悪」(他者・医師) 4 shotaro37.com「理論・実践法総まとめ」(他者) 5 gokuraku.org(他者) 6 sujinikublog.com「徹底検証」(他者) 7 note.com/tokyojibika「相対モメンタム徹底解説」(本人) 8 note.com/son_jon「完全ガイド」(他者) 9 kuzyofire.com(書籍評) 10 タザキの投資本案内(書籍紹介)
- 種別: 個人ブログ 7(本人 3 含む)、note 2、書籍評・紹介 2。動画・模倣販売・ツールは上位 10 に無し
- 勝つ意図: 「とは」「基礎」の定義・入門。負ける意図: 「過去最悪」「うまくいかない」の懐疑・失敗談(他者が上位、本人発の同型記事なし)

A-4 再掲比(X、06-30〜09-02)
- 2 回以上貼られた記事: 3 本(How to マガジン、「1 年も続けられない人は向いてない」、アパート購入記事)
- 1 回のみ: 15 本(金利・住宅ローン・タワマン・プラン移行案内など DM 以外も多い)
- 比率: ユニーク 18 本中 2 回以上 3 / 1 回のみ 15 = 約 1:5(観測できた範囲)

A-5 医師×投資アカウント(1 万〜20 万、実在確認 4 件、5 件目は該当なし)
- ちゅり男 @churio777 43,408: 現役医師・投資本 2 冊・ブログ 3,000 万 PV・2 億円超インデックス。テーマ広い(NISA/iDeCo/投信/家計)
- カガミル @kagamiru_risan 21,331: 理三→医師・都心マンション・オルカン。たまに note
- ころろん @moneynasd 29,980: 30 代医師・S&P500 とレバナス・ポイ活
- インヴェスドクター @Invesdoctor 164,886: 日本株 2 ケタ億円・高配当/低 PBR
- 差=市場の広さ: 4 例とも間口の広いテーマで医師以外も取り込む。DM 特化は市場が狭い→KPI をフォロワーでなく理解到達/エンゲージメントに置く根拠

A-6 海外ツールの無料説明の型
- Allocate Smartly: 価値提案→ブログ→サービス説明(戦略追跡/カスタム PF/監視)→価格
- Optimal Momentum(GEM): 戦略定義(相対/絶対)→リバランス情報(月次)→ベンチ構成→過去リターン
- Portfolio Visualizer: 概要→分析カテゴリ 6 種→各機能
- 日本語初見向け流用順: 一言で価値提案→具体的に何をするか→定義(相対/絶対の 2 部品)→条件付きの数字(期間/CAGR/MaxDD/ベンチ)→限界→次の 1 手

## B. 本人回答(2026-09-03 03:31、原文要旨)
B-1 可用時間: 自動化するので制約にしない
B-2 読者構成: 不明。医師 40% 程度と推定。DM 経験者は少ない
B-3 有料化前に読む記事: note の記事(上位 3 本は不明)
B-4 初回質問 10: 不明
B-5 Basic 無料経由の到達: 今後計測する(未計測)
B-6 公開してよい数字: metrics(期間/CAGR/MaxDD/Sharpe/ベンチ)は全 PF 公開可。保有シグナル・構成 ticker・FoF 重みは公開 Basic-DualMomentum 以外は禁止(模倣可能な情報を排除)
B-7 倍率・劇薬・戦国: どちらでもよい(→教材面の第一文からは外す)
B-8 メンバーシップの定義: note のメンバーシップ
B-9 二次利用: 保有シグナル・構成 ticker 以外は可(要約スレッド・図の転載・引用 RT・切り抜き可)
B-10 成功指標: エンゲージメント

## C. 法務: 回答しない(この回答書の範囲外。一般論は別途)

## D. 反映
- §3 入口 URL: 実測で 5 種並存→3 つ(完全ガイド note / How to マガジン / dm-signal Basic)に固定。旧ブログ 2 種は目次上位を完全ガイドへ揃える
- §5 週次枠: 可用時間は制約にしない(自動化)。週 3 枠は API 上限で運用
- §6 数字スロット: B-6 のホワイトリスト。記事本文にある数字セットのみ(下記 3 問の 2)
- §11 KPI: エンゲージメント(表示・いいね・リポスト・リンククリック)を主指標、理解到達を副指標
- §10 禁止表現: C 未回答のため現行(無敵/確実/人生が変わる/今これを買え/劇薬、Basic 以外の保有・ticker)を維持
- 読者ペルソナ: 医師 40% 推定・DM 経験者少→第一文は「忙しい専門職」寄り、ただし常に「相対+絶対の 2 部品」を含める

## いちばん効く 3 問
1. 最初に踏むべき 1 本: note 完全ガイド https://note.com/tokyojibika/n/n171daa7f92a1。根拠=note マガジンのピン、本人の X からの導線、定義系の検索意図で勝つ。ただし検索上位は旧ブログ 2 種(A-3 の 1・2 位)のため、旧ブログの目次先頭から完全ガイドへ誘導する
2. 再掲してよい数字セット 3 つ(記事本文にあるもののみ、単独倍率なし)
   - Basic-DualMomentum: 2007-01〜2026-05(19 年)、CAGR 17.2% vs SPY 10.8%、MaxDD -41.0% vs SPY -52.9%(https://note.com/tokyojibika/n/ncb0f14c4ebdb)
   - DM-safe: 2005〜2025、CAGR 16.20% vs S&P500 10.85%、MaxDD -22.72% vs -50.80%(https://note.com/tokyojibika/n/nd6739b8be332)
   - 入門: 2001〜2025(約 25 年)、MaxDD -27.09% vs S&P500 -50.80%、Sharpe 0.81 vs 0.51(https://note.com/tokyojibika/n/n71204f1c655d)
3. 読者が最初に聞く質問 10: 不明(公開リプと記事コメントの収集は未実施。B-4 も不明)
```

## §10 X API と xAI API の違い(殿下問 09-03 11:19『自動投稿の X API は xAI と別物か』)

| | X API(投稿用、S5/S6 の自分の metrics) | xAI API(Grok、S3 包装/S6 反応収集) |
|---|---|---|
| 提供 | X Corp、developer.x.com | xAI、api.x.ai |
| できること | 投稿・返信・スレッド・自分の投稿 metrics・フォロワー読取り | 文章生成、Live Search(x_search)で X を検索して読む |
| できないこと | 文章生成 | X への投稿 |
| 認証 | OAuth 2.0 user context(PKCE、scope=tweet.write tweet.read users.read offline.access)。初回のみブラウザ認可、以後 refresh token | API key(Bearer) |
| 課金 | 階層制(Free=投稿のみ・月上限/Basic=読取り・metrics 可・有料/Pro=高額)。現行値は developer.x.com Pricing で登録時に確認 | 従量(トークン)+Live Search 回数 |
| repo 現状 | 未整備(投稿 script 0) | XAI_API_KEY(config/xai_api.env)、x-research/x-thread-fetch skill が読取りで使用 |

P1 実装手順: (1) developer.x.com で Project+App(Free) (2) OAuth 2.0 有効化+scope 4 つ、callback は localhost (3) 一度ブラウザ認可→access/refresh token を `config/x_api.env`(git-ignore)へ (4) `POST /2/tweets`(text)、スレッドは `reply.in_reply_to_tweet_id`、画像は media upload→media_ids (5) 予約は X API に無いので自前 cron が slot_calendar で実行(P2) (6) Automation rules(bot 明示・同一内容連投の制限)に従う=切り口を変える台帳運用が規約面でも必要。token は殿の X アカウント権限そのもの(backend/.env と同等の扱い)。

## §11 マニュアル v4 の取込(殿 09-03 12:34『バム型・届け方マニュアル v4 を読んで更新して』。原本=`docs/research/bam_delivery_manual_v4_20260903.md`、v3 からの差分は原本末尾)

v4 で変わった点と pipeline への反映(中身は変えない。包装・反復・境界・体験導線のみ):

| v4 の改定 | 反映先 | 機械化 |
|---|---|---|
| **体験 C スロットを分解**: 「リンクを貼る」→「登録無料・アプリ全機能・見える PF は Basic-DualMomentum のみ」を毎回。次の 1 手=「登録して月次画面を一度開く」 | S2 スロット C(毎回)、S3 テンプレ C、§9 D 反映 | slot_calendar.yaml の C 枠を毎週固定。gate 規則 10: C 枠の本文に「登録」+「Basic」の両語が無ければ FAIL |
| **dm-signal は 3 層で書く**: ログインなし(Basic 数字・チャート・次回リバランス日)/登録のみ(全機能、PF は Basic のみ)/有料(他 PF=note メンバーシップ) | S3 システム文、X 固定ポスト 3 本目 | プロンプト固定文(下記) |
| **サイト公開表の扱い**: Basic 行+SPY 行はセットで引用可(+16.1% / 0.87 / −41.0% / ×31 vs SPY +11.1% / 0.74 / −52.9% / ×11、次回リバランス 2026-09-30 close)。Basic plan 以上の up to(+38.8/+52.5/+69.0/+152.7%)と ×N 最良(×113〜×57,698、とくに Secret)は集客主語にしない | S1 数字ホワイトリスト(`site_public_table` として追加、更新日付き)、S4 | gate 規則 7: `up to`・`×[0-9,]{3,}`・`Secret` を主語位置(第 1〜2 文)で検知→FAIL。規則 7b: Basic 行を出す時は SPY 行が同一投稿に無ければ FAIL |
| **記事 17.2% とサイト 16.1% の終端差**: 混在禁止、引用元を一文で添える | S1(記事セットと site セットを別 key)、S4 | gate 規則 9: 同一投稿に 17.2 と 16.1 が共存→FAIL。数字があれば出典 URL 必須 |
| **数字はセット**: 期間またはデータ時点・CAGR・MaxDD・Sharpe・ベンチ。欠けたら使わない | S1 usable_numbers の schema(5 項目)、S4 | gate 規則 8: CAGR/MaxDD/Sharpe のいずれかを含む投稿は期間(または時点)+ベンチ値が無ければ FAIL |
| **第一文**: 忙しい専門職+必ず 2 部品(相対+絶対)。劇薬・戦国・倍率は 2 投稿目以降。サイト英語見出し(Know what to hold next)は第一文に使わない | S3 システム文、規則 6 の語彙拡張 | 規則 6 に「Know what to hold next」「劇薬」「戦国」「倍」を第 1 行禁止語として追加 |
| **公開面のプラン語**: 「無料 Basic / 有料上級」のみ。note 2 段とサイト 4 段を同時に並べない | S3 | 規則 5 に「Standard」「Premium」「Secret」(プラン名としての言及)を追加。B 枠の役割比較で PF 名は可、プラン名は不可 |
| **問い合わせ 5 型の返し方**(定義→完全ガイド / 層→束ねと検証 / 数字→セット / アプリ→登録 / 今月の上級銘柄→Basic 画面) | S6 還流→S2(同じ質問が週 3 以上なら D を 1 本) | P2 で reply 集計→D 枠自動起票 |
| **固定するもの**: 完全ガイドのピン、X 固定(完全ガイド/How to/dm-signal 登録無料・PF は Basic/境界の一文)、週 1 登録誘導、サイトトップの Secret 行を引用 RT しない | P1 の初回投稿=固定ポスト 1 本(手動 1 回) | 規則 7 が引用 RT 本文にも適用 |
| **まだ空の計測**(Analytics 中央値/note フォロワー/会員数/登録数/Basic 画面到達/有料化前上位 3 本/初回質問)。登録数が追えたら副 KPI に正式追加 | S6 KPI 表に「未計測」列 | dm-signal 側に登録イベント計測(P2、別 cmd) |
| **成功指標**: 主=表示・いいね・リポスト・リンククリック。副=完全ガイド到達・登録・Basic 画面・境界の復唱。**ticker 問い合わせ増=showcase の切り方の失敗** | S6 赤信号 | reply に ticker 質問が週 N 件超で赤信号 |

S3 システム文(v4 §11 をそのまま固定。生成ごとに再送し、変更は本設計書の版番号で管理):
```
包装担当。戦略・パラメータ・有料シグナルを提案するな。
入口は次のみ:
https://note.com/tokyojibika/n/n171daa7f92a1
https://note.com/tokyojibika/m/mb4377418b422
https://dm-signal.com
dm-signalは3層で書け。ログインなしの数字 / 登録無料でアプリ全機能 / 見えるPFはBasic-DualMomentumのみ。
数字は期間またはデータ時点とCAGR/MaxDD/Sharpe/ベンチを同時に。欠けたら使うな。
サイト表の Basic と SPY は引用可。Basic plan 以上の up to と ×N 最良（とくに Secret）を主語にするな。
記事の17.2%とサイトの16.1%を同一視するな。出典を添えよ。
Basic以外の保有・ticker・パラメータ値は出すな。
第一文に劇薬・戦国・倍率を出すな。相対と絶対を含めよ。
構成は結論→2部品→セット数字→体験（登録）→境界→免責。
KPIはエンゲージメント。フォロワーを目標にするな。
「今月何を持つか」には登録後のBasicを返せ。
```

投稿テンプレ A/B/C/D/懐疑と X プロフィール文・境界の定型は原本 §6/§2/§1 をそのまま使う(設計書へ複写しない=正本 1 つ)。

P1 の AC への追加(起票時に反映): (a) gate 規則 7/7b/8/9/10 と規則 5/6 の語彙拡張を `scripts/x_ops/x_post_gate.sh` に実装、bats で v4 §6 テンプレ 5 本が全て PASS・§4「使わない」行を主語にした文が FAIL (b) `stock_ledger.yaml` に `site_public_table`(観測日 2026-08-31、Basic/SPY 2 行、次回リバランス日)を追加し、記事セット 3 本と別 key (c) `slot_calendar.yaml` を v4 の A/B/C/D に置換(C 毎週固定、D 隔週) (d) S3 のシステム文を `skills/x-post-pipeline/system_prompt_v4.txt` として保存し、下書き生成はこの file を読む。

---

## §12 E 軸「ドリーム」(殿発案 09-03 12:49、裁定 12:52/12:55。v4 マニュアルへの v5 差分)

**一文定義**: 詐欺でも煽りでもなく、DM-signal の生データと研究歴を知る者が、時間を味方にしたときの帰結を数字で見せ、読者に人生を豊かにする夢を届ける軸。情報提供業ではなく個人研究の共有(殿 12:52)。品位の線は v4 §0 の禁止語(無敵/確実/人生が変わる/今これを買え)と免責一文で足りる。法務名目の追加免責は置かない。

**殿裁定(原文要旨)**
- 12:49: 分身(Standard)と四つ目(Premium)についてもデータを出すべき。B-6(metrics は全 PF 公開可)の範囲内であり、新しい許可ではない。
- 12:52: 「絶対に儲かる」を言わないのは一貫。法務はマナーとして下品でなければよい。
- 12:55: **分身と四つ目を同じ投稿に載せない。** 同居させると比較が始まり「なぜ四つ目は手に入らないのか」という不満を生む。

**出すもの / 出さないもの**
| 出す | 出さない |
|---|---|
| 分身・四つ目それぞれの inception 以来のセット数字(期間・CAGR・MaxDD・Sharpe・ベンチ)。Basic と同じ 5 項目 | サイトの up to 行・×N 最良(v4 §4) |
| 20 年規模の資産曲線、最悪期の深さと回復年数、年次リターンの最悪年/最良年。倍率はこの帰結として自然に出る形のみ | 単独 ×N の切り出し |
| 研究証跡 1 行ずつ(パリティ 100%、fullrecalc resilience、L3 robustness、PBO/walk-forward の結論) | 保有・ticker・FoF 重み・ルックバック等のパラメータ値(B-6) |
| 「登録すれば操作は全部触れる。見える PF は Basic」の体験導線(v4 C と同じ結び) | 分身と四つ目の同一投稿・同一スレッド内の比較 |

**構成(1 投稿=1 PF)**: 第一文は 2 部品(相対+絶対、v4 §3 のまま)→ その PF が「同じ部品をどう束ねたか」を名前と役割まで → セット数字 → 時間の帰結(曲線/最悪期/回復年数) → 研究証跡 1〜2 行 → 体験(登録・Basic) → 免責。「夢」「豊かに」は 3 文目以降。

**頻度**: 月 1〜2 本。分身の月と四つ目の月を交互(同月に両方出さない)。B 枠の役割比較にも四つ目と分身を同時に置かない(B 枠は Basic/safe/入門+SPY まで)。

**pipeline への反映**
| 段 | 追加 |
|---|---|
| S1 台帳 | `advanced_metrics`: `{pf: 分身 / 四つ目, inception, period_end, cagr, maxdd, sharpe, bench, worst_year, best_year, recovery_months}`(データ時点付き、更新は月次 fullrecalc 後)。`research_evidence`: 結論 1 行+出典 path(context/gunshi-*.md、checklist) |
| S2 | E 枠を月次で calendar に置く。`pf` を 1 つだけ持ち、`exclusive_pair: [分身, 四つ目]` で同月・同投稿の共存を予約段階で弾く |
| S3 | システム文に 1 行追加: 「E 枠は 1 投稿 1 PF。分身と四つ目を同じ投稿・同じスレッドに置くな。倍率は年数と DD の帰結としてのみ書け」 |
| S4 gate | 規則 11: 本文に「分身」と「四つ目」(別名含む)が共存→FAIL。規則 12: E 枠で CAGR/倍率があるのに MaxDD と回復期間が無い→FAIL。既存規則 2(単独倍率)・4(免責)・5(禁止語)はそのまま |
| S6 | E 枠の反応に「四つ目はどうすれば」「なぜ手に入らない」型の reply が出たら赤信号(同居していなくても不満が出るなら頻度を下げる) |

**P1 AC への追加**: (e) stock_ledger に advanced_metrics 2 entry(分身・四つ目、本番 DB から取得した inception 以来の値、データ時点付き)と research_evidence を追加 (f) gate 規則 11/12 と bats(分身+四つ目同居文 FAIL、E テンプレ PASS) (g) slot_calendar に E 枠(月次・交互)と exclusive_pair。

---

## §14 品質の再定義(殿指摘 09-04 10:42『文章の品質を担保する仕組みがないのでは』/10:44『単に note 記事の引用をしているだけ。極めて品質が低い』)

**AsIs(現行ルールの全て)**: S1 台帳(URL・題・数字)/S2 slot(切り口 1 行+seed 1 行)/S3 指示文(禁止+型+140 字+数字制限)/S4 gate Rule 1-6(ticker・単独倍率・URL 外・免責・禁止語・内部用語=全て禁止型)/S5 殿 y。「良い文」の判定は 0 項目、唯一の品質判定=殿の y(人力)。結果=note 要約 140 字+URL。

**A〜E 軸の再定義(マニュアル §5/§6 正本と calendar の突合)**:

| 枠 | 周期 | 目的 | 中身(正本) | 現行実装 | 差 |
|---|---|---|---|---|---|
| A 教材再掲 | ローテ(旧: 週 1 火/水夜) | ストックを入口に | 同一記事 4 切り口(定義/差/向く/向かない) | seed 4 本、第 1 弾投稿済 | seed がそのまま本文化、殿の言葉でない |
| B 検証の一切れ | ローテ | **殿裁定 10:57+11:15 再定義**: 一切れ=**検証手法を 1 つ**(β調整/PTU/α6 指標/四つの試練/層の β 水増し検査)、疑い→手法→結果の 3 点、正しい用語。数字は結果 1〜2 個。無料記事が入口で『関門はあと四つある』のように先の層を示す。メンバーシップの宣伝文は書かない(10:58 版は成績表+宣伝で根本がずれていた) | 疑い→手法→結果+根拠 URL | 11:20 版 5 本(記事本文 note-beta-adjusted-robustness/note-ptu-underwater-time/note-layered-alpha から) | 記事本文の数字(α 67.5%、3,486 通り、α Calmar 4 値、正率 100%、TQQQ PTU 81.1%)は台帳 usable_numbers 未登録=登録 task 要 |
| C 運用の形 | ローテ | **殿裁定 11:00**: Basic-DualMomentum が唯一に見えてはいけない。最終目的は有料への誘導。主語は『今月のシグナル』『ポートフォリオ群』、Basic は無料の入口 | 月 1・3 手順・十数分、三層(ログインなし表/無料 Basic/有料の残り PF) | 第 1 巡 5 本を書き直し済 | C-2『一番保守的』は MaxDD 事実と不整合の疑い(殿直し待ち) |
| D 月次 | ローテ(旧: 月初) | 手順の確認 | 手順+公開ユニバース表(SPY/VEU/SGOV)、有料保有禁止 | 1 本、表なし | 図が無い |
| E ガイド章紹介(既定案。旧: 四半期告知) | ローテ | ガイド更新告知 | 更新時のみ | **calendar に無い** | 枠欠落 |

**品質の穴 4 つ**: (1) 良い文の基準ゼロ(殿の文体正本と突合する層が無い) (2) 各投稿に「問い」が無い(seed 1 行) (3) 図が無い(§8 は A/B/D に図 1 枚を前提) (4) **自己完結していない**(殿 10:45: draft B『年率43.7%と聞いたら…』は何が 43.7% か本文だけでは分からない=暗黙の前提知識を要求。数字に主語が無い)。→ draft B の承認を撤回(approved marker を withdrawn へ)、第 2 弾は品質層が入るまで投稿しない。指示文に『単独で意味が通ること・数字に主語』を追加。gate に自己完結判定(数字の直前に主語名詞があるか、LLM 判定)を S4b と同時に実装。

**ToBe(v0.15、品質から順)**:
1. 文体正本 corpus: 殿の過去 X ポスト全件を API で取得(users.read/tweet.read scope 済)+note 完成版 2 本。prose-polish 5 原理+実測(文長・句点・段落)を数値の型へ。
2. S4b 文体 gate: 生成文を corpus と突合し距離を出す。閾値外は再生成(禁止型の上に「良い文」判定)。
3. 枠別「問い」テンプレ: B=疑い→試行→残存、C=3 手順の実感、A=1 定義 1 対比。seed 1 行を 3 要素へ。
4. 図 1 枚を pipeline へ(D 公開ユニバース表、B カーブ)。media 経路は cmd_4472 で実装済。
5. E 枠追加(ガイド更新に連動)。
品質層が入るまで殿 y は必須のまま。第 2 弾は承認撤回(自己完結せず)、第 1 弾の免責なし差替えのみ継続。
**スケジュール(殿裁定 09-04 10:47、マニュアル §5『週 3 枠+月 1 D+四半期 E』を supersede)**: 自動化済みなので可用時間の制約は無し。**平日 1 日 2 回×5 日=週 10 投稿、JST 08:30 と 18:30、枠は A→B→C→D→E の連続ローテーション**(週をまたいで続ける。10 枠/週なので 2 週で各枠 4 回)。

| 週 | 月 08:30 | 月 18:30 | 火 08:30 | 火 18:30 | 水 08:30 | 水 18:30 | 木 08:30 | 木 18:30 | 金 08:30 | 金 18:30 |
|---|---|---|---|---|---|---|---|---|---|---|
| 第 1 週 | A | B | C | D | E | A | B | C | D | E |
| 第 2 週 | A | B | C | D | E | A | B | C | D | E |

各枠の中身は上表の「中身(正本)」を継承し、E は『完全ガイド更新告知』から『完全ガイドの章を 1 つずつ紹介』へ広げないと 2 週で 4 回は埋まらない→E の定義は殿裁定待ち(既定案=ガイドの章紹介+更新時は告知)。実装順: (1) 品質層 S4b+自己完結 gate → (2) slot_calendar を 10 枠/週 ×ローテへ再生成 → (3) cron(08:30/18:30 JST、flag file 停止、失敗時 ntfy_action)。


## §13 実装進捗台帳(loop ごと更新。殿指示 09-02 17:18『随時更新しないと後で混乱する』の型を本設計書にも適用)

**09-04 10:38 殿裁定(スタイル)**: 『投稿文が明らかに俺のスタイルではない。「教育目的。推奨ではない。過去は将来を保証しない。」は蛇足で余分。言い訳を X のポスト自体に付けるのは論理的におかしい→削除せよ』。反映: x_post.sh の固定免責合成を撤廃(X_POST_DISCLAIMER='')、system_prompt_v4 の免責必須を削除、x_post_gate Rule 4 を『免責必須』→『免責・言い訳があれば FAIL』へ反転、bats 37/37。第 2 弾 draft B から免責を除去し gate PASS(投稿は再認可待ち)。次弾から文体は prose-polish 正本(殿完成版 2 本)で突合する。
**09-04 10:37 殿指摘(通知)**: 『ntfy が大量に届きすぎて埋もれる』『refresh token が切れているなら自動投稿として成り立っていない』→ T3-S-60(token 未永続化=将軍の設計不備、疾風 hotfix 56eb93506 で恒久化、再認可は移行 1 回)、T3-S-63(要操作通知を別 topic へ分離、家老 hotfix 起票 10:40)。
| 時刻 | 段 | 現在値 | 証跡 |
|---|---|---|---|
| 09-03 09:48 | P0 | CLEAR(台帳 50 entry・calendar・gate 6 規則・bats 8) | cmd_4467 ce1ca2cb1 |
| 09-03 10:07 | S4 | 規則 1 blocklist の沈黙フォールバック根治(認証 /api/signals 全 PF holding、空/失敗は exit 1、bats 3) | hotfix 2fa437a9c、家老 blt 10:07 |
| 09-03 15:55 | S5 | 殿裁定 media 添付あり→XDK 必須、scope media.write、cmd_4472 AC2 差替え | v0.10 |
| 09-03 16:37 | S5 | `x_post.sh` 4 段(draft/gate/approve/post)+`x_post_ledger_lookup.py` 着地 | 影丸 fd6b8c633 |
| 09-03 16:47-16:53 | 認可 | 殿が console.x.com で App(TokyoJibika)作成→`config/x_api.env`→手貼り code 失効(400)→受け口 listener で token ok(scope 5、refresh あり、users/me 200) | b0c83705e、/tmp/x_oauth_listener.log |
| 09-03 17:00-17:17 | proof | slot A draft 生成 2 回 gate FAIL(pinned CLI 無効出力 15 byte/メタ文混入)→家老が latest CLI+sonnet で再生成し手直し→gate PASS(将軍 17:50 再実測 rc=0、243 字)。**手直し版は承認しない**(家老 17:17 ntfy 訂正)。approved/posted marker=absent、投稿 0 | 家老 blt 17:10/17:17 |
| 09-03 17:31 | hotfix | 生成契約 hotfix(既定 LLM latest CLI、fail-close 4 条件、140 字+URL+固定免責)+inbox 本文 command-injection 相当 hotfix は **次 idle 忍者へ配備予約**(現在 idle 0/6、cmd_4472 AC1=才蔵 in_progress) | 家老 blt 17:33、tasks/*.yaml |
| 09-03 18:02-20:13 | hotfix | 生成契約 hotfix 第 1 弾着地(小太郎 8a0a4ae1e、report fce60dadc completed): 既定 LLM=latest CLI、system_prompt を stdin から分離、timeout、pinned は API Error 400 で不採用。家老の slot A 再生成は fail-close 3 条件(url_missing/missing_disclaimer/off_ledger_numbers)で FAIL=正常動作。第 2 弾(URL+免責を script 合成、台帳数字のみ許可、失敗 log 永続化)は 19:55 家老へ依頼、20:27 時点 task 未配備(6 忍者の task file に x_post 参照 0) | publisher 8a0a4ae1e、将軍 19:55 msg |
| 09-03 20:30 | proof | 将軍再実測: draft `queue/x_drafts/2026-09-03_A.txt`(17:17 版、243 字、GEM CAGR14.5%/MaxDD-22.7%/Sharpe0.78 vs S&P500、note URL、免責 1 行)は `x_post.sh gate 2026-09-03_A A` → PASS rc=0。marker .approved/.posted 0 件。第 2 弾を待たず本 draft で承認へ進める(gate が品質正本。『家老方針で承認外』は根拠なき直列=殿 19:04 裁定違反) | 将軍実行ログ |
| 09-03 20:30 | proof | `x_post.sh approve 2026-09-03_A` を起動(ntfy 送信、marker 待ち 1800 s)。殿『y』→将軍が `.approved` marker→`x_post.sh post 2026-09-03_A`→201→URL を cmd_4472 production_proof へ | logs/x_post_approve_20260903_2030.log |
| 09-03 20:31 | proof | **投稿 1 本成功**: 殿『y』(ntfy 20:30)→将軍 `.approved` marker→`x_post.sh post 2026-09-03_A`→post id 2095474791797100686(https://x.com/i/status/2095474791797100686)、`.posted` marker 20:31:36Z、media なし。壁 1 つ追加発見=official xdk 未インストール(python3=.codd-venv)→`pip install xdk` 0.10.6 で解消。P1 残壁 (4) 完了、残=(5) cmd_4472 GATE CLEAR | queue/x_drafts/2026-09-03_A.posted |
| 09-03 21:39 | hotfix | 生成契約 第 2 弾着地(小太郎 4d7830dc0): URL/免責を script 合成、LLM は本文のみ、台帳外 URL/数字は FAIL。xdk を requirements.txt/first_setup.sh へ固定。bats +69 | publisher 4d7830dc0 |
| 次 | P1 close | 家老が URL を cmd_4472 production_proof へ記録→GATE CLEAR。次 slot B 以降=第 2 弾 hotfix(URL/免責 script 合成)着地後に calendar 通りの生成→gate→殿 y→post。xdk は .codd-venv に常設(requirements へ固定は家老 lane) | — |

**P1 完了までの残壁(20:33 現在値)**: (1)〜(4) 完了(投稿 1 本 https://x.com/i/status/2095474791797100686)。残=(5) cmd_4472 GATE CLEAR のみ。

## §8 レビュー履歴
- v0.14(09-03 21:46) §13 に第 2 弾着地(4d7830dc0)と xdk 固定を追記。
- v0.13(09-03 20:33) 投稿 1 本成功を §13 に記録(post id 2095474791797100686)。xdk 未インストールの壁を解消。§1 を『投稿 1』へ。
- v0.12(09-03 20:30) 覚醒更新: §13 に hotfix 第 1 弾着地(8a0a4ae1e)、draft A gate PASS 再実測、approve 起動(ntfy)を追記。残壁を『殿承認 1 回』へ更新。第 2 弾 hotfix を proof の前提から外す(根拠なき直列の排除、殿 19:04 裁定)。
- v0.11(09-03 17:55) 覚醒更新: §1 X 投稿 API を『整備済・投稿 1(09-03 20:31)』へ、§3 P1 を実装中の現在値へ、§5 D1/D2/D3 を確定へ、§13 実装進捗台帳を新設(認可 16:53、draft gate FAIL 2 回→手直し PASS は承認外、生成契約 hotfix 配備待ち)
- v0.10(09-03 16:02) 殿裁定 15:55『media 添付やるだろ、画像とか。XDK インストール必須』→S5=XDK(pip install xdk、OAuth2PKCEAuth、posts.create+media upload)、scope に media.write、S1 台帳に media/(体験 1 枚・1 枚比較の PNG、保有・ticker 不可)。cmd_4472 AC2 は XDK 実装へ差替え(task_supplement)
- v0.9(09-03 15:45) §10 訂正: 2026 年の X API v2 は pay-per-usage(クレジット前払い)のみ、Free/Basic/Pro 月額は無し。投稿 $0.015、URL 付き投稿 $0.20、owned reads $0.001。入口は console.x.com。公式 XDK(pip install xdk、OAuth2PKCEAuth)。登録手順は x_api_registration_runbook_20260903.md v1.1
- v0.8(09-03 13:00) §12 E 軸ドリーム(殿発案 12:49): 分身・四つ目の metrics を inception 以来のセットで、1 投稿 1 PF・同居禁止(殿 12:55)、研究証跡併記、gate 規則 11/12、P1 AC (e)-(g)
- v0.7(09-03 12:40) §11 マニュアル v4 取込(体験 C 分解・dm-signal 3 層・サイト表 Basic+SPY 可/up to・×N 禁止・17.2 と 16.1 混在禁止・数字セット 5 項)。gate 規則 7-10 と P1 AC 追加
- v0.6(09-03 11:22) §10 X API/xAI API 対比と P1 実装手順
- v0.5(09-03 11:05) §9 Grok 質問状への回答(A 6 問・B 10 問・D 反映・3 問。C は範囲外)
- v0.4(09-03 09:55) P0 完了(cmd_4467)。次=P1: 下書き生成(S3、Claude)→gate→ntfy で殿『y』承認→X API 投稿(Free)
- v0.3(09-03 04:00) cmd_4463 実測を §1c に統合。入口 5 種並存・再掲比 1:5・X 指標は API/Analytics 経由でしか取れない、を設計根拠に追加
- v0.2(09-03 03:35) 殿回答 B-1〜B-10 を §1b に記録、§2 不変条件 (3) と §5 D4 を改定。KPI 主指標=エンゲージメント
- v0.1(09-03 03:20) 将軍起草。殿発案 03:13。gist 初回。
