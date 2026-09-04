<!-- gist-master: da5adc2c7ff639d4b83e10355d46176b x_growth_engine_asis_tobe_5w1h_20260904.md -->
# X Growth Engine 設計書 v1.0 — AsIs/ToBe 5W1H(2026-09-04 14:51 殿指示)

- 発端: 殿 2026-09-04 14:51『Content Engine はかなり完成した。次は「その投稿でフォロワーが増えるか・note/DM-Signal へ流入するか・登録/有料化へつながるか」。Content Engine を再設計せず、上位に Growth Engine を設計・実装せよ』
- 上流正本: 方針 `docs/research/x_editorial_doctrine_20260904.md`(12:42 + 14:38 conversation gap)→ Content 設計 `docs/research/x_account_ops_automation_asis_tobe_5w1h_20260903.md` §16/§17 → 分析 `docs/research/x_author_corpus_analysis_20260904.md` → 本書
- 実装正本: `skills/x-post-pipeline/growth_schema.yaml`(定義)/`slot_calendar.yaml`(Growth 列)/`queue/x_rewrites/R4-*.yaml`(growth: ブロック)/`queue/x_live_oos/ledger.yaml`(live OOS 台帳)/`scripts/x_ops/{x_growth_tag.py,x_kpi_snapshot.py,x_slot_post.sh}`
- 不変: A〜G 分類、author corpus、human rewrite corpus、system_prompt_v5.x、承認済み 13 本は維持(殿)。本書は「良い文章を獲得につなげる仕組み」の追加のみ。

## §0 AsIs / ToBe(1 表)

| 項目 | AsIs(09-04 14:50) | ToBe(v1.0) |
|---|---|---|
| 最適化対象 | 投稿品質(Fact/Voice 6 軸) | ファネル全体。1 投稿の仕事は 1〜2 段階 |
| 軸 | content_category A-G のみ | + audience / funnel_stage / desired_action / hook_type / conversation_gap / link_type / series / external_context / topic_level |
| 配分 | 分類比 A-E 80/F 15/G 5 | + 段階比 reach 8/follow 4/trust 6/convert 2(20 slot、4 週固定) |
| 投稿 | 手動 post | cron 定時投稿 `x_slot_post.sh`(平日 08:30/18:30)+ 台帳へ post_id |
| 計測 | public_metrics 手動 | `x_kpi_snapshot.py` 毎時: 24h/7d snapshot(public + non_public: profile_clicks/link_clicks)+ followers 日次 |
| 会話 | なし(自分の島) | Conversation Entry lane(半自動、承認必須) |
| プロフィール | 未監査 | §11/§12 監査済み、改善案提示(変更は殿) |
| note | 販売リンク | Trust Amplifier(X=Hook、note=Proof、DM-Signal=Product) |

## §1 最終目的とファネル

Impression → Engagement/Dwell → Profile Visit → Follow → 再接触 → Trust → note → DM-Signal → Signup → Paid。
**規則**: 全投稿に全段階を担当させない。1 投稿=1〜2 段階(`growth.funnel_stage` + `desired_action`)。

## §2 Content Category × Funnel Role の分離

| funnel_stage | 目的 | desired_action | 既定 link |
|---|---|---|---|
| reach | 非フォロワーを止める。DM を知らなくても分かる | dwell/reply/quote/profile | none |
| follow | 「次も読みたい」=未来価値(series) | profile/follow | none |
| trust | 「ちゃんと調べている」。bookmark が主 proxy | bookmark/follow/note | none or note |
| convert | 信頼済みの人を note/DM-Signal へ | note/dm_signal/signup/paid | note or dm_signal |

category→既定 stage: A/D=reach、B=follow、C/E=trust、F/G=convert(C の series 1 本は follow、F の 2 本目以降は trust)。既定は `growth_schema.yaml category_defaults`。投稿単位の上書きは `x_growth_tag.py OVERRIDES`。

## §3 Audience 階段

general → investor → systematic → dual_momentum → dm_signal。入口ほど広く。13 本の現状: general 6 / systematic 5 / investor 1 / dual_momentum 1(dm_signal 0)。calendar 20 slot: general 4 / investor 3 / systematic 9 / dual_momentum 3 / dm_signal 1。**systematic 偏重が見える。Reach 素材(§5)の追加生成で general/investor を増やす。**

## §4 Topic ladder

1 お金・格差・複利・確率 → 2 投資の数学 → 3 投資システム → 4 検証 → 5 モメンタム → 6 デュアルモメンタム → 7 DM-Signal。
`growth.topic_level` を各投稿に持つ。stock_ledger への `topic_level/possible_previous_topic/possible_next_topic` は **v1 では追加しない**(64 entry の手作業になり複雑化。まず投稿側の topic_level で分布を見る)。

## §5 Reach 素材一覧

`growth_schema.yaml reach_materials` R01〜R10(殿例 7 + 暴落/−80%/医者年収 3)。うち承認済み 13 本で既に持つもの: R01(D-1)、R04(A-3)、R05(A-4)、R06(A-1)、R07(C-1)、R09(D-1)。**未生成 = R02 勝率、R03 長期、R08 暴落、R10 医者年収**。次の生成 round(Round5)はこの 4 本+E/G を対象にする。
根拠(§18): 本アカウントで math_prob テーマは like 中央値 7・bookmark 平均 15.8 と全テーマ最高、medical×お金は imp 平均 13,737 と最大。**Reach の主力は「お金の数学」と「医者のお金」**。

## §6 Follow Engine(series)

series `trust_system`「僕が投資システムを信用するまで」9 本(βを引く/OOS/WF/パラメータ全振り/計算日ずらし/執行日ずらし/二次元ずらし/論文再検証/不採用結果)。規則: 各投稿単独で意味が通る、末尾 (n/9) 可。R4-C-1(β調整後リターンを WF で分析しろ)を 1/9 に割当済み。残 8 本は Round5 で生成し、slot C(follow)へ順次。

## §7 Conversation Engine(別 lane)

対象: インデックス論/FIRE/暴落/積立/高配当/レバレッジ/モメンタム/バックテスト/有名論文/投資系の大きな投稿。
流れ: 候補検出(v1 は殿または将軍が URL を渡す。API 検索は Basic tier の recent search 制限を確認してから)→ LLM 案(v5.x + 「相手に同意できる部分を先に認めてから本人の視点を 1 つ接続」)→ 要操作 ntfy で承認 → reply/quote(`x_post.sh` に `--reply-to`/`--quote` を追加する。v1.1)。**自動 reply spam 禁止。**
根拠: 本人 X の reply like 上位 172/137/87/81 は全て他人の大きな話題(医療×経営)への接続。quote の imp 中央値 1,152 は single の 1.85 倍。

## §8 conversation gap の統合

`growth.conversation_gap` low/medium/high。13 本の付与: high 3(A-1/A-4/C-1)、medium 8、low 2(B-3/F-3 数字の投稿)。forward test の問い: gap=high は reply/quote が多いか(t24h reply_count, quote_count)。gap は Fact gate 通過が前提(悪い gap=誤り・隠蔽は Fact gate で落とす)。

## §9 note の役割 = Trust Amplifier

X(疑問・違和感・結論・数字 1 組)→ note(検証設計・方法・全データ・図・反証・失敗)→「本当に計算しているんだな」→ DM-Signal(その思想の実装)。X=Discovery/Hook、note=Proof、DM-Signal=Product。
実装: trust 投稿の link は「必要な時だけ note」。note 側で `?utm_source=x` 等は note が UTM を保持しないため **note PV の投稿別帰属は取得不能**(note ダッシュボードの日次 PV と投稿日を突合する手作業のみ)。

## §10 DM-Signal への導線

毎回貼らない。convert 段階(F の 1 本目 + G)のみ。順序は「検証結果 → この検証思想で作っている → DM-Signal」。**dm-signal.com へは `?utm_source=x&utm_content=<draft_id>` を付ける**(LP は静的で UTM を捨てないため、Render のアクセスログまたは Cloudflare Analytics で投稿別訪問を取れる。設定は v1.1)。

## §11 Profile 監査(実物 2026-09-04 14:52、API users/me)

| 項目 | 現状 | 所見 |
|---|---|---|
| display name | バム | 何者か分からない。X Voice は維持するとして「バム｜耳鼻科医×デュアルモメンタム」等の副題は候補 |
| bio | 東京の耳鼻科医｜診療と資産形成｜再現性と自由を追求 デュアルモメンタム×配当｜医師や忙しい人向け｜開業医の DX｜インカム×キャピタルの両立｜noteで戦略共有中 ▶ bit.ly/note-dm | 「何者か」は分かる。「フォローすると何が得られるか」「DM-Signal との関係」が無い。『配当』『開業医の DX』『インカム×キャピタル』は現在の発信軸(数学・確率・検証)とずれる |
| url | note.com/tokyojibika | note 直。DM-Signal へは bio の bit.ly のみ |
| pinned | 1534035934660132864(2022-06-07、画像 4 枚の投稿) | 4 年前。現在の思想・DM-Signal と無関係 |
| followers/following | 4,428 / 981 | listed 47、tweet 24,418 |
| profile image / header | 2021-07 の画像(URL のみ確認、内容は未確認) | 実物目視は殿 |

改善案(勝手に変えない): bio 案「東京の耳鼻科医。投資を数学・確率・検証で考える。デュアルモメンタムを自分で検証して運用、その実装が DM-Signal。noteで検証を全部出す ▶ note.com/tokyojibika」。**殿の裁定待ち。**

## §12 Pinned Post 監査

現 pinned は 2022-06 の画像投稿で、初見の「何者か・なぜフォローするか」に答えない。候補比較:

| 案 | 内容 | 担当段階 | 長所 | 短所 |
|---|---|---|---|---|
| P1 | デュアルモメンタム完全ガイド(n171daa7f92a1) | trust→convert | 本人最大の資産、5700 倍投稿(bm 650)と同系 | 商品寄り。初見に重い |
| P2 | 「僕が投資システムを信用するまで」series の 1/9 | follow | フォロー理由=未来価値を直接示す | 単発では弱い(series が揃ってから) |
| P3 | 自己紹介+思想(3 原則を本人 Voice で) | follow | 何者かに即答 | 数字が無い |
| P4 | DM-Signal 長期検証(公開成績+MaxDD+ベンチ) | trust | 本人 09-03 投稿(1,227 imp/4 bm)が実証 | 商品説明に見える危険 |

推奨: **P3 を本文、P1 を返信 1 段目に付けた 2 段構成**(本人の型: root+リプ二段目)。series が揃ったら P2 へ差替え比較。裁定は殿。

## §13 外部リンク戦略

reach/follow=X 内完結、trust=必要時 note、convert=note/DM-Signal。観測(§18): 投資系 single で URL あり imp 中央値 786(n=395) vs なし 636(n=174)。**このアカウントでは URL ありの方が中央値が高かった**。因果ではない(記事告知投稿が混在)。forward test で link_type 別に比較する。

## §14 投稿頻度

平日 2 投稿を維持(cron `30 8,18 * * 1-5`)。増やすなら Conversation Entry。

## §15 metadata schema

`growth_schema.yaml metadata_schema`。13 本へ `growth:` ブロック付与済み(`x_growth_tag.py`、既存フィールド不変)。slot_calendar に `funnel_stage/audience`(+series_id)を追加済み(最小変更)。

## §16 初期配分仮説(固定)

20 slot 実値: reach 7 / follow 4 / trust 7 / convert 2(A4 D4 → 1 本の A が投資家向け trust 寄りのため計算上 reach 7)。殿候補 40/25/25/10 との差は follow −1・trust +2。**4 週(40 投稿)固定。最適化禁止。**

## §17 KPI 体系

| 層 | 指標 | 取得 |
|---|---|---|
| Impressions | impression_count | 可(public) |
| Engagement | like/reply/repost/quote/bookmark | 可 |
| Profile | user_profile_clicks | 可(non_public、自投稿のみ。実証: 第 1 弾で 0/40imp) |
| Acquisition | followers_count 日次差分、follow/impression(日次近似)、follow/profile_visit | 日次のみ。**投稿別 follow は取得不能** |
| Trust | bookmark、repeat engagement(同一 user の再反応=取得不能)、url_link_clicks | bookmark・link_clicks は可 |
| Conversion | dm-signal visits(UTM 導入後)、signup/paid(DM-Signal DB 日次) | 投稿別は UTM 後。signup/paid は日次数のみ |

推測値は書かない。取得不能は台帳に書かない(空のまま)。

## §18 本人 X Growth 分析(3,247 件、観察データ。因果断定しない)

| 切り口 | n | like 中央値 | bookmark 平均 | imp 中央値 |
|---|---|---|---|---|
| 単独 全体 | 1,511 | 3 | 2.96 | 623 |
| 単独 投資系+ | 569 | 5 | 2.14 | 728 |
| URL あり / なし | 395 / 174 | 5 / 4.5 | 2.74 / 0.79 | 786 / 636 |
| 数字あり / なし | 452 / 117 | 5 / 4 | 2.61 / 0.35 | 774 / 613 |
| 疑問形 / なし | 52 / 517 | 5.5 / 5 | 1.73 / 2.19 | 913 / 712 |
| DM-Signal 言及 / なし | 37 / 532 | 6 / 5 | 0.38 / 2.27 | 731 / 728 |
| 長さ ≤80 / 81-140 / >140 | 96 / 266 / 207 | 4 / 5 / 6 | 0.36 / 1.07 / 4.35 | 609 / 718 / 791 |
| テーマ math_prob | 44 | 7 | 15.84 | 965 |
| テーマ investing | 385 | 5 | 2.79 | 739 |
| テーマ dm_signal | 180 | 5.5 | 0.48 | 722 |
| テーマ verification | 73 | 4 | 0.71 | 681 |
| テーマ medical | 75 | 5 | 7.28 | 1,002 |
| reply | 1,226 | 1 | 0.25 | 323 |
| quote | 359 | 3 | 0.54 | 1,152 |

読み(このアカウントでは、の範囲): (1) 数字ありは bookmark 平均 7 倍。(2) 140 字超は bookmark 平均 4 倍・reply 中央値 1。(3) math_prob は全テーマ最高(like 7、bm 15.8)。(4) DM-Signal 言及・verification は bookmark が低い=**商品名・検証語は保存されない。数字と数学は保存される**。(5) quote は imp が single の 1.85 倍。(6) 疑問形は imp 中央値が高く bookmark は低い=reach 向き。

## §19 bookmark 分析

bookmark≥2 の単独 144 件: 数字あり 128(89%)、URL あり 113(78%)、長さ中央値 133.5。上位: 年収⇄手取り計算(2,499)、5700 倍 DM(650)、町医者データ(368)、iDeCo(24)、専従者給与(19)。**共通点=「読者が自分の数字に当てはめて使える計算・表・具体額」**。DM の bookmark 上位は「5700 倍」「DM×3 倍レバ/ノンレバの使い分け(36)」。09-03 の DM 解説+検証数字(4 bm)はこの型。Trust proxy として bookmark を採用し、trust 投稿には「当てはめて使える数字 1 組」を必須にする(Content 側 v5.x に追記しない。slot 指示で渡す)。

## §20 Live OOS

台帳 `queue/x_live_oos/ledger.yaml`: 事前 metadata(13 本+第 1 弾 baseline)→ `x_slot_post.sh` が投稿し post_id/posted_at 記入 → `x_kpi_snapshot.py`(cron 毎時 15 分)が 24h/7d 到達時に snapshot → followers 日次 `account_daily.jsonl`。
API コスト: /2/tweets ids≤100 を毎時 1 回、/users/me 毎時 1 回。Basic tier で十分。
開始: 本日 2026-09-04(金)18:30 slot A(cron 登録済み)から。次は 09-07(月)08:30。在庫 13 本(A3 B3 C3 D3 F1、E/G 0)。E/G slot は在庫が無いと繰り下げになるため Round5 で E 4 本・G 1 本を先に生成する。

## §21 Content / Growth の分離

Content Engine=何を書くか・本人らしいか・数字は正しいか(v5.x + Fact/Voice gate)。Growth Engine=誰向けか・何をさせるか・どの段階か・いつ出すか・結果はどうか(growth_schema + calendar + ledger + snapshot)。Growth 側は本文を書き換えない。Content 側は metadata を読まない(slot 指示で「担当段階・audience・topic_level」だけ渡す)。

## §22 最適化を急がない

40 投稿(4 週)まで比率・型の変更禁止。比較は中央値で、「このアカウントでは」の範囲で書く。IS で良かった設定を即採用しない。

## §23 成果物と実装進捗台帳

| # | 成果物 | 状態 | 実体 |
|---|---|---|---|
| 1 | Growth Engine 設計書 | 済 | 本書 |
| 2-4 | funnel/audience/funnel_stage 定義 | 済 | growth_schema.yaml |
| 5 | topic ladder | 済(投稿側 topic_level。ledger 側は v1 見送り) | 同上 |
| 6 | Reach 素材一覧 | 済(R01-R10、未生成 4) | 同上 |
| 7 | series 設計 | 済(trust_system 9、1/9 割当) | 同上 |
| 8 | Conversation Entry 設計 | 済(実装 v1.1: reply/quote オプション) | §7 |
| 9 | Profile 監査 | 済(改善案は殿裁定待ち) | §11 |
| 10 | Pinned Post 監査 | 済(P3+P1 推奨、殿裁定待ち) | §12 |
| 11 | note Trust Amplifier | 済 | §9 |
| 12 | DM-Signal 導線 | 済(UTM は v1.1) | §10 |
| 13 | KPI schema | 済(取得可否を明示) | §17 |
| 14 | metadata schema | 済+13 本付与 | x_growth_tag.py |
| 15 | X Growth 分析 | 済(3,247 件) | §18/§19 |
| 16 | live OOS ledger | 済(14 entries) | queue/x_live_oos/ledger.yaml |
| 17 | 24h/7d 計測 | 済(cron 毎時、書式実証済み) | x_kpi_snapshot.py |
| 18 | slot_calendar Growth 列 | 済 | slot_calendar.yaml |
| 19 | スクリプト | 済 3 本(+cron 2 本) | x_growth_tag / x_kpi_snapshot / x_slot_post |
| 20 | AsIs/ToBe | 済 | §0 |
| 次 | Round5 生成(Reach 4・E 4・G 1・series 8)、reply/quote 実装、UTM、bio/pinned 裁定 | 未 | — |

### 実装進捗台帳(loop ごとに更新)
- 2026-09-04 15:00 v1.0: schema/tag/ledger/snapshot/slot_post/cron/calendar/分析/監査 完了。live OOS 開始=本日 18:30 slot A。
