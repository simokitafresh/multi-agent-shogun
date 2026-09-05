---
<!-- script_refs_checked_at: 2026-07-18T22:46:00+09:00 -->
<!-- 2026-07-18 cmd_karo_ci_fix_skill_refs_latest_202607182242検分: deploy_task.sh 0b1265d78b63d59102daa5816a4159f593ec6e36はplanned_pathsにscripts/coddまたはskills/codd系を含むtaskへcontext/codd.mdをLevel5注入する。2 Trackの配備CLI・固定base独立性・衝突guard・通知・失敗exitは不変で、該当scope時の両task context副作用のみ拡張。本文変更不要。 -->
<!-- script_refs_checked_at: 2026-07-18T21:58:00+09:00 -->
<!-- 2026-07-18 cmd_karo_ci_fix_skill_refs_deploy_pair_202607182153検分: deploy_task.sh eef20f23f/1f248cde4/8be72a421/765997873/11c325097/7acd9d27d/e7415f9dc/94f2a21e1をgit log/show。no-code N/A証跡、wave cache bounded identity、report template原子公開、配備wall/防御telemetry、post_verify順序正規化、absent target履歴walk回避、planned_pathsを含む予約衝突BLOCKを追加。2 Trackの配備CLI・独立性・通知・失敗出口は不変。target_pathだけでなくplanned_paths同一fileもactive peerとの安全衝突境界となり、BLOCK時は2人目を配備済み扱いにしない。 -->
<!-- script_refs_checked_at: 2026-07-18T14:08:00+09:00 -->
<!-- 2026-07-18 cmd_karo_hotfix_skill_refs_batch_b検分: deploy_task.sh 73e12f31/c10949d8/3a305a0f/d5b4e3fa/b8131106/4948a4a2/a9647608/b8583338/fb619776/eb378791/c8cf9081をgit log/show。report identity/no-code契約、配備control-plane bounded化、stale report同期archive復帰はいずれも共通配備内部の強化。recon1=`--yaml`、recon2=`--direct --yaml`の順序・重複guard・通知・失敗出口は不変で本文変更不要。 -->
<!-- script_refs_checked_at: 2026-07-18T04:36:00+09:00 -->
<!-- 2026-07-18 cmd_karo_hotfix_skill_refs_deploy_pair検分: deploy_task.sh 6f1f32c57はDM-Signal restore対象taskへ診断履歴post-snapshot artifact契約を事前注入するLevel5文脈強化。該当purposeなら両Trackのtask文脈へ条件付き副作用が加わるが、1人目正規配備・2人目--yaml、固定base、独立性guard、通知・失敗出口は不変。 -->
<!-- script_refs_checked_at: 2026-07-18T03:18:00+09:00 -->
<!-- 2026-07-18 cmd_karo_hotfix_skill_refs_freshness_batch検分: deploy_task.sh 30748a921/1c69c22ea/680ce7d76/06cd5ddfはwave cache、構造化commit契約、孤立caller fallback、target HEAD preflightを追加。2名偵察の通常配備+karo_direct分割契約、引数、副作用順序は不変。 -->
<!-- script_refs_checked_at: 2026-07-18T01:02:00+09:00 -->
<!-- 2026-07-18検分: deploy_task.sh 30748a92/1c69c22eはwave cache+構造化commit_contract追加。二名配備CLI不変。 -->
<!-- script_refs_checked_at: 2026-07-17T18:23:00+09:00 -->
<!-- 2026-07-17 cmd_karo_hotfix_skill_refs_202607171819検分: deploy_task.sh 06cd5ddf1はtarget_pathをYAML型のまま解釈し、git HEAD存在証跡(target_path_git_preflight)と未追跡警告をtaskへ事前注入するLevel5強化。1人目の正規配備、2人目の--yaml配備、重複guard、通知契約は不変。 -->
<!-- 2026-07-17 cmd_karo_hotfix_skill_refs_all検分: deploy_task.sh 14e62013d/630386f4d/242df2ee4/fff17f591/a9cf189d6のlesson注入・telemetry・batch read・delivery・opsim差分を実検分。2名配備順序とkaro_direct併用契約は不変。 -->
<!-- script_refs_checked_at: 2026-07-16T23:40:33+0900
<!-- script_refs_checked_at: 2026-08-01T19:15:00+09:00 -->
<!-- cmd_karo_hotfix_skill_refs_reflux_b_20260801検分: deploy_task.sh 4b2ebade6/ad9b08a8c/da8993f1d/efd5aaac7/9ef3e2d7e/7a4748678 と yaml_field_set.sh 7a4748678 をgit showで確認。配備時target_path blob基準とtask lease(progress_updated_at)の原子更新、lesson適用fail-close、owner transactionを追加。1人目正規配備→2人目--yaml、固定base、衝突BLOCK、通知・失敗出口の契約は不変。 -->

<!-- cmd_karo_hotfix_skill_script_refs_six_202607170058検分: deploy_task.sh 110c4df67/a9cf189d6/fff17f591をgit show。report metadata内部取得、全report opsim事前注入、task_assigned配達確認の非同期化のみ。1人目通常配備→2人目--yaml配備の引数・順序・重複guard・永続化/通知契約は不変。本文変更不要。 -->
<!-- script_refs_checked_at: 2026-07-17T01:02:18+09:00 -->
<!-- cmd_karo_hotfix_skill_refs_eight_202607162132検分: deploy_task.sh 63a76836dをgit showで確認。legacy lifecycle status制御を通常配備から早期分離した修正で、1人目通常配備→2人目`--yaml`の順序、引数、衝突guard、通知契約は不変。本文変更不要。 -->
<!-- script_refs_checked_at: 2026-07-16T23:40:33+0900
<!-- 2026-07-16再検分: deploy_task.sh 1b23b3c9d/e29f20e3e/00a06e308。各共通配備入口でuniversal shard manifestを自動生成し、生成不能はexit 2でBLOCKする副作用を追加。1人目通常配備→2人目`--yaml`の引数・順序・通知契約は不変。 -->
<!-- 将軍D0検分: deploy_task.sh 72fc07d15(LG055 operational_simulationテンプレート事前生成)。通常配備+2人目karo-directの順序契約は不変。 -->
<!-- script_refs_checked_at: 2026-07-16T23:40:33+0900
<!-- cmd_karo_hotfix_skill_refs_core_202607152126検分: deploy_task.sh 22609351d/6c2eea753/7a8dd1c68をgit showで確認。report summaryのLevel5事前供給、分析cmdの.logを含むreadonly_ref抽出、再注入時のsequence重複除去は内部生成処理。偵察1人目の`--yaml`配備、2人目のkaro-direct配備、通知・衝突guard契約は不変。 -->
<!-- script_refs_checked_at: 2026-07-16T23:40:33+0900
<!-- 2026-07-15検分: deploy_task.shはspeed campaign固有report名を保存。recon-dualの2名配備順序・karo-direct併用契約は不変。 -->
name: recon-dual
argument-hint: "[cmd_id] [target_scope]"
description: |
  【家老専用】偵察2名配備(recon Pattern 1)を標準化するスキル。
  1人目をdeploy_task.sh、2人目をkaro_direct方式で配備し、重複ガード問題を回避。
  TRIGGER: /recon-dual、偵察2名配備、recon2配備、2名偵察
  DO NOT TRIGGER: 偵察1名配備（→deploy_task.sh直接）、karo_direct単独（→/karo-direct）
quality_metric: "当該スキルで配備した偵察2名タスクのgate通過率（完了時cmd_complete_gate.sh CLEAR割合）"
allowed-tools:
  - Bash
  - Read
---

<!-- script_refs_checked_at: 2026-07-16T23:40:33+0900
<!-- cmd_karo_hotfix_skill_refs_202607151824検分: deploy_task.sh 26dd9b29c/9adea0b76/81162392b/7042b59e9とyaml_field_set.sh 7042b59e9をgit showで確認。配備taskのlesson/時間契約投影とindentless sequence置換の内部強化のみ。2名配備順序・CLI引数・重複guard回避・atomic更新契約は不変。 -->
<!-- cmd_karo_hotfix_skill_refs_after_infra_202607151211: deploy_task.sh 336f30b67は配備証跡capture拡張、yaml_field_set.sh 6dd44d13fは後置list id対応。二重配備・YAML更新の既存CLI契約は維持。 -->

<!-- script_refs_checked_at: 2026-07-16T23:40:33+0900
<!-- cmd_3948検分: deploy_task.sh/yaml_field_set.sh直近差分はpublication直列化・parse削減。二名配備契約不変。 -->
<!-- 検分: deploy_task.sh 030d267b..87ef68b7(継続配備、独立recon投影、no-code報告契約、事前検証)とyaml_field_set.sh 386cb6bb(lock domain統一)。CLI引数・出口値・1人目→2人目の呼出順序は不変 -->
<!-- Script refs verified 2026-07-13 shogun復帰時: checked_at以降の変更(yaml_field_set wrapped scalar保持fix de3df4b83, deploy_task parent AC contract dbcb20aa2, ninja_monitor journal+flock 93f8c898e/16f16e699, db_capability_launcher scoped credential 84231a01c)をgit logで確認。全て内部強化で呼出し契約・出口文言不変 -->

Script refs verified: 2026-07-13 将軍検分. checked_at以降の変更: `deploy_task.sh` 793d03399..1f55aae59(自然境界mapping検証+reopened parent解決+formal approval連動=内部配備ロジック。1人目/2人目の呼出し契約・safe_inbox_write通知は不変。親AC偽CLEAR hotfix RC継続中のため次回commit時に再検分される)、`yaml_field_set.sh` 692b6c8d8(post-write検証をyaml.safe_load scalar比較へ統一+複数行値の安全エスケープ。`<file> <block_id> <field> <value>`契約不変)。recon-dual手順の書き換え不要。
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->
Script refs verified: 2026-07-10 cmd_karo_hotfix_skill_ref_freshness_202607101154_normal. `deploy_task.sh` checked_at以降の変更(b458129d1)をgit showで確認。ACに'push'語を含むtask YAMLへ配備時`push_allowed:true`を自動付与する`inject_push_allowed()`を追加(cmd_3820 G2ガードBLOCK再発防止、Level5知識注入)。`deploy_task_apply_task_mutations`内の内部注入チェーン追加のみで、1人目 `bash scripts/deploy_task.sh <cmd_id> <ninja1> scout` と2人目 `bash scripts/deploy_task.sh --yaml <file> <ninja2>` の呼び出し契約、safe_inbox_write通知、report template生成は変更なし。recon-dual手順の書き換えは不要。

<!-- script_refs_checked_at: 2026-07-16T23:40:33+0900
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->

Script refs verified: 2026-07-08 cmd_karo_hotfix_skill_refs_202607081021. `deploy_task.sh` checked_at以降の変更(edb26ea1/0c73c7d1/f5f7600d)をgit showで確認。edb26ea1はrecon/scoutタイプreport templateへ`verified_existing_dependency: []`雛形とコメント例を追加(LG037除外宣言用、recon-dualの1人目scoutテンプレートにも及ぶ)。0c73c7d1はtask YAML配備batchに`deployed_at`/`acknowledged_at`/`done_at`/`completed_at`初期化を追加(throughput計測用)。f5f7600dはlesson/semantic/memory-db注入4関数のキャッシュ経路統一による内部性能改善(約140秒→約3秒)のみ。いずれも1人目 `bash scripts/deploy_task.sh <cmd_id> <ninja1> scout` と2人目 `bash scripts/deploy_task.sh --yaml <file> <ninja2>` の呼び出し契約、safe_inbox_write通知は変更なし。recon-dual手順の書き換えは不要。

Script refs verified: 2026-07-07 cmd_3743. `deploy_task.sh` checked_at以降の変更(3094ffeba/132a0f3fc/cbd5c9c94/88dae4ee5)をgit logで確認。CI回帰修正、配備鮮度/レビュー文脈強化、deployed_at保持、direct YAML collision guard追加で、1人目 `bash scripts/deploy_task.sh <cmd_id> <ninja1> scout` と2人目 `bash scripts/deploy_task.sh --yaml <file> <ninja2>` の呼び出し契約、safe_inbox_write通知、report template生成は維持。衝突時はdeploy_task.shのBLOCKを安全境界として扱う既存記載と一致。

Script refs verified: 2026-07-04 cmd_training_skill_refs_recon_dual_202607042005. `deploy_task.sh` の checked_at(2026-07-03T02:15:00+09:00)以降変更をgit log/showで確認。781d3c456は報告YAMLartifact向け教訓target_files除外の内部注入精度改善、15ff192a9はtask YAML構文FAIL時にtask_assigned/report template/draft reviewを停止して家老へdeploy_error通知、fc056d4b2はreport templateのfiles_modified雛形とbinary_checks生成強化、da70ad039はactive peerとのtarget_pathファイル衝突をBLOCKしディレクトリ衝突はINFOにする安全ガード追加。1人目 `bash scripts/deploy_task.sh <cmd_id> <ninja1> scout` と2人目 `bash scripts/deploy_task.sh --yaml <file> <ninja2>` の呼び出し契約、safe_inbox_write通知、report template生成は維持。ただし2人目`--yaml`でも同一ファイルtarget_path衝突は新ガードでBLOCKされるため、これは重複ガード回避対象ではなく安全境界として扱い、配備済みにしない。

Script refs verified: 2026-07-02 cmd_karo_hotfix_skill_script_refs_202607021234. 対象scriptの2026-07-02T01:12以降差分をgit log/showで確認。直近変更は速度改善・内部検査強化・テンプレート修復・files_modified path guardで、各SKILL本文の呼び出し契約は維持。

Script refs verified: 2026-07-02 cmd_karo_hotfix_shogun_startup_memory_skill_refs_20260702010546. `deploy_task.sh` 直近変更(a9a3bb08/42d661ef/a4297c73/d46b3e93/4e8e692/07f264d5)はAC parse、stale reset対象追加、lesson postcondition順序の内部修正で、1人目 `bash scripts/deploy_task.sh <cmd_id> <ninja1> scout` と2人目 `bash scripts/deploy_task.sh --yaml <file> <ninja2>` の契約は変更なし。

Script refs verified: 2026-07-01 idle useful-rate analysis follow-up. `deploy_task.sh` 直近変更は `target_files` を明示した教訓をタグ一致より強い制約として扱い、不一致なら `related_lessons` から除外する修正。狭義教訓が別ファイルtaskへ漏れて useful率を汚す経路を遮断した内部注入精度改善であり、1人目正規配備 `bash scripts/deploy_task.sh <cmd_id> <ninja1> scout` と2人目 `bash scripts/deploy_task.sh --yaml <file> <ninja2>` の引数契約、通知、report template生成、stale field resetは変更なし。

Script refs verified: 2026-06-28 cmd_3582/e13c60e60. `deploy_task.sh` 直近変更は `get_japanese_name` 経由で忍者名の日本語対応をSSOT化し、`inject_workaround_pattern_lessons` で `logs/karo_workarounds.yaml` の頻発WAカテゴリから関連教訓を `related_lessons`/descriptionへ注入する内部コンテキスト提供追加。1人目正規配備 `bash scripts/deploy_task.sh <cmd_id> <ninja1> scout` と2人目 `bash scripts/deploy_task.sh --yaml <file> <ninja2>` の引数契約、通知、report template生成、stale field resetは変更なし。
Script refs verified: 2026-06-16 cmd_3413. `deploy_task.sh` 直近変更(9fe724dda)はtask_tags空+target_pathあり時のpath-dirタグ推定追加。lesson注入タグ生成の内部ロジックであり、1人目 `bash scripts/deploy_task.sh <cmd_id> <ninja1> scout` と2人目 `bash scripts/deploy_task.sh --yaml <file> <ninja2>` の引数・通知契約、stale field reset、report template生成は変更なし。
Script refs verified: 2026-06-16 cmd_3405. `deploy_task.sh` 直近変更(1ef582caf)はMAX_INJECT 10→3に縮小。useful_rate=16.7%(<30%)の根因=過剰注入の修正。1人目 `bash scripts/deploy_task.sh <cmd_id> <ninja1> scout` と2人目 `bash scripts/deploy_task.sh --yaml <file> <ninja2>` の引数・通知契約、stale field reset、report template生成は変更なし。
Script refs verified: 2026-06-12 cmd_karo_hotfix_skill_refs_202606121132. `deploy_task.sh` 直近変更(d808770fc)はreadonly refsをtaskへ自動注入する内部コンテキスト提供追加。1人目 `bash scripts/deploy_task.sh <cmd_id> <ninja1> scout` と2人目 `bash scripts/deploy_task.sh --yaml <file> <ninja2>` の引数・通知契約、stale field reset、report template生成は変更なし。
Script refs verified: 2026-06-11. `deploy_task.sh` の契約は `<cmd_id> <ninja1> scout` / `--yaml <file> <ninja2>` のまま。25d0b1e22は分割配備判定の内部修正で、recon-dualの1人目scout正規配備と2人目`--yaml`配備の引数・通知契約変更なし。
Script refs verified: 2026-06-11 ab0d45dad. `deploy_task.sh` はzero-useful lesson自動deprecatedを `ENABLE_ZERO_USEFUL_AUTO_DEPRECATE=1` 指定時の明示機能に変更した。lesson注入後の評価分母保護の内部挙動であり、recon-dualの1人目正規配備 `bash scripts/deploy_task.sh <cmd_id> <ninja1> scout` と2人目 `--yaml <file> <ninja2>` の配備手順・通知契約変更なし。
Script refs verified: 2026-06-07 cmd_3206. `deploy_task.sh` の直近速度修行変更はearly target判定・ログ抑制など内部処理で、1人目の正規配備 `bash scripts/deploy_task.sh <cmd_id> <ninja1> scout` と2人目の `--yaml` 配備契約は変更なし。DIRECT_MODE専用のtraining parent_cmd補修スキップはrecon-dualのscout/`--yaml`経路に影響しない。`yaml_field_set.sh` はlock path高速化のみ。SKILL.md記載の偵察2名配備手順は現行と一致。

# /recon-dual — 偵察2名配備スキル

偵察cmd(type=scout)を2名の忍者に配備。毎回の手順バラつきをゼロに。

## 引数

`/recon-dual <cmd_id> <ninja1> <ninja2>`

## 実行フロー

### Step 1: idle忍者2名確認
```bash
tmux capture-pane -p -t <ninja1_pane> -S -30
tmux capture-pane -p -t <ninja2_pane> -S -30
```
snapshotだけで判断せず、指定2名がともにidleであることを実ペインで確認する。対象repoの固定base commitを `git -C <repo> rev-parse HEAD` で1回だけ取得し、両Trackのtask YAMLへ同じ `independence_base_commit` として記録する。
cmdの `recon_dual:` mapping(mode: independent / cross_reference: forbidden / base: fixed_origin_main / shared_context_embargo: karo_release_required)を正本として読む(2026-09-06: cmd_save Check 19.7 が起票時に fail-closed 検査するので、ここで欠落する cmd は原則届かない)。mapping が無く、title/purpose/commandに `独立2系統`・`相互参照禁止`・`independent recon` のいずれも無い場合だけ配備を停止し、将軍cmdへ `recon_dual:` を追加してから再開する。`deploy_task.sh`はこの語を検出し、nudge前にfixed-base/worktree/共有context embargoをtaskへ自動注入する。

### Step 2: 1人目配備（deploy_task.sh）
```bash
bash scripts/deploy_task.sh <ninja1> <cmd_id> "独立Track A。固定base以外の兄弟Track成果を参照せず、共有contextへの還流は家老releaseまで禁止" task_assigned karo
```
deploy_task.shが正規のタスクYAML生成+教訓注入+inbox_writeを実行。
配備ログに `[INDEPENDENT_RECON] group=<cmd_id> track=A base=<固定base> embargo=karo_release_required` が出たことを確認する。出なければ配備済み扱いにせず停止する。兄弟Trackのtask/report/branch/worktree/commitと、配備後に更新された共有contextを参照してはならない。

### Step 3: 2人目配備（karo_direct方式）
deploy_task.shの重複ガードを回避するため、/tmp YAMLを作って `--yaml` 経由で配備:
```bash
# 1人目のタスクYAMLをベースにrecon2用に調整（正式task YAMLへ直接cpしない）
cp queue/tasks/<ninja1>.yaml /tmp/recon2_<ninja2>.yaml
bash scripts/lib/yaml_field_set.sh /tmp/recon2_<ninja2>.yaml "task" "parent_cmd" "<cmd_id>_recon2"
bash scripts/lib/yaml_field_set.sh /tmp/recon2_<ninja2>.yaml "task" "cmd_id" "<cmd_id>_recon2"
bash scripts/lib/yaml_field_set.sh /tmp/recon2_<ninja2>.yaml "task" "independence_group" "<cmd_id>"
bash scripts/lib/yaml_field_set.sh /tmp/recon2_<ninja2>.yaml "task" "independence_track" "B"
bash scripts/lib/yaml_field_set.sh /tmp/recon2_<ninja2>.yaml "task" "independence_base_commit" "<固定base>"
bash scripts/lib/yaml_field_set.sh /tmp/recon2_<ninja2>.yaml "task" "shared_context_embargo" "karo_release_required"
bash scripts/lib/yaml_field_set.sh /tmp/recon2_<ninja2>.yaml "task" "role_reminder" "独立Track B。固定baseと自作probeのみ使用。兄弟Trackのtask/report/branch/worktree/commit・配備後の共有context参照禁止。共有context還流は家老releaseまで禁止"
bash scripts/deploy_task.sh --yaml /tmp/recon2_<ninja2>.yaml <ninja2>
```
`deploy_task.sh --yaml` が stale field reset、注入チェーン、report template生成、safe_inbox_write通知を実行する。手動 `cp` で `queue/tasks/<ninja2>.yaml` を上書きしたり、手動 `inbox_write` で通知したりしない。
`deploy_task.sh --yaml` はtask YAML構文を検証し、構文FAIL時はtask_assigned/report template/draft reviewを停止して家老へdeploy_error通知する。/tmp YAML作成後は`yaml_field_set.sh`だけで編集し、構文FAILまたはtarget_pathファイル衝突BLOCKが出たら、2人目を配備済み扱いにしない。
`deploy_task.sh` のtarget_path衝突ガードはparent_cmd重複ガードとは別系統である。同一ファイルtarget_pathを持つactive peerがいる場合は2人目`--yaml`でもBLOCKし、同一ディレクトリtarget_pathはINFOのみで継続する。2名偵察で同じファイルを意図する場合、このBLOCKを手動回避せず、cmd_complete_gate完了・別idle忍者選定・target_path粒度見直しのいずれかで処理する。
`deploy_task.sh` が配備前にpending own report / completed peer reportを検出してBLOCKした場合、報告YAML消失防止が優先である。cmd_complete_gate完了または別idle忍者選定まで、2人目を配備済み扱いにしない。

### Step 4: 陣形図確認
両忍者がin_progressになったことを確認。

## 制約
- 1人目=deploy_task.sh正規フロー、2人目=`deploy_task.sh --yaml` のkaro_direct方式。この順序を崩すな
- 2人目のcmd_idは `<cmd_id>_recon2` サフィックス
- 両Trackは同一の固定base commitから開始する。片方の成果commitをもう片方のbaseにしてはならない
- 両Track完了前の共有context/semantic-map/記憶DBへの結論還流は禁止。家老が2報告を受領・独立性検証後に統合還流する
- 片方が兄弟Track由来の結論を見た場合、その報告は補助証拠へ降格し、未汚染の代替Trackを固定baseから再配備する
- 偵察結果の突合は家老が手動で実施（報告YAML受領後）
- Script refs verified: 2026-06-02 cmd_3119/3121/3126. `deploy_task.sh` は関連教訓注入時に semantic-map に加えて memory DB `event_concepts` 由来のlesson boostを使い、`task_type=impl` のkeyword閾値を6へ引き上げ、memory DB boostの概念数・lesson数・event数をログ出力する。注入精度/可観測性の変更であり、偵察2名配備の手順変更は不要。2026-05-29 cmd_3107/a4a64068. `deploy_task.sh` の `inbox_write.sh` 呼び出しは draft_review に `review_request`、status_update に `status_update` の第5引数を渡す。偵察2名配備の手順変更は不要。2026-05-29 cmd_3091. `deploy_task.sh` はreport templateのbinary_checks注入ログでAC数をawk集計する。ログ精度の変更であり、偵察2名配備の手順変更は不要。2026-05-27 cmd_3062: `deploy_task.sh` は `target_path` / `files_modified` と教訓 `target_files` が一致した場合に `TARGET_PATH_MATCH_BOOST` で関連教訓の注入順位を上げる。注入精度の変更であり、偵察2名配備の手順変更は不要。`deploy_task.sh` は旧task由来の `scope`、`context_hints`、`context` をreset_stale_fieldsで清掃する。cmd_3019のq11_not_already_done再確認WARNとcmd_3020のuniversal lessons target_path関連フィルタは共通配備経路の自動処理で、偵察2名配備の手順変更は不要。`inbox_write.sh` は `from=shogun type=task_new` をBLOCKするため、将軍直送の作業指示経路をこのスキルへ追加しない。cmd_2899: deploy_task.sh target_path存在チェックのproject_path 2段解決追加+yaml_field_set.sh WSL2最適化。cmd_2939: report filename生成でparent_cmd未設定時にcmd_idをフォールバックとして使用。cmd_2944: `_compute_ac_hash` は `description:` なしACでも `check:` / `checks[].check` をフォールバックに使い、偵察/直接配備テンプレート由来ACのハッシュを空にしない。cmd_2951: 配備前pending own report / completed peer reportをBLOCKし、報告YAML消失を防止。cmd_2956: cmd_training_* のparent_cmd nullishをcmd_idから修復。cmd_2957: trainingテンプレートは関連ファイルへの直接[[ファイル名]]リンクとリンク先特定行引用を要求。cmd_2953: training target_pathは `markdown_link_counts.sh --select-file` 優先、未取得時のみ `semantic_alias_quality.sh` へフォールバックする。cmd_2968: report templateのverdictは空値のみを出力し、gate_report_format.shがbinary_checksから自動導出する。

Script refs verified: 2026-06-05 cmd_3146/cmd_3144. `deploy_task.sh` はlesson injectionで対象project外の教訓を除外し、platform project教訓のみ横断許可する(project filter)。これは注入精度の変更であり、偵察2名配備の手順変更なし。`deploy_task.sh` 直近変更(670918b3)はdraft review重複通知防止(内部追加のみ)。`yaml_field_set.sh` 直近変更(670918b3)はsingle-quoteエスケープ修正(内部バグフィックス)。SKILL.md記載の1人目正規配備+2人目--yaml配備手順は現行と一致。
Script refs verified: 2026-06-08 ceb10419a cmd_3231. `deploy_task.sh` はtarget_pathなし時にMIN_KEYWORD_SCOREを8へ引上げ、tag fallbackを無効化(低関連教訓のNOT_USEFUL量産防止)。注入精度の変更であり、偵察2名配備の手順変更なし。
Script refs verified: 2026-06-09 e72eb99d4+3de0d29cc. `deploy_task.sh` はinject_semantic_conceptsで推薦ログにninja_nameフィールドを記録(precision照合キー修正)。`yaml_field_set.sh` はskip_childrenがYAMLリスト要素を見逃すバグ修正。いずれも内部変更であり、偵察2名配備の手順変更なし。
Script refs verified: 2026-06-10 d38c43e8c+9c6df92d8+a9dc1b7c8. `deploy_task.sh` はlesson_impact.tsvの空行混入防御(CR汚染対策)、boost適用にkeyword_score>0必須化+flow-style deprecation対応、TRIGGER cross-validation追加(スキル推薦偽陽性防止)。全て内部注入精度/データ整合性の変更であり、偵察2名配備の手順変更なし。

Script refs verified: 2026-06-20 3421a1dc9+48204a464+782be65a6. `deploy_task.sh` 直近変更は教訓matching scoring調整、操作的オントロジー/targetフィルタ/スキル強制、PJパスSSOT化。1人目正規配備 `bash scripts/deploy_task.sh <cmd_id> <ninja1> scout` と2人目 `--yaml <file> <ninja2>` の契約は変更なし。

Script refs verified: 2026-06-21 d81b77654. `deploy_task.sh` 直近変更はtag fallbackをtarget_files一致教訓に限定し、CIのlesson fallbackテストを現行仕様へ合わせたもの。1人目正規配備 `bash scripts/deploy_task.sh <cmd_id> <ninja1> scout` と2人目 `--yaml <file> <ninja2>` の契約は変更なし。

Script refs verified: 2026-06-23 1586d6f48. `deploy_task.sh` 直近変更はGS/DB検出時execution_env自動注入(L5防御)。1人目正規配備+2人目`--yaml`の配備契約は変更なし。
Script refs verified: 2026-06-26 12c935c10. `deploy_task.sh` 直近変更はNO_WHEN_PENALTY 3→10(教訓注入スコアリング内部調整)。配備契約・引数・worktree・task YAML生成は変更なし。

Script refs verified: 2026-06-28 b1922e36b+0226e0db5+75aac6a10. `deploy_task.sh` 直近変更はfailed redeploy時のgate扱い修正とcanceled cmd配備BLOCK。`yaml_field_set.sh` 直近変更は新規field挿入位置の内部修正。1人目正規配備 `bash scripts/deploy_task.sh <cmd_id> <ninja1> scout` と2人目 `--yaml <file> <ninja2>` の契約は変更なし。

Script refs verified: 2026-07-07T18:19:00+09:00 (shogun復帰時WARN解消). `deploy_task.sh` 直近変更(88dae4ee5)をgit showで確認。direct/--yamlモードのtarget_path衝突ガードをtask YAML書換え前に先行実行する`deploy_task_guard_direct_yaml_prewrite_collision`追加。衝突BLOCKの判定基準は既存`deploy_task_guard_target_path_collision`のままで、2人目`--yaml`の呼び出し契約・安全境界の扱い(同一file衝突=BLOCK、配備済みにしない)は本文記載の通り変更なし。

<!-- script_refs_checked_at: 2026-07-16T23:40:33+0900
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->

<!-- script_refs_checked_at: 2026-07-16T23:40:33+0900
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->
Script refs verified: 2026-07-08 将軍検分. 前回checked_at以降の deploy_task.sh 差分は f5f7600d6(注入cache化)+0c73c7d1c(完了timing/通知)+e191bcf88(EXIT trap fallback報告メタデータ修復)=いずれも内部処理で、配備呼出し契約(引数・重複ガード・karo_direct経路)は不変。

<!-- script_refs_checked_at: 2026-07-16T23:40:33+0900
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->
Script refs verified: 2026-07-09 cmd_karo_hotfix_skill_refs_update_202607091452_saizo. `deploy_task.sh` 前回checked_at以降の変更(bddf2a457/0cb0954e3/14b74c865)をgit showで確認。bddf2a457はproject=dm-signal かつ PF削除/復元/rollback関連purposeの時のみ発火する`inject_dm_signal_pf_operation_guardrails`追加(Level5知識注入の対象追加。scout/`--yaml`いずれの経路でも発火し得るが引数・通知契約には無関係)。0cb0954e3はgate_report_format_learning.yamlのJSON形式prefill_active判定grepバグ修正(内部AUTO-PREFILL発火条件の修正)。14b74c865は`--direct` training(cmd_training_*)専用のtemplate内容検証追加で、recon-dualが使う1人目`<cmd_id> <ninja1> scout`・2人目`--yaml <file> <ninja2>`経路には未到達。1人目正規配備と2人目`--yaml`配備の引数契約、safe_inbox_write通知、report template生成は変更なし。recon-dual手順の書き換えは不要。

<!-- script参照互換確認 2026-07-12: 参照先(yaml_field_set.sh/deploy_task.sh/ninja_monitor.sh)の直近変更はatomic mv/validate/fail-closed等の内部堅牢化のみでCLI引数・呼出手順の変更なし。本書の手順は現行スクリプトと互換(将軍git log現物確認) -->

<!-- 検分: 2026-07-12 shogun起動時gate WARN解消。checked_at以降の差分をgit logで確認 — gate_report_format.sh 8c576d849(AC3 hunk provenance判定=内部判定強化)/memory_db_query.sh 8ce7c5c26(ext4キャッシュ経由=内部速度)/deploy_task.sh 2ecaf21ba+0cc6175e6+5dc9e8423(chunk境界regex誤検知根治+lesson注入絞込+atomic mv=内部)/ninja_scope_commit.sh 42d06b1d5+13f46a918(fail-closed patch commit mode追加+CI fixture=内部)/ninja_monitor.sh b40e13d2c系(dedupe通知+stall FP抑制=内部)。いずれも呼び出し契約・手順・出口文言に変更なし -->
<!-- script_refs_checked_at: 2026-07-16T23:40:33+0900
