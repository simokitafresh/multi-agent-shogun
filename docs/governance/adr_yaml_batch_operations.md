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

本ADRは、`module:yaml_helpers`（`scripts/lib/yaml_field_set.sh`, `scripts/lib/field_get.sh`）および `module:deploy_task`（`scripts/deploy_task.sh`）に対するYAMLバッチ操作の設計判断を記録する。

### 背景

`deploy_task.sh`（3607行）の `resolve_cmd_to_task()` と `inject_ac_version()` がテスト1件あたり2.6秒を消費している。根因は同一ファイルに対する `yaml_field_set` / `field_get` の逐次呼び出しであり、毎回 flock 取得 + awk 全量 rewrite が発生する。48テスト（ac_handling）で合計34秒に達する。

| 関数 | 現状時間 | field_get回数 | yaml_field_set回数 | 根因 |
|------|----------|---------------|-------------------|------|
| `resolve_cmd_to_task` | 627ms | 0 | 7 | 7回 flock + 7回 awk 全量 rewrite |
| `inject_ac_version` | 541ms | 6–7 | 3 | 6回 grep + 3回 flock + 3回 awk 全量 rewrite |
| `source deploy_task.sh` | 137ms | — | — | 3607行読込 |
| **合計** | **1305ms** | | | テスト1件の93% |

単体コスト内訳: `yaml_field_set` 1回あたり mktemp → flock -w 10 → awk 全量 rewrite → mv atomic replacement → post-write verification で 20–50ms。`field_get` 1回あたり grep/sed YAML解析 + optional flock/date/log で 2–15ms。

### 決定の要旨

2つのバッチユーティリティ関数を導入し、既存API契約を完全保持したまま I/O 回数を削減する。

1. **`yaml_field_set_batch`**（`scripts/lib/yaml_field_set.sh` に追加）: 複数フィールドを **単一の flock + 単一の awk pass** で同時更新する。
2. **`field_get_multi`**（`scripts/lib/field_get.sh` に追加）: 複数フィールドを **単一の awk pass** で一括抽出する。

### リリースブロッキング制約への準拠

**制約: `yaml_field_set_batch` は単一 flock + 単一 awk pass を使用すること。`field_get_multi` は単一 awk pass を使用すること。既存API契約を保持すること。違反は全 queue mutation をシステム全体で破壊する。**

本ADRはこの制約を以下のように遵守する:

- `yaml_field_set_batch` の内部実装は `flock -w 10` を1回だけ取得し、その中で1回の awk 実行により全フィールドを同時に更新/追加する。mktemp → flock → awk(全フィールド一括) → mv atomic replacement → post-write verification(1回)の順序を厳守する。
- `field_get_multi` の内部実装は flock を取得せず（読取専用）、1回の awk 実行で指定全フィールドを走査・抽出する。
- 既存の `yaml_field_set <file> <block_id> <field> <value>` および `field_get <file> <field>` のシグネチャ・挙動・戻り値は一切変更しない。バッチ関数は追加APIであり、既存関数の置換ではない。`deploy_task.sh` 以外の全呼び出し元は既存APIをそのまま使用し続ける。
- `deploy_task.sh` は FR-5（cmd→タスクメタデータ解決）および SR-1（共有YAMLヘルパー使用の義務）に準拠したまま、内部の逐次呼び出しをバッチ呼び出しに置換する。

### 期待効果

| 関数 | Before | After | 短縮率 |
|------|--------|-------|--------|
| `resolve_cmd_to_task` | 627ms | ~100ms | -84% |
| `inject_ac_version` | 541ms | ~80ms | -85% |
| **1テスト合計** | 2639ms | ~400ms | **-85%** |
| **48テスト (ac_handling)** | 34s | ~5s | **-85%** |

## 2. Decision Log

### ADR-001: バッチ関数を既存ファイルに追加（新ファイル作成せず）

**決定**: `yaml_field_set_batch` は `scripts/lib/yaml_field_set.sh` に、`field_get_multi` は `scripts/lib/field_get.sh` に追加する。

**理由**: deploy_task.sh は既に両ファイルを source している（FR-5, SR-1）。新ファイルを作ると source パスの追加が必要になり、全 queue mutation スクリプトへの波及リスクが生じる。同一ファイル内に追加すれば既存の source 行がそのまま機能する。

**影響範囲**: `module:yaml_helpers` のみ。他スクリプトの source 行は変更不要。

### ADR-002: yaml_field_set_batch のインターフェース設計

**決定**: 以下のシグネチャを採用する。

```bash
yaml_field_set_batch <file> <block_id> <field1>=<value1> [<field2>=<value2> ...]
```

**理由**: 既存 `yaml_field_set <file> <block_id> <field> <value>` との一貫性を維持しつつ、可変長引数で複数フィールドを受け取る。`=` 区切りにすることで引数のパース曖昧性を排除する（値にスペースを含む場合もクォートで対応可能）。

**内部処理フロー**:
1. 引数から field=value ペア配列を構築
2. `mktemp` で一時ファイル作成
3. `flock -w 10` で排他ロック取得（1回のみ）
4. 1回の awk で対象 block_id 内の全フィールドを走査し、既存フィールドは値を置換、未存在フィールドはブロック末尾に追加
5. `mv` でアトミック置換
6. post-write verification（1回のみ: 全フィールドが正しく書き込まれたことを確認）
7. flock 解放

**制約準拠**: flock 1回 + awk 1 pass を厳守。resolve_cmd_to_task の7回 flock + 7回 awk を1回ずつに削減。

### ADR-003: field_get_multi のインターフェース設計

**決定**: 以下のシグネチャを採用する。

```bash
field_get_multi <file> <field1> [<field2> ...] → stdout: "field1=value1\nfield2=value2\n..."
```

**理由**: 出力形式を `field=value` の改行区切りにすることで、呼び出し元で `eval` または `while IFS='=' read` で変数に展開できる。既存 `field_get` は単一値を stdout に返すため、複数値版は行区切りが自然。

**内部処理フロー**:
1. 引数からフィールド名配列を構築
2. 1回の awk でファイル全体を走査し、指定フィールドに一致する行から値を抽出
3. `field=value` 形式で stdout に出力

**制約準拠**: awk 1 pass を厳守。inject_ac_version の6–7回 grep を1回の awk に削減。flock は不要（読取専用操作）。

### ADR-004: 実施順序の決定

**決定**: 以下の順序で実施する。

| Phase | 対象 | 内容 | 依存 |
|-------|------|------|------|
| 1 | R3: `yaml_field_set_batch` | 新ユーティリティ関数 + 単体テスト | なし |
| 2 | R4: `field_get_multi` | 新ユーティリティ関数 + 単体テスト | なし |
| 3 | R1: `resolve_cmd_to_task` 書替え | R3 利用。既存テスト全 PASS 確認 | Phase 1 |
| 4 | R2: `inject_ac_version` 書替え | R3 + R4 利用。既存テスト全 PASS 確認 | Phase 1, 2 |
| 5 | 全量テスト + プロファイル再計測 | before/after 比較で -85% を検証 | Phase 3, 4 |

**理由**: ユーティリティ関数を先に作成・テストすることで、deploy_task.sh の書替え時にリグレッションリスクを最小化する。Phase 1 と Phase 2 は相互依存がないため並列実施可能。

### ADR-005: 既存API互換の保証方針

**決定**: 既存の `yaml_field_set` と `field_get` は一切変更しない。バッチ関数は純粋な追加であり、既存関数のラッパーや置換ではない。

**理由**: `yaml_field_set` は `deploy_task.sh` 以外にも `queue/`, `tasks/`, `inbox/`, `reports/`, `shogun_to_karo`, `karo_snapshot` の mutation で広く使用されている（SR-1）。既存関数のシグネチャや内部挙動を変更すると全 queue mutation がシステム全体で破壊される。

**検証方法**: Phase 3–4 完了後に既存テスト全PASS（48テスト ac_handling + deploy_task.sh の全テストスイート）を確認する。SKIP = FAIL として扱う。

### ADR-006: flock 排他の正確性維持

**決定**: `yaml_field_set_batch` は既存 `yaml_field_set` と同一の flock ファイル（対象YAMLファイル自体）を使用する。

**理由**: 異なるロックファイルを使うと、`yaml_field_set`（単一フィールド）と `yaml_field_set_batch`（複数フィールド）が同一ファイルに対して並行書込みした場合にデータ破壊が発生する。同一ロックファイルにすることで排他が保証される。deploy_task.sh の FR-4（stale fields リセット）や FR-7（inbox_write 経由の配信）との並行安全性を維持する。

### ADR-007: deploy_task.sh の配備モード互換維持

**決定**: `--direct`, `--yaml`, `--cmd` の全配備モード（FR-1）でバッチ関数を使用する。モードごとの分岐ロジックは変更しない。

**理由**: バッチ化は I/O 最適化であり、ビジネスロジックの変更ではない。resolve_cmd_to_task() 内の7回の yaml_field_set を1回の yaml_field_set_batch に置換するのみ。inject_ac_version() 内の field_get 6–7回を field_get_multi 1回に、yaml_field_set 3回を yaml_field_set_batch 1回に置換するのみ。FR-2（対象バリデーション）、FR-3（idle/busy判定）、FR-6（レポートテンプレート生成）、SR-2（重複配備ブロック）、SR-3（inbox パス通信）には影響しない。

## 3. Follow-ups

| ID | 内容 | トリガー | 対象ファイル |
|----|------|---------|------------|
| FU-001 | Phase 5 プロファイル再計測で -85% 未達の場合、awk スクリプト内のボトルネックを特定し追加最適化を検討する | Phase 5 完了時 | `scripts/lib/yaml_field_set.sh` |
| FU-002 | `yaml_field_set_batch` の導入後、deploy_task.sh 以外の逐次呼び出しホットスポット（ninja_monitor.sh, inbox_write.sh 等）でもバッチ化の適用を検討する | Phase 5 完了後 | `scripts/lib/yaml_field_set.sh` 呼び出し元全体 |
| FU-003 | `field_get_multi` の出力形式が eval 安全であることを確認するテスト（値に `=`, スペース, 改行, シングルクォートを含むケース）を Phase 2 のテストスイートに含める | Phase 2 実施時 | `scripts/lib/field_get.sh` テスト |
| FU-004 | バッチ関数追加後、`pre-bash-yaml-dump-guard.sh` hook がバッチ関数を誤ブロックしないことを確認する（バッチ関数は yaml.dump ではなく awk ベースのため対象外のはずだが、hook パターンマッチの偽陽性を排除する） | Phase 1 実施時 | `.claude/hooks/pre-bash-yaml-dump-guard.sh` |
| FU-005 | CoDD propagate で本ADRの変更が `module:yaml_helpers` および `module:deploy_task` の設計書・テスト設計書に波及することを確認し、必要に応じて更新する | Phase 1 開始前 | `codd/designs/`, `codd/tests/` |
