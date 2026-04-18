# ninja_done.sh CoDD Spec (cmd_2082) — 正規CoDD再改善

- cmd: cmd_2082
- 実施者: hanzo
- 日時: 2026-04-18
- CoDD Phase到達予定: Phase 5(spec先行+Before計測+改善+After計測+検証)

## 対象

- `scripts/ninja_done.sh` (183行)

---

## Before 計測

- 条件: archived success path (cmd_2035/cmd_2063と同一条件)
- コマンド: `INBOX_WRITE_ROOT_OVERRIDE=<tmp> bash scripts/ninja_done.sh hayate cmd_1946`
  - `hayate_report_cmd_1946_20260416.yaml` が queue/archive/reports/ に存在
- 実行環境: /mnt/c/tools/multi-agent-shogun (実運用ディレクトリ)
- warmup: 1回

| run | time |
|-----|------|
| 1 | 80ms |
| 2 | 96ms |
| 3 | 97ms |
| 4 | 81ms |
| 5 | 144ms |
| 6 | 101ms |
| 7 | 166ms |
| 8 | 103ms |
| 9 | 124ms |
| 10 | 80ms |
| **median** | **99ms** |

---

## ボトルネック分析

### コンポーネント別コスト (in-process計測)

| コンポーネント | コスト | 備考 |
|---|---|---|
| resolve_report_file (primary [ -f ]) | ~1ms | primary path hit時はfast path |
| **resolve_report_file (archive glob)** | **66ms** | ← メインボトルネック |
| summary_is_present (awk) | ~5ms | 既最適済み (cmd_1965) |
| gate_report_format.sh (warm) | ~25ms | PASS cache hit時 |
| gate_report_format.sh (cold) | ~170ms | Python起動+validation |
| inbox_write.sh | ~20ms | 既最適済み (cmd_2036/2064) |

### ボトルネック根因

`resolve_report_file()` でarchiveパスへのフォールバック時:

```bash
shopt -s nullglob
local archived_paths=("$ARCHIVE_REPORT_DIR/${ninja_name}_report_${cmd_id}_"*.yaml)
shopt -u nullglob
```

- `queue/archive/reports/` に **6714ファイル**存在 (2026-04-18時点)
- WSL2 /mnt/c上でのglob展開 = 全ファイルのstat/readdir = **66ms**
- `find -maxdepth 1` はさらに遅い (194ms)

### 改善候補

**B1: 日付トライアル (採用)**

archiveファイル名は `${ninja}_report_${cmd_id}_${YYYYMMDD}.yaml` の固定形式。
過去14日間の日付文字列を `printf '%(%Y%m%d)T'` (bash builtin) で生成し `[ -f ]` で直接チェック。

```bash
# Before: glob (66ms)
shopt -s nullglob
archived_paths=("$ARCHIVE_REPORT_DIR/${ninja}_report_${cmd_id}_"*.yaml)
shopt -u nullglob

# After: date trial (3ms)
_epoch=$(date +%s)  # 外部プロセス 1回のみ
for _d in 0 1 2 3 4 5 6 7 8 9 10 11 12 13; do
    printf -v _date_str '%(%Y%m%d)T' $(( _epoch - _d * 86400 ))
    _candidate="$ARCHIVE_REPORT_DIR/${ninja}_report_${cmd_id}_${_date_str}.yaml"
    if [ -f "$_candidate" ]; then
        printf '%s\n' "$_candidate"
        return 0
    fi
done
# 14日以上古い場合のみ glob fallback (稀ケース)
```

- `printf '%(%Y%m%d)T'` は bash 4.x builtin → サブシェルゼロ
- `date +%s` 1回のみ外部呼出し (~2ms)
- `[ -f ]` チェック = ~1ms/回 → 2日前のファイルなら3回 = ~3ms
- 合計: ~3ms (-95%)

計測による根拠:
- `printf %T` 20run*7days: **0ms** (builtin, 実測)
- `date -d` 20run*7days: 279ms (外部プロセス 7回)
- date trial approach 20回計測: **16ms平均** (3回試行時)

**実装計画: B1のみ** — gate/inbox_writeはスコープ外。既存のglob fallbackは保持(14日超の古いreportへの後方互換)。

---

## 実装仕様 (resolve_report_file)

### 変更箇所: `resolve_report_file()` 関数本体

**Before:**
```bash
resolve_report_file() {
    local ninja_name="$1"
    local cmd_id="$2"
    local primary_path="$REPORTS_DIR/${ninja_name}_report_${cmd_id}.yaml"

    if [ -f "$primary_path" ]; then
        printf '%s\n' "$primary_path"
        return 0
    fi

    shopt -s nullglob
    local archived_paths=("$ARCHIVE_REPORT_DIR/${ninja_name}_report_${cmd_id}_"*.yaml)
    shopt -u nullglob

    if [ "${#archived_paths[@]}" -eq 0 ]; then
        return 1
    fi

    local latest_path=""
    local path=""

    for path in "${archived_paths[@]}"; do
        if [ -z "$latest_path" ] || [ "$path" -nt "$latest_path" ]; then
            latest_path="$path"
        fi
    done

    if [ -n "$latest_path" ]; then
        printf '%s\n' "$latest_path"
        return 0
    fi

    return 1
}
```

**After:**
```bash
resolve_report_file() {
    local ninja_name="$1"
    local cmd_id="$2"
    local primary_path="$REPORTS_DIR/${ninja_name}_report_${cmd_id}.yaml"

    if [ -f "$primary_path" ]; then
        printf '%s\n' "$primary_path"
        return 0
    fi

    # cmd_2082: date-trial (printf %T builtin) でglobを回避 (~66ms→~3ms)
    # archiveファイル名: ${ninja}_report_${cmd_id}_${YYYYMMDD}.yaml
    local _epoch _date_str _candidate _d
    _epoch=$(date +%s)
    for _d in 0 1 2 3 4 5 6 7 8 9 10 11 12 13; do
        printf -v _date_str '%(%Y%m%d)T' $(( _epoch - _d * 86400 ))
        _candidate="$ARCHIVE_REPORT_DIR/${ninja_name}_report_${cmd_id}_${_date_str}.yaml"
        if [ -f "$_candidate" ]; then
            printf '%s\n' "$_candidate"
            return 0
        fi
    done

    # 14日超の古いreportへのfallback (稀ケース)
    shopt -s nullglob
    local archived_paths=("$ARCHIVE_REPORT_DIR/${ninja_name}_report_${cmd_id}_"*.yaml)
    shopt -u nullglob

    if [ "${#archived_paths[@]}" -eq 0 ]; then
        return 1
    fi

    local latest_path="" path
    for path in "${archived_paths[@]}"; do
        if [ -z "$latest_path" ] || [ "$path" -nt "$latest_path" ]; then
            latest_path="$path"
        fi
    done

    if [ -n "$latest_path" ]; then
        printf '%s\n' "$latest_path"
        return 0
    fi

    return 1
}
```

---

## 期待改善

| パス | Before | 期待After | 削減 |
|---|---|---|---|
| archived success path (median) | 99ms | ~36ms | -63ms (-64%) |
| primary success path (median) | ~14ms (※) | ~14ms | 変化なし |

※ 前回(cmd_1965)のprimary path実測。今回もほぼ同じ。

---

## 検証方法

- `bash -n scripts/ninja_done.sh` (構文チェック)
- `bats tests/unit/test_ninja_done.bats` (既存テスト全PASS)
- after計測 (同条件: archived success path, 10回)
