# CoDD Refactor Registry

CoDDリファクタリングの実績台帳。車輪の再発明を防ぐため、「いつ」「誰が」「何を」「どこまで進めたか」を記録する。

| 日付 | 実施者 | 対象スクリプト/領域 | Phase到達 | Before→After | spec/after設計書パス |
|------|--------|---------------------|-----------|--------------|----------------------|
| 2026-04-15 | 軍師 | `scripts/deploy_task.sh` | Phase 6完了 | `2639ms → 88ms` (`-97%`) | spec: `docs/research/gunshi_deploy_task_refactor_spec.md` / after: `docs/research/deploy_task_after_20260415.md` |
| 2026-04-14 | 軍師 | `scripts/gates/gate_gunshi_startup.sh` / `scripts/gates/gate_shogun_startup.sh` / `scripts/gunshi_gate_sync.sh` | なぜなぜ7回完了 + 高速化適用済 | `14.9s → 3.2s` (`4.7x`) | spec+result: `docs/research/gunshi_idle_startup_speedup_20260414.md` |
| 2026-04-14 | 軍師 | `scripts/analysis/grid_search/run_077_*` / `scripts/analysis/grid_search/gs_vectorized_subset.py` | なぜなぜ7回完了 + 方法E実装/12体同一性確認 | `OOM (437GB, 実行不能) → 50分/662MB (N=84推定, 同一性100%)` | spec+result: `docs/research/gunshi_nazenaze7_gs_speedup_20260414.md` |
| 2026-04-15 | 軍師 | `scripts/cmd_complete_gate.sh` テスト統合 | Phase 5完了(統合のみ) | 6ファイル→3ファイル, 41テスト維持, 8.3s→8.7s(速度横ばい=保守性改善) | テスト統合spec: `docs/research/gunshi_test_consolidation_spec.md` |
| 2026-04-16 | 忍者kotaro | `scripts/gates/gate_artifact_map.sh` | 高速化実装完了 | `967ms → 99ms` (`-90%`, `9.8x`) | ループ内echo\|awk×3(168サブシェル)→awk1パス+pure bash展開 |

## 運用

- CoDD系リファクタリングを完了したら、この台帳に1行追加する。
- `Phase到達` は spec only / implementation / after設計書あり など、現物で確認できる到達点を書く。
- `Before→After` は速度・メモリ・同一性など、再発明防止に効く定量差を優先して残す。
