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
| Basic | ベーシック ¥1,000(初月無料) | **5** | ±0(DM-safe・GSシン分身-常勝・シン白虎-激攻・Basic-DualMomentum・Ave-X) |
| NewStandard | スタンダード ¥8,000 | **17** | ±0 |
| Standard(古参) | ¥4,000 非公開 | 22 | ±0 |
| AddOn | 裏Ave7 ¥2,000 非公開 | 22 | ±0 |
| premium | ドクタープレミアム 招待制 | **28** | **+1** |
| どの tier にも出ない(Secret) | — | **73** | **+3** |
| is_active 合計 | | **102** | **+4**(98→102) |

- premium 専用(NewStandard/Basic 非可視)10 本の現物: DM-safe-2 / GSシン四つ目-常勝・激攻・鉄壁 / 劇薬DMオリジナル・スムーズ / 奥義-GS-分身-常勝・激攻・鉄壁 / 裏Ave-X。加えて Ave-X(Basic 可視・NewStandard 非可視)も premium で再可視。∴ premium で新たに見える 11 本 = 代表 GSシン四つ目-常勝 1 + 群 10(前版「+10」と同値)。
- **新規 active 4 本(08-19 作成)**: Sharpe4 / CAGR4 / greedy2 + `New Fund of Funds`×3(07-01)。いずれも Secret 群。**名前が作業名**(Secret 群は件数のみ公開なので画面には出ないが、件数 73 に作業 PF が混ざる → §6 未決 1)。
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
5. プラン 3 枚: Basic ¥1,000(初月無料・PF 5) / Standard ¥8,000(PF 17) / Coupon(期間限定)
6. 導線 4 本: What is Dual Momentum?(note JA) / Join on note(membership) / Weekly report / @TokyoJibika
7. サインインカード(§3.2)
8. フッタ: © / Not investment advice / Data: monthly close, US ETFs

### 2.3 公開データ契約 `GET /api/public/showcase`（認証不要・tier 非依存・cache 1h）
- `as_of`: {series_end: "2026-07-31", next_close: "2026-08-31", calculated_at}
- `blackout`: {active: bool, until_hint: "early September"} ← `viewer_tiers.password_expires_at` の max から算出(**数値のみ。パスワードや env key は決して返さない**)
- `rows[]`(ラベル方式の順): 
  - `{name, label: "free", holding, momentum, total_return, inception}` ← Basic-DualMomentum のみ完全公開(`signals.holding_signal`/`momentum_data`)
  - `{name, label: "basic", total_return, inception}` ×4 ← holding/momentum **キー自体を返さない**
  - `{group: true, label: "standard", count: 13, max_total_return}` ← NewStandard 可視 17 − Basic と重なる 4 本(Basic-DM・DM-safe・分身常勝・白虎激攻)= **13**(シン四神 11 + 分身激攻/鉄壁 2)
  - `{name: "GSシン四つ目-常勝", label: "premium", total_return}` + `{group, label: "premium", count: 10, max_total_return}` ← premium 可視 28 − NewStandard 可視 17 = 11、代表 1 を除いて **10**
  - `{group, label: "secret", count: 73 − 作業PF}` (§6 未決 1 で確定)
- 出所: `portfolio_metrics(years=0)`, `signals`(Basic-DM 最新 date), `tier_visibility_settings`, `viewer_tiers.password_expires_at`。**新規テーブル不要**。count は EP 内で導出(フロントに固定値を書かない)。
- 非送信の原則: 代表 4 行の保有/モメンタムはフロントがぼかしバーを描く(データは来ない)。

### 2.4 サインイン
- API 変更なし。入力 1 本のまま。
- 失敗時: 401 "Password expired" を **「This month's password has expired ／ 当月パスワードは失効しました」+ blackout 案内**、その他 401 は現行文の EN+JA 化。
- ブラックアウト中(`blackout.active`)はカード上部に帯「Blackout until early {month} — new password on note ／ ブラックアウト中」。

---

## §3 画面仕様

### 3.1 Current signals 表（列: Portfolio / Holding / Momentum / Total return since inception）— 本番件数で確定
| 行 | ラベル | +N | Holding/Momentum | Total return |
|---|---|---|---|---|
| Basic-DualMomentum | Free trial · full access(緑) | — | 表示 | +3,139%(2003-) |
| DM-safe | Basic plan | +4 PF with Basic | ぼかし | +1,411% |
| シン白虎-激攻 / GSシン分身-常勝 / Ave-X | Basic plan | — | ぼかし | +75,619% / +10,982% / +11,321% |
| シン四神 ×11 · GSシン分身 ×2(群) | Standard plan | +13 PF with Standard | ぼかし | up to X% |
| GSシン四つ目-常勝 | Premium plan · by invitation(紫) | +10 PF with Premium | ぼかし | +17,181% |
| Ave-X(再掲) · 裏Ave-X · DM-safe-2 · 四つ目 ×2 · 劇薬 ×2 · 奥義 ×3(群) | Premium plan · by invitation | — | ぼかし | up to X% |
| 73 portfolios(作業 PF 除外前) | Secret(灰) | Not viewable | Not disclosed | — |
- +N の定義(本番導出・10:14 実測から): Free 1 / Basic = Basic 可視 5 − 1 = **4** / Standard = NewStandard 可視 17 − Basic と重なる 4 = **13** / Premium = premium 可視 28 − NewStandard 17 − 代表 1 = **10** / Secret = active 102 − premium 28 − Ave-X(Basic のみ可視)1 = **73**。**件数は全て EP が tier 設定から導出し、フロントに固定値を書かない**(AC: 未認証 curl の count と DB 集計の一致を二値判定)。前版 §3.1 と同値(件数は 08-18 から Secret +3・premium 内訳 +1 のみ変動)。
- ヘッダ右: "Series through {series_end} · next rebalance {next_close} close"。**「today/毎営業日」禁止**。

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
- **追加 1**: 総リターンは `Intl.NumberFormat` で桁区切り、符号付き、%(小数なし)。**追加 2**: ブラックアウト帯・失効エラーは EN+JA 必須(今週から実需)。

---

## §5 実装単位（小さく 1 層ずつ・可逆・儀式なし）
| 手 | 内容 | 二値 AC |
|---|---|---|
| P0 | 数値表記の殿裁定(§6-3)と Secret 件数定義(§6-1) | 裁定 2 件が本設計書 §6 に「事実→制約→判断→効果」で記載済み |
| P1 | backend `GET /api/public/showcase`(read-only、cache 1h、tier 非依存、password 系非送信) | 未認証 curl: free 行に holding/momentum あり・basic 4 行に**キーなし**・count(4/13/10/secret) が DB 集計と一致・レスポンスに `password`/`env` 文字列 0 件 |
| P2 | frontend `/login` を §2.2 構造へ(SignInCard 2 variant + レスポンシブ + blackout 帯) | 860px 境界切替・sticky/ボトムシート動作・既存ログイン成功経路が従来どおり(7 層リセット→`/`) |
| P3 | 文言・導線 URL を設定値化、EN/JA 規則 | 「毎営業日/today」grep 0、note URL がコンポーネント直書き 0 |
| P4 | 本番 CDP 2 枚(モバイル/PC) + 殿実機 | 殿確認 |
- push/deploy は家老レーン(FE は 08-18 以来 deploy なし=本版が次の FE deploy)。P1 は read-only 新 EP で本番書込みなし。P2 以降 revert 可。

---

## §6 未決（殿裁定待ち。裁定は「事実→制約→判断→効果」で追記）
1. **Secret 件数から作業 PF を除くか**: 事実=Secret 73 に Sharpe4/CAGR4/greedy2/New Fund of Funds×3 等の作業名 PF が含まれる(is_active)。案=EP 側で「名前が英数字の作業名」ではなく **`is_active` かつ `portfolio_metrics(years=0)` あり**を条件に数える(作業 PF は metrics 未計算が多い)。要一次確認。
2. **Basic-DM の古参 tier(Standard/AddOn)で hide_portfolio=true**: 公開 PF なのにログイン後の古参会員に非表示。案=admin で 2 tier を false に(可逆・DB 設定変更のみ)。
3. **総リターンの表記**: 事実=since inception が +3,139%〜+75,619%(白虎)。案 A=% のまま(餌として最強)、案 B=「×32 / ×757」倍率、案 C=CAGR 併記(years=0 に cagr なし → EP で `(1+tr)^(12/months)-1` を算出)。将軍推奨=**C**(信憑性を保ちつつ interest を引く)。
4. 群行 "up to X%" を Standard/Premium で出すか(前版から継続)。
5. Coupon 説明「note 不要」の正確性(1.1 の通り auth.py にクーポン分岐はない → クーポン=別 env key の tier パスワードか、Legacy `VIEWER_PASS` か要確認)。

## §7 因果リンク
- [[殿観測_ログインページさみしい_20260818_1550]] -> [[login_showcase_mock_v1-v11]] -> [[dm-login-showcase-asis-tobe_20260818]](ToBe v0.3・未実装) -> [[殿指示_asis本番リアルタイム化_20260830_1007]] -> **[[dm-login-showcase-asis-tobe_v2_20260830]]**
- ← [[dm-login-boundary-asis-tobe_20260817]](第 0 段) / [[tier別可視性完成形]](cmd_3837) / [[visibility_philosophy]](projects/dm-signal.yaml)
- 一次証拠: Render deploys API(10:10)、`git diff 812f0b7a1 origin/main`、readonly_query 7 本(10:14-10:18)、`metrics_impl.py:1386`、`auth.py:21-70`
