# deploy_task.sh リファクタリング CoDD Spec

## 問題
deploy_task.sh(3607行)のresolve_cmd_to_task()とinject_ac_version()がテスト1件あたり2.6秒消費。
根因: 同一ファイルに対するyaml_field_set/field_getの逐次呼び出し（毎回flock+awk全量rewrite）。

## 定量プロファイル(2026-04-15実測)

| 関数 | 時間 | field_get | yaml_field_set | 根因 |
|------|------|-----------|----------------|------|
| resolve_cmd_to_task | 627ms | 0 | 7 | 7回flock+7回awk全量rewrite |
| inject_ac_version | 541ms | 6-7 | 3 | 6回grep+3回flock+3回awk全量rewrite |
| source deploy_task.sh | 137ms | - | - | 3607行読込 |
| **合計** | **1305ms** | | | テスト1件の93% |

### yaml_field_set 1回あたりのコスト
- mktemp (1回)
- flock -w 10 (排他ロック取得)
- awk全量rewrite (ファイル全行走査)
- mv atomic replacement
- post-write verification (再読込)
- **計: 20-50ms/回**

### field_get 1回あたりのコスト
- grep/sed YAML解析
- optional: flock + date + log書込み
- **計: 2-15ms/回**

## リファクタリング対象

### R1: resolve_cmd_to_task() — yaml_field_set 7回→1回バッチ化

**現状** (L247-330):
```
awk STK→変数抽出 (1回、高速)
yaml_field_set task parent_cmd ...  # flock+rewrite #1
yaml_field_set task task_id ...     # flock+rewrite #2
yaml_field_set task task_type ...   # flock+rewrite #3
yaml_field_set task project ...     # flock+rewrite #4
yaml_field_set task status ...      # flock+rewrite #5
yaml_field_set task purpose ...     # flock+rewrite #6
yaml_field_set task _ac_task_id ... # flock+rewrite #7
```

**改善**: 7回のyaml_field_set → 1回のawk pass(flock 1回+rewrite 1回)
- 入力: field=value ペアの配列
- 処理: 1回のawkで全フィールドを同時に更新/追加
- 期待効果: 627ms → ~100ms

### R2: inject_ac_version() — field_get 6回→1回awk、field_set 3回→1回バッチ化

**現状** (L690-745):
```
field_get ac_version       # grep #1
field_get task_id          # grep #2
field_get _ac_task_id      # grep #3 (conditional)
field_get worker_id        # grep #4
field_get _ac_worker_id    # grep #5 (conditional)
field_get _ac_task_id      # grep #6
field_get _ac_worker_id    # grep #7
... awk _compute_ac_hash ...
yaml_field_set ac_version  # flock+rewrite #1
yaml_field_set _ac_task_id # flock+rewrite #2
yaml_field_set _ac_worker_id # flock+rewrite #3
```

**改善**:
- field_get 6-7回 → 1回のawkで全フィールド一括抽出
- yaml_field_set 3回 → 1回のawkバッチ書込み
- 期待効果: 541ms → ~80ms

### R3: batch yaml_field_set ユーティリティ関数

新関数 `yaml_field_set_batch` をlib/yaml_field_set.shに追加:
```bash
yaml_field_set_batch <file> <block_id> <field1>=<value1> <field2>=<value2> ...
```
- 1回のflock+1回のawk passで全フィールドを同時に更新
- 既存yaml_field_setの内部awkロジックを拡張
- verify_after_writeも1回のみ

### R4: batch field_get ユーティリティ関数

新関数 `field_get_multi` をlib/field_get.shに追加:
```bash
field_get_multi <file> <field1> <field2> ... → "field1=value1\nfield2=value2\n..."
```
- 1回のawk passで複数フィールドを一括抽出
- eval可能な出力形式

## 期待効果

| 関数 | Before | After | 短縮 |
|------|--------|-------|------|
| resolve_cmd_to_task | 627ms | ~100ms | -84% |
| inject_ac_version | 541ms | ~80ms | -85% |
| **1テスト合計** | 2639ms | ~400ms | **-85%** |
| **48テスト(ac_handling)** | 34s | ~5s | **-85%** |

## 実施順序

1. **R3: yaml_field_set_batch** — 新ユーティリティ関数+テスト
2. **R4: field_get_multi** — 新ユーティリティ関数+テスト
3. **R1: resolve_cmd_to_task書替え** — R3利用。既存テスト全PASS確認
4. **R2: inject_ac_version書替え** — R3+R4利用。既存テスト全PASS確認
5. **全量テスト+プロファイル再計測** — before/after比較

## 制約
- 既存テスト全PASS維持（リグレッション禁止）
- flock排他の正確性維持（並行書込み安全）
- yaml_field_setの既存API互換維持（他の呼出元に影響なし）
- field_getの既存API互換維持
