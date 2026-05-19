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

deploy_task.sh（3607行）の `resolve_cmd_to_task()` と `inject_ac_version()` が、同一YAMLファイルに対する `yaml_field_set` / `field_get` の逐次呼び出しによりテスト1件あたり2.6秒を消費している。根因は毎回の flock 取得 + awk 全量 rewrite であり、7回の書込みで7回のロック・7回の全行走査が発生する。

本ADRは、`module:yaml_helpers`（`lib/yaml_field_set.sh`, `lib/field_get.sh`）に2つのバッチ関数を追加し、`module:deploy_task`（`scripts/deploy_task.sh`）の該当関数を書き替える設計判断を記録する。

**対象モジュールと制約**: `yaml_field_set_batch` は単一の flock + 単一の awk pass で複数フィールドを同時更新する。`field_get_multi` は単一の awk pass で複数フィールドを一括抽出する。既存の `yaml_field_set` および `field_get` のAPI契約は完全に保持する。これらのユーティリティはキュー操作系（`queue/`, `tasks/`, `inbox/`, `reports/`, `shogun_to_karo`, `karo_snapshot`）の全YAML変更に使用されており、API互換の破壊はシステム全体のキュー操作を停止させる。

### 定量根拠

| 関数 | Before | After（期待） | 短縮率 |
|------|--------|---------------|--------|
| `resolve_cmd_to_task` | 627ms（flock×7, awk rewrite×7） | ~100ms（flock×1, awk×1） | -84% |
| `inject_ac_version` | 541ms（grep×6-7, flock×3, awk rewrite×3） | ~80ms（awk read×1, flock×1, awk write×1） | -85% |
| テスト1件合計 | 2,639ms | ~400ms | -85% |
| ac_handling 48テスト | 34s | ~5s | -85% |

`yaml_field_set` 1回あたりのコスト内訳: mktemp → flock -w 10（排他ロック） → awk 全量 rewrite → mv atomic replacement → post-write verification（再読込）= 20–50ms/回。`field_get` 1回あたり: grep/sed YAML解析 + optional flock/date/log = 2–15ms/回。

### 非機能要件への適合

- **flock排他の正確性**: バッチ関数でもflock -w 10による排他ロックを1回取得し、awk処理完了+mv完了後に解放する。並行書込み安全性は単一操作版と同等。
- **atomic replacement**: mktemp → awk出力 → mv パターンを維持。中間状態のファイルが他プロセスから読まれることはない。
- **post-write verification**: バッチ完了後に1回だけ全フィールドを再読込して検証する。逐次版の7回検証より効率的かつ同等の信頼性。

### deploy_task.sh要件との整合

| deploy_task要件 | 本ADRとの関係 |
|----------------|--------------|
| FR-5: cmd→タスクメタデータ解決 | `resolve_cmd_to_task` が `yaml_field_set_batch` を使用し、parent_cmd/task_id/task_type/project/status/purpose/_ac_task_id を1パスで書込む |
| FR-5: ACバージョン生成 | `inject_ac_version` が `field_get_multi` で6-7フィールド一括取得後、`yaml_field_set_batch` で ac_version/_ac_task_id/_ac_worker_id を1パスで書込む |
| SR-1: 共有YAMLヘルパー使用 | バッチ関数は既存ヘルパーライブラリ内に追加。free-form YAML dumping は引き続き禁止 |
| FR-4: staleフィールドリセット | リセット操作も `yaml_field_set_batch` に統合可能（空値セットを1パスで実行） |

## 2. Decision Log

### D-001: バッチ書込みを新関数として追加し、既存関数を温存する

**決定**: `yaml_field_set_batch` を `lib/yaml_field_set.sh` に新関数として追加する。既存の `yaml_field_set`（単一フィールド版）はAPIもロジックも変更しない。

**理由**: `yaml_field_set` は deploy_task.sh 以外の多数のスクリプト（inbox_write.sh, inbox_mark_read.sh, タスク状態更新等）から呼ばれている。内部ロジック変更はリグレッションリスクが高い。新関数追加なら既存呼出元への影響はゼロ。

**却下案**: 既存 `yaml_field_set` を可変長引数対応に拡張する案。後方互換性の検証コストが高く、引数パースの複雑化でバグ混入リスクがある。

### D-002: バッチ読取りを新関数として追加し、既存関数を温存する

**決定**: `field_get_multi` を `lib/field_get.sh` に新関数として追加する。既存の `field_get`（単一フィールド版）は変更しない。

**理由**: D-001と同様。既存API互換を維持し、呼出元への影響をゼロにする。

### D-003: yaml_field_set_batch のインターフェース設計

**決定**: 以下のシグネチャを採用する。

```bash
yaml_field_set_batch <file> <block_id> <field1>=<value1> [<field2>=<value2> ...]
```

- 引数形式: `field=value` ペアを可変長で受け取る
- flock: 1回のみ取得（-w 10）
- awk: 1パスで全フィールドを同時に更新（存在すれば上書き、なければ追加）
- verify_after_write: 1回のみ実行（全フィールドを一括検証）
- 戻り値: 検証失敗時は非ゼロ

**理由**: deploy_task.sh の `resolve_cmd_to_task` は7つの `yaml_field_set` 呼出しを全て同一ファイル・同一ブロックに対して行っている。`field=value` 形式なら既存の呼出しパターンから機械的に変換できる。

### D-004: field_get_multi のインターフェースと出力形式

**決定**: 以下のシグネチャと出力形式を採用する。

```bash
field_get_multi <file> <field1> [<field2> ...] → stdout: "field1=value1\nfield2=value2\n..."
```

- awk: 1パスで全フィールドを一括抽出
- 出力: `field=value` 形式（改行区切り）。eval または while read で消費可能
- フィールドが存在しない場合: 該当行を出力しない（既存 `field_get` の空文字返却と整合）

**理由**: `inject_ac_version` は6-7回の `field_get` を個別変数に格納している。`eval "$(field_get_multi ...)"` パターンで既存コードの変数名をそのまま使える。

### D-005: 実施順序の決定

**決定**: R3 → R4 → R1 → R2 → 全量テスト+プロファイル再計測の順序で実施する。

| Phase | 内容 | 依存 |
|-------|------|------|
| R3 | `yaml_field_set_batch` 実装+単体テスト | なし |
| R4 | `field_get_multi` 実装+単体テスト | なし（R3と並列実施可能） |
| R1 | `resolve_cmd_to_task` 書替え（R3利用） | R3完了 |
| R2 | `inject_ac_version` 書替え（R3+R4利用） | R3+R4完了 |
| 検証 | 既存48テスト全PASS + before/after プロファイル比較 | R1+R2完了 |

**理由**: ユーティリティ関数を先に作りテスト済みにすることで、呼出元の書替え時にユーティリティ自体のバグを排除できる。R3とR4は相互依存がないため並列実施可能。

### D-006: resolve_cmd_to_task の書替え方針

**決定**: 既存の7回の `yaml_field_set` 呼出し（L247-330）を1回の `yaml_field_set_batch` 呼出しに置換する。awk による STK 変数抽出（1回、高速）は変更しない。

```bash
# Before: 7回のflock+rewrite
yaml_field_set "$task" parent_cmd "$cmd_id"
yaml_field_set "$task" task_id "$task_id"
yaml_field_set "$task" task_type "$task_type"
yaml_field_set "$task" project "$project"
yaml_field_set "$task" status "acknowledged"
yaml_field_set "$task" purpose "$purpose"
yaml_field_set "$task" _ac_task_id "$ac_task_id"

# After: 1回のflock+rewrite
yaml_field_set_batch "$task" "$block_id" \
  "parent_cmd=$cmd_id" \
  "task_id=$task_id" \
  "task_type=$task_type" \
  "project=$project" \
  "status=acknowledged" \
  "purpose=$purpose" \
  "_ac_task_id=$ac_task_id"
```

### D-007: inject_ac_version の書替え方針

**決定**: 読取り部を `field_get_multi` に、書込み部を `yaml_field_set_batch` に置換する。awk による `_compute_ac_hash` は変更しない。

```bash
# Before: 6-7回のgrep + 3回のflock+rewrite
ac_ver=$(field_get "$task" ac_version)
task_id=$(field_get "$task" task_id)
# ... 計6-7回

yaml_field_set "$task" ac_version "$new_ver"
yaml_field_set "$task" _ac_task_id "$ac_task_id"
yaml_field_set "$task" _ac_worker_id "$ac_worker_id"

# After: 1回のawk read + 1回のflock+rewrite
eval "$(field_get_multi "$task" ac_version task_id _ac_task_id worker_id _ac_worker_id)"
# ... _compute_ac_hash ...
yaml_field_set_batch "$task" "$block_id" \
  "ac_version=$new_ver" \
  "_ac_task_id=$ac_task_id" \
  "_ac_worker_id=$ac_worker_id"
```

## 3. Follow-ups

| ID | 内容 | 条件 | 優先度 |
|----|------|------|--------|
| FU-001 | `yaml_field_set_batch` の並行安全性テスト: 複数プロセスから同時にバッチ書込みを実行し、flock排他が正しく機能することを検証する | R3完了後 | 必須（リリース前） |
| FU-002 | deploy_task.sh 内の他の逐次 `yaml_field_set` 呼出しパターン（FR-4 staleフィールドリセット、FR-6 レポートテンプレート生成等）をバッチ化候補として洗い出す | R1+R2完了後 | 推奨 |
| FU-003 | `yaml_field_set_batch` を inbox_write.sh 等の他スクリプトに展開し、システム全体のYAML書込み性能を改善する | 本ADRの全Phase完了+安定稼働確認後 | 低（既存が性能問題を起こしていない場合） |
| FU-004 | プロファイル再計測で期待効果（-85%）に達しない場合、awk処理自体のボトルネック（大規模YAMLファイルの行数、フィールド数）を調査する | 全量テスト完了後 | 期待効果未達時のみ |
| FU-005 | `field_get_multi` の `eval` パターンにおけるシェルインジェクション防御: value に特殊文字（`$`, `` ` ``, `"`, 改行）が含まれる場合の安全性を検証し、必要に応じてクォーティング処理を追加する | R4完了後 | 必須（リリース前） |
