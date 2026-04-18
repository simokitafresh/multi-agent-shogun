# CoDD Spec: dashboard_auto_section.sh 正規CoDD再改善 (cmd_2081)

## Meta
- date: 2026-04-18
- author: tobisaru
- parent_cmd: cmd_2081
- target: `scripts/dashboard_auto_section.sh` (1216行)
- predecessor: 前回spec省略版 (2.8s → 307ms, GP-cmd_1981等)

---

## Before 計測 (warm path median 5回, /mnt/c/tools/multi-agent-shogun)

| パス | 測定値 (5回) | median |
|------|-------------|--------|
| warm (キャッシュ全ヒット) | 350,300,190,180,200ms | **200ms** |

> 注: cold runでCI status check (ci_status_check.sh) がネットワーク待ちになる場合あり (32s outlier観測)。
> warm path (TTLキャッシュ全ヒット) のmedian 200msをbefore基準とする。

---

## ボトルネック分析

### プロファイリング手法

1. PS4タイムスタンプ差分 (`PS4='$(date +%s%3N)'`) でホットスポット特定
2. スクリプト内に `mark()` 関数で段階的タイムスタンプ挿入し各ステージを独立計測
3. 各ボトルネック候補を bash -c でシェルから直接計測

### Top 3 ボトルネック

| 順位 | 箇所 | 行番号範囲 | 計測コスト | 根本原因 |
|------|------|-----------|-----------|---------|
| 1 | task files awk (ninja cmd mapping) | L243–L272 | **64ms** | 6忍者タスクYAMLを毎回gawk読込。WSL2 NTFS上の6ファイルI/O+bashループ |
| 2 | source agent_config.sh | L122 | **28ms** (init全体) | 毎プロセス起動でawk+settings.yaml読込 (NTFS I/O)。include guardは同プロセス内のみ有効 |
| 3 | archive glob展開 | L417 | **26ms** | 2047ファイルのglob配列構築 (`cmd_*.yaml`)。キャッシュヒット時も毎回実行 |

追加: mktemp×6呼出し **14ms** (個別mktemp 4本+後続2本)

### 計測詳細

```
Before median: 200ms (warm path)
│
├─ Stage1: init + source agent_config + cksum: 28ms
│   └─ agent_config.sh源: awk parses settings.yaml → 20ms (NTFS I/O)
│       cksum subprocess: 5ms
│
├─ Stage2: mktemp ×6: 14ms
│   └─ /mnt/c/ 上の /tmp はWSL2経由 → 個別呼出しコスト蓄積
│
├─ Stage3: stat 4ファイル (heavy key): 10ms
│
├─ Stage4: archive glob 2047ファイル: 26ms
│   └─ `_arch_files=(…/cmd_*.yaml)` がキャッシュヒット時も毎回実行
│       2047ファイルのmtime stat付き列挙 → bash配列構築
│       修正方針: ディレクトリmtime 1回stat → キャッシュキー代替 (~0ms)
│
├─ Stage5: archive cache読込: 6ms
│
├─ Stage6: gawk model precompute: 4ms (OSキャッシュ効き小)
│
├─ Stage7: STK pipeline parse (awk on 1106行YAML): 15ms
│
├─ Stage8: task files awk (最大ボトルネック): 64ms  ← FIX対象#1
│   └─ 6忍者 × YAML read + bash while loop処理
│       stat 6ファイル mtime → キャッシュチェックで50ms節約可能
│       キャッシュミス時: awk実行 + キャッシュ保存
│       キャッシュヒット時: stat 6ファイル (~12ms) + cat (~2ms) = 14ms
│       節約: 64ms → 14ms ≈ -50ms
│
├─ Stage9: snapshot grep: 9ms
│
├─ Stage10: CI + CTX cache読込: 5ms
│
└─ Stage11: TITLE_MAP build (heavy cache hit): 7ms
   Total: ~200ms
```

---

## 改善計画

### Fix #1: task files mapping MTIMEキャッシュ (期待 -50ms)

**対象**: L243–L272 (task files awk)

**Before**:
```bash
for _tnn in $ALL_NINJAS; do
    _tf="$TASKS_DIR/${_tnn}.yaml"
    [[ -f "$_tf" ]] && _task_files_arr+=("$_tf")
done
if [[ ${#_task_files_arr[@]} -gt 0 ]]; then
    while IFS='|' read -r _n _pcmd; do ...
    done < <(awk '...' "${_task_files_arr[@]}")
fi
```

**After**:
```bash
# Build task files array
for _tnn in $ALL_NINJAS; do
    _tf="$TASKS_DIR/${_tnn}.yaml"
    [[ -f "$_tf" ]] && _task_files_arr+=("$_tf")
done
_TASK_MAP_CACHE="/tmp/das_task_map_${_proj_hash}.txt"
_TASK_MAP_KEY="/tmp/das_task_map_${_proj_hash}.key"
_task_map_mtime=$(stat -c "%Y" "${_task_files_arr[@]}" 2>/dev/null | tr '\n' ':') || true
_task_map_cached_key=$(cat "$_TASK_MAP_KEY" 2>/dev/null || echo "")
if [[ "$_task_map_mtime" == "$_task_map_cached_key" ]] && [[ -s "$_TASK_MAP_CACHE" ]]; then
    # Cache hit: read from /tmp (fast)
    _task_map_src="$_TASK_MAP_CACHE"
else
    # Cache miss: awk + save
    awk '...' "${_task_files_arr[@]}" > "$_TASK_MAP_CACHE" 2>/dev/null || true
    echo "$_task_map_mtime" > "$_TASK_MAP_KEY"
    _task_map_src="$_TASK_MAP_CACHE"
fi
while IFS='|' read -r _n _pcmd; do ... done < "$_task_map_src"
```

期待コスト: miss時=awk+stat (~70ms, 初回/変更時), hit時=stat+cat (~14ms)
→ warm path削減: 64ms → 14ms = **-50ms**

---

### Fix #2: archive glob → directory mtime (期待 -22ms)

**対象**: L415–L465 (archive scan / cache check)

**Before**:
```bash
shopt -s nullglob
_arch_files=("$ARCHIVE_CMD_DIR"/cmd_*.yaml)   # ← 2047ファイルglob (26ms!)
shopt -u nullglob
_arch_count=${#_arch_files[@]}
_cached_arch_count=$(cat "$_ARCH_COUNT_CACHE" ...)
if [[ "$_arch_count" == "$_cached_arch_count" ]] && cache_exists; then
    # cache hit
else
    gawk ... "${_arch_files[@]}"
    echo "$_arch_count" > "$_ARCH_COUNT_CACHE"
fi
```

**After**:
```bash
_ARCH_MTIME_CACHE="/tmp/dashboard_arch_mtime_${_proj_hash}.txt"
_arch_dir_mtime=$(stat -c "%Y" "$ARCHIVE_CMD_DIR" 2>/dev/null || echo 0)  # ~0ms
_cached_arch_mtime=$(cat "$_ARCH_MTIME_CACHE" 2>/dev/null || echo "")
if [[ "$_arch_dir_mtime" == "$_cached_arch_mtime" ]] && [[ -f "$_ARCH_TITLES_CACHE" ]] && [[ -f "$_ARCH_CFC_CACHE" ]]; then
    # Cache hit: no glob needed
    cat "$_ARCH_TITLES_CACHE" >> "$TMP_TITLES"
    cat "$_ARCH_CFC_CACHE" > "$_CFC_CACHE"
else
    # Cache miss: glob + gawk + save
    shopt -s nullglob
    _arch_files=("$ARCHIVE_CMD_DIR"/cmd_*.yaml)
    shopt -u nullglob
    if (( ${#_arch_files[@]} > 0 )); then
        gawk ... "${_arch_files[@]}" 2>/dev/null
        echo "$_arch_dir_mtime" > "$_ARCH_MTIME_CACHE"
    fi
fi
```

期待コスト: hit時=stat (~2ms), miss時=stat+glob+gawk (初回/新cmd時)
→ warm path削減: 26ms → 2ms = **-24ms**

---

### Fix #3: mktemp×6 → mktemp -d (期待 -10ms)

**対象**: L111–L117 (初期tmpfile作成) + L409–L483 (後続tmp)

**Before**:
```bash
TMPFILE=$(mktemp)
TMP_METRICS=$(mktemp)
TMP_PIPELINE=$(mktemp)
TMP_RESULTS=$(mktemp)
TMP_TITLES=$(mktemp)
TMP_RECENT=$(mktemp)
trap 'rm -f "$TMPFILE" ...' EXIT
# ... later ...
_TMP_CTX_WARN=$(mktemp)
_CFC_CACHE=$(mktemp)
# ... later ...
_TMP_CI_STATUS=$(mktemp)
```

**After**:
```bash
_TMP_DIR=$(mktemp -d)   # 1回だけ
TMPFILE="$_TMP_DIR/main"
TMP_METRICS="$_TMP_DIR/metrics"
TMP_PIPELINE="$_TMP_DIR/pipeline"
TMP_RESULTS="$_TMP_DIR/results"
TMP_TITLES="$_TMP_DIR/titles"
TMP_RECENT="$_TMP_DIR/recent"
trap 'rm -rf "$_TMP_DIR"' EXIT
# ... later ...
_TMP_CTX_WARN="$_TMP_DIR/ctx_warn"
_CFC_CACHE="$_TMP_DIR/cfc"
# ... later ...
_TMP_CI_STATUS="$_TMP_DIR/ci_status"
```

期待コスト: 1回 mktemp -d → ~2ms (vs 6回×2ms = 12ms個別)
→ warm path削減: 14ms → 2ms = **-12ms**

---

## 期待効果

| Fix | Before | After | 削減 |
|-----|--------|-------|------|
| #1 task files cache | 64ms | 14ms | -50ms |
| #2 archive dir mtime | 26ms | 2ms | -24ms |
| #3 mktemp -d | 14ms | 2ms | -12ms |
| **合計** | **~104ms削減** | | |

**Predicted after**: 200ms - 104ms = **~96ms** (目標150ms達成)

---

## Regression防止

- Fix #1: タスクYAMLが更新された時点でキャッシュ無効化。stat mtimeが正確でないケースはキャッシュkey mismatch → awk再実行で自己修復
- Fix #2: アーカイブディレクトリmtimeはファイル追加時に更新される。WSL2/NTFSでも確認済み。削除は運用上発生しない
- Fix #3: 全tmpファイルが同一ディレクトリ内→ rm -rfで確実削除。trap EXIT継続

## Revert基準

- batsテストFAIL時はgit revertで即復帰
- after median > before median (200ms) の場合もrevert
