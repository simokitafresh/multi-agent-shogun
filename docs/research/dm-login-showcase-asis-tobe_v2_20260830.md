<!-- gist-master: 3236e0dfc698318bfc9d339eaac0cfe5 dm-login-showcase-asis-tobe_v2_20260830.md -->
# DM-Signal /login ショーウィンドウ — AsIs / ToBe 設計書 v2（2026-08-30）

- 版: **AsIs v2.0（本番リアルタイム 2026-08-30 10:10-10:20 JST 実測）/ ToBe v1.0**
- 前版: `docs/research/dm-login-showcase-asis-tobe_20260818.md`（gist 0e15f28f、ToBe v0.3 = ラベル方式）。**前版 ToBe は 1 手も実装されていない**（下記 §1.0）。本版は前版 ToBe を「今の本番」で再検証し、差分を反映した実装可能な版。
- モック: 前版 artifact fa111b2b（正本 `docs/dashboard/dm-signal-login-showcase.html` v13）を継承。本版で変えるのは数値・件数・データ契約・実装順序。
- 原則(前版から継承): ToBe は理想(現実のコード名で縛らない)。AsIs は現物。殿裁定は「事実→制約→判断→効果」で記す。
- 殿指示(10:07): 「asis をリアルタイムの今の本番として、tobe を考えよう」

---

## §0 殿裁定（拘束条件）

| 08-18 | 殿の言葉(要旨) | 効果 |
|---|---|---|
| 15:50 | ログインページがさみしい。誘導したい | /login=門ではなくショーウィンドウ |
| 15:54 | EN+JA(ログイン前)、ログイン後 EN のみ。何のページか不明は UX 害 | 言語規則 §4、明瞭性最優先 |
| 16:00-04 | モバイル=下にシンプルカード+sticky ポップアップ。PC=リッチ sticky カード | レスポンシブ 2 パターン §3.2 |
| 16:07 | Basic-DualMomentum を完全公開に | 未認証で保有まで見せる公開 PF 1 本 |
| 16:08 | inception 以来の total return は興味を引く | 代表 PF の総リターンは未認証公開 |
| 16:32 / 16:56 / 17:23 | 公開=Basic-DM・DM-safe・白虎激攻・分身・四つ目。他は存在のみ。premium も招待制、limited→「Secret」 | 代表 5 行+会員ランク別群行 |
| 17:28 | 「毎営業日」→「月に一回」 | 文言規則 §4 |
| 17:41 | PF 名の下にプランラベル、その下に「+N PF」 | ラベル方式(v13) |

| 08-30 | 殿の言葉(要旨) | 事実→制約→判断→効果 |
|---|---|---|
| 10:20 | メインページにプランの額はいらない。他サービスも入会時に遷移したページに価格を書く。現時点で課金は note 経由 | 事実=課金・価格提示は note メンバーシップ側にある。制約=/login は課金ページではなく、価格を二重管理すると note 側改定時に乖離する。判断=**/login に金額を書かない**。プラン名・PF 数・「Get it on note →」のみ。効果=§2.2-5 と §3.1 ラベルから ¥ を撤去、価格は note リンク先に一本化 |
| 10:21 | https://note.com/dataana2020/n/n17bd615c8f64 を参考にしてくれ(五十嵐「入口を変えただけで会員登録 1.6 倍」) | 事実=記事の結論は『使われない理由は魅力不足ではなく摩擦。効いたのは説明・特典・文言ではなく経路修正(着地ページを変える・ボタンを画面内に入れる)。区間ごとに数えると一箇所が突出して悪く、たいてい思っていた場所と違う。初見ユーザーとしてシークレット窓+スマホで自分で通せ』。制約=/login は未認証の全訪問者が着地する唯一の経路であり、摩擦の有無を今は計測していない。判断=ショーウィンドウ(魅力)より先に**摩擦除去と区間計測**を置く(§2.5)。効果=§5 の順序を P1 計測→P2a 摩擦→P2b ショーウィンドウへ組み替え、P4 を『初見ユーザー実機通し』に変更 |
| 10:41 | 本番を使うから secret 件数に試作 FoF も含めよ。Current signals 表に齟齬がある。パフォーマンスだけ閲覧できるとシグナルまで閲覧できるがごっちゃになっているのでは | 事実=tier 可視性は 3 段(hide_portfolio=パフォーマンス閲覧 / hide_signal=シグナル閲覧 / hide_components=構成閲覧)で、将軍の件数は hide_portfolio=false だけで数えていた(本番実測 10:43: Basic はパフォーマンス 5 本・シグナル 3 本、premium は 28/25)。制約=「+N PF with plan」はシグナルが見える本数として読まれる。判断=**Secret 件数は active かつ非公開の全 PF(FoF 6 本含む)=73 で確定(未決 1 解決)**。**表は「パフォーマンス閲覧」と「シグナル閲覧」を別の段として扱う**。効果=§1.3 に 3 段実測、§2.3 の row に `performance_plan`/`signals_plan`、§3.1 を 2 段ラベルへ書き換え |
| 12:18 | Current signals 表がわかりづらい。Basic-DualMomentum 単体、その後はプラン毎の平均とベストの total performance と ×N 倍、CAGR をレンジで書くのがシンプル | 事実=PF 行を並べる表は 8 行×2 段ラベルで読者が数える必要があった。制約=公開できる数値は tier 設定で決まる集合の集計値(個別 PF の保有・シグナルは出さない)。判断=**表を『Basic-DM 1 行 + プラン集計 3 行 + Secret 1 行』の 5 行にする**。各プラン行= PF 数 / 平均 total return / ベスト total return(PF 名) / ×N(平均・ベスト) / CAGR レンジ。効果=§3.1 を v3(集計方式)へ、§2.3 を plan 集計契約へ、未決 3(表記)は『% と ×N と CAGR レンジを併記』で解決 |
| 12:19-12:20 | シグナルまで公開しているものだけで計算しよう。basic dual momentum / basic plan / standard plan / premium plan / secret の 5 つに分けよう | 事実=プランの集計集合には『パフォーマンスのみ可視』の PF(Basic の白虎激攻・分身常勝、premium の奥義 ×3)を含める余地があった。制約=会員が実際に使えるのはシグナルまで見える PF。判断=**集計集合= hide_portfolio=false ∧ hide_signal=false(シグナル公開 PF)に確定、表は 5 行(Basic-DM / Basic / Standard / Premium / Secret)に確定**。効果=§3.1 v3 の『要殿確認』を撤去、§2.3 `plans[]` の集合定義を固定、AC の独立再計算も同じ集合で |

---

## §1 AsIs（本番リアルタイム 2026-08-30）

### 1.0 前版 ToBe の実装状況 = 0/4 手
| 一次証拠(10:10-10:15) | 結果 |
|---|---|
| Render FE `srv-d4ja8pp5pdvs739a5fsg` 最新 deploy | **live 812f0b7a1 (2026-08-18 06:03)**。08-18 以降 FE deploy なし |
| Render BE `srv-d4ja7q15pdvs739a4q1g` 最新 deploy | live 5a5556af7 (2026-08-23 01:59, Revert cmd_4337) |
| `git diff --stat 812f0b7a1 origin/main -- frontend` | **差分 0**(FE は deploy と完全一致) |
| `git log --since=2026-08-18 -- frontend/app/login …` | 0 commit |
| `grep -rn showcase backend/app` / `/api/public` | **0 件**(公開 EP 未実装) |
| `curl https://dm-signal-frontend.onrender.com/login` | 200、`<title>DM-Signal</title>` のみ(CSR。本文は JS bundle) |

∴ AsIs の画面・境界・言語は前版 §1 と同一(下記 1.1-1.2 は現物再掲)。変わったのは **データ側**(1.3)。

### 1.1 ルート・境界・認証（現物 = origin/main = 本番）
- `/login` = `frontend/app/login/page.tsx`(82 行、`"use client"`)。`RouteAccessBoundary` で `/login` のみ public、他は viewer/admin 認証なしなら `/login` へ replace。
- 認証 `POST /api/auth/verify-viewer`(`backend/app/api/auth.py:21`、rate limit 5/min): `viewer_tiers` 全 tier の `password_env_key` を順に `secrets.compare_digest`、一致 tier の `password_expires_at` が切れていれば **401 "Password expired"**。Legacy `VIEWER_PASS` フォールバックあり。**クーポン専用の分岐はない**(=「クーポンコード」も tier パスワードのいずれかとして照合される)。
- 成功で `viewerAuth.saveToken(token, expires, tier_name)` → `resetAuthScopedClientState()`(7 層リセット) → `replaceLocation("/")`。
- 未認証時のデータ fetch は走らない(第 0 段境界)。**未認証で見せられる動的データは今もゼロ**。

### 1.2 画面（現物）
- `main` 中央寄せ 1 カード(max-w-md): h1「DM-Signal ログイン」/ 説明「note に記載された当月のパスワードもしくはクーポンコードを入力してください。」/ 注意「月次更新のため、現在ブラックアウト中の場合は…お待ちください。」/ label「当月パスワードもしくはクーポンコード」/ `type=password` 入力 / ボタン「ログイン」(loading「確認中…」)。
- エラー文 2 種(JA): 「パスワードもしくはクーポンコードが正しくありません。」「認証に失敗しました。しばらくしてからお試しください。」
- 言語 JA のみ、i18n 基盤なし(`next-intl`/`i18next` 依存 0)。価値提示・導線・EN なし。

### 1.3 データ・可視性（本番 DB readonly 実測 10:14-10:18、`db_capability_launcher.py readonly_query`）

集計: `viewer_tiers × tier_visibility_settings × portfolios(is_active)` で `hide_portfolio=false` を COUNT。1 件 = is_active PF でその tier に可視な 1 本。

| tier(DB) | note プラン | 可視 PF | 08-18 比 |
|---|---|---|---|
| Basic | ベーシック(初月無料) | **5** | ±0(DM-safe・GSシン分身-常勝・シン白虎-激攻・Basic-DualMomentum・Ave-X) |
| NewStandard | スタンダード | **17** | ±0 |
| Standard(古参) | 非公開 | 22 | ±0 |
| AddOn | 裏Ave7 非公開 | 22 | ±0 |
| premium | ドクタープレミアム 招待制 | **28** | **+1** |
| どの tier にも出ない(Secret) | — | **73** | **+3** |
| is_active 合計 | | **102** | **+4**(98→102) |

**3 段の可視性(本番実測 10:43。1 件=is_active PF で hide_portfolio=false ∧(段ごとに)hide_signal=false / hide_components=false)**

| tier | パフォーマンス閲覧 | シグナル閲覧 | 構成(components)閲覧 |
|---|---|---|---|
| Basic | 5 | **3**(Basic-DM・DM-safe・Ave-X) | 1(Basic-DM) |
| NewStandard | 17 | 17 | 1 |
| Standard(古参) | 22 | 14 | 0 |
| AddOn | 22 | 18 | 0 |
| premium | 28 | **25**(奥義-GS-分身 ×3 はパフォーマンスのみ) | 1 |

- Basic でパフォーマンスのみ=シン白虎-激攻・GSシン分身-常勝(hide_signal=true)。この 2 本のシグナルは Standard から。
- premium でパフォーマンスのみ=奥義-GS-分身-常勝/激攻/鉄壁。
- 構成(components)が見えるのは全 tier で Basic-DualMomentum の 1 本だけ。

- premium 専用(NewStandard/Basic 非可視)10 本の現物: DM-safe-2 / GSシン四つ目-常勝・激攻・鉄壁 / 劇薬DMオリジナル・スムーズ / 奥義-GS-分身-常勝・激攻・鉄壁 / 裏Ave-X。加えて Ave-X(Basic 可視・NewStandard 非可視)も premium で再可視。∴ premium で新たに見える 11 本 = 代表 GSシン四つ目-常勝 1 + 群 10(前版「+10」と同値)。
- **新規 active 3 本(08-19 作成、folder「オリジナル」)**: Sharpe4 / CAGR4 / greedy2 — いずれも `type=fof`、`pipeline_config`=EqualWeight・selection blocks 0(=固定構成の等ウェイト FoF)、構成は全て**秘奥義** PF: Sharpe4={加速D-激攻, 加速R-鉄壁, 追い風-激攻, 四つ目-鉄壁}×25%、CAGR4={加速D-激攻, 四つ目-激攻, 追い風-激攻, 抜き身-激攻}×25%、greedy2={加速R-鉄壁, 追い風-激攻}×50%。weights 最新 08-03、metrics 2 行(years=0 total_return: CAGR4 15,907 / greedy2 8,373 / Sharpe4 3,279 = 秘奥義 EW-FoF)、可視 tier 0=Secret 群。同じく `New Fund of Funds`(+`_copy`/`_copy_copy`、07-01)={秘奥義-加速D-激攻, 奥義-GS-抜き身-激攻} EW、可視 tier 0。名前は選定基準(Sharpe 上位 4/CAGR 上位 4/greedy 2)そのまま=**殿が admin で組んだ秘奥義 FoF と見られる**(誰が何の目的で作ったかは DB に記録なし → §6 未決 1 は「これらを Secret 件数に含めるか」)。
- **Basic-DualMomentum の tier フラグ**: Basic/NewStandard/premium = 全 false(公開可)、**Standard(古参)/AddOn = hide_portfolio=true, hide_components=true**。前版 ToBe「全 tier で false を保証」は**未達**(古参 2 tier)。公開 EP は tier 非依存なので画面には影響しないが、古参会員がログイン後に Basic-DM を見られない不整合として §6 未決 2。
- **総リターン(since inception)の現物**: `portfolio_metrics(years=0).metrics_json.total_return` = `(1+monthly).prod()-1`(`metrics_impl.py:1386`)= **倍率ではなく「+○○ 倍相当の小数」**(0.31=+31%、31.39=**+3,139%**)。calculated_at=2026-08-29、end_date=**2026-07-31**(月次系列。8 月末クローズ後に更新)。

| PF | total_return | start_date | 表示例(×100 %) |
|---|---|---|---|
| Basic-DualMomentum | 31.39 | 2003-09-30 | +3,139% (275 か月、bench +1,023%) |
| DM-safe | 14.11 | 2006-01-31 | +1,411% |
| GSシン分身-常勝 | 109.82 | 2012-04-30 | +10,982% |
| Ave-X | 113.21 | 2012-04-30 | +11,321% |
| GSシン四つ目-常勝 | 171.81 | 2012-10-31 | +17,181% |
| シン白虎-激攻 | 756.19 | 2010-10-31 | +75,619% |

  → 4〜5 桁 % は「餌」として強いが**信憑性を損なう**懸念(§6 未決 3: CAGR 併記 or 「×N」倍率表記)。`cagr` は years=0 行では **null**(別 years 行にのみ存在)。
- **ブラックアウト状態(今)**: 5 tier とも `password_expires_at=2026-08-31`、`last_rotated_at=2026-08-03`。∴ **明日 08-31 に失効 → 9 月パスワード配布までブラックアウト**。/login のブラックアウト注意文は今週まさに出番。EN/JA 併記(§4)の優先度が高い。
- `signals` 列: portfolio_id / date / signal / holding_signal / momentum_data(json) / created_at / updated_at。Basic-DM の「今月の保有」= `holding_signal`、モメンタム= `momentum_data`。
- 導線 URL の現物(`marketing-director/marketing-info.md` L507-508): note https://note.com/tokyojibika 、メンバーシップ https://note.com/tokyojibika/membership 。

---

## §2 ToBe v1.0（理想。前版 v0.3 を今の本番で再構成）

### 2.1 目的（不変）
未認証訪問者が **(a) 何のサービスか (b) どこからログインするか (c) なぜ会員になるか** をスクロールなしで理解し、ログイン後の体験(EN・保有シグナル)へ最短で進む。ブラックアウト週(毎月末〜配布日)にも「待てば入れる/note で取れる」が一目で分かる。

### 2.2 情報構造（上から。前版 2.2 継承）
1. ブランド行: "DM-Signal" + "Dual Momentum signals · rebalanced once a month"
2. H1 "What to hold this month — computed, not guessed." / JA「今月、何を保有すべきか。月に一回、ルールで自動計算。」
3. リード 1 段落(EN。月末クローズで月 1 回リバランス・20 年超の月次実績・ルールベースで再現可能)
4. **Current signals 表**(§3.1、ラベル方式 v13)
5. プラン 3 枚(**金額なし・殿裁定 10:20**): Basic(PF 5・first month free) / Standard(PF 17) / Premium(by invitation)。各カードは「See plans on note →」(membership URL)で価格へ遷移。Coupon は独立カードにせず、サインインカードの補足 1 行(「Have a coupon? Use it here」)
6. 導線 4 本: What is Dual Momentum?(note JA) / Join on note(membership) / Weekly report / @TokyoJibika
7. サインインカード(§3.2)
8. フッタ: © / Not investment advice / Data: monthly close, US ETFs

### 2.3 公開データ契約 `GET /api/public/showcase`（認証不要・tier 非依存・cache 1h）
- `as_of`: {series_end: "2026-07-31", next_close: "2026-08-31", calculated_at}
- `blackout`: {active: bool, until_hint: "early September"} ← `viewer_tiers.password_expires_at` の max から算出(**数値のみ。パスワードや env key は決して返さない**)
- `hero`: Basic-DualMomentum 1 本 `{name, holding, momentum, components, total_return, multiple, cagr, inception, benchmark_total_return}`(完全公開)
- `plans[]`(basic / standard / premium の順): `{plan, n, avg_total_return, best_total_return, best_name, avg_multiple, best_multiple, cagr_min, cagr_max}` ← 集合= hide_portfolio=false ∧ hide_signal=false(§3.1)。**個別 PF の holding/momentum は返さない**(best_name のみ)
- `secret`: `{count: 73}` ← active 102 − premium performance 28 − Ave-X(Basic のみ)1(殿裁定 10:41、FoF 6 本含む)
- 出所: `portfolio_metrics(years=0)`, `signals`(Basic-DM 最新 date), `tier_visibility_settings`, `viewer_tiers.password_expires_at`。**新規テーブル不要**。count は EP 内で導出(フロントに固定値を書かない)。
- 非送信の原則: 代表 4 行の保有/モメンタムはフロントがぼかしバーを描く(データは来ない)。

### 2.4 サインイン
- API 変更なし。入力 1 本のまま。
- 失敗時: 401 "Password expired" を **「This month's password has expired ／ 当月パスワードは失効しました」+ blackout 案内**、その他 401 は現行文の EN+JA 化。
- ブラックアウト中(`blackout.active`)はカード上部に帯「Blackout until early {month} — new password on note ／ ブラックアウト中」。

### 2.5 摩擦優先の原則（殿参照 10:21 の記事を本設計への拘束に変換）
「摩擦を取る → それから魅力を足す」。/login の摩擦候補を先に潰し、区間で数えてから餌(§3.1 表)を足す。
| # | 摩擦候補(AsIs 現物) | 対処(ToBe) | 計測区間 |
|---|---|---|---|
| F1 | 未認証で `/` 等に来た人は `RouteAccessBoundary` が `/login` へ replace。着地までの空白フレーム(白画面)の有無・秒数を計測していない | 着地前の空白 0 フレームを AC(SSR で /login を即描画、または boundary の判定を同期化) | `/` 到達 → `/login` 描画 |
| F2 | モバイルで入力+ボタンが初期 viewport 内にあるか未確認(現物は中央 1 カード=たぶん見えるが、ショーウィンドウを上に積むと**確実に画面外へ出る**) | ≤860px は下部 sticky バー「Sign in」を**初期表示から常時**出す(§3.2 のボトムシート)。ボタンは常に画面内 | /login 描画 → 入力 focus |
| F3 | ブラックアウト中も「正しくありません」と同文で返る(auth.py 401 の detail を画面が読まない) | 失効 401 は専用文+「note で 9 月分を取る →」リンク(§2.4) | 送信 → 401 expired / 401 wrong / 成功 |
| F4 | パスワードは note の記事内にあり、/login からその記事へ 1 タップで行けない | サインインカードに「This month's password is on note →」(membership URL) | /login → note 遷移 |
| F5 | 言語 JA のみ(EN 読者は入口で詰む) | EN 主・JA 従(§4) | — |
- **区間計測(P1 と同時)**: `POST /api/public/showcase/event`(認証不要・body={step, ua_class, ts}、step ∈ {login_view, input_focus, submit, ok, expired, wrong, note_click})を 1 日分だけ集計して `logs`/DB 1 表に落とす。**「どこで消えているか」を数字で出してから**§3.1 の魅力側を最適化する。
- **初見ユーザー通し(P4)**: シークレット窓 × スマホ実機 × PC の 2 経路で「未認証で `/` に来る → /login → note でパスワードを見る → 戻って入力 → `/`」を殿自身と将軍(CDP モバイル幅)が通す。ボタンが画面外だった瞬間を 0 件にする。

---

## §3 画面仕様

### 3.1 Current signals 表 — 集計方式 v3（殿 12:18: Basic-DM 単体 + プラン毎の平均/ベスト/×N/CAGR レンジ）
5 行で完結。個別 PF 名は Basic-DM とベスト PF 名以外出さない。数値は本番 `portfolio_metrics(years=0)` から EP が集計(12:20 実測、series end 2026-07-31)。

| 行 | 対象 | Total return(平均 / ベスト) | ×N(平均 / ベスト) | CAGR レンジ | 保有・シグナル |
|---|---|---|---|---|---|
| **Basic-DualMomentum** | 1 本・完全公開(2003-09〜) | +3,139%(bench +1,023%) | ×32 | 16.4% | **表示**(holding / momentum / 構成) |
| **Basic plan** | signals 3 PF | +5,290% / +11,321%(Ave-X) | ×54 / ×114 | 14.1% 〜 39.2% | Sign in で表示 |
| **Standard plan** | signals 17 PF | +22,047% / +77,078%(シン白虎-鉄壁) | ×221 / ×772 | 14.1% 〜 52.2% | Sign in で表示 |
| **Premium plan** · by invitation | signals 25 PF | +23,725% / +106,789%(GSシン四つ目-激攻) | ×238 / ×1,069 | 14.1% 〜 68.7% | 招待制 |
| **Secret** | 73 PF | Not disclosed | — | — | Not viewable |

- 集合の定義(殿裁定 12:19): 各プラン行は**そのプランでシグナルまで公開している PF**(hide_portfolio=false ∧ hide_signal=false)だけで計算する。パフォーマンスのみ可視の PF(Basic の白虎激攻・分身常勝、premium の奥義 ×3)は集計に入れない(参考: 入れると Basic 平均 +20,494%/premium ベスト +365,962% まで跳ね、実際に使える数字と乖離する)。行構成は 5 つ(Basic-DM / Basic / Standard / Premium / Secret)に確定(殿裁定 12:20)。
- CAGR の算出: `(1+total_return)^(12/period_months)-1`(years=0 行に `cagr` がないため EP で算出)。period は 160〜275 か月(2003〜2013 起点)。
- 平均は単純平均(PF 数で割る)。中央値ではない(殿の言葉「平均」に従う)。
- 表題は "Current signals" のまま、副題 "Performance since inception, by plan"。
- **齟齬の再発防止(AC)**: 未認証 curl の各 plan 行の n/avg/best/×N/cagr_min/max を、DB から独立に再計算した値と全行一致(二値)。集合の定義(hide_portfolio ∧ hide_signal)を EP とテストの両方に同じ 1 関数で置く。
- ヘッダ右: "Series through {series_end} · next rebalance {next_close} close"。「today/毎営業日」禁止。

### 3.2 レスポンシブ 2 パターン（前版継承）
- >860px: 2 カラム(左ショーウィンドウ / 右 sticky リッチカード)。
- ≤860px: 1 カラム + 末尾シンプルカード + 下部 sticky バー「Sign in ／ ログイン」→ボトムシート(×/背景/Esc、safe-area、focus)。
- `<SignInCard variant="rich"|"simple">` 1 コンポーネント 2 インスタンス。

### 3.3 見た目（前版継承）
- `globals.css` 既存トークンのみ(primary #0369a1、slate、ダーク対応)。最も濃い塗り=「Sign in」ボタンのみ。装飾・ヒーロー画像なし。

---

## §4 言語・文言規則（前版継承 + 追加 2 条）
- ログイン前 EN 主・JA 従(`.ja` 小字)。ログイン後 EN のみ(範囲外)。
- 頻度: once a month / this month。「毎営業日」「today」禁止(grep 0 件が AC)。
- **金額禁止(殿裁定 10:20)**: /login に ¥・価格・「¥1,000」等の金額を書かない(grep `¥|円|yen` 0 件が AC)。価格は note membership ページへのリンクで示す。
- **追加 1**: 総リターンは `Intl.NumberFormat` で桁区切り、符号付き、%(小数なし)。**追加 2**: ブラックアウト帯・失効エラーは EN+JA 必須(今週から実需)。

---

## §5 実装単位（小さく 1 層ずつ・可逆・儀式なし。順序=摩擦→計測→魅力）
| 手 | 内容 | 二値 AC |
|---|---|---|
| P0 | 殿裁定(§6-1 試作 FoF・§6-3 数値表記) | §6 に事実→制約→判断→効果で記載済み |
| P1 | backend: `GET /api/public/showcase`(read-only・cache 1h・tier 非依存・password 系非送信)+ `POST …/showcase/event`(区間計測) | 未認証 curl: free 行に holding/momentum あり・basic 4 行に**キーなし**・count(4/13/10/secret) が DB 集計と一致・レスポンスに `password`/`env` 文字列 0 件・event 7 step が 1 表に落ちる |
| P2a | frontend 摩擦除去: モバイル sticky「Sign in」バー+ボトムシート、失効 401 専用文+note リンク、EN/JA、着地空白 0 フレーム(§2.5 F1-F5) | 375×667 で初期 viewport にボタンあり・失効時に専用文・`/`→`/login` の白画面 0 フレーム(CDP screencast) |
| P2b | frontend ショーウィンドウ: §2.2 構造+§3.1 表(データは P1) | 860px 切替・既存ログイン成功経路が従来どおり(7 層リセット→`/`) |
| P3 | 文言・導線 URL を設定値化、金額ゼロ | 「毎営業日/today」grep 0、`¥|円|yen` grep 0、note URL 直書き 0 |
| P4 | 初見ユーザー通し(§2.5)+本番 CDP 2 枚 | 殿実機(シークレット×スマホ)で「ボタンが画面外」0 件、将軍 CDP モバイル幅 1 枚+PC 1 枚 |
- push/deploy は家老レーン(FE は 08-18 以来 deploy なし=本版が次の FE deploy)。P1 は read-only 新 EP+追記専用 event で本番書込み最小。P2 以降 revert 可。
- 1 週間後に event 集計で「突出して悪い区間」を 1 つ特定し、そこだけを次弾にする(記事の教え: たいてい思っていた場所と違う)。

## §6 未決（殿裁定待ち。裁定は「事実→制約→判断→効果」で追記）
1. (解決 10:41 殿裁定)**Secret 件数=73 で確定(FoF 6 本含む。「本番を使う」)**。以下は経緯:  事実=Secret 73 のうち 6 本は folder「オリジナル」の等ウェイト FoF(Sharpe4/CAGR4/greedy2 08-19、New Fund of Funds ×3 07-01。構成は秘奥義 PF、metrics・signals 計算済み、可視 tier 0)。`is_active`・metrics 有無では他の Secret PF と区別できない。案 A=そのまま 73(「存在する PF 数」として正しい。秘奥義 FoF も Secret の一部)/ 案 B=殿が「これは正式 PF ではない」と判断するものだけ admin で `is_active=false` にして件数から自然に外す(データ側の整理、可逆)/ 案 C=EP に除外名リスト(非推奨・固定値)。将軍推奨=**A**(件数の定義を『active かつ非公開の PF 数』で固定し、画面ロジックに例外を持ち込まない。整理したい PF があれば B を殿が個別に)。
2. **Basic-DM の古参 tier(Standard/AddOn)で hide_portfolio=true**: 公開 PF なのにログイン後の古参会員に非表示。案=admin で 2 tier を false に(可逆・DB 設定変更のみ)。
3. (解決 12:18 殿裁定)**表記= total return(%)・×N 倍・CAGR レンジの併記(§3.1 v3)**。以下は経緯:  事実=since inception が +3,139%〜+75,619%(白虎)。案 A=% のまま(餌として最強)、案 B=「×32 / ×757」倍率、案 C=CAGR 併記(years=0 に cagr なし → EP で `(1+tr)^(12/months)-1` を算出)。将軍推奨=**C**(信憑性を保ちつつ interest を引く)。
4. 群行 "up to X%" を Standard/Premium で出すか(前版から継続)。
5. Coupon 説明「note 不要」の正確性(1.1 の通り auth.py にクーポン分岐はない → クーポン=別 env key の tier パスワードか、Legacy `VIEWER_PASS` か要確認)。

## §7 因果リンク
- [[殿観測_ログインページさみしい_20260818_1550]] -> [[login_showcase_mock_v1-v11]] -> [[dm-login-showcase-asis-tobe_20260818]](ToBe v0.3・未実装) -> [[殿指示_asis本番リアルタイム化_20260830_1007]] -> **[[dm-login-showcase-asis-tobe_v2_20260830]]** <- [[殿裁定_login金額なし_20260830_1020]] / [[殿参照_摩擦優先_note_dataana2020_20260830_1021]]
- ← [[dm-login-boundary-asis-tobe_20260817]](第 0 段) / [[tier別可視性完成形]](cmd_3837) / [[visibility_philosophy]](projects/dm-signal.yaml)
- 一次証拠: Render deploys API(10:10)、`git diff 812f0b7a1 origin/main`、readonly_query 7 本(10:14-10:18)、`metrics_impl.py:1386`、`auth.py:21-70`
