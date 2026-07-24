# DM-Signal Admin画面 一覧性改修 — AsIs/ToBe 5W1H設計書 v1.0

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
