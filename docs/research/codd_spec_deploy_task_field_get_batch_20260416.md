# CoDD Spec: deploy_task.sh field_get batch最適化 (cmd_1983)

**日付**: 2026-04-16
**実施者**: kotaro
**対象**: `scripts/deploy_task.sh` — `generate_report_template()` + `is_before_after_required_task()`
**Phase**: Phase 5（計測+実装+検証）spec事後作成

---

## 1. 前回改善内容確認

| 項目 | 内容 |
|------|------|
| 実施者 | 軍師 (2026-04-15) |
| before | 2639ms (cold, 軍師計測) |
| after | 88ms (after_doc記載値: native Linux環境) |
| 改善手法 | resolve_cmd_to_task: yaml_field_set 7→batch 1, inject_ac_version: field_get 6→multi 1 + yaml_field_set 3→batch 1 |
| 参照 | `docs/research/deploy_task_after_20260415.md` |

**WSL2実測ベースライン (cmd_1983)**: `generate_report_template` 単体 **224ms** (10回中央値)
→ 前回改善後でも WSL2 NTFS環境では依然高コスト。原因: generate_report_template内に field_get 呼び出しが12+回残存。

---

## 2. 残存ボトルネック特定

### B1: generate_report_template() — 12+個の field_get 呼び出し (★主要)

`generate_report_template()` 内部で同一YAMLファイルを12+回個別に読み込んでいた:

| 箇所 | フィールド | コスト推定 |
|------|-----------|-----------|
| line 1098 | assigned_to | ~20ms |
| line 1100 | subtask_id | ~20ms |
| line 1102 | task_id | ~20ms |
| line 1105 | _ac_task_id | ~20ms |
| line 1108 | parent_cmd | ~20ms |
| line 1110 | ac_version | ~20ms |
| line 1333-1334 | task_type | ~20ms |
| line 1339 | target_path | ~20ms |
| line 1340 | scout_exempt | ~20ms |
| line 1569-1577 | task_type / type / scope_mode | ~20ms×3 |
| **合計** | | **~240ms** |

WSL2 NTFS上では subprocess fork+exec が支配的 (~20ms/回)。同一ファイルを12+回読むのは純粋な無駄。

**対策**: 関数冒頭で `field_get_multi` 1回に集約（全フィールドを1 awk pass で抽出）→ 後続の呼び出しを変数参照に置き換え。

### B2: is_before_after_required_task() — field_get 2回（B1の副産物として解消）

`generate_report_template()` → `is_before_after_required_task()` 呼び出し時、内部でさらに `title` と `task_type` を個別取得していた。
→ B1で `title` / `task_type` が既に取得済みのため、第3・第4引数として渡すことで関数内部の field_get 2回を削除。

---

## 3. 実装内容（AC2）

### 変更1: `is_before_after_required_task()` に optional 引数追加 (line 864)

```bash
# 第3・第4引数が渡された場合はpre-read値を使用（field_get subprocess削減）
if [[ ${3+x} ]] && [[ ${4+x} ]]; then
    task_title="$3"
    task_type="$4"
else
    task_title=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "title" "" 2>/dev/null)
    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "" 2>/dev/null)
fi
```

### 変更2: `generate_report_template()` 冒頭に field_get_multi 一括読み取り (line 984)

```bash
# cmd_1983: 12+ field_get → field_get_multi 1回 (WSL2 subprocess削減)
local _p_task_id="$task_id" _p_parent_cmd="$parent_cmd"
local report_filename assigned_to subtask_id task_id _ac_task_id parent_cmd \
      ac_version title task_type target_path scout_exempt type scope_mode
eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" \
    report_filename assigned_to subtask_id task_id _ac_task_id \
    parent_cmd ac_version title task_type target_path scout_exempt \
    type scope_mode 2>/dev/null)" || true
```

### 変更3: 後続12+個の field_get → 変数参照に置き換え

- `worker_id="${assigned_to:-$ninja_name}"`
- `resolved_task_id="${subtask_id}"` → `"${task_id:-$_p_task_id}"` → `"${_ac_task_id}"`
- `resolved_parent_cmd="${parent_cmd:-$_p_parent_cmd}"`
- `_deploy_task_type="${task_type}"`
- `_tp_raw="${target_path}"` / `_scout_exempt="${scout_exempt}"`
- `report_task_type="${task_type:-${type:-${scope_mode}}}"`

### 変更4: is_before_after_required_task 呼び出しに title/task_type を渡す

```bash
if is_before_after_required_task "$task_file" "$resolved_parent_cmd" "$title" "$task_type"; then
```

**機能変更**: なし（全変数参照はfield_getと同じ値を返す。eval patternは既存field_get_multi実装を再利用）

---

## 4. 計測結果（AC3）

### 環境: WSL2 Ubuntu on Windows NTFS (/mnt/c/)

#### generate_report_template 単体（10回中央値）

| | 計測値 |
|--|--------|
| **Before** | **224ms** (WSL2実測) / 88ms (after_doc記載: native Linux推定) |
| **After** | **32ms** |
| **改善** | **-85.7%** (-192ms) / **2.6ms/field_get削減×約12回** |

#### template test suite（17 tests）

| | 計測値 |
|--|--------|
| **Before** | **15.6s** |
| **After** | **8.7s** |
| **改善** | **-44%** (-6.9s) |

---

## 5. テスト検証（AC4）

| テストスイート | 結果 |
|--------------|------|
| 全 unit tests (988件) | **PASS** |
| template generation (17件) | **17/17 PASS** |

---

## 6. 適用可能パターン（再発明防止）

- **同一YAMLファイルへの複数 field_get → field_get_multi 冒頭一括読み取り**: WSL2 NTFS環境で効果大。特に3回以上のfield_get呼び出しがある関数には積極適用すべし
- **呼び出し元から pre-read値をoptional引数で渡す**: 呼び出し先の内部field_getを排除する際の標準パターン
- **パラメータと同名フィールドの衝突対策**: `_p_task_id`等のコピー変数でeval前に退避

---

## 7. 関連

- 前回spec: `docs/research/deploy_task_after_20260415.md`
- L484: grep複数回→単一正規表現結合の教訓（同構造: subprocess削減）
- L483: 汎用ライブラリの無駄起動コスト（field_get_multi選択の根拠）
