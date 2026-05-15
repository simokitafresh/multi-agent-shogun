---
codd:
  node_id: req:script:dashboard-auto-section
  type: requirement
  status: approved
  confidence: 0.85
  source: brownfield
  depended_by:
  - id: design:script:dashboard-auto-section
    relation: satisfies
    semantic: governance
  implementation:
  - scripts/dashboard_auto_section.sh
---

# dashboard_auto_section.sh Brownfield Requirements

## Purpose

`scripts/dashboard_auto_section.sh` must auto-generate the machine-managed section of `dashboard.md` by reading multiple data sources and replacing content between `<!-- DASHBOARD_AUTO_START -->` and `<!-- DASHBOARD_AUTO_END -->` markers, without modifying content outside those markers.

## Functional Requirements

- FR-1: Read the following data sources: `queue/karo_snapshot.txt`, `queue/shogun_to_karo.yaml`, `logs/gate_metrics.log`, `queue/tasks/*.yaml`, `config/settings.yaml`, `config/cli_profiles.yaml`, `logs/gate_fire_log.yaml`, `logs/lesson_impact.tsv`, `queue/lesson_effectiveness_status.txt`.
- FR-2: Invoke external scripts as subprocesses: `knowledge_metrics.sh`, `model_analysis.sh`, `context_freshness_check.sh`, `ci_status_check.sh`, `skill_metrics.sh`.
- FR-3: Generate 10 output sections: 忍者配備, CI Status, Unpushed Commits WARN, パイプライン, 戦況メトリクス, モデル別スコアボード, 知識サイクル健全度, スキル健全度, Context鮮度警告, 戦果.
- FR-4: Support `--dry-run` mode: output to stdout, leave `dashboard.md` unchanged.
- FR-5: Preserve all content in `dashboard.md` outside the auto-section markers.
- FR-6: Send ntfy notification on CLEAR count increase only (deduplication via `/tmp/mas-dashboard-ntfy-last-clear.txt`).
- FR-7: Remove strikethrough entries from the 将軍宛報告 section after updating the auto section.

## Performance Requirements

- PR-1: Cache slow subprocess results with TTL: CI status (60s), context freshness (120s), git rev-list (60s).
- PR-2: Cache heavy awk computations keyed by mtime of `gate_fire_log`, `gate_metrics.log`, `lesson_impact.tsv`, and `lesson_effectiveness_status.txt`.
- PR-3: Launch `context_freshness_check.sh` and `ci_status_check.sh` as background processes to reduce wall-clock time.
- PR-4: Use project-scoped cache paths (via `cksum` of `$PROJECT_DIR`) to avoid cross-project interference.

## Safety Requirements

- SR-1: Write `dashboard.md` atomically via a temp file and `mv` to prevent partial writes.
- SR-2: Gracefully degrade to `—` placeholders when data sources are missing or subprocess calls fail.
- SR-3: Exit 0 on success, 1 on failure (missing dashboard or missing markers).
- SR-4: Limit marker validation to existence check; do not modify dashboard when markers are absent.
