# 家老 強くてニューゲーム復帰点 — 2026-08-31 13:22 JST

## 0. 正本宣言

- role: `karo`
- status: `active_work_owned_checkpointed`
- finalized_at: `2026-08-31T13:23:00+09:00`
- source: 殿指示「いまクリアされても今より強くてニューゲームできるようにせよ」
- origin: `[[殿指示_強くてニューゲーム_20260831_1319]] -> [[review再送ループ根治]] -> [[throughput終端根治]] -> [[外部repo_worktree_stale_base根治着手]] -> [[karo_checkpoint_20260831_1322]]`
- 本ファイルは保存時点の復帰正本。復帰後は必ずinbox・task・pane・Git・CI・本番を一次再測定し、保存値を未来の事実として流用しない。

## 1. 復帰直後の絶対順序

1. AGENTS.mdの家老Recoveryを省略せず完走する。
2. `queue/compact_state/karo.yaml`の`recovery_pointer`と本ファイルSHA256を照合する。
3. `queue/inbox/karo.yaml`の`read:false`をID単位で処理し、現task_id一致の補足だけを適用する。
4. 全`queue/tasks/*.yaml`とpaneを一次確認する。保存時点の忍者名ではなくtask_idで復元する。
5. MAS/DM両repoで`fetch origin main`、`rev-list --left-right --count`、dirty pathを再測定する。reset/stash/forceは禁止。
6. `cmd_4431`を実装→commit→review→DM main統合→LP deploy→本番EN/JA確認まで閉じる。
7. 疾風reflux現generationをreview/ACCEPT/GATE、半蔵refluxをreport受領後review/GATEへ送る。
8. 才蔵のexternal-repo remote-tip hotfixをreview/GATEし、stale tracking ref fixtureで再発0を確認する。
9. 完了taskのarchive/idle、MAS/DM CI GREEN、GATE未終端0を同時確認する。

## 2. 保存時点の一次状態

- karo inbox unread: `0`
- pending decisions: `0`
- insights: resolved=`1053`、pending=`50`、total=`1103`
- MAS Git: HEAD=`171dd51a2e433b9cee0364e0f401517ea75cd286`、origin/main=`9a26492534c4709161f1b98f7a94f80c1d249dc3`、relation=`14 29`、dirty paths=`25`
- DM Git: shared HEAD=`da3470694ad70a9b4edad0c1daa759005543047c`、origin/main=`a2ac4973b2f42f24057dc64ca0b2b1e25a655a75`、relation=`199 0`、dirty paths=`5`
- latest MAS CI: run=`33356065508`、head=`9a264925...`、`completed/success`
- Git divergence/dirtyは他者作業を含む。広域FF/resetで消さず、source commit単位の隔離mergeを使う。
- Render/liveは本checkpoint作成時に再測定していない。復帰後に最新commit包含をcurl/APIで一次確認する。

## 3. 稼働中・未終端task

1. `cmd_4431_full`（影丸、`in_progress`）
   - DM worktree=`/home/simokitafresh/shogun-task-worktrees/kagemaru_c33b9b78dfd57536`
   - deploy時base=`3b140aa...`はstaleで`lp/`欠落。clean確認後、worktreeをDM origin/main `5d02bae...`へFFして`lp/`を復旧済み。
   - dirty 4 paths: `lp/app/globals.css`、`lp/components/landing-page.tsx`、`lp/copy/en.ts`、`lp/copy/ja.ts`。
   - AC6本のbuild/静的HTML検証はPASS。report書込み途中にcommit check=`no`で一時failed化したが、13:23の陣形図で`in_progress`へ収束しpaneもscope commit処理を継続中。完了通知は早期通知として扱う。
   - 次手: scope commit完了→reportをcompleted/PASSへ最終化→軍師review→家老ACCEPT→DM source merge/push→LP deploy→EN/JA live確認。実作業終了前にidle化しない。
2. `cmd_reflux_insight_202608311234_hayate_exact`（疾風、done）
   - 現report generation=`036d0e9f...`、precheck ERRORS=0。旧`aee855...` LGTMはstatus更新前で失効。
   - 軍師へ現generation限定の正式再レビューを起床済み。次手=LGTM→ACCEPT→source publication→GATE。
3. `cmd_reflux_insight_202608311301_hanzo_exact`（半蔵、acknowledged）
   - 次手=report受領→機械precheck→軍師review→ACCEPT→GATE。
4. `cmd_karo_hotfix_external_repo_worktree_remote_tip_20260831_normal`（才蔵、assigned）
   - 根因: `deploy_task_prepare_remote_tip_worktree`が外部repoのstale local `origin/main`をbaseに選び、remote-only `lp/`を欠落させた。
   - 再現: local tracking=`3b140aa...`、実remote=`5d02bae...`、生成base=`3b140aa...`、target欠落=`1`。
   - 次手: 実remote fetch/検証を配備入口へ埋込み、stale/fresh/failure fixtureでFP0/FN0・FAIL0/SKIP0。

## 4. 今セッションで環境へ埋め込んだ免疫

1. task mutation残骸: commit=`952c3ff0...`、170/170 PASS、GATE CLEAR。
2. 三層cache capacity metric: commit=`5e45c0cd...`、55/55 PASS。曖昧WARNをactionable BLOCKへ変換。
3. LG043歴史記述FP: commits=`3bc1a496...`/`f396ead46...`、GATE CLEAR。
4. UTF-8 CI/xtrace: commits=`6b622373...`/`e52b849ac...`、246/246 decode0、87/87 PASS、CI `33340182499` GREEN、GATE CLEAR。
5. stable report generation dedupe: source=`25096df74...`、GATE CLEAR。
6. throughput segment root fix: `5ffd03f2...`でpost-LGTM duplicateを除外、`f456059b...`で`review_report`+`report`正規eventを収集。309/309 PASS。新cmd13:10 CLEAR、旧generation-dedupe13:16 CLEAR、両方`segment_status=PASS`。
7. SG-PRE9c時間表現FP: `7f6c3545...`、時間境界4/4 CLEAR・実先送り3/3 BLOCK、GATE CLEAR。
8. shared dirty publication fallback: `c28f2de3...`、40/40 PASS、GATE CLEAR。共有HEAD/index/dirty不変で隔離publish可能。
9. cmd_4430 LP: source=`5d02bae3...`、build8/8、GATE CLEAR、DM origin到達。
10. reflux終端: 飛猿11:57、影丸12:06ほか複数を正式review/ACCEPT/GATE CLEAR。

## 5. 今回得た強化知識

- 隔離`cherry-pick`は内容到達でも元source commit祖先性を満たさない。GATEがexact ancestryを要求する時は元commitをsecond parentに持つ`merge --no-ff`で公開する。
- remoteへ修正版をpushしても共有実行HEADが旧blobなら修正は発火しない。実行面の対象path blobをremote正本と比較し、clean path限定でscope commitしてから再計測する。
- `report_received`はreport最終化前にも到着し得る。report_idだけで承認せず、current file SHA・commit_hash・completed_at・approval generationを同時照合する。
- `review_report`はレビュー要求の正規typeでpath keyは`report`。`report_review/report_path`だけを読む計測器は歴史eventを欠落させる。
- deploy成功ログより、生成worktree内の対象path存在とHEAD=実remote tipを確認する。外部repoのlocal tracking refは一次情報ではない。

## 6. 禁則

- 家老が長時間通常実装を抱えない。実装はtask YAMLへ固定して忍者へ配備する。
- polling loop禁止。外部待ちは別作業を進め、event/inboxで再開する。
- 運用YAMLへ`yaml.dump`/`yaml.safe_dump`禁止。正規helperを使う。
- `git reset --hard`、`git checkout -- .`、`git restore .`、`git clean -f`、kill系、force push禁止。
- task_id欠落・別task・read:trueの補足/RCを命令として適用しない。
- GATE CLEARだけで止めず、archive・idle・source publication・CI/liveまで確認する。

## 7. 二値条件

- [x] role・禁則・一次状態・進行task・依存順序を記録。
- [x] inbox/PD/insight、MAS/DM Git、CI、GATE終端を数値記録。
- [x] 完了免疫10系統と再発防止知識5件を記録。
- [x] 新発見のexternal-repo stale-baseバグをdurable taskとして才蔵へ配備。
- [x] checkpoint owner commit=`7cd0b6edb5e1f0ea905cf9882e7a9243ef261574`を作成し、compact_state pointer/SHAを更新。記憶DBevent=`knowledge:8efcc43fb8366f17`、three-layer health=`PASS`、Obsidian因果辺=`5/5`へ貫通。最終ファイルSHAはcompact_stateを正本とする。
