# Portable Learning Loop Core

origin: [[cmd_3726]] -> [[学習ループのリポジトリ癒着]] -> [[cmd_3728_T6実装]]
created: 2026-07-07

## Boundary

Portable core is the smallest set needed to run one learning cycle in another project:

| Layer | Portable file | Role |
|---|---|---|
| report gate | `scripts/learning-loop/report_gate.py` | validates completed reports and binary checks |
| lesson | `scripts/learning-loop/lesson_write.sh` | appends reusable lessons |
| insight | `scripts/learning-loop/insight_write.sh` | appends pending improvement insights |
| memory | `scripts/learning-loop/memory_write.sh` | appends JSONL knowledge events |
| semantic | `scripts/learning-loop/semantic_search.sh` | searches semantic map and memory |
| inbox | `scripts/learning-loop/inbox_write.sh` | appends file-based messages |
| stores | `.learning-loop/` | project-local state |

Project-specific layer is intentionally excluded: tmux panes, agent roster, dashboards, shogun/karo/ninja hierarchy, `/mnt/c` paths, WSL2 assumptions, and this repository's knowledge files.

## Bootstrap

Install into an isolated project directory:

```bash
bash scripts/portable_loop_bootstrap.sh /tmp/portable-loop-demo
cd /tmp/portable-loop-demo
bash scripts/learning-loop/lesson_write.sh "First lesson" "Record a reusable rule" "smoke" "local"
bash scripts/learning-loop/insight_write.sh "First insight" medium smoke
bash scripts/learning-loop/memory_write.sh "portable core installed" smoke
python3 scripts/learning-loop/report_gate.py report.yaml
```

The report gate accepts JSON or simple YAML. Required report fields:
`worker_id`, `parent_cmd`, `status: completed`, `result.summary`, `purpose_validation`,
`files_modified`, `lesson_candidate.found`, `lessons_useful`, and `binary_checks.*[].result`.
Every binary check result must be `yes` or `no`; all `yes` produces `PASS`.

## Dependency Guard

Installed files must not contain these project-specific markers:

```text
tmux
/mnt/c
multi-agent-shogun
queue/tasks
queue/reports
shogun_to_karo
```

The regression test `tests/unit/test_portable_loop_bootstrap.bats` installs the core into a temporary directory, runs the lesson/insight/report-gate smoke path, and scans the installed files for those markers.
