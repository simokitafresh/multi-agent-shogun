# SSOT Audit Round 2: Clinic Expense Tracker

metadata:
- task: cmd_3459_normal
- auditor: hayate
- audited_at: 2026-06-20
- repo: `/mnt/c/Python_app/clinic-expense-tracker`
- scope: SSOT references, absolute path embedding, duplicated config/default values, hard-coded constants

| Area | Evidence | SSOT / Current Source | Duplication Or Risk | Fix Target Candidate |
|---|---|---|---|---|
| Application DB | `docs/01-requirements.md:213` | Render app SQLite DB is documented SSOT | Clear SSOT statement: local is backup/download sync, no bidirectional sync | Preserve; implementation changes must not introduce local-primary writes |
| Expense source settings | `docs/01-requirements.md:216`, `app.py:282-294`, `templates/settings.html` | Web `/settings` CRUD | Web setting screen is documented SSOT for categories/items | Positive SSOT pattern; audit code paths before modifying |
| SQLite file validation | `app.py:119` `_SQLITE_MAGIC` | App-level DB validation | Constant appears internal and local | Low risk |
| MoneyForward pipeline path | `docs/03-data-architecture.md:98-101` | Documentation command uses `auto-ops` and project `.env.moneyforward` | Absolute paths embedded in docs | Low risk if docs-only; script equivalents should use parameters |
| Gmail API base | `scripts/gmail_to_sqlite.py:139`, `scripts/parse_sase_shortage.py:52,141` | `gmail_to_sqlite.GMAIL_API_BASE` | Positive pattern: parser imports API base from one script module | If promoted, extract to shared config module |
| Google Workspace account | `scripts/gmail_to_sqlite.py:114` | Env var `GOOGLE_WORKSPACE_CLI_ACCOUNT` set from script constant | Bounded scan did not locate external config for account value | Candidate for env/config SSOT if account differs by environment |
| Render env loading | `docs/05-render-deploy.md:20`, `.env.render` present | Env file for deploy operations | `.env.render` exists but was not opened | Keep secrets env-only; avoid committing literal deploy secrets |

Counts from bounded search:
- Explicit SSOT decisions in requirements: 2.
- Absolute `/mnt/c/Python_app/...` doc/script command references: multiple docs and script docstrings.
- Shared API constant pattern: 1 positive pattern (`GMAIL_API_BASE` imported by parser).

Blind spots:
- `.env.moneyforward` and `.env.render` were not opened.
- No Gmail/API/Render operation was executed.
- App internals were not fully traced beyond bounded SSOT keyword scan.
