# cmd_karo_reprofile_freq_20260426 インフラスクリプト頻度再計測

- 作成: hayate / 2026-04-26T21:40:12+09:00
- 対象期間: 2026-04-25T21:40:12+09:00 以降の直近24h
- 対象: `scripts/**/*.sh` + `.claude/hooks/*.sh` = **235本**
- 前回計測: `docs/research/codd_infra_script_profiling.md` §3 / cmd_1951 (2026-04-16、対象220本)

## 計測ソース

| source | 集計結果 | 対応列 | 備考 |
|---|---:|---|---|
| `logs/gate_fire_log.yaml` | 225 events | gate発火 | `gate:<name>` を `scripts/gates/<name>.sh` に対応付け |
| `logs/karo_workarounds.yaml` | 57 entries | 合計推定 | 報告処理回数近似として `scripts/karo_workaround_log.sh` に加算 |
| `archive/inbox/karo_*.yaml` + `queue/inbox/*.yaml` | 326 unique messages | inbox経由 | 1 message ≒ `scripts/inbox_write.sh` 1回 |
| `git log --since=24 hours ago -- scripts .claude/hooks` | 49 file-touch events / 40 commits | 変更証跡 | 呼出し頻度ではないため差分欄の補助情報 |
| `.claude/settings.json` hooks | 14 hook definitions | hook発火推定 | 実発火回数ではなく、1イベントあたりの静的発火候補数 |

## 前回Top20差分

| rank | スクリプト | 前回呼出し証跡 | 今回合計推定 | 差分 | コメント |
|---:|---|---:|---:|---:|---|
| 1 | `scripts/inbox_write.sh` | 312 | 326 | +14 | inbox実績が主 |
| 2 | `scripts/ninja_done.sh` | 104 | 0 | -104 | 直近24h実績なし |
| 3 | `scripts/inbox_watcher.sh` | 91 | 0 | -91 | 直近24h実績なし |
| 4 | `scripts/cmd_save.sh` | 86 | 0 | -86 | 直近24h実績なし |
| 5 | `scripts/report_field_set.sh` | 73 | 0 | -73 | 直近24h実績なし |
| 6 | `scripts/ntfy.sh` | 60 | 0 | -60 | 直近24h実績なし |
| 7 | `scripts/lesson_write.sh` | 52 | 0 | -52 | 直近24h実績なし |
| 8 | `scripts/gates/gate_report_format.sh` | 48 | 122 | +74 | gate_fire_log実績あり |
| 9 | `scripts/lib/yaml_field_set.sh` | 41 | 0 | -41 | 直近24h実績なし |
| 10 | `scripts/shutsujin_departure.sh` | 38 | 0 | -38 | 直近24h実績なし |
| 11 | `scripts/ninja_monitor.sh` | 35 | 0 | -35 | 直近24h実績なし |
| 12 | `scripts/archive_completed.sh` | 31 | 0 | -31 | 直近24h実績なし |
| 13 | `scripts/lib/cli_lookup.sh` | 30 | 0 | -30 | 直近24h実績なし |
| 14 | `scripts/lib/agent_config.sh` | 29 | 0 | -29 | 直近24h実績なし |
| 15 | `scripts/lib/field_get.sh` | 29 | 0 | -29 | 直近24h実績なし |
| 16 | `scripts/cmd_delegate.sh` | 28 | 0 | -28 | 直近24h実績なし |
| 17 | `scripts/inbox_mark_read.sh` | 28 | 0 | -28 | 直近24h実績なし |
| 18 | `scripts/cdp/cdp_cli.sh` | 27 | 0 | -27 | 直近24h実績なし |
| 19 | `scripts/ntfy_listener.sh` | 27 | 0 | -27 | 直近24h実績なし |
| 20 | `scripts/pending_decision_write.sh` | 25 | 0 | -25 | 直近24h実績なし |

## 全スクリプト頻度テーブル

| スクリプト | gate発火 | inbox経由 | hook発火推定 | 合計推定 | 前回cmd_1951 | 差分 | 変更commit |
|---|---:|---:|---:|---:|---:|---:|---:|
| `scripts/inbox_write.sh` | 0 | 326 | 0 | 326 | 312 | +14 | 3 |
| `scripts/gates/gate_report_format.sh` | 122 | 0 | 0 | 122 | 48 | +74 | 0 |
| `scripts/gates/gate_report_autofix.sh` | 103 | 0 | 0 | 103 | 11 | +92 | 0 |
| `scripts/karo_workaround_log.sh` | 0 | 0 | 0 | 57 | 20 | +37 | 0 |
| `.claude/hooks/post-bash-combined.sh` | 0 | 0 | 1 | 1 | 1 | +0 | 1 |
| `.claude/hooks/post-search-completeness-guard.sh` | 0 | 0 | 1 | 1 | 1 | +0 | 0 |
| `.claude/hooks/post-shogun-inbox-check.sh` | 0 | 0 | 1 | 1 | 2 | -1 | 1 |
| `.claude/hooks/post-write-edit-combined.sh` | 0 | 0 | 1 | 1 | 1 | +0 | 0 |
| `.claude/hooks/pre-bash-combined.sh` | 0 | 0 | 1 | 1 | 4 | -3 | 0 |
| `.claude/hooks/pre-edit-pi-inject.sh` | 0 | 0 | 1 | 1 | 0 | +1 | 1 |
| `.claude/hooks/pre-write-edit-combined.sh` | 0 | 0 | 1 | 1 | 1 | +0 | 1 |
| `.claude/hooks/pre-write-read-tracker.sh` | 0 | 0 | 1 | 1 | 1 | +0 | 0 |
| `.claude/hooks/stop-lint-gate.sh` | 0 | 0 | 1 | 1 | 1 | +0 | 0 |
| `scripts/hooks/prompt_state_inject.sh` | 0 | 0 | 1 | 1 | 2 | -1 | 2 |
| `scripts/hooks/session_end_clear_check.sh` | 0 | 0 | 1 | 1 | 1 | +0 | 0 |
| `scripts/hooks/stop_check_inbox.sh` | 0 | 0 | 1 | 1 | 1 | +0 | 0 |
| `scripts/log_terminal_input.sh` | 0 | 0 | 1 | 1 | 3 | -2 | 0 |
| `scripts/log_terminal_response.sh` | 0 | 0 | 1 | 1 | 4 | -3 | 0 |
| `.claude/hooks/post-bash-commit-reminder.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `.claude/hooks/post-edit-instruction-hook-consistency.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `.claude/hooks/post-edit-report-guard.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `.claude/hooks/post-write-shellcheck.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `.claude/hooks/pre-bash-no-verify-guard.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `.claude/hooks/pre-bash-yaml-dump-guard.sh` | 0 | 0 | 0 | 0 | 1 | -1 | 0 |
| `.claude/hooks/pre-edit-report-deny.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `.claude/hooks/pre-edit-workaround-deny.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `.claude/hooks/pre-write-config-guard.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `scripts/ac_physical_verify.sh` | 0 | 0 | 0 | 0 | 13 | -13 | 0 |
| `scripts/affected_tests.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/agent_status.sh` | 0 | 0 | 0 | 0 | 4 | -4 | 0 |
| `scripts/api_usage.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/archive_completed.sh` | 0 | 0 | 0 | 0 | 31 | -31 | 3 |
| `scripts/auto_deploy_next.sh` | 0 | 0 | 0 | 0 | 9 | -9 | 0 |
| `scripts/auto_draft_lesson.sh` | 0 | 0 | 0 | 0 | 23 | -23 | 0 |
| `scripts/auto_failure_lesson.sh` | 0 | 0 | 0 | 0 | 10 | -10 | 0 |
| `scripts/backfill_knowledge_debt.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/backfill_lesson_target_files.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `scripts/backfill_review_gate_done.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/backfill_task_type.sh` | 0 | 0 | 0 | 0 | 3 | -3 | 0 |
| `scripts/build_instructions.sh` | 0 | 0 | 0 | 0 | 8 | -8 | 0 |
| `scripts/bulletin_archive.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `scripts/bulletin_close.sh` | 0 | 0 | 0 | 0 | 3 | -3 | 0 |
| `scripts/bulletin_confirm.sh` | 0 | 0 | 0 | 0 | 3 | -3 | 0 |
| `scripts/bulletin_write.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/capture_clipboard_image.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/cdp/cdp_benchmark.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `scripts/cdp/cdp_cli.sh` | 0 | 0 | 0 | 0 | 27 | -27 | 0 |
| `scripts/cdp/cdp_measure.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 10 |
| `scripts/cdp_canary.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 1 |
| `scripts/cdp_chrome_cleanup.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/checklist_progress.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/checklist_update.sh` | 0 | 0 | 0 | 0 | 9 | -9 | 0 |
| `scripts/chronicle_metrics.sh` | 0 | 0 | 0 | 0 | 3 | -3 | 0 |
| `scripts/ci_status_check.sh` | 0 | 0 | 0 | 0 | 8 | -8 | 0 |
| `scripts/clear_prep_check.sh` | 0 | 0 | 0 | 0 | 6 | -6 | 0 |
| `scripts/clipboard_watcher.sh` | 0 | 0 | 0 | 0 | 1 | -1 | 0 |
| `scripts/cmd_absorb.sh` | 0 | 0 | 0 | 0 | 13 | -13 | 0 |
| `scripts/cmd_complete_gate.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 1 |
| `scripts/cmd_delegate.sh` | 0 | 0 | 0 | 0 | 28 | -28 | 0 |
| `scripts/cmd_friction_log.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/cmd_halt.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/cmd_quality_log.sh` | 0 | 0 | 0 | 0 | 17 | -17 | 0 |
| `scripts/cmd_save.sh` | 0 | 0 | 0 | 0 | 86 | -86 | 6 |
| `scripts/context_freshness_check.sh` | 0 | 0 | 0 | 0 | 14 | -14 | 0 |
| `scripts/conversation_retention.sh` | 0 | 0 | 0 | 0 | 6 | -6 | 0 |
| `scripts/count_gate_metrics.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/daemon_watchdog.sh` | 0 | 0 | 0 | 0 | 6 | -6 | 0 |
| `scripts/dashboard_auto_section.sh` | 0 | 0 | 0 | 0 | 21 | -21 | 1 |
| `scripts/dashboard_update.sh` | 0 | 0 | 0 | 0 | 4 | -4 | 0 |
| `scripts/decision_write.sh` | 0 | 0 | 0 | 0 | 6 | -6 | 0 |
| `scripts/deploy_task.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 3 |
| `scripts/deploy_training.sh` | 0 | 0 | 0 | 0 | 6 | -6 | 0 |
| `scripts/enable_pane_trace.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `scripts/fullrecalculate.sh` | 0 | 0 | 0 | 0 | 9 | -9 | 0 |
| `scripts/gate_auto_respond.sh` | 0 | 0 | 0 | 0 | 8 | -8 | 0 |
| `scripts/gate_improvement_trigger.sh` | 0 | 0 | 0 | 0 | 11 | -11 | 0 |
| `scripts/gates/gate_artifact_map.sh` | 0 | 0 | 0 | 0 | 8 | -8 | 0 |
| `scripts/gates/gate_autofix_proposal.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `scripts/gates/gate_cmd_state.sh` | 0 | 0 | 0 | 0 | 4 | -4 | 0 |
| `scripts/gates/gate_codd_regression.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `scripts/gates/gate_codex_safe_write.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `scripts/gates/gate_context_freshness.sh` | 0 | 0 | 0 | 0 | 4 | -4 | 0 |
| `scripts/gates/gate_cycle_health.sh` | 0 | 0 | 0 | 0 | 11 | -11 | 0 |
| `scripts/gates/gate_dc_duplicate.sh` | 0 | 0 | 0 | 0 | 6 | -6 | 0 |
| `scripts/gates/gate_diagnose_check.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/gates/gate_enforcement_audit.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/gates/gate_field_get.sh` | 0 | 0 | 0 | 0 | 3 | -3 | 0 |
| `scripts/gates/gate_gunshi_cs_checklist.sh` | 0 | 0 | 0 | 0 | 6 | -6 | 0 |
| `scripts/gates/gate_gunshi_observations.sh` | 0 | 0 | 0 | 0 | 4 | -4 | 0 |
| `scripts/gates/gate_gunshi_report_precheck.sh` | 0 | 0 | 0 | 0 | 4 | -4 | 1 |
| `scripts/gates/gate_gunshi_startup.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 1 |
| `scripts/gates/gate_karo_startup.sh` | 0 | 0 | 0 | 0 | 12 | -12 | 0 |
| `scripts/gates/gate_knowledge_freshness.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `scripts/gates/gate_lesson_health.sh` | 0 | 0 | 0 | 0 | 16 | -16 | 0 |
| `scripts/gates/gate_loop_health.sh` | 0 | 0 | 0 | 0 | 14 | -14 | 0 |
| `scripts/gates/gate_mcp_access.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `scripts/gates/gate_ninja_workaround_rate.sh` | 0 | 0 | 0 | 0 | 11 | -11 | 0 |
| `scripts/gates/gate_p_average_freshness.sh` | 0 | 0 | 0 | 0 | 4 | -4 | 0 |
| `scripts/gates/gate_pd_sync.sh` | 0 | 0 | 0 | 0 | 4 | -4 | 0 |
| `scripts/gates/gate_recalculate_completeness.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/gates/gate_shogun_memory.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/gates/gate_shogun_startup.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 1 |
| `scripts/gates/gate_silent_fallback.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/gates/gate_skill_health.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 1 |
| `scripts/gates/gate_skill_quality.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/gates/gate_vercel_phase.sh` | 0 | 0 | 0 | 0 | 7 | -7 | 0 |
| `scripts/gates/gate_wa_data_quality.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/gates/gate_workaround_rate.sh` | 0 | 0 | 0 | 0 | 14 | -14 | 0 |
| `scripts/gates/gate_yaml_status.sh` | 0 | 0 | 0 | 0 | 7 | -7 | 0 |
| `scripts/gates/mark_no_learning.sh` | 0 | 0 | 0 | 0 | 3 | -3 | 0 |
| `scripts/gist_index_update.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `scripts/gist_sync.sh` | 0 | 0 | 0 | 0 | 4 | -4 | 0 |
| `scripts/gunshi_gate_reflux.sh` | 0 | 0 | 0 | 0 | 7 | -7 | 0 |
| `scripts/gunshi_gate_sync.sh` | 0 | 0 | 0 | 0 | 4 | -4 | 0 |
| `scripts/gunshi_log_append.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/gunshi_next_action.sh` | 0 | 0 | 0 | 0 | 1 | -1 | 0 |
| `scripts/gunshi_review_stats.sh` | 0 | 0 | 0 | 0 | 1 | -1 | 0 |
| `scripts/health_check.sh` | 0 | 0 | 0 | 0 | 4 | -4 | 0 |
| `scripts/hooks/bash_state_hook.sh` | 0 | 0 | 0 | 0 | 3 | -3 | 0 |
| `scripts/hooks/block_destructive.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `scripts/hooks/git-pre-commit.sh` | 0 | 0 | 0 | 0 | 1 | -1 | 0 |
| `scripts/hooks/pre-bash-report-deny.sh` | 0 | 0 | 0 | 0 | 1 | -1 | 0 |
| `scripts/hooks/pre-bash-test-fullrun-guard.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `scripts/hooks/pre-karo-edit-guard.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `scripts/hooks/pre-mcp-lord-attribution-guard.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `scripts/hooks/pre-write-report-deny.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/hooks/pre_compact_save.sh` | 0 | 0 | 0 | 0 | 1 | -1 | 0 |
| `scripts/hooks/session_start_inject.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/hooks/test_hooks.sh` | 0 | 0 | 0 | 0 | 1 | -1 | 0 |
| `scripts/hooks/test_result_guard.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/hybrid_search.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 1 |
| `scripts/inbox_archive.sh` | 0 | 0 | 0 | 0 | 9 | -9 | 0 |
| `scripts/inbox_mark_read.sh` | 0 | 0 | 0 | 0 | 28 | -28 | 0 |
| `scripts/inbox_prune.sh` | 0 | 0 | 0 | 0 | 4 | -4 | 0 |
| `scripts/inbox_watcher.sh` | 0 | 0 | 0 | 0 | 91 | -91 | 1 |
| `scripts/insight_resolve.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/insight_write.sh` | 0 | 0 | 0 | 0 | 16 | -16 | 0 |
| `scripts/knowledge_metrics.sh` | 0 | 0 | 0 | 0 | 6 | -6 | 1 |
| `scripts/lesson_auto_tag.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/lesson_check.sh` | 0 | 0 | 0 | 0 | 7 | -7 | 0 |
| `scripts/lesson_confirm.sh` | 0 | 0 | 0 | 0 | 6 | -6 | 0 |
| `scripts/lesson_delete.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/lesson_deprecate.sh` | 0 | 0 | 0 | 0 | 13 | -13 | 0 |
| `scripts/lesson_deprecation_scan.sh` | 0 | 0 | 0 | 0 | 13 | -13 | 0 |
| `scripts/lesson_edit.sh` | 0 | 0 | 0 | 0 | 6 | -6 | 0 |
| `scripts/lesson_effectiveness.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/lesson_find_duplicates.sh` | 0 | 0 | 0 | 0 | 4 | -4 | 0 |
| `scripts/lesson_harvest.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/lesson_health_report.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/lesson_impact_analysis.sh` | 0 | 0 | 0 | 0 | 3 | -3 | 0 |
| `scripts/lesson_impact_rotate.sh` | 0 | 0 | 0 | 0 | 4 | -4 | 0 |
| `scripts/lesson_merge.sh` | 0 | 0 | 0 | 0 | 9 | -9 | 0 |
| `scripts/lesson_review.sh` | 0 | 0 | 0 | 0 | 12 | -12 | 0 |
| `scripts/lesson_status_migration.sh` | 0 | 0 | 0 | 0 | 3 | -3 | 0 |
| `scripts/lesson_update_score.sh` | 0 | 0 | 0 | 0 | 13 | -13 | 0 |
| `scripts/lesson_write.sh` | 0 | 0 | 0 | 0 | 52 | -52 | 0 |
| `scripts/lesson_write_karo.sh` | 0 | 0 | 0 | 0 | 16 | -16 | 0 |
| `scripts/lesson_write_shogun.sh` | 0 | 0 | 0 | 0 | 8 | -8 | 0 |
| `scripts/lib/agent_config.sh` | 0 | 0 | 0 | 0 | 29 | -29 | 0 |
| `scripts/lib/cli_lookup.sh` | 0 | 0 | 0 | 0 | 30 | -30 | 1 |
| `scripts/lib/ctx_utils.sh` | 0 | 0 | 0 | 0 | 4 | -4 | 0 |
| `scripts/lib/field_get.sh` | 0 | 0 | 0 | 0 | 29 | -29 | 0 |
| `scripts/lib/firefighting_keywords.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/lib/gunshi_notify.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/lib/layout_string.sh` | 0 | 0 | 0 | 0 | 3 | -3 | 0 |
| `scripts/lib/lock_path.sh` | 0 | 0 | 0 | 0 | 13 | -13 | 0 |
| `scripts/lib/mcas_common.sh` | 0 | 0 | 0 | 0 | 1 | -1 | 0 |
| `scripts/lib/model_colors.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 1 |
| `scripts/lib/model_detect.sh` | 0 | 0 | 0 | 0 | 12 | -12 | 1 |
| `scripts/lib/model_resolve.sh` | 0 | 0 | 0 | 0 | 9 | -9 | 0 |
| `scripts/lib/normalize_report.sh` | 0 | 0 | 0 | 0 | 9 | -9 | 0 |
| `scripts/lib/pane_format.sh` | 0 | 0 | 0 | 0 | 7 | -7 | 0 |
| `scripts/lib/pane_lookup.sh` | 0 | 0 | 0 | 0 | 7 | -7 | 0 |
| `scripts/lib/pre_bash_combined_guard.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `scripts/lib/safe_rm.sh` | 0 | 0 | 0 | 0 | 1 | -1 | 0 |
| `scripts/lib/script_update.sh` | 0 | 0 | 0 | 0 | 4 | -4 | 0 |
| `scripts/lib/text_utils.sh` | 0 | 0 | 0 | 0 | 1 | -1 | 0 |
| `scripts/lib/tmux_utils.sh` | 0 | 0 | 0 | 0 | 8 | -8 | 0 |
| `scripts/lib/yaml_field_set.sh` | 0 | 0 | 0 | 0 | 41 | -41 | 0 |
| `scripts/log_rotate.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/mcp_sync_lesson.sh` | 0 | 0 | 0 | 0 | 6 | -6 | 0 |
| `scripts/model_analysis.sh` | 0 | 0 | 0 | 0 | 13 | -13 | 1 |
| `scripts/model_switch_preflight.sh` | 0 | 0 | 0 | 0 | 7 | -7 | 0 |
| `scripts/ninja_done.sh` | 0 | 0 | 0 | 0 | 104 | -104 | 0 |
| `scripts/ninja_monitor.sh` | 0 | 0 | 0 | 0 | 35 | -35 | 3 |
| `scripts/note_draft.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/ntfy.sh` | 0 | 0 | 0 | 0 | 60 | -60 | 0 |
| `scripts/ntfy_batch.sh` | 0 | 0 | 0 | 0 | 6 | -6 | 0 |
| `scripts/ntfy_batch_flush.sh` | 0 | 0 | 0 | 0 | 1 | -1 | 0 |
| `scripts/ntfy_cmd.sh` | 0 | 0 | 0 | 0 | 9 | -9 | 0 |
| `scripts/ntfy_inbox_archive.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/ntfy_listener.sh` | 0 | 0 | 0 | 0 | 27 | -27 | 0 |
| `scripts/oneshot/add_injection_count.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/oneshot/backfill_gate_titles.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/oneshot/reset_harmful_counts.sh` | 0 | 0 | 0 | 0 | 1 | -1 | 0 |
| `scripts/parity_check.sh` | 0 | 0 | 0 | 0 | 6 | -6 | 0 |
| `scripts/pending_decision_write.sh` | 0 | 0 | 0 | 0 | 25 | -25 | 0 |
| `scripts/post_recalculate_checks.sh` | 0 | 0 | 0 | 0 | 3 | -3 | 0 |
| `scripts/process_stop.sh` | 0 | 0 | 0 | 0 | 3 | -3 | 0 |
| `scripts/ralph_loop_closer.sh` | 0 | 0 | 0 | 0 | 7 | -7 | 0 |
| `scripts/ralph_loop_metrics.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/record_lesson_feedback.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/report_field_set.sh` | 0 | 0 | 0 | 0 | 73 | -73 | 1 |
| `scripts/report_merge.sh` | 0 | 0 | 0 | 0 | 19 | -19 | 0 |
| `scripts/reset_layout.sh` | 0 | 0 | 0 | 0 | 13 | -13 | 0 |
| `scripts/restart_all_daemons.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/restart_monitor.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/restart_ntfy_listener.sh` | 0 | 0 | 0 | 0 | 3 | -3 | 0 |
| `scripts/restart_watchers.sh` | 0 | 0 | 0 | 0 | 12 | -12 | 0 |
| `scripts/review_gate.sh` | 0 | 0 | 0 | 0 | 11 | -11 | 0 |
| `scripts/rework_rate.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/rotate_gate_metrics.sh` | 0 | 0 | 0 | 0 | 4 | -4 | 0 |
| `scripts/run_precommit_checks.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `scripts/run_tests.sh` | 0 | 0 | 0 | 0 | 9 | -9 | 0 |
| `scripts/should_dream.sh` | 0 | 0 | 0 | 0 | 3 | -3 | 0 |
| `scripts/shout.sh` | 0 | 0 | 0 | 0 | 13 | -13 | 0 |
| `scripts/shutsujin_departure.sh` | 0 | 0 | 0 | 0 | 38 | -38 | 0 |
| `scripts/statusline.sh` | 0 | 0 | 0 | 0 | 3 | -3 | 0 |
| `scripts/switch_cli_mode.sh` | 0 | 0 | 0 | 0 | 10 | -10 | 0 |
| `scripts/switch_project.sh` | 0 | 0 | 0 | 0 | 4 | -4 | 0 |
| `scripts/sync_lessons.sh` | 0 | 0 | 0 | 0 | 17 | -17 | 0 |
| `scripts/sync_pane_vars.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/task_deploy.sh` | 0 | 0 | 0 | 0 | 19 | -19 | 0 |
| `scripts/task_queue_status.sh` | 0 | 0 | 0 | 0 | 3 | -3 | 0 |
| `scripts/test_select.sh` | 0 | 0 | 0 | 0 | 0 | +0 | 0 |
| `scripts/token_refresh.sh` | 0 | 0 | 0 | 0 | 3 | -3 | 0 |
| `scripts/usage_compare.sh` | 0 | 0 | 0 | 0 | 1 | -1 | 0 |
| `scripts/usage_monitor.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/usage_status.sh` | 0 | 0 | 0 | 0 | 5 | -5 | 0 |
| `scripts/usage_statusbar_loop.sh` | 0 | 0 | 0 | 0 | 1 | -1 | 0 |
| `scripts/workaround_pattern_check.sh` | 0 | 0 | 0 | 0 | 9 | -9 | 0 |
| `scripts/workaround_pattern_resolve.sh` | 0 | 0 | 0 | 0 | 1 | -1 | 0 |
| `scripts/yaml_check_codex.sh` | 0 | 0 | 0 | 0 | 3 | -3 | 0 |
| `scripts/yaml_check_opus.sh` | 0 | 0 | 0 | 0 | 2 | -2 | 0 |
| `scripts/yaml_log_rotate.sh` | 0 | 0 | 0 | 0 | 3 | -3 | 0 |

## 差分所見

- 対象本数は **220→235本** に増加。前回後にCDP/PI/hook/growth系スクリプトが追加された。
- 直近24hの実測系トップは `scripts/inbox_write.sh` (326)、gate系トップは `scripts/gates/gate_report_format.sh` (122) と `scripts/gates/gate_report_autofix.sh` (103)。
- 前回cmd_1951の「呼出し証跡」は全量静的/履歴ベース、今回の「合計推定」は直近24hログベースのため、差分は期間差と計測定義差を含む。
- `.claude/settings.json` 由来のhook発火推定は実回数ではなく、ツールイベント1回あたりの発火候補数。実発火量はClaude hook logsがあれば別途掛け合わせが必要。
