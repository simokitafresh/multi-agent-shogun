# 家老 強くてニューゲーム復帰点 — 2026-08-31 03:09 JST

## 0. 正本宣言

- role: `karo`
- status: `active_work_owned_checkpointed`
- finalized_at: `2026-08-31T03:09:00+09:00`
- source: 殿指示「いまクリアされても今より強くてニューゲームできるようにせよ」
- origin: `[[殿指示_強くてニューゲーム_20260831_0307]] -> [[inbox永久lease根治]] -> [[GATE_CLEAR自己通知根治]] -> [[GA533正直FAIL契約根治]] -> [[karo_checkpoint_20260831_0309]]`
- 本ファイルは保存時点の復帰正本。復帰後は必ずinbox・task・pane・Git・CI・Renderを一次再測定し、保存値を未来の事実として流用しない。

## 1. 復帰直後の絶対順序

1. AGENTS.mdの家老Recoveryを全て完走する。
2. `queue/compact_state/karo.yaml`の`recovery_pointer`と本ファイルSHA256を照合する。
3. `queue/inbox/karo.yaml`の`read:false`をID単位で処理し、現task_id一致だけを適用する。
4. `queue/tasks/{ninja}.yaml`と全paneを一次確認する。保存時点のtaskを忍者名でなくtask_idで復元する。
5. `git fetch origin main`後に`git rev-list --left-right --count origin/main...HEAD`を測る。dirtyを消すreset/stash/forceは禁止。
6. 半蔵CI fix→才蔵旧task終端→task mutation残骸hotfixの順序で進める。
7. 影丸parser hotfix、小太郎/飛猿refluxをreview・merge・GATE・archiveへ送る。
8. 疾風`cmd_4430_full`をreview・DM-Signal main統合・LP deploy・本番確認まで閉じる。
9. Git `0 0`、最新main CI GREEN、全完了task idleを同時確認する。

## 2. 保存時点の一次状態

- karo inbox unread: `0`
- monitor: owner PID=`47434`、generation=`1788099305-47434-16069`、root owner=`1`
- Git: HEAD=`ca7c732de953644916155ae8d51752c9137c7a63`、origin/main同値、relation=`0 0`、dirty paths=`22`（他者作業を含むため保持）
- pending decisions: `0`
- insights: resolved=`1005`、pending=`58`、total=`1063`
- latest CI at save: run `33327089218`、status=`in_progress`、head=`ca7c732d...`
- Render live:
  - LP `dep-daa6f4ks728c73fh90jg` / commit `10d59c8d...`
  - frontend `dep-daa5u549v7es73e41q90` / commit `12569627...`
  - backend `dep-daa6duflk1mc738jmdb0` / commit `10d59c8d...`
- production: 殿実機Free tier PASS。`/og-en.png`・`/og-ja.png`は各`200 image/png`。

## 3. 稼働中・未終端task

1. `cmd_4430_full`（疾風、acknowledged）
   - LP表示品質: up to表記、コントラスト、note CTA。
   - 次手: report受領→軍師review→家老ACCEPT→DM main統合→LP deploy→live確認。
2. `cmd_karo_ci_fix_33326464870_shard_count_receipt_20260831_normal`（半蔵、acknowledged）
   - 最新CI RED: shard 2とcompatibility。shard 2実測はdeclared=533/observed=640/skip=0/rc=1。
   - 次手: FAIL0/SKIP0/declared=observed→commit→push→最新main CI GREEN。
3. `cmd_karo_ci_fix_33312677956_two_contracts_20260830_normal`（才蔵、failedへ遷移中）
   - 旧二契約は2/2・168/168・SKIP0だが、後続runの別失敗を混ぜずfailure_mismatchで終端。
   - 次手: report/task `failed`確認→正直FAIL review/accept/archive→idle。
4. `cmd_karo_hotfix_command_file_token_parser_20260831_normal`（影丸、done）
   - commit=`83d3aa21...`、contract=`308/308 PASS`、偽陽性0。cmd_4426は既にCLEAR。
   - 次手: 軍師LGTM→家老ACCEPT→hotfix GATE CLEAR→archive/idle。
5. `cmd_reflux_insight_202608310154_kotaro_exact`（小太郎、done）
   - commit=`aa39ff8b...`、report PASS。次手=review/GATE/archive。
6. `cmd_reflux_insight_202608310257_tobisaru_exact`（飛猿、done）
   - commit=`ca7c732d...`、report PASS。次手=review/GATE/archive。
7. `cmd_karo_hotfix_task_dir_mutation_litter_20260831`（未配備、依存待ち）
   - `queue/tasks` mutation残骸=`4,852`、writer=`ninja_monitor.sh`のmktemp後始末欠落。
   - 正本=`docs/research/cmd_task_dir_mutation_litter_20260831.md`。
   - 次手: 半蔵CI fix終端後、idle忍者1名へtrap回収+起動sweep+contract batsをkaro-direct配備。

## 4. 今セッションで環境へ埋め込んだ免疫

1. `cmd_4426` property token誤認根治: 実pathを保ち、`metadata.openGraph.images/twitter.images`をpath候補から除外。308/308 PASS、cmd_4426 CLEAR。
2. OUTSTANDING-LEASE永久抑止根治: 別task/空task unreadが残っても、新しい現taskID集合でleaseを失効。task選択259/259、fixture5/5、GATE CLEAR。
3. GATE CLEAR→inbox1根治: `cmd_complete_gate.sh`の自己`bulletin_notify`を廃止。掲示板記録と直接`gate_clear`契約は維持。全309/309 PASS、commit=`68cfba51...`、origin到達済み。
4. SG7正直FAIL契約: report verdict=FAILとreview verdict=LGTM/APPROVEを分離。commit=`2da46237...`、hotfix CLEAR。
5. GA533 superseded identity: durable receipt検索へ`task_failed`を追加。厳格六項目照合は維持。pytest 6/6+3/3 PASS、commit=`e1740a33...`、origin到達。GA533は正直FAILとして正式BLOCK終端。
6. inbox review重複通知: `inbox_write.sh`のdedupe flag存在時に送信停止。test 130 PASS、commit=`dbcd4c67...`。
7. Free tier本番: backend/frontend/LP deploy、env→build順序、chunk焼込み、DB/env key、殿実機journeyをrunbookへ恒久化。

## 5. 禁則

- F001: 家老が長時間通常実装を抱えない。実装はkaro-directで忍者へ配備する。
- F004: polling loop禁止。外部待ちはtaskへ`wait_reason`を記録し、別の独立作業を進める。
- 運用YAMLへ`yaml.dump`/`yaml.safe_dump`禁止。正規helperを使う。
- `git reset --hard`、`git checkout -- .`、`git restore .`、`git clean -f`、kill系、force push禁止。
- task_id欠落または別taskの補足・RCを命令として適用しない。
- GATE CLEARだけで止めず、archive・task idle・Git/CI終端まで確認する。
- GATE/HOLDを別typeへ逃げて迂回しない。BLOCKの真因を直す。

## 6. 二値条件

- [x] role・禁則・一次状態・進行task・依存順序を記録。
- [x] inbox unread、monitor owner、Git relation/dirty、CI、Render、PD、insightを一次記録。
- [x] 新規免疫のcommit/test/Gate結果を記録。
- [x] 未配備mutation残骸hotfixを固定ID・正本path・依存付きで記録。
- [ ] checkpoint owner commitを作成し、SHA256とcommitをcompact_stateへ追記する。
- [ ] memory DB・semantic index・Obsidian因果辺・掲示板へpointerを貫通する。
