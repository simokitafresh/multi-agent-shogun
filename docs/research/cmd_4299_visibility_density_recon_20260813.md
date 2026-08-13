# cmd_4299 visibility density reconnaissance

- cmd: `cmd_4299`
- date: `2026-08-13`
- scope: DM-Signal `/admin/visibility` code inventory + authenticated production CDP measurement
- non-goal: implementation, production Save, deployment

## 1. Code inventory

Primary source: `/mnt/c/Python_app/DM-signal/frontend/app/admin/visibility/`.

| Area | Evidence |
|---|---|
| tier/global state and fetch | `page.tsx:71-195` |
| unsaved tier-switch guard | `page.tsx:202-228` |
| page visibility toggles | `page.tsx:237-249`, `:660-741` |
| three PF toggles | `page.tsx:251-275`, `:1222-1333` (`hide_portfolio`, `hide_signal`, `hide_components`) |
| global bulk toggles | `page.tsx:303-352`, `:767-865` |
| folder hide/bulk toggles | `page.tsx:287-300`, `:419-447`, `:911-1133` |
| folder collapse state and rendering | `page.tsx:107-110`, `:450-480`, `:911-1042`, `:1135-1137` |
| Save payload | `page.tsx:482-548` (hidden pages, portfolio settings, folder settings, updated_at) |
| tier selector | `components/TierSelector.tsx:16-61` |
| tier CRUD/reorder/password actions | `components/ManageTiersModal.tsx:20-208`, rendering `:309-437` |
| table/header/cell styles | `page.tsx:767-870`, PF cells `:1176,1210,1223,1259,1297` |

`rg` over the visibility page/components found `collapsedFolders` only in the state/toggle/read path; no `localStorage`, `sessionStorage`, or Save/API payload path for that state exists in this scope. The existing `folder_settings` payload is visibility-hide state, not collapse state. Therefore Save-based collapse persistence is not supported by the current code evidence; no implementation was made.

## 2. Production CDP measurement

Authenticated via the standard DM-Signal CDP auth flow and measured DOM/getComputedStyle at viewport `1036×906px`, DPR `1.5`, `scrollY=0`.

| State | document/body scrollHeight | table scrollHeight | DOM rows |
|---|---:|---:|---:|
| all folders open | `6556px` | `5862px` | `109` = thead 1 + folder 6 + PF 102 |
| all folders closed | `980px` | `286px` | `7` = thead 1 + folder 6 |

Computed values:

- PF row height: `54.33–54.67px` (two subpixel variants); PF cell padding: top/bottom `8px/8px`; line-height `20px`; font-size `14px`.
- Folder header height: `40px`; folder header cell padding: top/bottom `8px/8px`.
- Table header height: `46.33px`; thead cell padding: top/bottom `12px/12px`.
- At scroll top, fully visible PF rows: `2`; viewport-intersecting PF rows: `3`.

## 3. Design material

- Row-density candidate: current PF rows are about `54.33–54.67px`; reducing `py-2` needs a separate admin-density decision because it goes below the viewer canonical `py-3`.
- Collapse candidate: open→closed reduces document scrollHeight by `5576px` (`~85.0%`), so existing collapse is a high-impact operational control; it is currently session-only in code.
- Search/filter candidate: only `2` PF rows fully fit in the desktop viewport when open; PF-name search or folder filtering remains a separate, unimplemented feature decision.

Conclusion: The implementation surface and density baseline are fully measured; no implementation should begin until the owner resolves the collapse-persistence discrepancy and chooses density versus search/filter scope.

origin: `[[殿指示_visibility両面実測_20260813]] -> [[cmd_4299両面偵察]] -> [[AsIs調査の抜け_フォルダ開閉未言及]]`
