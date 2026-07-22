# MECE element/file-line re-verification — hanzo — 2026-07-22

## Scope and binary result

- Routes: 7/7 (`/`, `/annual-returns`, `/compare`, `/compare-returns`, `/compare-summary`, `/dashboard`, `/deterioration`)
- Cells: 84/84 checked; unchecked 0
- Element-description match: 79/84 yes, 5/84 no
- Recheck false positives: 0/5 (all five remained mismatches after a second source read)
- Source of rows under test: `docs/research/dm-signal-page-style-diff-mece_20260722.md` §2, with §2.5/§2.6 used to cross-check K/L
- Implementation root: `/mnt/c/Python_app/DM-signal/frontend`

Legend: `type yes/no`; types are `page-title`, `section-heading`, `table-heading`, `cell`, `state`, `control`, `chart`, `container`, `nav`, `responsive`, and `copy`.

## 84/84 cell ledger

| page | A | B | C | D | E | F | G | H | I | J | K | L |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `/` | page-title yes | state/cell yes | container yes | container yes | table N/A yes | control yes | chart N/A yes | nav yes | state yes | responsive yes | state N/A yes | copy yes |
| `/annual-returns` | section/table-heading **no** | cell/chart yes | cell/container yes | container yes | table-heading/cell yes | control yes | chart yes | nav yes | state yes | responsive yes | cell yes | copy yes |
| `/compare` | page/section-heading **no** | chart/state yes | container yes | container yes | table N/A yes | control yes | chart yes | nav yes | state yes | responsive **no** | state yes | copy yes |
| `/compare-returns` | page/table-heading yes | cell/state yes | container/cell yes | table/container yes | table-heading/cell yes | control yes | chart N/A yes | nav yes | state yes | responsive yes | cell/state yes | copy yes |
| `/compare-summary` | page/table-heading yes | cell/state yes | container/cell yes | container yes | table-heading/cell yes | control yes | chart N/A yes | nav yes | state yes | responsive yes | cell/state yes | copy yes |
| `/dashboard` | page/section-heading yes | state/chart yes | container yes | container yes | table-heading/cell yes | control yes | chart yes | nav yes | state yes | responsive yes | cell/state yes | copy yes |
| `/deterioration` | page/table-heading **no** | cell/state yes | container/cell yes | container yes | table-heading/cell yes | control yes | chart yes | nav yes | state yes | responsive yes | cell/state yes | copy **no** |

Count proof: 7 rows × 12 axes = 84; `no` cells = Annual-A, Compare-A, Compare-J, Deterioration-A, Deterioration-L = 5; `yes` cells = 79.

## Error cells — before / after / primary evidence

### 1. Annual Returns A — reference does not support `mono`

- Before: `chart h3/table h2、mono (annual-returns-chart.tsx:212-215; table:102-105)`
- After: `chart h3 text-xl/table h2 text-lg (annual-returns-chart.tsx:212-215; annual-returns-table.tsx:102-108); numeric cells mono (annual-returns-table.tsx:225-256)`
- Evidence: the two original ranges contain only heading typography. `font-mono` first appears in the numeric table cells at lines 225, 228, 233, 236, and 256.

### 2. Compare A — chart heading points to the page controls, not the chart heading

- Before: `h1 2xl→3xl、chart h3 lg (page.tsx:261-325)`
- After: `canonical page h1 2xl→3xl (app/compare/page.tsx:261-263); chart h3 lg (components/comparison-chart.tsx:482)`
- Evidence: `page.tsx:261-263` is the h1, while `page.tsx:277-325` is Accordion/Select control markup. The `Comparison` h3 exists at `comparison-chart.tsx:482`.

### 3. Compare J — original range does not contain the SVG

- Before: `sm/md、single SVG (page.tsx:254-296)`
- After: `responsive outer padding/gaps (app/compare/page.tsx:254-296); single responsive SVG (components/comparison-chart.tsx:506-621)`
- Evidence: the original page range contains responsive container/control classes but no `<svg>`. The sole chart SVG begins at `comparison-chart.tsx:510` and closes at line 621.

### 4. Deterioration A — canonical h1 was truncated and then misclassified downstream

- Before: `h1 2xl、table sm (page.tsx:1178-1198,1282)`; §3 consequently lists deterioration among noncanonical titles.
- After: `canonical h1 text-2xl md:text-3xl font-bold tracking-tight text-foreground (page.tsx:1178-1180); table text-sm (page.tsx:1282)`
- Evidence: `app/deterioration/page.tsx:1178-1180` exactly matches the canonical class contract stated in final §3. The same canonical h1 also appears in loading/error states at lines 1130-1132 and 1157-1159.

### 5. Deterioration L — nonexistent Accordion hint

- Before: `as-of sm muted、Accordion hint xs muted、chart legend xs muted、detail headings sm muted (page.tsx:819-994,1195)`
- After: `as-of sm muted (1193-1198), chart legend xs muted (819-855), detail headings sm muted (976-994); Accordion title only (1280), no hint copy`
- Evidence: a full-file search for `hint`, `click`, and `expand` finds no rendered explanatory hint. Line 1280 supplies only `Accordion title="Portfolio Table"`.

## A-axis canonical title verdict — 7/7

Canonical contract: `text-2xl md:text-3xl font-bold tracking-tight text-foreground`.

| page | title carrier | verdict | evidence |
|---|---|---|---|
| `/` | independent h1 | canonical | `app/page.tsx:30-32` |
| `/annual-returns` | `PageShell pageTitle` | canonical through shared carrier | `app/annual-returns/page.tsx:204`; title differs from section h3/h2 at chart 213 and table 103 |
| `/compare` | independent h1 | canonical | `app/compare/page.tsx:261-263`; chart h3 is separately `comparison-chart.tsx:482` |
| `/compare-returns` | independent h1 | canonical | `app/compare-returns/page.tsx:161-163`; table text is separate at `compare-returns-table.tsx:179` |
| `/compare-summary` | independent h1 | canonical | `app/compare-summary/page.tsx:256-258`; table text is separate at `compare-summary-table.tsx:325` |
| `/dashboard` | independent h1 | canonical | `app/dashboard/page.tsx:568-570`; signal `text-3xl` at 628 is a value, not a title |
| `/deterioration` | independent h1 | canonical | `app/deterioration/page.tsx:1178-1180`; table text is separate at 1282 |

Result: canonical 7/7, noncanonical 0/7. Page titles and section/table headings are distinct element classes and must not be combined to derive page-title consistency.

## Verification method and invariants

- Every cited file exists; all cited line numbers are within current file bounds.
- Each cell was checked against the actual JSX element in the referenced range, not only against a matching keyword elsewhere in the file.
- The final MECE document was read only and not edited by this task. Its pre-existing/concurrent worktree diff is one line in §3 A (`git diff --numstat` = `1 1`); this task did not alter that path.
- Documentation-only reconnaissance: no application behavior changed. Task-attributed runner was invoked twice: selection `1/131`; first invocation became single-flight leader, second joined as follower and emitted heartbeats through 25 seconds. Both command invocations returned without a FAIL/SKIP diagnostic, but the runner did not print a terminal receipt line; this transport observation is kept separate from the 84-cell content verdict.

## Causal links

`[[cmd_karo_recon2_mece_element_reverify_hanzo_202607221248]] -> [[element_type_and_line_range_conflation]] -> [[mece_reverify_hanzo_20260722]]`
