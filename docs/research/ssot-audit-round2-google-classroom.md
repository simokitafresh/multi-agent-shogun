# SSOT Audit Round 2: Google Classroom

metadata:
- task: cmd_3459_normal
- auditor: hayate
- audited_at: 2026-06-20
- repo: `/mnt/c/Python_app/google_classroom`
- scope: SSOT references, absolute path embedding, duplicated config/default values, hard-coded constants

| Area | Evidence | SSOT / Current Source | Duplication Or Risk | Fix Target Candidate |
|---|---|---|---|---|
| Credentials | `CLAUDE.md:82-83`, `docs/architecture.md:233-234`, `scripts/auto_login.py:25-26` | `.env` / environment variables | Docs repeat env variable names; script reads env correctly | Keep secrets env-only; docs should stay placeholder-only |
| Render base URL | `android/app/build.gradle.kts:17`, `android/app/src/main/java/com/classroom/app/SyncManager.kt:100`, `MainActivity.kt:327` | Android `BuildConfig.RENDER_BASE_URL` | URL hard-coded at build config field; app reads BuildConfig consistently | If multiple deploy targets exist, make Gradle property/env the SSOT |
| Windows project root | `CLAUDE.md:99`, `scripts/setup_full_update_scheduler.ps1:3`, `scripts/run_full_update_and_push.ps1:2` | PowerShell script parameter default | `C:\Python_app\google_classroom` repeated in docs/scripts | Derive default or document one canonical Windows root |
| WSL/project references | `docs/research/cmd_3447_android_webview_viewport_sidebar.md:129`, `docs/future/013.md:258,310`, `docs/future/011.md:258,312,640` | Documentation references only | Many absolute references point to this repo and multi-agent-shogun repo | Low risk if docs-only; avoid copying into scripts |
| Android WebView viewport settings | `android/app/src/main/java/com/classroom/app/MainActivity.kt:99-114`, research docs repeat same settings | `MainActivity.kt` is implementation SSOT | Research docs duplicate values for explanation | Keep docs as historical; implementation changes should update only code plus latest design note |
| Google Classroom tabs | `scripts/scrape_todo.py:14,163` | `TODO_TABS` constant | Tab mapping appears local to one script | No duplication found in bounded scan |

Counts from bounded search:
- Hard-coded Render URL: 1 build config field, read through BuildConfig in app code.
- Hard-coded Windows project root defaults: 2 PowerShell scripts plus docs.
- `.env` credential references: docs and one script, with script using env.

Blind spots:
- `.env` was not opened.
- Browser profile data under `browser_data*` was not inspected.
- No Android build or web scrape was executed.
