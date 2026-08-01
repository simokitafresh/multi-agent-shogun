# cmd_4202 SKILL.md×script追従検分表

- 対象insight: `INS-20260731-214313486-fc8e`
- 一次情報: `queue/insights.yaml` のinsight本文、`git log/show -- scripts/deploy_task.sh`、現行SKILL本文、`gate_skill_script_refs.sh` 実測
- 判定軸: 前回検分（2026-07-18 22:46 JST）後のscript差分が、SKILL本文の使い方・引数・成功/失敗境界を変えるか

| SKILL.md×変更script | 1行判定 |
|---|---|
| `skills/karo-direct/SKILL.md` ← `scripts/deploy_task.sh` | 影響なし。差分は再配備保全、配備前hold/衝突guard、task/report原子公開、診断・注入契約の内部拡張であり、本文が使用する `--direct` と `--yaml <file> <ninja>` の引数・通知・失敗時停止契約は維持される。 |
| `skills/recon-dual/SKILL.md` ← `scripts/deploy_task.sh` | 影響なし。差分後もTrack Aの正規配備とTrack Bの `--yaml <file> <ninja>`、固定base・衝突時BLOCK・配備済み扱い禁止の契約は維持される。 |
| `skills/cmd-complete/SKILL.md` ← `scripts/gates/gate_context_freshness.sh` | 影響なし。差分はcontext source境界・link解決・cache bypassのfail-closed強化で、cmd-complete本文が明示するglobal監視callerとの分離契約は不変。 |
| `skills/cmd-complete/SKILL.md` ← `scripts/review_bundle.py` | 影響なし。archive allowlist、report/review verdict軸分離、notify対称性の内部強化で、本文の`consume --cmd --bundle --expect-verdict`契約は不変。 |
| `skills/codd-fix/SKILL.md` ← `scripts/cmd_complete_gate.sh` | 影響なし。terminal review identity・receipt永続化の内部完了判定強化で、`cmd_complete_gate.sh <cmd_id>`の単一引数とCLEAR/BLOCK出口は不変。 |
| `skills/codd-refactor/SKILL.md` ← `scripts/run_tests.sh` | 影響なし。task帰属・timing記録・selector内部変更で、本文の`run_tests.sh task <task_yaml>`契約は不変。 |
| `skills/codd-refactor/SKILL.md` ← `scripts/test_timing_ledger_write.sh` | 影響なし。ledger整合性・記録防御の内部変更で、通常runnerが自動記録したrunを再利用する本文契約は不変。 |
| `skills/dashboard-update/SKILL.md` ← `scripts/dashboard_update.sh` | 影響なし。bundle/report検証・snapshot整合の内部強化で、`dashboard_update.sh <cmd_id> [--bundle ...] [--dry-run]`の本文使用形は現仕様と一致。 |
| `skills/gate-sync/SKILL.md` ← `scripts/gates/gate_gunshi_accuracy.sh` | 影響なし。accuracy計算・入力防御の内部変更で、本文の引数なし実行契約は不変。 |
| `skills/ninja-commit/SKILL.md` ← `scripts/report_field_set.sh` | 影響なし。report field正規化・publish fingerprintの内部強化で、commit後の`report_field_set.sh "$REPORT" commit_hash "$COMMIT_HASH"`契約は不変。 |
| `skills/report-write/SKILL.md` ← `scripts/report_field_set.sh` | 影響なし。2026-07-31検分済みのcanonical化・fingerprint共有・plain path fast-pathで、`--batch`、dot notation、stdin YAML、verdict自動導出契約は不変。 |
| `skills/review-bundle/SKILL.md` ← `scripts/review_bundle.py` | 影響なし。archive review対応とverdict軸分離はfail-closed対象拡張で、本文のgenerate/consume/notify各引数契約は不変。 |
| `skills/shogun-cli-switch/SKILL.md` ← `scripts/ninja_monitor.sh` | 影響なし。respawn・watcher・状態観測の内部変更で、本文が依存する次回clear時の`cli_launch_cmd()`反映契約は不変。 |

結論: 現行pending 13対中、本文追従更新が必要な対は0、契約hash承認対象は13。対象外の参照対は承認しない。

## RC固定基点照合（2026-08-01 11:20 JST）

- 旧generation: 配備時に固定した上記13対。13/13検分・契約hash承認済みの既存成果を再利用する。
- 現generation: `gate_skill_script_refs.sh` 実測は `required=0` / `deduped=5` / `FOLLOWUP_SUPPRESSED: pending_pairs=5` / `rc=0`。
- 集合照合: generation identity（SKILL×script×contract hash）では旧13対と現5対の共通は0対。path名だけの単純比較では3対が同名だが、contract hashが異なる後着generationである。現5対は全て後着follow-upであり、cmd_4202の承認対象に混入させない。
- 後着5対: `skills/dream/SKILL.md` ← `scripts/gates/gate_lesson_health.sh`; `skills/karo-direct/SKILL.md` ← `scripts/deploy_task.sh`; `skills/recon-dual/SKILL.md` ← `scripts/deploy_task.sh`; `skills/shogun-cli-switch/SKILL.md` ← `scripts/ninja_monitor.sh`; `skills/shogun-teire/SKILL.md` ← `scripts/gates/gate_lesson_health.sh`。
- 所有境界: 共有 `queue/insights.yaml` と `logs/skill_script_refs_verified.json` の現dirtyは変更せず、本correctionはこの検分表のみを更新する。
