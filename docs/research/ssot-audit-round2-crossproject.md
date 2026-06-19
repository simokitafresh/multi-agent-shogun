# SSOT Audit Round 2: Cross-Project Patterns

metadata:
- task: cmd_3459_normal
- auditor: hayate
- audited_at: 2026-06-20
- projects: DM-Signal, Google Classroom, Clinic Expense Tracker, Dividend Tracker
- scope: common SSOT risks across bounded keyword scans

| Pattern | Projects | Evidence | Risk | Candidate Direction |
|---|---|---|---|---|
| Absolute local path embedding | DM-Signal, Google Classroom, Clinic Expense Tracker | `/mnt/c/Python_app/DM-signal` in scripts; `C:\Python_app\google_classroom` in PowerShell defaults; `/mnt/c/Python_app/clinic-expense-tracker` in docs/scripts | Repo moves, WSL/Windows split, and multi-node operation break scripts | Derive repo root from script path or require explicit CLI args; keep docs-only paths marked as examples |
| Environment variable SSOT works but is uneven | DM-Signal, Google Classroom, Clinic Expense Tracker | `DATABASE_URL`, `GOOGLE_EMAIL`, `GOOGLE_PASSWORD`, `.env.render`, `.env.moneyforward` | Some scripts correctly use env, but at least one DM-Signal analysis script embeds production DB URL | Standardize env loading helpers and gate literal secret-like URLs in executable scripts |
| Production base URL duplication | DM-Signal, Google Classroom | DM-Signal one-off registration scripts hard-code `https://dm-signal-backend.onrender.com`; Google Classroom Gradle BuildConfig embeds Render URL | URL changes require many edits or rebuild assumptions | Central URL resolver for Python scripts; Gradle property/env for Android build config |
| Constants duplicated across frontend/backend | DM-Signal | `MAX_PORTFOLIOS` in backend/frontend with frontend test asserting backend parity | Test catches mismatch but does not make one side generated from the other | Generate frontend constants or expose backend config endpoint if runtime-safe |
| Positive explicit SSOT comments | DM-Signal, Clinic Expense Tracker | Trade period return and annual return comments/tests; clinic requirements D6/D9 | Existing good patterns can guide ontology labels | Preserve and index these as positive SSOT anchors |
| Docs as historical duplicates | All except low-hit Dividend | Research/future docs repeat settings, paths, and examples | Docs may be mistaken for active implementation source | Mark active/current docs or add "historical" front matter where needed |
| One-off scripts as drift source | DM-Signal | `scripts/oneshot/cmd_*.py` repeat URLs, DB env handling, paths | One-off scripts often survive into operations and carry stale constants | Move reusable operational logic out of one-off scripts before reuse |

Cross-project counts:
- 4 repos audited.
- 3 repos show absolute path embedding in bounded scan.
- 3 repos rely on environment variables as intended SSOT.
- 2 repos repeat production service URLs.
- 1 repo shows clear frontend/backend constant duplication with test-only parity.

Implementation-readiness notes:
- Likely first code targets: DM-Signal registration/oneshot URL handling, DM-Signal literal DB URL, DM-Signal frontend/backend constant sync.
- Lower-risk docs cleanup targets: Google Classroom and Clinic Expense Tracker absolute path examples.
- Dividend Tracker currently has no strong SSOT violation by keyword scan; deeper app route tracing would be needed before action.

Blind spots:
- This is a reconnaissance artifact; no fixes were applied.
- Searches were bounded and keyword-based.
- Secret env files were intentionally not opened.
- Existing dirty worktrees were not modified or reverted.
