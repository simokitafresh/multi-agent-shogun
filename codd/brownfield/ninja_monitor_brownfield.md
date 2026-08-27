---
codd:
  node_id: doc:script:ninja-monitor-brownfield
  type: brownfield_report
  status: approved
  confidence: 0.9
  source: brownfield
  implementation:
  - scripts/ninja_monitor.sh
---

# Brownfield Report

## Summary

- extract_output: `/home/simokitafresh/multi-agent-shogun/codd/brownfield_targets/ninja_monitor/.codd/extract`
- extract_input: `/home/simokitafresh/multi-agent-shogun/codd/brownfield_targets/ninja_monitor/.codd/extract/extracted.md`
- requirements_path: `skipped`
- lexicon_path: `discovery mode`
- diff_findings: 0
- elicit_findings: 10
- merged_findings: 10

# Findings

## Implementation Evidence Update

The brownfield findings below were generated from broad context and should now be read with the current implementation evidence in [[ninja_monitor.sh]], plus operating context in [[infrastructure]] and [[training-cycle]].

- `stall_detection_threshold` / `polling_interval`: implementation evidence exists. `ninja_monitor.sh` defines `STALL_THRESHOLD_MIN`, `POLL_INTERVAL`, and `CONFIRM_WAIT`; the remaining gap is whether the report should mark these findings resolved or keep them open for behavior-level explanation.
- `monitoring_scope`: implementation evidence exists. `ninja_monitor.sh` builds `NINJA_NAMES` from `get_ninja_names`, with comments stating karo and shogun are excluded.
- `send_keys_mechanism`: implementation evidence exists. `safe_send_clear()` gates reset through `check_idle()` and `can_send_clear_with_report_gate()`, then uses Codex `respawn-pane -k` for Codex agents and `safe_send_keys_atomic` for non-Codex reset.
- `error_handling_monitor_failure`: implementation evidence exists in [[daemon_watchdog.sh]]. `check_ninja_monitor()` verifies the pid file/live process, restarts `scripts/ninja_monitor.sh`, throttles restart storms, and emits watchdog notifications; the remaining gap is whether this external watchdog should close or downgrade the original high-severity finding.
- `task_yaml_race_condition`: implementation evidence exists. `ninja_monitor.sh` wraps auto-void and auto-done task mutations in `/tmp/task_${name}.lock`, revalidates parent/task identity after lock acquisition, and writes status through [[yaml_field_set.sh]] instead of direct YAML rewrites.

<!-- codd:finding
{"details": {"gap": "STALLの定義（時間ベース/出力ベース/状態ベース）と閾値が明示されていない", "source": "CLAUDE.md: 'Ghost deployment checkはninja_monitorのSTALL検知が常時カバー'"}, "id": "stall_detection_threshold", "kind": "behavioral_specification", "name": "STALL検知の閾値・判定基準が未定義", "question": "ninja_monitorがSTALLと判定する条件は何か？時間閾値、出力停止、capture-paneの内容パターン等、具体的な判定ロジックはどう定義されているか？", "rationale": "STALL検知は家老の手動チェックを代替する自動化機能。閾値が不明だと偽陽性/偽陰性のリスクが評価できない", "related_requirement_ids": ["ghost_deployment_check"], "severity": "high", "source": "greenfield"}
-->
## stall_detection_threshold - STALL検知の閾値・判定基準が未定義

- approval: [ ] `stall_detection_threshold`
- id: `stall_detection_threshold`
- kind: `behavioral_specification`
- severity: `high`
- name: STALL検知の閾値・判定基準が未定義
- question: ninja_monitorがSTALLと判定する条件は何か？時間閾値、出力停止、capture-paneの内容パターン等、具体的な判定ロジックはどう定義されているか？
- rationale: STALL検知は家老の手動チェックを代替する自動化機能。閾値が不明だと偽陽性/偽陰性のリスクが評価できない
- related_requirement_ids: `ghost_deployment_check`

```yaml
source: 'CLAUDE.md: ''Ghost deployment checkはninja_monitorのSTALL検知が常時カバー'''
gap: STALLの定義（時間ベース/出力ベース/状態ベース）と閾値が明示されていない
```

<!-- codd:finding
{"details": {"gap": "idle状態の判定方法と/clearまでの遷移タイミングが未定義", "source": "CLAUDE.md: 'ninja_monitor: idle+タスクなし→無条件/clear'"}, "id": "idle_clear_conditions", "kind": "state_transition", "name": "idle+タスクなし→/clear の状態遷移条件が不完全", "question": "「idle」の判定方法は何か？タスクYAMLのstatus確認か、capture-paneの出力パターンか、両方の組合せか？idle判定から/clear実行までの猶予時間はあるか？", "rationale": "作業完了直後の報告YAML書込み中に誤って/clearされるとデータ消失のリスクがある", "related_requirement_ids": ["ctx_management"], "severity": "high", "source": "greenfield"}
-->
## idle_clear_conditions - idle+タスクなし→/clear の状態遷移条件が不完全

- approval: [ ] `idle_clear_conditions`
- id: `idle_clear_conditions`
- kind: `state_transition`
- severity: `high`
- name: idle+タスクなし→/clear の状態遷移条件が不完全
- question: 「idle」の判定方法は何か？タスクYAMLのstatus確認か、capture-paneの出力パターンか、両方の組合せか？idle判定から/clear実行までの猶予時間はあるか？
- rationale: 作業完了直後の報告YAML書込み中に誤って/clearされるとデータ消失のリスクがある
- related_requirement_ids: `ctx_management`

```yaml
source: 'CLAUDE.md: ''ninja_monitor: idle+タスクなし→無条件/clear'''
gap: idle状態の判定方法と/clearまでの遷移タイミングが未定義
```

<!-- codd:finding
{"details": {"gap": "両メカニズムが同時に発動した場合の挙動が不明", "source": "CLAUDE.md: 'AUTOCOMPACT=90%' と 'ninja_monitor: idle+タスクなし→無条件/clear'"}, "id": "clear_vs_autocompact_interaction", "kind": "system_interaction", "name": "ninja_monitorの/clearとAUTOCOMPACT=90%の相互作用が未定義", "question": "AUTOCOMPACT=90%で自動圧縮が走る場合とninja_monitorが/clearを発行する場合の優先順位・排他制御はどうなっているか？", "rationale": "AUTOCOMPACT中に/clearが発行されると状態が不整合になる可能性がある", "related_requirement_ids": ["ctx_management", "autocompact"], "severity": "medium", "source": "greenfield"}
-->
## clear_vs_autocompact_interaction - ninja_monitorの/clearとAUTOCOMPACT=90%の相互作用が未定義

- approval: [ ] `clear_vs_autocompact_interaction`
- id: `clear_vs_autocompact_interaction`
- kind: `system_interaction`
- severity: `medium`
- name: ninja_monitorの/clearとAUTOCOMPACT=90%の相互作用が未定義
- question: AUTOCOMPACT=90%で自動圧縮が走る場合とninja_monitorが/clearを発行する場合の優先順位・排他制御はどうなっているか？
- rationale: AUTOCOMPACT中に/clearが発行されると状態が不整合になる可能性がある
- related_requirement_ids: `ctx_management`, `autocompact`

```yaml
source: 'CLAUDE.md: ''AUTOCOMPACT=90%'' と ''ninja_monitor: idle+タスクなし→無条件/clear'''
gap: 両メカニズムが同時に発動した場合の挙動が不明
```

<!-- codd:finding
{"details": {"gap": "監視対象の明示的なスコープ定義がない", "source": "CLAUDE.md agent table: 6忍者+軍師+家老"}, "id": "monitoring_scope", "kind": "scope_definition", "name": "監視対象ペインの範囲が未定義", "question": "ninja_monitorは忍者6名(hayate/kagemaru/hanzo/saizo/kotaro/tobisaru)全員を監視するか？家老(karo)・軍師(gunshi)も対象か？将軍は対象外か？", "rationale": "名前は'ninja_monitor'だが、STALL検知やidle/clearが他ロールにも適用されるか不明", "related_requirement_ids": [], "severity": "medium", "source": "greenfield"}
-->
## monitoring_scope - 監視対象ペインの範囲が未定義

- approval: [ ] `monitoring_scope`
- id: `monitoring_scope`
- kind: `scope_definition`
- severity: `medium`
- name: 監視対象ペインの範囲が未定義
- question: ninja_monitorは忍者6名(hayate/kagemaru/hanzo/saizo/kotaro/tobisaru)全員を監視するか？家老(karo)・軍師(gunshi)も対象か？将軍は対象外か？
- rationale: 名前は'ninja_monitor'だが、STALL検知やidle/clearが他ロールにも適用されるか不明

```yaml
source: 'CLAUDE.md agent table: 6忍者+軍師+家老'
gap: 監視対象の明示的なスコープ定義がない
```

<!-- codd:finding
{"details": {"gap": "/clear発行がinbox_write経由かsend-keys直接かの実装パスが不明", "source": "CLAUDE.md: 'inbox_write type: clear_command → sends /clear + Enter + content'"}, "id": "send_keys_mechanism", "kind": "implementation_detail", "name": "/clear発行時のtmux send-keys使用とinbox_writeの整合性", "question": "ninja_monitorは/clear発行にtmux send-keysを直接使用するか？CLAUDE.mdの'Agents NEVER call tmux send-keys directly'ルールとの関係は？ninja_monitorはagentではなくinfrastructure扱いか？", "rationale": "インフラ層のスクリプトとエージェント間通信プロトコルの境界が曖昧", "related_requirement_ids": ["communication_protocol"], "severity": "medium", "source": "greenfield"}
-->
## send_keys_mechanism - /clear発行時のtmux send-keys使用とinbox_writeの整合性

- approval: [ ] `send_keys_mechanism`
- id: `send_keys_mechanism`
- kind: `implementation_detail`
- severity: `medium`
- name: /clear発行時のtmux send-keys使用とinbox_writeの整合性
- question: ninja_monitorは/clear発行にtmux send-keysを直接使用するか？CLAUDE.mdの'Agents NEVER call tmux send-keys directly'ルールとの関係は？ninja_monitorはagentではなくinfrastructure扱いか？
- rationale: インフラ層のスクリプトとエージェント間通信プロトコルの境界が曖昧
- related_requirement_ids: `communication_protocol`

```yaml
source: 'CLAUDE.md: ''inbox_write type: clear_command → sends /clear + Enter + content'''
gap: /clear発行がinbox_write経由かsend-keys直接かの実装パスが不明
```

<!-- codd:finding
{"details": {"gap": "監視者自身の監視(quis custodiet ipsos custodes)が未定義"}, "id": "error_handling_monitor_failure", "kind": "fault_tolerance", "name": "ninja_monitor自身の障害時の挙動が未定義", "question": "ninja_monitorプロセスがクラッシュまたはハングした場合の検知・自動復旧メカニズムはあるか？watchdog的な上位監視は存在するか？", "rationale": "ninja_monitorが停止すると全忍者のSTALL検知とidle/clearが機能停止し、CTXオーバーフローやゴーストデプロイが検知されなくなる", "related_requirement_ids": [], "severity": "high", "source": "greenfield"}
-->
## error_handling_monitor_failure - ninja_monitor自身の障害時の挙動が未定義

- approval: [ ] `error_handling_monitor_failure`
- id: `error_handling_monitor_failure`
- kind: `fault_tolerance`
- severity: `high`
- name: ninja_monitor自身の障害時の挙動が未定義
- question: ninja_monitorプロセスがクラッシュまたはハングした場合の検知・自動復旧メカニズムはあるか？watchdog的な上位監視は存在するか？
- rationale: ninja_monitorが停止すると全忍者のSTALL検知とidle/clearが機能停止し、CTXオーバーフローやゴーストデプロイが検知されなくなる

Implementation evidence: [[daemon_watchdog.sh]] has a dedicated `check_ninja_monitor()` path that checks the pid file/live process, restarts `scripts/ninja_monitor.sh`, records restart attempts, and notifies on restart failure or restart storms.

```yaml
gap: 監視者自身の監視(quis custodiet ipsos custodes)が未定義
```

<!-- codd:finding
{"details": {"gap": "ポーリング間隔とリソース消費のトレードオフが未定義", "source": "CLAUDE.md: 'WSL2 /mnt/c上=statポーリング'"}, "id": "polling_interval", "kind": "performance_specification", "name": "監視ポーリング間隔が未定義", "question": "ninja_monitorの監視サイクル（capture-pane取得、タスクYAML確認等）の実行間隔は何秒か？WSL2のstat制約(inotifywatchの代替ポーリング)との整合性は？", "rationale": "間隔が短すぎるとWSL2上のI/O負荷が増大、長すぎるとSTALL検知が遅延する", "related_requirement_ids": ["wsl2_constraints"], "severity": "medium", "source": "greenfield"}
-->
## polling_interval - 監視ポーリング間隔が未定義

- approval: [ ] `polling_interval`
- id: `polling_interval`
- kind: `performance_specification`
- severity: `medium`
- name: 監視ポーリング間隔が未定義
- question: ninja_monitorの監視サイクル（capture-pane取得、タスクYAML確認等）の実行間隔は何秒か？WSL2のstat制約(inotifywatchの代替ポーリング)との整合性は？
- rationale: 間隔が短すぎるとWSL2上のI/O負荷が増大、長すぎるとSTALL検知が遅延する
- related_requirement_ids: `wsl2_constraints`

```yaml
source: 'CLAUDE.md: ''WSL2 /mnt/c上=statポーリング'''
gap: ポーリング間隔とリソース消費のトレードオフが未定義
```

<!-- codd:finding
{"details": {"gap": "検知→通知→対応のフロー全体が未定義"}, "id": "karo_notification", "kind": "notification_flow", "name": "STALL検知時の通知先・通知方法が未定義", "question": "ninja_monitorがSTALLを検知した場合、家老への通知はinbox_write経由か？ntfy経由で殿にも通知するか？/clearで自動復旧する場合は通知不要か？", "rationale": "STALLの種類によって適切な対応（/clear, 家老介入, 殿通知）が異なるはず", "related_requirement_ids": ["communication_protocol", "report_flow"], "severity": "medium", "source": "greenfield"}
-->
## karo_notification - STALL検知時の通知先・通知方法が未定義

- approval: [ ] `karo_notification`
- id: `karo_notification`
- kind: `notification_flow`
- severity: `medium`
- name: STALL検知時の通知先・通知方法が未定義
- question: ninja_monitorがSTALLを検知した場合、家老への通知はinbox_write経由か？ntfy経由で殿にも通知するか？/clearで自動復旧する場合は通知不要か？
- rationale: STALLの種類によって適切な対応（/clear, 家老介入, 殿通知）が異なるはず
- related_requirement_ids: `communication_protocol`, `report_flow`

```yaml
gap: 検知→通知→対応のフロー全体が未定義
```

<!-- codd:finding
{"details": {"gap": "ninja_monitorとkaro間のファイルロック戦略が未定義"}, "id": "task_yaml_race_condition", "kind": "concurrency", "name": "タスクYAML読取りと家老の書込みの競合", "question": "ninja_monitorがtask YAMLのstatus確認中に家老がタスクを配備（YAML書込み）した場合のrace conditionは考慮されているか？flock等の排他制御はあるか？", "rationale": "idleと判定して/clearした直後にタスクが配備されると、忍者が新タスクを受け取れない", "related_requirement_ids": [], "severity": "medium", "source": "greenfield"}
-->
## task_yaml_race_condition - タスクYAML読取りと家老の書込みの競合

- approval: [ ] `task_yaml_race_condition`
- id: `task_yaml_race_condition`
- kind: `concurrency`
- severity: `medium`
- name: タスクYAML読取りと家老の書込みの競合
- question: ninja_monitorがtask YAMLのstatus確認中に家老がタスクを配備（YAML書込み）した場合のrace conditionは考慮されているか？flock等の排他制御はあるか？
- rationale: idleと判定して/clearした直後にタスクが配備されると、忍者が新タスクを受け取れない

Implementation evidence: `ninja_monitor.sh` uses per-ninja flock files around task status mutation, rechecks `parent_cmd`/`task_id` inside the lock, and delegates the actual YAML write to [[yaml_field_set.sh]].

```yaml
gap: ninja_monitorとkaro間のファイルロック戦略が未定義
```

<!-- codd:finding
{"details": {"note": "outside_lexicon_scope", "source": "working directory: codd/brownfield_targets/ninja_monitor"}, "id": "brownfield_codd_coverage", "kind": "codd_integration", "name": "CoDD brownfield対象としての設計書カバレッジが不明", "question": "ninja_monitorの既存コードに対してCoDD設計書(spec/plan)はどの程度生成済みか？brownfield_targetsに配置されている意図は新規CoDD化か？", "rationale": "CoDD brownfield対象であることは作業ディレクトリから明らかだが、現在のカバレッジ状態と目標が不明", "related_requirement_ids": [], "severity": "info", "source": "greenfield"}
-->
## brownfield_codd_coverage - CoDD brownfield対象としての設計書カバレッジが不明

- approval: [ ] `brownfield_codd_coverage`
- id: `brownfield_codd_coverage`
- kind: `codd_integration`
- severity: `info`
- name: CoDD brownfield対象としての設計書カバレッジが不明
- question: ninja_monitorの既存コードに対してCoDD設計書(spec/plan)はどの程度生成済みか？brownfield_targetsに配置されている意図は新規CoDD化か？
- rationale: CoDD brownfield対象であることは作業ディレクトリから明らかだが、現在のカバレッジ状態と目標が不明

```yaml
note: outside_lexicon_scope
source: 'working directory: codd/brownfield_targets/ninja_monitor'
```
