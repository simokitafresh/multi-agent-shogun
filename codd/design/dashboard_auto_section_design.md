---
codd:
  node_id: design:script:dashboard-auto-section
  type: design
  status: approved
  confidence: 0.85
  source: brownfield
  depends_on:
  - id: req:script:dashboard-auto-section
    relation: satisfies
    semantic: governance
  implementation:
  - scripts/dashboard_auto_section.sh
---

# dashboard_auto_section.sh Brownfield Design

## Entry Flow

The script resolves project paths, parses `--dry-run`, computes a project-scoped hash for cache isolation, then executes in three phases: (1) cache warm-up from mtime keys, (2) parallel background launch of slow subprocesses, (3) sequential data aggregation and section generation.

## Core Components

- `compute_first_fire_rate`: reads `gate_fire_log.yaml` in one awk pass to compute PASS/(PASS+FAIL) excluding `/tmp/` test entries. Result stored in heavy cache.
- `_MODEL_CACHE` (gawk): reads `settings.yaml` and `cli_profiles.yaml` in one gawk pass to build ninja→display_model map.
- `_task_map_src` (CMD_NINJAS / NINJA_CMD): reads all ninja task YAMLs in one awk pass to build cmd→ninjas and ninja→cmd mappings.
- Streak / TOTAL_CMDS / CLEAR_COUNT / CLEARED_CMDS: single-pass loop over `gate_metrics.log` sorted by timestamp.
- Heavy cache (`_HEAVY_CACHE_DIR`): keyed by stat mtime of 4 files; caches ffr, metrics.tsv, recent30.tsv, gate_titles.tsv, task_type_rows.txt, lesson_threshold.txt.
- Background subprocesses: `context_freshness_check.sh` (TTL 120s) and `ci_status_check.sh` (TTL 60s, stale refresh via lock file).
- `TITLE_MAP` (associative array): deduplicated cmd→title lookup; priority order gate_metrics > pipeline > archive.
- Section generator (lines 881-1178): heredoc-like `{ ... } > "$TMPFILE"` block generates all 10 sections from pre-computed variables.
- Atomic write: `awk`-based marker replacement writes to `${DASHBOARD}.tmp` then `mv`.
- ntfy dedup: skips send when `CLEAR_COUNT <= _last_clear_count` from `/tmp/mas-dashboard-ntfy-last-clear.txt`.
- Strikethrough removal: post-write `awk` pass removes `^- ~~` lines from 将軍宛報告 section.

## Data Boundaries

Inputs: `queue/karo_snapshot.txt`, `queue/shogun_to_karo.yaml`, `logs/gate_metrics.log`, `queue/tasks/*.yaml`, `config/settings.yaml`, `config/cli_profiles.yaml`, `logs/gate_fire_log.yaml`, `logs/lesson_impact.tsv`, `queue/lesson_effectiveness_status.txt`.

External script outputs (consumed via temp files): `knowledge_metrics.sh --json --by-project --by-model` → JSON; `model_analysis.sh --summary` → `model_row=` prefixed lines; `context_freshness_check.sh --dashboard-warnings` → plain text warnings; `ci_status_check.sh --status` → `GREEN` or `RED:<run_id>:<failed>`; `skill_metrics.sh` → pipe-delimited table.

Outputs: `dashboard.md` auto section (between markers), ntfy notification (on CLEAR increase), terminal stdout (--dry-run).

## Known Design Gaps (elicit findings)

- GAP-1 (concurrent_write_safety): No flock on `dashboard.md` write. Concurrent invocations (from dashboard-update skill and ninja_monitor) may interleave writes via the `.tmp` file.
- GAP-2 (ntfy_dedup_scope): `/tmp/mas-dashboard-ntfy-last-clear.txt` is not project-scoped (no `_proj_hash`). Multiple MAS instances on the same host share this file, causing missed notifications.
- GAP-3 (external_script_contract): Output format contracts for `knowledge_metrics.sh`, `model_analysis.sh`, `ci_status_check.sh`, `context_freshness_check.sh`, `skill_metrics.sh` are not documented in requirements or design.
- GAP-4 (marker_order_unvalidated): Script checks marker existence but not that MARKER_START precedes MARKER_END; inverted markers produce a truncated output.
- GAP-5 (silent_failure_opacity): `|| true` suppresses subprocess errors silently; no stderr log when data sources fail, making operational debugging difficult.

## Brownfield Evidence

- `scripts/dashboard_auto_section.sh` documents input/output contracts in its header comments.
- `scripts/dashboard_auto_section.sh` implements heavy cache with mtime key invalidation.
- `scripts/dashboard_auto_section.sh` launches background subprocesses for CI and context freshness.
- `scripts/dashboard_auto_section.sh` uses gawk multi-file pass for ninja model resolution (GP-081, cmd_1392).
