<!-- gist-master: 0e15f28f66da87251a77f4d6dc4dd072 dm-login-showcase-asis-tobe_20260818.md -->
# DM-Signal /login ショーウィンドウ — AsIs / ToBe 設計書

- 版: ToBe v0.3 / AsIs v1.0（2026-08-18 17:35 起草、17:38 v0.2=5ゾーン化、17:43 v0.3=ラベル方式）
- モック(artifact): https://claude.ai/code/artifact/fa111b2b-9ac4-44b9-9d4c-0c0d4581774c（正本HTML `docs/dashboard/dm-signal-login-showcase.html` v13）
- 要望・変更履歴ログ: `docs/research/dm-login-showcase-design-log_20260818.md`（殿の言葉→原理→版、随時追記）
- 前提設計書: ログイン境界 `docs/research/dm-login-boundary-asis-tobe_20260817.md`（gist 0d23e0c3、第0段 手①〜③=cmd_4325/4326/4327/4333 完了）
- 原則: ToBeは理想（現実のコード名で縛らない）。AsIsは現物。殿裁定は「事実→制約→判断→効果」で記す。

---

## §0 殿裁定・要望（本設計書に効く分のみ。全文はログ）

| 時刻(08-18) | 殿の言葉(要旨) | 効果(本設計への拘束) |
|---|---|---|
| 15:50 | ログインページがさみしい。ユーザーを誘導したい | /loginは門ではなくショーウィンドウ |
| 15:54 | 基本は英語ベース。ログイン画面はEN+JA、ログイン後はENのみ。おしゃれで「何のページか/どこからログインか」不明はUX害 | 言語規則(§4)、明瞭性最優先(§3) |
| 15:59 | 現状に合わせよ | 未実装のゲストtier/無料PFを描かない→ただし16:07で無料PFを新設 |
| 16:00-16:04 | モバイル=下にシンプルカード+stickyポップアップ。PC/タブレット=リッチsticky カード | レスポンシブ2パターン(§3.2) |
| 16:07 | Basic-DualMomentumを完全公開用に | 未認証で保有まで見せる公開PFが1本必要(§5 P1) |
| 16:08 | inception以来のtotal returnは見せた方が興味を引く | 代表PFの総リターンは未認証公開(§5 P2) |
| 16:32 | 公開=Basic-DM・DM-safe・白虎激攻・分身・四つ目。他は存在のみ。Standardの忍法は分身のみ | 代表5行(§3.1)、群行の分割(§3.1) |
| 16:56 | standard/premium/limited members only を餌に | 秘匿群を会員ランク別3行に |
| 17:23 | tier別データを確認せよ。premiumも招待制、limited→「Secret」 | 件数は本番tier_visibility_settings実測(§2.3)、表記Secret |
| 17:28 | 「毎営業日」は月次リバランスにふさわしくない→「月に一回」 | 文言規則(§4) |
| 17:36 | Current signalsを 無料お試し/Basic/Standard/Premium/Secret でゾーン分け | 表=プラン階段(§3.1 v12) |
| 17:41 | ゾーン行ではなくPF名の下にプランラベル、その下に「+N PF」 | §3.1 v13(ラベル方式) |

---

## §1 AsIs（現物・2026-08-18）

### 1.1 ルートと境界
- `/login` = `frontend/app/login/page.tsx`(82行)。`RouteAccessBoundary`(`frontend/components/route-access-boundary.tsx`)で `pathname==="/login"`→`public`、他ルートは viewer/admin 認証なしなら `/login` へ `replaceLocation`。
- 認証: `api.verifyViewer(password)` → `POST /api/auth/verify-viewer`(`backend/app/api/auth.py:21`)。入力は「当月パスワード or クーポンコード」1本。成功で `viewerAuth` にtoken/tier/expires_at、`resetAuthScopedClientState()`後に遷移(第0段 手②の7層リセット)。
- `/admin/login` は素描画で分離(cmd_4333)。
- 未認証時のデータfetchは走らない(第0段の境界。cmd_4325)。**よって現状、未認証で見せられる動的データはゼロ**。

### 1.2 画面
- 見出し「DM-Signal ログイン」+説明2文(日本語のみ)+入力+ボタン。価値提示・導線なし。言語=JAのみ。

### 1.3 データ・可視性の現物
- Tier可視性の正=`tier_visibility_settings.portfolio_settings`(hide_portfolio/hide_signal/hide_components)。判定関数=`backend/app/services/visibility_helpers.py`(`check_hide_portfolio_or_folder` を全閲覧EP18箇所へ適用済み cmd_3839)。
- 本番実測(17:26 readonly_query、is_active=98本):

| tier(DB名) | noteプラン | 可視PF数 | 内訳 |
|---|---|---|---|
| Basic | ベーシック ¥1,000(初月無料) | 5 | DM-safe・GSシン分身-常勝・シン白虎-激攻・Basic-DualMomentum・Ave-X |
| NewStandard | スタンダード ¥8,000 | 17 | Basic-DM・DM-safe・GSシン分身×3・シン四神×12 |
| Standard(古参) | ¥4,000 非公開 | 22 | (NewStandard 16 + Ave-X・裏Ave-X・DM-safe-2・奥義-GS-分身×3) |
| AddOn | 裏Ave7 ¥2,000 非公開 | 22 | 同上 |
| premium | ドクタープレミアム 招待制 | 27 | 上記+GSシン四つ目×3・劇薬DM×2 |
| (どのtierにも出ない) | — | 70 | Secret |

- 注意: **Ave-XはBasic可視・NewStandard非可視**（cmd_3837のnote対応表突合が要る。設定漏れなら是正cmd）。
- 総リターン(since inception)の出所: `portfolio_metrics.metrics_json`(years=0)の`total_return`(db-checkスキル§11)。全EPは`require_viewer`依存で未認証不可。

### 1.4 i18n
- frontendに i18n 基盤なし(next-intl等の依存なし)。文言はコンポーネント直書き。

---

## §2 ToBe（理想）

### 2.1 目的
未認証訪問者が **(a)何のサービスか (b)どこからログインするか (c)なぜ会員になるか** を、スクロールなしで理解できる。ログイン後の体験(EN・保有シグナル)へ最短で連れて行く。

### 2.2 情報構造（上から）
1. ブランド行: ロゴ + "DM-Signal" + "Dual Momentum signals · rebalanced once a month"
2. H1: "What to hold this month — computed, not guessed." / JA副題「今月、何を保有すべきか。月に一回、ルールで自動計算。」
3. リード1段落(EN。月末クローズで月1回リバランス・10年超バックテスト・ルールベースで再現可能)
4. **Current signals 表**（§3.1）
5. プラン3枚: Basic(¥1,000・初月無料・PF構成) / Standard(¥8,000・PF構成) / Coupon(期間限定・note不要)
6. 導線4本: What is Dual Momentum?(note JA) / Join membership on note / Weekly report / @TokyoJibika
7. サインインカード（§3.2）
8. フッタ: © / Not investment advice / Data: daily close, US ETFs

### 2.3 公開データ契約（未認証で返す新規の**公開エンドポイント**が必要）
- `GET /api/public/showcase`（認証不要・キャッシュ可・tier非依存）
  - `rebalance`: {last_close: date, next_close: date}
  - `zones[]`: free / basic / standard / premium / secret の順。各zoneに `portfolios[]`(代表行) と `group`(件数+max_total_return|null)
    - free: Basic-DualMomentum {name, holding, momentum, total_return_since_inception, inception_date} ← 完全公開
    - basic: DM-safe / シン白虎-激攻 / GSシン分身-常勝 / Ave-X {name, total_return_since_inception, inception_date} ← 保有・モメンタムは**返さない**(非送信)
    - standard: group {count(=NewStandard可視−Basic可視), max_total_return}
    - premium: GSシン四つ目-常勝(代表) + group {count(=premium可視−NewStandard可視−代表1), max_total_return}
    - secret: group {count(=active−premium可視−Basic-DM), max_total_return: null}
  - 出所: `portfolio_metrics(years=0).total_return`、`signals`(Basic-DMのみ)、`tier_visibility_settings`。**新規テーブル不要**。
- Basic-DualMomentumのtier設定: hide_portfolio=false/hide_signal=false/hide_components=false を全tierで保証(公開PFなので)。
- 表示規則: 代表4行の保有/モメンタム欄はプレースホルダ(ぼかしバー)を**フロントで描く**(データは来ない)。

### 2.4 サインイン
- 入力は現行どおり1本(password or coupon)。API変更なし(`POST /api/auth/verify-viewer`)。
- 成功後の遷移・7層リセットは第0段のまま。失敗時エラー文にブラックアウト案内(EN+JA)を出す。
- 「Get it →」= noteメンバーシップ固定記事URL(設定値。`marketing-director/marketing-info.md` §11のURL)。

---

## §3 画面仕様

### 3.1 Current signals 表（列: Portfolio / Holding / Momentum / Total return since inception）— ラベル方式(v13)
各行のPortfolioセル= ①PF名(+EN補助) ②プランラベル(pill) ③そのプランの先頭行のみ「+N PF with {plan}」。ゾーン見出し行は置かない(殿17:41)。
| PF行 | ラベル | +N表示 | Holding/Momentum | Total return |
|---|---|---|---|---|
| Basic-DualMomentum | Free trial · full access(緑) | — | 表示 | 表示 |
| DM-safe | Basic plan | +4 PF with Basic | ぼかし(非送信) | 表示 |
| シン白虎-激攻 / GSシン分身-常勝 / Ave-X | Basic plan | — | ぼかし | 表示 |
| シン四神×12 · GSシン分身×3(群) | Standard plan | +13 PF with Standard | ぼかし | up to X% |
| GSシン四つ目-常勝 | Premium plan · by invitation(紫) | +10 PF with Premium | ぼかし | 表示 |
| Ougi · Ura Ave-X · DM-safe-2 · Gekiyaku(群) | Premium plan · by invitation | — | ぼかし | up to X% |
| 70 portfolios | Secret(灰) | Not viewable | Not disclosed | — |
- +Nの定義: そのプランで**新たに**保有が見えるPF数(Basic=Basic可視−Free、Standard=NewStandard可視−Basic可視(Ave-X除く差分)、Premium=premium可視−NewStandard可視)。件数は`tier_visibility_settings`から導出(§2.3)。
- ヘッダ右: "Rebalanced {last_close} close · next {next_close}"

### 3.2 レスポンシブ2パターン
- **>860px(PC/タブレット)**: 2カラム(左1.25fr=ショーウィンドウ / 右0.9fr=サインインカード)。カードは`position: sticky; top:20px`。**リッチ版**: 見出し"Sign in"/ログイン・説明(EN+JA)・入力・ボタン・ブラックアウト注意・「This month's password is on note → Get it」・「Basic membership starts free for the first month」。
- **≤860px(モバイル)**: 1カラム。ショーウィンドウ→**末尾にシンプルカードをインライン**(見出し・入力・ボタン・note1行)。加えて**下部sticky バー**「Sign in ／ ログイン」→タップで**ボトムシート型ポップアップ**(同じシンプルカード、×/背景/Escで閉じる、safe-area対応、開いたら入力へfocus)。
- 実装は1つの`<SignInCard variant="rich"|"simple">`。ポップアップとインラインは同コンポーネントの2インスタンス(id分離)。

### 3.3 見た目
- トークンは`frontend/app/globals.css`既存(primary #0369a1、slate系、ダーク対応)。新色なし。
- ページ内で最も濃い塗りは「Sign in」ボタンのみ(一意の主アクション)。装飾・影・大ヒーロー画像は入れない。

---

## §4 言語・文言規則
- ログイン前(/login): **EN主・JA従**。JAは各英文の直下に小さく(`.ja`)。ボタン等の主要ラベルは "Sign in ／ ログイン" のように併記可。
- ログイン後: **ENのみ**（本設計書の範囲外だが方針として記録）。
- 頻度表現: 「月に一回 / once a month / this month」。**「毎営業日」「today」は使わない**(内部の日次再計算はユーザー体験ではない。殿17:28)。
- PF名は日本語正式名+EN補助(小文字)。
- 免責: "Not investment advice ／ 投資助言ではありません" をフッタ固定。

---

## §5 実装単位（小さく1層ずつ。儀式なし。可逆）
| 手 | 内容 | 合否(二値) |
|---|---|---|
| P1 | backend: `GET /api/public/showcase`(認証不要・代表5行+群件数+rebalance日付)。Basic-DMの全tier公開設定を確認 | 未認証curlで代表4行に holding/momentum キーが**存在しない**・Basic-DMには存在・件数が§1.3実測と一致 |
| P2 | frontend: `/login`を§2.2構造へ(静的部分+SignInCard 2 variant+レスポンシブ)。データはP1から | 860px境界で2パターン切替・sticky/ポップアップ動作・既存ログインが従来どおり成功 |
| P3 | 文言・導線URL(note/X/週報)を設定値化、EN/JA規則適用 | 「毎営業日/today」がgrep 0件 |
| P4 | 本番CDP確認(モバイル幅・PC幅の2枚) | 殿の実機確認 |
- push/deployは家老レーン。P1はread-only新EPで本番書込みなし。P2以降はrevert可。

---

## §6 未決・要確認
- Ave-X: Basic可視/NewStandard非可視の意図確認(cmd_3837 note対応表と突合→不一致なら是正cmd)。
- 群行の"up to X%"を出すか(Premium/Standardは出す・Secretは出さない、が現案)。
- Coupon説明「note不要」の正確性(クーポン発行経路の現物確認)。

## §7 因果リンク
- [[殿観測_ログインページさみしい_20260818_1550]] -> [[login_showcase_mock_v1-v11]] -> [[本設計書ToBe v0.1]]
- ← [[dm-login-boundary-asis-tobe_20260817]](第0段) / [[tier別可視性完成形]](cmd_3837) / [[visibility_philosophy]](projects/dm-signal.yaml)
