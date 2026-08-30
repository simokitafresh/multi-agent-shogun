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
| 12:30 | 一番下に比較として S&P500 指数(SPY)と TQQQ を入れよう。Sharpe ratio も同じように入れよう | 事実=metrics_json.metrics に『Sharpe Ratio』(Rf 控除・年率、`metrics_impl.py:977-983`)が全 PF にあり、`ticker_monthly_returns` に SPY(1993-01〜)・TQQQ(2010-02〜)がある。制約=比較の期間を揃えないと数字が意味を持たない(TQQQ は 2010 年起点)。判断=**表に Sharpe 列(プラン行は平均/ベスト)を追加し、最下段に SPY・TQQQ の比較 2 行**を置く。SPY は Basic-DM と同じ 2003-10〜、TQQQ は自身の 2010-03〜(各行に期間を明記)。効果=§3.1 v3 に Sharpe 列+比較 2 行、§2.3 に `benchmarks[]` と `sharpe_avg/best`、cmd_4413 は発令済みのため追補を別 cmd(P1b)で出す |
| 12:32 | secret の数値も入れよう | 事実=Secret 73 本は全て metrics(years=0)あり(12:35 実測: 平均 +535,294%・ベスト +5,405,515%(秘奥義-追い風-激攻)、×5,354/×54,056、CAGR 10.5%〜153.1%、Sharpe 平均 1.71/ベスト 2.48(Sharpe4)、期間 105〜196 か月)。制約=名前・保有・シグナルは非公開のまま。判断=**Secret 行にも集計値(平均/ベスト/×N/CAGR レンジ/Sharpe)を出す。ベスト PF 名は出さない**(Secret の存在は数字で示し、正体は伏せる)。効果=§3.1 Secret 行を数値化、§2.3 `secret` に集計フィールド、best_name は null |
| 12:46 | MDD も追加しよう | 事実=metrics に『Maximum Drawdown』(close.portfolio/benchmark)が全 PF にある(12:47 実測: Basic-DM −41.0%、Basic 平均 −36.5%/最浅 −23.3%(DM-safe)、Standard −47.0%/−22.8%(GSシン分身-鉄壁)、Premium −44.1%/−21.2%(GSシン四つ目-鉄壁)、Secret −29.9%/−9.8%、SPY 2003-10〜 −52.9%(Basic-DM 行の benchmark 値と一致)、TQQQ 2010-03〜 −80.1%)。制約=リターンだけの表は片面。判断=**MDD 列(プラン行は平均 / 最浅)を追加**。効果=§3.1 に MDD 列、§2.3 に `mdd_avg/mdd_best`、benchmarks に `mdd`。cmd_4414 は未配備(4413 CLEAR まで保留)のため void し、MDD 込みの cmd_4415 に差し替える |
| 12:48 | 表内にベストの PF 名は不要。期間の注釈は表外に小さく英語表記。平均とベストは『平均〜ベスト』(『/』ではなくレンジの『〜』) | 事実=表内の PF 名(Ave-X 等)と期間注記が行を長くし、『/』は比率にも読める。制約=公開できるのは集計値のみ(PF 名は Basic-DM 以外出さない)。判断=**全プラン行の値は『平均 〜 ベスト』のレンジ表記、PF 名なし、期間は表外の英語脚注**。効果=§3.1 表を書き換え、§2.3 の `best_name`/`sharpe_best_name`/`mdd_best_name` を契約から削除(hero の name のみ) |
| 12:49 | Sharpe と MDD は平均は不要。ベストだけでいい | 事実=Sharpe/MDD の平均はプラン内のばらつきで薄まり、読者が使うのはベスト値。判断=**Sharpe 列=ベスト(最大)、MDD 列=ベスト(最浅)の単値。レンジ表記は Total return/×N/CAGR の 3 列のみ**。効果=§3.1 表と §2.3 契約から sharpe_avg/mdd_avg を削除 |
| 12:54 | ログイン画面の数値データはリアルタイム更新(daily)にできるか？期間を明記して static にしたほうが SEO やユーザー動線としてベターか？ | 事実=①数値の出所 `portfolio_metrics(years=0)` は毎日再計算される(12:55 実測 calculated_at=2026-08-30 が 101 行)が、系列は月末クローズ基準で end_date=2026-07-31 のまま=**数字が動くのは月 1 回(月末クローズ翌日)**。②現行 /login は `"use client"` の CSR で、本番 HTML は `<title>DM-Signal</title>` のみ(12:11 curl)。robots.txt/sitemap/metadata なし=**検索エンジンには空ページ**。制約=daily 更新にしても表示値は月内不変。判断=**両立させる: サーバー側で HTML に数値を焼き込む ISR(revalidate 24h+月末再計算後の on-demand revalidate)+『Data through 2026-07-31』の期間明記**。訪問者には static に見え、実体は EP から毎日自動再生成。効果=§2.6 描画・更新方針を新設、P2b の AC に『初回 HTML に数値が含まれる(curl で表の数値が HTML 本文に存在)』『as_of の月末日が表外脚注に出る』を追加 |
| 12:58 | ブラックアウトはどう表現する。note に誘導+パスワード発表をお楽しみにという期待感をあおるのがいいか？発表日時は俺が任意で決めているので具体的にしたくない | 事実=ブラックアウトは『月末で旧パスワード失効〜殿が note で新パスワードを発表するまで』で、発表時刻は固定されていない(viewer_tiers は expires_at=月末と last_rotated_at しか持たない)。制約=日時・カウントダウン・『early September』のような時期の示唆も出さない。判断=**ブラックアウト帯は『新しい月のシグナルは計算済み。パスワードは note で発表』の期待感+note 誘導のみ。日時表現ゼロ**。状態判定は `max(password_expires_at) < today ∧ last_rotated_at ≤ expires_at`(=まだ配布されていない)。効果=§2.4 を書き換え、EP `blackout` から `until_hint` を削除し `{active, month_closed}` に |
| 13:04 | ログインページは単独でログイン後の本番には影響しないよな？ | 事実(13:05 一次)=①BE/FE とも origin/main と live deploy の差分 0(BE 5a5556af7・FE 812f0b7a1)=次の deploy に載るのは本設計の変更だけ。②/login が触る共有物は 3 つ: `RouteAccessBoundary`(layout で全ルートを包む。`pathname==="/login"` 分岐のみ)、`app/layout.tsx` の metadata、BE の同一 Render サービス(deploy で再起動)。③認証 API(`/api/auth/verify-viewer`)・7 層リセット・ログイン後ページのコードには一切触れない。制約=共有物に手を入れると波及する。判断=**影響境界を契約化(§2.7)**: 変更許可パス allowlist、RouteAccessBoundary の認証分岐は sha 固定で不変、metadata は /login ページ単位、BE は新 router+追記専用テーブルのみ、既存テストは無変更で全 PASS。効果=P1/P2 の AC に境界チェックを追加 |

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
- `blackout`: {active: bool, month_closed: bool, n_signals: int} ← `viewer_tiers.password_expires_at`/`last_rotated_at` から算出(§2.4。**時期示唆・パスワード・env key は決して返さない**)
- `hero`: Basic-DualMomentum 1 本 `{name, holding, momentum, components, total_return, multiple, cagr, inception, benchmark_total_return}`(完全公開)
- `plans[]`(basic / standard / premium の順): `{plan, n, avg_total_return, best_total_return, avg_multiple, best_multiple, cagr_min, cagr_max, sharpe_best, mdd_best}`(PF 名は返さない=殿裁定 12:48。Sharpe/MDD はベストのみ=12:49。Sharpe/MDD は metrics の『Sharpe Ratio』『Maximum Drawdown』close.portfolio) ← 集合= hide_portfolio=false ∧ hide_signal=false(§3.1)。**個別 PF の holding/momentum は返さない**(best_name のみ)
- `benchmarks[]`: `{symbol: "SPY", since: "2003-10", total_return, multiple, cagr, sharpe, mdd}` / `{symbol: "TQQQ", since: "2010-03", …}` ← `ticker_monthly_returns` から EP が算出(Sharpe は PF と同じ Rf 系列)
- `secret`: `{count: 73, n, avg_total_return, best_total_return, best_name: null, avg_multiple, best_multiple, cagr_min, cagr_max, sharpe_best, mdd_best}`(殿裁定 12:32/12:46/12:49。名前は返さない) ← active 102 − premium performance 28 − Ave-X(Basic のみ)1(殿裁定 10:41、FoF 6 本含む)
- 出所: `portfolio_metrics(years=0)`, `signals`(Basic-DM 最新 date), `tier_visibility_settings`, `viewer_tiers.password_expires_at`。**新規テーブル不要**。count は EP 内で導出(フロントに固定値を書かない)。
- 非送信の原則: 代表 4 行の保有/モメンタムはフロントがぼかしバーを描く(データは来ない)。

### 2.4 サインインとブラックアウト表現（殿裁定 12:58: 日時は書かない・期待感+note 誘導）
- API 変更なし。入力 1 本のまま。
- **状態判定(EP `blackout`)**: `active = max(viewer_tiers.password_expires_at) < today ∧ max(last_rotated_at) ≤ max(password_expires_at)`(=月末で失効し、まだ新パスワードが配布されていない)。配布(rotate)されると自動で `active=false`。`month_closed = series_end の翌月に入っている` を併せて返す。**`until_hint` 等の時期示唆フィールドは持たない**。
- **ブラックアウト帯(active=true のとき、サインインカード上部)**:
  - EN 主: **"August is closed. New signals for September are computed. The password unlocks them — announced on note."**
  - JA 従: 「8 月のシグナルは確定。9 月のパスワードは note で発表します。お楽しみに。」
  - ボタン: **"Get notified on note →"**(note membership/フォロー URL)。カウントダウン・日時・「soon/early September/近日」の語を**使わない**(発表タイミングは殿の裁量)。
  - 月名は `series_end` から自動(8 月/9 月は固定文言にしない)。
- **通常時(active=false)**: 帯なし。カード内 1 行 "This month's password is on note →"。
- **失効パスワードでの 401**(auth.py "Password expired"): 「This password has expired ／ このパスワードは失効しました」+ 帯と同じ note 誘導 1 行。入力欄は残す(新パスワードを持つ人はそのまま入れる)。
- 期待感の根拠を数字で: 帯の直下に "New month's holdings are ready for {n_signals} portfolios"(=Basic/Standard/Premium の signals 数 45 本の合計、EP から)。**保有内容は出さない**。Basic-DualMomentum(完全公開)の当月保有は帯の外(表の hero 行)で通常どおり見える=「無料の 1 本は今すぐ見られる、他は note で」の導線。
- 文言はコンポーネント直書きせず設定値(P3)。EN/JA 規則 §4。

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

### 2.6 描画・更新方針（殿下問 12:54 への答え）
| 観点 | AsIs(現物) | ToBe |
|---|---|---|
| 数値の鮮度 | metrics は毎日再計算(calculated_at 08-30)だが系列は月末基準(end 07-31)=月 1 回しか変わらない | EP は cache 1h、表示は「Data through {series_end}」を明記。**daily の見た目更新は不要**(値が変わらない) |
| 描画 | `"use client"` CSR。HTML 本文は空(title のみ) | **ISR**: `/login` を server component 化し EP を `fetch(..., { next: { revalidate: 86400 } })`、月末再計算完了後に on-demand `revalidatePath('/login')`。初回 HTML に表の数値・H1・脚注が含まれる |
| SEO | robots.txt / sitemap / page metadata なし。検索エンジンから見て空 | `metadata`(title/description EN、og)を /login に付与、robots.txt と sitemap を追加、`/login` を index 許可(ログイン後ページは noindex) |
| 動線 | 未認証は `/`→`/login` replace(白画面リスク §2.5 F1) | ISR で `/login` 自体が即描画される=F1 の解消と同じ手 |
| 数字の信頼 | — | 期間(inception〜series_end)を脚注で固定。「realtime」と書かない(月次データを日次に見せない=殿 08-18 17:28『毎営業日は月次にふさわしくない』と同じ規則) |
- 結論: 「static に見える ISR」= 期間明記+SEO 可+自動更新。CSR の daily fetch は SEO ゼロで値も変わらないので採らない。
- P2b の AC に追加: `curl -s https://dm-signal-frontend.onrender.com/login | grep -c '+3,139%'` が 1 以上(HTML 焼き込み)、脚注に `Data through 2026-07-31` 形式の日付が存在、`/login` の metadata description が EN で存在。

### 2.7 影響境界（殿下問 13:04「ログイン後の本番に影響しないか」への契約）
| 層 | 触ってよいもの(allowlist) | 触らないもの(不変を AC で固定) |
|---|---|---|
| backend | 新規 `app/api/public_showcase.py`(router `/api/public/*`)、新規 migration 1 本(追記専用 event テーブル)、`main.py` の router 登録 1 行、新規 test | `app/api/auth.py`・`visibility_helpers.py`・既存 EP・既存テーブル・既存 test(diff 0) |
| frontend | `app/login/**`(page・新規 components)、`app/login/` 配下の `metadata` export、新規 `app/robots.ts` / `app/sitemap.ts`、文言設定ファイル | `components/route-access-boundary.tsx` の認証分岐(`/login` 以外を `/login` へ replace する部分)、`lib/viewer-auth.ts`・`lib/auth-state-reset.ts`・`lib/api-client.ts`・`app/layout.tsx`(metadata 以外)・ログイン後ページ全て |
| deploy | FE/BE とも live と origin/main の差分は本設計分のみ(13:05 実測 0) | 他の未 deploy 変更を同乗させない(deploy 直前に `git diff --stat <live sha> origin/main` で本設計パス以外 0 を確認) |
| DB | 新テーブル(追記専用)への INSERT のみ | 既存テーブルへの書込み 0(readonly_query で before/after の行数一致) |
- 二値 AC(P1/P2 共通): (a) 変更ファイル一覧が allowlist の外 0 件 (b) `route-access-boundary.tsx` の認証分岐の関数が `git blame`/diff で不変(diff 0 行) (c) 既存 test ファイルの diff 0 かつ選択実行 PASS (d) 本番ログイン→`/`→既存ページ 3 本(dashboard/portfolio/signals)の HTTP 200 と表示が deploy 前後で同一(CDP 1 枚ずつ) (e) BE deploy 後に既存 EP(`/api/signals` 等)の smoke が 200。
- ISR 化(§2.6)は `/login` ルートを server component にするだけで、layout の RouteAccessBoundary は client のまま(境界 (b) を守る)。

---

## §3 画面仕様

### 3.1 Current signals 表 — 集計方式 v3（殿 12:18: Basic-DM 単体 + プラン毎の平均/ベスト/×N/CAGR レンジ）
5 行で完結。個別 PF 名は Basic-DM とベスト PF 名以外出さない。数値は本番 `portfolio_metrics(years=0)` から EP が集計(12:20 実測、series end 2026-07-31)。

| 行 | PF 数 | Total return | ×N | CAGR | Sharpe(best) | MDD(best) | Holding · Signals |
|---|---|---|---|---|---|---|---|
| **Basic-DualMomentum** | 1 | +3,139% | ×32 | 16.4% | 0.89 | −41.0% | **Shown**(holding / momentum / components) |
| **Basic plan** | 3 | +5,290% 〜 +11,321% | ×54 〜 ×114 | 14.1% 〜 39.2% | 1.11 | −23.3% | Sign in |
| **Standard plan** | 17 | +22,047% 〜 +77,078% | ×221 〜 ×772 | 14.1% 〜 52.2% | 1.28 | −22.8% | Sign in |
| **Premium plan** · by invitation | 25 | +23,725% 〜 +106,789% | ×238 〜 ×1,069 | 14.1% 〜 68.7% | 1.40 | −21.2% | Invitation |
| **Secret** | 73 | +535,294% 〜 +5,405,515% | ×5,354 〜 ×54,056 | 10.5% 〜 153.1% | 2.48 | −9.8% | Not viewable |
| *S&P 500 (SPY)* | — | +1,026% | ×11 | 11.2% | 0.63 | −52.9% | — |
| *TQQQ* | — | +29,383% | ×295 | 41.4% | 0.90† | −80.1% | — |

表外脚注(小・英語): "Plan rows: total return and ×N show average 〜 best across portfolios whose signals are included in the plan; CAGR shows min 〜 max; Sharpe and MDD show the best portfolio. Total return, ×N and CAGR since each portfolio's inception (2003–2016); MDD is the maximum monthly drawdown. SPY since 2003-10 (same window as Basic-DualMomentum); TQQQ since 2010-03 (inception). Sharpe uses excess return over the risk-free rate. Not investment advice."

- レンジの意味(殿裁定 12:48/12:49): Total return・×N は『平均 〜 ベスト』、CAGR は min〜max。Sharpe は最大値、MDD は最浅値の単値(平均なし)。表内に PF 名は出さない(Basic-DM のみ固有名)。
- 期間の注釈は表内に置かず、表外脚注に英語で小さく置く。
- Sharpe は `metrics_json.metrics[name="Sharpe Ratio"].close.portfolio`(年率、Rf 控除、`metrics_impl.py:977-983`)。SPY 0.63 は Basic-DM 行の `close.benchmark`(同じ Rf 控除)。† TQQQ の 0.90 は将軍が `ticker_monthly_returns` から Rf=0 で概算した値(12:33)。EP は PF と同じ Rf 系列で再計算する(AC)。
- 比較行の期間: SPY は Basic-DM と同じ 2003-10〜、TQQQ は 2010-03〜。各行に期間を明記し、プラン行(起点 2003〜2013 が混在)との単純比較ではないことを注記 "periods differ; see inception"。
- 集合の定義(殿裁定 12:19): 各プラン行は**そのプランでシグナルまで公開している PF**(hide_portfolio=false ∧ hide_signal=false)だけで計算する。パフォーマンスのみ可視の PF(Basic の白虎激攻・分身常勝、premium の奥義 ×3)は集計に入れない(参考: 入れると Basic 平均 +20,494%/premium ベスト +365,962% まで跳ね、実際に使える数字と乖離する)。行構成は 5 つ(Basic-DM / Basic / Standard / Premium / Secret)に確定(殿裁定 12:20)。
- CAGR の出所: `metrics_json.metrics[name="Geometric Mean (annualized)"].close.portfolio`(years=0 行の `cagr` キーは無いが、metrics 配列に格納済み。`(1+total_return)^(12/period_months)-1` と一致することを 12:44 に確認: CAGR4 1.5314=153.1%、秘奥義-追い風-激攻 1.4491=144.9%)。EP は格納値を返し、式は AC の独立再計算側で使う。プラン行の period は 160〜275 か月、Secret は 105〜196 か月。
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
