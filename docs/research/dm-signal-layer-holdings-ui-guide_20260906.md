# Layer Holdings Monthly ページ UI ガイド(cmd_4489 P3 用。殿 2026-09-06 23:43『デザインは DM-Signal に合わせる』/23:45『フォント・サイズ・コントラスト・カード不使用などデザインガイドを渡せ』)

読者: cmd_4489 担当忍者(才蔵)と家老・軍師レビュー。wireframe(gist 6ae60a9c)は**情報構造の正本**、見た目は**本書=DM-Signal 既存規約**が正本。迷ったら既存ページ(`frontend/app/monthly-returns/page.tsx`、`compare-returns`、`rolling-returns`)と同じにする。

## §1 フォント(正本: context/dm-signal-frontend.md §19-21、cmd_4124/4127/4128 で本番全数統一済み)

| 要素 | 規約 |
|---|---|
| 文字 | Inter(既存の `font-sans`。新フォント追加禁止) |
| 数値 | `ui-monospace` + `tabular-nums`(weight %、pf_count、year_month の数字列) |
| サイズ | 表本体 14px・表ヘッダ 14px(canonical)。ページ見出しは既存 `page-header` の階層をそのまま。矢印/アイコンだけ 18px 可 |
| weight | regular と bold の 2 段のみ。見出し=bold、本文/補助=regular |
| 大文字 | 全大文字は短いラベルのみ(既存 th と同じ)。それ以外は sentence case |
| 行間 | 本文 1.5 以上(既存の Tailwind 既定を変えない) |
| 揃え | 文字列は左揃え、数値列は右揃え(既存表と同じ) |

## §2 色とコントラスト(正本: context/ui-design-guide.md §1/§2、cmd_4124)

| 要素 | 規約 |
|---|---|
| 値の色 | 正値・通常値=`text-foreground`(light は黒寄り、dark は白)、負値=`text-red-400`(両モード)。本ページは weight ≥0 なので基本 `text-foreground` |
| 文字コントラスト | 18px 以下は 4.5:1 以上。補助文字(`text-muted-foreground`)も既存トークンをそのまま使う(独自グレーを作らない) |
| UI 要素コントラスト | ボタン/タブ/枠線/積み上げ棒の区切りは背景に対し 3:1 以上 |
| 色の意味 | 色だけで意味を持たせない。ticker は色+ラベル(棒内に ticker 名、幅が狭いときは title 属性+右の凡例)。凡例は既存 chip の型 |
| ticker 色 | 既存の ticker 色定義があればそれ(grep `XLU|TQQQ|GLD|TMV` を frontend/lib・components で確認)。無ければ Tailwind 既存パレット(`bg-blue-500` 等)から選び、light/dark 両方で棒内の白文字が 3:1 を満たすものだけ。wireframe の `PALETTE` hex は持ち込まない |
| 純黒本文 | 使わない(既存 `text-foreground` が既にダークグレー/白) |

## §3 コンテナとレイアウト(正本: context/ui-design-guide.md『Remove unnecessary containers』、cmd_4153 admin 偵察=カード縦積みが一覧性を落とした実証)

| 規約 | 内容 |
|---|---|
| **カードを使わない** | wireframe の `.card`(白背景+枠線+角丸)で 2 面を囲む構造は持ち込まない。`glass-card` も使わない。既存ページ(monthly-returns/compare-returns)と同じく、`mx-auto min-h-[400px] w-full max-w-[1100px]` の中に見出し→操作列→本体を**余白で**区切る |
| 区切り | 余白(gap/space-y)を第一手段にする。枠線・影・塗りは意味がある時だけ(表の行区切りは既存 `border-b` の型) |
| 見出し | 既存 `page-header`(タイトル+補足 1 行)。補足に「出所: 月次再計算後に自動更新 / 更新 {calculated_at}」を置く |
| 操作列 | layer 選択 5 と期間 3 は既存の `folder-filter-chip` または `button`(secondary=outline、選択中=primary fill)の型。**1 画面の primary は 1 つ**なので、選択中の chip だけを強調し、それ以外は outline。独自 `.tab` CSS を作らない |
| 積み上げ横棒 | 1 行=`year_month`(左、mono)+棒(flex、各 seg は `style={{width: pct%}}`)+`pf_count`(右、mono)。棒の高さは既存表の行高(概ね 32-36px)に合わせ、角丸は既存 radius トークン。行間は余白で。MTD 行は `opacity` ではなく `text-muted-foreground`+「MTD」ラベル(色だけに頼らない) |
| 生表(直近 3 ヶ月) | 既存 `<table>` 規約(th 14px 大文字ラベル、td 14px、数値右揃え mono、`border-b`)。wireframe の独自 table CSS は使わない |
| 状態表示 | 401/403=既存 error 表示、503=既存 `message-banner`(『集計待ち』)、loading=既存 `skeleton`/`loading`(`useDelayedLoading` 300ms) |
| モバイル | 棒と表は横スクロールを自分のコンテナ内で(`overflow-x-auto`)。ページ全体を横スクロールさせない(N2 の教訓) |
| ボタン/chip の hit 領域 | 44-48px 以上。隣接 chip の間隔は既存と同じ |

## §4 やらないこと

- 新規 CSS ファイル・新規色トークン・新規フォント・グラフ library・`glass-card`/独自カード・wireframe の `<style>` 移植・ダークモード用の独自色分岐(既存トークンが両モードを持つ)。
- 見た目の「wireframe 一致」は AC ではない。AC5 の 6 要素(layer タブ 5/期間 3/積み上げ横棒/pf_count/直近 3 ヶ月表/MTD)が揃い、上記規約に従っていること。

## §5 参照(読む順)

1. `context/ui-design-guide.md` §1-§2(14 tips、コントラスト閾値表)
2. `context/dm-signal-frontend.md` §19-§23(値配色、表フォント 14px、admin カード縦積みの失敗、モバイル sticky/overflow)
3. `docs/research/dm-signal-page-style-diff-mece_20260722.md` v3.0(ページ体裁差の MECE 是正の経緯と PLAYBOOK)
4. DM-Signal repo `frontend/app/monthly-returns/page.tsx`、`frontend/app/compare-returns/page.tsx`、`frontend/components/ui/*`(button/page-header/folder-filter-chip/skeleton/message-banner)

- origin: `[[殿指示_LayerHoldingsMonthly本番ページ_20260906_2207]] -> [[殿指示_UIはDM-Signalに合わせる_20260906_2343]] -> [[layer_holdings_ui_guide]] -> [[cmd_4489_layer_holdings_P3_page]]`
