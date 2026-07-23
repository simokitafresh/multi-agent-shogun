# DM-Signal page style MECE v2 — 全21 page × A–L 12軸 スタイル統一設計書

> ★このドキュメントを初めて読むLLM/人へ: まず本§METAを最後まで読め。前提を飛ばすと必ず誤解する。特に「測定はgrep禁止・CDP必須」「canonical(正)は殿裁定で確定済み」の2点を外すと過去の事故(本番色崩れ・フォント不統一)を再生産する。

## §META — 前提情報(5W1H) / AsIs-ToBe / バージョン / 索引

### バージョン履歴
| ver | 日付 | 転換点 | 誰の裁定 |
|---|---|---|---|
| v1 | 2026-07-22 | 全21page×A-L 12軸=252セルのMECE差分マトリクスを初版化 | 殿 |
| v2.0 | 2026-07-22 | §6実装粒度ブレークダウン(1cmd=1忍者)+§6.1コンポーネント×属性カバレッジ表を追加(A4/B1が対象表未明示で4表取りこぼした反省) | 殿裁定「粒度を小さく」 |
| **v2.1** | **2026-07-23** | **測定方式をソースgrep一次 → 本番CDP getComputedStyle一次へ転換(grepは描画を見ないため誤検出)。役割別粒度(ヘッダ/本体数値/本体文字)導入。色/フォントcanonicalを殿裁定で明示固定。§META(前提)追加** | 殿指摘「grepは見落とすぞ」「前提がないと誤解が生まれる」 |

### 5W1H(この設計書の前提)
- **Why(なぜ存在するか)**: DM-Signal本番FEの全21ページで、表・見出し・色・余白等のスタイルがページ/コンポーネントごとにバラバラ。殿が本番ライブレビューで不統一を繰り返し検出。場当たり修正では取りこぼす(1ページに複数コンポーネントの表が同居し、ページ名だけ見ると別componentの表を見落とす)ため、全数を軸×コンポーネント×属性×役割のマトリクスで管理し、取りこぼし0を実測証明する。
- **What(何を統一するか)**: 21ページを12軸(A typography / B color / C spacing / D card / E table / F interaction / G chart / H header / I states / J responsive / K viewport-color / L copy)で全数統一。
- **Who(誰が何を)**: 将軍=canonical確定(殿裁定を仰ぐ)+本番CDP実測(偵察入口・検証出口)。家老=cmd配備判断とGATE。忍者=コード実装+jest/tscで完結(per-task CDP禁止)。軍師=レビュー。
- **When(いつ)**: 2026-07-22起票、継続中。各軸は独立cmdで順次。
- **Where(どこが一次情報か)**: コード=`/mnt/c/Python_app/DM-signal/frontend`。**描画の真実=本番`https://dm-signal-frontend.onrender.com`のCDP getComputedStyle(ソースコードのclassnameではない)**。6断片の行番号詳細=`docs/research/fragments/mece_v2_{hayate,hanzo,kagemaru,kotaro,saizo,tobisaru}_20260722.md`。
- **How(どう測り、どう完了とするか)**: 測定は本番CDP getComputedStyle(§6.1手順)。**grepは○/×判定に使うな**(CSS継承/上書き/グループセレクタ/条件分岐class/semantic tokenを見ず、ソース文字列≠描画フォント)。完了=CDP実測で逸脱0を全数証明+本番デプロイ後に将軍が全数実物確認。

### canonical(正=殿裁定で確定済み。統一の基準はこれ。多数決・既存踏襲で決めるな)
| 対象 | canonical | 裁定 |
|---|---|---|
| 表本体・数値 | **14px / ui-monospace / tabular-nums** | 殿 2026-07-23 10:15 |
| 表本体・文字(ラベル) | **14px / Inter** | 殿 2026-07-23 10:15 |
| 表ヘッダ | **14px / Inter** | 殿 2026-07-23 10:15 |
| 値の色(getValueColorClass) | 正値=**text-foreground**(light黒寄り#0f172a/dark白#f8fafc) / 負値=**text-red-600 dark:text-red-400**(light濃色/dark現行維持) / 0・null=空文字 | 殿 2026-07-23 01:05、cmd_4142でlight contrast是正(2026-07-24) |
| status色バッジ(STATUS_TEXT_CLASSES) | 正=emerald-400/負=red-400/warning=amber-400/neutral=muted-foreground。★**値の色とは別物。混同禁止** | cmd_4120 |
| page-title h1 | `text-2xl md:text-3xl font-bold tracking-tight text-foreground` | cmd_4115 |
| 統一対象外(例外) | アイコン役割(deteriorationの方向矢印↘↓→ text-lg色付き)は数値/文字でなくアイコンゆえ除外 | 実装者判断+殿確認 |

### AsIs → ToBe(2026-07-23時点)
- **AsIs**: A軸(typography)完遂=本番LIVE。B軸=B1 status色/K軸viewport色/値の色(cmd_4124)完了。表フォント14px統一=cmd_4127で6表修正+本番CDP検証済、cmd_4128でup-down-market-chart回収中。B2/B3(色)・C(余白)・D(card)・E(表構造)・F(interaction)・G(chart)・H(header)・I(states)・J(responsive)・L(copy)=未着手または偵察のみ。
- **ToBe**: 全12軸×全コンポーネント×全属性が、上記canonicalへ本番CDP実測で逸脱0。1ページ複数表もCDP DOM文脈で各表の実体componentを特定して全数カバー。

### 索引(§一覧)
| § | 内容 | 用途 |
|---|---|---|
| §0 | Route inventory 21/21 | 全ページ列挙(取りこぼし防止の母数) |
| §1 | Axes A–L 定義 | 12軸の意味 |
| §2 | Main matrix 21×12=252 | 軸×ページの差分一覧 |
| §2.5 | Viewport state-color差分 | PC/mobile色差(K軸詳細) |
| §2.6 | Explanatory-copy/note/legend差分 | L軸詳細 |
| §3 | Unified design candidates | 統一案 |
| §4 | CE/ME/numeric verification | 断片突合・再検証 |
| §5 | Causal links | 因果 |
| §6 | 実装粒度ブレークダウン(A1-L1) | 1cmd=1忍者のサブタスク+状態/cmd |
| **§6.1** | **コンポーネント×属性×役割カバレッジ(CDP実測)** | **フォント/色の逸脱を本番CDPで全数記録。測定手順も内包** |

一次情報root: `/mnt/c/Python_app/DM-signal/frontend`。本書は21 pageの検索索引兼統合判定。gist正本=`c50699ea4e13d003a7864996b93ba19f`(gist_verified_write.shでバイト一致検証)、三層記憶=knowledge:7e967b43(CDP実測基盤)/70cfc7e4(§6.1改訂)/9d1f8e19(cmd_4127出口検証)。

## §0 Route inventory — 21/21

`find frontend/app -name page.tsx -type f | sort` の現物はviewer **17** + admin **4** = **21**。重複0、欠落0。

| # | route | page.tsx | 区分 |
|---:|---|---|---|
| 1 | `/` | `frontend/app/page.tsx` | viewer |
| 2 | `/annual-returns` | `frontend/app/annual-returns/page.tsx` | viewer |
| 3 | `/compare` | `frontend/app/compare/page.tsx` | viewer |
| 4 | `/compare-returns` | `frontend/app/compare-returns/page.tsx` | viewer |
| 5 | `/compare-summary` | `frontend/app/compare-summary/page.tsx` | viewer |
| 6 | `/dashboard` | `frontend/app/dashboard/page.tsx` | viewer |
| 7 | `/deterioration` | `frontend/app/deterioration/page.tsx` | viewer |
| 8 | `/docs` | `frontend/app/docs/page.tsx` | viewer |
| 9 | `/drawdowns` | `frontend/app/drawdowns/page.tsx` | viewer |
| 10 | `/faq` | `frontend/app/faq/page.tsx` | viewer |
| 11 | `/metrics` | `frontend/app/metrics/page.tsx` | viewer |
| 12 | `/monthly-returns` | `frontend/app/monthly-returns/page.tsx` | viewer |
| 13 | `/monthly-trade` | `frontend/app/monthly-trade/page.tsx` | viewer |
| 14 | `/offline` | `frontend/app/offline/page.tsx` | viewer |
| 15 | `/rolling-returns` | `frontend/app/rolling-returns/page.tsx` | viewer |
| 16 | `/summary` | `frontend/app/summary/page.tsx` | viewer |
| 17 | `/trades` | `frontend/app/trades/page.tsx` | viewer |
| 18 | `/admin` | `frontend/app/admin/page.tsx` | admin |
| 19 | `/admin/fof` | `frontend/app/admin/fof/page.tsx` | admin |
| 20 | `/admin/folders` | `frontend/app/admin/folders/page.tsx` | admin |
| 21 | `/admin/visibility` | `frontend/app/admin/visibility/page.tsx` | admin |

### 統合した断片 — 6/6

`docs/research/fragments/mece_v2_{hayate,hanzo,kagemaru,kotaro,saizo,tobisaru}_20260722.md`。各断片の行番号付き詳細を削除せず参照し、本表では検索判断点を21行へ圧縮する。

## §1 Axes A–L

| 軸 | 定義 |
|---|---|
| A | typography: size/weight/alignment/font |
| B | color: background/text/border/status palette |
| C | spacing: outer padding/gap/margin/cell padding |
| D | container/card: surface/radius/shadow/elevation |
| E | table: header/row/cell/numeric format |
| F | interaction: button/link/hover/focus/active |
| G | chart: palette/axis/legend/tooltip/library |
| H | header/nav: page chrome/title/control placement |
| I | states: loading/empty/error/offline/blocked |
| J | responsive: breakpoint/reflow/hide/scroll |
| K | viewport state color: PC/mobile DOMとhelper適用差 |
| L | copy/caption: description/note/legend/captionのtype/color/placement |

## §2 Main matrix — 21 rows × 12 axes = 252/252 cells

各cell末尾の`ref`は一次コード行。詳細な複数行証跡は該当fragmentに保持する。

| page | A | B | C | D | E | F | G | H | I | J | K | L |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `/` | icon4xl/h1 2xl→3xl (`page.tsx:27-39`) | semantic bg/card/muted (`:25-44`) | px4/card p8 (`:25-26`) | rounded2xl card (`:26`) | N/A table0 (`:3-50`) | dashboard Link (`:41-47`) | N/A chart0 (`:3-50`) | dashboard CTAのみ (`:41-47`) | holiday注記 (`:7-40`) | h1 mdのみ (`:25-30`) | 単一DOM、差N/A (`:25-49`) | 説明+休日note muted中央 (`:33-39`) |
| `/annual-returns` | canonical PageShell h1 (`page.tsx:204`; `page-shell.tsx:30`); section差分=chart h3 text-xl/table h2 text-lg (`annual-returns-chart.tsx:212-215`; table`:102-108`); numeric cells mono (`table:225-256`) | blue/cyan bars、return helper (`chart:319-347`; table`:68-74`) | gap2/cell py3 (`chart:212`; table`:165-256`) | bare、tooltip card (`chart:393`) | 2段header table (`table:165-268`) | Show All/hover (`chart:221-244`; table`:112-157`) | custom SVG+legend (`chart:251-443`) | PageShell (`page.tsx:204`) | loading/error/empty (`:205-258`) | chart scroll/table md (`chart:252-256`; table`:180`) | return helper同一、差0 (`table:218-236`) | YTD/Partial notes+axis+legend (`table:218-284`; chart`:273-443`) |
| `/compare` | canonical h1 2xl→3xl (`page.tsx:261-263`); section差分=chart h3 lg (`comparison-chart.tsx:482`) | PF palette/positive-negative (`comparison-chart.tsx:519-680`) | p4→sm8、space6→8 (`page.tsx:254-347`) | bare、tooltip card (`ChartTooltip.tsx:31-53`) | N/A table0 (`page.tsx:253-384`) | Accordion/Select/reset (`:277-347`) | interactive SVG (`comparison-chart.tsx:505-753`) | title/Home/Mobile (`page.tsx:257-275`) | loading/error/zero (`:230-381`) | responsive outer padding/gaps (`page.tsx:254-296`); single responsive SVG (`comparison-chart.tsx:506-621`) | single DOM、pos/neg共通 (`chart:622-753`) | as-of/max7/Bench/Since/legend (`page:270-330`; chart`:694-753`) |
| `/compare-returns` | h1 2xl→3xl、table sm (`page.tsx:161-177`; table`:179`) | return green/red、FoF purple/BM amber (`table:29-34,264-283`) | shell px4→8 (`page:156,182`) | borderless/sticky bg (`table:177-191`) | 8期間sortable (`table:177-285`) | timing/chips/sort (`page:164-222`) | N/A chart0 (`page:3-17`) | Home/Mobile/title (`:156-178`) | banners/skeleton/empty (`:138-186`; table`:120-175`) | md列hide/scroll (`table:122-191`) | one DOM/getReturnColor共通 (`table:29-34,264-275`) | as-of+FoF/BM/sort/period notes (`page:171-252`) |
| `/compare-summary` | h1 2xl→3xl、table sm (`page.tsx:251-273`; table`:325`) | FoF purple/BM amber/CAGR green-red (`table:377-393`) | px4→8/cell p3 (`page:251,278`; table`:370`) | bare wide surface (`page:249-327`) | sticky sortable (`table:323-440`) | timing/chips/link (`page:259-318`; table`:420-431`) | N/A chart0 (`page:1-10`) | title/Timing/Home/Mobile (`page:250-274`) | banners/skeleton/empty (`page:279-282`; table`:248-320`) | mobileVisible列hide (`table:335-376`) | common CAGR/name一致、MDD N/A (`table:377-417`) | as-of + FoF/BM/sort legend (`page:266-342`) |
| `/dashboard` | h1 2xl→3xl/signal3xl (`page.tsx:568-632`) | semantic/chart destructive (`:561-691`) | px4→sm8/gap6 (`:563-622`) | mostly bare (`:589-597`) | MTD sticky table (`mtd-daily-table.tsx:117-200`) | selectors/range (`page:565-703`) | return/pie/MTD charts (`:659-725`) | independent header (`:563-586`) | hidden/loading/error (`:548-616,741-749`) | lg signal/pie分岐 (`:622-680`) | return+dot helper一致 (`mtd table:38-44`; page`:638-677`) | as-of/signal/pending/pie legend/MTD note (`page:579-668`; table`:211-220`) |
| `/deterioration` | canonical h1 2xl→3xl (`page.tsx:1178-1180`); section差分=table sm (`page.tsx:1282`) | label/dot/trend palette (`:77-152`) | px4 py8/cell p3 (`:1172-1239,1289`) | Accordion bare (`:1279-1431`) | 14-col sortable (`:154-278,1281-1435`) | chips/sort/expand (`:1203-1339`) | detail SVG+tooltip (`:437-1000`) | title/Home/Mobile (`:1174-1201`) | skeleton/error/empty (`:1124-1167,1438`) | md hide/detail PC only (`:1296-1417`) | 4 dot helpers一致、badge/trend N/A (`:1351-1408`) | as-of/chart legend/detail headings; Accordion title only・hintなし (`:819-855,976-994,1193-1198,1280`) |
| `/docs` | PageHeader/accordion/body xs-sm (`page-header.tsx:54-65`; accordion`:28-38`) | semantic/sky/amber (`docs/*.tsx`) | p4→8/cards p4→6 (`page.tsx:32-60`) | 4 GlassCard (`:38-63`) | 2 content tables (`methodology-content.tsx:58-77`) | 4 accordions (`page:38-62`) | N/A chart0 (`docs/*.tsx`) | PageHeader/Mobile/Theme (`page-header:53-70`) | dynamic loading (`page:9-28`) | md gaps/table scroll (`:32-60`) | single content DOM、差N/A (`:32-64`) | subtitle/hints/definitions/disclosures/references全抽出 (`docs/*.tsx`) |
| `/drawdowns` | canonical PageShell h1 (`page.tsx:80`; `page-shell.tsx:30`); section差分=h2 lg/numeric right (`page.tsx:108-145`; table`:43-67`) | primary/muted/drawdown red (`page:109,134`; table`:64`) | space6→8/card p6 (`page:105-145`) | GlassCard 2/3 (`:107-140`) | one responsive table (`table:32-75`) | chart pointerのみ (`chart:186-193`) | responsive SVG (`chart:186-193`) | PageShell (`page:80`) | loading/banner/empty (`:81-103`; table`:27-29`) | md column hide (`table:39-62`) | drawdown red共通、差0 (`table:64-69`) | worst10/recovery note + chart legend/tooltip (`page:143-146`) |
| `/faq` | h1 2xl→3xl/question sm (`page-header:54-65`; page`:149-160`) | semantic/sky links (`page:45-68,390-430`) | p4→8/card p4→6 (`:342-358`) | GlassCards (`:287-438`) | markdown/glossary tables (`:42-68,359-380`) | Accordion/language/links (`:257-438`) | N/A chart0 (`:3-13`) | PageHeader+language (`:345-349`) | Suspense loading (`:444-458`) | md/table scroll (`:342-360`) | single DOM、link色共通 (`:45-68,223-231`) | subtitle/answers/glossary/references (`:31-68,149-160,359-430`) |
| `/metrics` | canonical PageShell h1 (`page.tsx:134`; `page-shell.tsx:30`); section差分=table h2 lg/chart h3 xl (`metrics-table.tsx:62-66`; chart`:272-274`) | negative red/up-down palette (`table:89-116`; chart`:272-305`) | table py2/chart mt8 (`table:68-116`; page`:177-191`) | table bare/chart card (`chart:486`) | metric+chart aux tables (`table:65-121`; chart`:281-308`) | PF nav/tooltip (`page:133-196`; chart`:630-689`) | custom SVG bars (`chart:486-715`) | PageShell (`page:133`) | loading/error/no-data (`:135-166`) | scroll/responsive SVG (`table:65`; chart`:486`) | metric inline condition共通 (`table:89-116`) | Analysis Period/tooltip/legend (`page:177-183`; chart`:272-715`) |
| `/monthly-returns` | canonical PageShell h1 (`page.tsx:231`; `page-shell.tsx:30`); section差分=h2 lg/cell xs→sm mono (`table:196-199,387-430`) | getValueClass/amber pending (`:289-466`) | gap2/cell px1→2 py3 (`:196,285`) | bare table/badges (`:285-425`) | 2-row header (`:285-544`) | show/pager (`:205-268`) | N/A chart0 (`page.tsx:3-22`) | PageShell (`page:231`) | loading/banner/pending (`page:232-269`) | month label/ticker md (`table:391-544`) | one row/helper、一致 (`table:428-490`) | MTD/Partial/PeriodNotes/footer (`table:398-572`; period-notes`:38-71`) |
| `/monthly-trade` | canonical PageShell h1 (`page.tsx:165`; `page-shell.tsx:30`); section差分=h2 lg/labels xs-sm (`table:122-132`) | active sky/warning amber/return helper (`:138-160,502`) | toolbar gap2/cell p4x3 (`:122,239`) | bare/Next amber panel (`:120,349-398`) | wide 9-col table (`:239-312`) | toggles/load/pager (`:135-223`) | N/A chart0 (`page:4-18`) | PageShell (`page:164`) | loading/error/no-data (`page:166-205`) | toolbar sm/columns md-lg (`table:120-289`) | same returnColor、差0 (`:502-741`) | count/FoF/Next/Preview/MTD badges (`:123-132,349-398,529-547`) |
| `/offline` | h1 2xl/body default (`page.tsx:8-14`) | secondary icon/muted (`:6-14`) | p4/card p8 (`:6-8`) | GlassCard max-md (`:7`) | N/A table0 (`:1-18`) | N/A control0 (`:1-18`) | N/A chart0 (`:1-18`) | no nav (`:1-18`) | offline static state (`:4-18`) | fluid max-width (`:6-7`) | single DOM、差N/A (`:6-15`) | connection explanation muted中央 (`:12-14`) |
| `/rolling-returns` | canonical PageShell h1 (`page.tsx:86`; `page-shell.tsx:30`); section差分=h2 lg/tables sm (`page.tsx:117-166`; dist`:72`) | summary helper/distribution PC red (`summary:47-51`; dist`:41-44`) | space6→8/card p4→6 (`page:113-164`) | 3 GlassCard (`:116-174`) | summary+distribution dual tables (`:135-160`) | period pills (`chart:325-356`) | rolling CAGR SVG (`chart:363-370`) | PageShell (`page:86`) | loading/error/no-data (`:87-131`) | desktop/mobile table branches (`summary:97,309`; dist`:71,136`) | distribution negative PC red/mobile継承=不一致1 (`dist:104-169`) | 3 headings+axis/legend/tooltip、caption0 (`page:136-166`; chart) |
| `/summary` | canonical PageShell h1 (`page.tsx:91`; `page-shell.tsx:30`); section差分=h2 lg/mono (`summary-table.tsx:138-165`) | negative red/hover (`:140-205`) | shell md/cell py2 px4 (`page-shell:25-56`; table`:143`) | bare wrapper (`table:138-146`) | single scroll table (`:143-257`) | shell controls (`page.tsx:90-129`) | N/A chart0 (`:9-12`) | PageShell (`:90`) | hidden/loading/error/no-data (`:80-110`) | table scroll (`table:143-257`) | single DOM inline color共通 (`:190-259`) | Analysis Period muted中央 (`page:120-125`) |
| `/trades` | emoji4xl/h1 2xl→3xl (`page.tsx:7-15`) | semantic card/muted (`:5-22`) | px4/card p8 (`:5-6`) | rounded2xl card (`:6`) | N/A route table0 (`:1-27`) | dashboard Link (`:16-22`) | N/A chart0 (`:1-27`) | CTAのみ (`:16-22`) | blocked static (`:3-27`) | h1 md (`:5-10`) | route single DOM、差N/A (`:5-24`) | blocked explanation muted中央 (`:13-15`) |
| `/admin` | h1 2xl→3xl/h3 lg-sm (`page.tsx:211-219,409`) | health emerald/amber/layer palette (`:275-473`) | p4→8/space6→8 (`:211-214`) | max6xl GlassCards (`:212,399,1202`) | DB portfolio table (`:799-1152`) | save/sync/CRUD (`:223-270,1271-1433`) | N/A chart0 (`:3-41`) | title/Mobile/toolbars (`:213-381`) | auth/login/loading/banner/empty (`:170-205,388-449,1453`) | md/hide/grid reflow (`:211-269,452-520`) | health short copy shares parent state color、一致 (`:452-506`) | auth/DB hints/card descriptions/count/empty (`:170-203,409-515,1204-1455`) |
| `/admin/fof` | h1 2xl/card h3 lg (`page.tsx:310-418`) | primary/muted/destructive (`:392-510`) | p4→8/stack6 (`:299-380`) | GlassCard list/editor (`:342-376`; FoFEditor`:139`) | WeightBreakdown table (`WeightBreakdown:165-213`) | CRUD/recalc/reorder (`page:331-517`) | N/A chart0 (`:3-26`) | back admin/title (`:301-319`) | auth/loading/empty/banner (`:286-356`) | same DOM/md flex (`:299-380`) | double DOM0、semantic states共通 (`:299-517`) | subtitle/empty/components/editor notes (`:313-432`; FoFEditor`:156-304`) |
| `/admin/folders` | h1 2xl/h2 lg/item sm (`page.tsx:281-712`) | semantic primary/destructive (`:312-499`) | p4→8/space2-6 (`:270-363`) | create/list/move cards (`:297-830`) | N/A table0 (`:3-30,352-724`) | CRUD/expand/bulk (`:300-830`) | N/A chart0 (`:3-30`) | back admin/title (`:272-290`) | auth/loading/empty/saving (`:256-361,616-817`) | same DOM/fixed bar shrink (`:270,725-830`) | double DOM0、selection色共通 (`:369-830`) | subtitle/empty/count/move note (`:284-287,358-817`) |
| `/admin/visibility` | h1 2xl/h2 lg/table sm (`page.tsx:596-1209`) | emerald/amber/red/sky (`:756-1228`) | p4→8/space6→8/cell py2-3 (`:581-1185`) | GlassCard/modal (`:648-776`; modal`:249-310`) | visibility matrix (`page:772-1360`) | tier/page toggles/save/modal (`:623-1360`) | N/A chart0 (`:3-34`) | back admin/TierSelector (`:581-623`) | auth/error/loading/disabled (`:550-1360`) | same DOM/grid/table scroll (`:668-1360`) | double DOM0、status色共通 (`:772-1360`) | section descriptions/status/PF metadata/modal help (`:661-1228`; modal`:215-409`) |

## §2.5 Viewport state-color differences — 21/21

| page | dual DOM / helper result | verdict |
|---|---|---|
| `/` | single DOM; no state-color concept (`page.tsx:25-49`) | N/A |
| `/annual-returns` | one return cell/helper (`annual-returns-table.tsx:68-74,218-236`) | match |
| `/compare` | one SVG/tooltip positive-negative condition (`comparison-chart.tsx:622-753`) | N/A |
| `/compare-returns` | one table/getReturnColor (`compare-returns-table.tsx:29-34,264-275`) | match |
| `/compare-summary` | one table; common CAGR/name, MDD desktop-only (`compare-summary-table.tsx:323-417`) | match/N/A |
| `/dashboard` | MTD and deterioration dots share helpers, size only differs (`mtd-daily-table.tsx:38-44`; `dashboard/page.tsx:638-677`) | match |
| `/deterioration` | G1/G2/P/p̄ share four helpers; badge/trend desktop-only (`page.tsx:1351-1408`) | match/N/A |
| `/docs` | single content DOM (`docs/page.tsx:32-64`) | N/A |
| `/drawdowns` | one drawdown red cell (`drawdowns-table.tsx:64-69`) | match |
| `/faq` | single DOM semantic/link color (`faq/page.tsx:45-68,223-231`) | N/A |
| `/metrics` | single table inline state condition (`metrics-table.tsx:89-116`) | N/A |
| `/monthly-returns` | same row/getValueClass (`monthly-returns-table.tsx:428-490`) | match |
| `/monthly-trade` | same row/returnColor (`monthly-trade-table.tsx:502-741`) | match |
| `/offline` | single static DOM (`offline/page.tsx:6-15`) | N/A |
| `/rolling-returns` | distribution PC uses `valueClass`; mobile Median/P10/Positive omits it (`rolling-returns-distribution-table.tsx:41-44,104-169`) | **mismatch 1 pattern / 6 logical fields** |
| `/summary` | single table inline condition (`summary-table.tsx:190-259`) | N/A |
| `/trades` | current route single blocked DOM (`trades/page.tsx:3-24`) | N/A |
| `/admin` | short/long health copy shares emerald/amber parent (`admin/page.tsx:452-506`) | match |
| `/admin/fof` | no dual DOM; semantic states shared (`admin/fof/page.tsx:299-517`) | N/A |
| `/admin/folders` | no dual DOM; selection/destructive shared (`admin/folders/page.tsx:369-830`) | N/A |
| `/admin/visibility` | no dual DOM; toggle/status shared (`admin/visibility/page.tsx:772-1360`) | N/A |

Rolling P10一次訂正: `rolling-returns-summary-table.tsx`の`p10|P10`は **0件**。P10実表示はdistribution `rolling-returns-distribution-table.tsx:108,145,158-159`。PC helper適用=`:41-44,112-121`、mobile helper欠落=`:155-169`。

## §2.6 Explanatory-copy / note / legend differences — 21/21

| page | L inventory (font/color/placement) |
|---|---|
| `/` | description default muted中央、holiday note sm muted同card (`page.tsx:33-39`) |
| `/annual-returns` | YTD/Partial xs muted row内、partial notes xs muted table下、axis 11/12px、legend sm chart下 (`annual-returns-table.tsx:218-284`; chart`:273-443`) |
| `/compare` | as-of sm muted header下、control labels sm muted、legend sm chart下、Since 10px muted (`page.tsx:270-330`; chart`:694-753`) |
| `/compare-returns` | as-of sm muted header下、FoF/BM/sort/period definitions xs muted table下 (`page.tsx:171-252`) |
| `/compare-summary` | as-of sm muted header下、FoF/BM/sort xs muted table下 (`page.tsx:266-342`) |
| `/dashboard` | as-of/signal sm muted、Pending/pie/MTD notes xs muted near widgets (`dashboard/page.tsx:579-668`; `mtd-daily-table.tsx:211-220`) |
| `/deterioration` | as-of sm muted、chart legend xs muted、detail headings sm muted、Accordion titleのみ・hintなし (`page.tsx:819-855,976-994,1193-1198,1280`) |
| `/docs` | subtitle sm muted、Accordion hint xs muted、definitions/disclosures/references xs-sm muted in sections (`components/docs/*.tsx`) |
| `/drawdowns` | worst10/recovery note sm muted italic centered page末尾、chart legend/tooltip (`page.tsx:143-146`) |
| `/faq` | subtitle/answers/glossary/references sm muted in header/cards (`faq/page.tsx:31-68,149-160,359-430`) |
| `/metrics` | Analysis Period sm muted table下、chart period sm muted、tooltip/legend sm (`metrics/page.tsx:177-183`; chart`:272-715`) |
| `/monthly-returns` | MTD/Partial/Pending xs badges row内、PeriodNotes sm muted table下、footer xs muted (`monthly-returns-table.tsx:398-572`; period-notes`:38-71`) |
| `/monthly-trade` | count/FoF xs-sm heading横、Next/Preview/MTD badges xs panel/row内 (`monthly-trade-table.tsx:123-132,349-398,529-547`) |
| `/offline` | connection explanation default muted centered card内 (`offline/page.tsx:12-14`) |
| `/rolling-returns` | three headings lg card上、chart axis/legend/tooltip; table caption/note absent (`rolling-returns/page.tsx:136-166`) |
| `/summary` | Analysis Period sm muted centered table下 (`summary/page.tsx:120-125`) |
| `/trades` | blocked explanation default muted centered card内 (`trades/page.tsx:13-15`) |
| `/admin` | auth/loading default muted中央、DB hint xs muted、management descriptions sm muted、count xs muted (`admin/page.tsx:170-203,409-515,1204-1455`) |
| `/admin/fof` | subtitle sm muted、empty/help/preview/allocation xs-sm near cards/editor (`admin/fof/page.tsx:313-432`; `FoFEditor.tsx:156-304`) |
| `/admin/folders` | subtitle sm muted、empty/count/move/saving xs-sm near lists/fixed bar (`admin/folders/page.tsx:284-817`) |
| `/admin/visibility` | section descriptions sm muted、status/PF metadata xs、modal help xs/11px (`admin/visibility/page.tsx:661-1228`; `ManageTiersModal.tsx:215-409`) |

HTML `<caption>`/`<figcaption>`の採用は21ページで0。凡例・注記は個別div/p/spanへ分散している。

## §3 Unified design candidates

| axis | observed divergence | unified candidate |
|---|---|---|
| A | **将軍全21自己検証**: ページタイトルは器3系統(PageShell/PageHeader/独自)とも同一canonical h1で**15/21がcanonical**。noncanonical6のみ: offline・trades・admin・admin/fof・admin/folders・admin/visibility（独自h1/専用静的画面）。section/table見出し(h2/h3)のサイズ階層は別途混在(要token化) | **基準=summary(PageShell canonical=`text-2xl md:text-3xl font-bold tracking-tight text-foreground`)**。①noncanonical6のh1/専用画面を適用対象ごとに整理しcanonical classへ統一 ②タイトル器をPageShell/PageHeaderへ一本化(独自canonical7のclassコピー=DRY解消) ③section見出しh2/h3階層をtoken化 |
| B | semantic token/inline hex/status class混在 | semantic palette + chart/status constants |
| C | sm/md shell breakpoint、cell density分散 | shell=`p/px-4 md:p/px-8`; named density |
| D | equivalent data surfaceがbare/card混在 | `DataSection surface=bare|card` |
| E | sticky/hide/dual-mobile table policy無名 | `TableShell` + critical-column policy |
| F | touch target不足、link affordance不統一 | mobile 48px floor + focus/underline contract |
| G | SVG/Recharts/tooltip/legend/palette個別 | shared ChartTooltip/Axis/Legend/palette |
| H | header 4系統、PageNavigation null | slotted `PageHeader` + route policy |
| I | loading height/banner/naked error混在 | `PageState` variants + reserved-height token |
| J | hide/scroll/duplicate/detail policy分散 | named responsive data-surface policy |
| K | Rolling distributionだけmobile負値helper欠落 | PC/mobile cell rendererを共有し、同一state-color helper適用を型/rendererで強制 |
| L | caption0、notes/legend typographyがxs/sm・位置とも個別 | `DataNote`/`Legend`/semantic `<caption>` token（note=xs muted、section description=sm muted、placement slots） |

## §4 CE / ME / numeric verification

- route inventory: viewer **17/17** + admin **4/4** = **21/21**、重複0、欠落0。
- axes: **12/12** (A-L)。matrix: **21×12 = 252/252** cells。
- fragments: **6/6** integrated。
- K: **21/21**、未確認0、mismatch 1 pattern / 6 logical fields、根拠付きN/Aのみ。
- L: **21/21**、font/color/placement確認、未確認0。caption/figcaption不在は現物根拠付き。
- Rolling P10: summary **0件**、distribution実所在確認済み。
- target files changed by this task: **1件**（本書のみ）。
- placeholder 0、根拠なしN/A 0。全体判定 **PASS**。

### §4.1 Three-fragment element/file-line re-verification

- source fragments: `fragments/mece_reverify_hanzo_20260722.md`, `fragments/mece_reverify_saizo_20260722.md`, `fragments/mece_reverify_kotaro_20260722.md` = **3/3**。
- fragment coverage: **84/84 × 3 = 252/252** cells、pages **21/21**、axes **12/12**、未確認 **0**。
- corrections: hanzo **5** + saizo **4** + kotaro **2** = **11/252**。二次再照合のtrue positive **11/11**、false positive **0/11**。
- A-axis page-title verdict: canonical **15/21**、noncanonical **6/21**。page title器とsection/table headingは分離して記録。
- preserved facts: Rolling P10はsummary **0件**、distribution実所在。viewport色差はdistribution **1 pattern / 6 logical fields**。

| # | page/axis | before | after | primary file:line |
|---:|---|---|---|---|
| 1 | annual-returns A | heading refsに`mono`を混在 | PageShell h1、section h3/h2、numeric monoを分離 | `annual-returns/page.tsx:204`; `annual-returns-chart.tsx:212-215`; `annual-returns-table.tsx:102-108,225-256` |
| 2 | compare A | page範囲をchart h3根拠化 | canonical h1とchart h3を分離 | `compare/page.tsx:261-263`; `comparison-chart.tsx:482` |
| 3 | compare J | page controls範囲をsingle SVG根拠化 | responsive shellとSVG所在を分離 | `compare/page.tsx:254-296`; `comparison-chart.tsx:506-621` |
| 4 | deterioration A | h1を2xlのみと記述 | canonical 2xl→3xl h1 + table heading | `deterioration/page.tsx:1178-1180,1282` |
| 5 | deterioration L | 存在しないAccordion hint | as-of/legend/detail heading + Accordion titleのみ | `deterioration/page.tsx:819-855,976-994,1193-1198,1280` |
| 6 | drawdowns A | section h2のみ | canonical PageShell h1 + section h2 | `drawdowns/page.tsx:80,108-145`; `page-shell.tsx:30` |
| 7 | metrics A | table h2/chart h3のみ | canonical PageShell h1 + section headings | `metrics/page.tsx:134`; `page-shell.tsx:30`; `metrics-table.tsx:62-66`; `up-down-market-chart.tsx:272-274` |
| 8 | monthly-returns A | table h2/cellのみ | canonical PageShell h1 + section/table typography | `monthly-returns/page.tsx:231`; `page-shell.tsx:30`; `monthly-returns-table.tsx:196-199,387-430` |
| 9 | monthly-trade A | table h2/labelsのみ | canonical PageShell h1 + section labels | `monthly-trade/page.tsx:165`; `page-shell.tsx:30`; `monthly-trade-table.tsx:122-132` |
| 10 | rolling-returns A | section/table headingsのみ | canonical PageShell h1 + local headings | `rolling-returns/page.tsx:86,117-166`; `page-shell.tsx:30`; `rolling-returns-distribution-table.tsx:72` |
| 11 | summary A | PageShell名のみでh1根拠欠落 | canonical PageShell h1 + table typography | `summary/page.tsx:91`; `page-shell.tsx:30`; `summary-table.tsx:138-165` |

差分要約: A軸9件はpage title器を先頭に固定してlocal headingを後置、Compare-JはSVG所在をcomponentへ移動、Deterioration-Lは不存在hintを除去。3 fragmentの他241セルは現記述と一次実装が一致したため変更なし。

## §5 Causal links

origin: `[[殿指示_デザイン統一_20260722]] -> [[6断片_A_L全数調査]] -> [[21x12_252セル_MECE_v2]]`  
viewport-origin: `[[Rolling_distribution_mobile_helper欠落]] -> [[PC_mobile状態色不一致]] -> [[共通cell_renderer提案]]`  
copy-origin: `[[caption不在_notes分散]] -> [[L軸全数抽出]] -> [[DataNote_Legend_caption_token提案]]`
reverify-origin: `[[三分割252セル再検証]] -> [[要素種別_所在混同11件]] -> [[MECE正本訂正11_252]]`

## §6 実装粒度ブレークダウン(殿裁定2026-07-22: 実装イメージで粒度を小さく)

各軸を「1cmd=1忍者で実装可能なサブタスク」へ細分化。CDPは各サブタスクの本番デプロイ後1回のみ(per-task CDP禁止)、実装はコード現読+jest。基本形=Monthly Returns。既存資産を再利用(車輪の再発明防止): 色=`frontend/lib/colors.ts`、見出し器=`components/ui/page-header.tsx`。

| ID | 軸 | サブタスク | 基準/SSOT | 状態/cmd |
|---|---|---|---|---|
| A1 | A typo | page-title h1 class統一 | canonical `text-2xl md:text-3xl font-bold tracking-tight text-foreground` | ✅完了 cmd_4115 |
| A2 | A typo | section見出しh2/h3を`section-heading`(text-lg semibold foreground)へ | Monthly Returns h2 | ✅完了 cmd_4116 |
| A3 | A typo | インラインh1(12ページ)→page-header.tsx/共有定数へDRY(12→1) | page-header.tsx | ✅完了 cmd_4117 |
| A4 | A typo | body=text-sm/caption=text-xs muted/numeric=font-mono text-sm tabular-nums。★font-size/family統一はgrep不可→CDP実測必須(§6.1参照)。cmd_4119は一部表のみ、CDP実測で残存6表判明→cmd_4127/4128で全数化 | Monthly Returns | ✅完了 cmd_4119+4122+4127(本番CDP検証済)、cmd_4128(up-down-market回収中) |
| B1 | B color | **status色**shade統一(STATUS_TEXT_CLASSESバッジ): 負値=text-red-400/正値=text-emerald-400/warning=amber-400/neutral=muted-foreground、colors.ts SSOT。⚠️**値の色(getValueColorClass)はstatus色と別ルール→B1-value参照。混同禁止** | colors.ts | ✅cmd_4120完了 |
| B1-value | B color | **値の色**(数値表示getValueColorClass): 正値=`text-foreground`(light黒寄り#0f172a/dark白#f8fafc)/負値=`STATUS_TEXT_CLASSES.negative`(text-red-400,両モード)/0・null=空文字。**殿裁定2026-07-23T01:05『ダークモードは正の値は白の文字色、ライトモードでは黒に近い色。マイナスは赤』(★同日00:45の暫定`text-foreground dark:text-emerald-400`は01:05裁定で失効。dark emeraldは付与しない)**。統一cmdは値色にstatus色のemeraldを流用するな(cmd_4122がemerald固定にしlightで緑発光→本番色崩れ→cmd_4124で修正。ui-design-guide L27/L57: 18px以下は4.5:1、白背景×emerald-400≈1.6:1でガイド違反) | colors.ts getValueColorClass | ✅cmd_4124本番LIVE |
| B2 | B color | chart等のinline hex(#3B82F6等8色)→colors.ts定数/semantic tokenへ | colors.ts | 未 |
| B3 | B color | border/background色をsemantic token(border/bg-card/muted等)へ統一 | tailwind semantic token | 未 |
| C1 | C spacing | shell padding `p/px-4 md:p/px-8` 統一 | Monthly Returns shell | 未 |
| C2 | C spacing | cell density(py/px)を named token化 | — | 未 |
| C3 | C spacing | section間gap統一(space-y) | — | 未 |
| D1 | D card | 等価データ面のbare/card混在→`DataSection surface=bare|card` | — | 未 |
| D2 | D card | radius/shadow/elevation token統一 | GlassCard基準 | 未 |
| E1 | E table | header/row/cell構造を`TableShell`へ共通化 | Monthly Returns table | 未 |
| E2 | E table | sticky/hide/mobile-dual policyを命名(critical-column) | — | 未 |
| E3 | E table | numeric format(小数桁/%/+-記号)統一 | — | 未 |
| F1 | F interaction | touch target 48px floor(mobile) | — | 未 |
| F2 | F interaction | focus/hover/link-underline contract | — | 未 |
| G1 | G chart | shared ChartTooltip/Axis/Legend抽出 | — | 未 |
| G2 | G chart | chart palette→colors.ts SSOT | colors.ts | 未 |
| H1 | H header | header 4系統→slotted PageHeader一本化 | page-header.tsx | 未(A3と関連) |
| H2 | H header | PageNavigation null/route policy | — | 未 |
| I1 | I states | loading/empty/error→`PageState` variants | — | 未 |
| I2 | I states | reserved-height token(CLS防止) | — | 未 |
| J1 | J responsive | hide/scroll/dual-mobile policyを named data-surface化 | — | 未 |
| K1 | K vp-color | mobile二重実装テーブルのgetValueColor SSOT適用(負値=赤) | colors.ts getValueColorClass | ✅本番LIVE cmd_4118 |
| L1 | L copy | notes/legend/captionを`DataNote`/`Legend`/semantic caption tokenへ | — | 未 |

**配備順序の原則**: 実害バグ(K済) > A軸完遂(A2-A4進行中) > B色(B1 status統一が高頻度=次) > E表 > 他。各サブタスクは独立cmd化し、同一component衝突時のみdepends_onで直列化。

impl-granularity-origin: `[[殿裁定_実装粒度細分化_20260722]] -> [[MECE_§3が1軸1行で粗い]] -> [[§6実装サブタスク表A1-L1へ細分]]`

## §6.1 コンポーネント単位カバレッジ表(殿裁定2026-07-22: §6でもまだ粗い→取りこぼしが見える粒度へ)

**教訓**: §6のA4「body/numeric token」は「13表のうち何表か」を明示せず、cmd_4119が4表(compare-returns/compare-summary/drawdowns/risk-management)を取りこぼした。殿の本番ライブレビューで露出=深掘り不足(全数網羅の甘さ)の再現。**対策=各サブタスクをコンポーネント×属性のマトリクスまで下げ、全対象を明示列挙して取りこぼしをgrepで0証明する。** 未列挙=対象外を意味しない、必ず全数を列挙せよ。

### 【廃止】旧・数値font-m/色 grepカバレッジ表(将軍grep実測 2026-07-22)

> ⚠️**この旧grep表は2026-07-23に廃止**(下記CDP実測表が正)。廃止理由: grepの`✅(N)`はソースにfont-monoが「N回書かれている」だけで、実際に**全数値セルに描画されているか**を保証しない。実証=rolling-returns-summary-tableはgrep`✅(12)`だったが本番CDP getComputedStyleで数値48セルがプロポーショナル(等幅漏れ)だった。またこの13表リストは**up-down-market-chart(/metricsのUp vs Down Market表)を含まず**、その数値等幅漏れを構造的に見落とした(cmd_4128で回収)。grep件数を○/×判定に使うと必ず取りこぼす。

### 数値表示テーブル × フォント属性(本番CDP getComputedStyle実測 2026-07-23)【正】

canonical=本体数値14px/ui-monospace/tabular-nums、本体文字14px/Inter、ヘッダ14px。逸脱=canonicalからの計算済みスタイルのズレ(役割別)。

| # | コンポーネント | 出現ページ | CDP実測(デプロイ後) | 逸脱内容 | cmd |
|---|---|---|---|---|---|
| 1 | rolling-returns-summary-table | /rolling-returns | ✅canonical | (旧)数値48セル等幅漏れ→修正 | cmd_4127 本番CDP検証済 |
| 2 | rolling-returns-distribution-table | /rolling-returns | ✅canonical | — | cmd_4122/4127 |
| 3 | deterioration表 | /deterioration | ✅canonical | (旧)カテゴリ小ラベル12px→14px。方向矢印18pxはアイコン除外(意図的) | cmd_4127 本番CDP検証済 |
| 4 | up-down-market-chart表 | /metrics(t1) | 🔄回収中 | 数値セル等幅漏れ(font-mono 0件)。cmd_4127が対象漏れ(実体がmetrics-tableでなくup-down-market-chart) | cmd_4128 |
| 5 | annual-returns-table | /annual-returns | ✅canonical | col0の年号(2025等)はデータでなく行ラベル→Inter正当(偽陽性でない) | cmd_4122/4127 |
| 6 | monthly-returns-table | /monthly-returns | ✅canonical | col0の年号/月ラベルはInter正当 | cmd_4122/4127 |
| 7 | monthly-trade-table | /monthly-trade | ✅canonical | '---'プレースホルダは数値でない(偽陽性) | cmd_4122/4127 |
| 8 | metrics-table(t0) | /metrics | ✅canonical | — | cmd_4122 |
| 9 | summary-table | /summary | ✅canonical | — | cmd_4122 |
| 10 | drawdowns-table | /drawdowns | ✅canonical | — | cmd_4122 |
| 11 | compare-returns-table | /compare-returns | ✅canonical | — | cmd_4122 |
| 12 | compare-summary-table | /compare-summary | ✅canonical | — | cmd_4122 |
| 13 | risk-management-table | (risk管理面) | 要CDP実測 | 旧grepでgetValueColor7+基準外混在。CDPで再測要 | cmd_4122 |
| 14 | model-trades-table | /trades | 要CDP実測 | 旧grep✅(5)。CDPで再測要 | cmd_4122 |
| 15 | mtd-daily-table | /mtd | 要CDP実測 | 旧grep✅(6)。CDPで再測要 | cmd_4122 |

**教訓(cmd_4128で確定)**: 1ページに複数の表コンポーネントが同居する(例:/metricsはmetrics-table + up-down-market-chart)。**修正対象componentもソースgrep(ページ名→単一component連想)でなくCDP DOM文脈(近傍見出し/firstRow/parentClass)で実体特定せよ**。ページ名≠component名。将軍がcmd_4127起票時にページ名基準でmetrics-tableを対象化し、実体のup-down-market-chartを外した=同一の取りこぼし構造の再現。

**完遂条件(CDP実測全数証明)**: 全表を本番CDP getComputedStyleで役割別実測し、canonical(本体14px/数値mono/文字Inter/ヘッダ14px)からの逸脱0を証明。加えて色は値の色=getValueColorClass経由(直書きred-400/amber混在=0)。grep 0件証明では不十分(描画と不一致)。「要CDP実測」の3表(risk-management/model-trades/mtd-daily)は本番CDPで再測して✅/逸脱を確定する。

### 粒度ルール(全サブタスク共通)【2026-07-23 CDP実測一次化へ改訂】

**改訂理由(殿指摘2026-07-23『表によってフォントが違う。grepは見落とすぞ』)**: 旧ルールはgrep件数を一次測定に据えたが、grepは(a)CSS継承(親→子で降る)(b)CSS上書き(text-base→14pxへ後勝ち)(c)グループセレクタ`[&_td]:font-mono`(d)条件分岐class(clsx/cn)(e)semantic token経由 を一切見ない。実証: 将軍がソースgrepで『数値font-mono 54/54統一』と報告したが、本番CDP getComputedStyleでは逸脱6表(rolling-returns等の数値48セルが等幅漏れ、annual/monthlyのヘッダ12px混在)。ソースの文字列≠描画されたフォント。**grepは偵察の起点にすらしてはならない。範囲を絞る母数として使うと、grepが見ないセルが最初から範囲外になり必ず見落とす(将軍が見落とした当人として実証)。**

1. **対象コンポーネントを全数列挙せよ**(「該当する表」でなく全表を名指し)。未列挙=対象外を意味しない。
2. **属性ごとの現状は本番CDP `getComputedStyle` で実測する(grep禁止)**。測定は役割別に分解: セルを {ヘッダ / 本体・数値 / 本体・文字} に分類し、各役割の font-size・font-family・font-weight の計算済み値を記録する。役割で分けないと『サイズ混在』の正体(数値/文字の差か、ヘッダ由来か)が判別できず誤修正する(殿指摘2026-07-23 09:55)。
3. **canonicalを殿裁定で明示的に確定してから逸脱を定義せよ**。多数決や既存実装の踏襲で決めるな(cmd_4122がmonthly-returns基準でなく他表慣習に合わせemerald固定にし本番色崩れ)。**表フォントcanonical(殿裁定2026-07-23 10:15)**: 本体数値=14px/ui-monospace/tabular-nums、本体文字=14px/Inter、ヘッダ=14px。例外=アイコン役割(deteriorationの方向矢印↘↓→ text-lg色付き)はcmd_4119のmuted caption除外と同型で統一対象外。
4. **完遂条件=CDP getComputedStyleで逸脱0を全数証明**(grep 0件証明では不十分。描画と不一致のため)。
5. **偵察入口も検証出口もCDP実測**。旧ルールはCDPを『最終確認』に後置したが、入口をgrepにすると見落とすため、偵察の最初からCDPで測る。将軍が実施(per-task CDP禁止=忍者の実装ループ内のみ、本番デプロイ後の全数実測は将軍の役目 knowledge:43724140b320495c)。

### CDP実測手順(正本・knowledge:776999ee で上書き 2026-07-23)
★旧記述(powershell手動起動+Render API verify-viewer手動注入、knowledge:7e967b43)は手動分解の断片。実体は下記ラッパーが起動+認証+測定を一括で行う。手動powershell/claude-in-chrome MCPは使うな。
1. **起動+認証+測定 一括**: `bash scripts/cdp/cdp_measure.sh <cmd_id> --pages /a /b`。内部で `/mnt/c/Python_app/auto-ops/workflows/perf_measure.py --profile production` を実行し、CDP起動(preflight port9222・既起動なら再利用・隔離profile D009)+認証+測定+JSON/MD保存(`/mnt/c/Python_app/DM-signal/outputs/`)を全て行う。
2. **認証の実体(perf_measure.py)**: **admin Basic Auth**(config `auth.admin_user/admin_pass`)で `/api/admin/tiers/passwords` からviewer passwordを取得→ `/api/viewer-permissions` でviewer認証。未認証だと表0件。
3. **★admin認証(殿厳命2026-07-23)**: **viewer認証だけでは不十分、admin認証で入らないと確認できないPF/ページがある**。admin対象は config `auth.admin_user/admin_pass` を設定して測れ(`/admin/*`もこの経路で到達可)。
4. **稼働中CDP(9222・認証済)への独自測定**: `python3 scripts/cdp/<probe>.py --base https://dm-signal-frontend.onrender.com --routes /a,/b --port 9222`。probe=`cdp_font_probe.py`(font役割別=header/body-number/body-text、数値プロポーショナルを `body-number(prop!)` surface)/`cdp_ed_probe.py`(E軸境界線・stripe・padding + D軸card)/`cdp_card_probe.py`(全カード列挙)。★**固定sleep禁止**=セル数2回連続同値まで安定ポーリング後に即測定(本番約2sで充填、固定15sは1ページ約13s浪費=将軍実測、ポーリング版6.1倍速)。ナビゲーション後は新規WSで測る(persistent WSは実行コンテキスト喪失)。**数値prop検出=candidateであり即逸脱でない**: 年号/月ラベル・'---'プレースホルダは非データゆえInter正当(偽陽性)、textContentで実データ判別してから逸脱確定。
5. **実ルートは想像するな**: ルートは `frontend/app/*/page.tsx` が権威(全21件)。将軍が架空ルート(risk-management/model-trades等)を作り`[]`を得た検証不足事故あり(2026-07-23)。

このコンポーネント×属性×役割粒度を、B(色: 全component×status色/border/bg)、E(表: 全表×header/row/cell/sticky)、G(グラフ: 全chart×palette/axis/legend)等の各軸にも適用。測定は全てCDP実測、grepは補助(どのcomponentファイルを触るかの当たり付け)にのみ使い、○/×判定には使わない。

component-granularity-origin: `[[殿指摘_表font色不統一連鎖_20260722]] -> [[§6のA4/B1が対象表を明示せず4表取りこぼし]] -> [[§6.1コンポーネント×属性カバレッジ表で全数列挙]] -> [[殿指摘_grepは見落とす_20260723]] -> [[測定をCDP getComputedStyle一次化+役割別粒度]]`
