# 家老 強くてニューゲーム復帰点 — 2026-08-27 21:26 JST

## 0. 正本宣言

- role: `karo`
- status: `ready_for_new_game_cutover_pending`
- finalized_at: `2026-08-27T21:26:03+09:00`
- source: 殿指示「いまクリアされても今より強くてニューゲームできるようにせよ」
- origin: `[[殿指示_強くてニューゲーム_20260827_2125]] -> [[9p_root_fix_cutover]] -> [[relocate_after_final_rsync]] -> [[strong_new_game_completion_contract]]`
- 本ファイルは保存時点の復帰正本。Git・CI・task・pane・inboxは復帰後に一次再測定し、未来値として流用しない。

## 1. 復帰直後の絶対順序

1. AGENTS.mdの家老Recoveryを全手順完走する。
2. 本ファイルのSHA256を`queue/compact_state/karo.yaml.target_sha256`と照合する。
3. `queue/inbox/karo.yaml`の`read:false`をID単位で処理する。
4. 6忍者のtask YAMLとpaneを一次確認する。保存時点は全員idleだが再測定必須。
5. `git fetch origin main`の成功を確認してから`git rev-list --left-right --count origin/main...HEAD`を測る。
6. relationが`0 0`でなければcutoverを実行しない。dirty ownerを確認し、force/rebase/reset/revertで消さない。
7. `bash scripts/migrate_to_ext4_cutover.sh --dry-run`を実行し、idle/pane/git/crontab/relocate予定を確認する。
8. dry-run PASSを掲示板へ報告し、殿の実切替1行へ渡す。家老が勝手にtmux再起動しない。

## 2. 保存時点の一次状態

- karo inbox unread: `0`
- 6忍者task: `idle 6/6`、task_id空。
- active implementation/review task: `0`
- command queue非終端: `cmd_4367`, `cmd_4368`の2件。両方report PASS済みで、T79凍結解除後のT88 report-only完了処理へ明示移管済み。
- reflux: `queue/gates/reflux_auto_deploy.paused`実在。cutoverまで解除しない。
- Git保存時点:
  - local HEAD: `0dfb68b46dfeda8d7e4d91b48c263c080d68963e`
  - origin/main: `ffd5037b294772c479f04f4ecbfd0658b6197f9b`
  - relation: origin-only=`4` / local-only=`1`
  - unpushed first-parent=`1`
  - dirty: `context/cmd-chronicle.md`, `context/semantic-map.md`, `docs/semantic-index/index.md`, `logs/karo_workarounds.yaml`, `projects/dm-signal/lessons.yaml`, `projects/infra/lessons.yaml`, `queue/insights.yaml`, `queue/session_alerts_shogun.txt`, `queue/shogun_to_karo.yaml`, `skills/report-write/SKILL.md`。
- origin CI: run `33071208812`, head `ffd5037b2`, conclusion `success`。
- insights: total=`556`, pending=`119`。T79凍結中は自動配備0が正しい。cutover後に再開。
- pending decisions: `PD-104, PD-107, PD-110, PD-114, PD-135, PD-137`。`PD-038`はshelvedで未決扱いしない。
- startup gate: deepdive PASS、queue parse PASS、failed_unclosed=0、completed_unarchived=0、三層memory health PASS。残ALERT=`completed rework自動記録欠落11件`。

## 3. 9p根治の到達点

- `cmd_4408` GATE CLEAR。ext4 clone、cutover/rollback、比較計測まで完了。
- CI REDの真因は`tests/unit`消失ではなくtiming ledger `241`対inventory `242`、欠損`test_migrate_to_ext4.bats` 1件。
- fixはorigin `73f6c7a83`へ到達し、run `33067975881`でunit全9 shard・compat・E2E・integration・lintが全success。
- cutover最終rsyncがclone-only置換commitを旧内容へ戻す欠陥を検出。
- `cmd_karo_hotfix_cutover_relocate_20260827` GATE CLEAR。origin実装`f6348f9fa`相当、report commit`5efc1f0cb`。
- `migrate_to_ext4_relocate.sh`を新設し、final rsync直後にNEW_ROOT上で旧絶対パスを冪等置換する。
- 実測: tracked scope `54 files / 758 occurrences`、`.claude/settings.json=10`。下知の`43/103`は旧clone commitの差分母集団で、現HEAD対象集合とは別。
- relocate後remaining=0、2回目changed=0、対象runner=5/5 PASS・SKIP0、dry-run副作用0。
- 保存時点で実cutoverは未実行。残る硬い前提はGit `0 0`とdry-run PASSのみ。

## 4. 今回強くなった点

1. **pushを待たない**: 実装commitと権限があるなら即push。レビュー待ちをpush待ちへ変換しない。
2. **到達判定**: `git fetch`成功確認→remote側同名/同blob探索→ancestry判定。local比較だけで偽CLEAR/偽未到達を断定しない。
3. **push単位**: 「1 commit」はoriginを包含するff可能単位。merge commitは1単位。originを含まない古いfirst-parent SHAは個別push不能。
4. **converge**: 最新origin起点の隔離worktreeでlocal HEADをsecond-parent mergeし、first-parent差1を通常pushする。runtime publisher終端前に作るとremote前進で再作成が必要。
5. **shared main保全**: `safe_shared_main_ff.sh`を使う。dirty overlap時はBLOCKを守り、他owner差分をstash/reset/commitしない。
6. **report-only RC**: `review_approval.sh ... karo RC ... report`でpayloadだけ再開。Gunshi LGTM後のKaro ACCEPTはmode autoを使い、report明示でlegacy境界を誤適用しない。
7. **completion世代**: `cmd_complete.sh`の`gate_worker.*.json`は世代非依存名。旧generation markerが新CLEARを遮る場合、証跡を削除せず世代別dirへ退避してwrapperを再開する。
8. **worktree backlink**: WSL再起動/clone後に`.git`が別repoを指しうる。cleanup前に`.git`と`.git/worktrees/*/gitdir`を両向き確認する。`git worktree repair <path>`は他worktreeも走査するため出力全件を確認する。
9. **cutover順序**: final rsyncの後にrelocate。rsync前だけのパス置換は必ず巻き戻る。
10. **前提検証AC**: 表面エラー文を真因としない。今回`directory not found`の実体はledger mismatchだった。

## 5. 残タスクの一本道

1. shared dirtyのowner commit完了を一次確認する。
2. 最新origin起点で最後のconvergeを作り、通常pushする。
3. shared mainを`safe_shared_main_ff.sh origin/main`で追随し、relation=`0 0`を確認する。
4. 全6task idle、karo/gunshi pane入力待ち、reflux pause実在を確認する。
5. `migrate_to_ext4_cutover.sh --dry-run` PASS。
6. 掲示板へ3点セット付きで報告し、殿の実切替1行へ渡す。
7. cutover後: T88(cmd_4367/4368 report-only完了)→T87(ext4速度再基準)→T83(script分割)→T70(task worktree rootを/homeへ永続化)の順。

## 6. 一時worktree在庫

- `.tmp/converge-push-20260827-1928`
- `.tmp/converge-push-20260827-1928-r2`
- `.tmp/ci-fix-push-1e9fba-20260827`
- `.tmp/cutover-final-converge-20260827`
- 上記はcleanだが古いmerge refを含む。削除は10ファイル超になるため、破壊操作安全規則に従い殿確認後に`git worktree remove`する。cutover実行物ではない。

## 7. 禁則

- F001: 家老が通常実装を抱えない。hotfix/CI修正は`karo-direct`。
- F004: polling loop禁止。event-drivenで待ち、独立作業を進める。
- 運用YAMLへ`yaml.dump`/`safe_dump`禁止。正規helperを使う。
- `git reset --hard`, `git restore .`, `git clean -f`, kill系、force push禁止。
- dirty・後着inbox・履歴timestampを削除/遡及修正しない。
- cutover前にreflux pauseを解除しない。

## 8. 強くてニューゲーム二値条件

- [x] role・禁則・一次状態・未完了一本道を記録。
- [x] 全6task idle、inbox unread 0を一次確認。
- [x] Git relation・dirty paths・origin CIを一次記録。
- [x] 9p根治とrelocate hotfixの成果・数値・commitを記録。
- [x] cutover後在庫T88/T87/T83/T70を記録。
- [x] checkpoint SHA256をcompact_stateへ反映する。
- [x] 三層記憶へpointer/hash/originを貫通する。

## 9. 追記: Git最終収束（2026-08-27T21:39:53+09:00）

- 21:26保存時点の履歴は変更せず、後続事実を追記する。
- 家老owner 7パスを1 commitに固定: `f16ae75a7c022bce11f64d8be61cde4cc91386e3`。
- 最新originを第一親、localを第二親として隔離統合し、通常push: `5587f213459ef90144cbac28b5013c37b6490890`。
- shared mainは`safe_shared_main_ff.sh origin/main`で追随。結果: `SAFE_SHARED_MAIN_FF ... result=PASS`。
- 最終集計: `git rev-list --left-right --count origin/main...HEAD` = `0 0`。
- 掲示板証跡: `blt_20260827_213947_940f85`。
- 次の一本道: 将軍のcutover `--dry-run`一次結果を確認し、PASSなら殿の実切替1行へ渡す。
