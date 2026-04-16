# karo_workaround_log.sh リファクタリング CoDD Spec

## cmd: cmd_1967 (CoDD改善#15)
## 実施者: kagemaru
## 日付: 2026-04-16

## 問題（ボトルネック関数+計測値）

`scripts/karo_workaround_log.sh` の実行時間 ~55-61ms。
家老がWA記録ごとに発火するため 20回/セッション × 55ms = 1.1秒の累積コスト。
目標: 25ms/回以下。

ボトルネック: `validate_ninja_id()` 内のtask dirループが全体の約82%を占有。

## 定量プロファイル(実測 before)

| セクション | 時間 | 根因 |
|------------|------|------|
| `validate_ninja_id` — task dir loop | ~45ms | `basename "$f" .yaml` subprocess×10回(queue/tasks/*.yaml) |
| `validate_ninja_id` — settings.yaml awk | ~6ms | awk起動 + config/settings.yaml読取 |
| `count_category_entries` (awk on 1709行log) | ~12ms | karo_workarounds.yaml全行スキャン |
| bash startup + その他 | ~10ms | WSL2 syscall overhead |
| flock + cat >> log | ~5ms | file I/O |
| **合計(clean mode)** | **~55ms** | - |
| **合計(normal mode)** | **~70ms** | + classify + count |

主ボトルネック: `validate_ninja_id` task dirループ = 45ms (全体の ~82%)。
根因: `$(basename "$f" .yaml)` が bashサブシェルを spawning 10回。1回≈4.5ms。

## リファクタリング対象

### R1: validate_ninja_id — task dirループ廃止 → settings.yamlのみで検証

**現状**:
```bash
# Source 2: queue/tasks/ yaml files (10ファイル × subprocess)
if [[ -d "$tasks_dir" ]]; then
    for f in "$tasks_dir"/*.yaml; do
        [[ -f "$f" ]] && valid_names+=("$(basename "$f" .yaml)")  # ← subprocess ×10
    done
fi
```

**問題**:
- `$(basename "$f" .yaml)` = サブシェル spawn。10ファイル × 4.5ms = 45ms
- task filesはephemeral state。agents定義のsourceではない
- settings.yamlが全エージェントの権威リスト（config/settings.yaml §agents確認済み）

**改善**:
```bash
validate_ninja_id() {
    local ninja_id="$1"
    local settings_file="$REPO_ROOT/config/settings.yaml"
    # karo (caller) は常に有効
    [[ "$ninja_id" == "karo" ]] && return 0
    # settings.yaml agents のみで検証(task filesはephemeral)
    awk -v id="$ninja_id" '
        /^  agents:/ { in_agents=1; next }
        in_agents && /^    [a-z][a-z0-9_]*:$/ {
            name=$0; gsub(/^ +|:$/, "", name)
            if (name == id) { found=1; exit }
        }
        in_agents && /^[^ ]/ { exit }
        in_agents && /^  [a-z]/ { exit }
        END { exit !found }
    ' "$settings_file"
}
```

- 期待効果: 45ms削減(task dir loop廃止) + 6ms → 4ms(early exit)
- 予測合計: clean mode 55ms → ~10ms、normal mode 70ms → ~25ms

### R2(副次): 不要な変数・array廃止

- `valid_names` 配列が不要になる(awk結果をdirectly return)
- リニアサーチループも不要

## 機能要件(変更なし)

- [x] `--reclassify` / `--normalize` / `--clean` モード: 影響なし
- [x] 引数バリデーション: 影響なし
- [x] YAML単一クォートエスケープ: 影響なし
- [x] カテゴリ自動分類: 影響なし
- [x] カテゴリエントリカウント(WARN/ALERT): 影響なし
- [x] flock排他制御: 影響なし
- [x] ntfy/insight/pending_decision通知: 影響なし
- **変更: validate_ninja_id がtask files由来エージェントを検証しなくなる**
  → settings.yamlに全エージェント収録済み確認済み。機能的に等価。

## 期待After

| 計測対象 | Before | After | 改善率 |
|----------|--------|-------|--------|
| clean mode (10runs median) | ~55ms | ~10ms | -82% |
| normal mode (no ALERT) | ~70ms | ~25ms | -64% |
