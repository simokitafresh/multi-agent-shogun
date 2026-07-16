---
<!-- script_refs_checked_at: 2026-07-16T14:00:00+09:00 -->
<!-- 将軍D0検分: deploy_task.sh 72fc07d15(LG055 operational_simulationテンプレート事前生成)。内部テンプレート追加のみ、--direct/--yaml配備CLIと重複guard契約は不変。 -->
<!-- script_refs_checked_at: 2026-07-15T21:27:50+09:00 -->
<!-- cmd_karo_hotfix_skill_refs_core_202607152126検分: deploy_task.sh 22609351d/6c2eea753/7a8dd1c68をgit showで確認。report summary事前供給、分析cmdのreadonly_ref抽出拡張、readonly_ref再注入の冪等化はいずれも配備内部の文脈生成強化。`--yaml <file> <ninja>`、`--direct <ninja> <cmd_id>`、`--direct --yaml <file> <ninja>`の引数・重複guard・通知契約は不変。 -->
<!-- script_refs_checked_at: 2026-07-15T05:58:00+09:00 -->
<!-- 2026-07-15検分: deploy_task.shはspeed campaign固有report名を保存。karo-directの配備CLI・重複guard回避契約は不変。 -->
name: karo-direct
argument-hint: "[task_id] [ninja_name] [reason]"
description: |
  【家老専用】将軍cmd不要の家老自立配備(karo_direct)を標準化するスキル。
  CI修正・修行・偵察2人目など、将軍cmdなしで家老が直接忍者に配備する場合に使用。
  deploy_task.shの重複ガード回避を安全に処理する。
  TRIGGER: /karo-direct、karo_direct配備、家老自立配備、CI修正配備
  DO NOT TRIGGER: 将軍cmdの通常配備（→deploy_task.sh直接）、偵察1名配備（→通常配備）
quality_metric: "当該スキルで配備したkaro_directタスクのgate通過率（完了時cmd_complete_gate.sh CLEAR割合）"
allowed-tools:
  - Bash
  - Read
---

<!-- script_refs_checked_at: 2026-07-15T18:29:00+09:00 -->
<!-- cmd_karo_hotfix_skill_refs_202607151824検分: deploy_task.sh 26dd9b29c/9adea0b76/81162392b/7042b59e9をgit showで確認。lesson割当集合、cmd時間契約投影、direct YAML repair import補完の内部強化で、deploy_task.sh引数・重複guard・配備/nudge副作用契約は不変。 -->
<!-- cmd_karo_hotfix_skill_refs_after_infra_202607151211: deploy_task.sh 336f30b67はpost-deploy delivery evidenceのcapture範囲を30行へ拡張。配備CLI・renudge出口契約は維持。 -->

<!-- script_refs_checked_at: 2026-07-15T03:25:00+09:00 -->
<!-- cmd_3948検分: deploy_task.sh直近差分はtask publication直列化・malformed YAML修復。配備CLI契約不変。 -->
<!-- 検分: deploy_task.sh 758585318/030d267bb/680edbe74/f5431606f/6cab52d61/880976003/87ef68b76をgit showで確認。履歴mapping、staged continuation、独立recon、配備前source検証、direct品質projection、no-code report契約を強化。CLI引数は不変だが、10分超taskの自然境界契約が追加されたため本文を現行化。 -->

Script refs verified: 2026-07-13 将軍検分. `deploy_task.sh` checked_at以降の変更(793d03399..1f55aae59: 自然境界mapping検証+reopened parent解決+formal approval連動)をgit logで確認。karo_direct呼出し契約(--yaml経路含む)不変。親AC偽CLEAR hotfix RC継続中のため次回commit時に再検分される。手順書き換え不要。
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->
Script refs verified: 2026-07-10 cmd_karo_hotfix_skill_refs_202607101945 follow-up. `parse_deploy_task_args`と`tests/unit/test_deploy_task_yaml_injection.bats`を実検分し、`--direct --yaml <yaml_file> <ninja_name>`が正式対応済みで、source YAMLのACをcmd sourceで上書きせず保持する契約を確認。trainingは手製の不完全YAMLを禁止する一方、`queue/training`のauto-generated完全AC YAMLはこの複合経路を正本として配備する。
Script refs verified: 2026-07-10 cmd_karo_hotfix_skill_ref_freshness_202607101154_normal. `deploy_task.sh` checked_at以降の変更(b458129d1)をgit showで確認。ACに'push'語を含むtask YAMLへ配備時`push_allowed:true`を自動付与する`inject_push_allowed()`を追加(cmd_3820 G2ガードBLOCK再発防止、Level5知識注入)。`deploy_task_apply_task_mutations`内の内部注入チェーン追加のみで、`--yaml <yaml_file> <ninja_name>` / `--direct <ninja_name> <cmd_id>` の呼び出し契約、通知、report template生成、stale field resetは変更なし。karo-direct手順の書き換えは不要。

<!-- script_refs_checked_at: 2026-07-13T07:55:00+09:00 -->
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->

Script refs verified: 2026-07-08 cmd_karo_hotfix_skill_refs_202607081021. `deploy_task.sh` checked_at以降の変更(edb26ea1/0c73c7d1/f5f7600d)をgit showで確認。edb26ea1はrecon/scoutタイプreport templateへ`verified_existing_dependency: []`雛形とコメント例を追加(LG037除外宣言用)。0c73c7d1はtask YAML配備時のbatch flock書込みに`deployed_at`/`acknowledged_at`/`done_at`/`completed_at`初期化を追加(throughput計測用)。f5f7600dはinject_related_lessons等4関数のmemory-db参照をmemory_db_query.sh経由のext4キャッシュへ寄せ、注入処理を約140秒→約3秒へ高速化した内部性能改善のみ。いずれも`bash scripts/deploy_task.sh --yaml <yaml_file> <ninja_name>` / `--direct <ninja_name> <cmd_id>` の呼び出し契約、通知、stale field resetは変更なし。karo-direct手順の書き換えは不要。

Script refs verified: 2026-07-04 cmd_karo_hotfix_skill_refs_after_deploy_task_202607041407. `deploy_task.sh` 直近変更(fc056d4b2+da70ad039)をgit log/showで確認。fc056d4b2はreport templateの`files_modified`雛形とbinary_checks生成の内部強化、da70ad039は`deploy_task_guard_target_path_collision`追加による活動中taskとの同一file `target_path` 衝突の配備前BLOCK(directory重複はINFO)で、いずれも安全強化。`--yaml <yaml_file> <ninja_name>` / `--direct <ninja_name> <cmd_id>` の呼び出し契約、通知、report template生成、stale field resetは変更なし。karo-direct手順は現行仕様と一致し、同一file target衝突時はdeploy_task.shのBLOCKに従い別忍者/別target選定または先行task完了待ちとする。

Script refs verified: 2026-07-02 cmd_karo_hotfix_skill_script_refs_202607021234. 対象scriptの2026-07-02T01:12以降差分をgit log/showで確認。直近変更は速度改善・内部検査強化・テンプレート修復・files_modified path guardで、各SKILL本文の呼び出し契約は維持。

Script refs verified: 2026-07-02 cmd_karo_hotfix_shogun_startup_memory_skill_refs_20260702010546. `deploy_task.sh` 直近変更(a9a3bb08/42d661ef/a4297c73/d46b3e93/4e8e692/07f264d5)はAC parse、stale reset対象追加、lesson postcondition順序の内部修正で、`bash scripts/deploy_task.sh --yaml <yaml_file> <ninja_name>` と `--direct <ninja_name> <cmd_id>` の呼び出し契約、通知、report template生成、stale field resetは変更なし。

Script refs verified: 2026-07-01 idle useful-rate analysis follow-up. `deploy_task.sh` 直近変更は `target_files` を明示した教訓をタグ一致より強い制約として扱い、不一致なら `related_lessons` から除外する修正。狭義教訓が別ファイルtaskへ漏れて useful率を汚す経路を遮断した内部注入精度改善であり、`--yaml <yaml_file> <ninja_name>` / `--direct <ninja_name> <cmd_training_...>` の引数契約、通知、report template生成、stale field resetは変更なし。

Script refs verified: 2026-06-28 cmd_3582/e13c60e60. `deploy_task.sh` 直近変更は `get_japanese_name` 経由で忍者名の日本語対応をSSOT化し、`inject_workaround_pattern_lessons` で `logs/karo_workarounds.yaml` の頻発WAカテゴリから関連教訓を `related_lessons`/descriptionへ注入する内部コンテキスト提供追加。`--yaml <yaml_file> <ninja_name>` / `--direct <ninja_name> <cmd_training_...>` の引数契約、通知、report template生成、stale field resetは変更なし。
Script refs verified: 2026-06-16 cmd_3413. `deploy_task.sh` 直近変更(9fe724dda)はtask_tags空+target_pathあり時のpath-dirタグ推定追加。lesson注入タグ生成の内部ロジックであり、`--yaml <yaml_file> <ninja_name>` / `--direct <ninja_name> <cmd_training_...>` の引数・通知契約、report template生成、safe_inbox_write経路は変更なし。
Script refs verified: 2026-06-16 cmd_3405. `deploy_task.sh` 直近変更(1ef582caf)はMAX_INJECT 10→3に縮小。useful_rate=16.7%(<30%)の根因=過剰注入の修正。`--yaml <yaml_file> <ninja_name>` / `--direct <ninja_name> <cmd_training_...>` の引数・通知契約、report template生成、safe_inbox_write経路は変更なし。
Script refs verified: 2026-06-12 cmd_karo_hotfix_skill_refs_202606121132. `deploy_task.sh` 直近変更(d808770fc)はreadonly refsをtaskへ自動注入する内部コンテキスト提供追加。`--yaml <yaml_file> <ninja_name>` / `--direct <ninja_name> <cmd_training_...>` の引数・通知契約、report template生成、safe_inbox_write経路は変更なし。
Script refs verified: 2026-06-11. `deploy_task.sh` の契約は `--yaml <file> <ninja>` / `--direct <ninja> <cmd_id>` のまま。25d0b1e22は分割配備判定の内部修正で、karo_directのci_fix/recon2/hotfix用YAML配備とtraining用direct配備の引数・通知契約変更なし。
Script refs verified: 2026-06-11 ab0d45dad. `deploy_task.sh` はzero-useful lesson自動deprecatedを `ENABLE_ZERO_USEFUL_AUTO_DEPRECATE=1` 指定時の明示機能に変更した。lesson注入後の評価分母保護の内部挙動であり、karo_directの `--yaml <yaml_file> <ninja_name>` / training用 `--direct <ninja_name> <cmd_training_...>` の配備手順・通知契約変更なし。

# /karo-direct — 家老自立配備スキル

将軍cmd不要の配備を安全に実行。重複ガード回避の手順を標準化。

## 引数

`/karo-direct <task_type> <ninja_name> <purpose>`
- task_type: ci_fix | training | recon2 | hotfix
- ninja_name: idle忍者名
- purpose: タスクの目的（1行）

内部で使う `deploy_task.sh` は次の2系統:
- `bash scripts/deploy_task.sh --yaml <yaml_file> <ninja_name>`: ci_fix/recon2/hotfix用。YAML内の `parent_cmd:` を `CMD_ID` として自動取得する。
- `bash scripts/deploy_task.sh --direct <ninja_name> <cmd_id>`: trainingテンプレートをその場で自動生成する場合。
- `bash scripts/deploy_task.sh --direct --yaml <yaml_file> <ninja_name>`: `queue/training`でauto-generated済みの完全AC YAMLを配備する場合。source YAMLのACを保持する正本経路。

### 10分超taskの配備前契約（必須）

- `estimated_minutes <= 10`: 追加情報不要。
- `10 < estimated_minutes <= 15`: `split_decision`をexact 3キーで必須記入する。`boundary_ac_ids`は当該taskのAC IDから選ぶ重複なし非空list、`integration_tasks`と`review_round_trips`は0以上の整数で合計1以上。
- `estimated_minutes > 15`: `execution_env.long_runtime_reason`と正の`execution_env.measured_runtime_sec`を必須記入する。
- free-formの`split_decision_reason`は代替にならない。契約検証はtask YAML公開・既存task変更より前にfail-closedで行われる。

```yaml
estimated_minutes: 15
split_decision:
  boundary_ac_ids: [AC2]
  integration_tasks: 0
  review_round_trips: 1
```

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
  estimated_minutes: <positive number>
  acceptance_criteria:
    AC1:
      description: "<AC内容>"
    AC2:
      description: "gate/hookの未解消条件が1件でもあればPASSにせずBLOCKとして報告する"
  quality_gate:
    action_conversion: "検出した未解消条件はBLOCKへ変換する"
    fp_measurement: "gate_fire_logまたはdetector_fp_rateでfalse_positive件数を計測する"
  status: assigned
YAML
```

`purpose` / ACにgate・hookの追加/実装/作成を含むと、`deploy_task.sh` は detector quality contractを配備前にfail-closedで検査する。action conversionの判定対象は`command`と`acceptance_criteria`であり、`quality_gate.action_conversion`だけでは代替不可。上記AC2のようにBLOCK/停止/強制をACへ明記し、`quality_gate.fp_measurement`に`false_positive` / `偽陽性` / `detector_fp_rate` / `gate_fire_log`の計測接続を記入する。

**★projectは作業実体で選べ（current_projectに流すな）**: CI修正・gate/hook/context索引・スクリプト修正等のインフラ系作業は、対象ファイルがPJ名を含んでも `project: infra` を指定する。
判定基準=「変更/調査するのは何のコードか」（例: context/dm-signal-research.mdの鮮度回復=contextインフラ作業→infra）。
理由: project指定が教訓注入のスコープになる。GA-038でproject: dm-signal指定→dm-signal教訓10件が10/10無駄打ちし、lesson useful率を9.4%まで汚染した(2026-06-11軍師計測)。

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
Script refs verified: 2026-06-02 cmd_3119/3121/3126 (`inject_related_lessons` は semantic-map 由来boostに加え、memory DB `event_concepts` に接続した過去eventから lesson ID を抽出してboostする。`task_type=impl` の `MIN_KEYWORD_SCORE` は6へ引上げ。memory DB boost発生時は概念数・lesson数・event数をstderrログへ出す。いずれも注入精度/可観測性の変更であり、karo_directの配備手順変更なし). 2026-05-29 cmd_3107/a4a64068 (`deploy_task.sh` の `inbox_write.sh` 呼び出しは draft_review に `review_request`、status_update に `status_update` の第5引数を渡す。karo_directの配備手順変更なし). 2026-05-29 cmd_3091 (report templateのbinary_checks注入ログでAC数を `grep -c` ではなくawkで堅牢に数える。配備手順変更なし). 2026-05-27 cmd_3062 (cmd_3062: `inject_related_lessons` は `target_path` / `files_modified` と教訓 `target_files` が一致した場合に `TARGET_PATH_MATCH_BOOST` で順位を上げる。注入精度の変更であり、karo_directの配備手順変更なし。cmd_3019: q11_not_already_done再確認WARNは `deploy_task.sh --yaml/--direct` 共通経路で自動実行されるため手順追記不要。cmd_3020: universal lessonsのtarget_path関連フィルタは注入内容の精度変更で、karo_directの配備手順変更なし。cmd_2852: context hints・PI注入のブロック挿入にinsert_task_block_before_description()ヘルパーを導入。sed -iの改行問題を解消し、descriptionブロック直前への挿入を確実化。cmd_2883: stale field reset対象に `scope`、`context_hints`、`context` を追加し、前taskのscope/context残留を防止。cmd_2899: target_path存在チェックにproject_path 2段解決追加+相対パスのSCRIPT_DIR基準解決による偽陽性修正。cmd_2939: report filename生成でparent_cmd未設定時にcmd_idをフォールバックとして使用。cmd_2944: `_compute_ac_hash` はkaro_direct形式の `description:` なしACでも `check:` / `checks[].check` をフォールバックに使い、checks[]内の `- check:` をAC item境界と誤判定しない。cmd_2951: 配備前pending own report / completed peer reportをBLOCKし、cmd_complete_gate未完了の報告YAML消失を防止。cmd_2956: cmd_training_* で parent_cmd がnullishならcmd_idからparent_cmd/task_id/statusを修復。cmd_2957: trainingテンプレートは関連ファイルへの直接[[ファイル名]]リンク追加、リンク先特定行引用、直接リンク数baseline/diff報告を要求。cmd_2953: training target_pathは既存指定がなければ `markdown_link_counts.sh --select-file` 優先、未取得時のみ `semantic_alias_quality.sh` へフォールバック。cmd_2968: report templateのverdictは空値のみを出力し、gate_report_format.shがbinary_checksから自動導出する。手動記入禁止コメントは提出前チェック側に集約)。

### Step 4: 陣形図更新
karo_snapshot.txtの該当忍者行を更新（ninja_monitorが自動検知）。

## task_type別テンプレート

### ci_fix
```yaml
purpose: "CI RED修正 — <テスト名/エラー内容>"
acceptance_criteria:
  AC1: {description: "該当テストがPASS"}
  AC2: {description: "既存テストにリグレッションなし。gate/hook未解消ならBLOCK"}
quality_gate:
  action_conversion: "未解消条件はBLOCK"
  fp_measurement: "gate_fire_logでfalse_positive件数を計測"
```

### recon2
```yaml
purpose: "偵察補完 — <1人目の偵察結果を受けた追加調査>"
acceptance_criteria:
  AC1: {description: "1人目の偵察結果と突合し差異を明記"}
  AC2: {description: "修正対象ファイル・行番号・波及先を明記。gate/hook未解消ならBLOCK"}
quality_gate:
  action_conversion: "未解消条件はBLOCK"
  fp_measurement: "detector_fp_rateで偽陽性率を計測"
```

### training（必ず deploy_task.sh --direct 系経路を使え）
```bash
# 手製YAMLを使わず、その場で修行テンプレート(purpose/AC)を自動注入する場合。
# cmd_id は cmd_training_L4_r<round>_<ninja_name> 形式など、cmd_training_ で始める。
bash scripts/deploy_task.sh --direct <ninja_name> cmd_training_L4_r<round>_<ninja_name>
# --direct は parent_cmd/task_id/status を自動設定し、cmd_training_* なら target_path 自動選定後に
# inject_direct_training_template が purpose/ACを自動注入する。inbox_write は deploy_task.sh 内部で自動送信されるため不要。

# queue/trainingが生成した完全AC YAMLを使う場合。--directと--yamlの併用が正式契約。
# deploy_task.shはsource YAMLのACをcmd sourceで上書きせず、そのまま保持する。
bash scripts/deploy_task.sh --direct --yaml queue/training/<generated_task>.yaml <ninja_name>
```
`--direct`単独では手動でpurpose/ACを書かず、`inject_direct_training_template`に生成させる。`--direct --yaml`は`queue/training`のauto-generated完全AC YAMLに限る。

## 制約
- training タイプは `deploy_task.sh --direct`単独、または`queue/training`のauto-generated完全AC YAMLに限り`deploy_task.sh --direct --yaml <yaml_file> <ninja_name>`を使う。`/tmp`手製YAMLは禁止（AC未注入を引き起こす。cmd_training_L4_r16事故実証済み）
- ci_fix/recon2/hotfix タイプは `/tmp` に一時YAMLを作り、必ず `bash scripts/deploy_task.sh --yaml /tmp/karo_direct_task.yaml <ninja_name>` で配備する。直接 `cp` 禁止（stale field reset、parent_cmd/task_id/status設定、注入チェーン、report template生成、safe_inbox_write通知を迂回するため）
- `/tmp` YAMLには `parent_cmd: cmd_karo_<task_type>_<簡潔な説明>` を入れる。`--yaml` はこの値を配備cmdとして読む。
- 再配備前に対象忍者の既存reportを確認する。`deploy_task.sh` がpending own report / completed peer reportをBLOCKした場合は、cmd_complete_gate完了または別忍者選定まで配備済み扱いにしない。
- 複数行ACやdescriptionはdeploy_task.shの手動YAML構築でindent保持される。YAML注入後に `python3 -c "import yaml; yaml.safe_load(open('queue/tasks/<ninja>.yaml'))"` で構文確認する。
- 家老自立配備は殿裁定済み（CI RED即修正等は将軍cmd不要）

Script refs verified: 2026-06-07 cmd_3206. `deploy_task.sh` はearly target判定・field_getログ抑制など速度修行の内部高速化が入ったが、karo_directで使う `--yaml <yaml_file> <ninja>` とtraining用 `--direct <ninja> <cmd_training_...>` の契約は変更なし。DIRECT_MODEでは既存task YAMLのtraining parent_cmd補修をスキップし、`--direct`が注入するcmd_id/parent_cmdを正本にする。`yaml_field_set.sh` のlock path高速化もI/F変更なし。SKILL.md記載の配備方式は現行と一致。
Script refs verified: 2026-06-05 cmd_3146/cmd_3144. `deploy_task.sh` はlesson injectionで対象project外の教訓を除外し、platform project教訓のみ横断許可する(project filter)。これは注入精度の変更であり、`--yaml`/`--direct`配備手順変更なし。`deploy_task.sh` 直近変更(670918b3)は`draft_review_already_completed()`関数追加によるdraft review重複通知防止(内部追加のみ、配備手順変更なし)。SKILL.md記載の`--yaml`/`--direct`呼び出し方法は現行と一致。
Script refs verified: 2026-06-08 ceb10419a cmd_3231. `deploy_task.sh` はtarget_pathなし時にMIN_KEYWORD_SCOREを8へ引上げ、tag fallbackを無効化(低関連教訓のNOT_USEFUL量産防止)。注入精度の変更であり、`--yaml`/`--direct`配備手順変更なし。
Script refs verified: 2026-06-09 e72eb99d4+3de0d29cc. `deploy_task.sh` はinject_semantic_conceptsで推薦ログにninja_nameフィールドを記録(precision照合キー修正)。`yaml_field_set.sh` はskip_childrenがYAMLリスト要素(`- `始まり)を見逃すバグ修正。いずれも内部変更であり、`--yaml`/`--direct`配備手順変更なし。
Script refs verified: 2026-06-10. `deploy_task.sh` は(1)TRIGGER cross-validation追加: inject_semantic_conceptsのスキル推薦で、semantic matchだけでなくSKILL.mdのTRIGGERキーワードがpurposeに含まれるかを確認し偽陽性を除去。(2)boost適用にkeyword_score>0必須化(cmd_3254): keyword_score=0でもboost+project点で閾値突破していたNOT_USEFUL教訓の注入を防止。(3)flow-style YAML deprecation対応: `- {id: L723, ...}` パターンのdeprecated:true挿入。(4)lesson_impact.tsv空行混入防御: ensure_impact_headerのCR汚染対策+_is_empty_row空行フィルタ+DictWriter lineterminator="\n"明示。いずれも内部変更であり、`--yaml`/`--direct`配備手順変更なし。

## 関連スキル

- [[recon-dual]] — 偵察2名並列配備（recon2タスクタイプで使用）
- [[cmd-complete]] — cmd完了処理（GATE CLEAR後の全ステップ自動化）
- [[reset-layout]] — エージェントウィンドウのレイアウト復元（ペイン消失時）
- [[cdp-browse]] — ブラウザ自動化スキル（hotfix作業でウェブ確認が必要な場合）

Script refs verified: 2026-06-20 3421a1dc9+48204a464+782be65a6. `deploy_task.sh` 直近変更は教訓matching scoring調整、操作的オントロジー/targetフィルタ/スキル強制、PJパスSSOT化。`--yaml <yaml_file> <ninja_name>` / `--direct <ninja_name> <cmd_id>` の配備契約、通知、report template生成は変更なし。

Script refs verified: 2026-06-21 d81b77654. `deploy_task.sh` 直近変更はtag fallbackをtarget_files一致教訓に限定し、CIのlesson fallbackテストを現行仕様へ合わせたもの。`--yaml <yaml_file> <ninja_name>` / `--direct <ninja_name> <cmd_id>` の配備契約、通知、report template生成は変更なし。

Script refs verified: 2026-06-23 1586d6f48. `deploy_task.sh` 直近変更はGS/DB検出時execution_env自動注入(L5防御、cmd_3496事故恒久対策)。配備契約(`--yaml`/`--direct`)・通知・report template生成は変更なし。

Script refs verified: 2026-06-28 b1922e36b+0226e0db5. `deploy_task.sh` 直近変更はfailed redeploy時のgate扱い修正と、`shogun_to_karo.yaml`でstatus=canceledのcmd配備をBLOCKする安全強化。`--yaml <yaml_file> <ninja_name>` / `--direct <ninja_name> <cmd_id>` の引数契約、通知、report template生成は変更なし。

Script refs verified: 2026-07-07T18:19:00+09:00 (shogun復帰時WARN解消). `deploy_task.sh` 直近変更(88dae4ee5)をgit showで確認。`deploy_task_guard_direct_yaml_prewrite_collision`追加 — direct/--yamlモードでtask YAML書換え前に既存`deploy_task_guard_target_path_collision`を先行実行し、衝突時はtask未変更のままBLOCKする発火位置の前倒し。判定基準・呼び出し契約(`--yaml <yaml_file> <ninja_name>` / `--direct <ninja_name> <cmd_id>`)・通知・report template生成は変更なし。

<!-- script_refs_checked_at: 2026-07-13T07:55:00+09:00 -->
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->

<!-- script_refs_checked_at: 2026-07-13T07:55:00+09:00 -->
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->
Script refs verified: 2026-07-08 将軍検分. 前回checked_at以降の deploy_task.sh 差分は f5f7600d6(注入cache化)+0c73c7d1c(完了timing/通知)+e191bcf88(EXIT trap fallback報告メタデータ修復)=いずれも内部処理で、配備呼出し契約(引数・重複ガード・karo_direct経路)は不変。

<!-- script_refs_checked_at: 2026-07-13T07:55:00+09:00 -->
<!-- 検証(shogun 2026-07-11): yaml_field_set.sh(1fba56549 atomic公開+parse検証=内部変更)/deploy_task.sh(8be3eaf72 assumptions保全=内部変更)/cmd_complete_gate.sh(0a41c0110 perf=内部変更)。呼出しインターフェース不変、手順書換え不要 -->
Script refs verified: 2026-07-09 cmd_karo_hotfix_skill_refs_update_202607091452_saizo. `deploy_task.sh` 前回checked_at以降の変更(bddf2a457/0cb0954e3/14b74c865)をgit showで確認。bddf2a457はproject=dm-signal かつ PF削除/復元/rollback関連purposeの時のみ発火する`inject_dm_signal_pf_operation_guardrails`追加(Level5知識注入の対象追加)。0cb0954e3はgate_report_format_learning.yamlのJSON形式prefill_active判定grepバグ修正(内部AUTO-PREFILL発火条件の修正)。14b74c865は`--direct` training(cmd_training_*)専用のtemplate内容検証(AC1-AC5必須文言チェック)を`inject_direct_training_template`後に追加し、不備時はFATALでreturn 1する安全強化。ci_fix/recon2/hotfix用の`--yaml <yaml_file> <ninja_name>`引数契約・重複ガード・通知・report template生成には影響なし。karo-direct手順の書き換えは不要。

<!-- script参照互換確認 2026-07-12: 参照先(yaml_field_set.sh/deploy_task.sh/ninja_monitor.sh)の直近変更はatomic mv/validate/fail-closed等の内部堅牢化のみでCLI引数・呼出手順の変更なし。本書の手順は現行スクリプトと互換(将軍git log現物確認) -->

<!-- 検分: 2026-07-12 shogun起動時gate WARN解消。checked_at以降の差分をgit logで確認 — gate_report_format.sh 8c576d849(AC3 hunk provenance判定=内部判定強化)/memory_db_query.sh 8ce7c5c26(ext4キャッシュ経由=内部速度)/deploy_task.sh 2ecaf21ba+0cc6175e6+5dc9e8423(chunk境界regex誤検知根治+lesson注入絞込+atomic mv=内部)/ninja_scope_commit.sh 42d06b1d5+13f46a918(fail-closed patch commit mode追加+CI fixture=内部)/ninja_monitor.sh b40e13d2c系(dedupe通知+stall FP抑制=内部)。いずれも呼び出し契約・手順・出口文言に変更なし -->
<!-- script_refs_checked_at: 2026-07-13T07:55:00+09:00 -->
