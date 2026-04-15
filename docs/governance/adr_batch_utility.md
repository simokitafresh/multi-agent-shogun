---
codd:
  node_id: governance:adr-batch-utility
  type: governance
  depends_on:
  - id: req:deploy-task-refactor-requirements
    relation: derives_from
    semantic: governance
  depended_by:
  - id: design:system-design
    relation: constrained_by
    semantic: governance
  conventions:
  - targets:
    - module:yaml_field_set
    - module:field_get
    reason: 既存API互換維持が必須。バッチ関数は新規追加であり既存関数の署名・挙動を変更してはならない。
  modules:
  - yaml_field_set
  - field_get
---

# ADR: Batch YAML Utility Design Decision

## 1. Overview

本ADRは、`yaml_field_set`（module:yaml_field_set）および`field_get`（module:field_get）に対するバッチ処理関数の追加設計判断を記録する。

### 背景

`deploy_task.sh`（3607行）内の`resolve_cmd_to_task()`と`inject_ac_version()`が、同一YAMLファイルに対して`yaml_field_set`を最大7回、`field_get`を最大7回逐次呼び出している。各`yaml_field_set`呼び出しはflock排他ロック取得→awk全量rewrite→atomic mv→post-write verificationを伴い、1回あたり20–50msを消費する。`field_get`も1回あたり2–15ms（grep/sed解析＋optional flock/log）を消費する。結果としてテスト1件あたり約1305msがこの2関数に費やされ、48テスト（ac_handling）全体で約34秒となっている。

### 決定の範囲

- `lib/yaml_field_set.sh` に `yaml_field_set_batch` 関数を**新規追加**する
- `lib/field_get.sh` に `field_get_multi` 関数を**新規追加**する
- 既存の `yaml_field_set` および `field_get` の関数シグネチャ・挙動は**一切変更しない**

### 既存API互換維持（リリースブロッキング制約）

本ADRの対象は module:yaml_field_set および module:field_get である。バッチ関数（`yaml_field_set_batch`, `field_get_multi`）は純粋な新規追加であり、既存関数の署名（引数の順序・個数・型）、戻り値、副作用（flock排他・atomic write・verify_after_write）、エラーコードのいずれも変更しない。既存の全呼び出し元は修正不要であり、既存テストは無変更で全PASSを維持する。この互換維持は本ADRにおけるリリースブロッキング制約として扱い、違反するいかなる実装も却下する。

## 2. Decision Log

### ADR-001: バッチ書込み関数 `yaml_field_set_batch` の導入

**ステータス**: 承認

**コンテキスト**: `resolve_cmd_to_task()` は同一ファイル・同一ブロックに対して `yaml_field_set` を7回連続呼び出す。各呼び出しがflock取得→awk全量走査→atomic mv→post-write verificationの完全サイクルを実行するため、合計627msを消費する。

**検討した選択肢**:

| 選択肢 | 説明 | 採否 | 理由 |
|--------|------|------|------|
| A. 既存関数のループ呼び出し維持 | 現状維持 | 却下 | 1テスト1305ms、48テスト34秒は許容不可 |
| B. yaml_field_set内部を可変長引数対応に改修 | 既存関数のシグネチャ変更 | 却下 | 既存API互換維持の制約に違反 |
| C. 新関数 `yaml_field_set_batch` を追加 | 既存関数と並存する新規バッチ関数 | **採用** | 互換維持＋1回のflock/awk/verifyで全フィールド更新 |
| D. 一時ファイルに書き溜めてflush | バッファリング方式 | 却下 | flock排他タイミングが不明瞭になり並行書込み安全性が低下 |

**決定**: 選択肢Cを採用する。

**関数シグネチャ**:
```bash
yaml_field_set_batch <file> <block_id> <field1>=<value1> <field2>=<value2> ...
```

**内部処理フロー**:
1. `mktemp` で一時ファイル作成（1回）
2. `flock -w 10` で排他ロック取得（1回）
3. 単一awkパスで全フィールドを同時に更新/追加（1回のファイル全行走査）
4. `mv` によるatomic replacement（1回）
5. `post-write verification`（1回の再読込で全フィールド検証）

**期待効果**: `resolve_cmd_to_task()` の7回flock+7回awk全量rewriteが1回flock+1回awk全量rewriteに集約され、627ms → 約100ms（-84%）。

**制約の遵守**:
- 既存 `yaml_field_set` 関数は無変更。シグネチャ `yaml_field_set <file> <block_id> <field> <value>` を保持
- flock排他の正確性維持: バッチ関数もflock -w 10による排他ロックを使用し、並行書込み安全性を保証
- verify_after_writeはバッチ完了後に1回実行し、全フィールドの書込み成功を検証

---

### ADR-002: バッチ読取り関数 `field_get_multi` の導入

**ステータス**: 承認

**コンテキスト**: `inject_ac_version()` は同一ファイルから `field_get` を6–7回連続呼び出す。各呼び出しがgrep/sedによるYAML解析を実行し、合計で541msのうち相当部分を消費する。

**検討した選択肢**:

| 選択肢 | 説明 | 採否 | 理由 |
|--------|------|------|------|
| A. 既存field_getのループ呼び出し維持 | 現状維持 | 却下 | 不要なI/O反復 |
| B. field_getを可変長引数対応に改修 | 既存関数のシグネチャ変更 | 却下 | 既存API互換維持の制約に違反 |
| C. 新関数 `field_get_multi` を追加 | 既存関数と並存する新規バッチ関数 | **採用** | 互換維持＋1回のawk passで全フィールド抽出 |

**決定**: 選択肢Cを採用する。

**関数シグネチャ**:
```bash
field_get_multi <file> <field1> <field2> ... → "field1=value1\nfield2=value2\n..."
```

**出力形式**: eval可能な `field=value` 形式を改行区切りで出力する。呼び出し元は `eval "$(field_get_multi ...)"` でシェル変数に展開可能。

**内部処理フロー**:
1. 単一awkパスでファイルを1回走査し、指定された全フィールドの値を抽出
2. 各フィールドを `field=value` 形式で標準出力に出力

**期待効果**: `inject_ac_version()` の6–7回grep/sed → 1回のawk passに集約。`yaml_field_set` 3回のバッチ化と合わせて541ms → 約80ms（-85%）。

**制約の遵守**:
- 既存 `field_get` 関数は無変更。シグネチャを保持
- 既存の全呼び出し元に影響なし

---

### ADR-003: 実施順序の決定

**ステータス**: 承認

**コンテキスト**: 4つのリファクタリング項目（R1–R4）間に依存関係がある。R1（resolve_cmd_to_task書替え）はR3（yaml_field_set_batch）に依存し、R2（inject_ac_version書替え）はR3とR4（field_get_multi）の両方に依存する。

**決定**: 以下の順序で実施する。

| Step | 対象 | 依存 | 完了基準 |
|------|------|------|----------|
| 1 | R3: `yaml_field_set_batch` 実装+単体テスト | なし | 新関数のテスト全PASS、既存yaml_field_setテスト全PASS |
| 2 | R4: `field_get_multi` 実装+単体テスト | なし | 新関数のテスト全PASS、既存field_getテスト全PASS |
| 3 | R1: `resolve_cmd_to_task()` をR3利用に書替え | R3完了 | 既存テスト全PASS（リグレッションなし） |
| 4 | R2: `inject_ac_version()` をR3+R4利用に書替え | R3+R4完了 | 既存テスト全PASS（リグレッションなし） |
| 5 | 全量テスト+プロファイル再計測 | R1–R4完了 | before/after比較で-85%達成確認 |

Step 1とStep 2は相互依存がないため並列実施可能。

**期待される最終効果**:

| 指標 | Before | After | 改善率 |
|------|--------|-------|--------|
| resolve_cmd_to_task | 627ms | ~100ms | -84% |
| inject_ac_version | 541ms | ~80ms | -85% |
| 1テスト合計 | 2639ms | ~400ms | -85% |
| 48テスト（ac_handling） | 34s | ~5s | -85% |

## 3. Follow-ups

| ID | 内容 | トリガー | 担当 |
|----|------|----------|------|
| FU-001 | `yaml_field_set_batch` の他の呼び出しパターンへの適用調査: deploy_task.sh以外にyaml_field_setを3回以上連続呼び出す箇所がないかgrepで特定し、バッチ化候補をリスト化する | R1–R4完了後 | 偵察cmd |
| FU-002 | プロファイル再計測の実施: Step 5で-85%未達の場合、awk内部処理のボトルネックを特定し追加最適化を検討する | Step 5完了時 | 実装cmd |
| FU-003 | `field_get_multi` のeval安全性検証: 値に特殊文字（シングルクォート、ダブルクォート、バックスラッシュ、改行）を含むケースのエッジケーステストを追加する | R4単体テスト時 | 実装cmd |
| FU-004 | pre-bash-yaml-dump-guard.sh hookとの整合確認: `yaml_field_set_batch` がhookのパターンマッチに誤検知されないことを検証する | R3実装時 | 実装cmd |
