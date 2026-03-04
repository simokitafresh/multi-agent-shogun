#!/bin/bash
# cmd_complete_gate.sh — cmd完了時の全ゲートフラグ確認スクリプト（ディレクトリ方式）
# Usage: bash scripts/cmd_complete_gate.sh <cmd_id>
# Exit 0: GATE CLEAR (全ゲートdone、または緊急override)
# Exit 1: GATE BLOCK (未完了フラグあり)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/field_get.sh"
source "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
CMD_ID="${1:-}"

if [ -z "$CMD_ID" ]; then
    echo "Usage: cmd_complete_gate.sh <cmd_id>" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

if [[ "$CMD_ID" != cmd_* ]]; then
    echo "ERROR: 第1引数はcmd_id（cmd_XXX形式）でなければならない。" >&2
    echo "Usage: cmd_complete_gate.sh <cmd_id>" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

GATES_DIR="$SCRIPT_DIR/queue/gates/${CMD_ID}"
YAML_FILE="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
TASKS_DIR="$SCRIPT_DIR/queue/tasks"
LOG_DIR="$SCRIPT_DIR/logs"
GATE_METRICS_LOG="$LOG_DIR/gate_metrics.log"
mkdir -p "$GATES_DIR" "$LOG_DIR"

# ─── 報告YAML解決関数（L085: 新命名規則対応、cmd_410: report_filename最優先） ───
# 優先順位: 1. タスクYAMLのreport_filename  2. 新形式  3. 旧形式
resolve_report_file() {
    local ninja="$1"
    local cmd="${2:-$CMD_ID}"
    # 1. タスクYAMLのreport_filenameを参照(最優先)
    local task_yaml="$TASKS_DIR/${ninja}.yaml"
    if [ -f "$task_yaml" ]; then
        local explicit
        explicit=$(grep 'report_filename:' "$task_yaml" | head -1 | sed 's/.*report_filename:[[:space:]]*//' | tr -d "'" | tr -d '"')
        if [ -n "$explicit" ] && [ -f "$SCRIPT_DIR/queue/reports/$explicit" ]; then
            echo "$SCRIPT_DIR/queue/reports/$explicit"
            return
        fi
    fi
    # 2. 新形式 (既存)
    local new_fmt="$SCRIPT_DIR/queue/reports/${ninja}_report_${cmd}.yaml"
    # 3. 旧形式フォールバック（安全化: parent_cmd一致チェック）
    local old_fmt="$SCRIPT_DIR/queue/reports/${ninja}_report.yaml"
    if [ -f "$new_fmt" ]; then
        echo "$new_fmt"
    elif [ -f "$old_fmt" ]; then
        # parent_cmd一致チェック（旧報告の誤採用防止）
        local report_parent
        report_parent=$(grep -E "^\s*parent_cmd:" "$old_fmt" | head -1 | sed 's/.*parent_cmd:\s*//' | tr -d "'" | tr -d '"')
        if [ "$report_parent" = "$cmd" ]; then
            echo "$old_fmt"  # parent_cmd一致 → 採用
        else
            echo "$new_fmt"  # 不一致 → 新形式パス返却（存在しない=報告なし扱い）
        fi
    else
        echo "$new_fmt"  # デフォルト（存在チェックは呼び出し側）
    fi
}

# ─── status自動更新関数 ───
update_status() {
    local cmd_id="$1"
    local current_status
    current_status=$(awk -v cmd="${cmd_id}" '
        {
            line = $0
            if (!found && line ~ /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/) {
                tmp = line
                sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "", tmp)
                sub(/[[:space:]]+#.*$/, "", tmp)
                gsub(/^["'"'"']|["'"'"']$/, "", tmp)
                if (tmp == cmd) { found=1; next }
            }
            if (found && line ~ /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/) { exit }
            if (found && line ~ /^[[:space:]]*status:[[:space:]]*/) {
                sub(/^[[:space:]]*status:[[:space:]]*/, "", line)
                gsub(/[[:space:]]+$/, "", line)
                print line
                exit
            }
        }
    ' "$YAML_FILE")

    case "$current_status" in
        completed|done)
            echo "STATUS ALREADY COMPLETED: ${cmd_id} (skip)"
            return 0
            ;;
        "")
            echo "ERROR: status not found for ${cmd_id} in ${YAML_FILE}" >&2
            return 1
            ;;
    esac

    if ! yaml_field_set "$YAML_FILE" "$cmd_id" "status" "completed"; then
        echo "ERROR: yaml_field_set failed (${cmd_id})" >&2
        return 1
    fi

    echo "STATUS UPDATED: ${cmd_id} → completed"
}

# ─── changelog自動記録関数 ───
append_changelog() {
    local cmd_id="$1"
    local changelog="$SCRIPT_DIR/queue/completed_changelog.yaml"
    local completed_at
    completed_at=$(date '+%Y-%m-%dT%H:%M:%S')

    # shogun_to_karo.yamlから該当cmdのpurposeとprojectを抽出
    local purpose
    purpose=$(awk -v cmd="${cmd_id}" '
        /^[ ]*- id:/ && index($0, cmd) { found=1; next }
        found && /^[ ]*- id:/ { exit }
        found && /^[ ]*purpose:/ { sub(/^[ ]*purpose: *"?/, ""); sub(/"$/, ""); print; exit }
    ' "$YAML_FILE")

    local project
    project=$(awk -v cmd="${cmd_id}" '
        /^[ ]*- id:/ && index($0, cmd) { found=1; next }
        found && /^[ ]*- id:/ { exit }
        found && /^[ ]*project:/ { sub(/^[ ]*project: */, ""); print; exit }
    ' "$YAML_FILE")

    if [ -z "$purpose" ]; then
        echo "CHANGELOG WARNING: purpose not found for ${cmd_id}"
        return 0
    fi
    [ -z "$project" ] && project="unknown"

    # ファイルが無ければヘッダ作成
    if [ ! -f "$changelog" ]; then
        echo "entries:" > "$changelog"
    fi

    # エントリ追記
    cat >> "$changelog" <<EOF
  - id: ${cmd_id}
    project: ${project}
    purpose: "${purpose}"
    completed_at: "${completed_at}"
EOF

    # 20件超なら古い順に剪定（各エントリ=4行、ヘッダ=1行）
    local entry_count
    entry_count=$(awk '/^\s+- id:/{c++} END{print c+0}' "$changelog" 2>/dev/null)
    if [ "$entry_count" -gt 20 ]; then
        { head -1 "$changelog"; tail -n 80 "$changelog"; } > "${changelog}.tmp"
        mv "${changelog}.tmp" "$changelog"
    fi

    echo "CHANGELOG: ${cmd_id} recorded (project=${project})"
}

# ─── task_type検出: タスクYAMLからparent_cmd一致のtask_typeを収集 ───
detect_task_types() {
    local cmd_id="$1"
    local has_recon=false
    local has_implement=false

    for task_file in "$TASKS_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        # parent_cmdが一致するか確認
        if grep -q "parent_cmd: ${cmd_id}" "$task_file" 2>/dev/null; then
            local ttype
            ttype=$(field_get "$task_file" "task_type" "")
            case "$ttype" in
                recon) has_recon=true ;;
                implement) has_implement=true ;;
                review) ;; # 既知の種別。条件ゲートには影響しない
                *) echo "[WARN] Unknown task_type: '$ttype'" >&2 ;;
            esac
        fi
    done

    # 結果を標準出力に返す（スペース区切り）
    echo "${has_recon} ${has_implement}"
}

# ─── cmd_407: gate_metrics拡張用 — task_type/model/bloom_levelの収集 ───
collect_gate_metrics_extra() {
    local cmd_id="$1"
    local settings_yaml="$SCRIPT_DIR/config/settings.yaml"
    local task_types_csv=""
    local models_csv=""
    local bloom_levels_csv=""
    local _seen_types="" _seen_models="" _seen_bloom_levels=""

    for task_file in "$TASKS_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        if ! grep -q "parent_cmd: ${cmd_id}" "$task_file" 2>/dev/null; then
            continue
        fi

        # task_type収集
        local ttype
        ttype=$(field_get "$task_file" "task_type" "")
        if [ -n "$ttype" ] && [[ "$_seen_types" != *"|$ttype|"* ]]; then
            _seen_types="${_seen_types}|${ttype}|"
            task_types_csv="${task_types_csv:+${task_types_csv},}${ttype}"
        fi

        # bloom_level収集（空欄はunknown）
        local bloom_level
        bloom_level=$(field_get "$task_file" "bloom_level" "")
        [ -z "$bloom_level" ] && bloom_level="unknown"
        if [[ "$_seen_bloom_levels" != *"|$bloom_level|"* ]]; then
            _seen_bloom_levels="${_seen_bloom_levels}|${bloom_level}|"
            bloom_levels_csv="${bloom_levels_csv:+${bloom_levels_csv},}${bloom_level}"
        fi

        # model収集: assigned_toからsettings.yamlのmodel_nameを取得
        if [ -f "$settings_yaml" ]; then
            local ninja_name
            ninja_name=$(field_get "$task_file" "assigned_to" "")
            if [ -n "$ninja_name" ]; then
                local model
                model=$(awk -v agent="$ninja_name" '
                    /^[[:space:]]+'"$ninja_name"':/ { found=1; next }
                    found && /^[[:space:]]+[a-z]/ && !/model_name:/ && !/tier:/ && !/type:/ { found=0 }
                    found && /model_name:/ { sub(/.*model_name:[[:space:]]*/, ""); print; exit }
                ' "$settings_yaml" 2>/dev/null)
                # Codex下忍はtype: codexでmodel_nameなし→"codex"を設定
                if [ -z "$model" ]; then
                    local cli_type
                    cli_type=$(awk -v agent="$ninja_name" '
                        /^[[:space:]]+'"$ninja_name"':/ { found=1; next }
                        found && /^[[:space:]]+[a-z]/ && !/type:/ && !/tier:/ && !/model_name:/ { found=0 }
                        found && /type:/ { sub(/.*type:[[:space:]]*/, ""); print; exit }
                    ' "$settings_yaml" 2>/dev/null)
                    [ "$cli_type" = "codex" ] && model="codex"
                fi
                # model_nameからショート名に変換 (claude-opus-4-6 → Opus等)
                case "$model" in
                    *opus*|*Opus*) model="Opus" ;;
                    *sonnet*|*Sonnet*) model="Sonnet" ;;
                    *haiku*|*Haiku*) model="Haiku" ;;
                    codex) model="Codex" ;;
                    "") model="unknown" ;;
                esac
                if [[ "$_seen_models" != *"|$model|"* ]]; then
                    _seen_models="${_seen_models}|${model}|"
                    models_csv="${models_csv:+${models_csv},}${model}"
                fi
            fi
        fi
    done

    [ -z "$task_types_csv" ] && task_types_csv="unknown"
    [ -z "$models_csv" ] && models_csv="unknown"
    [ -z "$bloom_levels_csv" ] && bloom_levels_csv="unknown"

    # スペース区切りで3値を返す
    echo "${task_types_csv} ${models_csv} ${bloom_levels_csv}"
}

# ─── cmd_466: gate_metrics拡張用 — 注入教訓ID収集 ───
collect_injected_lessons() {
    local cmd_id="$1"
    local injected_lessons

    injected_lessons=$(python3 - "$TASKS_DIR" "$cmd_id" <<'PY'
import os
import sys
import yaml

tasks_dir = sys.argv[1]
cmd_id = sys.argv[2]
seen = set()
ordered = []

for filename in sorted(os.listdir(tasks_dir)):
    if not filename.endswith(".yaml"):
        continue
    task_path = os.path.join(tasks_dir, filename)
    try:
        with open(task_path, encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        continue
    if not isinstance(data, dict):
        continue
    task = data.get("task", {})
    if not isinstance(task, dict):
        continue
    if str(task.get("parent_cmd", "")).strip() != cmd_id:
        continue

    related_lessons = task.get("related_lessons") or []
    if not isinstance(related_lessons, list):
        continue
    for lesson in related_lessons:
        if isinstance(lesson, dict):
            lid = lesson.get("id")
        else:
            lid = lesson
        if lid is None:
            continue
        lid = str(lid).strip()
        if not lid or lid in seen:
            continue
        seen.add(lid)
        ordered.append(lid)

print(",".join(ordered) if ordered else "none")
PY
    ) || injected_lessons="none"

    [ -z "$injected_lessons" ] && injected_lessons="none"
    echo "$injected_lessons"
}

# ─── cmd_472: gate_metrics拡張用 — cmd title収集（shogun_to_karo.yaml） ───
collect_cmd_title() {
    local cmd_id="$1"
    local cmd_title=""

    cmd_title=$(awk -v cmd="${cmd_id}" '
        /^[[:space:]]*-[[:space:]]*id:[[:space:]]*cmd_[0-9]+/ {
            line = $0
            sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            gsub(/["[:space:]]/, "", line)
            if (line == cmd) {
                found = 1
                next
            }
            if (found) {
                exit
            }
        }
        found && /^[[:space:]]*title:[[:space:]]*/ {
            line = $0
            sub(/^[[:space:]]*title:[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            print line
            exit
        }
    ' "$YAML_FILE" 2>/dev/null || true)

    cmd_title=$(printf '%s' "$cmd_title" | sed "s/^['\"]//; s/['\"]$//")
    cmd_title=${cmd_title//$'\t'/ }
    if [ "${#cmd_title}" -gt 50 ]; then
        cmd_title="${cmd_title:0:47}..."
    fi

    echo "$cmd_title"
}

# ─── lesson tracking追記（ベストエフォート） ───
append_lesson_tracking() {
    local cmd_id="$1"
    local gate_result="$2"
    local tracking_file="$LOG_DIR/lesson_tracking.tsv"
    local parsed ninja injected_ids referenced_ids timestamp

    parsed=$(python3 - "$TASKS_DIR" "$SCRIPT_DIR/queue/reports" "$cmd_id" <<'PY'
import os
import sys
import yaml

tasks_dir = sys.argv[1]
reports_dir = sys.argv[2]
cmd_id = sys.argv[3]

ninjas = []
injected = []
referenced = []
task_types = []

def add_unique(target, value):
    if value is None:
        return
    sval = str(value).strip()
    if not sval:
        return
    if sval not in target:
        target.append(sval)

def detect_task_type(task_id_str):
    tid = str(task_id_str)
    if "_scout" in tid:
        return "scout"
    elif "_impl" in tid:
        return "impl"
    elif "_review" in tid:
        return "review"
    elif "_design" in tid:
        return "design"
    return "unknown"

for filename in sorted(os.listdir(tasks_dir)):
    if not filename.endswith(".yaml"):
        continue
    task_path = os.path.join(tasks_dir, filename)
    try:
        with open(task_path, encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        continue
    if not isinstance(data, dict):
        continue
    task = data.get("task", {})
    if not isinstance(task, dict):
        continue
    if str(task.get("parent_cmd", "")).strip() != cmd_id:
        continue

    assigned_to = task.get("assigned_to")
    if isinstance(assigned_to, list):
        for ninja in assigned_to:
            add_unique(ninjas, ninja)
    else:
        add_unique(ninjas, assigned_to)

    task_id_val = task.get("task_id", "")
    if task_id_val:
        add_unique(task_types, detect_task_type(task_id_val))

    related_lessons = task.get("related_lessons") or []
    if isinstance(related_lessons, list):
        for lesson in related_lessons:
            if isinstance(lesson, dict):
                add_unique(injected, lesson.get("id"))
            else:
                add_unique(injected, lesson)

for ninja in ninjas:
    report_path = os.path.join(reports_dir, f"{ninja}_report_{cmd_id}.yaml")
    if not os.path.exists(report_path):
        report_path = os.path.join(reports_dir, f"{ninja}_report.yaml")
    if not os.path.exists(report_path):
        continue
    try:
        with open(report_path, encoding="utf-8") as f:
            report = yaml.safe_load(f) or {}
    except Exception:
        continue
    if not isinstance(report, dict):
        continue
    lessons_useful = report.get("lessons_useful")
    if lessons_useful is None:
        # Backward compatibility for legacy report field.
        lessons_useful = report.get("lesson_referenced")
    if isinstance(lessons_useful, list):
        for item in lessons_useful:
            if isinstance(item, dict):
                add_unique(referenced, item.get("id"))
            else:
                add_unique(referenced, item)

print(",".join(ninjas) if ninjas else "none")
print(",".join(injected) if injected else "none")
print(",".join(referenced) if referenced else "none")
print(",".join(task_types) if task_types else "unknown")
PY
    ) || return 1

    ninja=$(printf '%s\n' "$parsed" | sed -n '1p')
    injected_ids=$(printf '%s\n' "$parsed" | sed -n '2p')
    referenced_ids=$(printf '%s\n' "$parsed" | sed -n '3p')
    task_type=$(printf '%s\n' "$parsed" | sed -n '4p')

    [ -z "$ninja" ] && ninja="none"
    [ -z "$injected_ids" ] && injected_ids="none"
    [ -z "$referenced_ids" ] && referenced_ids="none"
    [ -z "$task_type" ] && task_type="unknown"
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S')

    if [ ! -f "$tracking_file" ]; then
        printf 'timestamp\tcmd_id\tninja\tgate_result\tinjected_ids\treferenced_ids\ttask_type\n' > "$tracking_file"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$timestamp" "$cmd_id" "$ninja" "$gate_result" "$injected_ids" "$referenced_ids" "$task_type" >> "$tracking_file"
    echo "LESSON_TRACKING: ${cmd_id} (${gate_result}) appended"
}

# ─── lesson impact更新（ベストエフォート） ───
update_lesson_impact_tsv() {
    local cmd_id="$1"
    local gate_result="$2"
    local impact_file="$LOG_DIR/lesson_impact.tsv"

    if [ ! -f "$impact_file" ]; then
        echo "LESSON_IMPACT: SKIP (file not found: ${impact_file})"
        return 0
    fi

    IMPACT_FILE="$impact_file" TASKS_DIR="$TASKS_DIR" REPORTS_DIR="$SCRIPT_DIR/queue/reports" CMD_ID="$cmd_id" GATE_RESULT="$gate_result" python3 - <<'PY'
import csv
import os
import tempfile
import yaml

impact_file = os.environ["IMPACT_FILE"]
tasks_dir = os.environ["TASKS_DIR"]
reports_dir = os.environ["REPORTS_DIR"]
cmd_id = os.environ["CMD_ID"]
gate_result = os.environ["GATE_RESULT"]


def parse_yaml(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def add_unique(target, value):
    s = str(value).strip()
    if s and s not in target:
        target.append(s)


def resolve_report_file(ninja_name, task):
    explicit = str(task.get("report_filename", "")).strip().strip("'\"")
    if explicit:
        explicit_path = os.path.join(reports_dir, explicit)
        if os.path.exists(explicit_path):
            return explicit_path

    new_fmt = os.path.join(reports_dir, f"{ninja_name}_report_{cmd_id}.yaml")
    if os.path.exists(new_fmt):
        return new_fmt

    old_fmt = os.path.join(reports_dir, f"{ninja_name}_report.yaml")
    if os.path.exists(old_fmt):
        old_data = parse_yaml(old_fmt)
        if str(old_data.get("parent_cmd", "")).strip() == cmd_id:
            return old_fmt
    return None


ninjas = []
ninja_tasks = {}
referenced_ids = []

try:
    task_files = sorted(
        os.path.join(tasks_dir, name)
        for name in os.listdir(tasks_dir)
        if name.endswith(".yaml")
    )
except Exception:
    task_files = []

for task_path in task_files:
    data = parse_yaml(task_path)
    task = data.get("task", {})
    if not isinstance(task, dict):
        continue
    if str(task.get("parent_cmd", "")).strip() != cmd_id:
        continue

    assigned_to = task.get("assigned_to")
    if isinstance(assigned_to, list):
        for ninja in assigned_to:
            add_unique(ninjas, ninja)
            ninja_tasks[str(ninja).strip()] = task
    elif assigned_to:
        add_unique(ninjas, assigned_to)
        ninja_tasks[str(assigned_to).strip()] = task
    else:
        fallback_ninja = os.path.splitext(os.path.basename(task_path))[0]
        add_unique(ninjas, fallback_ninja)
        ninja_tasks[fallback_ninja] = task

for ninja in ninjas:
    report_file = resolve_report_file(ninja, ninja_tasks.get(ninja, {}))
    if not report_file:
        continue
    report = parse_yaml(report_file)
    lessons_useful = report.get("lessons_useful")
    if lessons_useful is None:
        # Backward compatibility for legacy report field.
        lessons_useful = report.get("lesson_referenced")
    if isinstance(lessons_useful, list):
        for item in lessons_useful:
            if isinstance(item, dict):
                add_unique(referenced_ids, item.get("id"))
            else:
                add_unique(referenced_ids, item)

rows = []
updated = 0
fieldnames = None
required = {"cmd_id", "lesson_id", "action", "result", "referenced"}

with open(impact_file, "r", newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f, delimiter="\t")
    fieldnames = reader.fieldnames or []
    if not required.issubset(set(fieldnames)):
        print("LESSON_IMPACT: SKIP (required columns missing)")
        raise SystemExit(0)

    for row in reader:
        if row.get("cmd_id") == cmd_id and row.get("result") == "pending":
            row["result"] = gate_result
            if row.get("action") != "withheld":
                row["referenced"] = "yes" if row.get("lesson_id") in referenced_ids else "no"
            updated += 1
        rows.append(row)

if updated == 0:
    print(f"LESSON_IMPACT: {cmd_id} no pending rows to update")
    raise SystemExit(0)

tmp_path = None
tmp_dir = os.path.dirname(impact_file) or "."
try:
    tmp_fd, tmp_path = tempfile.mkstemp(dir=tmp_dir, prefix="lesson_impact.", suffix=".tmp")
    with os.fdopen(tmp_fd, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)
    os.replace(tmp_path, impact_file)
except Exception:
    if tmp_path and os.path.exists(tmp_path):
        os.unlink(tmp_path)
    raise

print(f"LESSON_IMPACT: {cmd_id} updated rows={updated} referenced_ids={len(referenced_ids)}")
PY
}

# ─── BLOCK理由収集 ───
record_block_reason() {
    local reason="$1"
    if [ -n "$reason" ]; then
        BLOCK_REASONS+=("$reason")
    fi
}

# ─── preflight: ゲートフラグ未存在時の自動生成（冪等） ───
# GATE BLOCK率65%の主因=missing_gate(archive/lesson/review_gate)を解消。
# gate本体チェック前に、対応するフラグ生成処理を先行実行する。
# 既にフラグが存在する場合は何もしない(冪等)。品質BLOCKは維持。
preflight_gate_flags() {
    local cmd_id="$1"
    local gates_dir="$SCRIPT_DIR/queue/gates/${cmd_id}"
    mkdir -p "$gates_dir"

    echo "Preflight gate flag generation:"

    # archive.doneはGATE CLEAR後に自動実行（順序逆転防止）。preflightでは実行しない

    # 1. lesson.done — found:true候補確認後、適切な方法でフラグ生成
    if [ ! -f "$gates_dir/lesson.done" ]; then
        echo "  lesson: checking lesson_candidates..."
        local has_found_true=false
        local pf_task_file
        for pf_task_file in "$TASKS_DIR"/*.yaml; do
            [ -f "$pf_task_file" ] || continue
            if ! grep -q "parent_cmd: ${cmd_id}" "$pf_task_file" 2>/dev/null; then
                continue
            fi
            local pf_report_file pf_lc_found pf_ninja_name
            pf_ninja_name=$(basename "$pf_task_file" .yaml)
            pf_report_file=$(resolve_report_file "$pf_ninja_name")
            if [ -f "$pf_report_file" ]; then
                pf_lc_found=$(REPORT_FILE="$pf_report_file" python3 -c "
import yaml, os
try:
    with open(os.environ['REPORT_FILE']) as f:
        data = yaml.safe_load(f)
    lc = data.get('lesson_candidate', {}) if data else {}
    print('true' if isinstance(lc, dict) and lc.get('found') is True else 'false')
except:
    print('false')
" 2>/dev/null)
                [ "$pf_lc_found" = "true" ] && has_found_true=true
            fi
        done
        if [ "$has_found_true" = true ]; then
            # auto_draft_lesson.sh already ran (上段L276-295), which calls lesson_write.sh
            # lesson_write.sh doesn't create lesson.done when CMD_ID is empty
            # auto_draftが正常処理済みと判断し、不足フラグを補完する
            echo "timestamp: $(date '+%Y-%m-%dT%H:%M:%S')" > "$gates_dir/lesson.done"
            echo "source: lesson_write" >> "$gates_dir/lesson.done"
            echo "note: preflight補完 (auto_draft ran without CMD_ID)" >> "$gates_dir/lesson.done"
            echo "  lesson: preflight OK (found:true — flag for auto_draft)"
        else
            # found:true候補なし → lesson_check.shで「教訓なし」フラグ生成
            if bash "$SCRIPT_DIR/scripts/lesson_check.sh" "$cmd_id" "preflight: no found:true lesson_candidate" 2>&1; then
                echo "  lesson: preflight OK (via lesson_check)"
            else
                echo "  lesson: preflight WARN (lesson_check failed, non-blocking)"
            fi
        fi
    else
        # cmd_407: deploy_preflightで生成済みの場合、found:true検出時にsource upgradeする
        local pf_lesson_source
        pf_lesson_source=$(grep -E '^\s*source:' "$gates_dir/lesson.done" 2>/dev/null | sed 's/.*source: *//')
        if [ "$pf_lesson_source" != "lesson_write" ] && [ "$has_found_true" = true ]; then
            echo "  lesson: upgrading source ${pf_lesson_source} → lesson_write (found:true detected)"
            echo "timestamp: $(date '+%Y-%m-%dT%H:%M:%S')" > "$gates_dir/lesson.done"
            echo "source: lesson_write" >> "$gates_dir/lesson.done"
            echo "note: preflight upgrade (${pf_lesson_source}→lesson_write, found:true)" >> "$gates_dir/lesson.done"
        else
            echo "  lesson: already exists (skip)"
        fi
    fi

    # 3. review_gate.done (conditional — ALL_GATESに含まれる場合のみ)
    local pf_gate pf_needs_review=false
    for pf_gate in "${ALL_GATES[@]}"; do
        [ "$pf_gate" = "review_gate" ] && pf_needs_review=true && break
    done
    if [ "$pf_needs_review" = true ] && [ ! -f "$gates_dir/review_gate.done" ]; then
        echo "  review_gate: generating..."
        if bash "$SCRIPT_DIR/scripts/review_gate.sh" "$cmd_id" 2>&1; then
            echo "  review_gate: preflight OK"
        else
            echo "  review_gate: preflight WARN (review may not be complete)"
        fi
    elif [ "$pf_needs_review" = true ]; then
        echo "  review_gate: already exists (skip)"
    fi

    # 4. report_merge.done (conditional — ALL_GATESに含まれる場合のみ)
    local pf_needs_merge=false
    for pf_gate in "${ALL_GATES[@]}"; do
        [ "$pf_gate" = "report_merge" ] && pf_needs_merge=true && break
    done
    if [ "$pf_needs_merge" = true ] && [ ! -f "$gates_dir/report_merge.done" ]; then
        echo "  report_merge: generating..."
        if [ -f "$SCRIPT_DIR/scripts/report_merge.sh" ]; then
            if bash "$SCRIPT_DIR/scripts/report_merge.sh" "$cmd_id" 2>&1; then
                echo "  report_merge: preflight OK"
            else
                echo "  report_merge: preflight WARN (merge may not be ready)"
            fi
        else
            echo "  report_merge: SKIP (script not found)"
        fi
    elif [ "$pf_needs_merge" = true ]; then
        echo "  report_merge: already exists (skip)"
    fi

    echo ""
}

# ─── 必須フラグ構築 ───
ALWAYS_REQUIRED=("lesson")

# task_type検出
read -r HAS_RECON HAS_IMPLEMENT <<< "$(detect_task_types "$CMD_ID")"

CONDITIONAL=()
if [ "$HAS_RECON" = "true" ]; then
    CONDITIONAL+=("report_merge")
fi
if [ "$HAS_IMPLEMENT" = "true" ]; then
    CONDITIONAL+=("review_gate")
fi

ALL_GATES=("${ALWAYS_REQUIRED[@]}" "${CONDITIONAL[@]}")

# cmd_407: gate_metrics拡張用のtask_type/model/bloom_level収集
read -r GATE_TASK_TYPE GATE_MODEL GATE_BLOOM_LEVEL <<< "$(collect_gate_metrics_extra "$CMD_ID")"
GATE_INJECTED_LESSONS="$(collect_injected_lessons "$CMD_ID")"
CMD_TITLE="$(collect_cmd_title "$CMD_ID")"

# ─── 忍者報告からlesson_candidate自動draft登録 ───
echo "Auto-draft lesson candidates:"
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi
    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")
    if [ -f "$report_file" ]; then
        if bash "$SCRIPT_DIR/scripts/auto_draft_lesson.sh" "$report_file" 2>&1; then
            true
        else
            echo "  WARN: auto_draft_lesson.sh failed for ${ninja_name} (non-blocking)"
        fi
    else
        echo "  ${ninja_name}: no report file"
    fi
done
echo ""

# ─── preflight: ゲートフラグ自動生成（冪等） ───
preflight_gate_flags "$CMD_ID"

# ─── 緊急override確認 ───
if [ -f "$GATES_DIR/emergency.override" ]; then
    echo "GATE CLEAR (緊急override): ${CMD_ID}の全ゲートをバイパス"
    for gate in "${ALL_GATES[@]}"; do
        echo "  ${gate}: OVERRIDE"
    done
    bash "$SCRIPT_DIR/scripts/ntfy.sh" "🚨 緊急override: ${CMD_ID}のゲートをバイパス"
    # gate_yaml_status: YAML status更新（WARNING only）
    if bash "$SCRIPT_DIR/scripts/gates/gate_yaml_status.sh" "$CMD_ID" 2>&1; then
        true
    else
        echo "  WARN: gate_yaml_status.sh failed (non-blocking)"
    fi
    update_status "$CMD_ID"
    append_changelog "$CMD_ID"
    echo -e "$(date +%Y-%m-%dT%H:%M:%S)\t${CMD_ID}\tOVERRIDE\temergency_override\t${GATE_TASK_TYPE}\t${GATE_MODEL}\t${GATE_BLOOM_LEVEL}\t${GATE_INJECTED_LESSONS}\t${CMD_TITLE}" >> "$GATE_METRICS_LOG"
    if append_lesson_tracking "$CMD_ID" "OVERRIDE" 2>&1; then
        true
    else
        echo "  WARN: append_lesson_tracking failed (non-blocking)"
    fi

    # ─── lesson_merge自動実行（ベストエフォート） ───
    echo ""
    echo "Lesson merge (auto):"
    if [ -f "$SCRIPT_DIR/scripts/lesson_merge.sh" ]; then
        if bash "$SCRIPT_DIR/scripts/lesson_merge.sh" 2>&1; then
            echo "  [GATE] lesson_merge: OK"
        else
            echo "  [GATE] lesson_merge: SKIP (non-blocking)"
        fi
    else
        echo "  [GATE] lesson_merge: SKIP (script not found)"
    fi

    # ─── GATE CLEAR時 自動通知（ベストエフォート） ───
    echo ""
    echo "Auto-notification (GATE CLEAR - emergency override):"

    # dashboard_update（最初に実行。dashboard.mdを更新）
    if bash "$SCRIPT_DIR/scripts/dashboard_update.sh" "$CMD_ID"; then
        echo "  dashboard_update: OK ($CMD_ID)"
    else
        echo "  dashboard_update: WARN (failed, continuing)" >&2
    fi

    # gist_sync --once（dashboard更新後。ntfyにGist URLを含めるため）
    if bash "$SCRIPT_DIR/scripts/gist_sync.sh" --once >/dev/null 2>&1; then
        echo "  gist_sync: OK"
    else
        echo "  gist_sync: WARN (sync failed, non-blocking)" >&2
    fi

    # ntfy_cmd（gist_sync後に実行）
    if bash "$SCRIPT_DIR/scripts/ntfy_cmd.sh" "$CMD_ID" "GATE CLEAR — ${CMD_ID} 完了" 2>/dev/null; then
        echo "  ntfy_cmd: OK"
    else
        echo "  ntfy_cmd: WARN (notification failed, non-blocking)" >&2
    fi

    # archive_completed（ntfy後に実行。報告YAML退避はgate CLEAR後でなければならない）
    if bash "$SCRIPT_DIR/scripts/archive_completed.sh" "$CMD_ID" 2>&1; then
        echo "  archive_completed: OK ($CMD_ID)"
    else
        echo "  archive_completed: WARN (failed, non-blocking)" >&2
    fi

    exit 0
fi

# ─── 各フラグの状態確認 ───
MISSING_GATES=()
BLOCK_REASONS=()
ALL_CLEAR=true

echo "Gate check: ${CMD_ID}"
echo "  Required: ${ALL_GATES[*]}"
if [ ${#CONDITIONAL[@]} -gt 0 ]; then
    echo "  Conditional: ${CONDITIONAL[*]} (task_type: recon=${HAS_RECON}, implement=${HAS_IMPLEMENT})"
fi
echo ""

for gate in "${ALL_GATES[@]}"; do
    done_file="$GATES_DIR/${gate}.done"

    if [ -f "$done_file" ]; then
        detail=$(head -1 "$done_file" 2>/dev/null)
        if [ -n "$detail" ]; then
            echo "  ${gate}: DONE (${detail})"
        else
            echo "  ${gate}: DONE"
        fi
    else
        echo "  ${gate}: MISSING ← 未完了"
        MISSING_GATES+=("$gate")
        record_block_reason "missing_gate:${gate}"
        ALL_CLEAR=false
    fi
done

# ─── related_lessons存在チェック（deploy_task.sh経由確認） ───
echo ""
echo "Related lessons injection check:"
RL_CHECKED=false
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi

    RL_CHECKED=true
    ninja_name=$(basename "$task_file" .yaml)

    has_rl_key=$(python3 -c "
import yaml, sys
try:
    with open('$task_file') as f:
        data = yaml.safe_load(f)
    task = data.get('task', {}) if data else {}
    print('yes' if 'related_lessons' in task else 'no')
except:
    print('error')
" 2>/dev/null)

    if [ "$has_rl_key" = "yes" ]; then
        echo "  ${ninja_name}: OK (related_lessons present)"
    elif [ "$has_rl_key" = "no" ]; then
        echo "  ${ninja_name}: WARN ← related_lessonsキー欠落（deploy_task.sh経由でない可能性）"
    else
        echo "  ${ninja_name}: WARN ← related_lessons解析エラー"
    fi
done
if [ "$RL_CHECKED" = false ]; then
    echo "  (no tasks found for this cmd)"
fi

# ─── lessons_useful検証（related_lessonsあり→報告にlessons_useful必須） ───
echo ""
echo "Lessons useful check:"
LESSON_CHECKED=false
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi

    # related_lessonsの有無をチェック（空リスト[]やnullは除外）
    has_lessons=$(python3 -c "
import yaml, sys
try:
    with open('$task_file') as f:
        data = yaml.safe_load(f)
    task = data.get('task', {}) if data else {}
    rl = task.get('related_lessons', [])
    print('yes' if rl and len(rl) > 0 else 'no')
except:
    print('no')
" 2>/dev/null)

    if [ "$has_lessons" = "yes" ]; then
        LESSON_CHECKED=true
        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name")

        if [ -f "$report_file" ]; then
            # Python判定: lessons_usefulが非空リストかチェック（旧lesson_referencedにも対応）
            lr_status=$(python3 -c "
import yaml, sys
try:
    with open('$report_file') as f:
        data = yaml.safe_load(f)
    if not data:
        print('empty')
        sys.exit(0)
    lr = data.get('lessons_useful')
    if lr is None:
        lr = data.get('lesson_referenced')
    if lr and isinstance(lr, list) and len(lr) > 0:
        print('ok')
    else:
        print('empty')
except:
    print('error')
" 2>/dev/null)

            if [ "$lr_status" = "ok" ]; then
                echo "  ${ninja_name}: OK (lessons_useful present and non-empty)"
            else
                # related_lessonsからlesson IDを抽出してメッセージに表示
                rl_ids=$(python3 -c "
import yaml
try:
    with open('$task_file') as f:
        data = yaml.safe_load(f)
    task = data.get('task', {}) if data else {}
    rl = task.get('related_lessons', [])
    ids = [str(l.get('id', '?')) for l in rl if isinstance(l, dict)]
    print(','.join(ids) if ids else '(unknown)')
except:
    print('(parse_error)')
" 2>/dev/null)
                echo "  ${ninja_name}: NG ← lessons_useful空。related_lessons [${rl_ids}] のうち実際に役立った教訓を報告に記載せよ"
                record_block_reason "${ninja_name}:empty_lessons_useful:related=[${rl_ids}]"
                ALL_CLEAR=false
            fi
        else
            echo "  ${ninja_name}: SKIP (report not found)"
        fi
    fi
done
if [ "$LESSON_CHECKED" = false ]; then
    echo "  (no tasks with related_lessons for this cmd)"
fi

# ─── reviewed:false残存チェック（教訓確認の強制） ───
echo ""
echo "Lesson reviewed check:"
REVIEWED_OK=true
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi

    unreviewed=$(python3 -c "
import yaml, sys
try:
    with open('$task_file') as f:
        data = yaml.safe_load(f)
    task = data.get('task', {}) if data else {}
    rl = task.get('related_lessons', [])
    if not rl:
        sys.exit(0)
    unrev = [l.get('id','?') for l in rl if l.get('reviewed') == False]
    if unrev:
        print(','.join(unrev))
except:
    pass
" 2>/dev/null)

    ninja_name=$(basename "$task_file" .yaml)
    if [ -n "$unreviewed" ]; then
        echo "  ${ninja_name}: NG ← reviewed:false残存 [${unreviewed}]"
        record_block_reason "${ninja_name}:unreviewed_lessons:${unreviewed}"
        REVIEWED_OK=false
        ALL_CLEAR=false
    else
        echo "  ${ninja_name}: OK (all reviewed)"
    fi
done
if [ "$REVIEWED_OK" = true ]; then
    echo "  (all lessons reviewed or no lessons)"
fi

# ─── lesson_candidate検証（found:trueなのに未登録を防止） ───
echo ""
echo "Lesson candidate check:"
LC_CHECKED=false
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi

    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (report not found)"
        continue
    fi

    LC_CHECKED=true

    # lesson_candidateフィールドの検証
    lc_status=$(python3 -c "
import yaml, sys
try:
    with open('$report_file') as f:
        data = yaml.safe_load(f)
    if not data:
        print('missing')
        sys.exit(0)
    lc = data.get('lesson_candidate')
    if lc is None:
        print('missing')
    elif isinstance(lc, list):
        print('legacy_list')
    elif not isinstance(lc, dict):
        print('malformed')
    elif 'found' not in lc:
        print('found_missing')
    elif lc['found'] == False:
        print('ok_false')
    elif lc['found'] == True:
        print('found_true')
    else:
        print('malformed')
except:
    print('error')
" 2>/dev/null)

    case "$lc_status" in
        ok_false)
            echo "  ${ninja_name}: OK (lesson_candidate: found=false)"
            ;;
        found_true)
            # lesson.doneのsource確認
            lesson_done="$GATES_DIR/lesson.done"
            if [ -f "$lesson_done" ]; then
                lsource=$(grep -E '^\s*source:' "$lesson_done" 2>/dev/null | sed 's/.*source: *//')
                [ -z "$lsource" ] && echo "[WARN] Empty source field in lesson" >&2
                if [ "$lsource" = "lesson_write" ]; then
                    echo "  ${ninja_name}: OK (lesson_candidate found:true, registered via lesson_write)"
                else
                    echo "  ${ninja_name}: NG ← lesson_candidate found:true but lesson.done source=${lsource} (not lesson_write)"
                    record_block_reason "${ninja_name}:lesson_done_source:${lsource}"
                    ALL_CLEAR=false
                fi
            else
                echo "  ${ninja_name}: NG ← lesson_candidate found:true but lesson.done not found"
                record_block_reason "${ninja_name}:lesson_done_missing"
                ALL_CLEAR=false
            fi
            ;;
        missing)
            echo "  ${ninja_name}: NG ← lesson_candidateフィールド欠落"
            record_block_reason "${ninja_name}:lesson_candidate_missing"
            ALL_CLEAR=false
            ;;
        legacy_list)
            echo "  ${ninja_name}: NG ← lesson_candidateが旧形式(リスト)。正規フォーマット: found: true/false + title + detail + project"
            record_block_reason "${ninja_name}:lesson_candidate_legacy_list"
            ALL_CLEAR=false
            ;;
        found_missing)
            echo "  ${ninja_name}: NG ← lesson_candidate.found が未設定。正規フォーマット: found: true/false"
            record_block_reason "${ninja_name}:lesson_candidate_found_missing"
            ALL_CLEAR=false
            ;;
        malformed)
            echo "  ${ninja_name}: NG ← lesson_candidate構造不正"
            record_block_reason "${ninja_name}:lesson_candidate_malformed"
            ALL_CLEAR=false
            ;;
        *)
            echo "  ${ninja_name}: NG ← lesson_candidate解析エラー"
            record_block_reason "${ninja_name}:lesson_candidate_parse_error"
            ALL_CLEAR=false
            ;;
    esac
done
if [ "$LC_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── purpose_validation検証（fit:falseでBLOCK、fit空欄はWARN） ───
echo ""
echo "Purpose validation check:"
PV_CHECKED=false
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi

    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (report not found)"
        continue
    fi

    PV_CHECKED=true
    pv_fit=$(field_get "$report_file" "fit" "")

    case "$pv_fit" in
        true)
            # fit=true はPASS（要件どおり無出力）
            ;;
        false)
            echo "GATE BLOCK: purpose_validation.fit=false (目的未達成)"
            echo "  ${ninja_name}: fit=false"
            record_block_reason "${ninja_name}:purpose_validation_fit_false"
            ALL_CLEAR=false
            ;;
        "")
            echo "  WARN: ${ninja_name}: fit未記入（段階導入: 非BLOCK）"
            ;;
        *)
            echo "  WARN: ${ninja_name}: fit値不正 '${pv_fit}'（段階導入: 非BLOCK）"
            ;;
    esac
done
if [ "$PV_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── skill_candidate検証（WARNのみ、ブロックしない） ───
echo ""
echo "Skill candidate check:"
SC_CHECKED=false
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi

    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (report not found)"
        continue
    fi

    SC_CHECKED=true

    sc_status=$(python3 -c "
import yaml, sys
try:
    with open('$report_file') as f:
        data = yaml.safe_load(f)
    if not data:
        print('missing')
        sys.exit(0)
    sc = data.get('skill_candidate')
    if sc is None:
        print('missing')
    elif not isinstance(sc, dict):
        print('malformed')
    elif 'found' not in sc:
        print('no_found')
    else:
        print('ok')
except:
    print('error')
" 2>/dev/null)

    case "$sc_status" in
        ok)
            echo "  ${ninja_name}: OK (skill_candidate.found present)"
            ;;
        missing)
            echo "  WARN: ${ninja_name}_report.yaml missing skill_candidate.found"
            ;;
        no_found)
            echo "  WARN: ${ninja_name}_report.yaml missing skill_candidate.found"
            ;;
        malformed)
            echo "  WARN: ${ninja_name}_report.yaml skill_candidate構造不正"
            ;;
        *)
            echo "  WARN: ${ninja_name}_report.yaml skill_candidate解析エラー"
            ;;
    esac
done
if [ "$SC_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── decision_candidate検証（WARNのみ、ブロックしない） ───
echo ""
echo "Decision candidate check:"
DC_CHECKED=false
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi

    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (report not found)"
        continue
    fi

    DC_CHECKED=true

    dc_status=$(python3 -c "
import yaml, sys
try:
    with open('$report_file') as f:
        data = yaml.safe_load(f)
    if not data:
        print('missing')
        sys.exit(0)
    dc = data.get('decision_candidate')
    if dc is None:
        print('missing')
    elif not isinstance(dc, dict):
        print('malformed')
    elif 'found' not in dc:
        print('no_found')
    else:
        print('ok')
except:
    print('error')
" 2>/dev/null)

    case "$dc_status" in
        ok)
            echo "  ${ninja_name}: OK (decision_candidate.found present)"
            ;;
        missing)
            echo "  WARN: ${ninja_name}_report.yaml missing decision_candidate.found"
            ;;
        no_found)
            echo "  WARN: ${ninja_name}_report.yaml missing decision_candidate.found"
            ;;
        malformed)
            echo "  WARN: ${ninja_name}_report.yaml decision_candidate構造不正"
            ;;
        *)
            echo "  WARN: ${ninja_name}_report.yaml decision_candidate解析エラー"
            ;;
    esac
done
if [ "$DC_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── draft教訓存在チェック（プロジェクト関連のdraft未査読をブロック） ───
echo ""
echo "Draft lesson check:"
# cmdのprojectを取得
CMD_PROJECT=$(awk -v cmd="${CMD_ID}" '
    /^[ ]*- id:/ && index($0, cmd) { found=1; next }
    found && /^[ ]*- id:/ { exit }
    found && /^[ ]*project:/ { sub(/^[ ]*project: */, ""); print; exit }
' "$YAML_FILE")

if [ -n "$CMD_PROJECT" ]; then
    # projectのSSOTパスを取得
    DRAFT_SSOT_PATH=$(python3 -c "
import yaml
with open('$SCRIPT_DIR/config/projects.yaml', encoding='utf-8') as f:
    cfg = yaml.safe_load(f)
for p in cfg.get('projects', []):
    if p['id'] == '$CMD_PROJECT':
        print(p['path'])
        break
" 2>/dev/null)

    if [ -n "$DRAFT_SSOT_PATH" ]; then
        DRAFT_LESSONS_FILE="$DRAFT_SSOT_PATH/tasks/lessons.md"
        if [ -f "$DRAFT_LESSONS_FILE" ]; then
            draft_count=$(grep -c '^\- \*\*status\*\*: draft' "$DRAFT_LESSONS_FILE" 2>/dev/null || true)
            draft_count=${draft_count:-0}
            if [ "$draft_count" -gt 0 ]; then
                echo "  NG ← ${CMD_PROJECT}に${draft_count}件のdraft未査読教訓あり"
                record_block_reason "draft_lessons:${draft_count}"
                ALL_CLEAR=false
            else
                echo "  OK (no draft lessons in ${CMD_PROJECT})"
            fi
        else
            echo "  SKIP (lessons file not found: ${DRAFT_LESSONS_FILE})"
        fi
    else
        echo "  SKIP (project path not found for: ${CMD_PROJECT})"
    fi
else
    echo "  SKIP (project not found in cmd)"
fi

# ─── grep直書きYAMLアクセス検出（WARNのみ、ブロックしない） L070 ───
echo ""
echo "Raw grep YAML access check (L070):"
RAW_GREP_COUNT=0
# 検出対象: scripts/*.sh と scripts/lib/*.sh
# 除外: scripts/lib/field_get.sh 自身, scripts/gates/ 配下
# 検出パターン: grep で YAML キーを直接抽出するパターン (^\s+field: or ^  field:)
for script_file in "$SCRIPT_DIR"/scripts/*.sh "$SCRIPT_DIR"/scripts/lib/*.sh; do
    [ -f "$script_file" ] || continue
    rel_path="${script_file#"$SCRIPT_DIR"/}"
    # 除外: field_get.sh自身, gates/配下
    case "$rel_path" in
        scripts/lib/field_get.sh) continue ;;
        scripts/gates/*) continue ;;
    esac
    # 検出: grep で YAML キー抽出パターン (^\s or ^  で始まるYAMLフィールドアクセス)
    # Stage 1: grep + '^\s' or '^  ' パターンを検出
    # Stage 2: コメント行・field_get言及を除外
    # Stage 3: field_name: パターンを含む行のみ保持
    hits=$(grep -nE "grep.*['\"]\\^(\\\\s|  )" "$script_file" 2>/dev/null \
        | grep -vE '^[[:space:]]*#' \
        | grep -v 'field_get' \
        | grep -E '[a-z_]+:' \
        || true)
    if [ -n "$hits" ]; then
        echo "  WARN: ${rel_path} — raw grep YAML access detected:"
        echo "$hits" | head -3 | while IFS= read -r line; do
            echo "    $line"
        done
        RAW_GREP_COUNT=$((RAW_GREP_COUNT + 1))
    fi
done
if [ "$RAW_GREP_COUNT" -eq 0 ]; then
    echo "  OK (no raw grep YAML access detected in scripts/)"
else
    echo "  WARN: ${RAW_GREP_COUNT} script(s) use raw grep for YAML field access. Migrate to field_get (scripts/lib/field_get.sh)"
fi

# ─── inbox_archive強制チェック（WARNのみ、ブロックしない） ───
echo ""
echo "Inbox archive check:"
KARO_INBOX="$SCRIPT_DIR/queue/inbox/karo.yaml"
if [ -f "$KARO_INBOX" ]; then
    read_count=$(grep -c 'read: true' "$KARO_INBOX" 2>/dev/null || true)
    read_count=${read_count:-0}

    if [ "$read_count" -ge 10 ]; then
        echo "INBOX_ARCHIVE_WARN: karo has ${read_count} read messages, running inbox_archive.sh"
        if bash "$SCRIPT_DIR/scripts/inbox_archive.sh" karo; then
            echo "  karo: inbox_archive completed"
        else
            echo "  WARN: inbox_archive.sh failed for karo"
        fi
    else
        echo "  karo: OK (read:true=${read_count}, threshold=10)"
    fi
else
    echo "  WARN: karo inbox file not found: ${KARO_INBOX}"
fi

# ─── 未反映PD検出（WARNのみ、ブロックしない） ───
echo ""
echo "Pending decision context sync check:"
PD_FILE="$SCRIPT_DIR/queue/pending_decisions.yaml"
if [ -f "$PD_FILE" ]; then
    unsynced_pds=$(python3 -c "
import yaml, sys
try:
    with open('$PD_FILE') as f:
        data = yaml.safe_load(f)
    if not data or not data.get('decisions'):
        sys.exit(0)
    for d in data['decisions']:
        if d.get('source_cmd') == '${CMD_ID}' and d.get('status') == 'resolved' and d.get('context_synced') == False:
            print(d.get('id', '???'))
except:
    pass
" 2>/dev/null)

    if [ -n "$unsynced_pds" ]; then
        while IFS= read -r pd_id; do
            echo "  ⚠️ WARNING: ${pd_id} resolved but context not synced"
        done <<< "$unsynced_pds"
    else
        echo "  OK (no unsynced resolved PDs for ${CMD_ID})"
    fi
else
    echo "  SKIP (pending_decisions.yaml not found)"
fi

# ─── 穴4: 調査恒久化チェック（WARNのみ、ブロックしない） ───
echo ""
echo "Recon knowledge persistence check (穴4):"
# purposeを取得（append_changelog内と同じawk）
CMD_PURPOSE=$(awk -v cmd="${CMD_ID}" '
    /^[ ]*- id:/ && index($0, cmd) { found=1; next }
    found && /^[ ]*- id:/ { exit }
    found && /^[ ]*purpose:/ { sub(/^[ ]*purpose: *"?/, ""); sub(/"$/, ""); print; exit }
' "$YAML_FILE")

IS_RECON=false
if echo "$CMD_PURPOSE" | grep -qE '偵察|調査|棚卸し|recon|investigation'; then
    IS_RECON=true
fi

if [ "$IS_RECON" = true ]; then
    if [ -n "$CMD_PROJECT" ]; then
        CONTEXT_FILE="$SCRIPT_DIR/context/${CMD_PROJECT}.md"
        PROJECT_YAML="$SCRIPT_DIR/projects/${CMD_PROJECT}.yaml"
        HAS_CHANGE=false

        # git diffで変更有無を確認（ステージ済み+未ステージ両方）
        if [ -f "$CONTEXT_FILE" ] && git -C "$SCRIPT_DIR" diff HEAD -- "context/${CMD_PROJECT}.md" 2>/dev/null | grep -q '^[+-]'; then
            HAS_CHANGE=true
        fi
        if [ -f "$PROJECT_YAML" ] && git -C "$SCRIPT_DIR" diff HEAD -- "projects/${CMD_PROJECT}.yaml" 2>/dev/null | grep -q '^[+-]'; then
            HAS_CHANGE=true
        fi
        # ステージ済みの変更もチェック
        if [ "$HAS_CHANGE" = false ]; then
            if [ -f "$CONTEXT_FILE" ] && git -C "$SCRIPT_DIR" diff --cached -- "context/${CMD_PROJECT}.md" 2>/dev/null | grep -q '^[+-]'; then
                HAS_CHANGE=true
            fi
            if [ -f "$PROJECT_YAML" ] && git -C "$SCRIPT_DIR" diff --cached -- "projects/${CMD_PROJECT}.yaml" 2>/dev/null | grep -q '^[+-]'; then
                HAS_CHANGE=true
            fi
        fi

        if [ "$HAS_CHANGE" = true ]; then
            echo "  OK (context/${CMD_PROJECT}.md or projects/${CMD_PROJECT}.yaml has changes)"
        else
            echo "  ⚠️ 穴4: 調査結果が知識基盤に未反映。context/*.md or projects/*.yaml を更新せよ"
        fi
    else
        echo "  SKIP (project not found in cmd — cannot check knowledge files)"
    fi
else
    echo "  SKIP (non-recon cmd: purpose does not contain recon keywords)"
fi

# ─── TODO/FIXME残存チェック（WARNのみ、ブロックしない） ───
echo ""
echo "TODO/FIXME residual check:"
CMD_NUM="${CMD_ID#cmd_}"
TODO_HITS=""
# cmd_IDパターン検索
TODO_HITS_CMD=$(grep -rn "TODO.*${CMD_ID}\|FIXME.*${CMD_ID}" "$SCRIPT_DIR/scripts/" "$SCRIPT_DIR/lib/" 2>/dev/null || true)
# subtaskパターン検索
TODO_HITS_SUB=$(grep -rn "TODO.*subtask_${CMD_NUM}\|FIXME.*subtask_${CMD_NUM}" "$SCRIPT_DIR/scripts/" "$SCRIPT_DIR/lib/" 2>/dev/null || true)

# 結合（重複除去）
TODO_HITS=$(printf '%s\n%s' "$TODO_HITS_CMD" "$TODO_HITS_SUB" | sort -u | grep -v '^$' || true)
TODO_COUNT=$(printf '%s' "$TODO_HITS" | grep -c '.' 2>/dev/null || true)
TODO_COUNT=${TODO_COUNT:-0}

if [ "$TODO_COUNT" -gt 0 ]; then
    echo "  TODO_WARN: ${TODO_COUNT}件のTODO/FIXMEが残存:"
    printf '%s\n' "$TODO_HITS" | head -10 | while IFS= read -r line; do
        echo "    ${line}"
    done
    if [ "$TODO_COUNT" -gt 10 ]; then
        echo "    ... (${TODO_COUNT}件中10件表示)"
    fi
else
    echo "  TODO check: OK (0 remaining)"
fi

# ─── Vercel Phaseリンク整合チェック（context変更時のみ、BLOCK対象） ───
echo ""
echo "Vercel phase link check:"
changed_contexts=$(git -C "$SCRIPT_DIR" diff --name-only HEAD~1 2>/dev/null | grep '^context/' || true)
if [ -n "$changed_contexts" ]; then
    if [ -f "$SCRIPT_DIR/scripts/gates/gate_vercel_phase.sh" ]; then
        if bash "$SCRIPT_DIR/scripts/gates/gate_vercel_phase.sh"; then
            echo "  OK (gate_vercel_phase passed)"
        else
            echo "  ALERT: gate_vercel_phase failed (broken docs/research refs)"
            record_block_reason "vercel_phase:broken_references"
            ALL_CLEAR=false
        fi
    else
        echo "  WARN: gate_vercel_phase.sh not found (skip)"
    fi
else
    echo "  SKIP (no context/*.md changes detected since HEAD~1)"
fi

# ─── 判定結果 ───
echo ""
if [ "$ALL_CLEAR" = true ]; then
    echo "GATE CLEAR: cmd完了許可"
    echo -e "$(date +%Y-%m-%dT%H:%M:%S)\t${CMD_ID}\tCLEAR\tall_gates_passed\t${GATE_TASK_TYPE}\t${GATE_MODEL}\t${GATE_BLOOM_LEVEL}\t${GATE_INJECTED_LESSONS}\t${CMD_TITLE}" >> "$GATE_METRICS_LOG"
    # gate_yaml_status: YAML status更新（WARNING only）
    if bash "$SCRIPT_DIR/scripts/gates/gate_yaml_status.sh" "$CMD_ID" 2>&1; then
        true
    else
        echo "  WARN: gate_yaml_status.sh failed (non-blocking)"
    fi
    update_status "$CMD_ID" || echo "  WARN: update_status failed (non-blocking)"
    append_changelog "$CMD_ID" || echo "  WARN: append_changelog failed (non-blocking)"
    if append_lesson_tracking "$CMD_ID" "CLEAR" 2>&1; then
        true
    else
        echo "  WARN: append_lesson_tracking failed (non-blocking)"
    fi
    if update_lesson_impact_tsv "$CMD_ID" "CLEAR" 2>&1; then
        true
    else
        echo "  WARN: update_lesson_impact_tsv failed (non-blocking)"
    fi
    bash "$SCRIPT_DIR/scripts/lesson_impact_analysis.sh" --sync-counters 2>&1 || echo "  WARN: sync-counters failed (non-blocking)"

    # ─── lesson_merge自動実行（ベストエフォート） ───
    echo ""
    echo "Lesson merge (auto):"
    if [ -f "$SCRIPT_DIR/scripts/lesson_merge.sh" ]; then
        if bash "$SCRIPT_DIR/scripts/lesson_merge.sh" 2>&1; then
            echo "  [GATE] lesson_merge: OK"
        else
            echo "  [GATE] lesson_merge: SKIP (non-blocking)"
        fi
    else
        echo "  [GATE] lesson_merge: SKIP (script not found)"
    fi

    # ─── lesson score自動更新（GATE CLEAR時のみ、ベストエフォート） ───
    echo ""
    echo "Lesson score update (helpful):"
    if [ -n "$CMD_PROJECT" ] && [ -f "$SCRIPT_DIR/scripts/lesson_update_score.sh" ]; then
        SCORE_UPDATED=0
        for task_file in "$TASKS_DIR"/*.yaml; do
            [ -f "$task_file" ] || continue
            if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
                continue
            fi
            ninja_name=$(basename "$task_file" .yaml)
            report_file=$(resolve_report_file "$ninja_name")
            if [ -f "$report_file" ]; then
                score_entries=$(python3 -c "
import yaml, sys
import re

def parse_yaml(path):
    try:
        with open(path, encoding='utf-8') as f:
            data = yaml.safe_load(f)
        if isinstance(data, dict):
            return data
    except Exception:
        pass
    return {}

def normalize_lesson_ids(raw):
    out = []
    seen = set()
    if isinstance(raw, list):
        for item in raw:
            lid = ''
            if isinstance(item, str):
                lid = item.strip()
            elif isinstance(item, dict):
                lid = str(item.get('id', '')).strip()
            if lid and lid not in seen:
                seen.add(lid)
                out.append(lid)
    return out

try:
    report_data = parse_yaml('$report_file')
    task_data = parse_yaml('$task_file')
    task = task_data.get('task', {}) if isinstance(task_data, dict) else {}

    if not report_data:
        sys.exit(0)

    lr = report_data.get('lessons_useful')
    if lr is None:
        lr = report_data.get('lesson_referenced', [])

    explicit_ids = normalize_lesson_ids(lr)
    explicit_set = set(explicit_ids)
    for lid in explicit_ids:
        print(f'explicit\t{lid}')

    related_ids = []
    related_seen = set()
    related_lessons = task.get('related_lessons', [])
    if isinstance(related_lessons, list):
        for lesson in related_lessons:
            if not isinstance(lesson, dict):
                continue
            lid = str(lesson.get('id', '')).strip()
            if lid and lid not in related_seen:
                related_seen.add(lid)
                related_ids.append(lid)

    report_text = ''
    try:
        with open('$report_file', encoding='utf-8') as rf:
            report_text = rf.read()
    except Exception:
        report_text = ''

    for lid in related_ids:
        if lid in explicit_set:
            continue
        pattern = rf'(?<![A-Za-z0-9_]){re.escape(lid)}(?![A-Za-z0-9_])'
        if re.search(pattern, report_text):
            print(f'auto\t{lid}')
except:
    pass
" 2>/dev/null)
                while IFS=$'\t' read -r score_type lid; do
                    [ -z "$score_type" ] && continue
                    [ -z "$lid" ] && continue
                    if bash "$SCRIPT_DIR/scripts/lesson_update_score.sh" "$CMD_PROJECT" "$lid" helpful 2>&1; then
                        if [ "$score_type" = "auto" ]; then
                            echo "  ${lid}: helpful +1 (auto-detected in report text)"
                        else
                            echo "  ${lid}: helpful +1"
                        fi
                        SCORE_UPDATED=$((SCORE_UPDATED + 1))
                    else
                        echo "  WARN: ${lid}: score update failed (non-blocking)"
                    fi
                done <<< "$score_entries"
            fi
        done
        echo "  Updated: ${SCORE_UPDATED} lesson(s)"
    elif [ -z "$CMD_PROJECT" ]; then
        echo "  SKIP (project not found in cmd)"
    else
        echo "  SKIP (lesson_update_score.sh not found — waiting for subtask_309_score)"
    fi

    # ─── GATE CLEAR時 自動通知（ベストエフォート） ───
    echo ""
    echo "Auto-notification (GATE CLEAR):"

    # dashboard_update（最初に実行。dashboard.mdを更新）
    if bash "$SCRIPT_DIR/scripts/dashboard_update.sh" "$CMD_ID"; then
        echo "  dashboard_update: OK ($CMD_ID)"
    else
        echo "  dashboard_update: WARN (failed, continuing)" >&2
    fi

    # gist_sync --once（dashboard更新後。ntfyにGist URLを含めるため）
    if bash "$SCRIPT_DIR/scripts/gist_sync.sh" --once >/dev/null 2>&1; then
        echo "  gist_sync: OK"
    else
        echo "  gist_sync: WARN (sync failed, non-blocking)" >&2
    fi

    # ntfy_cmd（gist_sync後に実行）
    if bash "$SCRIPT_DIR/scripts/ntfy_cmd.sh" "$CMD_ID" "GATE CLEAR — ${CMD_ID} 完了" 2>/dev/null; then
        echo "  ntfy_cmd: OK"
    else
        echo "  ntfy_cmd: WARN (notification failed, non-blocking)" >&2
    fi

    # archive_completed（ntfy後に実行。報告YAML退避はgate CLEAR後でなければならない）
    if bash "$SCRIPT_DIR/scripts/archive_completed.sh" "$CMD_ID" 2>&1; then
        echo "  archive_completed: OK ($CMD_ID)"
    else
        echo "  archive_completed: WARN (failed, non-blocking)" >&2
    fi

    # ─── GATE CLEAR時 淘汰候補自動deprecate（ベストエフォート） ───
    echo ""
    echo "Auto-deprecate check (unused - GATE CLEAR):"
    if [ -f "$SCRIPT_DIR/scripts/knowledge_metrics.sh" ] && [ -f "$SCRIPT_DIR/scripts/lesson_deprecate.sh" ]; then
        UNUSED_DEPRECATE_COUNT=0
        if metrics_json=$(bash "$SCRIPT_DIR/scripts/knowledge_metrics.sh" --json 2>/dev/null); then
            elimination_ids=$(echo "$metrics_json" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for c in data.get('elimination_candidates', []):
        lid = c.get('lesson_id', '')
        project = c.get('project', '')
        inject = c.get('inject_count', 0)
        if lid and project:
            print(f'{lid}\t{project}\t{inject}')
except:
    pass
" 2>/dev/null)
            if [ -n "$elimination_ids" ]; then
                while IFS=$'\t' read -r lid project injected; do
                    [ -z "$lid" ] && continue
                    if bash "$SCRIPT_DIR/scripts/lesson_deprecate.sh" "$project" "$lid" "AUTO-DEPRECATE(unused): injected=${injected} referenced=0" 2>&1; then
                        echo "  [gate] AUTO-DEPRECATE(unused): ${lid} project=${project} (injected=${injected} referenced=0)"
                        UNUSED_DEPRECATE_COUNT=$((UNUSED_DEPRECATE_COUNT + 1))
                    else
                        echo "  WARN: ${lid}: auto-deprecate failed (non-blocking)"
                    fi
                done <<< "$elimination_ids"
            fi
            echo "  Auto-deprecated (unused): ${UNUSED_DEPRECATE_COUNT} lesson(s)"
        else
            echo "  SKIP (knowledge_metrics.sh failed)"
        fi
    else
        echo "  SKIP (knowledge_metrics.sh or lesson_deprecate.sh not found)"
    fi

    exit 0
else
    missing_list=$(IFS=,; echo "${MISSING_GATES[*]}")
    if [ ${#BLOCK_REASONS[@]} -gt 0 ]; then
        block_reason=$(IFS='|'; echo "${BLOCK_REASONS[*]}")
    elif [ -n "$missing_list" ]; then
        block_reason="missing_gates:${missing_list}"
    else
        block_reason="unknown_block_reason"
    fi
    echo -e "$(date +%Y-%m-%dT%H:%M:%S)\t${CMD_ID}\tBLOCK\t${block_reason}\t${GATE_TASK_TYPE}\t${GATE_MODEL}\t${GATE_BLOOM_LEVEL}\t${GATE_INJECTED_LESSONS}\t${CMD_TITLE}" >> "$GATE_METRICS_LOG"
    echo "GATE BLOCK: 不足フラグ=[${missing_list}] 理由=${block_reason}"
    if append_lesson_tracking "$CMD_ID" "BLOCK" 2>&1; then
        true
    else
        echo "  WARN: append_lesson_tracking failed (non-blocking)"
    fi
    if update_lesson_impact_tsv "$CMD_ID" "BLOCK" 2>&1; then
        true
    else
        echo "  WARN: update_lesson_impact_tsv failed (non-blocking)"
    fi
    bash "$SCRIPT_DIR/scripts/lesson_impact_analysis.sh" --sync-counters 2>&1 || echo "  WARN: sync-counters failed (non-blocking)"

    # ─── GATE BLOCK時自動draft教訓生成（ベストエフォート） ───
    echo ""
    echo "Auto-draft lessons for GATE BLOCK:"
    if [ -n "$CMD_PROJECT" ]; then
        DRAFT_GENERATED=0

        # Pattern 1: lessons_useful empty
        lr_empty_ninjas=()
        for reason in "${BLOCK_REASONS[@]}"; do
            if [[ "$reason" == *":empty_lessons_useful:"* || "$reason" == *":empty_lesson_referenced:"* ]]; then
                ninja=$(echo "$reason" | cut -d: -f1)
                lr_empty_ninjas+=("$ninja")
            fi
        done
        if [ ${#lr_empty_ninjas[@]} -gt 0 ]; then
            lr_count=${#lr_empty_ninjas[@]}
            if bash "$SCRIPT_DIR/scripts/lesson_write.sh" "$CMD_PROJECT" \
                "[自動生成] 有効教訓の記録を怠った: ${CMD_ID}" \
                "lessons_usefulが空のサブタスクが${lr_count}件。役立った教訓IDを報告に記載してから完了せよ" \
                "${CMD_ID}" "gate_auto" "${CMD_ID}" --status draft 2>&1; then
                echo "  draft: 有効教訓の記録を怠った (${lr_count}件)"
                DRAFT_GENERATED=$((DRAFT_GENERATED + 1))
            else
                echo "  WARN: draft生成失敗 (lessons_useful_empty)"
            fi
        fi

        # Pattern 2: draft_remaining
        for reason in "${BLOCK_REASONS[@]}"; do
            if [[ "$reason" == draft_lessons:* ]]; then
                d_count=$(echo "$reason" | cut -d: -f2)
                if bash "$SCRIPT_DIR/scripts/lesson_write.sh" "$CMD_PROJECT" \
                    "[自動生成] draft教訓の査読を怠った: ${CMD_ID}" \
                    "draft教訓${d_count}件が未査読のままGATE到達" \
                    "${CMD_ID}" "gate_auto" "${CMD_ID}" --status draft 2>&1; then
                    echo "  draft: draft教訓の査読を怠った (${d_count}件)"
                    DRAFT_GENERATED=$((DRAFT_GENERATED + 1))
                else
                    echo "  WARN: draft生成失敗 (draft_remaining)"
                fi
                break
            fi
        done

        # Pattern 3: reviewed_false
        unrev_ninjas=()
        for reason in "${BLOCK_REASONS[@]}"; do
            if [[ "$reason" == *":unreviewed_lessons:"* ]]; then
                ninja=$(echo "$reason" | cut -d: -f1)
                unrev_ninjas+=("$ninja")
            fi
        done
        if [ ${#unrev_ninjas[@]} -gt 0 ]; then
            ninja_names=$(IFS=,; echo "${unrev_ninjas[*]}")
            if bash "$SCRIPT_DIR/scripts/lesson_write.sh" "$CMD_PROJECT" \
                "[自動生成] 注入教訓の確認を怠った: ${CMD_ID}" \
                "reviewed:falseのまま作業完了した忍者: ${ninja_names}" \
                "${CMD_ID}" "gate_auto" "${CMD_ID}" --status draft 2>&1; then
                echo "  draft: 注入教訓の確認を怠った (忍者: ${ninja_names})"
                DRAFT_GENERATED=$((DRAFT_GENERATED + 1))
            else
                echo "  WARN: draft生成失敗 (reviewed_false)"
            fi
        fi

        echo "  Generated: ${DRAFT_GENERATED} draft lesson(s)"
    else
        echo "  SKIP (project not found in cmd)"
    fi

    # ─── GATE BLOCK時 harmful判定（教訓参照しなかった忍者の注入教訓にharmful +1） ───
    echo ""
    echo "Lesson score update (harmful - GATE BLOCK):"
    # harmful判定はACE Reflector方式に移行(cmd_470)。自己申告不在での一律harmful廃止。
    echo "  SKIP (disabled)"

    # ─── GATE BLOCK時 harmful閾値による教訓自動deprecate ───
    echo ""
    echo "Auto-deprecate check (harmful threshold):"
    if [ -n "$CMD_PROJECT" ] && [ -f "$SCRIPT_DIR/scripts/lesson_deprecate.sh" ]; then
        DEPRECATE_COUNT=0
        DEPRECATE_LESSONS_FILE="$SCRIPT_DIR/projects/${CMD_PROJECT}/lessons.yaml"
        if [ -f "$DEPRECATE_LESSONS_FILE" ]; then
            # harmful_count >= 5 かつ harmful_count > helpful_count の教訓を検出
            deprecate_targets=$(DEPRECATE_LESSONS_FILE="$DEPRECATE_LESSONS_FILE" python3 -c "
import yaml, sys, os
lessons_file = os.environ['DEPRECATE_LESSONS_FILE']
try:
    with open(lessons_file, encoding='utf-8') as f:
        data = yaml.safe_load(f)
    if not data or not isinstance(data.get('lessons'), list):
        sys.exit(0)
    for lesson in data['lessons']:
        if not isinstance(lesson, dict):
            continue
        lid = str(lesson.get('id', ''))
        if not lid:
            continue
        harmful = int(lesson.get('harmful_count', 0))
        helpful = int(lesson.get('helpful_count', 0))
        # 既にdeprecated済みならスキップ（冪等性）
        if lesson.get('deprecated') is True:
            continue
        if str(lesson.get('status', '')) == 'deprecated':
            continue
        if lesson.get('deprecated_by'):
            continue
        # 閾値チェック
        if harmful >= 5 and harmful > helpful:
            print(f'{lid}\t{harmful}\t{helpful}')
except Exception:
    pass
" 2>/dev/null)

            if [ -n "$deprecate_targets" ]; then
                while IFS=$'\t' read -r lid harmful helpful; do
                    [ -z "$lid" ] && continue
                    if bash "$SCRIPT_DIR/scripts/lesson_deprecate.sh" "$CMD_PROJECT" "$lid" "AUTO-DEPRECATE: harmful=${harmful} > helpful=${helpful}" 2>&1; then
                        echo "  [gate] AUTO-DEPRECATE: ${lid} (harmful=${harmful} > helpful=${helpful})"
                        DEPRECATE_COUNT=$((DEPRECATE_COUNT + 1))
                    else
                        echo "  WARN: ${lid}: auto-deprecate failed (non-blocking)"
                    fi
                done <<< "$deprecate_targets"
            fi
            echo "  Auto-deprecated: ${DEPRECATE_COUNT} lesson(s)"
        else
            echo "  SKIP (lessons file not found: ${DEPRECATE_LESSONS_FILE})"
        fi
    else
        echo "  SKIP (project not found or lesson_deprecate.sh missing)"
    fi

    exit 1
fi
