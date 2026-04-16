# CoDD Refactor Registry

CoDDリファクタリングの実績台帳。車輪の再発明を防ぐため、「いつ」「誰が」「何を」「どこまで進めたか」を記録する。

| 日付 | 実施者 | 対象スクリプト/領域 | Phase到達 | Before→After | spec/after設計書パス |
|------|--------|---------------------|-----------|--------------|----------------------|
| 2026-04-16 | 才蔵 | `scripts/report_field_set.sh` | Phase 5(計測+実装+検証)。spec事後作成 | `66-70ms → 11ms` (`-83%`, scalar hot path) | spec+after: `docs/research/report_field_set_after_20260416.md` |
| 2026-04-16 | 才蔵 | `scripts/inbox_write.sh` | Phase 5(計測+実装+検証)。spec事後作成 | `78ms → 50ms` (`-35.9%`, write path) / `89ms → 10-20ms` (`--help`) | spec+after: `docs/research/inbox_write_after_20260416.md` |
| 2026-04-16 | 才蔵 | `scripts/dashboard_auto_section.sh` | Phase 5(計測+実装+検証)。spec事後作成 | `0.89s → 0.34s` (`-61.8%`, stale-cache path) | spec+after: `docs/research/dashboard_auto_section_after_20260416.md` |
| 2026-04-16 | 才蔵 | `scripts/post_recalculate_checks.sh` | Phase 5(計測+実装+検証)。spec先行作成 | `6.15s → 2.23s` (`-63.9%`, cold run) | spec: `docs/research/codd_spec_post_recalculate_checks_20260416.md` |
| 2026-04-15 | 軍師 | `scripts/deploy_task.sh` | Phase 6完了 | `2639ms → 88ms` (`-97%`) | spec: `docs/research/gunshi_deploy_task_refactor_spec.md` / after: `docs/research/deploy_task_after_20260415.md` |
| 2026-04-14 | 軍師 | `scripts/gates/gate_gunshi_startup.sh` / `scripts/gates/gate_shogun_startup.sh` / `scripts/gunshi_gate_sync.sh` | なぜなぜ7回完了 + 高速化適用済 | `14.9s → 3.2s` (`4.7x`) | spec+result: `docs/research/gunshi_idle_startup_speedup_20260414.md` |
| 2026-04-14 | 軍師 | `scripts/analysis/grid_search/run_077_*` / `scripts/analysis/grid_search/gs_vectorized_subset.py` | なぜなぜ7回完了 + 方法E実装/12体同一性確認 | `OOM (437GB, 実行不能) → 50分/662MB (N=84推定, 同一性100%)` | spec+result: `docs/research/gunshi_nazenaze7_gs_speedup_20260414.md` |
| 2026-04-15 | 軍師 | `scripts/cmd_complete_gate.sh` テスト統合 | Phase 5完了(統合のみ) | 6ファイル→3ファイル, 41テスト維持, 8.3s→8.7s(速度横ばい=保守性改善) | テスト統合spec: `docs/research/gunshi_test_consolidation_spec.md` |
| 2026-04-16 | hayate | `scripts/shutsujin_departure.sh` | Phase 5(計測+実装+検証)。spec事後作成 | `2.43s → 0.17s` (`-92.9%`, `14.1x`) | spec+after: `docs/research/shutsujin_departure_after_20260416.md` |
| 2026-04-16 | 才蔵 | `scripts/parity_check.sh` | Phase 5(計測+実装+検証)。spec先行作成 | `5.50s → 0.02s` (`-99.6%`, `--help` path) | spec: `docs/research/codd_spec_parity_check_20260416.md` |
| 2026-04-16 | hayate | `scripts/ninja_done.sh` | Phase 5(計測+実装+検証)。spec事後作成 | `22ms → 2ms` (usage, `-90.9%`) / `228ms → 168ms` (success path, `-26.3%`) | spec+after: `docs/research/cmd_1965_ninja_done_after_20260416.md` |
| 2026-04-16 | hayate | `scripts/lesson_harvest.sh` | Phase 5(計測+実装+検証)。spec事後作成 | `36.34s → 10.57s` (`-70.9%`, `3.4x`) | spec+after: `docs/research/lesson_harvest_after_20260416.md` |
| 2026-04-16 | kotaro | `scripts/gates/gate_artifact_map.sh` | Phase 5(計測+実装+検証)。spec事後作成 | `967ms → 99ms` (`-90%`, `9.8x`) | spec: `docs/research/codd_spec_gate_artifact_map_20260416.md` |
| 2026-04-16 | hanzo | `scripts/report_merge.sh` | Phase 5(計測+実装+検証)。spec事後作成 | `1947ms → 76ms` (`-96%`, `25.6x`) | spec: `docs/research/codd_spec_report_merge_20260416.md` |
| 2026-04-16 | kagemaru | `scripts/gates/gate_cycle_health.sh` | Phase 5(計測+実装+検証)。spec事後作成 | `793ms → 296ms` (`-63%`, `2.7x`) | spec: `docs/research/codd_spec_gate_cycle_health_20260416.md` |
| 2026-04-16 | tobisaru | `scripts/gates/gate_karo_startup.sh` | Phase 5(計測+実装+検証)。spec事後作成 | `464ms → 225ms` (`-51%`, `2.1x`) | spec: `docs/research/codd_spec_gate_karo_startup_20260416.md` |
| 2026-04-16 | kagemaru | `scripts/ntfy.sh` | Phase 5(計測+実装+検証) | `33ms → 23ms` (`-30%`) | (軽微改善。spec省略) |
| 2026-04-16 | kagemaru | `scripts/karo_workaround_log.sh` | Phase 5(計測+実装+検証) | `61ms → 26ms` (`-57%`, `2.3x`, clean mode) / `70ms → 32ms` (`-54%`, normal mode) | validate_ninja_id task dir loop(basename subprocess×10=45ms)廃止+settings.yaml only+TZ=UTC printf builtin。26/26テストPASS。spec: `docs/research/codd_spec_karo_workaround_log_20260416.md` |
| 2026-04-16 | hayate | `scripts/gates/gate_recalculate_completeness.sh` | Phase 5(計測+実装+検証) | `7.40s(FAIL) → 2.74s(PASS)` (`-63%`) | after: `docs/research/gate_recalculate_completeness_after_20260416.md` |
| 2026-04-16 | kotaro | `scripts/gates/gate_loop_health.sh` | Phase 5(計測+実装+検証) | `287ms → 93ms` (`-67%`, `3.1x`) | (yaml.safe_load→行パーサ。spec省略) |
| 2026-04-16 | tobisaru | `scripts/gates/gate_lesson_health.sh` | Phase 5(計測+実装+検証) | `666ms → 140ms` (`-79%`, `4.75x`) | lessons.yaml awk 15+回→1回/PJ統合+config 1回awk+context synced+unsorted 1awk+float比較4→1awk+notify read 2→1awk+mktemp廃止。全関連テストPASS |

| 2026-04-16 | 軍師 | `scripts/oneshot/cmd_1934_l3_threebody_stability.py` | Phase 5(計測+実装+検証) | `~10min → ~1min` (`10x`, 4851combo) | `_fast_beta`関数追加+evaluate_expanding/WFのnumpy化+load_monthly_returns引数化+COL_RE ①対応。spec: `docs/research/gunshi_cmd1934_scalability_42col_20260416.md` |
| 2026-04-16 | hanzo | `scripts/lesson_effectiveness.sh` | Phase 5(計測+実装+検証) | `30s → 0.33s` (`-98.9%`, `91x`) | bash while-loop×501ファイル逐次処理 → Python3+ThreadPoolExecutor(8並列)。WSL2 I/O並列化で0.33s達成。63/63テストPASS |
| 2026-04-16 | tobisaru | `scripts/gates/gate_workaround_rate.sh` | Phase 5(計測+実装+検証)。spec事後作成 | `user 30ms → 12ms` (`-60% CPU`, `2.5x`) / `real 55ms → 46ms` (`-16%` WSL2 I/O支配) | python3+grep+awk3本 → awk1本統合。cmd_1951基準135ms(14回発火)。38/38テストPASS。spec: `docs/research/codd_spec_gate_workaround_rate_20260416.md` |
| 2026-04-16 | kagemaru | `scripts/model_switch_preflight.sh` | Phase 5(計測+実装+検証)。spec先行作成 | `5483ms → ~1230ms` (`-78%`, `4.5x`) / 本セッション実測 `13183ms → ~1230ms` | 11grep別々→単一正規表現(12.4x)+python3×6→awk(10.5x)+grep -rl→git grep(3.5x)。63/63テストPASS。spec: `docs/research/cmd_1973_model_switch_preflight_speedup.md` |
| 2026-04-16 | saizo | `scripts/hooks/test_hooks.sh` | Phase 5(計測+実装+検証) | `18.07s → 1.93s` (`-89.3%`, `9.4x`) | spec+after: `docs/research/codd_spec_test_hooks_20260416.md` |
| 2026-04-16 | hanzo | `scripts/archive_completed.sh` | Phase 5(計測+実装+検証) | `1073ms → 783ms` (`-27%`) | sed×21→gawk単一pass(A)+grep-rl全走査→REPORT_CACHE直接path(B)+sync_stk+trim_stk Python統合(C)+chronicle早期リターン(D)。980/980テストPASS。spec: `docs/research/codd_spec_archive_completed_20260416.md` |

## 運用

- CoDD系リファクタリングを完了したら、この台帳に1行追加する。
- `Phase到達` は spec only / implementation / after設計書あり など、現物で確認できる到達点を書く。
- `Before→After` は速度・メモリ・同一性など、再発明防止に効く定量差を優先して残す。
