# 家老 強くてニューゲーム復帰点 — 2026-08-27 08:58 JST

## 0. 正本宣言

- role: `karo`
- status: `ready_for_new_game_with_active_tasks`
- finalized_at: `2026-08-27T08:58:42+09:00`
- updated_at: `2026-08-27T09:14:00+09:00`（後着inbox、T47 FAIL、T21再配備、小太郎完了を追記。finalized_atは歴史として変更しない）
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
- active/assigned task count: `1`（hanzo T21 acknowledged）
- hayate:
  - task: `cmd_karo_hotfix_reflux_idle_anchor_20260827_normal`
  - status: `failed`
  - report: `queue/reports/hayate_report_cmd_karo_hotfix_reflux_idle_anchor_20260827.yaml`
  - report status/verdict: `failed / FAIL`
  - worktree: `/tmp/shogun-task-worktrees/hayate_204c6a76a6b02702`
  - result: 実装commit=`a40800476ec6f6695a0e310aa33432c7e059d9fb`（前段`05d798238afd215798a7703e86820e6373fe21d0`）。AC1のdurable anchor回帰とtask selectorはPASS/SKIP0。AC2の修正後live再配備が未観測でBLOCK。次reflux実配備1件を一次観測してreview→GATEを閉じる。
- kotaro:
  - task: `cmd_reflux_insight_202608270814_kotaro_exact`
  - status: `done`
  - report: `queue/reports/kotaro_report_cmd_reflux_insight_202608270814_kotaro.yaml`
  - report: `gate_report_format PASS`、commit=`2dff8b3cca8f393d2104d9f01f569f655249b445`、fingerprint=`191d27b82501f0255f5d08c9a6b80ce2371e0a79e950c1cb26e76f3ea66c80ee`。軍師LGTM受領、家老ACCEPT→GATE待ち。
  - draft review: 軍師`APPROVE`、task fingerprint=`36ce6ad7`
  - live evidence: 対象insight解消処理中。公式inventory snapshotが2分超の長時間経路で待機中。
- kagemaru/hanzo/saizo/tobisaru: `idle`
- hanzo:
  - task: `cmd_karo_hotfix_t21_codex_delivery_read_transition_20260826_normal`
  - status: `assigned`（09:09配備、capture-paneでnudge到達後Working確認）
  - source artifact: `/tmp/shogun-task-worktrees/kagemaru_d795c554d7f22909`の保全差分2ファイル。
  - differential AC: `tests/unit/test_inbox_write_codex_delivery.bats`の旧pane-success契約1件をexact message ID read遷移へ同期し、対象FAIL0/SKIP0で3ファイルcommit。
- kagemaru/saizo/tobisaru: `idle`

## 3. タスクマップの正しい読み方

- T12: 真に未着手。理由欄の「次回cmd_publish時にstdout保存」は硬い依存ではなく受動待機。復帰後はcontrolled publishを起こして13分の内訳を即計測する。待つな。
- T40: マップは`[ ]`だが実態は着手済み。05:39〜07:00にrefluxを5件配備・完了。T45が回転計測、T47が空白根治を担う。表示鮮度不良を未着手理由に使わない。
- T47: 実装・回帰はPASS、修正後live再配備未観測で`failed/FAIL`。次reflux 1件を一次観測してAC2を閉じ、review→GATEへ進む。
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

- HEAD: `1ffa1584502330e65e949358ca8abb1211667743`
- origin/main: `1ffa1584502330e65e949358ca8abb1211667743`
- relation: behind=`0` / ahead=`0`
- 直近push実測: `3d368515b` 08:57:05→08:57:10=`5s`、`1f0a3e83c` 08:57:23→08:57:28=`5s`。
- checkpoint追加後は新commitが増えるため、復帰時に必ず再計測する。

## 6. 在庫・未決裁定

- insights: total=`465`, pending=`104`, resolved=`361`, unique IDs=`465`。
- pending decisions: `PD-104, PD-107, PD-110, PD-114, PD-135, PD-137`。
- T40の在庫数は流入で増減する。pending数だけで未実行と判定せず、`REFLUX-AUTO-DEPLOY/DONE`ログと解消IDを数える。

## 6.1 後着下知キュー（未配備を消すな）

- T22: 飛猿pre-push cache/tree-hash成果worktreeを確認し、使えるならcommitだけ再配備、不可ならfailedクローズ。
- T10: 本日GATE CLEAR timing logの完走run件数を数え、1件以上なら本質短縮をidle忍者へ再配備。
- T08: converge ours採用/theirs破棄のr2成果を確認し、未実施ならidle忍者へ再配備。
- T50: insights daemon書込み後のdirty-guard毎周期再発を同一transaction commitまたはstatus差分許容で根治。
- T51: pre-push成功時も`logs/defense_overhead.jsonl`へwall/affectedを記録し、300秒超WARN。
- T49: `hayate_report_cmd_alias.yaml`偽抽出へ実在チェックを追加。
- infra critical: T21配備中に`semantic_index.py`が`sqlite3.DatabaseError: database disk image is malformed`。task配備はfail-open継続したが、記憶DB正本/キャッシュのどちらが破損したかを復帰後に一次診断し、迂回せず根治する。

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
2. 小太郎reflux報告を軍師review/GATEで閉じる。target占有は解放済みなので次周期`REFLUX-AUTO-DEPLOY` 1件を確認する。
3. そのlive配備をT47 AC2証拠としてreview→GATEを閉じる。
4. 半蔵T21差分RCをcommit/report/GATEまで閉じる。
5. idle枠へT50/T51/T49を先に配備し、枠解放後T22/T10/T08を続ける。
6. T12をcontrolled publishで着手し、cmd_4401 stdoutを恒久ログへ保存して13分を分解する。
7. origin差分は1commitずつpushし、各hash・開始/終了時刻・wall秒を記録する。

## 9. 二値条件

- [x] role・禁則・active task・report・次行動を記録。
- [x] inbox unread=`0`を一次確認。
- [x] active task=`2`をtask YAMLとcapture-paneで確認。
- [x] Git relation=`0 0`を一次確認。
- [x] insights在庫とpending decisionsを一次確認。
- [x] T12/T40/T47のマップ表示と実態差を記録。
- [x] checkpoint SHA256をcompact_stateへ反映（本節確定後のhashを使用）。
- [x] 三層記憶へpointer/hashを貫通（記憶DB+semantic concept+Obsidian origin）。
