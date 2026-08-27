# 家老 強くてニューゲーム復帰点 — 2026-08-27 08:58 JST

## 0. 正本宣言

- role: `karo`
- status: `ready_for_new_game_with_active_tasks`
- finalized_at: `2026-08-27T08:58:42+09:00`
- origin: `[[殿指示_今クリアされても今より強くてニューゲーム_20260827_0856]] -> [[T40_reflux実回転]] -> [[T47_idle起点固定hotfix]] -> [[strong_new_game_completion_contract]]`
- 本ファイルは保存時点の復帰正本。数値・ペイン・Git・inboxは復帰後に一次再計測し、未来値として流用しない。

## 1. 復帰直後の絶対順序

1. AGENTS.mdの家老Recoveryを全手順完走する。
2. 本ファイルのSHA256を`queue/compact_state/karo.yaml.target_sha256`と照合する。
3. `queue/inbox/karo.yaml`の`read:false`をID単位で処理し、`inbox_mark_read.sh karo <msg_id>`で個別既読化する。
4. `queue/tasks/hayate.yaml`と`queue/tasks/kotaro.yaml`を再読し、report template・task worktree・capture-paneを一次確認する。
5. `git rev-list --left-right --count origin/main...HEAD`を再計測する。差分はfirst-parent oldest-firstで1本ずつpushし、各push後に再計測する。
6. `queue/shogun_todo_map.md`を読み、表示とtask/log実態を突合する。`[ ]`を未着手と即断しない。

## 2. 保存時点の陣形

- karo inbox unread: `0`
- active task count: `2`
- hayate:
  - task: `cmd_karo_hotfix_reflux_idle_anchor_20260827_normal`
  - status: `in_progress`
  - report: `queue/reports/hayate_report_cmd_karo_hotfix_reflux_idle_anchor_20260827.yaml`
  - report status/verdict: `pending / empty`
  - worktree: `/tmp/shogun-task-worktrees/hayate_204c6a76a6b02702`
  - live evidence: `scripts/ninja_monitor.sh`を変更中。選択2 filesのrun_tests完走証跡あり、ペインはWorking。
- kotaro:
  - task: `cmd_reflux_insight_202608270814_kotaro_exact`
  - status: `in_progress`
  - report: `queue/reports/kotaro_report_cmd_reflux_insight_202608270814_kotaro.yaml`
  - report status/verdict: `pending / empty`
  - draft review: 軍師`APPROVE`、task fingerprint=`36ce6ad7`
  - live evidence: 対象insight解消処理中。公式inventory snapshotが2分超の長時間経路で待機中。
- kagemaru/hanzo/saizo/tobisaru: `idle`

## 3. タスクマップの正しい読み方

- T12: 真に未着手。理由欄の「次回cmd_publish時にstdout保存」は硬い依存ではなく受動待機。復帰後はcontrolled publishを起こして13分の内訳を即計測する。待つな。
- T40: マップは`[ ]`だが実態は着手済み。05:39〜07:00にrefluxを5件配備・完了。T45が回転計測、T47が空白根治を担う。表示鮮度不良を未着手理由に使わない。
- T47: 疾風へ07:39配備済みで現在`in_progress`。idle起点をtask idle遷移時刻等へ固定し、監視再起動で600秒計時が巻き戻らないこと、次配備が600秒+1周期以内であることを検証中。
- タスクマップ正本: `queue/shogun_todo_map.md`、HTML: `docs/dashboard/shogun-todo-map.html`。

## 4. 今回強くなった点

- inbox優先: nudge受領時は作業中でも即読み、取得済みIDだけを個別既読化する。
- push最小単位: first-parent oldest-firstで1commitずつpushし、毎回rev-listを再計測する。直近実測は各5秒、最終`0 0`。
- reflux実回転: picker先頭詰まりを`5a9f583b9`で根治後、5件連続配備を実証。
- reflux dirty-guard: semantic/index writerの変更で配備BLOCKが再発する。dirty通知受領時は差分主体を確認し、`ninja_scope_commit.sh`専用経路または既存auto-commitの収束を確認してから再試行する。巻戻し禁止。
- T47配備空白: 07:00 DONE後07:31にidle trackingが再開始し、6名idleでも30〜40分空白となる構造をtask化。単なる監視ではなく永続起点へ修正中。
- CI owner heartbeat: `cmd_karo_ci_fix_33014653183_owner_heartbeat_20260827`はcase103秒境界raceをdeadline polling化し、GATE CLEAR・archive・ntfyまでCOMPLETE。
- orphan test: `8c09923f8`でrun_tests子孫reap+fixture root固定。長時間bats自己増殖の根を断った。D006により家老はkillしない。
- T25動的baseline契約: `77107a355`で「固定基準値」ではなく同一環境before→after自己計測へ変更し、誤FAILを防いだ。
- 偵察契約: `06ddbc988`でrecon/scoutはfinding必須、通常commit契約の誤適用を除外。
- task/report SHA: task worktreeのroot commitとshared main integration commitを混同しない。report rootはtask worktree HEAD、shared統合はsummary/cross-repo証跡へ残す。

## 5. Git / remote

- HEAD: `1f0a3e83c54534c2050e11cc27827cd59af4163f`
- origin/main: `1f0a3e83c54534c2050e11cc27827cd59af4163f`
- relation: behind=`0` / ahead=`0`
- 直近push実測: `3d368515b` 08:57:05→08:57:10=`5s`、`1f0a3e83c` 08:57:23→08:57:28=`5s`。
- checkpoint追加後は新commitが増えるため、復帰時に必ず再計測する。

## 6. 在庫・未決裁定

- insights: total=`465`, pending=`104`, resolved=`361`, unique IDs=`465`。
- pending decisions: `PD-104, PD-107, PD-110, PD-114, PD-135, PD-137`。
- T40の在庫数は流入で増減する。pending数だけで未実行と判定せず、`REFLUX-AUTO-DEPLOY/DONE`ログと解消IDを数える。

## 7. 禁則

- F001: 家老が通常実装を抱えない。hotfix/CI修正は`karo-direct`でidle忍者へ配備する。
- F002: 将軍宛報告はbulletin。殿向け情報はdashboard経路。ただし殿の直接指示には直接応答する。
- F003: 通常の人間操作押し返し禁止。可逆操作は自走する。
- F004: pollingで待ち続けない。60秒以内に進捗を伝え、独立作業を進める。
- 運用YAMLへ`yaml.dump`/`safe_dump`禁止。reportは`report_field_set.sh`、共有YAMLは正規helperを使う。
- `queue/insights.yaml`の後着差分を削除・巻戻し・広域上書きしない。
- `git reset --hard`、`git restore .`、`git clean -f`、kill系は禁止。

## 8. 復帰後の次行動

1. inbox未読を先に処理。
2. 疾風T47のtest/commit/reportを回収し、軍師LGTM→家老ACCEPT→`cmd-complete`まで終端。
3. 小太郎reflux報告を回収し、同じレビュー/GATE経路で終端。
4. T12をcontrolled publishで着手し、cmd_4401 stdoutを恒久ログへ保存して13分を分解する。
5. T40はreflux回転を継続し、マップ表示を`[~]`へ是正する。
6. origin差分は1commitずつpushし、各hash・開始/終了時刻・wall秒を記録する。

## 9. 二値条件

- [x] role・禁則・active task・report・次行動を記録。
- [x] inbox unread=`0`を一次確認。
- [x] active task=`2`をtask YAMLとcapture-paneで確認。
- [x] Git relation=`0 0`を一次確認。
- [x] insights在庫とpending decisionsを一次確認。
- [x] T12/T40/T47のマップ表示と実態差を記録。
- [x] checkpoint SHA256をcompact_stateへ反映（本節確定後のhashを使用）。
- [x] 三層記憶へpointer/hashを貫通（記憶DB+semantic concept+Obsidian origin）。
