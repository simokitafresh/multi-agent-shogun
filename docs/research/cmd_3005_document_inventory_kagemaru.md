# cmd_3005 ドキュメント棚卸し（kagemaru）

- generated_at: 2026-05-22T22:25:30+09:00
- source: `config/projects.yaml` registered projects; dependency/build/cache dirs pruned; project roots fully walked
- target_extensions: `md`, `yaml/yml`, `txt`, `rst`
- csv_full_inventory: `docs/research/cmd_3005_document_inventory_kagemaru.csv`
- total_files: 12974
- excluded_unreadable_entries: 2 (broken archive symlink等。行数/更新日が取得できないため除外)

## Category Totals

| category | files |
|---|---:|
| context | 59 |
| コード | 663 |
| チェックリスト | 10 |
| 教訓 | 63 |
| 自動生成 | 9496 |
| 記事(殿の判断) | 63 |
| 設計書 | 2620 |

## Project Totals

| project | files | 記事 | 設計書 | context | 教訓 | チェックリスト | 自動生成 | コード | 除外 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| auto-ops | 73 | 0 | 67 | 0 | 1 | 0 | 0 | 5 | 0 |
| database | 29 | 0 | 8 | 1 | 0 | 0 | 12 | 8 | 0 |
| dm-signal | 2115 | 56 | 1360 | 3 | 3 | 0 | 303 | 390 | 0 |
| google-classroom | 34 | 0 | 23 | 1 | 1 | 0 | 5 | 4 | 0 |
| infra | 10533 | 7 | 997 | 53 | 57 | 10 | 9176 | 233 | 0 |
| kj-partshift | 8 | 0 | 6 | 0 | 0 | 0 | 0 | 2 | 0 |
| kj-role-count | 59 | 0 | 55 | 0 | 0 | 0 | 0 | 4 | 0 |
| kj-toilet | 53 | 0 | 50 | 0 | 0 | 0 | 0 | 3 | 0 |
| mcas | 6 | 0 | 3 | 0 | 1 | 0 | 0 | 2 | 0 |
| milk | 3 | 0 | 1 | 0 | 0 | 0 | 0 | 2 | 0 |
| rebalancer | 21 | 0 | 15 | 1 | 0 | 0 | 0 | 5 | 0 |
| simple-ocr | 40 | 0 | 35 | 0 | 0 | 0 | 0 | 5 | 0 |

## Memory DB Candidate Shape

- candidate_files_non_archived: 2811
- 優先投入カテゴリ: context / 教訓 / チェックリスト / 設計書 / 記事(殿の判断)
- 低優先または除外: コード(設定・CI・requirements等), 自動生成, 除外

## Largest Candidate Files

| project | category | lines | path |
|---|---|---:|---|
| dm-signal | 設計書 | 320736 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1760_underwater_period_ninpo_results.yaml` |
| dm-signal | 設計書 | 299743 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1760_sortino_ratio_ninpo_results.yaml` |
| dm-signal | 設計書 | 137161 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1745_alm_ninpo_results.yaml` |
| infra | 設計書 | 94963 | `/mnt/c/tools/multi-agent-shogun/logs/shogun_action_log.txt` |
| dm-signal | 設計書 | 43246 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1736_results.yaml` |
| dm-signal | 設計書 | 29907 | `/mnt/c/Python_app/DM-signal/outputs/cdp_profile_cmd695_review/ZxcvbnData/3.2.0.0/english_wikipedia.txt` |
| infra | 設計書 | 29907 | `/mnt/c/tools/multi-agent-shogun/.codex_tmp/cdp_profile_cmd2268/ZxcvbnData/3.2.0.0/english_wikipedia.txt` |
| dm-signal | 設計書 | 29636 | `/mnt/c/Python_app/DM-signal/outputs/cdp_profile_cmd695_review/ZxcvbnData/3.2.0.0/passwords.txt` |
| infra | 設計書 | 29636 | `/mnt/c/tools/multi-agent-shogun/.codex_tmp/cdp_profile_cmd2268/ZxcvbnData/3.2.0.0/passwords.txt` |
| dm-signal | 設計書 | 18999 | `/mnt/c/Python_app/DM-signal/outputs/cdp_profile_cmd695_review/ZxcvbnData/3.2.0.0/us_tv_and_film.txt` |
| infra | 設計書 | 18999 | `/mnt/c/tools/multi-agent-shogun/.codex_tmp/cdp_profile_cmd2268/ZxcvbnData/3.2.0.0/us_tv_and_film.txt` |
| infra | 教訓 | 14253 | `/mnt/c/tools/multi-agent-shogun/projects/dm-signal/lessons_archive.yaml` |
| infra | 教訓 | 13160 | `/mnt/c/tools/multi-agent-shogun/projects/infra/lessons_archive.yaml` |
| dm-signal | 設計書 | 9987 | `/mnt/c/Python_app/DM-signal/outputs/cdp_profile_cmd695_review/ZxcvbnData/3.2.0.0/surnames.txt` |
| infra | 設計書 | 9987 | `/mnt/c/tools/multi-agent-shogun/.codex_tmp/cdp_profile_cmd2268/ZxcvbnData/3.2.0.0/surnames.txt` |
| dm-signal | 設計書 | 9379 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1748_partial_nhf.yaml` |
| dm-signal | 設計書 | 9379 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1748_partial_sharpe.yaml` |
| dm-signal | 設計書 | 9246 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1748_partial_cagr.yaml` |
| dm-signal | 設計書 | 9113 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1748_partial_left_tail_jumps_inv.yaml` |
| infra | 教訓 | 8825 | `/mnt/c/tools/multi-agent-shogun/projects/dm-signal/lessons.yaml` |
| dm-signal | 教訓 | 8057 | `/mnt/c/Python_app/DM-signal/tasks/lessons.md` |
| dm-signal | 設計書 | 7293 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1791_metrics_bunshin_l1_wf_pattern_classification.yaml` |
| infra | 教訓 | 7189 | `/mnt/c/tools/multi-agent-shogun/projects/infra/lessons.yaml` |
| dm-signal | 設計書 | 7164 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1791_1186_kasoku_ratio_l1_wf_pattern_classification.yaml` |
| dm-signal | 設計書 | 6981 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1791_1186_oikaze_l1_wf_pattern_classification.yaml` |
| infra | 教訓 | 6836 | `/mnt/c/tools/multi-agent-shogun/tasks/lessons.md` |
| dm-signal | 設計書 | 6795 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1748_partial_max_run_up.yaml` |
| dm-signal | 設計書 | 6787 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1791_1186_nukimi_l1_wf_pattern_classification.yaml` |
| dm-signal | 設計書 | 6781 | `/mnt/c/Python_app/DM-signal/analysis_runs/docs/pipeline-troubleshooting.md` |
| dm-signal | 設計書 | 6512 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1791_1200_yotsume_l1_wf_pattern_classification.yaml` |
| dm-signal | 設計書 | 6512 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1791_smoke_l1_wf_pattern_classification.yaml` |
| dm-signal | 設計書 | 6457 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1791_1186_kasoku_diff_l1_wf_pattern_classification.yaml` |
| dm-signal | 設計書 | 6419 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1791_1186_kawarimi_l1_wf_pattern_classification.yaml` |
| infra | 教訓 | 6398 | `/mnt/c/tools/multi-agent-shogun/.tmp/lesson_write_bench_hayate_after_1779196971141546168/fakeproj/tasks/lessons.md` |
| infra | 教訓 | 6398 | `/mnt/c/tools/multi-agent-shogun/.tmp/lesson_write_bench_hayate_real_1779196913528237491/fakeproj/tasks/lessons.md` |
| infra | 教訓 | 6398 | `/mnt/c/tools/multi-agent-shogun/.tmp/lesson_write_bench_hayate_tags_1779196931173464682/fakeproj/tasks/lessons.md` |
| dm-signal | 設計書 | 5352 | `/mnt/c/Python_app/DM-signal/analysis_runs/results/_trash/FoF_20260111_Combined4PF_test.md` |
| dm-signal | 設計書 | 3709 | `/mnt/c/Python_app/DM-signal/outputs/cdp_profile_cmd695_review/ZxcvbnData/3.2.0.0/female_names.txt` |
| infra | 設計書 | 3709 | `/mnt/c/tools/multi-agent-shogun/.codex_tmp/cdp_profile_cmd2268/ZxcvbnData/3.2.0.0/female_names.txt` |
| infra | 設計書 | 3384 | `/mnt/c/tools/multi-agent-shogun/memory/dialogue_preprocessing_research_20260331.md` |
| dm-signal | 設計書 | 3363 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1759_dna_constrained_alm.yaml` |
| dm-signal | 設計書 | 3256 | `/mnt/c/Python_app/DM-signal/outputs/analysis/cmd_2151_cmd_1947_after_profile.txt` |
| dm-signal | 設計書 | 2701 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1747_cross_comparison.yaml` |
| simple-ocr | 設計書 | 2533 | `/mnt/c/Python_app/Simple-OCR/CLAUDE/old/ocr-exclusion-pattern-design.md` |
| dm-signal | 設計書 | 2529 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1761_full_metrics.yaml` |
| dm-signal | 設計書 | 2160 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1793_ninjutsu_alm_suitability.yaml` |
| dm-signal | 設計書 | 2085 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1759_family_objective_matrix.yaml` |
| infra | 設計書 | 2064 | `/mnt/c/tools/multi-agent-shogun/logs/cmd_design_quality.yaml` |
| dm-signal | 設計書 | 1740 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1791_1186_kasoku_diff_l1_wf_validation.yaml` |
| dm-signal | 設計書 | 1740 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1791_1186_kasoku_ratio_l1_wf_validation.yaml` |
| dm-signal | 設計書 | 1740 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1791_1186_kawarimi_l1_wf_validation.yaml` |
| dm-signal | 設計書 | 1740 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1791_1186_nukimi_l1_wf_validation.yaml` |
| dm-signal | 設計書 | 1740 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1791_1186_oikaze_l1_wf_validation.yaml` |
| dm-signal | 設計書 | 1740 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1791_1200_yotsume_l1_wf_validation.yaml` |
| dm-signal | 設計書 | 1740 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1791_metrics_bunshin_l1_wf_validation.yaml` |
| dm-signal | 設計書 | 1740 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1791_smoke_l1_wf_validation.yaml` |
| dm-signal | 設計書 | 1663 | `/mnt/c/Python_app/DM-signal/docs/research/metrics-engine-runbook.md` |
| infra | 設計書 | 1643 | `/mnt/c/tools/multi-agent-shogun/docs/semantic-index/index.md` |
| infra | 設計書 | 1543 | `/mnt/c/tools/multi-agent-shogun/README.md` |
| infra | 設計書 | 1520 | `/mnt/c/tools/multi-agent-shogun/README_ja.md` |
| dm-signal | 設計書 | 1512 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1741_family_alm_results.yaml` |
| dm-signal | 設計書 | 1502 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1760_underwater_period_vs_shin.yaml` |
| dm-signal | 設計書 | 1432 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1739_cscv_results.yaml` |
| dm-signal | 設計書 | 1414 | `/mnt/c/Python_app/DM-signal/docs/security/security-mvp.md` |
| dm-signal | 設計書 | 1392 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1760_sortino_ratio_vs_shin.yaml` |
| dm-signal | 設計書 | 1391 | `/mnt/c/Python_app/DM-signal/analysis_runs/results/fof/reports/DM2_Intersection_EW_20260111.md` |
| dm-signal | 設計書 | 1367 | `/mnt/c/Python_app/DM-signal/docs/rule/trade-rule.md` |
| dm-signal | 設計書 | 1360 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1747_ninpo_6obj_results.yaml` |
| dm-signal | 設計書 | 1349 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1745_vs_shin_ninpo.yaml` |
| dm-signal | 設計書 | 1327 | `/mnt/c/Python_app/DM-signal/docs/skills/portfolio-analysis-verification.md` |
| dm-signal | 設計書 | 1299 | `/mnt/c/Python_app/DM-signal/docs/rule/design.md` |
| dm-signal | 設計書 | 1250 | `/mnt/c/Python_app/DM-signal/docs/rule/calculation-theory.md` |
| dm-signal | 設計書 | 1163 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1748_partial_tail_contribution.yaml` |
| dm-signal | 設計書 | 1142 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/batch_metrics_bunshin_l1_wf_pattern_classification.yaml` |
| dm-signal | 設計書 | 1142 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1784_baseline_metrics_bunshin_l1_wf_pattern_classification.yaml` |
| dm-signal | 設計書 | 1142 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/cmd_1784_clean_batch_metrics_bunshin_l1_wf_pattern_classification.yaml` |
| dm-signal | 設計書 | 1142 | `/mnt/c/Python_app/DM-signal/outputs/analysis/alm_research/saizo1782_batch_metrics_bunshin_l1_wf_pattern_classification.yaml` |
| infra | 設計書 | 1132 | `/mnt/c/tools/multi-agent-shogun/docs/research/nested-fof-hrp-herc-implementation.md` |
| database | 設計書 | 1128 | `/mnt/c/Python_app/database/docs/architecture.md` |
| dm-signal | 設計書 | 1123 | `/mnt/c/Python_app/DM-signal/marketing-director/templates/psyco-teqnique.md` |

## Classification Rules

- 記事(殿の判断): `article/note/blog/post/essay/newsletter/draft` を含む文書
- 設計書: `docs/`, `projects/`, `README`, `design/spec/architecture/research/runbook` 系
- context: `context/`, `AGENTS.md`, `CLAUDE.md`, `MEMORY.md`
- 教訓: `lessons*` / `*lesson*`
- チェックリスト: `checklist` / `check-list`
- 自動生成: `generated/archive/backup` 系
- コード: CI・設定・requirements・アプリ設定YAML
- 除外: 依存物・生成物・lock等
