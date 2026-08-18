# DM-Signal /login ショーウィンドウ — 殿の要望記録

- artifact: https://claude.ai/code/artifact/fa111b2b-9ac4-44b9-9d4c-0c0d4581774c
- 正本HTML: `docs/dashboard/dm-signal-login-showcase.html`
- 現状(AsIs): `frontend/app/login/page.tsx`(82行。見出し+2文+入力+ボタンのみ、cmd_4325/4332で第0段として稼働)
- 関連: ログイン境界設計書 `docs/research/dm-login-boundary-asis-tobe_20260817.md`(gist 0d23e0c3)

## 殿の要望(時系列・原文要旨)

| 時刻(JST) | 殿の言葉 | 読み取った原理 |
|---|---|---|
| 08-18 15:50 | 「ログインページを作成したがさみしすぎないか？DM-signalにユーザーを誘導する方法を教えてくれ」 | ログイン画面=門ではなくショーウィンドウ。未認証者に価値と導線を見せる |
| 15:54 | 「基本は英語ベース。ログインページはショーウィンドウとして英語＋日本語、ログイン後は基本英語のみ」「よくあるおしゃれなページはどこからログインしていいか、これが何のページかわからない。UXを害する」 | EN主・JA従。**何のページか/どこからログインするかが一目で分かる**ことが最優先。装飾より明瞭 |
| 15:59 | 「もう少し現状に合わせよう」 | 未実装(ゲストtier・無料PF)を描かない。実プラン(Basic ¥1,000初月無料/Standard ¥8,000/Coupon)・実ラインナップ・実導線のみ |
| 16:00 | 「レスポンシブの時のサインインのカードは下のほうに表示＋カード自体の表示もシンプルなほうがいい」 | モバイルはショーウィンドウ優先、カードは簡素(見出し+入力+ボタン+note1行) |
| 16:02 | 「サインインはポップアップでstickyがいい」 | ログイン入口は常時追従(sticky)+ポップアップ |
| 16:03 | 「レスポンシブの時はシンプルなカード、PCやタブレットでは元のリッチな情報の2パターンがいい」 | 2パターン: PC/タブレット=リッチsticky カード(ページ内)、モバイル=シンプル |
| 16:04 | 「レスポンシブの時は下にシンプルなカード＋stickyなポップアップだ。おれの希望などを随時記録してどう変えていったかを記録してくれ」 | モバイル=ページ下部にシンプルカード**かつ**sticky ボタン→シンプルポップアップの両方。要望と変更を本ログに随時記録 |

## v1-v9 — 2026-08-18 15:57-16:58 JST

| 版 | 時刻 | 変更 | 対応する要望 |
|---|---|---|---|
| v1 | 15:57 | 2カラム(左ショーウィンドウ/右sticky リッチカード)。無料PF2本表示+ゲストボタン(仮) | 15:50/15:54 |
| v2 | 15:59 | ゲスト/無料PF撤去、全50本マスク、実プラン3種、実導線(noteマガジン/メンバーシップ/週報/@TokyoJibika)、初月無料1行 | 15:59 |
| v3 | 16:00 | モバイル: カードを下に自然順、非sticky。カード簡素化(説明/ブラックアウト箱/影を削除) | 16:00 |
| v4 | 16:02 | 1カラム化+上部sticky バー(PC)/下部sticky バー(モバイル)→モーダル(ボトムシート) | 16:02 |
| v5 | 16:03 | 2パターン化: >860px=2カラム+リッチsticky カード(ページ内)、≤860px=下部sticky ボタン→シンプルポップアップ。同一asideを`.rich`クラスで出し分け | 16:03 |
| v6 | 16:05 | モバイル: ページ末尾にシンプルカードをインライン表示**+**下部sticky ボタン→シンプルポップアップ(aside 2枚目、id分離) | 16:04 |

## 現時点の仕様(v6)
- 言語: EN主、JAは各英文直下に小さく従属。ログイン後はEN。
- >860px: 左=ブランド+H1+リード+Today's signals(全マスク)+プラン3枚+導線4本 / 右=sticky リッチカード(見出し・説明EN/JA・入力・ボタン・ブラックアウト注意・note導線・初月無料)。
- ≤860px: 上記ショーウィンドウ→末尾にシンプルカード(見出し・入力・ボタン・note1行) + 下部sticky「Sign in ／ ログイン」→ボトムシート型シンプルカード。
- トークンは`frontend/app/globals.css`(primary #0369a1・slate系)を継承。ダーク対応。

## 未決・次段
- Today's signals更新時刻/件数は実装時に`/api/signals`メタから取得。
- ゲスト(L1)は現状未実装のため載せていない。載せるなら別段。
- 実装は設計書(AsIs=page.tsx / ToBe=本モック)化→ログイン境界第0段の手④として起票。

## 追記 16:07-16:10
| 時刻 | 殿の言葉 | 読み取った原理 |
|---|---|---|
| 16:07 | 「無料で公開できるものがあったほうがいいな。Basic-DualMomentumを完全公開用としようか。あとはDM-safe、L1,L2,L3はどうする」 | 無料の完全公開PFを1本置く=餌。他階層の公開度は将軍が案を出し殿が裁定 |
| 16:08 | 「inceptionからのtotal returnは見えたほうが興味を引くね」 | 保有(価値の核心)は隠し、総リターン(餌)は全PFで見せる=visibility_philosophy vis_L3の思想 |

| v7 | 16:10 | 表を「Basic DM=保有+モメンタム+総リターン全公開(Freeタグ)」「他PF=保有/モメンタムはマスク、inception以来総リターンは公開」へ。行はDM-safe/L0四神/L1忍法/L2奥義+L3秘奥義FoFの階層表記。数値はダミー(実装時API) | 16:07/16:08 |

## 追記 16:32
| 時刻 | 殿の言葉 | 読み取った原理 |
|---|---|---|
| 16:32 | 「L1忍法はstandardプランは分身のみだね。basic,DM-safe,四神から白虎激攻、忍法から分身、四つ身、その他は秘匿かな存在のみ」 | **殿裁定(公開階段)**: 公開=Basic DM(完全)・DM-safe・シン白虎-激攻・シン分身・シン四つ目(殿表記「四つ身」)は総リターン公開/保有マスク。その他は存在(件数)のみ。Standardプランで見えるL1忍法は分身のみ |

| v8 | 16:34 | 表を殿裁定どおり5本+「+45 more (Members only)」行へ。階層別レンジ行は撤去 | 16:32 |

## 追記 16:56
| 時刻 | 殿の言葉 | 読み取った原理 |
|---|---|---|
| 16:56 | 「standard member only, premium member only, 更にlimited member onlyがあると餌としておくのは？」 | 秘匿PFを一括「会員限定」ではなく会員ランク別に存在を見せ、上位ほど希少(招待制)に。餌の階段化 |

| v9 | 16:58 | 「+45 more」1行を3行へ分割: Standard members only(四神・忍法 +18・上限リターン表示)/Premium members only(奥義・秘奥義 +15・上限リターン表示)/Limited members only・招待制(FoF +12・数値非表示)。件数・数値はダミー | 16:56 |

## 追記 17:24 — 本番tier実データ突合(殿「tier別のデータあるだろ？ちゃんと確認してくれ」)
- 集計コマンド: `db_capability_launcher.py readonly_query`で `viewer_tiers × tier_visibility_settings × portfolios(is_active)`をhide_portfolio=falseで集計(2026-08-18 17:26 JST)
- 出力行(生): Standard(古参¥4,000) 22 / premium 27 / AddOn 22 / Basic 5 / NewStandard(スタンダード¥8,000) 17 / active合計 98
- 1件の定義: is_active PFでそのtierのhide_portfolio=false 1本
- Basic 5本 = DM-safe・GSシン分身-常勝・シン白虎-激攻・Basic-DualMomentum・Ave-X
- NewStandard 17本 = Basic-DM・DM-safe・GSシン分身×3(常勝/激攻/鉄壁)・シン四神×12(白虎/朱雀/玄武/青龍×常勝/激攻/鉄壁)。**Ave-XはBasicで可視だがNewStandardでは非表示**(要確認: 意図か設定漏れか)
- premium 27本 = 上記16(Basic-DM除く)+Ave-X・裏Ave-X・DM-safe-2・GSシン四つ目×3・劇薬DM×2・奥義-GS-分身×3
- どのtierにも出ない = 70本
- 殿裁定17:23: premiumも招待制、limitedは「Secret」表記
| v10 | 17:28 | 表を実データへ: 代表5行(Basic-DM/DM-safe/白虎激攻/分身常勝/四つ目常勝)+「+13 Standard members only(四神11・分身2)」「+10 Premium members only · by invitation(四つ目2・奥義分身3・Ave-X・裏Ave-X・DM-safe-2・劇薬2)」「+70 Secret」。件数は実測、リターン値はダミー。プランカードにも実PF構成を記載 | 17:23 |

## 追記 17:28
| 時刻 | 殿の言葉 | 読み取った原理 |
|---|---|---|
| 17:28 | 「今日、何を保有すべきか。毎営業日、ルールで自動計算、の文言は毎月リバランスにはふさわしくないね。毎営業日→月に一回がいいな」 | 製品の本質は月次リバランス。「毎日見る」印象を与えない。日次再計算(内部)と月次リバランス(ユーザー体験)を混同しない |

| v11 | 17:29 | 文言を月次へ: H1「What to hold this month」/JA「今月、何を保有すべきか。月に一回、ルールで自動計算」/ブランド副題「rebalanced once a month」/リード「rebalances once a month at month-end close…no daily watching」/表ヘッダ「Current signals · Rebalanced 2026-07-31 close · next 2026-08-31」 | 17:28 |

## 追記 17:30-17:38
| 時刻 | 殿の言葉 | 読み取った原理 |
|---|---|---|
| 17:30 | 「実際のページを作るときに必要になる情報は設計書のほうに会話とともに随時記載しているか？」 | ログ(要望履歴)だけでは実装できない。AsIs/ToBe設計書を新設し会話→拘束を§0に随時反映する |
| 17:36 | 「current signalsのところは無料お試し、basic plan, standard plan, premium plan, secretでゾーン分けしたほうがいいね」 | 表をプラン階段そのものにする=見ながら「どこまで払えば何が見えるか」が分かる |

- 設計書新設: `docs/research/dm-login-showcase-asis-tobe_20260818.md`(AsIs v1.0/ToBe v0.1: 境界・API・公開データ契約`GET /api/public/showcase`・tier実測・レスポンシブ仕様・文言規則・実装単位P1-P4・未決)
| v12 | 17:38 | 表を5ゾーンへ: Free trial(Basic-DM完全公開)/Basic plan(DM-safe・白虎激攻・分身常勝・Ave-X=総リターン公開)/Standard plan(+13群行)/Premium plan 招待制(四つ目常勝+9群行)/Secret(+70)。ゾーン見出し行にプラン名+価格 | 17:36 |
| 17:41 | 「それかBasic-Dualmomentumの下のラベルみたいにするといいな。ラベルを下に、その下に追加で見られるPF数を＋２１PFみたいに表示」 | ゾーン見出し行ではなく、各PF名の下にプランラベル+「+N PF」。行単位で「このプランで保有が見える・さらにN本増える」が読める |
| v13 | 17:43 | ゾーン行を撤去。各行=PF名／プランラベル(Free trial=緑・Basic・Standard・Premium 招待制=紫・Secret=灰)／各プラン先頭行に「+N PF with {plan}」(Basic +4・Standard +13・Premium +10・Secret=Not viewable) | 17:41 |
