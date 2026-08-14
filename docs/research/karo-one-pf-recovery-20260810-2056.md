# Karo one-PF recovery checkpoint — 2026-08-10 20:56 JST

- Lord protocol: full/all-PF validation is forbidden during iteration. Validate L5 on one representative PF, fix, rerun the same PF; expand to 3 PF only after PASS. Run all PF only when projected full time is under 5 minutes.
- Representative PF: `fc82e757-4ade-4b2b-9af4-49895d96c29f`.
- Remote main: `f76df2a7139476a89e6a13997b1a68c2060bc0c9`.
- Included hotfixes:
  - `bcb75220`: preserve annual-return no-data semantics with an internal L5 sentinel.
  - `f76df2a7`: `POST /admin/precompute-raw?portfolio_id=<id>` scopes L5 to one PF.
- Render deployment: `dep-d9sro1b7uimc73bvm6rg`; it was `build_in_progress` before WSL shutdown.
- Immediate recovery action: confirm this deployment is `live`; confirm erroneous all-PF run 236 is no longer running after service cutover; then POST L5 for the representative PF only.
- Completion evidence for one-PF L5: Render `[P4_TIMING_SUCCESS]`/terminal log, portfolios=1, failed=0, elapsed seconds, rows count, and `annual_returns` no-data read remains `None` without `IncompletePortfolioRaw`.
- Previous all-PF L5 evidence (do not repeat): portfolios=102, rows=108, failed=95, elapsed=123.70s. Common failure was annual_returns builder `None`.
- Erroneous full run: DB status id 236 / run_id `20260810113657B38B77`; it emitted thousands of guarded `SIGNAL DECISION DRIFT` alerts. Writes were blocked by the confirmed-ledger guard. Do not use its timing as clean one-PF evidence.
