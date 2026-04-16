# CoDD Spec: archive_completed.sh 高速化
**cmd**: cmd_1968 | **作成者**: hanzo | **作成日**: 2026-04-16

---

## 1. Before 実測値

| 計測 | 値 |
|------|-----|
| before (3回平均) | **1,073ms** (1062 / 1100 / 1062ms) |
| 計測コマンド | `time bash scripts/archive_completed.sh 3` |
| 測定環境 | WSL2 NTFS (queue/reports 30件, queue/shogun_to_karo.yaml 21 cmds) |

注記: cmd_1951プロファイリングの52ms は `--help` (エラー退場パス) の誤測定。実 baseline は **~1,073ms**。

---

## 2. ボトルネック分析

| # | 処理 | 計測値 | 問題 |
|---|------|--------|------|
| 1 | `archive_cmds` 21x sed ループ | **134ms** | flock内で `grep -n` + 21回の `sed -n "${s},${e}p"` + 21x `grep -m1 status` + 21x `grep -m1 cmd_id` = 計105プロセス起動 |
| 2 | `grep -q "source: deploy_preflight"` x19 | **104ms** | `archive_reports` ループ内で review_gate.done 存在チェック後、存在するファイル (19件) を1件ずつ grep |
| 3 | `sync_stk_status_from_archive` Python | **113ms** | Python起動(28ms) + `os.listdir(1923件)`(13ms) + `yaml.safe_load(STK)`(36ms) + ループ |
| 4 | `trim_stk_old_entries` Python | **84ms** | Python起動(28ms) + `yaml.safe_load(STK)`(36ms) — STKを別途再度ロード |
| 5 | `trim_cmd_chronicle` Python | **33ms** | noop でも Python起動(28ms) + chronicle読込(5ms) を強制実行 |
| 6 | gawk task files (10件) | **24ms** | `archive_reports` 内で毎回gawk実行 |
| 7 | gawk report cache (cold, 30件) | **74ms** | ファイル数変化でキャッシュミス頻発 |

---

## 3. リファクタ方針

### 方針A: `archive_cmds` sed ループ → 単一 awk パスに置換 (−100ms)

**現状**:
```bash
mapfile -t starts < <(grep -nE '...' "$QUEUE_FILE" | cut -d: -f1)
for i in "${!starts[@]}"; do
    entry="$(sed -n "${s},${e}p" "$QUEUE_FILE")"  # 21回ファイル読込
    status_val=$(printf '%s\n' "$entry" | grep -m1 '^ *status:' | sed ...)
    cmd_id=$(printf '%s\n' "$entry" | grep -m1 -E '...' | sed ...)
done
```

**改善後**:
```bash
# 単一 awk パスで cmd_id|status|entry_text を出力 → bash がTSV処理
awk '...' "$QUEUE_FILE" > "$TMP/entries.tsv"
while IFS='|' read -r cmd_id status_val; do ...
done < "$TMP/entries.tsv"
```

awk は ファイルを1回読み込んでエントリ境界を自分で追跡。sed 21回 → gawk 1回。

### 方針B: `grep -q deploy_preflight` → バッチ事前スキャン (−90ms)

**現状**: ループ内で1件ずつ `grep -q "source: deploy_preflight" gate_file`

**改善後**: ループ前に一括スキャン:
```bash
# review_gate.done が存在する cmd を1プロセスで全スキャン
declare -A _deploy_preflight_cmds=()
while IFS= read -r gate_path; do
    cmd_id="${gate_path#*/gates/}"; cmd_id="${cmd_id%/review_gate.done}"
    _deploy_preflight_cmds["$cmd_id"]=1
done < <(grep -rl "source: deploy_preflight" \
    "$PROJECT_DIR/queue/gates" --include="review_gate.done" 2>/dev/null)
```

### 方針C: `sync_stk` + `trim_stk_old` → 単一 Python 呼び出しに統合 (−64ms)

**現状**: 2回の Python サブプロセス = 2x Python起動 + 2x yaml.safe_load(STK)

**改善後**: 1回の Python サブプロセスが両方の処理を実行 = 1x Python起動 + 1x yaml.safe_load(STK)

### 方針D: `trim_cmd_chronicle` 早期リターン (−20ms)

**現状**: noop でも必ず Python 起動

**改善後**: awk で 30日超エントリの有無を事前チェック (awk ~10ms << Python起動28ms):
```bash
local cutoff_mmdd
cutoff_mmdd=$(date -d '30 days ago' '+%m-%d')
if ! awk -v co="$cutoff_mmdd" '/^\| cmd_/{...date comparison...}' "$CHRONICLE_FILE" 2>/dev/null | grep -q .; then
    echo "[chronicle-trim] noop: no old entries (early exit)"; return 0
fi
```

---

## 4. 機能不変量 (変えてはいけないもの)

1. `archive_cmds`: done/cancelled/absorbed cmds を archive/cmds/ に退避し QUEUE_FILE から除去
2. `archive_reports`: review_gate.done がない報告はアーカイブしない (安全弁)
3. `archive.done` フラグ: CMD_ID 指定時に必ず生成
4. yaml.dump 禁止: STK 書込みは stk_remove_cmd_blocks (awk) のみ
5. flock: STK・chronicle・dashboard の排他書込みは維持

---

## 5. 改善予測

| 最適化 | 予測削減 |
|--------|---------|
| A: archive_cmds sed→awk | −100ms |
| B: deploy_preflight バッチ | −90ms |
| C: sync_stk+trim_stk 統合 | −64ms |
| D: chronicle 早期リターン | −20ms |
| **合計** | **−274ms** |

**予測 after**: 1073 − 274 ≈ **799ms** (−26%)
