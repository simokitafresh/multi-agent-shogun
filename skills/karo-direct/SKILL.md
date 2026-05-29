---
name: karo-direct
argument-hint: "[task_id] [ninja_name] [reason]"
description: |
  【家老専用】将軍cmd不要の家老自立配備(karo_direct)を標準化するスキル。
  CI修正・修行・偵察2人目など、将軍cmdなしで家老が直接忍者に配備する場合に使用。
  deploy_task.shの重複ガード回避を安全に処理する。
  TRIGGER: /karo-direct、karo_direct配備、家老自立配備、CI修正配備
  DO NOT TRIGGER: 将軍cmdの通常配備（→deploy_task.sh直接）、偵察1名配備（→通常配備）
quality_metric: "当該スキルで配備したkaro_directタスクのgate通過率（完了時cmd_complete_gate.sh CLEAR割合）"
---

<!-- script_refs_checked_at: 2026-05-29T20:07:36+09:00 -->

# /karo-direct — 家老自立配備スキル

将軍cmd不要の配備を安全に実行。重複ガード回避の手順を標準化。

## 引数

`/karo-direct <task_type> <ninja_name> <purpose>`
- task_type: ci_fix | training | recon2 | hotfix
- ninja_name: idle忍者名
- purpose: タスクの目的（1行）

内部で使う `deploy_task.sh` は次の2系統:
- `bash scripts/deploy_task.sh --yaml <yaml_file> <ninja_name>`: ci_fix/recon2/hotfix用。YAML内の `parent_cmd:` を `CMD_ID` として自動取得する。
- `bash scripts/deploy_task.sh --direct <ninja_name> <cmd_id>`: training用。`cmd_id` は `cmd_training_...` 形式にする。

## 実行フロー

### Step 1: idle忍者確認
```bash
# karo_snapshot.txtからidle忍者を確認
grep "idle" queue/karo_snapshot.txt
```
指定忍者がidleでなければ停止。

### Step 2: タスクYAML作成（ci_fix/recon2/hotfix）
```bash
# /tmp に一時YAML作成（deploy_task.shの重複ガード回避）
cat > /tmp/karo_direct_task.yaml << 'YAML'
task:
  parent_cmd: cmd_karo_<task_type>_<timestamp>
  task_type: <task_type>
  project: <project>
  purpose: <purpose>
  acceptance_criteria:
    AC1:
      description: "<AC内容>"
  status: assigned
YAML
```

### Step 3: タスク配備
```bash
# /tmp から deploy_task.sh --yaml 経由で配備する。
# --yaml は <yaml_file> <ninja_name> の順。parent_cmdはYAMLから自動取得される。
# deploy_task.sh は共通経路で reset_stale_fields を実行し、旧task YAMLの残留フィールドを清掃する。
bash scripts/deploy_task.sh --yaml /tmp/karo_direct_task.yaml <ninja_name>

# deploy_task.sh は共通入口で reset_stale_fields を完了してから /tmp YAML を task YAML に反映し、
# 前task由来の `scope`、`context_hints`、`context` も毎回クリアする。
# direct_mode として resolve_cmd_to_task をスキップする。
# その後 parent_cmd/status/task_id を設定し、通常配備と同じ注入チェーン
# (related_lessons, standard_skills, semantic_concepts, causal_links, growth_loop_defense,
# report_filename/report_path, weak_points など) と report template 生成を通す。
# 最後に safe_inbox_write で inbox 永続化を確認し、必要なら watcher失敗をWARN扱いで継続する。
# 手動 inbox_write は不要。
# YAML注入に失敗した場合、deploy_task.sh は deploy_error を家老inboxへ送る。
# failure通知が出たら配備済み扱いにせず、deploy_task.log と対象task YAMLを確認する。
# 配備前に同cmd・同忍者の未完了reportが残っている場合はBLOCKする。
# PASS/FAIL/PASS_NO_IMPROVEMENT verdict済みreportがある場合、cmd_complete_gate完了前の再配備を禁止する。
# exact以外で他忍者の完了済みpeer reportがある場合もBLOCKし、二重配備による報告YAML消失を防ぐ。
```
Script refs verified: 2026-05-29 cmd_3091 (report templateのbinary_checks注入ログでAC数を `grep -c` ではなくawkで堅牢に数える。配備手順変更なし). 2026-05-27 cmd_3062 (cmd_3062: `inject_related_lessons` は `target_path` / `files_modified` と教訓 `target_files` が一致した場合に `TARGET_PATH_MATCH_BOOST` で順位を上げる。注入精度の変更であり、karo_directの配備手順変更なし。cmd_3019: q11_not_already_done再確認WARNは `deploy_task.sh --yaml/--direct` 共通経路で自動実行されるため手順追記不要。cmd_3020: universal lessonsのtarget_path関連フィルタは注入内容の精度変更で、karo_directの配備手順変更なし。cmd_2852: context hints・PI注入のブロック挿入にinsert_task_block_before_description()ヘルパーを導入。sed -iの改行問題を解消し、descriptionブロック直前への挿入を確実化。cmd_2883: stale field reset対象に `scope`、`context_hints`、`context` を追加し、前taskのscope/context残留を防止。cmd_2899: target_path存在チェックにproject_path 2段解決追加+相対パスのSCRIPT_DIR基準解決による偽陽性修正。cmd_2939: report filename生成でparent_cmd未設定時にcmd_idをフォールバックとして使用。cmd_2944: `_compute_ac_hash` はkaro_direct形式の `description:` なしACでも `check:` / `checks[].check` をフォールバックに使い、checks[]内の `- check:` をAC item境界と誤判定しない。cmd_2951: 配備前pending own report / completed peer reportをBLOCKし、cmd_complete_gate未完了の報告YAML消失を防止。cmd_2956: cmd_training_* で parent_cmd がnullishならcmd_idからparent_cmd/task_id/statusを修復。cmd_2957: trainingテンプレートは関連ファイルへの直接[[ファイル名]]リンク追加、リンク先特定行引用、直接リンク数baseline/diff報告を要求。cmd_2953: training target_pathは既存指定がなければ `markdown_link_counts.sh --select-file` 優先、未取得時のみ `semantic_alias_quality.sh` へフォールバック。cmd_2968: report templateのverdictは空値のみを出力し、gate_report_format.shがbinary_checksから自動導出する。手動記入禁止コメントは提出前チェック側に集約)。

### Step 4: 陣形図更新
karo_snapshot.txtの該当忍者行を更新（ninja_monitorが自動検知）。

## task_type別テンプレート

### ci_fix
```yaml
purpose: "CI RED修正 — <テスト名/エラー内容>"
acceptance_criteria:
  AC1: {description: "該当テストがPASS"}
  AC2: {description: "既存テストにリグレッションなし"}
```

### recon2
```yaml
purpose: "偵察補完 — <1人目の偵察結果を受けた追加調査>"
acceptance_criteria:
  AC1: {description: "1人目の偵察結果と突合し差異を明記"}
  AC2: {description: "修正対象ファイル・行番号・波及先を明記"}
```

### training（必ず deploy_task.sh --direct を使え）
```bash
# ★ training だけは /tmp 手動YAML禁止。deploy_task.sh --direct が修行テンプレート(purpose/AC)を自動注入する。
# cmd_id は cmd_training_L4_r<round>_<ninja_name> 形式など、cmd_training_ で始める。
bash scripts/deploy_task.sh --direct <ninja_name> cmd_training_L4_r<round>_<ninja_name>
# --direct は parent_cmd/task_id/status を自動設定し、cmd_training_* なら target_path 自動選定後に
# inject_direct_training_template が purpose/ACを自動注入する。inbox_write は deploy_task.sh 内部で自動送信されるため不要。
```
手動でpurpose/ACを書いてはならない。inject_direct_training_template が自動注入する。

## 制約
- training タイプは deploy_task.sh --direct を使え。/tmp 手動YAML方式は AC 未注入を引き起こす（cmd_training_L4_r16 事故実証済み）
- ci_fix/recon2/hotfix タイプは `/tmp` に一時YAMLを作り、必ず `bash scripts/deploy_task.sh --yaml /tmp/karo_direct_task.yaml <ninja_name>` で配備する。直接 `cp` 禁止（stale field reset、parent_cmd/task_id/status設定、注入チェーン、report template生成、safe_inbox_write通知を迂回するため）
- `/tmp` YAMLには `parent_cmd: cmd_karo_<task_type>_<簡潔な説明>` を入れる。`--yaml` はこの値を配備cmdとして読む。
- 再配備前に対象忍者の既存reportを確認する。`deploy_task.sh` がpending own report / completed peer reportをBLOCKした場合は、cmd_complete_gate完了または別忍者選定まで配備済み扱いにしない。
- 複数行ACやdescriptionはdeploy_task.shの手動YAML構築でindent保持される。YAML注入後に `python3 -c "import yaml; yaml.safe_load(open('queue/tasks/<ninja>.yaml'))"` で構文確認する。
- 家老自立配備は殿裁定済み（CI RED即修正等は将軍cmd不要）
