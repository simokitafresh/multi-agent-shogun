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

<!-- script_refs_checked_at: 2026-06-28T12:18:00+09:00 -->

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

<!-- script_refs_checked_at: 2026-06-28T23:18:00+09:00 -->
