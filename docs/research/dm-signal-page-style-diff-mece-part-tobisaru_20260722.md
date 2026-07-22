# DM-Signal page-style MECE fragment — FAQ / Offline

検証日時: 2026-07-22 JST  
対象commit: `/mnt/c/Python_app/DM-signal` `git rev-parse HEAD` 実測  
範囲: `/faq`, `/offline` の2ページ。A–Jは親資料 `docs/research/dm-signal-page-style-diff-mece_20260722.md:36-51` の定義をそのまま使用した。

## 1. 依存グラフと route inventory (AC1)

### FAQ

`frontend/app/faq/page.tsx:3-13` → React (`useState/useEffect/Suspense`), Next (`useSearchParams/useRouter`, `Link`), `lucide-react/ExternalLink`, `GlassCard`, `Accordion`, `LanguageToggle`, `Loading`, `PageHeader`, `faqContent` 型/データ, `cn`。このうち描画へ到達するローカル依存は次の通り。

- `GlassCard` → `cn`: `frontend/components/ui/glass-card.tsx:1-10`; 実体classは `.glass-card`: `frontend/app/globals.css:119-146`。
- `Accordion` → React state, lucide Chevron, `cn`: `frontend/components/ui/accordion.tsx:1-42`。
- `LanguageToggle` → `cn`: `frontend/components/language-toggle.tsx:1-33`。
- `Loading` → lucide Loader2: `frontend/components/ui/loading.tsx:1-13`。
- `PageHeader` → `MobileMenu`, `ThemeToggle`, `cn`: `frontend/components/ui/page-header.tsx:21-72`。
- FAQ表示データ/型: `frontend/lib/faq-content.ts:4-40`。`Link` と `cn` はpageでimportされるが参照0件（`frontend/app/faq/page.tsx:5,13` と同ファイル全体の識別子照合）。
- 共通layout → Inter, Sidebar等の全体shell: `frontend/app/layout.tsx:1-14,57-75`; Tailwind token/breakpoint: `frontend/tailwind.config.ts:13-52`。

### Offline

`frontend/app/offline/page.tsx:1-2` → `GlassCard`, `lucide-react/WifiOff`。`GlassCard` → `cn` → `.glass-card` の依存は上記と同一。共通layout/globals/TailwindもFAQと同じ。

### `frontend/app/**/page.tsx` 全数検算

`find frontend/app -name page.tsx -type f | sort` = **21/21件**。admin 4件 (`admin`, `admin/fof`, `admin/folders`, `admin/visibility`) を親資料の明示スコープ外として除くとviewer routeは **17/17件**:

`/`, `/annual-returns`, `/compare`, `/compare-returns`, `/compare-summary`, `/dashboard`, `/deterioration`, `/docs`, `/drawdowns`, `/faq`, `/metrics`, `/monthly-returns`, `/monthly-trade`, `/offline`, `/rolling-returns`, `/summary`, `/trades`。

親資料§0の15項目との独立照合結果は **過不足あり**。実在17 routeに対し、(1) `/` と `/docs` が親15項目に未掲載、(2) 親の `Signals` は独立 `page.tsx` が存在しない（Dashboard内表示という概念項目）、(3) `/compare` と `/compare-summary` は1項目へ集約されている。したがって「15 conceptual items」は実route inventoryと1:1ではない。FAQ/Offline自体は2/2実在。

## 2. 2ページ × A–J 差分マトリクス (AC2)

| 軸 | FAQ | Offline |
|---|---|---|
| A タイポグラフィ | 共通Inter (`layout.tsx:2,14,58`; `globals.css:111-115`)。PageHeader h1=`text-2xl md:text-3xl font-bold tracking-tight` (`page-header.tsx:52-65`)。質問=`text-sm font-medium`、回答=`text-muted-foreground`、節h4=`font-semibold` (`faq/page.tsx:149-160,267-270`)。 | 共通Inter。h1=`text-2xl font-bold`、本文は既定size+`text-muted-foreground` (`offline/page.tsx:11-14`)。FAQと異なりmdで3xl化・tracking-tightなし。 |
| B カラー | 背景/前景token=`bg-background`/`text-foreground`; muted本文、border token、リンクは固定`sky-400/300` (`faq/page.tsx:342,362-375,394,423`)。token実値はlight/dark (`globals.css:5-20,59-75`)。 | 背景/前景token。icon円=`bg-secondary/20 text-muted-foreground`、本文muted (`offline/page.tsx:6-14`)。固定accent/status色なし。 |
| C スペーシング | 外周`p-4 md:p-8`; max幅内`space-y-6 md:space-y-8`; card `p-4 md:p-6`; CTA内`space-y-6`, list `space-y-2 ml-6` (`faq/page.tsx:342-343,357,407-433`)。 | 外周`p-4`; card=`p-8 space-y-4`, icon=`p-4` (`offline/page.tsx:6-8`)。FAQより固定・中央集約。 |
| D コンテナ/カード | 各section/glossary/reference/CTAをGlassCard。page propの`p-4 md:p-6`が基底`p-6`をtwMerge上書き (`faq/page.tsx:289,357,385,407`; `glass-card.tsx:8-10`)。基底=`glass rounded-2xl p-6`+shadow (`globals.css:119-146`)。 | 単一GlassCard=`max-w-md w-full flex flex-col items-center text-center p-8`。同じ基底radius/shadowだがpadding/幅/整列が固有 (`offline/page.tsx:7`)。 |
| E テーブル | FAQ本文Markdown tableとGlossary tableあり。`w-full text-sm`, `border-b border-border/50` header, cells `py-2 px-3`, body border `/30`; header左揃え、stripe/hover/数値右揃え/桁処理なし (`faq/page.tsx:45-68,359-379`)。 | **N/A**: page JSX 1-18にtable要素/importなし。 |
| F ボタン/リンク/interaction | Accordion/質問buttonは`hover:opacity-80 transition-opacity` (`accordion.tsx:23-42`; `faq/page.tsx:263-276`)。言語toggleはactive fill sky-500、inactive muted、rounded左右 (`language-toggle.tsx:13-33`)。linkはsky色+hoverのみで下線/focus classなし (`faq/page.tsx:223-231,390-398,419-427`)。 | **N/A**: page JSX 1-18にbutton/link/handlerなし。 |
| G チャート/グラフ | **N/A**: page import/JSXにchart library/componentなし (`faq/page.tsx:3-13,341-458`)。 | **N/A**: page JSX 1-18にchartなし。 |
| H ヘッダー/nav/tab | `PageHeader`使用。title/subtitle+LanguageToggle、MobileMenu/ThemeToggleを内包 (`faq/page.tsx:345-349`; `page-header.tsx:52-72`)。tab/breadcrumbなし。共通Sidebarはlayout (`layout.tsx:73-75`)。 | PageHeader不使用。中央card内の素h1のみ (`offline/page.tsx:6-15`)。共通Sidebarはlayout由来だがoffline固有nav/tab/breadcrumbなし。 |
| I loading/empty/error | Suspense fallbackは`min-h-[400px]`中央の共通`Loading`（Loader2 `animate-spin` + text、role/status） (`faq/page.tsx:444-457`; `loading.tsx:8-13`)。empty/error/304固有処理なし。 | offline自体が接続不能状態表示。WifiOff 48px+明示文 (`offline/page.tsx:6-14`)。spinner/empty/error分岐/304処理なし。 |
| J responsive | `p-4→md:p-8`, gap `space-y-6→md:space-y-8`, h1 `2xl→md:3xl`, card `p-4→md:p-6`; table `overflow-x-auto` (`faq/page.tsx:45,342-343,345-349,357-360`)。共通sidebar breakpointは1100/1280px (`tailwind.config.ts:13-21`; `layout.tsx:74`)。 | breakpoint固有classなし。`w-full max-w-md`, `p-4`外周により小画面縮退 (`offline/page.tsx:6-7`)。共通sidebar breakpointのみ適用。 |

## 3. 差異・guide逸脱・統一候補 (AC3)

### 軸別差異

1. A/H: FAQは共通PageHeader (`2xl→3xl`, tracking-tight, mobile controls)、Offlineは素h1 (`2xl`)。同じ「ページタイトル」の実装が二系統。
2. C/D/J: FAQはresponsive外周/card paddingと`max-w-6xl`; Offlineは固定`p-4`/`p-8`と`max-w-md`中央配置。状態画面として幅差は妥当だが、共通shell/headline tokenは未共有。
3. F: FAQのリンクは色だけで識別し下線なし。Accordion/質問buttonにはhoverはあるがfocus-visible classと48pt最小高さの明示なし。
4. I: FAQは共通Loadingを利用、Offlineは専用状態画面。目的が異なるため同一分類内の重複所見ではなく「待機」と「接続不能」の別状態。

### `context/ui-design-guide.md` 逸脱

- FAQ links (`faq/page.tsx:228,394,423`) は§1/§6「Do not rely on color alone / Links need more than color」に逸脱（underline等なし）。
- FAQ accordion/question buttons (`accordion.tsx:24-39`; `faq/page.tsx:263-273`) とLanguageToggle (`language-toggle.tsx:14-37`) は§1/§3の48pt touch targetをclass上保証していない。
- Offline h1はPageHeaderと異なるが、短い状態画面を中央整列すること自体は§4「body left align」の対象外。本文も短文なので逸脱とは判定しない。

### 統一候補

- タイトルtokenはPageHeaderの `text-2xl md:text-3xl font-bold tracking-tight` をSSOT候補にし、Offlineには状態画面用variant（中央配置・nav非表示可）をpropで表現する。
- リンクは共通link componentまたはclassへ `underline underline-offset-*` と`focus-visible`を追加し、FAQ内3経路（inline/reference/CTA）を統一する。
- interactive controlは共通 `min-h-12` 相当とfocus-visible ringをAccordion、FAQQuestion、LanguageToggleへ統一する。
- 状態表示はLoadingとOfflineの意味は統合せず、icon/heading/bodyのtypography・spacingだけ共通StatePanel primitive候補にする。

## 4. MECE二値検証 (AC4)

| check | 実測 | result |
|---|---:|---|
| 担当ページ網羅 | 2/2 | PASS |
| 軸網羅 | 10/10 | PASS |
| matrix cell | 20/20（N/A 5セルもコード根拠あり） | PASS |
| `page.tsx` inventory | 21/21全数列挙、viewer 17/17分類 | PASS |
| 親15項目との過不足検出 | 差異4類型（未掲載route 2、非実在独立page 1、2route集約1） | PASS（差異は未解消条件として明記） |
| ME所見重複 | 0件（A=文字、B=色、C=距離、D=surface、E=table、F=操作、G=graph、H=page chrome、I=状態、J=viewport adaptationに一意帰属） | PASS |

品質計測: cell attribution候補 **20**、true positive **20**、false positive **0**。route inventory差異を隠さずBLOCK条件へ変換するため、親資料の「15項目=全実route」とする統合は **BLOCK**。15項目をconceptual inventoryとして維持するなら、`/`・`/docs`・Signals内包・Compare集約の注記が必須。

