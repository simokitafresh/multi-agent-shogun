# DM-Signal page style MECE — compare-summary / deterioration

検証日: 2026-07-22  
検証方法: `/mnt/c/Python_app/DM-signal` の `page.tsx` と直接 import される表示componentを静的全数追跡。Tailwind class、component prop、JSX属性を一次根拠とした。N/Aは該当UIが存在しないコード根拠を記載した。

## §1 依存グラフ（表示・styleに関与する全import component）

```text
compare-summary/page.tsx
├─ TimingToggle -> cn
├─ CompareSummaryTable -> Link, useSortableTable, deterioration-colors, compare-summary types, cn
├─ MobileMenu -> AuthStatus, ThemeToggle, DropdownMenu, viewer permissions
├─ PageNavigation / HomeButton -> portfolio-param hook
├─ FolderFilterChip -> cn
└─ MessageBanner -> lucide icons, cn

deterioration/page.tsx
├─ ChartTooltip / TooltipItem -> cn
├─ MobileMenu -> AuthStatus, ThemeToggle, DropdownMenu, viewer permissions
├─ PageNavigation / HomeButton -> portfolio-param hook
├─ Accordion -> lucide ChevronRight/ChevronDown, cn
└─ FolderFilterChip -> cn
```

根拠: compare-summary の component imports は `frontend/app/compare-summary/page.tsx:4-9`、deterioration は `frontend/app/deterioration/page.tsx:4-8`。`CompareSummaryTable` の下流は `frontend/components/compare-summary-table.tsx:3-16`、MobileMenu は `frontend/components/mobile-menu.tsx:3-6`、Accordion は `frontend/components/ui/accordion.tsx:3-5`。`PageNavigation` 自体は描画 `null` (`frontend/components/page-navigation.tsx:9-11`) で、実表示は HomeButton のみ。

## §2 2ページ × A-J 全20セル

| 軸 | compare-summary | deterioration |
|---|---|---|
| A 外枠・最大幅 | `main min-h-screen bg-background`。header/contentとも `max-w-7xl xl:max-w-[120rem] mx-auto px-4 md:px-8` でXL時120remまで拡張 (`frontend/app/compare-summary/page.tsx:249-251,278`)。 | `div max-w-7xl mx-auto px-4 py-8` の単一外枠で背景/min-height指定なし、120rem拡張なし (`frontend/app/deterioration/page.tsx:1172`)。loading/errorも同じ7xl (`1126,1153`)。 |
| B ヘッダー構造 | `header space-y-2` 内に nav/title/timing と右側Home/Mobile、as-ofを別行 (`252-272`)。 | `mb-6` 内に nav/title と右側Home/Mobile、as-ofを別行 (`1174-1200`)。TimingToggleはimportも描画もなくN/A (`frontend/app/deterioration/page.tsx:1-31`)。 |
| C タイポグラフィ | h1=`text-2xl md:text-3xl font-bold tracking-tight text-foreground` (`256`)。as-of=`text-sm text-muted-foreground` (`266`)。 | h1=`text-2xl font-bold`、responsive拡大・tracking・明示foregroundなし (`1178`)。as-of=`text-sm text-muted-foreground mt-1` (`1196`)。 |
| D 余白・密度 | header上 `pt-4 md:pt-8`、content `py-4 md:py-8`。header `space-y-2`、filter `gap-1 mb-3` (`251-252,278,286`)。 | 外枠は常時 `py-8`、header `mb-6`、folder filter `gap-1 mb-3`、label filter `gap-2 mb-4` (`1172-1175,1205,1239`)。mobileでも縦余白8を維持。 |
| E フィルター | FolderFilterChip群のみ。All/各folder/Uncategorized/Clearを共通componentで表示 (`286-318`)。 | 同一folder filter (`1205-1234`) に加え、状態label filterを `px-3 py-1 rounded-full text-xs font-medium border` で追加 (`1239-1275`)。二段のchip体系。 |
| F 表・データ密度 | `CompareSummaryTable`。`overflow-auto max-h-[70vh] lg:max-h-[82vh]`、sticky headerとsticky name列、`px-3 py-3` (`frontend/components/compare-summary-table.tsx:324-376`)。 | Accordion内 `overflow-x-auto` + `w-full text-sm`。header/セル `px-3 py-3`、sticky/max-heightなし (`frontend/app/deterioration/page.tsx:1281-1348`)。行展開detailあり (`1418-1432`)。 |
| G 色・状態表現 | FoF紫、Benchmark amber、CAGR正green/負red、MaxDD red (`frontend/components/compare-summary-table.tsx:377-393`)。凡例でFoF/Benchmarkを色+文言併記 (`frontend/app/compare-summary/page.tsx:330-338`)。dotはaria-label/title付き (`compare-summary-table.tsx:403-417`)。 | label chipはgreen/yellow/orange等のbg+text+border、表はG1/G2/P/p̄をColorDot、labelをLabelBadge、trendをicon+colorで表現 (`frontend/app/deterioration/page.tsx:73-105,1253-1264,1351-1408`)。複数表現だがページ末尾の常設凡例はN/A。 |
| H 操作・affordance | column header sort、portfolio名Link、TimingToggle switch、folder filter。sort header=`cursor-pointer hover:text-foreground select-none` (`compare-summary-table.tsx:329-353`)、Link=`hover:underline` (`422-431`)。 | column sort、desktop行click展開、Accordion開閉、2種filter。行はdesktopのみ `hover:bg-muted/30 cursor-pointer` (`frontend/app/deterioration/page.tsx:1336-1342`)。mobile行展開は無効 (`1331-1334`)。 |
| I レスポンシブ | container `md:px-8`/`xl:120rem`、title `md:text-3xl`、table非mobile列=`hidden md:table-cell`、name列160→200px、table height 70→82vh (`page.tsx:251,256`; `compare-summary-table.tsx:324-376`)。 | container pxは常時4、max7xl。非mobile列=`hidden md:table-cell`、dot 10→12px (`frontend/app/deterioration/page.tsx:1289-1300,1348-1413`)。desktopのみdetail展開。title/outer spacingはbreakpoint不変。 |
| J loading/error/empty/a11y | hidden/errorはMessageBannerのicon+message (`page.tsx:237-245,280-284`; `message-banner.tsx:18-40`)。loadingは表skeleton、emptyは中央文 (`compare-summary-table.tsx:248-320`)。TimingToggleはrole=switch/aria-checked (`TimingToggle.tsx:18-34`)。 | loadingは5本skeleton、errorは裸の `text-red-500`、emptyは中央文 (`page.tsx:1124-1167,1438-1444`)。ColorDotにlabel、Accordionはbuttonだがaria-expanded/controlsなし (`accordion.tsx:23-43`)。 |

完全性: ページ 2/2、軸 10/10、セル 20/20。N/Aは B の deterioration TimingToggle、G の deterioration常設凡例のみで、いずれもimport/描画不在を明記した。

## §3 軸別差異と統一候補

| 軸 | 差異（重複しない所見） | ui-design-guide照合 | 統一候補 |
|---|---|---|---|
| A | compareは背景+min-height+XL 120rem、deteriorationは7xl単一div。 | §1「Keep patterns consistent」逸脱。 | 共通 `PageShell` で背景/min-height/paddingをSSOT化し、wide-table propだけ最大幅を切替。 |
| B | header wrapperが `header space-y-2` 対 `div mb-6`、TimingToggle有無。 | 同じページ見出しjobの構造不一致。 | `PageHeader` に title/asOf/actions/controls slotを定義。 |
| C | 同格h1がcompareのみmd:3xl/tracking-tight/foreground。 | §1 visual hierarchy / consistent patterns逸脱。 | h1 tokenを `text-2xl md:text-3xl font-bold tracking-tight text-foreground` に統一。 |
| D | mobile縦余白がcompare 4、deterioration 8。 | related groups spacingの一貫性不足。 | shell spacingを `py-4 md:py-8`、header-to-content spacingを共通token化。 |
| E | 共通folder chipsは一致、deterioration label chipだけ寸法・gapが別体系。 | 同じbutton shape for same jobとの境界が曖昧。 | filter semanticsをfolder/statusでvariant化し、hit area・active treatmentを共通componentに集約。現状 `py-0.5`/`py-1` は§1 48pt hit areaを満たさない。 |
| F | compareはsticky縦スクロール表、deteriorationはpage縦スクロール+Accordion+展開行。 | 機能差は妥当だが表header/cell token重複。 | TableShell/SortableHeader/metric-cellの基礎classのみ統一し、sticky/expandはvariant維持。 |
| G | compareは色+凡例、deteriorationはdot/badge/trendの複合だが常設凡例なし。 | §1「Do not rely on color alone」。dotはaria-labelが補完するが視覚利用者向け説明が弱い。 | 共通status legendまたはdot横短縮labelを追加。意味色tokenを deterioration-colors SSOTへ寄せる。 |
| H | compare名Linkはunderline affordance、deterioration行は全体clickでdesktopのみ。 | §1「Similar look must mean similar behavior」「Keep important content visible」。 | 行展開に明示button/chevronを置きmobileでも同操作を提供。sortable headerはbutton化。 |
| I | breakpoint/幅/余白が不統一、deteriorationはmobileで詳細へ到達不能。 | clarityとinteraction consistency逸脱。 | shared responsive shell + mobile detail disclosureを実装候補とする。 |
| J | compareはMessageBanner、deterioration errorは裸文字。Accordionにaria-expandedなし。 | §1 color-alone禁止、interface clarity、contrast/affordanceに逸脱。 | loading/error/emptyを共通StatePanel化。Accordionへ `aria-expanded`, `aria-controls`, idを付与。 |

## §4 CE / ME 二値検証

- CE-pages: **PASS** — 2/2 (`compare-summary`, `deterioration`)
- CE-axes: **PASS** — A-J 10/10
- CE-cells: **PASS** — 20/20、空セル0、根拠なしN/A 0
- ME-findings: **PASS** — 所見10件を各軸へ一意帰属、重複0件
- unresolved/blocking: **0件**
- MECE attribution candidates: 20、true_positive: 20、false_positive: 0（全セルが各軸定義に一意帰属し、別軸へ重複計上なし）
