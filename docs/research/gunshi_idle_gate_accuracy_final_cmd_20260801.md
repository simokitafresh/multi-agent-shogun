# Gate Accuracy Final-Command Analysis
<!-- generated: 2026-08-01T02:47:00+09:00 by gunshi idle analysis -->

## Conclusion

The repeated 50% alert was a population-granularity defect, not a prediction-quality regression. The incident window contained five mismatches, all intermediate RC/FAIL entries later superseded by a final LGTM for the same command. True final-command prediction errors were 0.

## Incident-window classification

| Entry | Command | Verdict | Prediction/result | Classification |
|---|---|---|---|---|
| 1 | `cmd_karo_hotfix_run_tests_task_python_dispatch_20260801` | `REQUEST_CHANGES` | `BLOCK/CLEAR` | RC途中のprediction切替 |
| 2 | same | `FAIL` | `BLOCK/CLEAR` | RC途中のprediction切替 |
| 3 | `cmd_karo_hotfix_archive_review_reviewer_fail_bundle_20260801` | `REQUEST_CHANGES` | `BLOCK/CLEAR` | RC途中のprediction切替 |
| 4 | same | `FAIL` | `BLOCK/CLEAR` | RC途中のprediction切替 |
| 5 | same | `FAIL` | `BLOCK/CLEAR` | RC途中のprediction切替 |

- Gate specification changes: 0
- True prediction errors: 0
- Raw recent-entry metric: 5/10 (50%)
- Final verdict within that ten-entry incident window: 4/4 commands (100%)
- Corrected current final-command metric: 9/9 commands (100%; fewer than ten eligible commands exist in the active log)

## Root cause and correction

`skills/gate-sync/SKILL.md` independently counted every review entry although `scripts/gates/gate_gunshi_accuracy.sh` is the canonical calculator. RC/FAIL round trips therefore multiplied the denominator and compared intermediate predictions with the eventual terminal gate result.

The canonical calculator now parses YAML, keeps only the last eligible entry for each `cmd_id`, and emits `RECENT_FINAL_CMD_ACCURACY`. The skill now invokes that calculator and may alert only when this corrected metric is below 70%.

Origin: `[[blt_20260801_024330_fde785]] -> [[LS096]] -> [[gate_accuracy_final_command_granularity]]`
