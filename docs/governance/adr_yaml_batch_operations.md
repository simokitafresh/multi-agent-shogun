---
codd:
  node_id: governance:adr-yaml-batch-operations
  type: governance
  depends_on:
  - id: req:deploy-task-refactor-requirements
    relation: derives_from
    semantic: governance
  - id: req:script:deploy-task
    relation: derives_from
    semantic: governance
  depended_by:
  - id: design:system-overview
    relation: constrained_by
    semantic: governance
  - id: detailed:yaml-library
    relation: constrained_by
    semantic: governance
  conventions:
  - targets:
    - module:yaml_helpers
    - module:deploy_task
    reason: yaml_field_set_batch must use single flock+awk pass; field_get_multi must
      use single awk pass. Existing API contracts must be preserved; violation breaks
      all queue mutations system-wide.
  modules:
  - yaml_helpers
  - deploy_task
---

# ADR: YAML Batch Operations Design

## 1. Overview

`deploy_task.sh`（3607行）の`resolve_cmd_to_task()`と`inject_ac_version()`は、同一YAMLファイルに対して`yaml_field_set`/`field_get`を逐次呼び出すことでテスト1件あたり2.6秒を消費している。根因は毎回のflock取得+awk全量rewriteであり、48テスト（ac_handling）で合計34秒に達する。

本ADRは`module:yaml_helpers`に`yaml_field_set_batch`と`field_get_multi`の2関数を追加し、`module:deploy_task`の該当箇所を書き替えることで、1テストあたりの所要時間を2639ms→約400ms（-85%）に短縮する設計判断を記録する。

### スコープ

| 対象モジュール | 変更内容 | 影響範囲 |
|---------------|---------|---------|
| `module:yaml_helpers` (`scripts/lib/yaml_field_set.sh`) | `yaml_field_set_batch`関数追加 | queue/task/inbox/report等の全YAML mutation |
| `module:yaml_helpers` (`scripts/lib/field_get.sh`) | `field_get_multi`関数追加 | YAML読取り全般 |
| `module:deploy_task` (`scripts/deploy_task.sh`) | `resolve_cmd_to_task` L247-330書替え、`inject_ac_version` L690-745書替え | タスク配備・ACバージョン注入 |

### 定量根拠（2026-04-15実測プロファイル）

| 関数 | 現状 | field_get回数 | yaml_field_set回数 | 根因 |
|------|------|-------------|-------------------|------|
| `resolve_cmd_to_task` | 627ms | 0 | 7 | 7回flock + 7回awk全量rewrite |
| `inject_ac_version` | 541ms | 6-7 | 3 | 6回grep + 3回flock + 3回awk全量rewrite |
| `source deploy_task.sh` | 137ms | — | — | 3607行読込 |
| **合計** | **1305ms** | — | — | テスト1件の93% |

単一操作コスト: `yaml_field_set`=20-50ms/回（mktemp+flock+awk全量rewrite+mv+verify）、`field_get`=2-15ms/回（grep/sed+optional flock+log）。

### 非機能要件適合

**Convention 1適合**: `yaml_field_set_batch`は単一flock取得+単一awk passで全フィールドを同時更新する。`field_get_multi`は単一awk passで複数フィールドを一括抽出する。既存の`yaml_field_set`と`field_get`のAPI契約（引数形式・戻り値・エラーコード）は変更しない。これにより`queue/`配下の全YAML mutation（タスク配備・inbox・レポート・snapshot）の既存呼出元は影響を受けない。

## 2. Decision Log

### ADR-001: バッチ書込み関数の設計（yaml_field_set_batch）

**決定**: `scripts/lib/yaml_field_set.sh`に以下のAPIで`yaml_field_set_batch`を追加する。

```bash
yaml_field_set_batch <file> <block_id> <field1>=<value1> <field2>=<value2> ...
```

**処理フロー**:
1. mktemp（1回）
2. flock -w 10（排他ロック取得、1回）
3. awk全量rewrite（1回のawk passで全フィールドを同時に更新/追加）
4. mv atomic replacement（1回）
5. verify_after_write（1回、全フィールド一括検証）

**理由**: `resolve_cmd_to_task`は7回のyaml_field_set（parent_cmd, task_id, task_type, project, status, purpose, _ac_task_id）を逐次実行しており、各回でflock+awk全量rewriteが発生する。1回のflock+awkに集約すれば627ms→約100ms（-84%）となる。

**制約（release-blocking）**: 既存`yaml_field_set`のAPI（`yaml_field_set <file> <block_id> <field> <value>`）は一切変更しない。`yaml_field_set_batch`は追加関数であり、既存の呼出元（SR-1準拠の全queue mutation）に影響しない。flock排他の正確性は単一flock取得で維持される。

**FR-5適合**: `resolve_cmd_to_task`がparent cmdからtask metadata（task_id, task_type, project, status, purpose, _ac_task_id, parent_cmd）を解決してtask YAMLに書込む処理は、`yaml_field_set_batch`による1回のバッチ書込みで実現する。

### ADR-002: バッチ読取り関数の設計（field_get_multi）

**決定**: `scripts/lib/field_get.sh`に以下のAPIで`field_get_multi`を追加する。

```bash
field_get_multi <file> <field1> <field2> ... → "field1=value1\nfield2=value2\n..."
```

**出力形式**: eval可能な`field=value`ペアを改行区切りで出力する。フィールドが存在しない場合は`field=`（空値）を出力する。

**処理フロー**: 1回のawk passでファイルを走査し、指定された全フィールドの値を同時に抽出する。

**理由**: `inject_ac_version`は6-7回のfield_get（ac_version, task_id, _ac_task_id, worker_id, _ac_worker_id等）を逐次実行している。1回のawkに集約すれば読取り部分のオーバーヘッドを解消できる。

**制約（release-blocking）**: 既存`field_get`のAPI（`field_get <file> <field>`）は一切変更しない。`field_get_multi`は追加関数であり、既存の呼出元に影響しない。

### ADR-003: resolve_cmd_to_task書替え

**決定**: `deploy_task.sh` L247-330の7回のyaml_field_set呼出しを、1回の`yaml_field_set_batch`呼出しに置換する。

**変更前**:
```bash
yaml_field_set "$task" parent_cmd "$cmd_id"
yaml_field_set "$task" task_id "$task_id"
yaml_field_set "$task" task_type "$task_type"
yaml_field_set "$task" project "$project"
yaml_field_set "$task" status "assigned"
yaml_field_set "$task" purpose "$purpose"
yaml_field_set "$task" _ac_task_id "$ac_task_id"
```

**変更後**:
```bash
yaml_field_set_batch "$task" "" \
  "parent_cmd=$cmd_id" \
  "task_id=$task_id" \
  "task_type=$task_type" \
  "project=$project" \
  "status=assigned" \
  "purpose=$purpose" \
  "_ac_task_id=$ac_task_id"
```

**期待効果**: 627ms → 約100ms（-84%）。flock取得7回→1回、awk全量rewrite 7回→1回。

**FR-4適合**: stale task fieldsのリセットとnew assignmentの書込みがバッチ化後も正しく実行されることを既存テスト全PASSで検証する。

### ADR-004: inject_ac_version書替え

**決定**: `deploy_task.sh` L690-745の読取り・書込みを、`field_get_multi`+`yaml_field_set_batch`の組合せに置換する。

**変更前**:
```bash
local ac_ver=$(field_get "$task" ac_version)
local task_id=$(field_get "$task" task_id)
local ac_task_id=$(field_get "$task" _ac_task_id)
local worker_id=$(field_get "$task" worker_id)
local ac_worker_id=$(field_get "$task" _ac_worker_id)
# ... _compute_ac_hash ...
yaml_field_set "$task" ac_version "$new_ver"
yaml_field_set "$task" _ac_task_id "$new_ac_task_id"
yaml_field_set "$task" _ac_worker_id "$new_ac_worker_id"
```

**変更後**:
```bash
eval "$(field_get_multi "$task" ac_version task_id _ac_task_id worker_id _ac_worker_id)"
# ... _compute_ac_hash ...
yaml_field_set_batch "$task" "" \
  "ac_version=$new_ver" \
  "_ac_task_id=$new_ac_task_id" \
  "_ac_worker_id=$new_ac_worker_id"
```

**期待効果**: 541ms → 約80ms（-85%）。field_get 6-7回→awk 1回、yaml_field_set 3回→flock+awk 1回。

### ADR-005: 実施順序

| Step | 内容 | 依存 | 検証 |
|------|------|------|------|
| 1 | R3: `yaml_field_set_batch`実装+単体テスト | なし | 新関数テストPASS |
| 2 | R4: `field_get_multi`実装+単体テスト | なし | 新関数テストPASS |
| 3 | R1: `resolve_cmd_to_task`書替え | Step 1完了 | 既存テスト全48件PASS |
| 4 | R2: `inject_ac_version`書替え | Step 1, 2完了 | 既存テスト全48件PASS |
| 5 | 全量テスト+プロファイル再計測 | Step 3, 4完了 | before/after比較で-85%達成確認 |

Step 1とStep 2は相互依存がないため並列実施可能。Step 3以降は逐次実施とする。

### ADR-006: 安全性保証

**SR-1適合**: `yaml_field_set_batch`は`scripts/lib/yaml_field_set.sh`内に定義され、shared YAML helperとしてqueue/task mutationに利用される。free-form YAML dumpingは使用しない（`yaml.dump`/`yaml.safe_dump`はpre-bash-yaml-dump-guard.shでブロック済み）。

**SR-2適合**: duplicate active deployment検知ロジックは書替え対象外であり、バッチ化による影響を受けない。

**FR-7適合**: タスク通知のinbox_write.sh呼出しは書替え対象外であり、バッチ化による影響を受けない。

**flock排他保証**: `yaml_field_set_batch`は`yaml_field_set`と同一のflock機構（flock -w 10）を使用する。1回のflock取得内で全フィールドを更新するため、並行書込み安全性は現状と同等以上となる（中間状態が外部から観測されない）。

## 3. Follow-ups

| ID | 内容 | トリガー | 担当 |
|----|------|---------|------|
| FU-1 | `yaml_field_set_batch`のエッジケーステスト: 値にイコール記号・改行・引用符を含むケース | Step 1実装時 | 実装担当忍者 |
| FU-2 | `field_get_multi`で存在しないフィールド混在時の出力検証 | Step 2実装時 | 実装担当忍者 |
| FU-3 | 48テスト全量プロファイル再計測で-85%（34s→5s）達成を定量確認 | Step 5完了時 | 家老 |
| FU-4 | `yaml_field_set_batch`の他モジュール展開検討: `inbox_write.sh`、`report_field_set.sh`等のバッチ化余地 | 本ADR CLEAR後 | 軍師 |
| FU-5 | `deploy_task.sh` source時間137ms（3607行読込）の別途最適化検討 | 本ADRスコープ外 | 将軍判断 |
| FU-6 | FR-2（ninja name validation）、FR-3（idle/busy判定）、FR-4（stale reset）、FR-6（report template生成）が書替え後も正常動作することを既存テスト全PASSで確認 | Step 3, 4完了時 | 実装担当忍者 |
