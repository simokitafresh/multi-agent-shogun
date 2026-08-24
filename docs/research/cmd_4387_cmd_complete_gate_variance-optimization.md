# cmd_4387 cmd_complete_gate 変動是正

## 固定条件と一次データ

- 対象: `scripts/cmd_complete_gate.sh`、同一repo・同一source-only publication契約。
- before source: `logs/cmd_complete_gate_details.log` / `logs/cmd_complete_gate_subphases.log`（2026-08-24）。
- after source: 現物fixture、同一receipt・remote evolution・同一source commitで再実行。
- 品質境界: 検査項目削除0、source-only push回数1、dirty source path保持、receipt exact-match再利用。

## Before / after

| 対象 | before実測 | after実測・証跡 | 判定 |
|---|---:|---:|---|
| `post_source_checks` 残余 | 325.352s (`cmd_karo_ci_fix_32680992968_postclear_notification_contract`)、386.702s (`cmd_reflux_insight_202608241436_hayate`) | `report_commit_main_ancestry.resolve_state`、`capture_durable_writer_snapshot.tracked_delta`、`durable_writer_wait.tracked_delta`を内部計装。snapshot fixtureは変更path 1件だけを検出 | PASS: 検査境界維持 |
| `self_grade` 遅延経路 | 54.055s / 56.600s (`self_grade_start`) | phase-union fallbackを1回のNUL-safe `git log --name-only`へ統合。direct/phase-unionを別detail labelで記録 | PASS: 検査対象維持 |
| tracked runtime lock | `runtime_publish.tracked_runtime_lock_wait=552.752s` | local generation admission後、`remote_source_push`前にlock解放。remote evolution fixtureでreceipt再利用、push回数 `1` | PASS: network待ちを共有lockから分離 |
| receipt再利用 | remote evolution後もfetch前ancestor未解決でsource-equivalent経路へ遷移 | fetch後にreceipt+ancestorを再検証し、`durable source-only publication receipt exact-match+ancestry after fetch`でSKIP | PASS: 二重pushなし |
| durable snapshot | 全tracked fileを前後SHA-256（最大52.152sの既存detail） | staged/unstaged変更path＋HEAD差分のみ比較。変更path exact fixture `context/semantic-map.md`、commit済みclean path `tracked.txt`とも検出 | PASS: path manifest契約維持 |

## v1.0 — 2026-08-24T17:18:00+09:00

- `scripts/cmd_complete_gate.sh`: 詳細計装、phase-union batch化、sparse durable snapshot、runtime lock粒度是正、fetch後receipt再検証。
- `tests/unit/test_cmd_complete_gate.bats`: lock境界契約を「local generation serialized / network unlocked」へ更新。
- 局所fixture: `snapshot_delta=1 exact_path=1`、`head_delta=1 exact_path=1`。
- 選択runner: `bash scripts/run_tests.sh file tests/unit/test_cmd_complete_gate.bats` は171件PASS、既存receipt試験#172は修正前にtimeout。修正後の同試験再実行を最終checkpointとする。

## 因果

`[[cmd_4387]] -> [[post_source_checks/self_grade/runtime_lockの変動3要因]] -> [[計装・lock粒度是正・receipt再検証]]`
