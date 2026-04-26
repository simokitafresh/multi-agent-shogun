# cmd_karo_reprofile_bench_20260426

目的: 前回プロファイリングTop 20スクリプトの実行時間を、現行HEADで5回実行し中央値で再計測する。

計測日時: 2026-04-26  
実行環境: `/mnt/c/tools/multi-agent-shogun` on WSL2 `/mnt/c`  
計測方法: Python `time.perf_counter()` で各コマンドを5回実行し、wall-clock ms の中央値を採用。副作用を避けるため、書込み系は usage path / dry-run / `/tmp/shogun_reprofile_bench_saizo` 隔離fixtureを使用した。  
CoDD台帳: `docs/research/codd_refactor_registry.md` を照合。

## Summary

| スクリプト | 前回ms | 今回ms(中央値) | 差分% | CoDD台帳 |
|---|---:|---:|---:|---|
| `scripts/gates/gate_report_format.sh` | 40 | 214.8 | +437.0% | 改善済み。2026-04-18 kagemaru/hayate: 148→90ms、76.0→71.2ms。今回fixtureは未完成reportでFAIL pathのため前回条件と差異あり。 |
| `scripts/shutsujin_departure.sh` | 2424 | 114.8 | -95.3% | 改善済み。2026-04-16/18にdry-run系を複数回改善、代表: 2.43s→0.17s、0.13s→0.04s。 |
| `scripts/lib/yaml_field_set.sh` | 51 | 32.6 | -36.0% | 改善済み。2026-04-18 hayate: 14.9→13.7ms。今回fixtureはtask status更新。 |
| `scripts/cdp/cdp_cli.sh` | 36 | 16.3 | -54.6% | 台帳記載なし。今回計測はno-args usage path。 |
| `scripts/ntfy.sh` | 130 | 8.0 | -93.9% | 改善済み。2026-04-16 kagemaru: 33→23ms。今回計測はno-args usage pathで送信なし。 |
| `scripts/inbox_write.sh` | 89 | 16.4 | -81.6% | 改善済み。2026-04-16/18に複数回改善、代表: 78→50ms、32→25ms、29→26ms。今回計測はno-args usage pathで書込みなし。 |
| `scripts/ninja_done.sh` | 68 | 7.9 | -88.4% | 改善済み。2026-04-16/18に複数回改善、usage 22→2ms、success path 99→60ms等。今回計測はno-args usage path。 |
| `scripts/report_field_set.sh` | 40 | 7.9 | -80.1% | 改善済み。2026-04-16/18に複数回改善、代表: 66-70→11ms、~15→~12ms。今回計測はno-args usage path。 |
| `scripts/lib/cli_lookup.sh` | 50 | 16.7 | -66.6% | 改善済み。2026-04-18 saizo: 113.6→44.8ms。今回計測はsourceのみ。 |
| `.claude/hooks/stop-lint-gate.sh` | 3002 | 114.9 | -96.2% | 改善済み。2026-04-16/18に複数回改善、代表: 5149→61ms、0.82s→0.65s。今回計測は現行repoでstaged対象なしのclean exit。 |
| `scripts/lib/agent_config.sh` | 36 | 16.4 | -54.4% | 改善済み。2026-04-18 kagemaru: 36→~6ms。今回計測はsourceのみ。 |
| `scripts/lib/field_get.sh` | 33 | 32.7 | -0.9% | 改善済み。2026-04-18 kagemaru: 33→~2ms with `FIELD_GET_NO_LOG=1`。今回計測は通常ログ条件のYAML field取得。 |
| `scripts/archive_completed.sh` | 52 | 32.3 | -37.9% | 改善済み。2026-04-16/18に複数回改善、代表: 1073→783ms、1073→962ms。今回計測はinvalid-args usage pathでarchiveなし。 |
| `scripts/cmd_delegate.sh` | 28 | 8.4 | -70.0% | 改善済み。2026-04-18 saizo: 93.8→59.7ms。今回計測はno-args usage path。 |
| `scripts/inbox_mark_read.sh` | 34 | 8.2 | -75.9% | 改善済み。2026-04-18 kagemaru: 34→16ms。今回計測はno-args usage pathで既読化なし。 |
| `.claude/hooks/pre-bash-combined.sh` | 21 | 16.6 | -21.1% | 改善済み。2026-04-18 kagemaru: guard 10→7ms / hot 45→32ms。saizoの別試行はregressionでrevert済み。今回計測は安全なBash payload。 |
| `scripts/dashboard_auto_section.sh` | 2775 | 314.9 | -88.7% | 改善済み。2026-04-16/18に複数回改善、代表: 0.89s→0.34s、330→220ms。今回計測は`--dry-run`。 |
| `scripts/gates/gate_cycle_health.sh` | 2575 | 415.9 | -83.8% | 改善済み。2026-04-16/18に複数回改善、代表: 793→296ms。2026-04-18再改善は192→192msでPASS_NO_IMPROVEMENT。 |
| `scripts/deploy_task.sh` | N/A | 64.7 | N/A (追加対象) | 改善済み。2026-04-15/16/18に複数回改善、代表: 2639→88ms、224→32ms、83→62ms。今回計測はno-args usage path。 |
| `scripts/cmd_complete_gate.sh` | N/A | 32.8 | N/A (追加対象) | 改善済み。2026-04-19 hayate: live median 31.956s→4.993s。今回計測はno-args usage path。 |

## Raw Runs

| スクリプト | runs ms | exit codes | 計測コマンド概要 |
|---|---:|---|---|
| `scripts/gates/gate_report_format.sh` | 164.8, 164.6, 214.8, 215.0, 215.9 | 1,1,1,1,1 | `bash scripts/gates/gate_report_format.sh /tmp/.../report.yaml` |
| `scripts/shutsujin_departure.sh` | 115.7, 114.8, 64.7, 64.6, 115.9 | 0,0,0,0,0 | `bash scripts/shutsujin_departure.sh --dry-run` |
| `scripts/lib/yaml_field_set.sh` | 32.2, 32.6, 32.7, 32.5, 33.1 | 0,0,0,0,0 | `bash scripts/lib/yaml_field_set.sh /tmp/.../task.yaml task status acknowledged` |
| `scripts/cdp/cdp_cli.sh` | 16.3, 16.3, 17.0, 16.3, 16.4 | 1,1,1,1,1 | `bash scripts/cdp/cdp_cli.sh` |
| `scripts/ntfy.sh` | 9.6, 7.9, 8.0, 8.1, 7.8 | 1,1,1,1,1 | `bash scripts/ntfy.sh` |
| `scripts/inbox_write.sh` | 16.4, 17.7, 16.3, 16.5, 16.1 | 1,1,1,1,1 | `bash scripts/inbox_write.sh` |
| `scripts/ninja_done.sh` | 7.9, 7.9, 8.1, 7.8, 8.4 | 1,1,1,1,1 | `bash scripts/ninja_done.sh` |
| `scripts/report_field_set.sh` | 8.2, 8.3, 7.7, 7.8, 7.9 | 1,1,1,1,1 | `bash scripts/report_field_set.sh` |
| `scripts/lib/cli_lookup.sh` | 16.3, 16.7, 17.1, 17.5, 16.1 | 0,0,0,0,0 | `source scripts/lib/cli_lookup.sh` |
| `.claude/hooks/stop-lint-gate.sh` | 115.4, 114.6, 114.9, 114.5, 115.0 | 0,0,0,0,0 | `bash .claude/hooks/stop-lint-gate.sh` |
| `scripts/lib/agent_config.sh` | 16.2, 16.6, 16.2, 16.4, 16.5 | 0,0,0,0,0 | `source scripts/lib/agent_config.sh` |
| `scripts/lib/field_get.sh` | 32.7, 32.4, 32.4, 64.4, 33.7 | 0,0,0,0,0 | `source scripts/lib/field_get.sh; field_get /tmp/.../field.yaml task.status` |
| `scripts/archive_completed.sh` | 32.6, 16.2, 15.8, 32.3, 32.4 | 1,1,1,1,1 | `bash scripts/archive_completed.sh bad args extra` |
| `scripts/cmd_delegate.sh` | 8.3, 16.5, 8.8, 8.4, 8.2 | 1,1,1,1,1 | `bash scripts/cmd_delegate.sh` |
| `scripts/inbox_mark_read.sh` | 8.1, 16.4, 8.2, 8.1, 8.5 | 1,1,1,1,1 | `bash scripts/inbox_mark_read.sh` |
| `.claude/hooks/pre-bash-combined.sh` | 16.2, 16.2, 16.6, 32.5, 18.8 | 0,0,0,0,0 | safe Bash JSON payload via stdin |
| `scripts/dashboard_auto_section.sh` | 467.1, 366.3, 314.9, 265.0, 264.9 | 0,0,0,0,0 | `bash scripts/dashboard_auto_section.sh --dry-run >/dev/null` |
| `scripts/gates/gate_cycle_health.sh` | 465.4, 365.5, 365.0, 465.6, 415.9 | 0,0,0,0,0 | `bash scripts/gates/gate_cycle_health.sh` |
| `scripts/deploy_task.sh` | 65.6, 64.5, 64.6, 65.4, 64.7 | 1,1,1,1,1 | `bash scripts/deploy_task.sh` |
| `scripts/cmd_complete_gate.sh` | 32.6, 32.8, 32.7, 32.8, 65.7 | 1,1,1,1,1 | `bash scripts/cmd_complete_gate.sh` |

## Notes

- `deploy_task.sh` と `cmd_complete_gate.sh` はcmd側で「追加。高頻度」とされ、前回msが与えられていないため差分%は `N/A` とした。
- usage path の exit code `1` は正常なusage表示終了として扱った。送信・archive・委任・既読化などの本番副作用は発生させていない。
- `gate_report_format.sh` のみ前回比で大幅悪化しているが、今回の入力は未完成reportテンプレートのFAIL pathであり、台帳のvalid PASS/cache miss条件と一致しない。比較には条件差がある。
