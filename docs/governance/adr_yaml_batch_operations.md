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

本ADRは `yaml_field_set_batch` および `field_get_multi` の導入と、それに伴う `deploy_task.sh` 内部関数のバッチ化リファクタリングに関する設計判断を記録する。

### 背景

`deploy_task.sh`（3607行）の `resolve_cmd_to_task()` と `inject_ac_version()` がテスト1件あたり2.6秒（全体の93%）を消費している。根因は同一YAMLファイルに対する `yaml_field_set` / `field_get` の逐次呼び出しであり、毎回 flock 取得 → awk 全量rewrite → atomic replacement → post-write verification を繰り返す。

| 関数 | 現状時間 | field_get回数 | yaml_field_set回数 | 根因 |
|------|----------|---------------|--------------------|----|
| `resolve_cmd_to_task` | 627ms | 0 | 7 | 7回 flock + 7回 awk 全量rewrite |
| `inject_ac_version` | 541ms | 6–7 | 3 | 6回 grep + 3回 flock + 3回 awk 全量rewrite |
| source読込 | 137ms | — | — | 3607行読込 |

`yaml_field_set` 1回あたりのコストは mktemp → flock -w 10 → awk全行走査 → mv atomic replacement → verify再読込で20–50ms。`field_get` 1回あたりは grep/sed YAML解析＋optional flock/log で2–15ms。

### 判断対象

| ID | 内容 | 対象モジュール |
|----|------|---------------|
| R3 | `yaml_field_set_batch` 新関数追加 | `module:yaml_helpers`（`scripts/lib/yaml_field_set.sh`） |
| R4 | `field_get_multi` 新関数追加 | `module:yaml_helpers`（`scripts/lib/field_get.sh`） |
| R1 | `resolve_cmd_to_task()` バッチ化書替え | `module:deploy_task`（`scripts/deploy_task.sh`） |
| R2 | `inject_ac_version()` バッチ化書替え | `module:deploy_task`（`scripts/deploy_task.sh`） |

### 非交渉制約（release-blocking）

**対象モジュール: `module:yaml_helpers`, `module:deploy_task`**

> `yaml_field_set_batch` は単一の flock 取得＋単一の awk pass で全フィールドを更新しなければならない。`field_get_multi` は単一の awk pass で全フィールドを抽出しなければならない。既存の `yaml_field_set` および `field_get` の API 契約は完全に保存されなければならない。違反はシステム全体のキュー変更操作を破壊する。

本ADRはこの制約を以下の形で反映する:

- **§2 Decision D-001**: flock 1回 + awk 1 pass の内部構造を義務化
- **§2 Decision D-002**: awk 1 pass の内部構造を義務化
- **§2 Decision D-003, D-004**: 既存API互換を明示的に保証
- **§2 Decision D-005**: flock 排他の正確性を維持する並行書込み安全性を保証

### 期待効果

| 関数 | Before | After | 短縮率 |
|------|--------|-------|--------|
| `resolve_cmd_to_task` | 627ms | ~100ms | −84% |
| `inject_ac_version` | 541ms | ~80ms | −85% |
| 1テスト合計 | 2,639ms | ~400ms | −85% |
| 48テスト（ac_handling） | 34s | ~5s | −85% |

## 2. Decision Log

### D-001: `yaml_field_set_batch` は単一 flock + 単一 awk pass で実装する

**状態**: 承認

**文脈**: `resolve_cmd_to_task()` は7回の `yaml_field_set` を逐次呼び出し、毎回 flock 取得 → awk 全量走査 → atomic mv → verify を行う。合計627ms。

**決定**: `scripts/lib/yaml_field_set.sh` に以下のシグネチャで新関数を追加する。

```bash
yaml_field_set_batch <file> <block_id> <field1>=<value1> [<field2>=<value2> ...]
```

内部処理:
1. `flock -w 10` を **1回** 取得
2. **1回** の awk pass で全 field=value ペアを同時に更新（既存フィールドは値置換、未存在フィールドはブロック末尾に追加）
3. `mv` による atomic replacement を **1回** 実行
4. post-write verification を **1回** 実行

**根拠**: flock 取得回数を N→1 に削減し、awk 全量走査も N→1 に削減することで、O(N) の I/O コストを O(1) に圧縮する。

**制約との適合**: 「single flock + awk pass」制約を直接実装。既存 `yaml_field_set` は変更せず、新関数として追加するため API 互換を保持。

### D-002: `field_get_multi` は単一 awk pass で実装する

**状態**: 承認

**文脈**: `inject_ac_version()` は6–7回の `field_get`（grep/sed ベース）を逐次呼び出す。各呼び出しが2–15ms で合計40–100ms。

**決定**: `scripts/lib/field_get.sh` に以下のシグネチャで新関数を追加する。

```bash
field_get_multi <file> <field1> [<field2> ...] → stdout: "field1=value1\nfield2=value2\n..."
```

内部処理:
1. **1回** の awk pass で指定された全フィールドの値を抽出
2. `field=value` の改行区切り形式で stdout に出力（eval 可能）

**根拠**: grep/sed の N 回起動を awk 1 回に統合。I/O 回数を O(N)→O(1) に削減。

**制約との適合**: 「single awk pass」制約を直接実装。既存 `field_get` は変更せず新関数として追加。

### D-003: `resolve_cmd_to_task()` を `yaml_field_set_batch` で書き替える

**状態**: 承認

**文脈**: 現状の7回逐次 `yaml_field_set` 呼び出し（L247–330）を D-001 の `yaml_field_set_batch` に置換する。

**決定**: 既存の awk STK→変数抽出（1回、高速）はそのまま維持し、後続の7回 `yaml_field_set` を以下の1回呼び出しに統合する。

```bash
yaml_field_set_batch "$task_file" "$block_id" \
  "parent_cmd=$parent_cmd" \
  "task_id=$task_id" \
  "task_type=$task_type" \
  "project=$project" \
  "status=$status" \
  "purpose=$purpose" \
  "_ac_task_id=$ac_task_id"
```

**根拠**: 627ms → ~100ms（−84%）。FR-5（cmd→タスクメタデータ解決）の機能要件を維持したまま性能改善。

**制約との適合**: `yaml_field_set_batch` の API 契約内で使用。既存テスト全 PASS を実施順序 Step 3 で検証。

### D-004: `inject_ac_version()` を `field_get_multi` + `yaml_field_set_batch` で書き替える

**状態**: 承認

**文脈**: 現状の6–7回 `field_get` + 3回 `yaml_field_set`（L690–745）を D-001 + D-002 のバッチ関数に置換する。

**決定**:

読取り部:
```bash
eval "$(field_get_multi "$task_file" ac_version task_id _ac_task_id worker_id _ac_worker_id)"
```

書込み部（`_compute_ac_hash` 後）:
```bash
yaml_field_set_batch "$task_file" "$block_id" \
  "ac_version=$new_ac_version" \
  "_ac_task_id=$new_ac_task_id" \
  "_ac_worker_id=$new_ac_worker_id"
```

**根拠**: 541ms → ~80ms（−85%）。条件分岐（`_ac_task_id` / `_ac_worker_id` の conditional get）は `field_get_multi` の出力で空値を検出して処理。

**制約との適合**: 既存 `field_get` / `yaml_field_set` の呼び出し元（deploy_task.sh 以外）には影響なし。SR-1（共有YAMLヘルパー使用）を維持。

### D-005: flock 排他の並行書込み安全性を維持する

**状態**: 承認

**文脈**: `yaml_field_set` の排他制御は `flock -w 10` による advisory lock。複数エージェントが同一タスク YAML を同時に書き込む可能性がある（家老の配備と忍者の進捗更新が競合するケース）。

**決定**:
- `yaml_field_set_batch` は既存の `yaml_field_set` と同一のロックファイル（`"${file}.lock"`）を使用する
- flock のタイムアウトは既存と同じ `10秒` を維持
- atomic replacement は `mv` を使用（既存と同一手法）
- `yaml_field_set_batch` と既存 `yaml_field_set` は同一ロックを共有するため、混在呼び出し時も安全

**根拠**: ロックの粒度を変更しないことで、既存の並行安全性をそのまま継承する。

### D-006: 実施順序は R3 → R4 → R1 → R2 → 全量検証の5段階

**状態**: 承認

**決定**: 依存関係の順に実施する。

| Step | 内容 | 前提 | 検証 |
|------|------|------|------|
| 1 | R3: `yaml_field_set_batch` 新関数 + 単体テスト | なし | 新関数テスト PASS |
| 2 | R4: `field_get_multi` 新関数 + 単体テスト | なし | 新関数テスト PASS |
| 3 | R1: `resolve_cmd_to_task` 書替え | R3 完了 | 既存テスト全 PASS |
| 4 | R2: `inject_ac_version` 書替え | R3 + R4 完了 | 既存テスト全 PASS |
| 5 | 全量テスト + プロファイル再計測 | R1–R4 完了 | 48テスト全 PASS + before/after 比較で −80% 以上 |

**根拠**: R3/R4（ユーティリティ）を先に確立し、R1/R2（呼び出し元）は安定した基盤の上で書き替える。FR-1〜FR-7、SR-1〜SR-3 の全要件は Step 5 の全量テストで回帰検証する。

### D-007: deploy_task.sh の既存機能要件は全て維持する

**状態**: 承認

**文脈**: `deploy_task.sh` は normal / `--direct` / `--yaml` / `--cmd` の4配備モード（FR-1）、忍者名バリデーション（FR-2）、tmux/CLI 経由の idle/busy 判定（FR-3）、stale フィールドリセット（FR-4）、cmd→タスクメタデータ解決（FR-5）、報告テンプレート生成（FR-6）、inbox_write.sh 経由の配信（FR-7）を担う。安全要件として共有 YAML ヘルパー使用（SR-1）、重複配備ブロック（SR-2）、inbox パス限定配信（SR-3）がある。

**決定**: 本リファクタリングは `resolve_cmd_to_task()`（FR-5 の一部）と `inject_ac_version()`（FR-5 の一部）の内部実装のみを変更する。上記 FR-1〜FR-7、SR-1〜SR-3 の外部契約は一切変更しない。

## 3. Follow-ups

| ID | 内容 | トリガー | 担当 |
|----|------|----------|------|
| FU-001 | `yaml_field_set_batch` の他の呼び出し元への展開検討（`inbox_write.sh`, `lesson_write.sh` 等で逐次 `yaml_field_set` を使っている箇所） | R3 完了 + 全量テスト PASS 後 | 家老判断 |
| FU-002 | `source deploy_task.sh` の137ms（3607行読込）短縮 — 関数分割による遅延読込の検討 | 本リファクタリング完了後 | 偵察cmd |
| FU-003 | プロファイル再計測で −80% 未達の場合の追加最適化（awk スクリプトのインライン化、verify_after_write の条件付きスキップ等） | Step 5 計測結果 | 家老判断 |
| FU-004 | `field_get_multi` の出力形式が eval 安全であることの fuzz テスト（値に `=`, 改行, シェルメタ文字を含むケース） | R4 単体テスト時 | R4 実装者 |
| FU-005 | `yaml_field_set_batch` と既存 `yaml_field_set` の混在呼び出し時の並行安全性の負荷テスト（10並列 flock 競合） | R3 単体テスト時 | R3 実装者 |
