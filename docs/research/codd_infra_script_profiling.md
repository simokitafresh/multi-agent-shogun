# cmd_1951 インフラスクリプト全量プロファイリング

## 0. CoDD改善バッチ計画(2026-04-16)

| バッチ | cmd | 対象 | status |
|--------|-----|------|--------|
| 1 | 1953-1958 | shutsujin_departure, dashboard_auto_section, gate_cycle_health, report_merge, gate_artifact_map, gate_karo_startup | **全GATE CLEAR** |
| 2 | 1959-1964 | gate_recalculate_completeness, inbox_write, ntfy, lesson_effectiveness, gate_loop_health, gate_lesson_health | **全GATE CLEAR** |
| 3 | 1965-1970 | ninja_done, report_field_set, karo_workaround_log, archive_completed, pre_compact_save, gate_workaround_rate | **全GATE CLEAR** |
| 4 | 1971-1976 | lesson_harvest, parity_check, model_switch_preflight, post_recalculate_checks, test_hooks, gate_vercel_phase | **全GATE CLEAR** |
| 単発 | 1977-1978 | cmd_save.sh(4.0s→1.06s), stop-lint-gate.sh(0.82s→0.65s) | **全GATE CLEAR** |
| 5(再トライ) | 1979-1984 | inbox_write, gate_recalculate_completeness, dashboard_auto_section, gate_cycle_health, deploy_task, gate_karo_startup | **全GATE CLEAR** |

知見: ACは4段階(spec/design/impl/test)に分解(codd.md §4.5)。ただし道具の目的と作業性質を照合し機械的適用は避ける(LS036)。

## 1. 前提と方法

- 対象: `scripts/**/*.sh` + `.claude/hooks/*.sh` の全220本。
- AC1確認: `find scripts .claude/hooks -type f -name "*.sh" | wc -l` = **220**。
- 計測: 常駐系は除外し、それ以外は `bash <script> --help` 優先、非対応は `bash <script>`、`timeout 3-4s` で実測。
- 分類基準: A=高頻度パス、B=低頻度だが重要、C=低頻度だが遅い。MECEで全件に1カテゴリを付与。
- 既リファクタ済み: `deploy_task.sh`、`gate_gunshi_startup.sh`、`gate_shogun_startup.sh`、`cmd_complete_gate.sh` は優先順位から除外し `済` 表示。

## 2. 集計

| 指標 | 値 |
|---|---:|
| 総数 | 220 |
| A | 93 |
| B | 109 |
| C | 18 |
| 常駐系で計測除外 | 11 |

## 3. 優先順位 Top 20

| 順位 | スクリプト | 区分 | 実行時間ms | 呼出し証跡 | 発火条件 | 改善見込み | 備考 |
|---:|---|:---:|---:|---:|---|:---:|---|
| 1 | `scripts/gates/gate_report_format.sh` | A | 40 | 48 | gate/startup/report validation | 低 |  |
| 2 | `scripts/shutsujin_departure.sh` | A | 2424 | 38 | manual/maintenance | 高 |  |
| 3 | `scripts/lib/yaml_field_set.sh` | A | 51 | 41 | manual/maintenance | 低 |  |
| 4 | `scripts/cdp/cdp_cli.sh` | A | 36 | 27 | manual/maintenance | 低 |  |
| 5 | `scripts/ntfy.sh` | A | 130 | 60 | manual/maintenance | 中 |  |
| 6 | `scripts/inbox_watcher.sh` | A |  | 91 | task lifecycle / agent communication | 低 |  |
| 7 | `scripts/inbox_write.sh` | A | 89 | 312 | task lifecycle / agent communication | 低 |  |
| 8 | `scripts/ninja_done.sh` | A | 68 | 104 | task lifecycle / agent communication | 低 |  |
| 9 | `scripts/report_field_set.sh` | A | 40 | 73 | manual/maintenance | 低 |  |
| 10 | `scripts/ninja_monitor.sh` | A |  | 35 | daemon/watcher loop | 低 |  |
| 11 | `scripts/lib/cli_lookup.sh` | A | 50 | 30 | manual/maintenance | 低 |  |
| 12 | `.claude/hooks/stop-lint-gate.sh` | A | 3002 | 1 | .claude/settings.json hook | 高 | timeout |
| 13 | `scripts/lib/agent_config.sh` | A | 36 | 29 | manual/maintenance | 低 |  |
| 14 | `scripts/lib/field_get.sh` | A | 33 | 29 | manual/maintenance | 低 |  |
| 15 | `scripts/archive_completed.sh` | A | 52 | 31 | task lifecycle / agent communication | 低 |  |
| 16 | `scripts/cmd_delegate.sh` | A | 28 | 28 | manual/maintenance | 低 |  |
| 17 | `scripts/inbox_mark_read.sh` | A | 34 | 28 | task lifecycle / agent communication | 低 |  |
| 18 | `.claude/hooks/pre-bash-combined.sh` | A | 21 | 4 | .claude/settings.json hook | 低 |  |
| 19 | `scripts/dashboard_auto_section.sh` | A | 2775 | 21 | manual/maintenance | 高 |  |
| 20 | `scripts/gates/gate_cycle_health.sh` | A | 2575 | 11 | gate/startup/report validation | 高 |  |

## 4. 最遅スクリプト Top 15

| スクリプト | 実行時間ms | 区分 | 優先 | 備考 |
|---|---:|:---:|---:|---|
| `scripts/lesson_effectiveness.sh` | 5498 | C | 114 | timeout |
| `scripts/lesson_harvest.sh` | 5498 | C | 132 | timeout |
| `scripts/parity_check.sh` | 5495 | C | 107 | timeout |
| `scripts/oneshot/backfill_gate_titles.sh` | 5491 | C | 134 | timeout |
| `scripts/post_recalculate_checks.sh` | 5489 | C | 129 | timeout |
| `scripts/ralph_loop_metrics.sh` | 5484 | C | 135 | timeout |
| `scripts/model_switch_preflight.sh` | 5483 | C | 104 | timeout |
| `scripts/gates/gate_shogun_startup.sh` | 4039 | A | 済 | 済 |
| `scripts/gates/gate_recalculate_completeness.sh` | 4026 | A | 43 | timeout |
| `scripts/gist_index_update.sh` | 4023 | C | 201 | timeout |
| `scripts/cmd_save.sh` | 4016 | B | 27 | timeout |
| `scripts/gunshi_next_action.sh` | 4016 | C | 184 | timeout |
| `scripts/hooks/test_hooks.sh` | 4015 | A | 47 | timeout |
| `scripts/backfill_review_gate_done.sh` | 4014 | C | 172 | timeout |
| `scripts/affected_tests.sh` | 4013 | C | 136 | timeout |

## 5. 全220本一覧

| 優先 | スクリプト | 区分 | 実行時間ms | 呼出し証跡 | 発火条件 | 改善見込み | 計測 | 備考 |
|---:|---|:---:|---:|---:|---|:---:|---|---|
| 1 | `scripts/gates/gate_report_format.sh` | A | 40 | 48 | gate/startup/report validation | 低 | --help |  |
| 2 | `scripts/shutsujin_departure.sh` | A | 2424 | 38 | manual/maintenance | 高 | --help |  |
| 3 | `scripts/lib/yaml_field_set.sh` | A | 51 | 41 | manual/maintenance | 低 | --help |  |
| 4 | `scripts/cdp/cdp_cli.sh` | A | 36 | 27 | manual/maintenance | 低 | --help |  |
| 5 | `scripts/ntfy.sh` | A | 130 | 60 | manual/maintenance | 中 | --help |  |
| 6 | `scripts/inbox_watcher.sh` | A |  | 91 | task lifecycle / agent communication | 低 | skip | daemon/long-running |
| 7 | `scripts/inbox_write.sh` | A | 89 | 312 | task lifecycle / agent communication | 低 | --help |  |
| 8 | `scripts/ninja_done.sh` | A | 68 | 104 | task lifecycle / agent communication | 低 | --help |  |
| 9 | `scripts/report_field_set.sh` | A | 40 | 73 | manual/maintenance | 低 | --help |  |
| 10 | `scripts/ninja_monitor.sh` | A |  | 35 | daemon/watcher loop | 低 | skip | daemon/long-running |
| 11 | `scripts/lib/cli_lookup.sh` | A | 50 | 30 | manual/maintenance | 低 | --help |  |
| 12 | `.claude/hooks/stop-lint-gate.sh` | A | 3002 | 1 | .claude/settings.json hook | 高 | no-args | timeout |
| 13 | `scripts/lib/agent_config.sh` | A | 36 | 29 | manual/maintenance | 低 | --help |  |
| 14 | `scripts/lib/field_get.sh` | A | 33 | 29 | manual/maintenance | 低 | --help |  |
| 15 | `scripts/archive_completed.sh` | A | 52 | 31 | task lifecycle / agent communication | 低 | --help |  |
| 16 | `scripts/cmd_delegate.sh` | A | 28 | 28 | manual/maintenance | 低 | --help |  |
| 17 | `scripts/inbox_mark_read.sh` | A | 34 | 28 | task lifecycle / agent communication | 低 | --help |  |
| 18 | `.claude/hooks/pre-bash-combined.sh` | A | 21 | 4 | .claude/settings.json hook | 低 | no-args |  |
| 19 | `scripts/dashboard_auto_section.sh` | A | 2775 | 21 | manual/maintenance | 高 | --help |  |
| 20 | `scripts/gates/gate_cycle_health.sh` | A | 2575 | 11 | gate/startup/report validation | 高 | --help |  |
| 21 | `scripts/ntfy_listener.sh` | A |  | 27 | task lifecycle / agent communication | 低 | skip | daemon/long-running |
| 22 | `scripts/gates/gate_lesson_health.sh` | A | 228 | 16 | gate/startup/report validation | 中 | --help |  |
| 23 | `.claude/hooks/post-shogun-inbox-check.sh` | A | 34 | 2 | .claude/settings.json hook | 低 | no-args |  |
| 24 | `scripts/hooks/pre-write-report-deny.sh` | A | 31 | 2 | Stop/Session/Bash hook | 低 | --help |  |
| 25 | `scripts/hooks/prompt_state_inject.sh` | A | 38 | 2 | Stop/Session/Bash hook | 低 | no-args |  |
| 26 | `scripts/hooks/session_start_inject.sh` | A | 38 | 2 | Stop/Session/Bash hook | 低 | no-args |  |
| 27 | `scripts/cmd_save.sh` | B | 4016 | 86 | manual/maintenance | 高 | --help | timeout |
| 28 | `scripts/gates/gate_loop_health.sh` | A | 493 | 14 | gate/startup/report validation | 中 | --help |  |
| 29 | `scripts/hooks/pre_compact_save.sh` | A | 141 | 1 | Stop/Session/Bash hook | 中 | no-args |  |
| 30 | `.claude/hooks/post-bash-combined.sh` | A | 14 | 1 | .claude/settings.json hook | 低 | no-args |  |
| 31 | `.claude/hooks/post-search-completeness-guard.sh` | A | 17 | 1 | .claude/settings.json hook | 低 | no-args |  |
| 32 | `.claude/hooks/post-write-edit-combined.sh` | A | 34 | 1 | .claude/settings.json hook | 低 | no-args |  |
| 33 | `.claude/hooks/pre-write-edit-combined.sh` | A | 32 | 1 | .claude/settings.json hook | 低 | no-args |  |
| 34 | `.claude/hooks/pre-write-read-tracker.sh` | A | 20 | 1 | .claude/settings.json hook | 低 | no-args |  |
| 35 | `scripts/gates/gate_karo_startup.sh` | A | 1106 | 12 | gate/startup/report validation | 高 | --help |  |
| 36 | `scripts/hooks/pre-bash-report-deny.sh` | A | 30 | 1 | Stop/Session/Bash hook | 低 | no-args |  |
| 37 | `scripts/hooks/session_end_clear_check.sh` | A | 45 | 1 | Stop/Session/Bash hook | 低 | no-args |  |
| 38 | `scripts/hooks/stop_check_inbox.sh` | A |  | 1 | Stop/Session/Bash hook | 低 | skip | daemon/long-running |
| 39 | `scripts/gates/gate_workaround_rate.sh` | A | 135 | 14 | gate/startup/report validation | 中 | --help |  |
| 40 | `scripts/report_merge.sh` | A | 1947 | 19 | manual/maintenance | 高 | --help |  |
| 41 | `scripts/gates/gate_artifact_map.sh` | A | 2155 | 8 | gate/startup/report validation | 高 | no-args |  |
| 42 | `scripts/auto_draft_lesson.sh` | A | 30 | 23 | manual/maintenance | 低 | --help |  |
| 43 | `scripts/gates/gate_recalculate_completeness.sh` | A | 4026 | 2 | gate/startup/report validation | 高 | no-args | timeout |
| 44 | `scripts/gates/gate_ninja_workaround_rate.sh` | A | 63 | 11 | gate/startup/report validation | 低 | --help |  |
| 45 | `scripts/gates/gate_report_autofix.sh` | A | 32 | 11 | gate/startup/report validation | 低 | --help |  |
| 46 | `scripts/karo_workaround_log.sh` | A | 61 | 20 | manual/maintenance | 低 | --help |  |
| 47 | `scripts/hooks/test_hooks.sh` | A | 4015 | 1 | Stop/Session/Bash hook | 高 | no-args | timeout |
| 48 | `scripts/log_terminal_response.sh` | A | 43 | 4 | manual/maintenance | 低 | no-args |  |
| 49 | `scripts/task_deploy.sh` | A | 17 | 19 | task lifecycle / agent communication | 低 | --help |  |
| 50 | `scripts/gates/gate_vercel_phase.sh` | A | 481 | 7 | gate/startup/report validation | 中 | --help |  |
| 51 | `scripts/log_terminal_input.sh` | A | 39 | 3 | manual/maintenance | 低 | no-args |  |
| 52 | `scripts/statusline.sh` | A | 33 | 3 | manual/maintenance | 低 | no-args |  |
| 53 | `scripts/sync_lessons.sh` | A | 117 | 17 | manual/maintenance | 中 | --help |  |
| 54 | `scripts/cmd_quality_log.sh` | A | 26 | 17 | manual/maintenance | 低 | --help |  |
| 55 | `scripts/gates/gate_yaml_status.sh` | A | 62 | 7 | gate/startup/report validation | 低 | --help |  |
| 56 | `scripts/insight_write.sh` | A | 324 | 16 | manual/maintenance | 中 | --help |  |
| 57 | `scripts/gates/gate_shogun_memory.sh` | A | 697 | 5 | gate/startup/report validation | 高 | --help |  |
| 58 | `scripts/gates/gate_gunshi_cs_checklist.sh` | A | 199 | 6 | gate/startup/report validation | 中 | --help |  |
| 59 | `scripts/gates/gate_dc_duplicate.sh` | A | 52 | 6 | gate/startup/report validation | 低 | --help |  |
| 60 | `scripts/gates/gate_enforcement_audit.sh` | A | 341 | 5 | gate/startup/report validation | 中 | --help |  |
| 61 | `scripts/gates/gate_wa_data_quality.sh` | A | 320 | 5 | gate/startup/report validation | 中 | --help |  |
| 62 | `scripts/gates/gate_skill_quality.sh` | A | 1399 | 2 | gate/startup/report validation | 高 | --help |  |
| 63 | `scripts/gates/gate_diagnose_check.sh` | A | 32 | 5 | gate/startup/report validation | 低 | --help |  |
| 64 | `scripts/gates/gate_silent_fallback.sh` | A | 27 | 5 | gate/startup/report validation | 低 | --help |  |
| 65 | `scripts/lesson_write.sh` | B | 87 | 52 | knowledge maintenance | 低 | --help |  |
| 66 | `scripts/gates/gate_context_freshness.sh` | A | 323 | 4 | gate/startup/report validation | 中 | --help |  |
| 67 | `scripts/gates/gate_gunshi_observations.sh` | A | 100 | 4 | gate/startup/report validation | 中 | --help |  |
| 68 | `scripts/gates/gate_pd_sync.sh` | A | 197 | 4 | gate/startup/report validation | 中 | --help |  |
| 69 | `scripts/gates/gate_cmd_state.sh` | A | 74 | 4 | gate/startup/report validation | 低 | --help |  |
| 70 | `scripts/gates/gate_field_get.sh` | A | 404 | 3 | gate/startup/report validation | 中 | --help |  |
| 71 | `scripts/gates/gate_gunshi_report_precheck.sh` | A | 41 | 4 | gate/startup/report validation | 低 | --help |  |
| 72 | `scripts/gates/gate_p_average_freshness.sh` | A | 65 | 4 | gate/startup/report validation | 低 | --help |  |
| 73 | `scripts/gates/mark_no_learning.sh` | A | 43 | 3 | gate/startup/report validation | 低 | --help |  |
| 74 | `scripts/hooks/bash_state_hook.sh` | A | 36 | 3 | Stop/Session/Bash hook | 低 | no-args |  |
| 75 | `scripts/hooks/git-pre-commit.sh` | A | 736 | 1 | Stop/Session/Bash hook | 高 | no-args |  |
| 76 | `scripts/hooks/test_result_guard.sh` | A | 32 | 2 | Stop/Session/Bash hook | 低 | no-args |  |
| 77 | `scripts/gates/gate_mcp_access.sh` | A | 39 | 0 | gate/startup/report validation | 低 | no-args |  |
| 78 | `.claude/hooks/pre-bash-yaml-dump-guard.sh` | A | 17 | 1 | .claude/settings.json hook | 低 | no-args |  |
| 79 | `.claude/hooks/post-bash-commit-reminder.sh` | A | 16 | 0 | .claude/settings.json hook | 低 | no-args |  |
| 80 | `.claude/hooks/post-edit-instruction-hook-consistency.sh` | A | 17 | 0 | .claude/settings.json hook | 低 | no-args |  |
| 81 | `.claude/hooks/post-edit-report-guard.sh` | A | 33 | 0 | .claude/settings.json hook | 低 | no-args |  |
| 82 | `.claude/hooks/post-write-shellcheck.sh` | A | 19 | 0 | .claude/settings.json hook | 低 | no-args |  |
| 83 | `.claude/hooks/pre-bash-no-verify-guard.sh` | A | 33 | 0 | .claude/settings.json hook | 低 | no-args |  |
| 84 | `.claude/hooks/pre-edit-report-deny.sh` | A | 17 | 0 | .claude/settings.json hook | 低 | no-args |  |
| 85 | `.claude/hooks/pre-edit-workaround-deny.sh` | A | 19 | 0 | .claude/settings.json hook | 低 | no-args |  |
| 86 | `.claude/hooks/pre-write-config-guard.sh` | A | 17 | 0 | .claude/settings.json hook | 低 | no-args |  |
| 87 | `scripts/hooks/block_destructive.sh` | A | 48 | 0 | Stop/Session/Bash hook | 低 | no-args |  |
| 88 | `scripts/hooks/pre-bash-test-fullrun-guard.sh` | A | 49 | 0 | Stop/Session/Bash hook | 低 | no-args |  |
| 89 | `scripts/hooks/pre-karo-edit-guard.sh` | A | 28 | 0 | Stop/Session/Bash hook | 低 | no-args |  |
| 90 | `scripts/hooks/pre-mcp-lord-attribution-guard.sh` | A | 50 | 0 | Stop/Session/Bash hook | 低 | no-args |  |
| 91 | `scripts/task_queue_status.sh` | A | 17 | 3 | task lifecycle / agent communication | 低 | --help |  |
| 92 | `scripts/pending_decision_write.sh` | B | 64 | 25 | knowledge maintenance | 低 | --help |  |
| 93 | `scripts/reset_layout.sh` | B | 2575 | 13 | manual/maintenance | 中 | --help |  |
| 94 | `scripts/lesson_write_karo.sh` | B | 46 | 16 | knowledge maintenance | 低 | --help |  |
| 95 | `scripts/lib/lock_path.sh` | B | 47 | 13 | manual/maintenance | 低 | --help |  |
| 96 | `scripts/lib/model_detect.sh` | B | 26 | 12 | manual/maintenance | 低 | --help |  |
| 97 | `scripts/context_freshness_check.sh` | B | 23 | 14 | manual/maintenance | 低 | --help |  |
| 98 | `scripts/ac_physical_verify.sh` | B | 149 | 13 | manual/maintenance | 低 | --help |  |
| 99 | `scripts/cmd_absorb.sh` | B | 28 | 13 | manual/maintenance | 低 | --help |  |
| 100 | `scripts/lesson_deprecate.sh` | B | 55 | 13 | knowledge maintenance | 低 | --help |  |
| 101 | `scripts/lesson_deprecation_scan.sh` | B | 74 | 13 | knowledge maintenance | 低 | --help |  |
| 102 | `scripts/lesson_update_score.sh` | B | 64 | 13 | knowledge maintenance | 低 | --help |  |
| 103 | `scripts/model_analysis.sh` | B | 53 | 13 | manual/maintenance | 低 | --help |  |
| 104 | `scripts/model_switch_preflight.sh` | C | 5483 | 7 | manual/maintenance | 高 | --help | timeout |
| 105 | `scripts/shout.sh` | B | 32 | 13 | manual/maintenance | 低 | --help |  |
| 106 | `scripts/lesson_review.sh` | B | 152 | 12 | knowledge maintenance | 低 | --help |  |
| 107 | `scripts/parity_check.sh` | C | 5495 | 6 | manual/maintenance | 高 | --help | timeout |
| 108 | `scripts/restart_watchers.sh` | B |  | 12 | daemon/watcher loop | 低 | skip | daemon/long-running |
| 109 | `scripts/gate_improvement_trigger.sh` | C | 3277 | 11 | manual/maintenance | 高 | --help |  |
| 110 | `scripts/lib/model_resolve.sh` | B | 34 | 9 | manual/maintenance | 低 | --help |  |
| 111 | `scripts/lib/normalize_report.sh` | B | 39 | 9 | manual/maintenance | 低 | --help |  |
| 112 | `scripts/review_gate.sh` | B | 215 | 11 | manual/maintenance | 低 | --help |  |
| 113 | `scripts/build_instructions.sh` | B | 1320 | 8 | manual/maintenance | 中 | no-args |  |
| 114 | `scripts/lesson_effectiveness.sh` | C | 5498 | 5 | knowledge maintenance | 高 | --help | timeout |
| 115 | `scripts/lib/tmux_utils.sh` | B | 22 | 8 | manual/maintenance | 低 | --help |  |
| 116 | `scripts/workaround_pattern_check.sh` | B | 666 | 9 | manual/maintenance | 低 | no-args |  |
| 117 | `scripts/ci_status_check.sh` | B | 908 | 8 | manual/maintenance | 低 | --help |  |
| 118 | `scripts/auto_failure_lesson.sh` | B | 30 | 10 | manual/maintenance | 低 | --help |  |
| 119 | `scripts/switch_cli_mode.sh` | B | 67 | 10 | manual/maintenance | 低 | --help |  |
| 120 | `scripts/lib/pane_lookup.sh` | B | 111 | 7 | manual/maintenance | 低 | --help |  |
| 121 | `scripts/lib/pane_format.sh` | B | 40 | 7 | manual/maintenance | 低 | --help |  |
| 122 | `scripts/sync_pane_vars.sh` | B | 1773 | 5 | manual/maintenance | 中 | --help |  |
| 123 | `scripts/auto_deploy_next.sh` | B | 34 | 9 | task lifecycle / agent communication | 低 | --help |  |
| 124 | `scripts/checklist_update.sh` | B | 36 | 9 | manual/maintenance | 低 | --help |  |
| 125 | `scripts/fullrecalculate.sh` | B | 47 | 9 | manual/maintenance | 低 | --help |  |
| 126 | `scripts/inbox_archive.sh` | B | 49 | 9 | task lifecycle / agent communication | 低 | --help |  |
| 127 | `scripts/lesson_merge.sh` | B | 70 | 9 | knowledge maintenance | 低 | --help |  |
| 128 | `scripts/ntfy_cmd.sh` | B | 39 | 9 | task lifecycle / agent communication | 低 | --help |  |
| 129 | `scripts/post_recalculate_checks.sh` | C | 5489 | 3 | manual/maintenance | 高 | no-args | timeout |
| 130 | `scripts/run_tests.sh` | B | 16 | 9 | manual/maintenance | 低 | --help |  |
| 131 | `scripts/gate_auto_respond.sh` | C | 3150 | 8 | manual/maintenance | 高 | --help |  |
| 132 | `scripts/lesson_harvest.sh` | C | 5498 | 2 | knowledge maintenance | 高 | --help | timeout |
| 133 | `scripts/lesson_write_shogun.sh` | B | 47 | 8 | knowledge maintenance | 低 | --help |  |
| 134 | `scripts/oneshot/backfill_gate_titles.sh` | C | 5491 | 2 | manual/maintenance | 高 | --help | timeout |
| 135 | `scripts/ralph_loop_metrics.sh` | C | 5484 | 2 | manual/maintenance | 高 | no-args | timeout |
| 136 | `scripts/affected_tests.sh` | C | 4013 | 5 | manual/maintenance | 高 | --help | timeout |
| 137 | `scripts/clear_prep_check.sh` | C | 3661 | 6 | manual/maintenance | 高 | --help |  |
| 138 | `scripts/lib/model_colors.sh` | B | 43 | 5 | manual/maintenance | 低 | --help |  |
| 139 | `scripts/gunshi_gate_reflux.sh` | B | 34 | 7 | manual/maintenance | 低 | --help |  |
| 140 | `scripts/lesson_check.sh` | B | 49 | 7 | knowledge maintenance | 低 | --help |  |
| 141 | `scripts/ralph_loop_closer.sh` | B | 19 | 7 | manual/maintenance | 低 | --help |  |
| 142 | `scripts/lib/ctx_utils.sh` | B | 36 | 4 | manual/maintenance | 低 | --help |  |
| 143 | `scripts/lib/script_update.sh` | B | 27 | 4 | manual/maintenance | 低 | --help |  |
| 144 | `scripts/bulletin_write.sh` | B | 548 | 5 | manual/maintenance | 低 | --help |  |
| 145 | `scripts/capture_clipboard_image.sh` | B | 551 | 5 | manual/maintenance | 低 | --help |  |
| 146 | `scripts/conversation_retention.sh` | B | 193 | 6 | manual/maintenance | 低 | no-args |  |
| 147 | `scripts/ntfy_batch.sh` | B | 112 | 6 | task lifecycle / agent communication | 低 | --help |  |
| 148 | `scripts/ntfy_inbox_archive.sh` | B | 1700 | 2 | task lifecycle / agent communication | 中 | --help |  |
| 149 | `scripts/daemon_watchdog.sh` | B |  | 6 | daemon/watcher loop | 低 | skip | daemon/long-running |
| 150 | `scripts/decision_write.sh` | B | 30 | 6 | knowledge maintenance | 低 | --help |  |
| 151 | `scripts/deploy_training.sh` | B | 25 | 6 | task lifecycle / agent communication | 低 | --help |  |
| 152 | `scripts/knowledge_metrics.sh` | B | 45 | 6 | knowledge maintenance | 低 | --help |  |
| 153 | `scripts/lesson_confirm.sh` | B | 55 | 6 | knowledge maintenance | 低 | --help |  |
| 154 | `scripts/lesson_edit.sh` | B | 61 | 6 | knowledge maintenance | 低 | --help |  |
| 155 | `scripts/mcp_sync_lesson.sh` | B | 43 | 6 | manual/maintenance | 低 | --help |  |
| 156 | `scripts/lib/layout_string.sh` | B | 37 | 3 | manual/maintenance | 低 | --help |  |
| 157 | `scripts/api_usage.sh` | B | 28 | 5 | manual/maintenance | 低 | --help |  |
| 158 | `scripts/backfill_knowledge_debt.sh` | B | 27 | 5 | knowledge maintenance | 低 | --help |  |
| 159 | `scripts/cdp_chrome_cleanup.sh` | B | 47 | 5 | manual/maintenance | 低 | no-args |  |
| 160 | `scripts/checklist_progress.sh` | B | 30 | 5 | manual/maintenance | 低 | --help |  |
| 161 | `scripts/cmd_friction_log.sh` | B | 36 | 5 | manual/maintenance | 低 | --help |  |
| 162 | `scripts/cmd_halt.sh` | B | 27 | 5 | manual/maintenance | 低 | --help |  |
| 163 | `scripts/insight_resolve.sh` | B | 44 | 5 | manual/maintenance | 低 | --help |  |
| 164 | `scripts/lesson_delete.sh` | B | 49 | 5 | knowledge maintenance | 低 | --help |  |
| 165 | `scripts/record_lesson_feedback.sh` | B | 29 | 5 | knowledge maintenance | 低 | --help |  |
| 166 | `scripts/usage_monitor.sh` | B |  | 5 | daemon/watcher loop | 低 | skip | daemon/long-running |
| 167 | `scripts/usage_status.sh` | B | 65 | 5 | manual/maintenance | 低 | no-args |  |
| 168 | `scripts/gunshi_gate_sync.sh` | B | 332 | 4 | manual/maintenance | 低 | no-args |  |
| 169 | `scripts/lesson_auto_tag.sh` | B | 1139 | 2 | knowledge maintenance | 中 | --help |  |
| 170 | `scripts/lesson_health_report.sh` | B | 1141 | 2 | knowledge maintenance | 中 | --help |  |
| 171 | `scripts/oneshot/add_injection_count.sh` | B | 1167 | 2 | manual/maintenance | 中 | --help |  |
| 172 | `scripts/backfill_review_gate_done.sh` | C | 4014 | 2 | manual/maintenance | 高 | --help | timeout |
| 173 | `scripts/lib/firefighting_keywords.sh` | B | 25 | 2 | manual/maintenance | 低 | no-args |  |
| 174 | `scripts/lib/gunshi_notify.sh` | B | 30 | 2 | manual/maintenance | 低 | no-args |  |
| 175 | `scripts/agent_status.sh` | B | 192 | 4 | manual/maintenance | 低 | --help |  |
| 176 | `scripts/lesson_impact_rotate.sh` | B | 194 | 4 | knowledge maintenance | 低 | --help |  |
| 177 | `scripts/dashboard_update.sh` | B | 48 | 4 | manual/maintenance | 低 | --help |  |
| 178 | `scripts/gist_sync.sh` | B |  | 4 | daemon/watcher loop | 低 | skip | daemon/long-running |
| 179 | `scripts/health_check.sh` | B |  | 4 | daemon/watcher loop | 低 | skip | daemon/long-running |
| 180 | `scripts/inbox_prune.sh` | B | 36 | 4 | task lifecycle / agent communication | 低 | --help |  |
| 181 | `scripts/lesson_find_duplicates.sh` | B | 45 | 4 | knowledge maintenance | 低 | --help |  |
| 182 | `scripts/rotate_gate_metrics.sh` | B | 17 | 4 | manual/maintenance | 低 | --help |  |
| 183 | `scripts/switch_project.sh` | B | 65 | 4 | manual/maintenance | 低 | --help |  |
| 184 | `scripts/gunshi_next_action.sh` | C | 4016 | 1 | manual/maintenance | 高 | no-args | timeout |
| 185 | `scripts/lib/mcas_common.sh` | B | 24 | 1 | manual/maintenance | 低 | --help |  |
| 186 | `scripts/lib/safe_rm.sh` | B | 29 | 1 | manual/maintenance | 低 | no-args |  |
| 187 | `scripts/lib/text_utils.sh` | B | 22 | 1 | manual/maintenance | 低 | no-args |  |
| 188 | `scripts/bulletin_close.sh` | B | 114 | 3 | manual/maintenance | 低 | --help |  |
| 189 | `scripts/chronicle_metrics.sh` | B | 143 | 3 | manual/maintenance | 低 | no-args |  |
| 190 | `scripts/lesson_impact_analysis.sh` | B | 163 | 3 | knowledge maintenance | 低 | --help |  |
| 191 | `scripts/backfill_task_type.sh` | B | 38 | 3 | task lifecycle / agent communication | 低 | --help |  |
| 192 | `scripts/bulletin_confirm.sh` | B | 25 | 3 | manual/maintenance | 低 | --help |  |
| 193 | `scripts/lesson_status_migration.sh` | B | 40 | 3 | knowledge maintenance | 低 | --help |  |
| 194 | `scripts/process_stop.sh` | B | 57 | 3 | manual/maintenance | 低 | --help |  |
| 195 | `scripts/restart_ntfy_listener.sh` | C | 3002 | 3 | task lifecycle / agent communication | 高 | no-args | timeout |
| 196 | `scripts/should_dream.sh` | B | 16 | 3 | manual/maintenance | 低 | no-args |  |
| 197 | `scripts/token_refresh.sh` | B | 12 | 3 | manual/maintenance | 低 | --help |  |
| 198 | `scripts/yaml_check_codex.sh` | B | 8 | 3 | manual/maintenance | 低 | --help |  |
| 199 | `scripts/yaml_log_rotate.sh` | B | 8 | 3 | manual/maintenance | 低 | --help |  |
| 200 | `scripts/log_rotate.sh` | B | 349 | 2 | manual/maintenance | 低 | --help |  |
| 201 | `scripts/gist_index_update.sh` | C | 4023 | 0 | manual/maintenance | 高 | no-args | timeout |
| 202 | `scripts/gunshi_review_stats.sh` | B | 685 | 1 | manual/maintenance | 低 | no-args |  |
| 203 | `scripts/restart_all_daemons.sh` | C | 3179 | 2 | manual/maintenance | 高 | --help |  |
| 204 | `scripts/restart_monitor.sh` | C | 3138 | 2 | manual/maintenance | 高 | no-args |  |
| 205 | `scripts/count_gate_metrics.sh` | B | 63 | 2 | manual/maintenance | 低 | --help |  |
| 206 | `scripts/gunshi_log_append.sh` | B | 75 | 2 | manual/maintenance | 低 | --help |  |
| 207 | `scripts/note_draft.sh` | B | 21 | 2 | manual/maintenance | 低 | --help |  |
| 208 | `scripts/oneshot/reset_harmful_counts.sh` | B | 472 | 1 | manual/maintenance | 低 | no-args |  |
| 209 | `scripts/rework_rate.sh` | B | 17 | 2 | manual/maintenance | 低 | --help |  |
| 210 | `scripts/yaml_check_opus.sh` | B | 8 | 2 | manual/maintenance | 低 | --help |  |
| 211 | `scripts/ntfy_batch_flush.sh` | B | 247 | 1 | task lifecycle / agent communication | 低 | no-args |  |
| 212 | `scripts/clipboard_watcher.sh` | B |  | 1 | daemon/watcher loop | 低 | skip | daemon/long-running |
| 213 | `scripts/usage_compare.sh` | C | 3002 | 1 | manual/maintenance | 高 | no-args | timeout |
| 214 | `scripts/usage_statusbar_loop.sh` | B |  | 1 | daemon/watcher loop | 低 | skip | daemon/long-running |
| 215 | `scripts/workaround_pattern_resolve.sh` | B | 16 | 1 | manual/maintenance | 低 | --help |  |
| 216 | `scripts/run_precommit_checks.sh` | B | 165 | 0 | manual/maintenance | 低 | no-args |  |
| 済 | `scripts/cmd_complete_gate.sh` | A | 44 | 88 | manual/maintenance | 済 | --help | test integration done (2026-04-15) |
| 済 | `scripts/deploy_task.sh` | A | 159 | 175 | task lifecycle / agent communication | 済 | --help | 2639ms→88ms (2026-04-15) |
| 済 | `scripts/gates/gate_gunshi_startup.sh` | A | 2093 | 6 | gate/startup/report validation | 済 | --help | 14.9s→3.2s (2026-04-14) |
| 済 | `scripts/gates/gate_shogun_startup.sh` | A | 4039 | 19 | gate/startup/report validation | 済 | --help | 14.9s→3.2s (2026-04-14) |
