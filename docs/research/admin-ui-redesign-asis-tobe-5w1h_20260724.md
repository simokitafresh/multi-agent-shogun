<!-- gist-master: 6c30b09414a9404d21389bce3f9aa53f admin-ui-redesign-asis-tobe-5w1h_20260724.md -->
# DM-Signal Admin画面 一覧性改修 — AsIs/ToBe 5W1H設計書 v1.1

## §0 殿裁定 2026-08-13 17:04 — /admin/fof(案B)実装GO

殿原文(2026-08-13 17:04): 「/admin/fofが縦に長くスクロールが大変だ。カードスタイルの廃止、Weight Breakdown表のアコーディオン（基本はclose）とフォントサイズなどの他ページとの共通化をやりたい」

これにより以下が裁定確定:
1. **案B採用・実装GO**(/admin/fof): カードスタイル廃止→一覧テーブル/行リスト化。
2. **未決事項3の裁定**: Weight Breakdown表=**アコーディオン・既定close**で確定。
3. **設計原則P2の適用確定**: フォントサイズ等はviewer表canonical(14px/罫線slate-700/800/padding 12-8/sticky thead、正本=dm-signal-page-style-diff-mece_20260722.md)へ共通化。
4. 案A/C/Dと未決事項1・2・4は引き続き裁定待ち(実装禁止のまま)。

実装cmd=cmd_4297(2026-08-13起票)。RB6/RB8復旧レーン(backend)とはFE専用ゆえ独立並行可。

## §0.1 殿裁定 2026-08-13 18:02 — /admin/visibility(案C縮小版)実装GO

殿原文: 「/admin/visibilityも改良しよう。まずはstickyとカードスタイル除去、フォントサイズの他ページとの統一に絞る」「CDPなどの実測は俺がやる。実装だけでいい。余分な機能改変はしない」

裁定確定:
1. **案Cの縮小版採用**: スコープは(a)thead sticky追加 (b)カード骨格(GlassCard等)の除去 (c)フォント・罫線・paddingのviewer表canonical統一、の**3点のみ**。案Cにあった検索box追加は**今回スコープ外**(機能改変なしの殿指示)。
2. **検証出口の変更**: CDP実測は殿が自ら実施。実装cmdのACはコード+テストで完結し、本番実測ACを含めない。
3. トグル・保存・tier切替等の**機能ロジックは一切変更しない**。

実装cmd=cmd_4298(2026-08-13起票)。cmd_4297は18:02 GATE CLEAR済み(FoF一覧化完了)。

## §0.2 殿実機確認 2026-08-13 18:50 — /admin/visibility結果と残課題

- **殿実機確認: 問題なし**(cmd_4298の3点=sticky・カード除去・canonical統一はPASS。実装commit `c22362a9`)。
- **残課題(殿指摘)**: 「**縦スクロールが長く一覧性に劣る**」— 102PF行の縦の長さ自体は未解消。原因はcmd_4298のスコープが§0.1裁定で3点に限定され、案C原案にあった**行高圧縮(密度改善)が対象外**だったため。
- **次の改善候補(未裁定・実装禁止)**: (a)行高圧縮=cell paddingの縮小(canonicalのpadding 12-8より密なadmin専用密度。AsIs 8画面→4-5画面が案C原案の目標値) (c)PF名検索/フォルダフィルタ(案C原案・機能追加ゆえ別裁定)。
- **訂正(殿指摘2026-08-13 18:51)**: 当初候補に挙げた「フォルダ単位の折りたたみ」は**既に実装済み**であり、**開閉状態はsaveで任意に固定できる**(将軍の現物未確認による候補誤り。設計書§2.2(D)のAsIs記述も折りたたみ機構に未言及だった=AsIs調査の抜け)。∴縦スクロール改善の残候補は(a)行高圧縮と(c)検索/フィルタの2つ。殿の裁定で次スコープを確定する。
- **cmd_4299一次確認(2026-08-13 19:30)**: 現物コードでは`collapsedFolders`がReact stateに留まり、visibility page/components内の保存payload・local/session storageに開閉状態の経路は無かった。Save永続化は未確認のため、殿確認との不一致を§5および`docs/research/cmd_4299_visibility_density_recon_20260813.md`へ記録した。

> ★前提情報のないLLM/人へ: このドキュメントだけで理解できるよう自己完結している。§1(5W1H)→§2(AsIs実測)→§3(ToBe案)の順に読め。ToBeは**未裁定の候補案**であり、殿(オーナー)の裁定で確定する。**実装はまだ始めない**(殿指示 2026-07-24 12:43「実装にはいらず修正案を練ろう」)。

## §1 5W1H(前提)

- **What(対象)**: DM-Signal(投資シグナル配信Webアプリ)の管理者画面。本番URL=`https://dm-signal-frontend.onrender.com/admin` 配下の**4ページ**: `/admin`(PF設定本体) / `/admin/fof`(Fund of Funds管理) / `/admin/folders`(フォルダ管理) / `/admin/visibility`(公開設定)。コード=DM-signal repo `frontend/app/admin/` 配下(Next.js+Tailwind)。
- **Why(なぜ改修するか)**: 殿の原文「現在はカードでデザイン優先となっているため、**一覧性が低く作業が猥雑**だ」(2026-07-24 12:43)。管理対象PFは102件(Max 200)・FoF約39件あり、カードUIでは全体を俯瞰できず運用作業(設定確認・比較・一括変更)のコストが高い。
- **Who(誰が使うか)**: 管理者=殿のみ。viewer(顧客)は使わない。よって「見栄え」より**作業効率(一覧性・到達クリック数・1画面あたり情報密度)**が設計基準。
- **When**: 2026-07-24調査開始。実装cmdは修正案の殿裁定後。
- **Where(一次情報)**: (1)本番CDP実測+スクリーンショット(§2、将軍が2026-07-24 12:55取得) (2)コード全数偵察=cmd_4153(忍者、`docs/research/cmd_4153_admin_ui_recon_20260724.md`に行番号付きインベントリ) (3)スクショ原本=session scratchpad `admin_recon_admin*.png` 4枚。
- **How(測定と完了基準)**: 測定は本番CDP一次(grep禁止 — 描画の真実はgetComputedStyle/DOM。viewer側UI統一で確立した規律)。改修完了の判定は「1画面(スクロールなし)で把握できる管理対象行数」「目的の設定への到達クリック数」の前後比較+殿実機確認。
- **関連canonical**: viewer側で確立済みの表canonical=Monthly Returns基本形(14px・thead slate-700/行間slate-800罫線・padding 12-8・card/stripe撤去・sticky header)。正本=`docs/research/dm-signal-page-style-diff-mece_20260722.md`(gist c50699ea)。admin改修もこの表canonicalを再利用する(車輪の再発明禁止)。

## §2 AsIs(本番実測 2026-07-24 12:55、viewport 2561×1398・認証済みセッション)

### §2.1 実測サマリ表

| ページ | cards | tables | buttons | scrollHeight | 画面数(÷932px) | 一覧性の実態 |
|---|---|---|---|---|---|---|
| /admin | 32 | 0 | 212 | 1,605 | 1.7 | **単票ナビ**: 102PFをPrev/Next/ドロップダウンで1件ずつ。俯瞰不能 |
| /admin/fof | 80 | 78 | 489 | **24,588** | **26.4** | 全FoFが巨大カード縦積み+Weight Breakdown表**常時展開** |
| /admin/folders | 4 | 0 | 52 | 932 | 1.0 | 行リスト形式で比較的良好。展開しないと中身不可視 |
| /admin/visibility | 4 | 1 | 382 | 7,460 | 8.0 | 表形式だが行高大・トグル密度低。102行で8画面 |

### §2.2 ページ別AsIs詳細

**(A) /admin(本体)** — 構成: Save/Sync/Logoutバー → Database Status(折りたたみカード) → ナビカード3枚(FoF/Folders/Visibilityへの入口。各1行の説明+ボタンのみで1画面の1/3を消費) → **PF単票エディタ**(「Portfolio 1 of 102 (Max: 200)」+Prev/Next/ドロップダウン/New/複製) → General Settings+Asset Configurationの2カラムカード(Portfolio Name/Lookback Periods(期間×weight表)/Rebalance Trigger/Top N/Relative Momentum Assets/Absolute Momentum/Risk-Free/Safe Haven/Benchmark/Delete)。
**猥雑さの核**: (1)102 PFの設定を**1件ずつしか見られない**(比較・横断確認が不可能。目的PFへの到達=ドロップダウン検索1回+スクロール) (2)ナビカード3枚が縦積みで単票エディタが2画面目に沈む (3)設定項目がカード2枚に分散し1PFの全設定も1画面に収まらない。

**(B) /admin/fof** — 構成: New Fund of Fundsボタン → FoFごとに巨大カード(FoF名/Components一覧文/Allocation/Edit/複製/削除/並び替え↑↓ + **Weight Breakdown表(as-of日付+Component×Target%)が常時展開**)。約39 FoF×約630px/枚=26画面分。
**猥雑さの核**: (1)FoF一覧の俯瞰が不可能(名前を探すだけで大量スクロール) (2)Weight Breakdownは確認頻度が低いのに常時展開で縦を支配 (3)構成・配分の横断比較(どのFoFがどのPFを含むか)が構造的に不可能。

**(C) /admin/folders** — 構成: Folders行リスト(6フォルダ: メンバーシップ7/オリジナル17/シン四神12/GSシン忍法21/GSシン奥義24/秘奥義21 PFs)+New Folder+並び替え/編集/削除、Uncategorizedセクション。1画面完結。
**評価**: 4ページ中もっとも一覧的。**このページの「行リスト+件数+行内操作」パターンが、他ページのToBeの参考型になる**。弱点: フォルダ内PFは展開しないと見えず、PFの所属変更は展開後の個別操作。

**(D) /admin/visibility** — 構成: tierタブ(Global Default/Standard/premium/AddOn/Basic/NewStandard+Manage Tiers) → L1: Global Page Visibility(Core/Info Pagesのチェックボックスをグリッド配置) → L2-L4: Global Portfolio Settings(PF×L2:Hide/L3:MaskPF/L4:MaskCompのトグル表、フォルダ見出し行つき102行)。
**評価**: 既に表形式で方向性は正しい。弱点: (1)行高が大きく102行=8画面(viewer canonicalのpadding 12-8適用で圧縮余地) (2)theadがstickyでないため深部でヘッダ不明 (3)tier切替時に現在タブ以外の設定状態が俯瞰できない。
**cmd_4299実測追記**: 本番viewport `1036×906`では全開document scrollHeight=`6556px`、全閉=`980px`、PF行=`54.33–54.67px`、folder header=`40px`、完全表示=`2 PF行`（交差=`3 PF行`）。開閉UIは既存だが、visibility page/components内のSave payload・local/session storageに`collapsedFolders`永続化経路は無い。詳細→`docs/research/cmd_4299_visibility_density_recon_20260813.md`。

### §2.3 共通AsIs
- 表canonical(viewer側で統一済みの罫線・フォント・padding)がadminには**未適用**。カード(`rounded-lg border`系)が全ページの基本骨格。
- 検索・フィルタ・ソートが4ページとも**存在しない**(102 PF・39 FoFに対して)。
- コード行番号付きの全数インベントリはcmd_4153偵察(進行中)が補完する。

## §3 ToBe(修正案候補 — 未裁定。殿と練る土台)

**設計原則**: (P1)カード→**表/行リスト**へ(一覧性最優先。管理者専用画面ゆえ装飾不要) (P2)viewer表canonical(14px/罫線slate-700/800/padding 12-8/sticky thead)を再利用 (P3)**master一覧→detail単票**の2段構成(一覧で俯瞰・検索→行クリックで編集) (P4)既存の良い型(/foldersの行リスト、/visibilityの表)を基準に他ページを寄せる — 最小差分で作る(過剰デザイン禁止=LS104)。

### 案A: /admin本体 = PF一覧テーブル化(本命・効果最大)
- 単票エディタの手前に**PF一覧テーブル**(102行: PF名/フォルダ/Rebalance/Top N/Lookback概要/Benchmark/操作)を新設。検索box+フォルダフィルタ+列ソート付き。sticky thead。
- 行クリック(またはEdit)で現行の単票エディタへ(単票自体は既存を維持=最小差分)。Prev/Nextドロップダウンは一覧からの遷移に置換または併存。
- ナビカード3枚は上部の小型タブ/リンク行へ圧縮(1画面目に一覧が入るように)。
- 期待効果: 到達=検索1回+クリック1回。全PF設定の俯瞰・比較が初めて可能に。

### 案B: /admin/fof = FoF一覧テーブル+行展開
- 一覧テーブル(39行: FoF名/構成数/構成PF(省略表示)/配分方式/as-of/操作Edit・複製・削除・並び替え)。
- Weight Breakdownは**行展開(クリックで開閉)**または詳細パネルへ退避。既定は閉。
- 期待効果: 26.4画面→1-2画面。構成の横断比較が可能に。

### 案C: /admin/visibility = 密度圧縮+sticky(小改修)
- 表canonicalのpadding 12-8適用で行高圧縮(8画面→4-5画面目標)、thead sticky追加、PF名検索box追加。
- L1チェックボックスグリッドは現行維持(既に一覧的)。

### 案D: /admin/folders = 現行維持+微修正(最小)
- 行リストは維持。フォルダ展開時のPF行にも表canonical適用。PFのフォルダ移動をドラッグまたは一覧(案A)側のフォルダ列編集で可能にする案は要裁定。

### 実装順序案(裁定後)
効果/コスト比で **案A → 案B → 案C → 案D**。各案は独立cmd(1道具1CMD)。実装前にcmd_4153のコードインベントリで波及先(テスト・共有コンポーネント)を確定する。

### 未決事項(殿裁定待ち)
1. 案Aの一覧に載せる列の選定(全設定項目は載らない。何を俯瞰したいか)
2. 単票エディタの2カラムカード構成を表形式へ寄せるか、現行維持か
3. FoF Weight Breakdownの既定=閉で問題ないか(as-of確認の頻度)
4. 一括操作(複数PF選択→フォルダ移動/visibility変更)の要否

## §4 証跡
- 本番CDP実測JSON: session scratchpad `admin_recon_report.json`(2026-07-24 12:55、cdp-browseスキル正本のauto-ops cdp_helper使用、認証済み)
- スクショ4枚: `admin_recon_admin.png` / `admin_recon_admin_fof.png` / `admin_recon_admin_folders.png` / `admin_recon_admin_visibility.png`
- コード全数偵察: cmd_4153(進行中) → `docs/research/cmd_4153_admin_ui_recon_20260724.md`

origin: `[[殿指示_admin一覧性改善_20260724]] -> [[将軍CDP4ページ実測+cmd_4153コード偵察]] -> [[admin-ui-redesign-asis-tobe-5w1h]]`

## §5 cmd_4299 visibility両面実測 (2026-08-13 19:30 JST)

### 5.1 調査範囲と一次ソース

- 対象: 本番 `https://dm-signal-frontend.onrender.com/admin/visibility`、認証済みCDP、DOM/getComputedStyle実測。実装・Save実行はしていない。
- コード正本: `/mnt/c/Python_app/DM-signal/frontend/app/admin/visibility/page.tsx`、同 `components/TierSelector.tsx` / `ManageTiersModal.tsx`。
- CDP実測条件: viewport `1036×906px`、DPR `1.5`、scrollY `0`。対象PFはDOM上102行、folder headerは6行。

### 5.2 コード機能インベントリ（grep/行番号確認済み）

| 機能 | 現物証跡 |
|---|---|
| Global/Tier状態・取得 | `page.tsx:71-108`（selectedTierId、global/tier settings、collapsedFolders）、`:134-195`（tiers/folders/global/tier fetch）、`:218-228`（未保存時Tier切替confirm） |
| L1 page visibility | `page.tsx:237-249`, `:660-741`（Core/Info checkbox、togglePageVisibility） |
| PF 3トグル | `page.tsx:251-275`（state更新）、`:1222-1333`（`hide_portfolio` / `hide_signal` / `hide_components`の個別UI） |
| 全PF一括トグル | `page.tsx:303-352`, `:767-865`（L2/L3/L4 header toggle、階層ルールで下位変更を抑止） |
| Folder一括トグル・hide | `page.tsx:287-300`, `:419-447`, `:911-1133`（folder settings、L2/L3/L4 bulk、L1.5 hide） |
| Folder開閉 | `page.tsx:107-110`（`Set<string>`）、`:450-460`（toggle）、`:473-480`（uncategorized/partial例外）、`:911-1042`（header button）、`:1135-1137`（collapsed時PF行を非描画） |
| Saveフロー | `page.tsx:482-548`, Save button `:600`。Tier/globalとも `hidden_pages`・`portfolio_settings`・`folder_settings`・`updated_at` のみ送信 |
| Tier切替・Manage起動 | `TierSelector.tsx:16-61`、`page.tsx:615-620`、Manage modal起動 `:1352-1357` |
| ManageTiers CRUD/並べ替え/パスワード | `ManageTiersModal.tsx:20-208`（load/create/update/delete/copy/reorder/copy-all/rotate-all）、描画 `:309-437` |
| 行スタイル | PF cell `page.tsx:1176,1210,1223,1259,1297`=`px-2 py-2`、thead `:770,773,776,806,836`=`px-2 py-3`、table `:767`、sticky thead `:768` |

### 5.3 CDP実測値

| 状態 | document/body scrollHeight | table scrollHeight | DOM行数 | 備考 |
|---|---:|---:|---:|---|
| 全フォルダ開 | 6,556px | 5,862px | 109 (`thead 1 + folder 6 + PF 102`) | PF行高は54.33–54.67px、folder headerは40px |
| 全フォルダ閉 | 980px | 286px | 7 (`thead 1 + folder 6`) | PF行はDOMから除去（`collapsed`条件） |

Computed styleはPF cell `padding-top/bottom=8px/8px`、`line-height=20px`、`font-size=14px`。thead cellは `12px/12px`、実測高さ46.33px、`position=static`（コード上は `sticky top-0`だが、computed styleのpositionはstatic）。viewport上端で完全に収まるPF行は2行、viewport内に一部交差するPF行は3行だった。

### 5.4 開閉状態の永続化確認（不一致を記録）

`rg`一次確認では `collapsedFolders` の参照は `page.tsx:108,450-460,479` のみで、`localStorage`/`sessionStorage`/API payloadへの参照は0件。`handleSave`（`:482-548`）にも `collapsedFolders` は含まれない。∴現行実装の開閉はReact stateによるセッション内表示制御であり、Saveによる開閉状態の永続化経路は確認できない。殿確認の「Saveで任意に固定」という前提とはコード一次情報が不一致のため、実装・補正は次の裁定へ持ち越す。

### 5.5 改善材料（実装しない）

- 行高圧縮: 現状PF行54.33–54.67px。`px-2 py-2`（上下8px）をadmin専用密度へ縮小する場合、canonical `py-3`を下回る変更なので、候補案として別裁定・再CDPが必要。
- 折りたたみ活用: 全開6,556px→全閉980px（5,576px、約85.0%減）。6 folder headerは全て40pxで、開閉は既存UIで実行可能。ただし現状は永続化されない。
- 検索/フィルタ: 102 PFを全開で1画面に完全表示できるのは2行のみ。PF名検索またはfolder filterは一覧性改善候補だが機能追加のため未裁定・未実装。

origin: `[[殿指示_visibility両面実測_20260813]] -> [[cmd_4299両面偵察]] -> [[AsIs調査の抜け_フォルダ開閉未言及]]`
