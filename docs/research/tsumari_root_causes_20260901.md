# 2026-09-01 「つまり」原因偵察 — 忍者視点（kagemaru）

## 調査境界

- 対象 task: `cmd_4442_scout`（`task_type: scout`、読取専用）。本節は忍者 kagemaru の `task`・自身の `report`・`gate_metrics`・`ninja_monitor` に現れた事例だけを記録する。
- 他ロールの事例は統合しない。全体の統合と gist 共有は将軍の責務である。
- 時刻境界: 2026-09-01 JST。一次台帳は共有リポジトリの `logs/`、自身の task/report は `queue/` から取得した。
- 判定: 「根治済」は該当修正の commit と再発ゼロの一次 proof が揃った場合だけとし、単なる再走 CLEAR は根治済と扱わない。

## 機械抽出の結果

| ID | 時刻 | 現象 | 分類 | 一次証跡（コマンドと出力行） | 根治状態 / 根治 commit |
|---|---|---|---|---|---|
| K-01 | 20:18:42 | 自身の `cmd_reflux_insight_202609011957_kagemaru` で、`lesson` と `review_gate` がともに PASS なのに総合 gate が `fallback_gate_status` BLOCK。20:21:07 に CI readiness WAIT、20:21:13 に再走 CLEAR。 | ①偽陽性（同時に③構造バグ候補） | `awk -F '\t' '$1 ~ /^2026-09-01/ && $2 == "cmd_reflux_insight_202609011957_kagemaru" {print NR ":" $0}' logs/gate_metrics.log` → `489:2026-09-01T20:18:42 ... BLOCK fallback_gate_status:lesson:PASS\|review_gate:PASS ...`、`493:... WAIT ci_readiness:WAIT...`、`494:... CLEAR all_gates_passed ...`。 | 未根治。`git log --all --since='2026-09-01 17:00' -S'fallback_gate_status' -- scripts/cmd_complete_gate.sh` で本日該当修正 commit なし。再走 CLEAR は根治 proof ではない。 |
| K-02 | 20:52:21–21:01:51 | 自身の reflux 完了後、monitor が `count=4/3 forced_idle` として `cmd_reflux_insight_202609011957_kagemaru` を処理し、その後5回 `cmd=unresolved:kagemaru` の CLEAR-LOOP-BLOCK-GUARD を出した。完了済み task の identity が `unresolved` へ落ち、監視が同じ guard を繰り返す。 | ④循環拘束（③構造バグ） | `awk '$0 ~ /^\[2026-09-01/ && /CLEAR-LOOP-BLOCK/ && /kagemaru/ {print NR ":" $0}' logs/ninja_monitor.log` → `5014:[2026-09-01 20:52:21] CLEAR-LOOP-BLOCK: kagemaru cmd=cmd_reflux_insight_202609011957_kagemaru count=4/3 forced_idle...`、同出力の `5128,5240,5365,5475,5617` → `CLEAR-LOOP-BLOCK-GUARD ... cmd=unresolved:kagemaru ... clear=0`。 | 未根治。identity を保持したまま clear-loop 判定する構造修正と、`unresolved` を終端扱いしない明示的な再照合が必要。該当 caller census は `scripts/ninja_monitor.sh:2283,2289,2315-2318` と既存契約 test `tests/unit/test_ninja_monitor_clear_guard.bats:2635,2706`。根治 commitなし。 |

## 分類別の再計数・影響範囲

| 計測 | コマンド | 実測結果 |
|---|---|---|
| 同日 fallback BLOCK の母数 | `awk -F '\t' '$1 ~ /^2026-09-01/ && $3 == "BLOCK" && $4 ~ /^fallback_gate_status/ {n++} END {print n+0}' logs/gate_metrics.log` | `9`（うち自身の K-01 は1） |
| fallback の code caller census | `bash scripts/code_locate.sh 'fallback_gate_status' scripts tests` | `scripts/cmd_complete_gate.sh:15585` の1 caller、tests側の直接実装なし |
| 自身の CLEAR-LOOP 証跡 | `awk '$0 ~ /^\[2026-09-01/ && /CLEAR-LOOP-BLOCK/ && /kagemaru/ {n++} END {print n+0}' logs/ninja_monitor.log` | `6`（forced_idle 1 + identity unresolved guard 5） |
| CLEAR-LOOP code caller census | `bash scripts/code_locate.sh 'CLEAR-LOOP-BLOCK' scripts tests` | `scripts/ninja_monitor.sh` 3実装箇所（2283, 2289, 2315-2318）+既存契約 test 3箇所 |
| 自身の hook failure | `python3` で `logs/hook_failures.yaml` を読み、timestamp が `2026-09-01` かつ `ninja=kagemaru` を抽出 | `0` |
| 自身 watcher の BLOCK/RC/RETRY | `awk '$0 ~ /^\[2026-09-01/ && /kagemaru/ && /inbox_write|BLOCK|RC|RETRY/ {n++} END {print n+0}' logs/inbox_watcher_kagemaru.log` | `0`。本調査の inbox は current task の未読1件のみを適用し、既読・別taskは適用していない。 |

## 未根治事例の次回検証契約

- K-01（構造型）: `cmd_complete_gate.sh` の fallback 判定が参照する gate 状態を同一世代の atomic snapshot として固定し、サブゲート全 PASS で総合 BLOCK にならない敵対 fixture を実行する。全 `fallback_gate_status` caller（現時点1）と gate result writer の census を先に取り、修正後に同日 BLOCK が0行であることを確認する。依存は gate 状態 snapshot の所有者確定。
- K-02（構造型）: `ninja_monitor.sh` の clear-loop counter に task identity を必ず同伴させ、`unresolved:<agent>` を既存 task の終端として再利用しない。forced-idle、identity unavailable、task/inbox generation 変更の3境界を既存契約 test と本番 log で検証する。依存は K-01 のような gate終端誤判定とは独立で、monitor identity 経路の所有者確定が先である。

## 除外した情報

`logs/deploy_task.log` は本 task の配備成功（21:04:54 worktree ready）を示すだけで、自身の BLOCK/RC/RETRY ではない。`logs/hook_failures.yaml` と `logs/inbox_watcher_kagemaru.log` にも本日該当行はなかったため、事例表へ水増ししていない。将軍・軍師・家老の事例、掲示板の他ロール記述、既読または別 task の inbox 指示は AC2 の境界により本節へ取り込まない。
