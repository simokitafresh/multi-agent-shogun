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

deploy_task.sh（3607行）の `resolve_cmd_to_task()` と `inject_ac_version()` は、同一ファイルに対する `yaml_field_set` / `field_get` の逐次呼び出しにより、テスト1件あたり2.6秒（全体の93%）を消費している。根因は毎回の flock 取得 + awk 全量 rewrite である。

本 ADR は、`module:yaml_helpers`（`scripts/lib/yaml_field_set.sh`, `scripts/lib/field_get.sh`）に2つのバッチ関数を追加し、`module:deploy_task`（`scripts/deploy_task.sh`）の呼び出し側を書き替える設計判断を記録する。

**対象モジュールと不変量**: `yaml_field_set_batch` は単一の flock + 単一の awk pass で全フィールドを更新する。`field_get_multi` は単一の awk pass で複数フィールドを一括抽出する。既存の `yaml_field_set` および `field_get` の API 契約（引数順序・出力形式・戻り値・flock 排他保証）は一切変更しない。これらのユーティリティは queue/ 配下の全 YAML 変更に使われており、API 契約の破壊はシステム全体の queue mutation を停止させる release-blocking リスクである。

### 定量目標

| 関数 | Before | After | 短縮率 |
|------|--------|-------|--------|
| `resolve_cmd_to_task` | 627ms（yaml_field_set ×7 = flock×7 + awk×7） | ~100ms（yaml_field_set_batch ×1 = flock×1 + awk×1） | -84% |
| `inject_ac_version` | 541ms（field_get ×6-7 + yaml_field_set ×3） | ~80ms（field_get_multi ×1 + yaml_field_set_batch ×1） | -85% |
| 48テスト合計（ac_handling） | 34s | ~5s | -85% |

### API 契約保全

`yaml_field_set_batch` と `field_get_multi` は新規関数として追加する。既存関数のシグネチャ・動作・戻り値は変更しない。

- **`yaml_field_set <file> <block_id> <field> <value>`**: 単一フィールド書込み。flock + awk rewrite + mv atomic + verify_after_write。呼び出し元は deploy_task.sh 以外にも inbox_write.sh, inbox_mark_read.sh, タスク状態更新等で広範に使用される。この関数は変更しない。
- **`field_get <file> <field>`**: 単一フィールド読取り。grep/sed による YAML 解析。この関数は変更しない。
- **`yaml_field_set_batch <file> <block_id> <field1>=<value1> [<field2>=<value2> ...]`**: 新規追加。内部で1回の flock + 1回の awk pass で全フィールドを同時に更新/追加。verify_after_write も1回のみ。
- **`field_get_multi <file> <field1> [<field2> ...]`**: 新規追加。1回の awk pass で複数フィールドを一括抽出。出力形式は `field1=value1\nfield2=value2\n...`（eval 可能）。

### 適用範囲

本 ADR の書き替え対象は以下の2関数に限定する。

1. **`resolve_cmd_to_task()`**（deploy_task.sh L247-330）: awk による STK 変数抽出後の yaml_field_set ×7 を yaml_field_set_batch ×1 に置換。FR-5（cmd → task metadata 解決）の機能を維持する。
2. **`inject_ac_version()`**（deploy_task.sh L690-745）: field_get ×6-7 を field_get_multi ×1 に、yaml_field_set ×3 を yaml_field_set_batch ×1 に置換。AC バージョン計算・書込みの機能を維持する。

deploy_task.sh の他の機能（FR-1 デプロイモード解析、FR-2 忍者名バリデーション、FR-3 tmux/CLI ペイン解決、FR-4 stale フィールドリセット、FR-6 レポートテンプレート生成、FR-7 inbox_write.sh 配信、SR-1 共有 YAML ヘルパー使用、SR-2 重複配備ブロック、SR-3 inbox パス通信）は影響を受けない。

## 2. Decision Log

### ADR-001: バッチ関数を既存ファイルに追加する（新ファイル作成しない）

**決定**: `yaml_field_set_batch` は `scripts/lib/yaml_field_set.sh` に、`field_get_multi` は `scripts/lib/field_get.sh` に追加する。

**理由**: 既存の source パスを変更せず、deploy_task.sh の `source` コスト（137ms）に影響を与えない。新ファイル追加は source チェインの変更を要し、他スクリプトへの波及リスクがある。

**却下案**: 別ファイル `lib/yaml_batch.sh` に分離 → source パスの追加が全呼び出し元に波及するため却下。

### ADR-002: yaml_field_set_batch の内部実装は単一 flock + 単一 awk pass

**決定**: `yaml_field_set_batch` は1回の `flock -w 10` でロックを取得し、1回の awk 実行で全 field=value ペアを同時に更新/追加し、`mv` による atomic replacement を行い、1回の verify_after_write で全フィールドを検証する。

**理由**: yaml_field_set 1回あたりのコスト（20-50ms）の主因は flock 取得 + awk 全量走査 + mv + 再読込検証である。N 回の逐次呼び出しを1回に集約することで、オーバーヘッドを O(N) から O(1) に削減する。flock の排他保証は維持される（ロック取得から mv 完了まで他プロセスをブロックする）。

**制約（release-blocking）**: flock + awk は必ず1回ずつ。複数回の flock 取得や複数回の awk 実行はこの ADR に違反する。

### ADR-003: field_get_multi の内部実装は単一 awk pass

**決定**: `field_get_multi` は1回の awk 実行で、指定された全フィールドの値を抽出する。出力は `field=value` の改行区切り（eval 互換）。

**理由**: field_get 1回あたり 2-15ms だが、inject_ac_version では6-7回呼ばれる。1回の awk で YAML を1回走査し、フィールド名をキーとした連想配列で全値を収集すれば、ファイル I/O は1回で済む。

**制約（release-blocking）**: awk は必ず1回。grep/sed の複数呼び出しへのフォールバックはこの ADR に違反する。

### ADR-004: 既存 API は変更しない

**決定**: `yaml_field_set` の引数順序（`<file> <block_id> <field> <value>`）、戻り値（成功=0, 失敗=1）、flock 動作、verify_after_write 動作は一切変更しない。`field_get` も同様。

**理由**: yaml_field_set は inbox_write.sh, inbox_mark_read.sh, タスク状態更新、レポート書込み等でシステム全体の queue mutation に使用される。API 変更は全呼び出し元のリグレッションを引き起こす。SR-1（共有 YAML ヘルパー使用）の要件に従い、ヘルパーの信頼性を維持する。

### ADR-005: 実施順序は R3 → R4 → R1 → R2 → 全量テスト

**決定**: 以下の順序で実施する。

1. **R3**: `yaml_field_set_batch` 実装 + 単体テスト
2. **R4**: `field_get_multi` 実装 + 単体テスト
3. **R1**: `resolve_cmd_to_task()` を R3 利用に書替え + 既存テスト全 PASS 確認
4. **R2**: `inject_ac_version()` を R3 + R4 利用に書替え + 既存テスト全 PASS 確認
5. **全量テスト + プロファイル再計測**: before/after 比較で定量目標（-85%）を検証

**理由**: ユーティリティ関数を先に安定させてから呼び出し側を書き替えることで、リグレッションの切り分けが容易になる。R1（yaml_field_set のみ）は R2（yaml_field_set + field_get 両方）より依存が少ないため先に実施する。

### ADR-006: deploy_task.sh の他機能への非影響を保証する

**決定**: 書き替え対象は `resolve_cmd_to_task()`（L247-330）と `inject_ac_version()`（L690-745）の2関数のみ。他の全機能（FR-1〜FR-4, FR-6〜FR-7, SR-1〜SR-3）は変更しない。

**理由**: deploy_task.sh は忍者配備の唯一のパスであり（FR-1）、配備失敗はシステム停止を意味する。変更範囲を最小化し、既存テスト全 PASS で非影響を検証する。

## 3. Follow-ups

| ID | 内容 | トリガー | 担当 |
|----|------|----------|------|
| FU-1 | R3 実装後、yaml_field_set_batch の flock 排他が並行書込みで正しく動作することを検証する（2プロセス同時書込みテスト） | R3 単体テスト完了時 | 実装担当忍者 |
| FU-2 | R4 実装後、field_get_multi が存在しないフィールドを指定された場合に空値を返すことを検証する（field_get との動作一致確認） | R4 単体テスト完了時 | 実装担当忍者 |
| FU-3 | R1+R2 書替え後、deploy_task.sh の全48テスト（ac_handling）+ 他テストスイートが全 PASS であることを確認する | R2 完了時 | 実装担当忍者 |
| FU-4 | 全量テスト後、プロファイル再計測を実施し、resolve_cmd_to_task ~100ms / inject_ac_version ~80ms / 48テスト合計 ~5s の定量目標を達成したことを確認する | 全量テスト完了時 | 実装担当忍者 |
| FU-5 | バッチ関数が安定した後、deploy_task.sh 内の他の逐次 yaml_field_set 呼び出し（R1/R2 以外）をバッチ化する追加最適化の候補を洗い出す | プロファイル再計測完了後 | 家老判断 |
| FU-6 | yaml_field_set_batch / field_get_multi の利用ガイドを lib/ 内のコメントとして記載し、他スクリプトからの利用方法を明示する | R3+R4 テスト完了時 | 実装担当忍者 |
