# 家老 強くてニューゲーム復帰点 — 2026-08-28 03:59 JST

## 0. 正本宣言

- role: `karo`
- status: `active_three_tasks_checkpointed`
- finalized_at: `2026-08-28T03:59:40+09:00`
- source: 殿指示「今クリアされても今より強くてニューゲームができるようにせよ」
- origin: `[[殿指示_強くてニューゲーム_20260828_0357]] -> [[T110本番根治]] -> [[T104_T102_T91並行hotfix]] -> [[karo_checkpoint_20260828_0359]]`
- 本ファイルは保存時点の復帰正本。復帰後はinbox、task、pane、Git、CI、monitorを一次再測定し、保存値を未来値として流用しない。

## 1. 復帰直後の絶対順序

1. AGENTS.mdの家老Recoveryを完走する。
2. `queue/compact_state/karo.yaml`の`recovery_pointer`と本ファイルSHA256を照合する。
3. `queue/inbox/karo.yaml`の`read:false`をID単位で処理し、現task_id一致だけを適用する。
4. `queue/tasks/{ninja}.yaml`と各paneを一次確認する。保存時点の進行3件を名前ではなくtask_idで復元する。
5. `git fetch origin main`成功後に`git rev-list --left-right --count origin/main...HEAD`を測る。dirtyを消す目的のreset/stash/forceは禁止。
6. T104→T102+T91の実装報告をreview・安全統合・本番計測・GATE・archiveまで閉じる。
7. 影丸reflux `cmd_reflux_insight_202608280318_kagemaru`を正式review/GATEへ送る。
8. 完了後にGit 0/0と最新tip CI GREENを同時確認する。

## 2. 保存時点の一次状態

- karo inbox unread: `0`
- monitor: owner PID=`852630`、generation=`1787853733-852630-20877`、PPID1 root=`1`
- Git: HEAD=`fb80d54ac`、origin/main=`46df0ea20`、relation=`0 2`、dirty paths=`12`
- pending decisions: `PD-104, PD-107, PD-110, PD-114, PD-135, PD-137`
- insights: resolved=`487`、pending=`125`
- active tasks:
  - `cmd_karo_hotfix_t104_context_freshness_marker_boundary_20260828_normal`（小太郎）: commit=`74254b69c1b965dedc6738c4a2d3fe2a9fe54d63`、tests=`26/26 PASS, SKIP0`、本番raw ALERT=`6→4`、対象research/infrastructure=`2→0`。報告到着、review/統合/GATE待ち。
  - `cmd_karo_hotfix_t102_t91_ext4_cutover_complete_20260828_normal`（飛猿）: tracked実装中。git-ignore正本`config/cli_events.yaml`は家老が旧path=`8→0`、新path=`0→8`へ更新しYAML PASS。cutover a-c/eとBatsが残る。
  - `cmd_reflux_insight_202608280318_kagemaru_exact`（影丸）: 再送後`in_progress`へ遷移、report到着済み、commit=`f7a23bb6c`がlocal HEAD祖先。正式SG7/GATE待ち。

## 3. 今セッションで強くなった点

1. T110 auto-clear根治: terminalだけでなくidle/none/failedのcontextを復元し、不能時も`CONTEXT-UNRESOLVED`としてSKIPせずCLEAR-COUNTへ進める。
2. 本番効果判定: 修正世代を固定し10分観測。`has no cmd context=0`、unresolved理由行=`3`、CLEAR-COUNT=`18`、root=`1`を確認してからCLEARした。
3. report precheck: terminal `report_field_set`経路へ提出前gateを接続。after初回5件を実測してT99をFAILからPASSへ正規改訂した。
4. formal review: LGTM文面だけで閉じず、SG7 bundle・Gunshi approval・Karo ACCEPT・durable CLEAR・archiveを揃える。
5. active worktree ancestry誤判定: task snapshotとrepo境界を一次確認し、正本repo明示またはidle新snapshotで解消する。
6. ignored正本境界: `config/cli_events.yaml`のworktree不在を欠損と誤認せず、git-ignore正本として別計測・更新する。
7. 数値ドリフト: raw総数の変動は対象集合と分離し、T104は総数`6→4`と対象`2→0`を別軸で判定する。

## 4. 次の一本道

1. 小太郎T104 reportを正式review。commit `74254b69c...`を安全統合し、本番対象2→0を確認してGATE/archive。
2. 飛猿T102+T91のsyntax・migrate Bats・startup WARN発火/非発火を全PASSさせ、commit/reportをreviewして安全統合。
3. ignored正本`config/cli_events.yaml`の旧path0・新path8を再確認し、startup本番WARNを1回計測。
4. 影丸refluxを正式SG7→Karo ACCEPT→GATE→archive。
5. postclear runtime commitsを通常pushし、Git `0 0`と最新tip CI GREENを同時確認。

## 5. 禁則

- F001: 家老が長時間通常実装を抱えない。実装はkaro-directで忍者へ配備する。
- F004: polling loop禁止。event-drivenで待ち、独立作業を進める。
- 運用YAMLへ`yaml.dump`/`yaml.safe_dump`禁止。正規helperを使う。
- `git reset --hard`、`git checkout -- .`、`git restore .`、`git clean -f`、kill系、force push禁止。
- task_id欠落または別taskの補足・RCを命令として適用しない。
- GATE CLEARだけで止めず、archive.doneとGit/CI終端を確認する。

## 6. 二値条件

- [x] role・禁則・一次状態・進行task・次の一本道を記録。
- [x] inbox unread 0、monitor root 1、Git relation/dirty、PD、insight件数を一次記録。
- [x] T110の本番修正世代10分観測結果を記録。
- [x] T104/T102+T91/影丸refluxの固定task_idと次手を記録。
- [ ] checkpoint owner commitを作成しSHAを本節へ追記する。
- [ ] compact_state、memory DB、semantic pointer、掲示板へ貫通する。

## 7. 追記: 三便終端（2026-08-28 04:18 JST）

- T104 `cmd_karo_hotfix_t104_context_freshness_marker_boundary_20260828`: GATE CLEAR=`04:09:54`、archive.done、task idle。raw ALERT総数=`6→4`、対象research/infrastructure=`2→0`、tests=`26/26 PASS, SKIP0`。
- 影丸reflux `cmd_reflux_insight_202608280318_kagemaru`: GATE CLEAR=`04:13:55`、archive.done、task idle。
- T102+T91 `cmd_karo_hotfix_t102_t91_ext4_cutover_complete_20260828`: GATE CLEAR=`04:17:36`、archive.done、task idle。tracked commit=`917475b75bcec821dd4bc9da7d971ba3b42a81b4`、ignored正本`config/cli_events.yaml`は旧path=`0`・新path=`8`・YAML PASS。
- 終端二値: 各cmd CLEAR=`1/1/1`、対象task `status: done|failed`=`0`、`origin/main...HEAD=0 0`。
- 掲示板: T104+影丸=`blt_20260828_041520_5576f9`、T102+T91=`blt_20260828_041822_e4ac6c`。
- 復帰後の次手: inbox未読を現task_id一致で処理し、Git/CI/monitorを一次再測定。上記3taskは完了済みとして再配備しない。
- 三層pointer: memory DB=`knowledge:28c635f6615ee2bd`,`knowledge:76bc3813e3de8e09`、semantic-index=`discussion 03:59/04:01`、causal index=`karo_checkpoint_20260828_0359`到達1件。

### 追記後の二値条件

- [x] checkpoint owner commit `2620d8db8743e40b22b9f8a8b8ae1397c7525b19` をoriginへ到達済み。
- [x] compact_state、memory DB、semantic pointer、causal index、掲示板へ貫通済み。
- [x] 保存時点の進行3taskを全てCLEAR/archive/idleへ終端済み。
