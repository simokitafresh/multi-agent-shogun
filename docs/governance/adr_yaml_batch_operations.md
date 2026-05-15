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

本ADRは、`deploy_task.sh`（3607行）内の`resolve_cmd_to_task()`および`inject_ac_version()`が抱えるYAML I/Oボトルネックを解消するためのバッチ操作設計を記録する。

### 問題の構造

`deploy_task.sh`はタスクYAMLの変更に`yaml_field_set`（`scripts/lib/yaml_field_set.sh`）と`field_get`（`scripts/lib/field_get.sh`）を逐次呼び出す。各呼び出しが独立した`flock`取得＋`awk`全量rewrite＋`mv`アトミック置換＋post-write verificationを実行するため、1テストあたり2.6秒（全体の93%）をI/Oに消費する。

| 関数 | field_get回数 | yaml_field_set回数 | 合計時間 | 根因 |
|------|-------------|-------------------|---------|------|
| `resolve_cmd_to_task` | 0 | 7 | 627ms | 7回flock＋7回awk全量rewrite |
| `inject_ac_version` | 6–7 | 3 | 541ms | 6回grep＋3回flock＋3回awk全量rewrite |

48テスト（`ac_handling`スイート）で合計34秒。目標は-85%の約5秒。

### 決定の要旨

2つのバッチユーティリティ関数を導入する:

1. **`yaml_field_set_batch`**（`module:yaml_helpers`）— 複数フィールドを1回のflock＋1回のawk passで同時書込み
2. **`field_get_multi`**（`module:deploy_task`経由で`module:yaml_helpers`を利用）— 複数フィールドを1回のawk passで一括抽出

両関数は既存の`yaml_field_set`/`field_get`のAPI契約を破壊しない。既存関数は残存し、単一フィールド操作の呼び出し元は変更不要。

### 非交渉制約への適合

**制約**: `yaml_field_set_batch`は単一flock＋単一awk passを使用しなければならない。`field_get_multi`は単一awk passを使用しなければならない。既存API契約は保全必須であり、違反はキュー変更系全体を破壊する。

本ADRはこの制約を以下のように満たす:

- `yaml_field_set_batch`は`flock -w 10`を1回だけ取得し、その中で単一の`awk`プログラムが全`field=value`ペアを同時に処理する。`mktemp`→`awk`→`mv`アトミック置換→post-write verification（1回）の順序を1パスで完結させる。
- `field_get_multi`は`flock`を取得せず（読取専用）、単一の`awk`プログラムが指定された全フィールドを1回のファイル走査で抽出し、`field=value`改行区切りで出力する。
- 既存の`yaml_field_set <file> <block_id> <field> <value>`シグネチャと`field_get <file> <field>`シグネチャはそのまま残り、他の全呼び出し元（`inbox_write.sh`、`inbox_mark_read.sh`、`lesson_write.sh`等）は変更不要。

### 安全要件との対応

`deploy_task.sh`のBrownfield Requirements（`req:script:deploy-task`）との整合:

| 要件 | 本ADRでの対応 |
|------|-------------|
| SR-1: 共有YAMLヘルパーでキュー/タスク変更 | バッチ関数は`yaml_field_set.sh`内に追加。自由形式YAML書込みを増やさない |
| SR-2: 重複配備ブロック | バッチ化は書込み内容を変えない。ロック粒度はファイル単位flockで同一 |
| SR-3: inbox経路の通信維持 | 本ADRはinbox経路に変更を加えない |
| FR-5: cmd→タスクメタデータ解決 | `resolve_cmd_to_task`のバッチ化は7フィールド同時書込みで機能等価 |
| FR-7: inbox_write.sh経由配信 | バッチ化対象外。既存フロー維持 |

## 2. Decision Log

### ADR-001: バッチ書込みの粒度 — ファイル単位flock維持

**状況**: `yaml_field_set`は呼び出し毎にファイル全体をflockする。バッチ化で粒度を変更するか。

**決定**: ファイル単位flockを維持する。バッチ関数は1回のflockの中で全フィールドを処理する。

**根拠**: 現行の並行安全性モデル（`flock -w 10` + アトミック`mv`）を変更すると、`inbox_write.sh`等の他のflock利用者との整合性が崩れる。粒度変更は本リファクタリングのスコープ外。

### ADR-002: `yaml_field_set_batch`のインターフェース設計

**状況**: バッチ書込み関数のシグネチャをどうするか。

**決定**:
```bash
yaml_field_set_batch <file> <block_id> <field1>=<value1> [<field2>=<value2> ...]
```

**根拠**: 既存`yaml_field_set <file> <block_id> <field> <value>`と同じ先頭2引数を維持し、3引数目以降を`key=value`ペアとして可変長で受け取る。これにより:
- 呼び出し元の移行が機械的（7行→1行）
- `=`区切りにより引数の対応関係が明示的
- 値に空白を含む場合はシェルクォートで対応（既存`yaml_field_set`と同じ制約）

### ADR-003: `field_get_multi`のインターフェースと出力形式

**状況**: バッチ読取関数の出力形式をどうするか。

**決定**:
```bash
field_get_multi <file> <field1> [<field2> ...]
# 出力: field1=value1\nfield2=value2\n...
```

呼び出し元はeval互換の出力をそのまま変数に展開できる:
```bash
eval "$(field_get_multi "$task_file" ac_version task_id worker_id)"
```

**根拠**: eval可能な`key=value`改行区切りは、既存の`field_get`呼び出しパターン（`local var; var=$(field_get ...)`）からの移行コストが最小。1回のawk passで全フィールドを抽出するため、ファイル走査は1回で済む。

### ADR-004: 既存関数の残存方針

**状況**: バッチ関数導入後、既存の`yaml_field_set`と`field_get`を廃止するか。

**決定**: 残存させる。廃止しない。

**根拠**: `yaml_field_set`は`deploy_task.sh`以外にも`inbox_write.sh`、`inbox_mark_read.sh`、`lesson_write.sh`、`bulletin_write.sh`等の20以上のスクリプトから呼ばれている。単一フィールド操作のユースケースは残り続けるため、既存APIを維持し、バッチ関数は「複数フィールドを同一ブロックに同時書込み/読取する」ユースケース専用とする。

### ADR-005: 実施順序 — ユーティリティ先行、呼び出し元後行

**状況**: R1–R4の実施順序をどうするか。

**決定**: R3→R4→R1→R2→全量テスト＋プロファイル再計測の順序。

| Phase | 対象 | 内容 | 検証基準 |
|-------|------|------|---------|
| Phase 1 | R3: `yaml_field_set_batch` | `lib/yaml_field_set.sh`にバッチ関数追加＋単体テスト | 新テスト全PASS。既存`yaml_field_set`テスト全PASS（リグレッションなし） |
| Phase 2 | R4: `field_get_multi` | `lib/field_get.sh`にバッチ読取関数追加＋単体テスト | 新テスト全PASS。既存`field_get`テスト全PASS |
| Phase 3 | R1: `resolve_cmd_to_task` | 7回`yaml_field_set`→1回`yaml_field_set_batch`に書替え | 既存48テスト全PASS。SKIP=0 |
| Phase 4 | R2: `inject_ac_version` | 6回`field_get`→1回`field_get_multi`、3回`yaml_field_set`→1回`yaml_field_set_batch` | 既存48テスト全PASS。SKIP=0 |
| Phase 5 | 全量テスト＋計測 | before/after比較。`time`計測で各関数の実行時間を記録 | 1テスト合計≤500ms（目標400ms）。48テスト合計≤8s（目標5s） |

**根拠**: ユーティリティ関数を先に作りテストすることで、呼び出し元の書替え時にバッチ関数の正しさが保証済みとなる。呼び出し元の変更は機能等価の書替えのみとなり、リグレッションリスクが局所化される。

### ADR-006: post-write verificationのバッチ対応

**状況**: 既存`yaml_field_set`はwrite後に再読込で値を検証する。バッチ関数でも全フィールドを検証するか。

**決定**: バッチ関数では書込み完了後に1回のawk passで全フィールドの値を検証する。フィールド毎の個別検証は行わない。

**根拠**: N回の検証をN回のgrep/awkで行うと、バッチ化の効果が半減する。1回のawkで全フィールドを読み取り、期待値と突合する。1つでも不一致があればエラーを返す。

### ADR-007: awkプログラムの設計方針

**状況**: バッチawkプログラムの複雑性をどう管理するか。

**決定**: 既存`yaml_field_set`内部のawkロジック（ブロックID検出→フィールド検索→値置換/追加）を拡張し、複数フィールドを連想配列で管理する。新規awkプログラムを別途作成せず、既存パターンを踏襲する。

**根拠**: 既存awkロジックは`block_id`行の検出→インデント内のフィールド走査→値置換という構造で、これを連想配列（`fields_to_set["field_name"] = "value"`）に拡張するだけで複数フィールド対応が可能。独自パーサーの新規作成はメンテナンスコストが増大する。

## 3. Follow-ups

| ID | 内容 | 条件 | 優先度 |
|----|------|------|--------|
| FU-001 | `deploy_task.sh`の`source`コスト（137ms）の削減。3607行の関数定義ファイルの分割または遅延読込み | Phase 5計測でsource時間が全体の20%以上を占める場合 | 低 |
| FU-002 | `yaml_field_set`の他の高頻度呼び出し元（`inbox_write.sh`等）でのバッチ化適用検討 | Phase 5完了後、プロファイルデータに基づき判断 | 中 |
| FU-003 | `field_get_multi`のeval出力における値のエスケープ強化。値に`=`や改行を含むケースへの対応 | 現行の運用YAMLで該当ケースが発見された場合 | 中 |
| FU-004 | バッチ関数のbatsテストで並行書込み競合シナリオ（複数プロセスが同一ファイルに同時バッチ書込み）のストレステスト追加 | Phase 1–2のテスト作成時に基本ケースは含める。ストレステストはPhase 5後 | 低 |
| FU-005 | Phase 5の計測結果が目標（1テスト≤500ms）未達の場合、`flock`のタイムアウト値（現行10秒）の短縮、またはtmpfsへの一時ファイル配置を検討 | Phase 5計測結果に基づく | 条件付き |
