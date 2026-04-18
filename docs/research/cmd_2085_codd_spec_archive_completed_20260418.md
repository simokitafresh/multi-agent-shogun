# CoDD Spec: archive_completed.sh 正規CoDD再改善
**cmd**: cmd_2085 | **作成者**: kagemaru | **作成日**: 2026-04-18

---

## 1. Before 実測値

| 計測 | 値 |
|------|-----|
| before (5回 raw) | 1318 / 964 / 893 / 1091 / 1073ms |
| before (median 5回) | **1073ms** |
| 計測コマンド | `time bash scripts/archive_completed.sh 100` |
| 測定環境 | WSL2 NTFS `/mnt/c/...` (queue/reports 106件, shogun_to_karo.yaml 24 cmds, archive/cmds 2054件) |

---

## 2. ボトルネック分析

| # | 処理 | 計測値 | 問題 |
|---|------|--------|------|
| 1 | `archive_reports` gate_scan (while+[ -f ] ×82) | **400〜600ms** | 82 unique parent_cmds に対し WSL2 NTFS 個別 `[ -f ]` ×82 = ~7ms/件 × 82 = ~580ms |
| 2 | `sync_stk_status_from_archive` Python | **130ms** | Python起動(~30ms) + os.listdir(archive_cmd_dir 2054件)(15ms) + yaml.safe_load(STK 1013行)(~85ms) |
| 3 | `task_files` gawk (archive_reports内) | **43ms** | 7ファイルを毎回 gawk で処理。ファイル数・mtime変化時のみ必要な情報をキャッシュなし |
| 4 | `trim_cmd_chronicle` Python | **47ms** | gawk early return が false → Python起動(~30ms)+ファイル処理 |

プロファイリング詳細:
```
Phase 1 (REPORT_CACHE init):   11ms  (cache hit)
Phase 2 (archive_cmds gawk):   23ms
Phase 3 (sync_stk Python):    130ms
Phase 4 (chronicle gawk):      10ms  (has old entries → Python実行)
Phase 4 (chronicle Python):    47ms
Phase 5a (gate_scan while-f): 400ms
Phase 5b (task_files gawk):    43ms
Phase 5c (queue_cmd gawk):     12ms
合計 (プロファイリング):       676ms
```

---

## 3. リファクタ方針

### 方針A: gate_scan キャッシュ化 (−200〜400ms)

**現状**:
```bash
# _REPORT_CACHEの82 unique parent_cmdsに対し個別[ -f ]チェック
while IFS='|' read -r _rc_fname _rc_status _rc_parent; do
    [ "${_gate_status[$_rc_parent]+x}" = "x" ] && continue
    local _gc_g="$PROJECT_DIR/queue/gates/${_rc_parent}/review_gate.done"
    if [ -f "$_gc_g" ]; then  # ← WSL2 NTFS 個別stat = ~7ms/件
        _gate_status["$_rc_parent"]="ok"
    fi
done < "$_REPORT_CACHE"
```

**改善後**: _REPORT_CACHEと同様の「ファイル数ベースTTLキャッシュ」
```bash
# /tmpにgate_status TSVキャッシュ(ファイル数が変わらない限り有効)
_RPT_CACHE_SIZE=$(wc -l < "$_REPORT_CACHE" 2>/dev/null || echo "0")
_GATE_CACHE="/tmp/shogun_gate_status_${_RPT_HASH}.tsv"
_GATE_CACHE_SIZE="/tmp/shogun_gate_cache_size_${_RPT_HASH}"

_cached_gate_size=$(cat "$_GATE_CACHE_SIZE" 2>/dev/null || echo "-1")
if [[ "$_RPT_CACHE_SIZE" == "$_cached_gate_size" ]] && [[ -f "$_GATE_CACHE" ]]; then
    # ヒット: TSVから連想配列ロード (~5ms)
    while IFS='|' read -r _cmd _status; do
        _gate_status["$_cmd"]="$_status"
    done < "$_GATE_CACHE"
else
    # ミス: 既存の while+[ -f ] で計算後にキャッシュ保存
    # (同時にdeploy_preflight grep-lも実行)
    ... existing logic ...
    # 保存
    for k in "${!_gate_status[@]}"; do
        echo "$k|${_gate_status[$k]}"
    done > "$_GATE_CACHE"
    echo "$_RPT_CACHE_SIZE" > "$_GATE_CACHE_SIZE"
fi
```

**効果**: キャッシュヒット時に82件の[ -f ]チェック(400〜600ms) → TSVロード(5ms)
**注意**: report_cacheサイズ(=reportファイル数)が変わるとキャッシュ無効化 → ミス時はそのまま既存ロジックが走る

### 方針B: task_files gawk キャッシュ化 (−30〜40ms)

**現状**:
```bash
# archive_reports内で毎回gawkでtask filesを処理(7ファイル)
while IFS='|' read -r _tf _ts _tp; do ...
done < <(gawk '...' "${_task_glob[@]}" 2>/dev/null)
```

**改善後**: _REPORT_CACHEと同じパターン。task yamlファイル数が変化しない限りキャッシュ使用
```bash
_TASK_CACHE="/tmp/shogun_task_cache_${_RPT_HASH}.tsv"
_TASK_CACHE_COUNT="/tmp/shogun_task_cache_count_${_RPT_HASH}"
_task_count="${#_task_glob[@]}"
_cached_task_count=$(cat "$_TASK_CACHE_COUNT" 2>/dev/null || echo "-1")
if [[ "$_task_count" == "$_cached_task_count" ]] && [[ -f "$_TASK_CACHE" ]]; then
    cp "$_TASK_CACHE" "$TMP/task_cache.tsv"
else
    gawk '...' "${_task_glob[@]}" > "$TMP/task_cache.tsv"
    cp "$TMP/task_cache.tsv" "$_TASK_CACHE" 2>/dev/null || true
    echo "$_task_count" > "$_TASK_CACHE_COUNT" 2>/dev/null || true
fi
while IFS='|' read -r _tf _ts _tp; do ...
done < "$TMP/task_cache.tsv"
```

**効果**: キャッシュヒット時: gawk 43ms → cp 5ms (−38ms)

### 方針C: sync_stk completed_ids キャッシュ化 (−15〜100ms)

**現状**:
```bash
python3 - ... <<'PY'
# os.listdir(archive_cmd_dir) 2054件
if os.path.isdir(archive_cmd_dir):
    for fname in os.listdir(archive_cmd_dir):
        if fname.startswith("cmd_") and fname.endswith(".yaml"):
            ...
PY
```

**改善後**: archive/cmdsファイル数をキャッシュのキーに
```python
_ARCH_CACHE_COUNT="/tmp/shogun_arch_count_${_RPT_HASH}"
_ARCH_CACHE="/tmp/shogun_arch_ids_${_RPT_HASH}.txt"
```

Python内:
```python
import os
arch_count = len(os.listdir(archive_cmd_dir)) if os.path.isdir(archive_cmd_dir) else 0
cached_count_path = os.environ.get("_ARCH_CACHE_COUNT", "")
cached_ids_path = os.environ.get("_ARCH_CACHE", "")
cached_count = int(open(cached_count_path).read().strip()) if os.path.isfile(cached_count_path) else -1
if arch_count == cached_count and os.path.isfile(cached_ids_path):
    with open(cached_ids_path) as f:
        completed_ids = set(f.read().splitlines())
else:
    completed_ids = set()
    for fname in os.listdir(archive_cmd_dir):
        ...
    # save cache
```

**効果**: キャッシュヒット時: os.listdir(2054件, 15ms) → open(small file, 1ms)
ただしSTKの yaml.safe_load(85ms)は変わらないため、全体的な削減は限定的

**注意**: archive_cmdsは毎回のcmd完了で増加するため、キャッシュヒット率は低い → 方針A,Bより優先度低い

---

## 4. 機能不変量 (変えてはいけないもの)

1. `archive_cmds`: done/cancelled/absorbed cmds を archive/cmds/ に退避し QUEUE_FILE から除去
2. `archive_reports`: review_gate.done がない報告はアーカイブしない (安全弁)
3. `archive.done` フラグ: CMD_ID 指定時に必ず生成
4. yaml.dump 禁止: STK 書込みは stk_remove_cmd_blocks (awk) のみ
5. flock: STK・chronicle・dashboard の排他書込みは維持
6. _gate_status["cmd"] の判定ロジック: missing/placeholder/ok の3値は維持
7. キャッシュ無効化時は必ず既存ロジックにフォールバック

---

## 5. 改善予測

| 最適化 | 予測削減 (ヒット時) | 適用条件 |
|--------|--------------------|-|
| A: gate_scan キャッシュ | −370ms | report_cacheサイズ不変時 |
| B: task_files gawk キャッシュ | −38ms | task yamlファイル数不変時 |
| C: completed_ids キャッシュ | −10ms | archive/cmdsファイル数不変時 (ヒット率低) |
| **合計 (ヒット時)** | **−418ms** | |

**予測 after (median, ヒット時)**: 1073 − 418 ≈ **655ms** (−39%)
**予測 after (median, ミス時)**: ほぼ変化なし (既存ロジックにフォールバック)

注記: キャッシュはcmd完了ごとにreport_filesが追加されるため、archive_completed.sh実行の都度ヒット率が変動する。
現在の報告ファイル構成（106件）では、連続した実行でヒット率が高い。
