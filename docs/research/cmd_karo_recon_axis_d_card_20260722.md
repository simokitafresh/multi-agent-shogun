# DM-Signal D軸 card全component監査

検証日: 2026-07-22。一次情報: `/mnt/c/Python_app/DM-signal/frontend/components/**/*.tsx`（`__tests__`除外）。CDP不使用、実装変更なし。

## §1 母集団・検索契約

- component母集団: **67/67** (`rg --files frontend/components | rg '\.tsx$' | rg -v '/__tests__/'`)。
- 属性grep: surface=`bg-card|bg-background|bg-muted|bg-slate|glass`、radius=class token `rounded*`、shadow=`shadow*`、border=`border*`。
- file:lineは各属性の先頭一致。`× (0)`は当該ファイル内の属性token 0件。`Math.round`等はradiusから除外。
- 全体grep採用ファイル数: surface **43**、radius **41**（生grep43から`comparison-chart.tsx`/`total-return-chart.tsx`の計算変数2件を除外）、shadow **13**、border **44**。

## §2 §6.1形式 component × 属性カバレッジ

| component | surface | radius | shadow | border |
|---|---:|---:|---:|---:|
| `components/ErrorBoundary.tsx` | × (0) | ○ `:44` | × (0) | ○ `:44` |
| `components/GlobalErrorBanner.tsx` | ○ `:23` | ○ `:23` | × (0) | ○ `:23` |
| `components/RecalculateStatus.tsx` | ○ `:110` | ○ `:110` | × (0) | ○ `:110` |
| `components/annual-returns-chart.tsx` | ○ `:393` | ○ `:225` | ○ `:393` | ○ `:393` |
| `components/annual-returns-table.tsx` | ○ `:142` | ○ `:113` | × (0) | ○ `:166` |
| `components/auth-status.tsx` | ○ `:88` | ○ `:109` | × (0) | ○ `:82` |
| `components/chart/ChartAxes.tsx` | × (0) | × (0) | × (0) | ○ `:110` |
| `components/chart/ChartControls.tsx` | × (0) | × (0) | × (0) | × (0) |
| `components/chart/ChartLegend.tsx` | × (0) | × (0) | × (0) | × (0) |
| `components/chart/ChartTooltip.tsx` | ○ `:45` | ○ `:45` | ○ `:45` | ○ `:45` |
| `components/chart/FromYearSelector.tsx` | × (0) | × (0) | × (0) | × (0) |
| `components/chart/PeriodModeToggle.tsx` | ○ `:22` | ○ `:22` | ○ `:29` | × (0) |
| `components/chart/ScaleToggle.tsx` | ○ `:21` | ○ `:18` | × (0) | ○ `:18` |
| `components/chart/TimingToggle.tsx` | ○ `:25` | ○ `:22` | × (0) | ○ `:22` |
| `components/chart/YearRangeSelector.tsx` | ○ `:72` | ○ `:69` | × (0) | ○ `:69` |
| `components/compare-returns-table.tsx` | ○ `:128` | ○ `:156` | × (0) | ○ `:123` |
| `components/compare-summary-table.tsx` | ○ `:259` | ○ `:301` | × (0) | ○ `:254` |
| `components/comparison-chart.tsx` | × (0) | × (0) | × (0) | × (0) |
| `components/docs/deterioration-monitor-content.tsx` | ○ `:49` | ○ `:49` | × (0) | ○ `:63` |
| `components/docs/disclosures-content.tsx` | × (0) | ○ `:10` | × (0) | ○ `:10` |
| `components/docs/methodology-content.tsx` | ○ `:45` | ○ `:45` | × (0) | ○ `:69` |
| `components/docs/terms-content.tsx` | ○ `:22` | ○ `:22` | × (0) | × (0) |
| `components/drawdowns-chart.tsx` | × (0) | × (0) | × (0) | × (0) |
| `components/drawdowns-table.tsx` | ○ `:50` | × (0) | × (0) | ○ `:37` |
| `components/install-prompt.tsx` | ○ `:62` | ○ `:62` | ○ `:62` | ○ `:62` |
| `components/language-toggle.tsx` | ○ `:20` | ○ `:17` | × (0) | × (0) |
| `components/metrics-table.tsx` | × (0) | × (0) | × (0) | ○ `:69` |
| `components/mobile-menu.tsx` | × (0) | × (0) | × (0) | × (0) |
| `components/model-trades-table.tsx` | ○ `:177` | ○ `:148` | × (0) | ○ `:202` |
| `components/momentum-chart.tsx` | × (0) | × (0) | × (0) | × (0) |
| `components/monthly-returns-table.tsx` | ○ `:246` | ○ `:207` | × (0) | ○ `:284` |
| `components/monthly-trade-table.tsx` | ○ `:127` | ○ `:127` | × (0) | ○ `:351` |
| `components/mtd-chart.tsx` | × (0) | × (0) | × (0) | × (0) |
| `components/mtd-daily-table.tsx` | ○ `:124` | × (0) | × (0) | ○ `:120` |
| `components/page-navigation.tsx` | ○ `:29` | ○ `:28` | × (0) | × (0) |
| `components/page-shell.tsx` | ○ `:23` | × (0) | ○ `:46` | × (0) |
| `components/page-view-tracker.tsx` | × (0) | × (0) | × (0) | × (0) |
| `components/period-notes.tsx` | × (0) | × (0) | × (0) | ○ `:39` |
| `components/portfolio-details.tsx` | ○ `:6` | ○ `:211` | × (0) | ○ `:162` |
| `components/portfolio-nav-selector.tsx` | ○ `:71` | ○ `:71` | × (0) | × (0) |
| `components/portfolio-select-items.tsx` | × (0) | × (0) | × (0) | × (0) |
| `components/portfolio-selector.tsx` | ○ `:123` | ○ `:105` | × (0) | ○ `:105` |
| `components/risk-management-table.tsx` | ○ `:46` | ○ `:46` | × (0) | ○ `:56` |
| `components/rolling-return-chart.tsx` | ○ `:327` | ○ `:327` | ○ `:333` | ○ `:570` |
| `components/rolling-returns-distribution-table.tsx` | × (0) | × (0) | × (0) | ○ `:72` |
| `components/rolling-returns-summary-table.tsx` | ○ `:149` | × (0) | × (0) | ○ `:94` |
| `components/sidebar.tsx` | ○ `:354` | ○ `:372` | × (0) | ○ `:354` |
| `components/signal-pie-chart.tsx` | ○ `:52` | ○ `:52` | ○ `:52` | ○ `:52` |
| `components/summary-table.tsx` | × (0) | × (0) | × (0) | ○ `:147` |
| `components/sw-register.tsx` | ○ `:75` | ○ `:75` | ○ `:75` | ○ `:75` |
| `components/theme-provider.tsx` | × (0) | × (0) | × (0) | × (0) |
| `components/theme-toggle.tsx` | ○ `:19` | ○ `:19` | ○ `:43` | ○ `:43` |
| `components/total-return-chart.tsx` | × (0) | × (0) | × (0) | × (0) |
| `components/ui/accordion.tsx` | × (0) | × (0) | × (0) | ○ `:42` |
| `components/ui/button.tsx` | ○ `:19` | ○ `:15` | × (0) | ○ `:19` |
| `components/ui/dropdown-menu.tsx` | ○ `:72` | ○ `:72` | ○ `:72` | ○ `:72` |
| `components/ui/folder-filter-chip.tsx` | × (0) | ○ `:15` | × (0) | ○ `:15` |
| `components/ui/glass-card.tsx` | ○ `:10` → CSS `globals.css:139-145` | ○ CSS `:140` | ○ CSS `:141,145` | ○ CSS `:121-136` |
| `components/ui/input.tsx` | ○ `:12` | ○ `:12` | × (0) | ○ `:12` |
| `components/ui/latex.tsx` | × (0) | × (0) | × (0) | × (0) |
| `components/ui/loading.tsx` | × (0) | × (0) | × (0) | × (0) |
| `components/ui/message-banner.tsx` | ○ `:21` | ○ `:21` | × (0) | ○ `:21` |
| `components/ui/page-header.tsx` | × (0) | × (0) | × (0) | × (0) |
| `components/ui/select.tsx` | ○ `:100` | ○ `:100` | ○ `:244` | ○ `:100` |
| `components/ui/skeleton.tsx` | ○ `:12` | ○ `:12` | × (0) | × (0) |
| `components/up-down-market-chart.tsx` | ○ `:312` | ○ `:486` | ○ `:637` | ○ `:281` |
| `components/viewer-auth-modal.tsx` | ○ `:156` | ○ `:156` | ○ `:156` | ○ `:156` |

## §3 variants・基準外・再利用候補

| 対象 | 実測整数 | 判定 |
|---|---:|---|
| surface variant | **8** | `glass-card`, `glass`, `bg-card`, `bg-background`, `bg-muted`, `bg-slate-600`, `bg-slate-800`, `bg-slate-900` |
| radius variant | **4** | `rounded`, `rounded-md`, `rounded-lg`, `rounded-xl`（GlassCardは`rounded-2xl`を加え全体では5） |
| shadow variant | **4** | `shadow-sm`, `shadow-md`, `shadow-lg`, `shadow-xl`（GlassCard custom shadowを加え全体では5） |
| 基準外component | **19** | surfaceを持つ43件のうち、基準候補`glass-card`/`bg-card`/`bg-background`以外の直接surface (`glass`,`bg-muted`,`bg-slate-*`) を持つcomponent |
| 再利用候補 | **3** | `GlassCard`、CSS semantic `--card`/Tailwind `bg-card`、`PageHeader`（card属性は持たないが共有器の先例） |

統一基準候補は、データ面を `GlassCard`（surface=`glass`、radius=`rounded-2xl`、custom shadow）へ寄せるか、軽量面を `bg-card border-border rounded-lg shadow-sm` に固定する二variant。新規tokenを作る前に既存 `GlassCard` と `--card` を再利用可能。`page-header.tsx`はcard SSOTではないが、共有component+canonical classという統一方法を再利用可能。`colors.ts`はchart/status色SSOTでありcard surface/radius/shadowの定義はなく、D軸への直接再利用は不可。

## §4 二値検証

- component inventory **67/67**、表行 **67/67**、未確認 **0**。
- 実装変更 **0**（DM-Signal frontendはread-only）。成果物1件のみ。
- CDP呼出 **0**。
- 統一候補は現存資産3件を現物確認し、直接再利用可2、方法再利用可1、`colors.ts`直接再利用不可1を明記。

origin: `[[殿指示_デザイン統一_20260722]] -> [[D軸card全component監査]] -> [[GlassCard_semantic_card二variant候補]]`
