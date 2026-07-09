---
name: recon-dual
argument-hint: "[cmd_id] [target_scope]"
description: |
  【家老専用】偵察2名配備(recon Pattern 1)を標準化するスキル。
  1人目をdeploy_task.sh、2人目をkaro_direct方式で配備し、重複ガード問題を回避。
  TRIGGER: /recon-dual、偵察2名配備、recon2配備、2名偵察
  DO NOT TRIGGER: 偵察1名配備（→deploy_task.sh直接）、karo_direct単独（→/karo-direct）
quality_metric: "当該スキルで配備した偵察2名タスクのgate通過率（完了時cmd_complete_gate.sh CLEAR割合）"
---

<!-- script_refs_checked_at: 2026-07-08T10:26:09+09:00 -->

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
grep "idle" queue/karo_snapshot.txt
```
指定2名がともにidleでなければ停止。

### Step 2: 1人目配備（deploy_task.sh）
```bash
bash scripts/deploy_task.sh <cmd_id> <ninja1> scout
```
deploy_task.shが正規のタスクYAML生成+教訓注入+inbox_writeを実行。

### Step 3: 2人目配備（karo_direct方式）
deploy_task.shの重複ガードを回避するため、/tmp YAMLを作って `--yaml` 経由で配備:
```bash
# 1人目のタスクYAMLをベースにrecon2用に調整（正式task YAMLへ直接cpしない）
cp queue/tasks/<ninja1>.yaml /tmp/recon2_<ninja2>.yaml
bash scripts/lib/yaml_field_set.sh /tmp/recon2_<ninja2>.yaml "task" "parent_cmd" "<cmd_id>_recon2"
bash scripts/lib/yaml_field_set.sh /tmp/recon2_<ninja2>.yaml "task" "cmd_id" "<cmd_id>_recon2"
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

<!-- script_refs_checked_at: 2026-07-07T18:19:00+09:00 -->

<!-- script_refs_checked_at: 2026-07-08T22:35:00+09:00 -->
Script refs verified: 2026-07-08 将軍検分. 前回checked_at以降の deploy_task.sh 差分は f5f7600d6(注入cache化)+0c73c7d1c(完了timing/通知)+e191bcf88(EXIT trap fallback報告メタデータ修復)=いずれも内部処理で、配備呼出し契約(引数・重複ガード・karo_direct経路)は不変。

<!-- script_refs_checked_at: 2026-07-09T14:56:35+09:00 -->
Script refs verified: 2026-07-09 cmd_karo_hotfix_skill_refs_update_202607091452_saizo. `deploy_task.sh` 前回checked_at以降の変更(bddf2a457/0cb0954e3/14b74c865)をgit showで確認。bddf2a457はproject=dm-signal かつ PF削除/復元/rollback関連purposeの時のみ発火する`inject_dm_signal_pf_operation_guardrails`追加(Level5知識注入の対象追加。scout/`--yaml`いずれの経路でも発火し得るが引数・通知契約には無関係)。0cb0954e3はgate_report_format_learning.yamlのJSON形式prefill_active判定grepバグ修正(内部AUTO-PREFILL発火条件の修正)。14b74c865は`--direct` training(cmd_training_*)専用のtemplate内容検証追加で、recon-dualが使う1人目`<cmd_id> <ninja1> scout`・2人目`--yaml <file> <ninja2>`経路には未到達。1人目正規配備と2人目`--yaml`配備の引数契約、safe_inbox_write通知、report template生成は変更なし。recon-dual手順の書き換えは不要。
