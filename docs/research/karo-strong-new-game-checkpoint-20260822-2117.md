# 家老 強くてニューゲーム復帰点 — 2026-08-22 21:17 JST

## 0. 正本宣言

- role: `karo`
- source: 殿指示「今 クリアされても今すぐニューゲームができるようにせよ」
- status: `ready_for_new_game`
- current_project: `dm-signal`
- current_active_cmd: `none`
- origin: `[[殿指示_強くてニューゲーム_20260822_2113]] -> [[GA491_ancestry_without_blob_gap]] -> [[terminal_blob_parity_gate]] -> [[strong_new_game_completion_contract]]`
- 本ファイルは保存時点の復帰正本。数値は未来値として流用せず、復帰後に一次再計測する。

## 1. 復帰直後の順序

1. AGENTS.mdの家老Recoveryを省略せず完走する。
2. `sha256sum docs/research/karo-strong-new-game-checkpoint-20260822-2117.md` を `queue/compact_state/karo.yaml` の `target_sha256` と照合する。
3. `queue/karo_snapshot.txt`、`queue/pending_decisions.yaml`、`queue/inbox/karo.yaml` を再読する。
4. inboxは `read:false` のIDだけ処理し、`inbox_mark_read.sh karo <msg_id>` で個別既読化する。
5. active taskがなければ新作業を捏造せずidleへ戻る。新cmdがあれば正本cmd/taskから再開する。

## 2. 保存時点の陣形

- `karo`: idle、inbox unread 0。
- active ninja task: 0件。
- hayate: `cmd_karo_ci_fix_32544223690_task_contract_shebang_normal` done。
- kagemaru: `cmd_karo_hotfix_doc_lane_stale_alert_revalidate_normal` idle、GATE CLEAR/archive済み。
- hanzo: `cmd_reflux_insight_202608221206_hanzo_exact` done、GATE CLEAR/archive済み。
- saizo: `cmd_karo_hotfix_ga491_terminal_blob_parity_normal` idle、GATE CLEAR/archive済み。
- tobisaru: `cmd_reflux_insight_202608221335_tobisaru_exact` idle、GATE CLEAR/archive済み。pane busy表示はtask不一致のstale補足を適用せず確認していただけで、実作業なし。
- kotaro: `cmd_reflux_insight_202608212332_kotaro_exact` failedの履歴状態。新しい未読・再開指示なし。勝手に上書きしない。

## 3. Git / remote / CI

- baseline local HEAD before checkpoint commit: `cdc349017773032a117e2f1d7591009572223979`
- origin/main: `37d27d146a8043e64486bc84b9ddaca9d3768ee2`
- relation at save before checkpoint commit: remote-only 0 / local-only 9。localはremoteを包含。
- tracked worktree: clean。
- user-owned untracked: `tests/unit/test_cmd_complete_gate_source_publish.bats`。触れない・混入させない。
- latest remote CI: run `32557279449`, head `37d27d146a8043e64486bc84b9ddaca9d3768ee2`, conclusion `success`。
- 広域local履歴をそのままpushしない。必要成果だけisolated clone/source-only snapshotで公開し、remote blobを終端検査する。

## 4. 今回確立した強い不変量

### 4.1 祖先性だけでは成果反映を証明しない

- GA-491でGA-490 doc commitsはHEAD祖先だったが、対象4pathはblob一致0/4だった。
- 根因: ancestry-only terminal checkは、後続treeが成果pathを旧blobへ戻した事実を検出できない。
- 根治commit: `8fed7e2df6da51337f30ea892d2d88e08e035e62`。
- 実装: `scripts/cmd_complete_gate.sh` が通常不変pathについてsource commit blobとremote expected head blobの一致をCLEAR条件にする。
- mutable operational path (`queue/*`, `logs/*`, lessons等) はexact blob比較せず既存field-aware/ID単調性laneを使う。
- tests: 265/265 PASS、SKIP 0。
- terminal Gate: GATE CLEAR、`cmd-complete` COMPLETE、archive済み。

### 4.2 stale raw ALERTは通知直前に現物再照合する

- rootfix commit: `af59c82f46213731695e6c78364b43149038171d`。
- `gate_context_freshness.sh` はraw ALERT cutoff日と対象file先頭metadata日を通知直前に再読する。
- metadataが新しければbulletinとdedupe markerを生成しない。
- 真のALERT、metadata欠落/不正、通知失敗は既存fail-closedを維持。
- tests: 18/18 PASS、SKIP 0。

### 4.3 insightはIDだけでなくresolved fieldも単調に保つ

- 保存時点: live 136 IDs、unique 136、重複0。remoteは保存直前の再計測対象であり、本値を未来へ流用しない。
- 重要対象3件はlive/remoteともresolved:
  - `INS-20260822-063624178-9fac`
  - `INS-20260822-064517955-347a`
  - `INS-20260822-110452842-73f5`
- `restore_insights_from_corrupt.sh --id-union` はID消失を防ぐが、入力優先順でpendingがresolvedを上書きし得る。合流後は対象status/resolved_reason/action_artifact/resolved_atを必ず再検査する。
- stale liveは `ninja_scope_commit.sh -- queue/insights.yaml` で収束する。scope取得時に差分0なら追加commitしない。

## 5. GA-491 doc lane復旧の終端値

- recovery commit: `928dfcc2603246a6ccac3a3a2dbb998362beb107`。
- terminal knowledge commit: `2d605c473d5ab7b0217ca9a8ab6a931407e33a4b`。
- local/remote blob一致4/4:
  - `context/dm-signal-core.md` = `b6337ca0a7da422c57624fc4c0c40737dfd9441f`
  - `context/dm-signal-ops.md` = `239a7abb3a678012c1bf9f959c77795e3b63b228`
  - `context/dm-signal-research.md` = `f4ced60bd2cd4796a42735846a5e982303337365`
  - `context/infrastructure.md` = `df22392633c23387a36b852f6c20916e9339c166`
- terminal gate blobs一致2/2:
  - `scripts/cmd_complete_gate.sh` = `08d03f2d35d182d78329fe6689699ba385d60fb7`
  - `tests/unit/test_cmd_complete_gate.bats` = `7a37b8a56e5c8b93366b94a00452a4bd55a97d9b`
- cache無効 `gate_context_freshness.sh`: 総合判定OK。

## 6. 未決裁定

- active/shelved IDs: `PD-038`, `PD-104`, `PD-107`, `PD-110`, `PD-114`, `PD-135`, `PD-137`。
- 復帰後は `queue/pending_decisions.yaml` の現物を再読し、ここにあるstatusを未来値として使わない。

## 7. 禁則

- F001: 家老が実装を抱えない。実装は忍者へ配備し、家老は診断・分解・レビュー・検証に専念する。
- F002: 通常の殿直報は禁止。将軍宛はbulletin、殿向けはdashboard経路。
- F003: Task agentを使わない。
- F004: polling loopを作らない。
- 運用YAMLへyaml.dump/safe_dumpを使わない。
- report YAMLは`report_field_set.sh`、共有YAMLは正規helperを使う。
- remote ancestry PASSだけで完了しない。通常pathはblob一致、mutable pathはfield-aware不変量を確認する。

## 8. 強くてニューゲーム二値条件

- [x] 復帰正本に役割・禁則・現task・次行動がある。
- [x] active task 0件、karo unread 0件を一次確認した。
- [x] localがremoteを包含し、tracked worktree cleanを確認した。
- [x] user-owned untracked pathを保護対象として記録した。
- [x] 最新remote CI successを記録した。
- [x] insights ID/unique/resolved状態を記録した。
- [x] doc 4pathとterminal gate 2pathのblob終端値を記録した。
- [x] pending decision IDsを記録した。
- [x] 本ファイルSHA256を計算し `queue/compact_state/karo.yaml` へ反映する。
- [x] 三層記憶へ本checkpoint pointer/hashを貫通する。
