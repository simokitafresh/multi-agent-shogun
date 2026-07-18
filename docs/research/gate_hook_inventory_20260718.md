# Gate / Hook / cmd_save 防御機構 全数棚卸し（2026-07-18）

- 対象: 現物 `scripts/gates` 62本、`scripts/hooks` + `.claude/hooks` 45本、cmd_save catalog 82項目、合計189項目。
- 指示時の期待値63/50/82に対し現物は62/45/82。hookはtracked列挙44本に加えて現物symlink 1本を含む。差分は削除済み・非tracked・数え方のドリフト候補であり、件数を水増しせず穴として記録する。
- 発火数: `logs/gate_fire_log.yaml` の全期間line-oriented集計。BLOCK/WARNは同一行のresultで集計。wallは同ログに未収録のため、blocked secondsは直近一次実測がある項目のみ算出し、他はN/A。
- FP: `logs/detector_fp_rate.yaml` に共通item identityがない項目は推測せず「未確定」。v2.1分類は途中tool-call儀式を緩和、最終checkpointを維持する規則で機械的初期分類した偵察結論。

## 全数台帳

|#|種別|項目|trigger|fire|BLOCK|WARN|FP根拠|v2.1分類|
|---:|---|---|---|---:|---:|---:|---|---|
|1|gate|`scripts/gates/gate_artifact_map.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|2|gate|`scripts/gates/gate_autofix_proposal.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|3|gate|`scripts/gates/gate_cmd_state.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|4|gate|`scripts/gates/gate_codd_regression.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|5|gate|`scripts/gates/gate_codex_hooks_no_stop.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|6|gate|`scripts/gates/gate_codex_safe_write.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|7|gate|`scripts/gates/gate_context_freshness.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|8|gate|`scripts/gates/gate_cycle_health.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|9|gate|`scripts/gates/gate_daemon.py`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|10|gate|`scripts/gates/gate_dc_duplicate.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|11|gate|`scripts/gates/gate_design_cmd_handoff.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|12|gate|`scripts/gates/gate_diagnose_check.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|13|gate|`scripts/gates/gate_enforcement_audit.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|14|gate|`scripts/gates/gate_field_get.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|15|gate|`scripts/gates/gate_fp_relaxation_proposal.py`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|16|gate|`scripts/gates/gate_gunshi_accuracy.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|17|gate|`scripts/gates/gate_gunshi_cs_checklist.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|18|gate|`scripts/gates/gate_gunshi_observations.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|19|gate|`scripts/gates/gate_gunshi_report_precheck.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|20|gate|`scripts/gates/gate_gunshi_report_precheck_engine.py`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|21|gate|`scripts/gates/gate_gunshi_startup.sh`|起動時|0|0|0|発火ログ0件; FP未判定|緩和|
|22|gate|`scripts/gates/gate_hooks_no_runtime_incident_ids.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|23|gate|`scripts/gates/gate_hot_path_no_sync_io.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|24|gate|`scripts/gates/gate_immunity_depth.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|25|gate|`scripts/gates/gate_karo_startup.sh`|起動時|0|0|0|発火ログ0件; FP未判定|緩和|
|26|gate|`scripts/gates/gate_knowledge_freshness.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|27|gate|`scripts/gates/gate_lesson_enforcement_level.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|28|gate|`scripts/gates/gate_lesson_health.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|29|gate|`scripts/gates/gate_loop_health.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|30|gate|`scripts/gates/gate_mcp_access.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|31|gate|`scripts/gates/gate_memory_db_live_insert_async.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|32|gate|`scripts/gates/gate_ninja_workaround_rate.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|33|gate|`scripts/gates/gate_no_direct_yaml_dump.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|34|gate|`scripts/gates/gate_no_hardcoded_ninja_list.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|35|gate|`scripts/gates/gate_p_average_freshness.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|36|gate|`scripts/gates/gate_pd_sync.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|37|gate|`scripts/gates/gate_queue_yaml_parse.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|38|gate|`scripts/gates/gate_queue_yaml_reader_migration.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|39|gate|`scripts/gates/gate_recalculate_completeness.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|40|gate|`scripts/gates/gate_report_autofix.sh`|gate明示呼出時|469|0|0|PASS/非判定のみ; FPラベルなし|維持|
|41|gate|`scripts/gates/gate_report_autofix_main.py`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|42|gate|`scripts/gates/gate_report_format.sh`|gate明示呼出時|7643|0|0|PASS/非判定のみ; FPラベルなし|維持|
|43|gate|`scripts/gates/gate_report_format_combined.py`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|44|gate|`scripts/gates/gate_report_format_main.py`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|45|gate|`scripts/gates/gate_set_e_short_circuit.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|46|gate|`scripts/gates/gate_shogun_memory.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|47|gate|`scripts/gates/gate_shogun_startup.sh`|起動時|0|0|0|発火ログ0件; FP未判定|緩和|
|48|gate|`scripts/gates/gate_silent_fallback.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|49|gate|`scripts/gates/gate_skill_health.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|50|gate|`scripts/gates/gate_skill_quality.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|51|gate|`scripts/gates/gate_skill_script_refs.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|緩和|
|52|gate|`scripts/gates/gate_test_health.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|53|gate|`scripts/gates/gate_three_layer_health.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|54|gate|`scripts/gates/gate_universal_shard.py`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|55|gate|`scripts/gates/gate_vercel_phase.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|56|gate|`scripts/gates/gate_wa_data_quality.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|57|gate|`scripts/gates/gate_workaround_rate.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|58|gate|`scripts/gates/gate_yaml_field_set_block_sync.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|59|gate|`scripts/gates/gate_yaml_status.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|60|gate|`scripts/gates/lesson_context_routes.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|61|gate|`scripts/gates/mark_no_learning.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|62|gate|`scripts/gates/session_alerts_render.sh`|gate明示呼出時|0|0|0|発火ログ0件; FP未判定|維持|
|63|hook|`.claude/hooks/hook_violation_logger.py`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|64|hook|`.claude/hooks/post-bash-combined.sh`|毎tool call|0|0|0|発火ログ0件; FP未判定|緩和|
|65|hook|`.claude/hooks/post-bash-commit-reminder.sh`|毎tool call|0|0|0|発火ログ0件; FP未判定|緩和|
|66|hook|`.claude/hooks/post-bulletin-notify-read-check.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|67|hook|`.claude/hooks/post-edit-instruction-hook-consistency.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|68|hook|`.claude/hooks/post-edit-report-guard.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|69|hook|`.claude/hooks/post-search-completeness-guard.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|70|hook|`.claude/hooks/post-shogun-inbox-check.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|71|hook|`.claude/hooks/post-skill-execution.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|72|hook|`.claude/hooks/post-write-edit-combined.sh`|毎tool call|0|0|0|発火ログ0件; FP未判定|緩和|
|73|hook|`.claude/hooks/post-write-shellcheck.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|74|hook|`.claude/hooks/posttool-dispatch.sh`|毎tool call|0|0|0|発火ログ0件; FP未判定|緩和|
|75|hook|`.claude/hooks/pre-bash-combined.sh`|毎tool call|0|0|0|発火ログ0件; FP未判定|緩和|
|76|hook|`.claude/hooks/pre-bash-no-verify-guard.sh`|毎tool call|0|0|0|発火ログ0件; FP未判定|緩和|
|77|hook|`.claude/hooks/pre-bash-yaml-dump-guard.sh`|毎tool call|0|0|0|発火ログ0件; FP未判定|緩和|
|78|hook|`.claude/hooks/pre-edit-pi-inject.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|79|hook|`.claude/hooks/pre-edit-report-deny.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|80|hook|`.claude/hooks/pre-edit-workaround-deny.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|81|hook|`.claude/hooks/pre-skill-project-guard.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|82|hook|`.claude/hooks/pre-write-config-guard.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|83|hook|`.claude/hooks/pre-write-edit-combined.sh`|毎tool call|0|0|0|発火ログ0件; FP未判定|緩和|
|84|hook|`.claude/hooks/pre-write-read-tracker.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|85|hook|`.claude/hooks/pretool-dispatch.sh`|毎tool call|0|0|0|発火ログ0件; FP未判定|緩和|
|86|hook|`.claude/hooks/stop-lint-gate.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|87|hook|`scripts/hooks/bash_state_hook.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|88|hook|`scripts/hooks/block_destructive.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|89|hook|`scripts/hooks/codex_session_start.sh`|起動時|0|0|0|発火ログ0件; FP未判定|維持|
|90|hook|`scripts/hooks/codex_user_prompt_submit.sh`|毎prompt|0|0|0|発火ログ0件; FP未判定|維持|
|91|hook|`scripts/hooks/git-pre-commit.sh`|毎commit|0|0|0|発火ログ0件; FP未判定|維持|
|92|hook|`scripts/hooks/git-stage-guard.py`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|93|hook|`scripts/hooks/memory_db_fts5_preflight.py`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|緩和|
|94|hook|`scripts/hooks/pre-bash-report-deny.sh`|毎tool call|0|0|0|発火ログ0件; FP未判定|緩和|
|95|hook|`scripts/hooks/pre-bash-test-fullrun-guard.sh`|毎tool call|0|0|0|発火ログ0件; FP未判定|緩和|
|96|hook|`scripts/hooks/pre-karo-edit-guard.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|97|hook|`scripts/hooks/pre-mcp-lord-attribution-guard.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|98|hook|`scripts/hooks/pre-write-report-deny.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|99|hook|`scripts/hooks/pre_compact_save.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|100|hook|`scripts/hooks/prompt_state_inject.sh`|毎prompt|0|0|0|発火ログ0件; FP未判定|維持|
|101|hook|`scripts/hooks/session_end_clear_check.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|102|hook|`scripts/hooks/session_start_inject.sh`|起動時|0|0|0|発火ログ0件; FP未判定|維持|
|103|hook|`scripts/hooks/stop_check_inbox.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|104|hook|`scripts/hooks/stop_session_alerts.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|105|hook|`scripts/hooks/test_hooks.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|106|hook|`scripts/hooks/test_result_guard.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|維持|
|107|hook|`scripts/hooks/three_layer_preflight.sh`|hook dispatcher条件時|0|0|0|発火ログ0件; FP未判定|緩和|
|108|cmd_save|`scripts/cmd_save.sh` `is_gate_or_hook_addition_cmd`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|109|cmd_save|`scripts/cmd_save.sh` `is_gate_or_script_modification_cmd`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|110|cmd_save|`scripts/cmd_save.sh` `check_gate_script_execution_evidence`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|111|cmd_save|`scripts/cmd_save.sh` `check_gate_hook_action_conversion`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|112|cmd_save|`scripts/cmd_save.sh` `check_lord_30min_cost_question`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|113|cmd_save|`scripts/cmd_save.sh` `check_deferral_language_warn`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|114|cmd_save|`scripts/cmd_save.sh` `check_lord_instruction_ac_alignment_info`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|115|cmd_save|`scripts/cmd_save.sh` `check_measurement_env_info`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|116|cmd_save|`scripts/cmd_save.sh` `check_depends_on_field`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|117|cmd_save|`scripts/cmd_save.sh` `check_origin_field`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|118|cmd_save|`scripts/cmd_save.sh` `check_causal_verification_requirement`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|119|cmd_save|`scripts/cmd_save.sh` `check_three_layer_penetration`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|120|cmd_save|`scripts/cmd_save.sh` `check_self_reread_red_flag`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|121|cmd_save|`scripts/cmd_save.sh` `check_bundle_red_flag`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|122|cmd_save|`scripts/cmd_save.sh` `check_gunshi_analysis_overlap`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|123|cmd_save|`scripts/cmd_save.sh` `check_pi_number_collision`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|124|cmd_save|`scripts/cmd_save.sh` `check_ac_file_paths`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|125|cmd_save|`scripts/cmd_save.sh` `check_cmd_text_pipe_danger`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|126|cmd_save|`scripts/cmd_save.sh` `check_impl_push_ac`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|127|cmd_save|`scripts/cmd_save.sh` `check_dm_signal_bare_layer_reference`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|128|cmd_save|`scripts/cmd_save.sh` `check_ac_must_should_mix`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|129|cmd_save|`scripts/cmd_save.sh` `check_research_tool_growth_ac`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|130|cmd_save|`scripts/cmd_save.sh` `check_projects_yaml_forbidden_topics`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|131|cmd_save|`scripts/cmd_save.sh` `check_content_duplicate`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|132|cmd_save|`scripts/cmd_save.sh` `check_ac_param_sufficiency`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|133|cmd_save|`scripts/cmd_save.sh` `check_param_space_against_results`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|134|cmd_save|`scripts/cmd_save.sh` `check_param_space_shrink`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|135|cmd_save|`scripts/cmd_save.sh` `check_gunshi_design_num_relax`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|136|cmd_save|`scripts/cmd_save.sh` `check_action_immediate_verification`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|137|cmd_save|`scripts/cmd_save.sh` `check_research_tool_explicit`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|138|cmd_save|`scripts/cmd_save.sh` `check_timebox_minutes_required`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|139|cmd_save|`scripts/cmd_save.sh` `check_ac_absolute_literals`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|140|cmd_save|`scripts/cmd_save.sh` `check_db_backup_ac_warn`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|141|cmd_save|`scripts/cmd_save.sh` `check_numeric_literal_derivation_source_info`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|142|cmd_save|`scripts/cmd_save.sh` `check_ac_phase_mixing`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|143|cmd_save|`scripts/cmd_save.sh` `check_ac_test_scope`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|144|cmd_save|`scripts/cmd_save.sh` `check_new_file_structure_warning`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|145|cmd_save|`scripts/cmd_save.sh` `q11_has_existing_alternative_verification`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|146|cmd_save|`scripts/cmd_save.sh` `q5_has_execution_evidence`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|147|cmd_save|`scripts/cmd_save.sh` `q11_has_guard_duplicate_check`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|148|cmd_save|`scripts/cmd_save.sh` `inline_fill_this_placeholder_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|149|cmd_save|`scripts/cmd_save.sh` `inline_delegated_duplicate_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|150|cmd_save|`scripts/cmd_save.sh` `inline_previous_pass_pending_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|151|cmd_save|`scripts/cmd_save.sh` `inline_archive_duplicate_warn`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|152|cmd_save|`scripts/cmd_save.sh` `inline_other_draft_exists_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|153|cmd_save|`scripts/cmd_save.sh` `inline_diagnosis_format_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|154|cmd_save|`scripts/cmd_save.sh` `inline_environment_change_missing_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|155|cmd_save|`scripts/cmd_save.sh` `inline_environment_change_quality_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|156|cmd_save|`scripts/cmd_save.sh` `inline_environment_change_implemented_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|157|cmd_save|`scripts/cmd_save.sh` `inline_environment_change_structured_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|158|cmd_save|`scripts/cmd_save.sh` `inline_quality_gate_missing_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|159|cmd_save|`scripts/cmd_save.sh` `inline_quality_gate_invalid_fields_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|160|cmd_save|`scripts/cmd_save.sh` `inline_required_keys_missing_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|161|cmd_save|`scripts/cmd_save.sh` `inline_q4_depth_missing_warn`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|162|cmd_save|`scripts/cmd_save.sh` `inline_research_baseline_warn`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|163|cmd_save|`scripts/cmd_save.sh` `inline_q5_code_reading_only_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|164|cmd_save|`scripts/cmd_save.sh` `inline_q6_not_hiding_missing_warn`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|165|cmd_save|`scripts/cmd_save.sh` `inline_q7_definition_verified_warn`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|166|cmd_save|`scripts/cmd_save.sh` `inline_q8_scope_expression_warn`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|167|cmd_save|`scripts/cmd_save.sh` `inline_q8_compound_question_warn`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|168|cmd_save|`scripts/cmd_save.sh` `inline_q8_when_how_warn`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|169|cmd_save|`scripts/cmd_save.sh` `inline_q8_where_who_warn`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|170|cmd_save|`scripts/cmd_save.sh` `inline_q9_firefighting_missing_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|171|cmd_save|`scripts/cmd_save.sh` `inline_q9_root_cause_label_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|172|cmd_save|`scripts/cmd_save.sh` `inline_q9_prevention_label_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|173|cmd_save|`scripts/cmd_save.sh` `inline_q9_root_cause_length_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|174|cmd_save|`scripts/cmd_save.sh` `inline_q9_prevention_length_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|175|cmd_save|`scripts/cmd_save.sh` `inline_q10_knowledge_boundary_warn`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|176|cmd_save|`scripts/cmd_save.sh` `inline_q11_guard_duplicate_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|177|cmd_save|`scripts/cmd_save.sh` `inline_q11_existing_alternative_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|維持|
|178|cmd_save|`scripts/cmd_save.sh` `inline_lock_contention_warn`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|179|cmd_save|`scripts/cmd_save.sh` `warn_q5_pair_missing_session_state`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|180|cmd_save|`scripts/cmd_save.sh` `warn_missing_prev_cmd_lesson`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|181|cmd_save|`scripts/cmd_save.sh` `show_three_layer_memory_ruling_info`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|182|cmd_save|`scripts/cmd_save.sh` `show_gunshi_pane_status.ac_structure_incomplete`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|183|cmd_save|`scripts/cmd_save.sh` `show_gunshi_pane_status.unverified_assumption_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|184|cmd_save|`scripts/cmd_save.sh` `show_gunshi_pane_status.assumption_source_path_block`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|185|cmd_save|`scripts/cmd_save.sh` `show_gunshi_pane_status.claim_date_warn`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|186|cmd_save|`scripts/cmd_save.sh` `show_gunshi_pane_status.negative_claim_grep_warn`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|187|cmd_save|`scripts/cmd_save.sh` `show_gunshi_pane_status.bulletin_count_grep_warn`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|188|cmd_save|`scripts/cmd_save.sh` `inline_session_state_queue_presence_warn`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|
|189|cmd_save|`scripts/cmd_save.sh` `inline_session_state_cmd_block_presence_warn`|毎cmd保存|6645|4236|2409|BLOCK/WARNあり; detector_fp_rateとのitem-level join keyなしのためFP未確定|統合|

## 件数二値照合

- gate: 台帳62 = 現物62: yes
- hook: 台帳45 = 現物45: yes
- cmd_save: 台帳82 = catalog 82: yes
- 総計: 台帳189 = 62+45+82=189: yes
- 4分類: 撤去=0, 緩和=17, 統合=28, 維持=144; 合計=189: yes

## blocked_agent_seconds 上位10（推定）

`発火頻度×wall`を要求するが共通ログにwallがない。以下は当日一次実測と発火ログを結合できるものを優先し、欠測を明示した優先順位。推定値を精密値として扱わない。

|順位|候補|発火/実測wall|推定blocked秒|分類|5要件|
|---:|---|---|---:|---|---|
|1|pre-commit combined|毎commit / 8.4s,4.6s|6.5×commit回数|緩和|`.git/hooks/pre-commit`/呼出元git commit/関連precommit bats/linked worktree・9P/commit lock→hook順|
|2|cmd_save 82 checks|cmd_save log=6645 / wall欠測|N/A|統合|`scripts/cmd_save.sh` catalog行/`scripts/cmd_save.sh` caller/cmd_save bats/多重WARN昇格/parse→check→save|
|3|skill_script_refs|fire=1701 / wall欠測|N/A|緩和|`scripts/gates/gate_skill_script_refs.sh`/cmd_complete callers/skill refs tests/stale false positive/Git snapshot→batch lookup|
|4|gate_report_format|fire=7643 / wall欠測|N/A|維持|`scripts/gates/gate_report_format.sh`/report+review callers/report format bats/stale template false BLOCK/setter→final checkpoint|
|5|pretool dispatcher|毎tool / 0.079s|0.079×tool calls|緩和|`.claude/hooks/pretool-dispatch.sh`/settings hook/hook bats/heredoc+linked worktree/dispatch→guard|
|6|posttool dispatcher|毎tool / 0.286s|0.286×tool calls|緩和|`.claude/hooks/posttool-dispatch.sh`/settings hook/hook bats/large output/postprocess→return|
|7|startup gates|起動時 / wall欠測|N/A|緩和|`scripts/gates/gate_*_startup.sh`/session start/startup bats/stale snapshots/inject→gate→recovery|
|8|memory DB prompt injection|毎prompt / wall欠測|N/A|緩和|`scripts/hooks/prompt_state_inject.sh`/UserPromptSubmit/memory tests/FTS miss+DB lock/query→inject|
|9|Guard18 backlink scan|毎Write/Edit / wall欠測|N/A|緩和|`.claude/hooks/pre-write-edit-combined.sh`/PreToolUse/hook bats/large corpus/parse→backlink scan→decision|
|10|cmd_complete_gate|fire=351 / wall欠測|N/A|維持|`scripts/cmd_complete_gate.sh`/completion flow/gate bats/CI RED+uncommitted/final verify→archive|

## 結論

最優先は、品質境界を削ることではなく、毎tool/毎prompt/毎commitの同期枝を計測可能にして非同期化・差分化すること。最終checkpointの `gate_report_format` / `cmd_complete_gate` は維持し、cmd_save 82 checksは同一入力parse・三層検索・grepを共有して統合する。現状最大の穴は全防御機構に共通wall/identityがなく、blocked_agent_secondsとFPを項目単位でjoinできないことである。
