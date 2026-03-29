#!/usr/bin/env bash
# ============================================================
# archive_completed.sh
# 完了cmdと古い戦果をアーカイブし、ファイルを軽量化する
# 家老がcmd完了判定後に呼び出す
#
# Usage: bash scripts/archive_completed.sh [keep_results] [cmd_id]
#   keep_results: ダッシュボードに残す戦果数（デフォルト: 3）
#   cmd_id: 指定時にqueue/gates/{cmd_id}/archive.doneフラグを出力
# ============================================================
set -euo pipefail

# tmpファイルの後始末
TMP=$(mktemp -d)
export TMP  # GP-080: PythonのENVIRON参照用
cleanup() { rm -rf "$TMP" /tmp/stk_active_$$.yaml /tmp/dash_karo_trim_$$.md /tmp/lord_conv_trim_$$.yaml; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck disable=SC1091
source "$PROJECT_DIR/scripts/lib/field_get.sh"

QUEUE_FILE="$PROJECT_DIR/queue/shogun_to_karo.yaml"
CHANGELOG_FILE="$PROJECT_DIR/queue/completed_changelog.yaml"
ARCHIVE_DIR="$PROJECT_DIR/queue/archive"
ARCHIVE_CMD_DIR="$ARCHIVE_DIR/cmds"
DASHBOARD="$PROJECT_DIR/dashboard.md"
DASH_ARCHIVE="$ARCHIVE_DIR/dashboard_archive.md"
REPORTS_DIR="$PROJECT_DIR/queue/reports"
ARCHIVE_REPORT_DIR="$ARCHIVE_DIR/reports"
CHRONICLE_FILE="$PROJECT_DIR/context/cmd-chronicle.md"
CHRONICLE_ARCHIVE_DIR="$PROJECT_DIR/archive/cmd-chronicle"
PENDING_DECISIONS_FILE="$PROJECT_DIR/queue/pending_decisions.yaml"
PENDING_DECISIONS_ARCHIVE="$ARCHIVE_DIR/pending_decisions_archive.yaml"
usage_error() {
    echo "Usage: archive_completed.sh [keep_results] [cmd_id]" >&2
    echo "  keep_results: 正の整数（省略時3）" >&2
    echo "  cmd_id: cmd_XXX形式（任意）" >&2
    echo "受け取った引数: $*" >&2
}

# 引数パース: $1がcmd_で始まる場合はCMD_IDとして扱う
if [[ "${1:-}" == cmd_* ]]; then
    CMD_ID="$1"
    KEEP_RESULTS=${2:-3}
else
    KEEP_RESULTS=${1:-3}
    CMD_ID=${2:-""}
fi

if [[ ! "$KEEP_RESULTS" =~ ^[0-9]+$ ]]; then
    echo "ERROR: keep_results は正の整数で指定せよ。" >&2
    usage_error "$@"
    exit 1
fi

if [ -n "$CMD_ID" ] && [[ "$CMD_ID" != cmd_* ]]; then
    echo "ERROR: cmd_id は cmd_XXX 形式で指定せよ。" >&2
    usage_error "$@"
    exit 1
fi

mkdir -p "$ARCHIVE_DIR"
mkdir -p "$ARCHIVE_CMD_DIR"
mkdir -p "$ARCHIVE_REPORT_DIR"

# postcondition用グローバル変数（archive_cmdsが設定）
_POSTCOND_COMPLETED=0
_POSTCOND_ARCHIVED=0

# ============================================================
# 0.5 CMD年代記への追記
# ============================================================
get_report_summary_for_cmd() {
    local cmd_id="$1"
    python3 - "$REPORTS_DIR" "$cmd_id" <<'PY'
import glob
import os
import sys
import yaml

report_dir, cmd_id = sys.argv[1:3]

patterns = [
    os.path.join(report_dir, f"*_report_{cmd_id}.yaml"),
    os.path.join(report_dir, "subtask_*.yaml"),
]

def normalize(value):
    if value is None:
        return ""
    text = str(value).replace("\r", " ").replace("\n", " ").strip()
    return " ".join(text.split())

for pattern in patterns:
    for path in sorted(glob.glob(pattern)):
        try:
            with open(path, encoding="utf-8") as f:
                data = yaml.safe_load(f) or {}
        except Exception:
            continue
        if not isinstance(data, dict):
            continue
        parent_cmd = normalize(data.get("parent_cmd"))
        if parent_cmd and parent_cmd != cmd_id:
            continue
        nested_report = data.get("report") if isinstance(data.get("report"), dict) else {}
        nested_result = data.get("result") if isinstance(data.get("result"), dict) else {}
        for candidate in (data.get("summary"), nested_report.get("summary"), nested_result.get("summary")):
            text = normalize(candidate)
            if text and text != "|":
                print(text[:30])
                sys.exit(0)

print("")
PY
}

sync_chronicle_entry() {
    local cmd_id="$1"
    local entry="$2"

    local title project key_result
    title=$(printf '%s\n' "$entry" | grep -m1 '^ *purpose:' | sed 's/^ *purpose: *//; s/^"//; s/"$//')
    if [ -z "$title" ]; then
        title=$(printf '%s\n' "$entry" | grep -m1 '^ *title:' | sed 's/^ *title: *//; s/^"//; s/"$//')
    fi
    project=$(printf '%s\n' "$entry" | grep -m1 '^ *project:' | sed 's/^ *project: *//; s/^"//; s/"$//')
    key_result=$(get_report_summary_for_cmd "$cmd_id")

    local date_mm_dd year_month
    date_mm_dd="$(date '+%m-%d')"
    year_month="$(date '+%Y-%m')"

    (
        flock -w 10 200 || { echo "[chronicle] WARN: flock timeout on chronicle" >&2; return 1; }

        python3 - "$CHRONICLE_FILE" "$cmd_id" "$title" "$project" "$date_mm_dd" "$key_result" "$year_month" <<'PY'
import os
import sys

chronicle_path, cmd_id, title, project, date_mm_dd, key_result, year_month = sys.argv[1:8]
today = __import__("datetime").datetime.now().strftime("%Y-%m-%d")

def norm(value, fallback="—"):
    value = (value or "").strip()
    return value if value else fallback

def blankish(value):
    return value.strip() in {"", "—"}

if not os.path.exists(chronicle_path):
    with open(chronicle_path, "w", encoding="utf-8") as f:
        f.write(f"# CMD年代記\n<!-- last_updated: {today} -->\n")

with open(chronicle_path, encoding="utf-8") as f:
    lines = f.read().splitlines()

if not lines:
    lines = ["# CMD年代記", f"<!-- last_updated: {today} -->"]
elif len(lines) == 1:
    lines.append(f"<!-- last_updated: {today} -->")

if not lines[1].startswith("<!-- last_updated: "):
    lines.insert(1, f"<!-- last_updated: {today} -->")

row_idx = next((i for i, line in enumerate(lines) if line.startswith(f"| {cmd_id} |")), None)
action = "noop"

if row_idx is not None:
    parts = [part.strip() for part in lines[row_idx].split("|")[1:-1]]
    while len(parts) < 5:
        parts.append("")
    if blankish(parts[1]) and title.strip():
        parts[1] = title.strip()
        action = "updated"
    if blankish(parts[4]) and key_result.strip():
        parts[4] = key_result.strip()
        action = "updated"
    if blankish(parts[2]):
        parts[2] = norm(project)
        action = "updated" if action == "noop" else action
    if blankish(parts[3]):
        parts[3] = norm(date_mm_dd)
        action = "updated" if action == "noop" else action
    lines[row_idx] = f"| {parts[0] or cmd_id} | {norm(parts[1])} | {norm(parts[2])} | {norm(parts[3])} | {norm(parts[4])} |"
else:
    month_idx = next((i for i, line in enumerate(lines) if line == f"## {year_month}"), None)
    if month_idx is None:
        if lines and lines[-1] != "":
            lines.append("")
        lines.extend([
            f"## {year_month}",
            "",
            "| cmd | title | project | date | key_result |",
            "|-----|-------|---------|------|------------|",
        ])
    lines.append(f"| {cmd_id} | {norm(title)} | {norm(project)} | {norm(date_mm_dd)} | {norm(key_result)} |")
    action = "appended"

lines[1] = f"<!-- last_updated: {today} -->"

with open(chronicle_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

print(action)
PY
    ) 200>"/tmp/mas-chronicle.lock"

    echo "[chronicle] synced: $cmd_id"
}

archive_pending_decisions_for_cmd() {
    local cmd_id="$1"
    [ -f "$PENDING_DECISIONS_FILE" ] || return 0
    mkdir -p "$(dirname "$PENDING_DECISIONS_ARCHIVE")"

    local archived_count
    archived_count=$(
        (
            flock -w 10 200 || { echo "[pending_decisions] WARN: flock timeout on pending_decisions" >&2; exit 1; }
            flock -w 10 201 || { echo "[pending_decisions] WARN: flock timeout on pending_decisions_archive" >&2; exit 1; }

            python3 - "$PENDING_DECISIONS_FILE" "$PENDING_DECISIONS_ARCHIVE" "$cmd_id" <<'PY'
import os
import sys
import tempfile
import yaml

pending_path, archive_path, cmd_id = sys.argv[1:4]

def load_yaml(path):
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f) or {}

def write_yaml(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2, sort_keys=False)
        os.replace(tmp_path, path)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise

def build_doc(decisions):
    total = len(decisions)
    resolved = sum(1 for d in decisions if isinstance(d, dict) and d.get("status") == "resolved")
    pending = total - resolved
    return {"summary": {"total": total, "resolved": resolved, "pending": pending}, "decisions": decisions}

pending_data = load_yaml(pending_path)
decisions = pending_data.get("decisions") or []
matched = []
kept = []
for decision in decisions:
    if isinstance(decision, dict) and str(decision.get("resolved_by", "")).strip() == cmd_id and str(decision.get("status", "")).strip() == "resolved":
        matched.append(decision)
    else:
        kept.append(decision)

if not matched:
    print(0)
    sys.exit(0)

archive_data = load_yaml(archive_path)
archive_decisions = archive_data.get("decisions") or []
existing_ids = {d.get("id") for d in archive_decisions if isinstance(d, dict)}
for decision in matched:
    if decision.get("id") not in existing_ids:
        archive_decisions.append(decision)

write_yaml(pending_path, build_doc(kept))
write_yaml(archive_path, build_doc(archive_decisions))
print(len(matched))
PY
        ) 200>"/tmp/mas-pending-decisions.lock" 201>"/tmp/mas-pending-decisions-archive.lock"
    )

    if [ "${archived_count:-0}" -gt 0 ]; then
        echo "[pending_decisions] archived=$archived_count cmd=$cmd_id"
    else
        echo "[pending_decisions] none for $cmd_id"
    fi
}

# ============================================================
# 0.9 STK dict形式status同期+アーカイブ退避
#   1. archive/cmds/ + 完了報告 から完了cmd_idを収集
#   2. STK内delegated→doneに更新
#   3. done/cancelled/absorbed エントリをarchive/cmds/に退避しSTKから除去
# ============================================================
sync_stk_status_from_archive() {
    [ -f "$QUEUE_FILE" ] || return 0

    local result
    result=$(
        (
            flock -w 10 200 || { echo "[stk-sync] WARN: flock timeout" >&2; echo "0 0"; exit 1; }

            python3 - "$QUEUE_FILE" "$ARCHIVE_CMD_DIR" "$REPORTS_DIR" "$ARCHIVE_REPORT_DIR" <<'PY'
import glob
import os
import sys
import tempfile
from datetime import datetime

import yaml

stk_path, archive_cmd_dir, reports_dir, archive_report_dir = sys.argv[1:5]
SAFE_STATUSES = {"pending", "in_progress", "acknowledged", "assigned"}
DONE_STATUSES = {"done", "cancelled", "absorbed"}

# === Phase 1: 完了cmd_idを3ソースから収集 ===

completed_ids = set()

# Source 1: archive/cmds/ のファイル名
if os.path.isdir(archive_cmd_dir):
    for fname in os.listdir(archive_cmd_dir):
        if fname.startswith("cmd_") and fname.endswith(".yaml"):
            parts = fname.split("_")
            if len(parts) >= 2:
                completed_ids.add(f"{parts[0]}_{parts[1]}")

# Source 2: 現行報告 (status: done/completed) — GP-080: TSVキャッシュから読取り
# 旧: yaml.safe_load×97ファイル(457ms)
# 新: gawk生成TSV 1回読取り(<1ms)
cache_path = os.path.join(os.environ.get("TMP", "/tmp"), "report_fields_cache.tsv")
if os.path.isfile(cache_path):
    with open(cache_path, encoding="utf-8") as cf:
        for line in cf:
            parts = line.strip().split("|", 2)
            if len(parts) < 3:
                continue
            fname, status, parent = parts
            if status in ("done", "completed", "complete", "success"):
                if parent.startswith("cmd_"):
                    cid = "_".join(parent.split("_")[:2])
                    completed_ids.add(cid)

# Source 3: アーカイブ済み報告 — GP-077: スキップ
# archive/reportsの全量yaml.safe_load(2827件, 11.7秒)は冗長。
# Source 1(archive/cmds/ファイル名)で完了cmd_idは十分カバー済み。
# check_reports_dir(archive_report_dir)  # GP-077: disabled for performance

# === Phase 2: STK読み込み+status同期+退避 ===

with open(stk_path, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

cmds = data.get("commands")
if not isinstance(cmds, dict):
    print("0 0")
    sys.exit(0)

date_stamp = datetime.now().strftime("%Y%m%d")
synced = 0
archived = 0
keep = {}

for cmd_id, entry in cmds.items():
    if not isinstance(entry, dict):
        keep[cmd_id] = entry
        continue

    status = str(entry.get("status", "")).strip()

    # 安全弁: pending/in_progressは無条件で残す
    if status in SAFE_STATUSES:
        keep[cmd_id] = entry
        continue

    # delegated → done 同期
    if status == "delegated" and cmd_id in completed_ids:
        entry["status"] = "done"
        status = "done"
        synced += 1

    # done/cancelled/absorbed → archive/cmds/に退避
    if status in DONE_STATUSES:
        archive_path = os.path.join(archive_cmd_dir, f"{cmd_id}_{status}_{date_stamp}.yaml")
        if not os.path.exists(archive_path):
            os.makedirs(archive_cmd_dir, exist_ok=True)
            with open(archive_path, "w", encoding="utf-8") as f:
                yaml.dump({"commands": {cmd_id: entry}}, f,
                          default_flow_style=False, allow_unicode=True,
                          indent=2, sort_keys=False)
        archived += 1
        continue

    keep[cmd_id] = entry

# STK書き戻し（keepのみ）
if archived > 0:
    trimmed_data = {"commands": keep}
    fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(stk_path), suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            yaml.dump(trimmed_data, f, default_flow_style=False,
                      allow_unicode=True, indent=2, sort_keys=False)
        os.replace(tmp_path, stk_path)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise

print(f"{synced} {archived}")
PY
        ) 200>"/tmp/mas-stk.lock"
    )

    local synced archived
    synced=$(echo "$result" | awk '{print $1}')
    archived=$(echo "$result" | awk '{print $2}')
    echo "[stk-sync] delegated→done: ${synced:-0}, archived: ${archived:-0}"
}

# ============================================================
# 1. shogun_to_karo.yaml — 完了cmdをアーカイブに退避
# ============================================================
archive_cmds() {
    [ -f "$QUEUE_FILE" ] || return 0

    local tmp_active="/tmp/stk_active_$$.yaml"
    local archived=0 kept=0
    local date_stamp
    date_stamp="$(date '+%Y%m%d')"

    echo "commands:" > "$tmp_active"
    # エントリ境界を行番号で特定（リスト形式 + マッピング形式の両対応）
    local -a starts
    mapfile -t starts < <(grep -nE '^ *- id: cmd_|^  cmd_[0-9a-z_]+:' "$QUEUE_FILE" | cut -d: -f1)

    if [ ${#starts[@]} -eq 0 ]; then
        # 空振り検出: エントリ境界が0件でも完了ステータスが存在するならパターン不一致
        local pre_check
        pre_check=$(awk '/^ *status: *(completed|cancelled|absorbed|halted|superseded|done)/{c++} END{print c+0}' "$QUEUE_FILE")
        if [ "$pre_check" -gt 0 ]; then
            echo "[archive] WARN: $pre_check completed cmds found but 0 archived — grep pattern mismatch?" >&2
        fi
        _POSTCOND_COMPLETED=$pre_check
        echo "[archive] cmds: no entries found"
        rm -f "$tmp_active"
        return 0
    fi

    local total_lines
    total_lines=$(wc -l < "$QUEUE_FILE")

    for i in "${!starts[@]}"; do
        local s=${starts[$i]}
        local e
        if [ $((i + 1)) -lt ${#starts[@]} ]; then
            e=$(( ${starts[$((i + 1))]} - 1 ))
        else
            e=$total_lines
        fi

        local entry
        entry="$(sed -n "${s},${e}p" "$QUEUE_FILE")"

        # statusフィールドを取得（L070対策: field_getでインデント変動に追従）
        local status_val
        local entry_tmp="/tmp/stk_entry_${$}_${i}.yaml"
        printf '%s\n' "$entry" > "$entry_tmp"
        status_val=$(FIELD_GET_NO_LOG=1 field_get "$entry_tmp" "status" "" 2>/dev/null | tr -d '[:space:]')
        rm -f "$entry_tmp"

        # cmd_idを取得（退避先ファイル名に利用。リスト形式 + マッピング形式の両対応）
        local cmd_id
        cmd_id=$(printf '%s\n' "$entry" \
            | grep -m1 -E '^ *- id: cmd_|^  cmd_[0-9a-z_]+:' \
            | sed -E 's/^ *- id: *//; s/^[[:space:]]*(cmd_[0-9a-z_]+):.*/\1/')

        # status欠損時のみ、completed_changelog照合でcompleted扱いにする。
        # 完全一致(anchor)で cmd_51 が cmd_515 に誤マッチしないようにする。
        if [ -z "$status_val" ] && [ -n "$cmd_id" ] && [ -f "$CHANGELOG_FILE" ]; then
            local cmd_id_re
            cmd_id_re=$(printf '%s' "$cmd_id" | sed 's/[][(){}.^$*+?|\\-]/\\&/g')
            if grep -Eq "^[[:space:]]*(-[[:space:]]*)?(id|cmd_id):[[:space:]]*${cmd_id_re}[[:space:]]*$" "$CHANGELOG_FILE"; then
                status_val="completed"
            fi
        fi

        if [[ "$status_val" =~ ^(completed|cancelled|absorbed|halted|superseded|done) ]]; then
            local archive_status="${BASH_REMATCH[1]}"
            if [ -n "$cmd_id" ]; then
                local cmd_archive_file="$ARCHIVE_CMD_DIR/${cmd_id}_${archive_status}_${date_stamp}.yaml"
                {
                    echo "commands:"
                    printf '%s\n' "$entry"
                } > "$cmd_archive_file"
                archive_pending_decisions_for_cmd "$cmd_id" || true
                sync_chronicle_entry "$cmd_id" "$entry" || true
            else
                echo "[archive] WARN: failed to parse cmd_id at lines ${s}-${e}" >&2
            fi

            ((archived++)) || true
        else
            printf '%s\n' "$entry" >> "$tmp_active"
            ((kept++)) || true
        fi
    done

    # 空振り検出: 完了ステータスのcmdが存在するのにarchived=0の場合WARN
    local completed_count
    completed_count=$(awk '/^ *status: *(completed|cancelled|absorbed|halted|superseded|done)/{c++} END{print c+0}' "$QUEUE_FILE")
    # postcondition用グローバル変数を設定
    _POSTCOND_COMPLETED=$completed_count
    _POSTCOND_ARCHIVED=$archived

    if [ "$completed_count" -gt 0 ] && [ "$archived" -eq 0 ]; then
        echo "[archive] WARN: $completed_count completed cmds found but 0 archived — grep pattern mismatch?" >&2
    fi

    if [ "$archived" -gt 0 ]; then
        # flockでYAMLファイルへの書き込みを排他制御
        (
            flock -w 10 200 || { echo "[archive] WARN: flock timeout on QUEUE_FILE"; return 1; }
            # S06修正: mv前にtmpファイル存在確認
            [ -f "$tmp_active" ] || { echo "[archive] FATAL: tmp_active not found: $tmp_active" >&2; exit 1; }
            mv "$tmp_active" "$QUEUE_FILE" || { echo "[archive] FATAL: mv failed: $tmp_active → $QUEUE_FILE" >&2; exit 1; }
        ) 200>"/tmp/mas-stk.lock"
        echo "[archive] cmds: archived=$archived kept=$kept"
    else
        rm -f "$tmp_active"
        echo "[archive] cmds: nothing to archive (kept=$kept)"
    fi

}

# ============================================================
# 1.5 queue/reports — 完了報告をアーカイブ
#   - 新形式: {ninja}_report_{cmd}.yaml
#   - 旧形式: {ninja}_report.yaml（後方互換）
# ============================================================
archive_reports() {
    [ -d "$REPORTS_DIR" ] || return 0

    local archived=0 kept=0 skipped=0 junk=0
    local date_stamp
    date_stamp="$(date '+%Y%m%d')"

    # --- 非YAMLファイルの掃除 (忍者の成果物混入防止) ---
    shopt -s nullglob
    local all_files=("$REPORTS_DIR"/*)
    shopt -u nullglob
    for f in "${all_files[@]}"; do
        [ -f "$f" ] || continue
        case "$f" in *.yaml) continue ;; esac
        mv "$f" "$ARCHIVE_REPORT_DIR/" || { echo "[archive] WARN: mv failed: $f" >&2; continue; }
        junk=$((junk + 1))
    done

    # --- YAML報告のアーカイブ ---
    shopt -s nullglob
    local report_files=("$REPORTS_DIR"/*_report*.yaml "$REPORTS_DIR"/subtask_*.yaml)
    shopt -u nullglob

    if [ ${#report_files[@]} -eq 0 ] && [ "$junk" -eq 0 ]; then
        echo "[archive] reports: none"
        return 0
    fi

    # GP-080: 共有キャッシュTSVから連想配列ロード (gawk実行は Main で1回のみ)
    declare -A _rpt_status _rpt_parent
    if [ -f "$_REPORT_CACHE" ]; then
        while IFS='|' read -r _rf _rs _rp; do
            _rpt_status["$_rf"]="$_rs"
            _rpt_parent["$_rf"]="$_rp"
        done < "$_REPORT_CACHE"
    fi

    # task files キャッシュ (L667-669のfield_get置換)
    declare -A _task_parent _task_status
    local _task_glob=("$PROJECT_DIR/queue/tasks"/*.yaml)
    if [ -f "${_task_glob[0]}" ]; then
        while IFS='|' read -r _tf _ts _tp; do
            _task_status["$_tf"]="$_ts"
            _task_parent["$_tf"]="$_tp"
        done < <(gawk '
            BEGINFILE {
                fname = FILENAME; sub(/.*\//, "", fname)
                st = ""; pc = ""
            }
            /status:/ && !/^#/ { st = $0; sub(/.*status: */, "", st); gsub(/["'"'"'"'"'"'"'"'"'\t ]/, "", st) }
            /parent_cmd:/ { pc = $0; sub(/.*parent_cmd: */, "", pc); gsub(/["'"'"'"'"'"'"'"'"'\t ]/, "", pc) }
            ENDFILE { print fname "|" st "|" pc }
        ' "${_task_glob[@]}" 2>/dev/null)
    fi

    for report_file in "${report_files[@]}"; do
        [ -f "$report_file" ] || continue

        local status_val parent_cmd base_name target_name dest_path
        local _bname; _bname="$(basename "$report_file")"
        status_val="${_rpt_status[$_bname]}"
        parent_cmd="${_rpt_parent[$_bname]}"

        # cmd指定時は該当cmdの報告のみを対象化
        if [ -n "$CMD_ID" ] && [ -n "$parent_cmd" ] && [ "$parent_cmd" != "$CMD_ID" ]; then
            skipped=$((skipped + 1))
            continue
        fi

        # CMD_ID指定パス: status=pending → スキップ（生成直後のテンプレート保護）
        if [ -n "$CMD_ID" ] && [ "$status_val" = "pending" ]; then
            echo "[archive] WARNING: Skipping pending report: $(basename "$report_file")"
            kept=$((kept + 1))
            continue
        fi

        # review_gate.done未存在 → 家老レビュー未完了なのでアーカイブをスキップ
        local check_cmd_for_review=""
        if [ -n "$CMD_ID" ]; then
            check_cmd_for_review="$CMD_ID"
        elif [ -n "$parent_cmd" ]; then
            check_cmd_for_review="$parent_cmd"
        fi
        if [ -n "$check_cmd_for_review" ]; then
            # 修練cmd例外: training/cycle/selfimprovementはGATEフロー外のためreview_gate.doneチェック不要
            local is_training_cmd=false
            case "$check_cmd_for_review" in
                cmd_training_*|cmd_cycle_*|cmd_selfimprovement_*) is_training_cmd=true ;;
            esac
            if [ "$is_training_cmd" = "false" ]; then
                local review_gate_file="$PROJECT_DIR/queue/gates/${check_cmd_for_review}/review_gate.done"
                if [ ! -f "$review_gate_file" ]; then
                    echo "[archive] SKIP: review_gate.done not found for ${check_cmd_for_review}: $(basename "$report_file")"
                    kept=$((kept + 1))
                    continue
                fi
            fi
        fi

        # CMD_ID指定なし(sweep mode): 完了報告のみ。CMD_ID指定あり: status不問で全archive
        if [ -z "$CMD_ID" ]; then
            local status_lower="${status_val,,}"
            case "$status_lower" in
                done|completed|complete|success|failed|pass|fail|blocked|waived|stop_for) ;;
                *)
                    kept=$((kept + 1))
                    continue
                    ;;
            esac

            # sweep mode安全弁: 親cmdが進行中なら報告を退避しない
            # 取得失敗(空文字)は安全側(keep)へ倒す。
            if [ -n "$parent_cmd" ]; then
                local cmd_status
                if [ ! -f "$QUEUE_FILE" ]; then
                    kept=$((kept + 1))
                    continue
                fi

                # exact matchでparent_cmdブロックのstatusを抽出（部分一致防止）
                cmd_status=$(
                    awk -v target="$parent_cmd" '
                        BEGIN { in_target = 0 }
                        /^[[:space:]]*-[[:space:]]id:[[:space:]]*cmd_/ {
                            id = $0
                            sub(/^[[:space:]]*-[[:space:]]id:[[:space:]]*/, "", id)
                            gsub(/[[:space:]]+$/, "", id)
                            if (in_target == 1) { exit }
                            in_target = (id == target)
                            next
                        }
                        in_target == 1 && /^[[:space:]]*status:[[:space:]]*/ {
                            st = $0
                            sub(/^[[:space:]]*status:[[:space:]]*/, "", st)
                            gsub(/[[:space:]]+$/, "", st)
                            print st
                            exit
                        }
                    ' "$QUEUE_FILE"
                )

                case "$cmd_status" in
                    pending|delegated|in_progress|acknowledged)
                        kept=$((kept + 1))
                        continue
                        ;;
                    "")
                        # parent cmd not in QUEUE_FILE — check child tasks
                        local has_active_child=false
                        local task_file_check
                        for task_file_check in "$PROJECT_DIR/queue/tasks"/*.yaml; do
                            [ -f "$task_file_check" ] || continue
                            local t_parent t_status
                            local _tbname; _tbname="$(basename "$task_file_check")"
                            t_parent="${_task_parent[$_tbname]}"
                            [ "$t_parent" = "$parent_cmd" ] || continue
                            t_status="${_task_status[$_tbname]}"
                            case "$t_status" in
                                done|completed|complete|success|failed|"") ;;
                                *)
                                    has_active_child=true
                                    break
                                    ;;
                            esac
                        done
                        if $has_active_child; then
                            kept=$((kept + 1))
                            continue
                        fi
                        # No active children — safe to archive
                        ;;
                esac
            fi

            # archive.doneチェック: GATE未完了cmdの報告をsweepから保護
            # archive.doneはcmd_complete_gate.shのGATE CLEAR最終ステップで作成される。
            # これがない=GATEの全処理未完了→報告退避は早すぎる(cmd_1519-1522レース事故の再発防止)
            if [ -n "$parent_cmd" ]; then
                # 修練cmd例外: training/cycle/selfimprovementはGATEフロー外のためarchive.doneチェック不要
                local skip_archive_done=false
                case "$parent_cmd" in
                    cmd_training_*|cmd_cycle_*|cmd_selfimprovement_*) skip_archive_done=true ;;
                esac
                if [ "$skip_archive_done" = "false" ]; then
                    local archive_done_flag="$PROJECT_DIR/queue/gates/${parent_cmd}/archive.done"
                    if [ ! -f "$archive_done_flag" ]; then
                        echo "[archive] SKIP(sweep): archive.done not found for ${parent_cmd}: $(basename "$report_file")"
                        kept=$((kept + 1))
                        continue
                    fi
                fi
            fi
        fi

        base_name="$(basename "$report_file")"
        target_name="$base_name"

        # 旧形式はアーカイブ時にcmdサフィックスを付与（識別性向上）
        if [[ "$base_name" =~ _report\.yaml$ ]] && [[ "$parent_cmd" == cmd_* ]]; then
            target_name="${base_name%.yaml}_${parent_cmd}.yaml"
        fi

        dest_path="$ARCHIVE_REPORT_DIR/${target_name%.yaml}_${date_stamp}.yaml"
        if [ -e "$dest_path" ]; then
            dest_path="$ARCHIVE_REPORT_DIR/${target_name%.yaml}_$(date '+%H%M%S').yaml"
        fi

        mv "$report_file" "$dest_path" || { echo "[archive] WARN: mv failed: $report_file → $dest_path" >&2; continue; }
        archived=$((archived + 1))
    done

    echo "[archive] reports: archived=$archived kept=$kept skipped=$skipped junk=$junk"
}

# ============================================================
# 1.6 dashboard.md KARO_SECTION 最新更新 — 古い更新をアーカイブ（直近3件を残す）
# ============================================================
archive_karo_section() {
    [ -f "$DASHBOARD" ] || return 0

    local karo_archive="$ARCHIVE_DIR/dashboard_karo_archive.md"
    local update_start update_end
    update_start=$(grep -n '^## 最新更新' "$DASHBOARD" | head -1 | cut -d: -f1 || true)

    if [[ -z "$update_start" ]]; then
        echo "[archive] karo_section: '## 最新更新' not found, skip"
        return 0
    fi

    # 次の ## ヘッダ直前までを最新更新セクションとみなす
    update_end=$(awk -v s="$update_start" '
        NR > s && /^## / { print NR - 1; found=1; exit }
        END { if (!found) print NR }
    ' "$DASHBOARD")

    local -a update_lines
    mapfile -t update_lines < <(
        awk -v s="$update_start" -v e="$update_end" '
            NR > s && NR <= e && /^- \*\*cmd_[^*]*\*\*:/ { print NR }
        ' "$DASHBOARD"
    )
    local total_updates=${#update_lines[@]}

    if [[ $total_updates -le 3 ]]; then
        echo "[archive] karo_updates: $total_updates entries <= 3, skip"
        return 0
    fi

    local -a delete_lines=("${update_lines[@]:3}")
    local archived_count=${#delete_lines[@]}
    local delete_csv
    delete_csv=$(IFS=,; echo "${delete_lines[*]}")

    {
        echo ""
        echo "# Archived KARO updates $(date '+%Y-%m-%d %H:%M')"
        for line_no in "${delete_lines[@]}"; do
            sed -n "${line_no}p" "$DASHBOARD"
        done
    } >> "$karo_archive"

    # dashboard.mdから退避済み行を削除（flock排他）
    (
        flock -w 10 200 || { echo "[archive] WARN: flock timeout on DASHBOARD"; return 1; }
        awk -v csv="$delete_csv" '
            BEGIN {
                n = split(csv, arr, ",")
                for (i = 1; i <= n; i++) {
                    if (arr[i] != "") del[arr[i]] = 1
                }
            }
            !(NR in del) { print }
        ' "$DASHBOARD" > "/tmp/dash_karo_trim_$$.md"
        mv "/tmp/dash_karo_trim_$$.md" "$DASHBOARD" || { echo "[archive] FATAL: mv failed: karo trim → $DASHBOARD" >&2; exit 1; }
    ) 200>"/tmp/mas-dashboard.lock"

    echo "[archive] karo_updates: archived=$archived_count kept=3"
}

# ============================================================
# 2. dashboard.md — 古い戦果をアーカイブ（直近N件を残す）
# ============================================================
archive_dashboard() {
    [ -f "$DASHBOARD" ] || return 0

    # 戦果セクションのデータ行を取得（ヘッダ・区切り行を除外）
    local -a result_lines
    mapfile -t result_lines < <(grep -n '^| [0-9]' "$DASHBOARD" | cut -d: -f1)

    local total=${#result_lines[@]}
    if [ "$total" -le "$KEEP_RESULTS" ]; then
        echo "[archive] dashboard: $total results <= keep=$KEEP_RESULTS, skip"
        return 0
    fi

    # KEEP_RESULTS件目の次のデータ行からアーカイブ対象
    local archive_first_line=${result_lines[$KEEP_RESULTS]}
    local last_data_line=${result_lines[$((total - 1))]}
    local archived_count=$((total - KEEP_RESULTS))

    # アーカイブに追記（データ行のみ）
    {
        echo ""
        echo "# Archived $(date '+%Y-%m-%d %H:%M')"
        sed -n "${archive_first_line},${last_data_line}p" "$DASHBOARD"
    } >> "$DASH_ARCHIVE"

    # ダッシュボードからアーカイブ済みデータ行を削除（flock排他）
    (
        flock -w 10 200 || { echo "[archive] WARN: flock timeout on DASHBOARD"; return 1; }
        # S07修正: mktempで安全なtmp生成 + sed成功確認後にmv
        local tmp_dash
        tmp_dash=$(mktemp /tmp/dash_trim_XXXXXXXX.md)
        if ! sed "${archive_first_line},${last_data_line}d" "$DASHBOARD" > "$tmp_dash"; then
            echo "[archive] FATAL: sed failed for dashboard trim" >&2
            rm -f "$tmp_dash"
            exit 1
        fi
        mv "$tmp_dash" "$DASHBOARD" || { echo "[archive] FATAL: mv failed: $tmp_dash → $DASHBOARD" >&2; exit 1; }
    ) 200>"/tmp/mas-dashboard.lock"

    echo "[archive] dashboard: archived=$archived_count kept=$KEEP_RESULTS"
}

# ============================================================
# 2.5 cmd-chronicle.md — 30日超のエントリをarchive/cmd-chronicle/YYYY-MM.mdに退避
# ============================================================
trim_cmd_chronicle() {
    [ -f "$CHRONICLE_FILE" ] || return 0

    local cutoff_date
    cutoff_date=$(date -d '30 days ago' '+%Y-%m-%d')

    (
        flock -w 10 200 || { echo "[chronicle-trim] WARN: flock timeout" >&2; return 1; }

        python3 - "$CHRONICLE_FILE" "$CHRONICLE_ARCHIVE_DIR" "$cutoff_date" <<'PY'
import os
import sys
from datetime import datetime

chronicle_path, archive_dir, cutoff_str = sys.argv[1:4]
cutoff = datetime.strptime(cutoff_str, "%Y-%m-%d")

with open(chronicle_path, encoding="utf-8") as f:
    lines = f.read().splitlines()

# Phase 1: Parse into file_header + sections
file_header = []
sections = []  # [(ym, header_lines, data_rows)]
current_ym = None
section_header = []
section_data = []

for line in lines:
    if line.startswith("## "):
        if current_ym is not None:
            sections.append((current_ym, list(section_header), list(section_data)))
        current_ym = line[3:].strip()
        section_header = [line]
        section_data = []
    elif current_ym is None:
        file_header.append(line)
    elif line.startswith("| cmd_"):
        section_data.append(line)
    else:
        if not section_data:
            section_header.append(line)
        else:
            section_data.append(line)

if current_ym is not None:
    sections.append((current_ym, list(section_header), list(section_data)))

# Phase 2: Separate keep vs archive
to_archive = {}  # ym -> [rows]
kept_sections = []
total_archived = 0

for ym, header, data in sections:
    year = ym[:4]
    keep = []
    for row in data:
        if not row.startswith("| cmd_"):
            keep.append(row)
            continue
        parts = [p.strip() for p in row.split("|")]
        date_str = parts[4] if len(parts) > 4 else ""
        try:
            full_date = datetime.strptime(f"{year}-{date_str}", "%Y-%m-%d")
        except (ValueError, IndexError):
            keep.append(row)
            continue
        if full_date < cutoff:
            target_ym = full_date.strftime("%Y-%m")
            to_archive.setdefault(target_ym, []).append(row)
            total_archived += 1
        else:
            keep.append(row)
    has_data = any(r.startswith("| cmd_") for r in keep)
    if has_data:
        kept_sections.append((ym, header, keep))

if total_archived == 0:
    print("noop")
    sys.exit(0)

# Phase 3: Write archive files
os.makedirs(archive_dir, exist_ok=True)
for ym, rows in to_archive.items():
    archive_path = os.path.join(archive_dir, f"{ym}.md")
    if os.path.exists(archive_path):
        with open(archive_path, encoding="utf-8") as f:
            existing = f.read().splitlines()
        existing_ids = set()
        for el in existing:
            if el.startswith("| cmd_"):
                existing_ids.add(el.split("|")[1].strip())
        new_rows = [r for r in rows if r.split("|")[1].strip() not in existing_ids]
        if new_rows:
            existing.extend(new_rows)
            with open(archive_path, "w", encoding="utf-8") as f:
                f.write("\n".join(existing) + "\n")
    else:
        content = [
            f"# CMD年代記 Archive: {ym}",
            "",
            "| cmd | title | project | date | key_result |",
            "|-----|-------|---------|------|------------|",
        ]
        content.extend(rows)
        with open(archive_path, "w", encoding="utf-8") as f:
            f.write("\n".join(content) + "\n")

# Phase 4: Rebuild chronicle
output = list(file_header)
for ym, header, data in kept_sections:
    output.extend(header)
    output.extend(data)

today = datetime.now().strftime("%Y-%m-%d")
for idx, line in enumerate(output):
    if line.startswith("<!-- last_updated:"):
        output[idx] = f"<!-- last_updated: {today} -->"
        break

with open(chronicle_path, "w", encoding="utf-8") as f:
    f.write("\n".join(output) + "\n")

print(f"trimmed: archived={total_archived}")
PY
    ) 200>"/tmp/mas-chronicle.lock"

    echo "[chronicle-trim] done"
}

# ============================================================
# 2.7 shogun_to_karo.yaml — 完了済み+30日超のエントリを退避 (cmd_1120_b)
# ============================================================
STK_ARCHIVE_DIR="$PROJECT_DIR/archive/shogun_to_karo"

trim_stk_old_entries() {
    [ -f "$QUEUE_FILE" ] || return 0

    (
        flock -w 10 200 || { echo "[stk-trim] WARN: flock timeout on QUEUE_FILE" >&2; return 1; }

        python3 - "$QUEUE_FILE" "$STK_ARCHIVE_DIR" <<'PY'
import os
import sys
import tempfile
from datetime import datetime, timedelta, timezone

import yaml

stk_path, archive_dir = sys.argv[1:3]
CUTOFF_DAYS = 30
ARCHIVE_STATUSES = {"done", "absorbed", "cancelled"}
# pending/in_progress は絶対に退避しない
KEEP_STATUSES = {"pending", "in_progress", "acknowledged", "assigned"}

now = datetime.now(timezone(timedelta(hours=9)))
cutoff = now - timedelta(days=CUTOFF_DAYS)

with open(stk_path, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

cmds = data.get("commands")
if not isinstance(cmds, dict):
    print("noop: no commands dict")
    sys.exit(0)

keep = {}
to_archive = {}  # ym -> {cmd_id: entry}
archived_count = 0

for cmd_id, entry in cmds.items():
    if not isinstance(entry, dict):
        keep[cmd_id] = entry
        continue

    status = str(entry.get("status", "")).strip().lower()

    # 安全弁: pending/in_progressは無条件で残す
    if status in KEEP_STATUSES:
        keep[cmd_id] = entry
        continue

    if status not in ARCHIVE_STATUSES:
        keep[cmd_id] = entry
        continue

    # timestamp解析 (複数フォーマット対応)
    ts_raw = entry.get("timestamp") or entry.get("delegated_at") or ""
    ts_str = str(ts_raw).strip().strip("'\"")
    entry_dt = None
    for fmt in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S+09:00",
                "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            entry_dt = datetime.strptime(ts_str, fmt)
            if entry_dt.tzinfo is None:
                entry_dt = entry_dt.replace(tzinfo=timezone(timedelta(hours=9)))
            break
        except ValueError:
            continue

    if entry_dt is None:
        # timestamp解析失敗 → 安全側(keep)
        keep[cmd_id] = entry
        continue

    if entry_dt >= cutoff:
        # 30日以内 → keep
        keep[cmd_id] = entry
        continue

    # 退避対象
    ym = entry_dt.strftime("%Y-%m")
    to_archive.setdefault(ym, {})[cmd_id] = entry
    archived_count += 1

if archived_count == 0:
    print("noop: no entries to archive")
    sys.exit(0)

# Phase 2: 退避先に書き出し (月別 YYYY-MM.yaml)
os.makedirs(archive_dir, exist_ok=True)
for ym, entries in to_archive.items():
    archive_path = os.path.join(archive_dir, f"{ym}.yaml")
    if os.path.exists(archive_path):
        with open(archive_path, encoding="utf-8") as f:
            existing = yaml.safe_load(f) or {}
        existing_cmds = existing.get("commands") or {}
    else:
        existing_cmds = {}

    existing_cmds.update(entries)
    archive_data = {"commands": existing_cmds}

    fd, tmp_path = tempfile.mkstemp(dir=archive_dir, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            yaml.dump(archive_data, f, default_flow_style=False,
                      allow_unicode=True, indent=2, sort_keys=False)
        os.replace(tmp_path, archive_path)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise

# Phase 3: 元ファイルを更新 (keep のみ残す)
trimmed_data = {"commands": keep}
fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(stk_path), suffix=".tmp")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        yaml.dump(trimmed_data, f, default_flow_style=False,
                  allow_unicode=True, indent=2, sort_keys=False)
    os.replace(tmp_path, stk_path)
except Exception:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    raise

print(f"trimmed: archived={archived_count} kept={len(keep)}")
PY
    ) 200>"/tmp/mas-stk.lock"

    echo "[stk-trim] done"
}

# ============================================================
# Main
# ============================================================
echo "[archive_completed] $(date '+%Y-%m-%d %H:%M:%S') start"

# GP-080: 報告ファイルのstatus/parent_cmdを一括抽出 (共有キャッシュ)
# sync_stk Source 2 + archive_reports L582-583 の両方が消費
_REPORT_CACHE="$TMP/report_fields_cache.tsv"
if compgen -G "$REPORTS_DIR/*_report*.yaml" > /dev/null 2>&1 || compgen -G "$REPORTS_DIR/subtask_*.yaml" > /dev/null 2>&1; then
    gawk '
        BEGINFILE {
            fname = FILENAME; sub(/.*\//, "", fname)
            st = ""; pc = ""
        }
        /^status:/ { st = $0; sub(/.*status: */, "", st); gsub(/["'"'"'\t ]/, "", st) }
        /^parent_cmd:/ { pc = $0; sub(/.*parent_cmd: */, "", pc); gsub(/["'"'"'\t ]/, "", pc) }
        ENDFILE { print fname "|" st "|" pc }
    ' "$REPORTS_DIR"/*.yaml 2>/dev/null > "$_REPORT_CACHE"
fi

archive_cmds
sync_stk_status_from_archive
trim_cmd_chronicle
trim_stk_old_entries
archive_reports
archive_karo_section

# ============================================================
# postcondition: archive_cmds結果の事後検証
# L074対策: 算術式は$((var+1))形式。postcondition失敗でもスクリプトを止めない。
# ============================================================
postcondition_archive() {
    local input=$_POSTCOND_COMPLETED
    local output=$_POSTCOND_ARCHIVED

    if [ "$input" -eq 0 ]; then
        echo "[archive] postcondition: OK (no completed cmds)"
        return 0
    fi

    if [ "$output" -eq 0 ]; then
        echo "[archive] ALERT: completed存在するがアーカイブ0件 (expected=$input actual=0)" >&2
        bash "$PROJECT_DIR/scripts/ntfy_batch.sh" "[archive] INFO: completed存在するがアーカイブ0件 (expected=${input} actual=0)" || true
        return 0
    fi

    if [ "$output" -lt "$input" ]; then
        echo "[archive] WARN: アーカイブ不完全 (expected=$input actual=$output)" >&2
        return 0
    fi

    echo "[archive] postcondition: OK (archived=$output/$input)"
}
postcondition_archive || true

archive_dashboard

# cmd_579: 会話保持はJSONL専用 `scripts/conversation_retention.sh` に移管。
# archive_completed.sh から旧YAMLローテーションは撤去する。

# archive.doneフラグ出力（CMD_ID指定時のみ）
if [ -n "$CMD_ID" ]; then
    mkdir -p "$PROJECT_DIR/queue/gates/${CMD_ID}"
    touch "$PROJECT_DIR/queue/gates/${CMD_ID}/archive.done"
    echo "[archive_completed] gate flag: queue/gates/${CMD_ID}/archive.done"
fi

echo "[archive_completed] done"
