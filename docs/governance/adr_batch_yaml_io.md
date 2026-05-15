---
codd:
  node_id: governance:adr-batch-yaml-io
  type: governance
  depends_on:
  - id: req:deploy-task-refactor-requirements
    relation: derives_from
    semantic: governance
  - id: req:script:deploy-task
    relation: derives_from
    semantic: governance
  depended_by:
  - id: design:system-architecture
    relation: constrained_by
    semantic: governance
  - id: detailed:yaml-io-library
    relation: constrained_by
    semantic: governance
  conventions:
  - targets:
    - module:yaml_helpers
    - module:deploy_task
    reason: Existing yaml_field_set and field_get API signatures must remain unchanged;
      backward compatibility is release-blocking (refactor constraints).
  - targets:
    - module:yaml_helpers
    reason: flock exclusive locking correctness must be preserved in batch operations;
      single flock acquisition per batch call (refactor constraints + inbox_write
      FR-4).
  modules:
  - yaml_helpers
  - deploy_task
---

# ADR: Batch YAML I/O Refactoring

## 1. Overview

deploy_task.sh (3,607行) の `resolve_cmd_to_task()` および `inject_ac_version()` が、同一ファイルに対する `yaml_field_set` / `field_get` の逐次呼び出しによりテスト1件あたり 2.6秒（全体の93%）を消費している。根因は毎回の flock 排他ロック取得 + awk 全量 rewrite + post-write verification の繰り返しである。

本 ADR は、既存 API 互換を維持したまま batch I/O ユーティリティ (`yaml_field_set_batch`, `field_get_multi`) を導入し、48テスト (ac_handling) の実行時間を 34秒 → 約5秒 (−85%) に短縮する意思決定を記録する。

### 定量プロファイル (2026-04-15 実測)

| 関数 | Before | After (期待) | 短縮率 | 根因 |
|------|--------|-------------|--------|------|
| `resolve_cmd_to_task` | 627ms | ~100ms | −84% | yaml_field_set 7回 → 1回 (flock 7→1, awk rewrite 7→1) |
| `inject_ac_version` | 541ms | ~80ms | −85% | field_get 6–7回 → awk 1回, yaml_field_set 3回 → 1回 |
| source deploy_task.sh | 137ms | 137ms | — | 対象外 |
| **1テスト合計** | **2,639ms** | **~400ms** | **−85%** | |
| **48テスト** | **34s** | **~5s** | **−85%** | |

### yaml_field_set 1回あたりのコスト内訳

- mktemp (一時ファイル生成)
- `flock -w 10` (排他ロック取得)
- awk 全量 rewrite (ファイル全行走査)
- `mv` atomic replacement
- post-write verification (再読込)
- **計: 20–50ms/回**

### field_get 1回あたりのコスト内訳

- grep/sed による YAML 解析
- optional: flock + date + log 書込み
- **計: 2–15ms/回**

### 非交渉制約の遵守

**後方互換性 (module:yaml_helpers, module:deploy_task)**: `yaml_field_set` および `field_get` の既存 API シグネチャは一切変更しない。新関数 `yaml_field_set_batch` と `field_get_multi` は追加であり、既存の呼び出し元 (deploy_task.sh 以外の全スクリプト) は変更不要。deploy_task.sh 内部でのみ呼び出しを batch 版に切り替える。これはリリースブロッキング制約であり、既存テスト全 PASS が移行の前提条件となる。

**flock 排他ロック正確性 (module:yaml_helpers)**: `yaml_field_set_batch` は 1回の `flock -w 10` 取得で全フィールドを単一 awk pass で更新し、atomic な `mv` で置換する。複数フィールド更新中にロックが解放される瞬間は存在しない。これは FR-4 (stale task field reset) および SR-1 (shared YAML helpers for queue/task mutation) の安全性要件を満たす。

## 2. Decision Log

### D-001: batch 書込みは新関数追加、既存関数は温存

**決定**: `yaml_field_set` を内部改修するのではなく、`yaml_field_set_batch` を `lib/yaml_field_set.sh` に新規追加する。

**理由**: 既存 `yaml_field_set` は deploy_task.sh 以外の多数のスクリプト (inbox_write.sh, inbox_mark_read.sh, ninja_monitor.sh 等) から単一フィールド更新に使用されている。API シグネチャ変更は波及範囲が広すぎる。新関数追加なら呼び出し元への影響はゼロで、テスト全 PASS を構造的に保証できる。

**API 定義**:
```bash
yaml_field_set_batch <file> <block_id> <field1>=<value1> [<field2>=<value2> ...]
```
- flock 1回 + awk 1 pass + mv 1回 + verify 1回
- 既存 `yaml_field_set` の内部 awk ロジックを拡張し、複数フィールド同時マッチ・更新を行う
- フィールドが存在しない場合はブロック末尾に追加 (既存動作と同一)
- `=` を含む value は最初の `=` で分割 (value 内の `=` は保持)

### D-002: batch 読取りも新関数追加

**決定**: `field_get_multi` を `lib/field_get.sh` に新規追加する。

**理由**: inject_ac_version() が同一ファイルを 6–7回 grep するオーバーヘッドを排除する。1回の awk pass で全フィールドを抽出すれば I/O を 1/7 に削減できる。

**API 定義**:
```bash
field_get_multi <file> <field1> [<field2> ...] → stdout: "field1=value1\nfield2=value2\n..."
```
- eval 可能な出力形式 (`eval "$(field_get_multi ...)"` で変数展開)
- 存在しないフィールドは空値 (`field1=`) として出力 (呼び出し元で存在判定可能)
- 既存 `field_get` は温存し、単一フィールド取得の既存呼び出し元に影響なし

### D-003: 実施順序は R3 → R4 → R1 → R2 → 全量検証

**決定**: ユーティリティ関数を先に作成・テストし、その後 deploy_task.sh の呼び出し元を段階的に切り替える。

**理由**: ユーティリティ関数の正確性を独立テストで確認してから適用することで、リグレッションリスクを最小化する。各段階で既存テスト全 PASS を確認してから次へ進む。

| Step | 対象 | 内容 | 検証 |
|------|------|------|------|
| 1 | R3: `yaml_field_set_batch` | 新ユーティリティ + 単体テスト | batch 書込みの flock 正確性、atomic 置換、複数フィールド同時更新 |
| 2 | R4: `field_get_multi` | 新ユーティリティ + 単体テスト | 複数フィールド一括抽出、eval 可能出力、存在しないフィールドの空値出力 |
| 3 | R1: `resolve_cmd_to_task` | yaml_field_set 7回 → yaml_field_set_batch 1回 | 既存 deploy_task テスト全 PASS |
| 4 | R2: `inject_ac_version` | field_get 6–7回 → field_get_multi 1回, yaml_field_set 3回 → yaml_field_set_batch 1回 | 既存 deploy_task テスト全 PASS |
| 5 | 全量検証 | 48テスト (ac_handling) + プロファイル再計測 | before/after 比較で −85% 確認 |

### D-004: flock 取得戦略は「1 batch = 1 flock」

**決定**: `yaml_field_set_batch` は関数呼び出し全体で 1回の flock を取得し、全フィールド更新完了後に解放する。中間状態で他プロセスが読み取る余地を排除する。

**理由**: deploy_task.sh は FR-5 (cmd → task metadata 解決) で複数フィールドを一括設定する。parent_cmd, task_id, status 等が部分的に更新された中間状態を inbox_watcher や ninja_monitor が読み取ると、不整合な task YAML に基づく誤動作が発生する。single flock acquisition per batch call はこの不整合を構造的に防止する。これは SR-1 (shared YAML helpers) の要件を直接満たす。

### D-005: resolve_cmd_to_task の awk STK 抽出は変更なし

**決定**: resolve_cmd_to_task() 冒頭の awk による STK (shogun_to_karo.yaml) からの変数抽出は現状維持する。

**理由**: STK 抽出は 1回の awk pass で完了しており、ボトルネックではない。変更対象は抽出後の yaml_field_set 7回のみ。変更範囲を最小化し、FR-5 (cmd → task metadata 解決) の正確性を維持する。

### D-006: deploy_task.sh の FR-4 (stale field reset) は batch に統合

**決定**: FR-4 が要求する stale task field リセット・ghost `None.yaml` 除去は、resolve_cmd_to_task() 内の yaml_field_set_batch 呼び出しに統合する。リセット対象フィールドを batch のフィールドリストに含め、1回の flock+rewrite で新規設定と同時に処理する。

**理由**: stale field リセットと新規設定を別々の I/O にすると、リセット後・設定前の中間状態が発生する。batch 統合によりこの窓を排除し、SR-2 (duplicate active deployment blocking) の前提となるタスク状態の一貫性を保証する。

### D-007: verify_after_write は batch 完了後に 1回のみ実行

**決定**: 既存の yaml_field_set は毎回 verify_after_write (再読込による書込み確認) を実行するが、yaml_field_set_batch では全フィールド書込み完了後に 1回のみ実行する。

**理由**: verify_after_write は atomic mv 後のファイル破損検出が目的。batch では mv が 1回なので検証も 1回で十分。7回の verify を 1回に削減することで、−84% 短縮の一部を構成する。

## 3. Follow-ups

| ID | 内容 | 条件 | 対象モジュール |
|----|------|------|--------------|
| FU-1 | yaml_field_set_batch の並行書込みストレステスト | R3 実装完了後 | module:yaml_helpers |
| FU-2 | deploy_task.sh 以外の逐次 yaml_field_set 呼び出し箇所の棚卸し | 全量検証完了後 | module:yaml_helpers 全利用元 |
| FU-3 | field_get_multi の出力形式が eval injection に対して安全であることの検証 | R4 実装完了後。value に `$(...)` やバッククォートを含む YAML フィールドでの挙動確認 | module:yaml_helpers |
| FU-4 | プロファイル再計測による実測値と期待値 (−85%) の突合 | Step 5 完了後。乖離が 10% 以上の場合は原因調査 | module:deploy_task |
| FU-5 | inbox_write.sh (FR-7) 側の yaml_field_set 呼び出しが batch 化の恩恵を受けるかの評価 | FU-2 の棚卸し結果に基づく | module:yaml_helpers, scripts/inbox_write.sh |
