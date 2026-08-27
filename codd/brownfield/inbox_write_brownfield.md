---
codd:
  node_id: doc:script:inbox-write-brownfield
  type: brownfield_report
  status: approved
  confidence: 0.9
  source: brownfield
  implementation:
  - scripts/inbox_write.sh
---

# Brownfield Report

## Summary

- extract_output: `/home/simokitafresh/multi-agent-shogun/codd/brownfield_targets/inbox_write/.codd/extract`
- extract_input: `/home/simokitafresh/multi-agent-shogun/codd/brownfield_targets/inbox_write/.codd/extract/extracted.md`
- requirements_path: `skipped`
- lexicon_path: `discovery mode`
- diff_findings: 0
- elicit_findings: 10
- merged_findings: 10

# Findings

## Cross-References

- [[inbox_write.sh]] is the executable mailbox writer; its header defines the CLI contract and supported message types.
- [[cmd_2762_inbox_write_requirements.md]] is the current brownfield requirements document for target validation, inbox serialization, locking, duplicate deployment blocking, and report notification behavior.
- [[inbox_write_design.md]] maps the implemented flow: validate routing, compute inbox/lock paths, append under lock, then run wake-up or downstream side effects.
- [[test_inbox_write.bats]] is the unit regression surface for argument validation, default fields, flock retry behavior, special character escaping, inbox initialization, and duplicate task assignment blocking.

<!-- codd:finding
{"details": {"context": "Elicitation L0の全入力フィールドが(none provided)。分析対象のドキュメントがない状態では網羅的なgap分析は不可能。"}, "id": "no_requirements_provided", "kind": "missing_input", "name": "要件定義ドキュメントが未提供", "question": "inbox_write.shの正式な要件定義書またはCoDD設計書(spec)は存在しますか？存在する場合、パスを教えてください。", "rationale": "要件が不明なままでは、カバレッジ評価もgap検出もできない。まずinbox_writeの仕様を明示する必要がある。", "related_requirement_ids": [], "severity": "critical", "source": "greenfield"}
-->
## no_requirements_provided - 要件定義ドキュメントが未提供

- approval: [ ] `no_requirements_provided`
- id: `no_requirements_provided`
- kind: `missing_input`
- severity: `critical`
- name: 要件定義ドキュメントが未提供
- question: inbox_write.shの正式な要件定義書またはCoDD設計書(spec)は存在しますか？存在する場合、パスを教えてください。
- rationale: 要件が不明なままでは、カバレッジ評価もgap検出もできない。まずinbox_writeの仕様を明示する必要がある。

```yaml
context: Elicitation L0の全入力フィールドが(none provided)。分析対象のドキュメントがない状態では網羅的なgap分析は不可能。
```

<!-- codd:finding
{"details": {"evidence": "CLAUDE.mdに'inbox_write.sh writes to queue/inbox/{agent}.yaml with flock'と記載あるが、タイムアウト値・リトライ戦略・デッドロック防止策の仕様が見当たらない"}, "id": "concurrency_safety", "kind": "race_condition", "name": "並行書込み時のflock挙動が未定義", "question": "複数エージェントが同時にinbox_write.shを呼んだ場合、flockのタイムアウトや競合解決の仕様は明文化されていますか？", "rationale": "6忍者+家老+将軍+軍師の最大9エージェントが並行稼働する環境で、flockの詳細挙動が未定義だとメッセージ消失やデッドロックのリスクがある。", "related_requirement_ids": [], "severity": "high", "source": "greenfield"}
-->
## concurrency_safety - 並行書込み時のflock挙動が未定義

- approval: [ ] `concurrency_safety`
- id: `concurrency_safety`
- kind: `race_condition`
- severity: `high`
- name: 並行書込み時のflock挙動が未定義
- question: 複数エージェントが同時にinbox_write.shを呼んだ場合、flockのタイムアウトや競合解決の仕様は明文化されていますか？
- rationale: 6忍者+家老+将軍+軍師の最大9エージェントが並行稼働する環境で、flockの詳細挙動が未定義だとメッセージ消失やデッドロックのリスクがある。

```yaml
evidence: CLAUDE.mdに'inbox_write.sh writes to queue/inbox/{agent}.yaml with flock'と記載あるが、タイムアウト値・リトライ戦略・デッドロック防止策の仕様が見当たらない
```

<!-- codd:finding
{"details": {"evidence": "CLAUDE.mdの使用例: bash scripts/inbox_write.sh <target_agent> \"<message>\" <type> <from>。引数の長さ制限、許可されるtype値の列挙、禁止文字のバリデーションが不明"}, "id": "message_schema_validation", "kind": "input_validation", "name": "メッセージ引数のバリデーション仕様が不明", "question": "inbox_write.shは不正な引数（空文字列、特殊文字、YAMLインジェクション文字列など）をどう処理しますか？", "rationale": "YAMLファイルへの直接書込みのため、メッセージ内容にYAML特殊文字(コロン、ハイフン等)が含まれるとパース破壊の可能性がある。", "related_requirement_ids": [], "severity": "high", "source": "greenfield"}
-->
## message_schema_validation - メッセージ引数のバリデーション仕様が不明

- approval: [ ] `message_schema_validation`
- id: `message_schema_validation`
- kind: `input_validation`
- severity: `high`
- name: メッセージ引数のバリデーション仕様が不明
- question: inbox_write.shは不正な引数（空文字列、特殊文字、YAMLインジェクション文字列など）をどう処理しますか？
- rationale: YAMLファイルへの直接書込みのため、メッセージ内容にYAML特殊文字(コロン、ハイフン等)が含まれるとパース破壊の可能性がある。

```yaml
evidence: 'CLAUDE.mdの使用例: bash scripts/inbox_write.sh <target_agent> "<message>" <type>
  <from>。引数の長さ制限、許可されるtype値の列挙、禁止文字のバリデーションが不明'
```

<!-- codd:finding
{"details": {"evidence": "inbox_mark_read.shが{msg_id}を引数に取ることから、各メッセージには一意のIDが付与されるはずだが、生成方式が不明"}, "id": "message_id_generation", "kind": "identity", "name": "メッセージID生成ロジックが未定義", "question": "msg_idはどのように生成されますか？（連番、UUID、タイムスタンプ等）衝突防止策はありますか？", "rationale": "ID衝突はメッセージの誤既読化やデータ不整合を引き起こす。", "related_requirement_ids": [], "severity": "medium", "source": "greenfield"}
-->
## message_id_generation - メッセージID生成ロジックが未定義

- approval: [ ] `message_id_generation`
- id: `message_id_generation`
- kind: `identity`
- severity: `medium`
- name: メッセージID生成ロジックが未定義
- question: msg_idはどのように生成されますか？（連番、UUID、タイムスタンプ等）衝突防止策はありますか？
- rationale: ID衝突はメッセージの誤既読化やデータ不整合を引き起こす。

```yaml
evidence: inbox_mark_read.shが{msg_id}を引数に取ることから、各メッセージには一意のIDが付与されるはずだが、生成方式が不明
```

<!-- codd:finding
{"details": {"evidence": "CLAUDE.md内に散在する使用例から上記typeを確認できるが、公式enumとしての定義場所が不明", "known_types": ["cmd_new", "report_received", "task_assigned", "clear_command", "model_switch", "training_directive"]}, "id": "type_enum_completeness", "kind": "data_model", "name": "typeフィールドの許容値一覧が散在", "question": "inbox_write.shが受け付けるtype値の完全な列挙はどこにありますか？", "rationale": "type値がenum定義されていないと、typoによるサイレント失敗や、watcher側の未知type処理漏れが起きる。", "related_requirement_ids": [], "severity": "medium", "source": "greenfield"}
-->
## type_enum_completeness - typeフィールドの許容値一覧が散在

- approval: [ ] `type_enum_completeness`
- id: `type_enum_completeness`
- kind: `data_model`
- severity: `medium`
- name: typeフィールドの許容値一覧が散在
- question: inbox_write.shが受け付けるtype値の完全な列挙はどこにありますか？
- rationale: type値がenum定義されていないと、typoによるサイレント失敗や、watcher側の未知type処理漏れが起きる。

```yaml
known_types:
- cmd_new
- report_received
- task_assigned
- clear_command
- model_switch
- training_directive
evidence: CLAUDE.md内に散在する使用例から上記typeを確認できるが、公式enumとしての定義場所が不明
```

<!-- codd:finding
{"details": {"valid_agents": ["shogun", "karo", "gunshi", "hayate", "kagemaru", "hanzo", "saizo", "kotaro", "tobisaru"]}, "id": "target_agent_validation", "kind": "input_validation", "name": "存在しないエージェント名指定時の挙動が不明", "question": "inbox_write.sh karo2 'test' cmd_new shogun のように存在しないエージェントを指定した場合、エラーになりますか？それともファイルが生成されますか？", "rationale": "typoで誤ったinboxファイルが生成されるとメッセージがブラックホール化する。", "related_requirement_ids": [], "severity": "medium", "source": "greenfield"}
-->
## target_agent_validation - 存在しないエージェント名指定時の挙動が不明

- approval: [ ] `target_agent_validation`
- id: `target_agent_validation`
- kind: `input_validation`
- severity: `medium`
- name: 存在しないエージェント名指定時の挙動が不明
- question: inbox_write.sh karo2 'test' cmd_new shogun のように存在しないエージェントを指定した場合、エラーになりますか？それともファイルが生成されますか？
- rationale: typoで誤ったinboxファイルが生成されるとメッセージがブラックホール化する。

```yaml
valid_agents:
- shogun
- karo
- gunshi
- hayate
- kagemaru
- hanzo
- saizo
- kotaro
- tobisaru
```

<!-- codd:finding
{"details": {"evidence": "inbox_watcher.shはinotifywaitを使用するが、/mnt/c上ではinotifyが効かずstatポーリングにフォールバックする旨がCLAUDE.mdに記載"}, "id": "wsl2_inotify_limitation", "kind": "platform_constraint", "name": "WSL2 /mnt/c上でのinotifywait制約と代替策の仕様", "question": "CLAUDE.mdに'WSL2 /mnt/c上=statポーリング'とあるが、ポーリング間隔やCPU負荷の許容値は定義されていますか？", "rationale": "ポーリング間隔が長すぎるとメッセージ配信遅延、短すぎるとCPU浪費。定量的な仕様が必要。", "related_requirement_ids": [], "severity": "medium", "source": "greenfield"}
-->
## wsl2_inotify_limitation - WSL2 /mnt/c上でのinotifywait制約と代替策の仕様

- approval: [ ] `wsl2_inotify_limitation`
- id: `wsl2_inotify_limitation`
- kind: `platform_constraint`
- severity: `medium`
- name: WSL2 /mnt/c上でのinotifywait制約と代替策の仕様
- question: CLAUDE.mdに'WSL2 /mnt/c上=statポーリング'とあるが、ポーリング間隔やCPU負荷の許容値は定義されていますか？
- rationale: ポーリング間隔が長すぎるとメッセージ配信遅延、短すぎるとCPU浪費。定量的な仕様が必要。

```yaml
evidence: inbox_watcher.shはinotifywaitを使用するが、/mnt/c上ではinotifyが効かずstatポーリングにフォールバックする旨がCLAUDE.mdに記載
```

<!-- codd:finding
{"details": {"concern": "サイレント失敗するとメッセージ消失に気づけない"}, "id": "error_handling_strategy", "kind": "error_handling", "name": "書込み失敗時のエラーハンドリングが未定義", "question": "ディスク容量不足、権限エラー、flock取得失敗時にinbox_write.shはどう振る舞いますか？呼び出し元に通知されますか？", "rationale": "メッセージ消失はエージェント間の鎖の断絶を意味し、システム全体の信頼性に直結する。", "related_requirement_ids": [], "severity": "medium", "source": "greenfield"}
-->
## error_handling_strategy - 書込み失敗時のエラーハンドリングが未定義

- approval: [ ] `error_handling_strategy`
- id: `error_handling_strategy`
- kind: `error_handling`
- severity: `medium`
- name: 書込み失敗時のエラーハンドリングが未定義
- question: ディスク容量不足、権限エラー、flock取得失敗時にinbox_write.shはどう振る舞いますか？呼び出し元に通知されますか？
- rationale: メッセージ消失はエージェント間の鎖の断絶を意味し、システム全体の信頼性に直結する。

```yaml
concern: サイレント失敗するとメッセージ消失に気づけない
```

<!-- codd:finding
{"details": {"evidence": "CLAUDE.mdに'yaml.dump/yaml.safe_dumpで運用YAMLを上書きすることは禁止'と明記。inbox_write.shがこのルールに準拠しているかの検証ポイントが不明"}, "id": "yaml_append_integrity", "kind": "data_integrity", "name": "YAML追記時のファイル構造保全策が不明", "question": "inbox_write.shはYAMLファイルにどのように追記しますか？（echo >>、yq、sed等）yaml.dump禁止ルールとの整合性は確認されていますか？", "rationale": "cmd_1399事故（yaml.dumpによるデータ消失）の再発防止。inbox YAMLは運用YAML対象に含まれる。", "related_requirement_ids": [], "severity": "high", "source": "greenfield"}
-->
## yaml_append_integrity - YAML追記時のファイル構造保全策が不明

- approval: [ ] `yaml_append_integrity`
- id: `yaml_append_integrity`
- kind: `data_integrity`
- severity: `high`
- name: YAML追記時のファイル構造保全策が不明
- question: inbox_write.shはYAMLファイルにどのように追記しますか？（echo >>、yq、sed等）yaml.dump禁止ルールとの整合性は確認されていますか？
- rationale: cmd_1399事故（yaml.dumpによるデータ消失）の再発防止。inbox YAMLは運用YAML対象に含まれる。

```yaml
evidence: CLAUDE.mdに'yaml.dump/yaml.safe_dumpで運用YAMLを上書きすることは禁止'と明記。inbox_write.shがこのルールに準拠しているかの検証ポイントが不明
```

<!-- codd:finding
{"details": {"concern": "flockによる排他制御は同時書込みを防ぐが、flock待ちの順序がFIFO保証されるかはOS実装依存"}, "id": "message_ordering_guarantee", "kind": "ordering", "name": "メッセージの順序保証の有無", "question": "複数メッセージが短時間に書き込まれた場合、受信側での処理順序は書込み順と一致しますか？", "rationale": "cmd_new → task_assignedの順序が逆転すると、忍者が未配備のcmdを参照しようとする可能性がある。", "related_requirement_ids": [], "severity": "info", "source": "greenfield"}
-->
## message_ordering_guarantee - メッセージの順序保証の有無

- approval: [ ] `message_ordering_guarantee`
- id: `message_ordering_guarantee`
- kind: `ordering`
- severity: `info`
- name: メッセージの順序保証の有無
- question: 複数メッセージが短時間に書き込まれた場合、受信側での処理順序は書込み順と一致しますか？
- rationale: cmd_new → task_assignedの順序が逆転すると、忍者が未配備のcmdを参照しようとする可能性がある。

```yaml
concern: flockによる排他制御は同時書込みを防ぐが、flock待ちの順序がFIFO保証されるかはOS実装依存
```

---

## Implementation Reality

> 実装照合: [[scripts/inbox_write.sh]] を直接確認した結果。
> 関連設計書: [[codd/design/inbox_write_design.md]]

brownfield elicitationで検出されたfindingのうち、複数は既に実装済みであることが判明した。
未解決gapに集中するための照合表を以下に示す。

| finding_id | 当初評価 | 実装状況 | 根拠（行番号） |
|------------|----------|----------|----------------|
| concurrency_safety | high: タイムアウト未定義 | ✅ 実装済み | L1309: `flock -w 5`, L1307–1474: 3回リトライループ, L1470: ntfy最終失敗通知 |
| message_id_generation | medium: 生成方式不明 | ✅ 実装済み | L1007: `MSG_ID="msg_${_msg_stamp}_$$_${_msg_rand}"` (timestamp+PID+randomhex) |
| type_enum_completeness | medium: 散在 | ✅ 定義済み | L8–30: スクリプトヘッダに20種類のtype定義あり。CLAUDE.mdの6件は部分抜粋 |
| target_agent_validation | medium: 挙動不明 | ✅ 実装済み | L961–964: 不正エージェント名は `ERROR: Invalid target agent` でexit 1 |
| yaml_append_integrity | high: 手法不明 | ✅ 実装済み | L633–638: `printf '%s' >> "$inbox_file"` でbash printf追記。yaml.dump不使用 |
| error_handling_strategy | medium: 未定義 | ✅ 実装済み | L1462–1474: 3回リトライ後エラーログ+ntfy通知 |
| message_schema_validation | high: バリデーション不明 | ⚠️ 部分実装 | L930–935: cmd_*ターゲット拒否, L272: `value="${value//\'/\'\'}"` でシングルクォートエスケープあり。YAML特殊文字の完全バリデーションは未実装 |
| wsl2_inotify_limitation | medium: ポーリング間隔未定義 | ⚠️ 設計外 | inbox_write.shではなくinbox_watcher.shの責務。本findingはwatcher側に転記すべき |
| message_ordering_guarantee | info: 順序不保証 | ⚠️ OS依存 | flockは排他だがFIFO保証なし。設計上の既知制約として受理 |
| no_requirements_provided | critical: 要件なし | ⚠️ 部分解消 | [[codd/design/inbox_write_design.md]] が設計書として機能している |

**本照合で判明した真のgap（対処が必要なもの）:**
- `message_schema_validation`: YAML特殊文字（コロン、改行等）のフルバリデーションが未実装
- `wsl2_inotify_limitation`: inbox_watcher.sh側のポーリング間隔仕様が未文書化
- `no_requirements_provided`: 正式なCoDD spec（requirements）が未作成
