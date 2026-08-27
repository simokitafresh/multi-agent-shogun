# cmd_complete_gate.sh 分割設計書(2026-08-27)

meta: cmd=cmd_karo_hotfix_t83_cmd_complete_gate_split_design_20260827(T83) / 抽出=才蔵(機械抽出、22:37) / doc lane=将軍(23:00、報告YAMLから機械生成) / 正本データ=`queue/archive/reports/saizo_report_cmd_karo_hotfix_t83_*.yaml`(function_inventory 187行/split_unit_table 17行/test_ownership 43行) / 型=deploy_task 分割(最終弾J)

## §1 結論

`scripts/cmd_complete_gate.sh` 15,030 行(一次実測、前提差 0)。shell 定義 187 件(ユニーク 181、埋込 awk helper L6098/L12923/L14986 と L10584/L10588 は別枠)を **17 の lib/ 分割単位へ 187/187 割当(未割当 0)**。関連 unit test 43 ファイル(明示 contract 34)に所有者付与、所有者不明 0・理由なき重複 0。本書は設計のみ。実装・リネーム・挙動変更は次 cmd。

## §2 分割単位(source 順・共有 global・副作用・呼出依存)

| # | unit | 行範囲 | 分割先 | defs | 主な副作用 | cross-unit calls | 関数(先頭@行) |
|---|---|---|---|---|---|---|---|
| 1 | ci_readiness | L1-L552 | `scripts/lib/cmd_complete_gate_ci.sh` | 10 | include/source,git repository/state,Python helper,child script,stdout/file output,stdout/log output,cleanup,copy | check_report_commit_main_ancestry | evaluate_ci_readiness_json@L46<br>classify_gate_record_category@L153<br>classify_gate_record_reasons@L173<br>format_ci_raw_columns@L203<br>ci_fix_task_deployed@L212<br>format_gate_block_message@L244<br>classify_vercel_phase_output@L265<br>resolve_ci_expected_head@L280<br>resolve_report_commit_repo@L290<br>report_ci_push_state@L340 |
| 2 | report_parity | L553-L1016 | `scripts/lib/cmd_complete_gate_report_parity.sh` | 8 | include/source,git repository/state,Python helper,child script,lock,stdout/file output,stdout/log output,directory creation,cleanup | classify_gate_record_reasons classify_vercel_phase_output evaluate_ci_readiness_json format_gate_block_message gate_detail_begin gate_detail_finish report_ci_push_state resolve_ci_expected_head resolve_report_commit_repo resolve_report_file resolve_task_repo_dir | report_commit_main_ancestry_state@L553<br>report_blob_parity_mutable_path@L597<br>report_commit_blob_parity_state@L606<br>check_report_commit_blob_parity@L729<br>check_one_report@L734<br>discover_terminal_reports_for_cmd@L779<br>check_report_commit_main_ancestry@L831<br>check_one_report@L845 |
| 3 | telemetry | L1017-L1310 | `scripts/lib/cmd_complete_gate_telemetry.sh` | 11 | include/source,git repository/state,lock,stdout/file output,stdout/log output,directory creation,cleanup,rename | lock_path report_commit_blob_parity_state | cmd_complete_gate_function_timing_enable@L1017<br>_ccg_function_timing_debug@L1038<br>_ccg_function_timing_finish@L1062<br>gate_phase_now_us@L1148<br>gate_phase_tick@L1156<br>gate_subphase_tick@L1193<br>gate_subphase_finish@L1230<br>gate_phase_finish@L1231<br>gate_detail_now_us@L1233<br>gate_detail_finish@L1240<br>gate_detail_begin@L1272 |
| 4 | publication | L1311-L2100 | `scripts/lib/cmd_complete_gate_publication.sh` | 17 | include/source,git repository/state,Python helper,stdout/file output,directory creation,cleanup | source_only_path_snapshot | resolve_task_repo_dir@L1311<br>resolve_task_publish_repo_dir@L1364<br>push_overlap_blocking_paths@L1399<br>resolve_push_source_commit@L1433<br>mark_task_worktree_published@L1476<br>source_publish_receipt_path@L1489<br>resolve_publish_report_generation@L1493<br>source_publish_receipt_matches@L1534<br>receipt_source_commits_are_remote_ancestors@L1585<br>source_publish_legacy_evidence_path@L1602<br>migrate_legacy_source_publish_receipt@L1619<br>write_source_publish_receipt@L1800<br>source_snapshot_matches_tip@L1875<br>pass_no_improvement_base_tree_noop@L1900<br>discover_cmd_report_cross_repo_sources@L1980<br>report_source_paths_match_commit@L2072<br>source_only_path_snapshot_generic@L2100 |
| 5 | source_push | L2101-L3512 | `scripts/lib/cmd_complete_gate_source_push.sh` | 7 | include/source,git repository/state,Python helper,child script,stdout/file output,stdout/log output,directory creation,marker creation,cleanup,copy | discover_cmd_report_cross_repo_sources mark_task_worktree_published migrate_legacy_source_publish_receipt pass_no_improvement_base_tree_noop push_overlap_blocking_paths receipt_source_commits_are_remote_ancestors report_source_paths_match_commit resolve_publish_report_generation resolve_push_source_commit resolve_task_publish_repo_dir source_only_path_snapshot_generic source_publish_legacy_evidence_path source_publish_receipt_matches source_publish_receipt_path source_snapshot_matches_tip write_source_publish_receipt | source_only_lessons_candidate@L2695<br>source_only_lessons_scope_violation@L2716<br>source_only_insights_candidate@L3013<br>source_only_path_snapshot@L3028<br>task_push_allowed@L3048<br>push_from_clean_worktree@L3062<br>push_task_repositories@L3200 |
| 6 | convergence | L3513-L4284 | `scripts/lib/cmd_complete_gate_convergence.sh` | 15 | include/source,git repository/state,Python helper,lock,stdout/file output,stdout/log output,directory creation,marker creation,cleanup,copy | push_from_clean_worktree push_overlap_blocking_paths push_task_repositories resolve_task_repo_dir | converge_shared_execution_sources@L3513<br>lock_path@L3519<br>gate_detail_begin@L3524<br>gate_detail_finish@L3525<br>path_is_target@L3529<br>postclear_runtime_path_is_publishable@L3718<br>runtime_generation_change_is_clean_and_disjoint@L3734<br>capture_durable_writer_paths@L3753<br>publish_postclear_runtime_deltas@L3827<br>lock_path@L3844<br>gate_detail_begin@L3849<br>gate_detail_finish@L3850<br>wait_for_postclear_durable_writers@L4130<br>queue_postclear_publication_followup@L4212<br>model_injection_profile_intensity@L4277 |
| 7 | async_followups | L4285-L4640 | `scripts/lib/cmd_complete_gate_async_followups.sh` | 9 | Python helper,child script,lock,locked append,stdout/file output,stdout/log output,directory creation | gate_phase_tick lock_path | append_line_locked@L4285<br>log_gate_stderr_file@L4298<br>queue_lesson_impact_followup@L4309<br>lesson_done_satisfies_lesson_candidate_registration@L4317<br>cmd_status_is_canceled@L4343<br>classify_missing_report_status@L4392<br>resolve_declared_task_report_path@L4401<br>resolve_report_file@L4430<br>auto_unwrap_report_yaml@L4452 |
| 8 | notifications | L4641-L5000 | `scripts/lib/cmd_complete_gate_notifications.sh` | 15 | include/source,Python helper,child script,lock,locked append,mailbox write,stdout/file output,stdout/log output,directory creation,cleanup | append_line_locked format_gate_block_message log_gate_stderr_file | dispatch_gate_notification_async@L4641<br>send_high_notification@L4657<br>send_info_cmd_notification@L4664<br>gate_clear_notify_dedup_key@L4681<br>gate_clear_notify_flag_path@L4702<br>gate_clear_notify_historical_evidence@L4717<br>gate_clear_notify_claim@L4775<br>notify_shogun_gate_clear@L4792<br>notify_karo_cmd_complete_skill_hint@L4818<br>send_clear_notifications_once@L4840<br>notify_karo_lesson_registration_reminder@L4860<br>karo_gate_block_unread_exists@L4876<br>notify_karo_gate_block@L4908<br>notify_karo_cmd_fail@L4934<br>log_skill_execution_pass@L4953 |
| 9 | metrics_lifecycle | L5001-L5606 | `scripts/lib/cmd_complete_gate_metrics_lifecycle.sh` | 9 | Python helper,child script,stdout/file output,stdout/log output,cleanup | agent_pane_target log_gate_stderr_file model_injection_profile_intensity resolve_report_file | build_clear_duration_metric@L5001<br>build_clear_throughput_metric@L5128<br>build_clear_ctx_metric@L5386<br>build_karo_ctx_metric@L5423<br>build_first_gate_model_metric@L5438<br>update_status@L5449<br>set_matching_tasks_idle@L5503<br>record_finalize_phase_event@L5573<br>queue_completion_gap_metrics@L5589 |
| 10 | learning | L5607-L6833 | `scripts/lib/cmd_complete_gate_learning.sh` | 11 | include/source,Python helper,child script,lock,locked append,mailbox write,stdout/file output,stdout/log output,directory creation,cleanup,rename | append_line_locked lock_path log_gate_stderr_file resolve_report_file | append_codd_registry_entry@L5607<br>run_codd_propagate_update@L5963<br>run_skill_script_refs_check@L6003<br>normalize_block_reason_to_workaround_categories@L6094<br>update_karo_workaround_resolutions@L6131<br>classify_completed_rework_event_kind@L6269<br>capture_completed_rework_event@L6279<br>write_l6_horizontal_level5_insights@L6350<br>run_report_memory_semantic_scan@L6558<br>auto_resolve_cmd_related_insights@L6640<br>append_changelog@L6763 |
| 11 | task_context | L6834-L7225 | `scripts/lib/cmd_complete_gate_task_context.sh` | 13 | include/source,git repository/state,Python helper,stdout/file output,stdout/log output | cmd_entry_exists collect_report_commit_hash discover_reports_for_cmd record_block_reason resolve_report_file | detect_task_types@L6834<br>is_lessons_useful_empty_warn_task_type@L6874<br>handle_empty_lessons_useful_check@L6883<br>validate_lesson_feedback_set@L6897<br>agent_pane_target@L6905<br>normalize_model_label@L6914<br>encode_model_label_for_tsv@L6921<br>fallback_model_label_from_settings@L6930<br>resolve_agent_model_label@L6990<br>collect_gate_metrics_extra@L7017<br>collect_injected_lessons@L7076<br>collect_cmd_title@L7138<br>resolve_cmd_report_source_commit@L7185 |
| 12 | quality_checks | L7226-L8707 | `scripts/lib/cmd_complete_gate_quality_checks.sh` | 11 | include/source,git repository/state,Python helper,child script,lock,stdout/file output,stdout/log output,cleanup | collect_report_files_modified get_cmd_head_hashes level_heading lock_path resolve_cmd_report_source_commit resolve_report_file resolve_task_repo_dir | check_project_code_stubs@L7226<br>check_script_wiring@L7495<br>check_gs_bench_gate_warn@L7687<br>check_scope_drift@L7758<br>check_review_staleness@L7861<br>check_partial_completion@L7905<br>check_wtf_likelihood@L8014<br>append_lesson_tracking@L8077<br>update_lesson_impact_tsv@L8284<br>record_lesson_feedback_for_cmd@L8524<br>update_lesson_scores_batch@L8570 |
| 13 | report_checks | L8708-L10003 | `scripts/lib/cmd_complete_gate_report_checks.sh` | 28 | include/source,git repository/state,Python helper,child script,lock,locked append,stdout/file output,stdout/log output,directory creation | append_line_locked cmd_entry_exists cmd_status_is_canceled gate_detail_begin gate_detail_finish gate_phase_tick is_cmd_task resolve_report_file | record_block_reason@L8708<br>check_behavior_invariant_full_parity@L8720<br>resolve_gate_rg@L8832<br>level_heading@L8846<br>binary_checks_warn_reason@L8853<br>report_has_commit_binary_check_yes@L8874<br>collect_report_files_modified@L8906<br>discover_reports_for_cmd@L8967<br>collect_parent_cmd_report_files_modified@L9011<br>close_resolved_gate_alerts@L9024<br>has_parent_cmd_report@L9037<br>collect_git_show_w_files@L9042<br>collect_report_commit_hash@L9050<br>collect_cmd_phase_git_files@L9071<br>check_self_grade_commit_file_coverage@L9119<br>detect_task_role@L9210<br>_check_lc_found@L9228<br>lesson_candidate_status@L9239<br>check_how_it_works_status@L9293<br>cmd_task_matches@L9315<br>evaluate_review_report_status@L9321<br>find_overlapping_workers@L9347<br>run_review_quality_check@L9357<br>run_todo_fixme_residual_check@L9450<br>check_context_update@L9485<br>preflight_gate_flags@L9703<br>dedupe_task_files_by_logical_identity@L9942<br>print_matching_task_files_summary@L10000 |
| 14 | task_contract | L10004-L10702 | `scripts/lib/cmd_complete_gate_task_contract.sh` | 11 | git repository/state,Python helper,locked append,stdout/file output,stdout/log output | append_line_locked discover_reports_for_cmd evaluate_ci_readiness_json gate_phase_finish gate_phase_tick has_parent_cmd_report print_matching_task_files_summary resolve_report_file | is_cmd_task@L10004<br>cmd_entry_exists@L10006<br>get_cmd_head_hashes@L10032<br>get_cmd_changed_files@L10056<br>collect_report_modified_files@L10065<br>load_validated_sg7_context@L10102<br>resolve_karo_reviewed_at@L10181<br>resolve_sg7_completion_identity@L10255<br>collect_cmd_command_file_refs@L10279<br>collect_report_verified_existing_deps@L10569<br>collect_task_readonly_refs@L10669 |
| 15 | production_checks | L10703-L11262 | `scripts/lib/cmd_complete_gate_production_checks.sh` | 7 | include/source,git repository/state,Python helper,child script,locked append,stdout/file output,stdout/log output | append_line_locked build_first_gate_model_metric collect_cmd_command_file_refs collect_cmd_title collect_gate_metrics_extra collect_injected_lessons collect_report_modified_files collect_report_verified_existing_deps collect_task_readonly_refs detect_task_types gate_phase_tick get_cmd_changed_files level_heading load_validated_sg7_context record_block_reason resolve_karo_reviewed_at resolve_report_file resolve_sg7_completion_identity resolve_task_repo_dir | check_command_files_modified_coverage@L10703<br>cmd_requires_cdp_production_check@L10857<br>run_cdp_production_check@L10903<br>cmd_requires_dm_signal_production_smoke@L10949<br>dm_signal_report_deploy_sha@L10992<br>resolve_dm_signal_render_live_sha@L11022<br>run_dm_signal_production_smoke_check@L11059 |
| 16 | context_validation | L11263-L13538 | `scripts/lib/cmd_complete_gate_context_validation.sh` | 4 | include/source,git repository/state,Python helper,child script,lock,locked append,stdout/file output,stdout/log output | append_changelog append_lesson_tracking append_line_locked auto_resolve_cmd_related_insights binary_checks_warn_reason capture_completed_rework_event check_behavior_invariant_full_parity check_gs_bench_gate_warn check_how_it_works_status check_project_code_stubs check_script_wiring ci_fix_task_deployed classify_missing_report_status classify_vercel_phase_output cmd_entry_exists collect_report_modified_files detect_task_role evaluate_ci_readiness_json format_ci_raw_columns gate_phase_tick gate_subphase_tick handle_empty_lessons_useful_check has_parent_cmd_report lesson_candidate_status | check_context_freshness_own_commit@L11263<br>validate_report_format_file@L11831<br>compute_task_ac_version@L12080<br>check_task_ac_version_integrity@L12085 |
| 17 | safety_entrypoint | L13539-L15030 | `scripts/lib/cmd_complete_gate_entrypoint.sh` | 1 | include/source,git repository/state,Python helper,child script,lock,locked append,mailbox write,stdout/file output,stdout/log output,marker creation,cleanup,rename | append_changelog append_codd_registry_entry append_lesson_tracking append_line_locked auto_resolve_cmd_related_insights build_clear_ctx_metric build_clear_duration_metric build_clear_throughput_metric build_karo_ctx_metric capture_completed_rework_event capture_durable_writer_paths check_command_files_modified_coverage check_partial_completion check_report_commit_main_ancestry check_review_staleness check_scope_drift check_self_grade_commit_file_coverage check_wtf_likelihood classify_gate_record_reasons close_resolved_gate_alerts cmd_entry_exists format_ci_raw_columns gate_detail_begin gate_detail_finish | check_safety_pattern_removal@L13539 |

共有 global の詳細(unit 別の変数集合)は正本データ split_unit_table を参照(抽出器は引用符・here-doc 片も global 候補として拾うため精査は実装 cmd で行う)。

## §3 source 順(必ず保持)

分割後も以下の source 文と順序を entrypoint で保持する(L2296 は Python 片の `source =` 代入であり shell source ではない)。

```
L998: source "$SCRIPT_DIR/scripts/lib/task_cmd_match.sh"
L1293: source "$SCRIPT_DIR/scripts/lib/field_get.sh"
L1294: source "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
L1295: source "$SCRIPT_DIR/scripts/lib/task_lifecycle.sh"
L1296: source "$SCRIPT_DIR/scripts/lib/lock_path.sh"
L1297: source "$SCRIPT_DIR/scripts/lib/autogen_paths.sh"
L2296: source = Path(os.environ["CUMULATIVE_SOURCE"]).read_bytes().decode("utf-8")
L4275: source "$SCRIPT_DIR/scripts/lib/model_injection_profile.sh"
L6827: source "$SCRIPT_DIR/scripts/lib/gunshi_notify.sh"
L6831: source "$SCRIPT_DIR/scripts/lib/report_commit_nonoverlap_filter.sh"
L6909: source "$SCRIPT_DIR/scripts/lib/pane_lookup.sh"
L11170: source "$SCRIPT_DIR/scripts/lib/review_approval.sh"
L11847: source "$SCRIPT_DIR/scripts/lib/gate_report_format_classify.sh"
L13847: source "$SCRIPT_DIR/scripts/lib/defense_overhead_writer.sh"
L13852: source "$SCRIPT_DIR/scripts/lib/retro_pane_prompt.sh"
```

## §4 契約 test の所有(43 ファイル)

| test | 明示 contract | tests | 一次 owner |
|---|---|---|---|
| `tests/unit/test_archive_completed_target_manifest.bats` | yes | 9 | `scripts/lib/cmd_complete_gate_entrypoint.sh` |
| `tests/unit/test_cmd_complete_gate.bats` | yes | 282 | `scripts/lib/cmd_complete_gate_report_checks.sh` |
| `tests/unit/test_cmd_complete_gate_auto_lesson_write.bats` | no | 9 | `scripts/lib/cmd_complete_gate_learning.sh` |
| `tests/unit/test_cmd_complete_gate_ci_readiness.bats` | yes | 18 | `scripts/lib/cmd_complete_gate_ci.sh` |
| `tests/unit/test_cmd_complete_gate_ci_result_type.bats` | yes | 12 | `scripts/lib/cmd_complete_gate_ci.sh` |
| `tests/unit/test_cmd_complete_gate_context_freshness_block.bats` | no | 15 | `scripts/lib/cmd_complete_gate_context_validation.sh` |
| `tests/unit/test_cmd_complete_gate_convergence.bats` | yes | 3 | `scripts/lib/cmd_complete_gate_convergence.sh` |
| `tests/unit/test_cmd_complete_gate_gunshi_verdict_precheck.bats` | no | 14 | `scripts/lib/cmd_complete_gate_report_checks.sh` |
| `tests/unit/test_cmd_complete_gate_small_consolidated.bats` | no | 5 | `scripts/lib/cmd_complete_gate_report_checks.sh` |
| `tests/unit/test_cmd_complete_gate_source_publish.bats` | yes | 1 | `scripts/lib/cmd_complete_gate_publication.sh` |
| `tests/unit/test_cmd_complete_gate_subsystems.bats` | no | 31 | `scripts/lib/cmd_complete_gate_report_checks.sh` |
| `tests/unit/test_cmd_complete_gate_task_idle.bats` | yes | 16 | `scripts/lib/cmd_complete_gate_learning.sh` |
| `tests/unit/test_cmd_complete_gate_warning_levels.bats` | no | 45 | `scripts/lib/cmd_complete_gate_notifications.sh` |
| `tests/unit/test_cmd_complete_insight_consumption.bats` | no | 5 | `scripts/lib/cmd_complete_gate_async_followups.sh` |
| `tests/unit/test_cmd_complete_resume.bats` | yes | 10 | `scripts/lib/cmd_complete_gate_entrypoint.sh` |
| `tests/unit/test_cmd_complete_wrapper.bats` | yes | 37 | `scripts/lib/cmd_complete_gate_learning.sh` |
| `tests/unit/test_cmd_gate_scaffold_lib_mirror.bats` | yes | 3 | `scripts/lib/cmd_complete_gate_entrypoint.sh` |
| `tests/unit/test_cmd_quality_log.bats` | yes | 13 | `scripts/lib/cmd_complete_gate_convergence.sh` |
| `tests/unit/test_context_freshness_check.bats` | yes | 66 | `scripts/lib/cmd_complete_gate_context_validation.sh` |
| `tests/unit/test_defense_overhead_writer.bats` | yes | 18 | `scripts/lib/cmd_complete_gate_quality_checks.sh` |
| `tests/unit/test_deploy_task_ac_handling.bats` | yes | 54 | `scripts/lib/cmd_complete_gate_entrypoint.sh` |
| `tests/unit/test_deploy_task_lifecycle.bats` | yes | 102 | `scripts/lib/cmd_complete_gate_convergence.sh` |
| `tests/unit/test_deploy_task_nocode_commit_contract.bats` | yes | 16 | `scripts/lib/cmd_complete_gate_entrypoint.sh` |
| `tests/unit/test_deploy_task_yaml_injection.bats` | yes | 77 | `scripts/lib/cmd_complete_gate_entrypoint.sh` |
| `tests/unit/test_gate_gunshi_report_precheck.bats` | yes | 32 | `scripts/lib/cmd_complete_gate_entrypoint.sh` |
| `tests/unit/test_gate_hot_path_no_sync_io.bats` | yes | 8 | `scripts/lib/cmd_complete_gate_entrypoint.sh` |
| `tests/unit/test_gate_karo_startup.bats` | yes | 17 | `scripts/lib/cmd_complete_gate_entrypoint.sh` |
| `tests/unit/test_gate_report_format_classify.bats` | yes | 3 | `scripts/lib/cmd_complete_gate_report_checks.sh` |
| `tests/unit/test_gate_report_format_lg051_scope.bats` | yes | 6 | `scripts/lib/cmd_complete_gate_report_checks.sh` |
| `tests/unit/test_gate_report_format_pass_no_improvement.bats` | yes | 24 | `scripts/lib/cmd_complete_gate_report_checks.sh` |
| `tests/unit/test_gate_vercel_phase.bats` | no | 8 | `scripts/lib/cmd_complete_gate_entrypoint.sh` |
| `tests/unit/test_heavy_job_admission.bats` | yes | 94 | `scripts/lib/cmd_complete_gate_entrypoint.sh` |
| `tests/unit/test_inbox_write.bats` | yes | 118 | `scripts/lib/cmd_complete_gate_convergence.sh` |
| `tests/unit/test_ninja_monitor.bats` | yes | 36 | `scripts/lib/cmd_complete_gate_entrypoint.sh` |
| `tests/unit/test_ninja_monitor_clear_guard.bats` | yes | 71 | `scripts/lib/cmd_complete_gate_entrypoint.sh` |
| `tests/unit/test_ninja_monitor_stall.bats` | yes | 111 | `scripts/lib/cmd_complete_gate_entrypoint.sh` |
| `tests/unit/test_pytest_speed_task_generator.bats` | yes | 12 | `scripts/lib/cmd_complete_gate_entrypoint.sh` |
| `tests/unit/test_report_field_set_normalize_hook.bats` | no | 11 | `scripts/lib/cmd_complete_gate_report_checks.sh` |
| `tests/unit/test_retro_verbatim_prompt_identity.bats` | yes | 5 | `scripts/lib/cmd_complete_gate_entrypoint.sh` |
| `tests/unit/test_review_approval.bats` | yes | 13 | `scripts/lib/cmd_complete_gate_entrypoint.sh` |
| `tests/unit/test_run_tests.bats` | yes | 106 | `scripts/lib/cmd_complete_gate_entrypoint.sh` |
| `tests/unit/test_semantic_index_update.bats` | yes | 44 | `scripts/lib/cmd_complete_gate_learning.sh` |
| `tests/unit/test_skill_feedback_loop.bats` | yes | 44 | `scripts/lib/cmd_complete_gate_quality_checks.sh` |

## §5 実装 cmd が守る制約

- AC1 -> AC2 -> AC3 strict serial dependency
- preserve source order listed in source_order
- preserve cross-unit call edges listed in split_unit_table
- doc_lane_handoff only: docs/design/cmd_complete_gate_split_design_20260827.md

エッジケース:
- embedded awk helper definitions are not shell functions and remain separately inventoried
- conditional nested shell definitions are counted by definition occurrence
- source order must preserve all source statements listed in source_order
- external-scope zero mapping must not be mislabeled as a passing test run

## §6 次弾(実装 cmd の型)

1. entrypoint(`cmd_complete_gate_entrypoint.sh`)が §3 の source 順で 16 lib を読み込み、`scripts/cmd_complete_gate.sh` は薄い wrapper に。
2. 1 unit ずつ移動→所有 test を実行→commit(バッチらせん 5 条: 個別 before-after・ファイル排他)。
3. 各弾で `tests/unit/test_cmd_gate_scaffold_lib_mirror.bats` と hot-path 契約(`test_gate_hot_path_no_sync_io.bats`)を境界確認。
4. 計測: gate 本体 wall(gate_metrics duration_sec)と bash 読込時間を before/after で記録。

## §7 因果

`[[cmd_4403_script_size_alert]] -> [[cmd_karo_hotfix_t83_cmd_complete_gate_split_design_20260827]] -> [[cmd_complete_gate_肥大化]] -> [[deploy_task_split_final_J]]`(同型)
