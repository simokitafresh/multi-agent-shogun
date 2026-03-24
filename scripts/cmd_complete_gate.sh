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

# --force フラグ検出
FORCE_MODE=false
for arg in "$@"; do
    if [ "$arg" = "--force" ]; then
        FORCE_MODE=true
    fi
done

GATES_DIR="$SCRIPT_DIR/queue/gates/${CMD_ID}"
YAML_FILE="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
TASKS_DIR="$SCRIPT_DIR/queue/tasks"
LOG_DIR="$SCRIPT_DIR/logs"
GATE_METRICS_LOG="$LOG_DIR/gate_metrics.log"
mkdir -p "$GATES_DIR" "$LOG_DIR"

# ─── CLEAR済みcmd早期exit（GP-026 B案: cmd_1332） ───
# gate_metrics.logに当該cmd_idのCLEAR記録があれば再検査をスキップ
if [ "$FORCE_MODE" = false ] && [ -f "$GATE_METRICS_LOG" ]; then
    if grep -qP "^[^\t]+\t${CMD_ID}\tCLEAR\t" "$GATE_METRICS_LOG"; then
        echo "[gate] ${CMD_ID}: Already CLEARED (gate_metrics.logにCLEAR記録あり。--forceで再検査可能)"
        exit 0
    fi
fi

# ─── 報告YAML解決関数（L085: 新命名規則対応、cmd_410: report_filename最優先） ───
# 優先順位: 1. タスクYAMLのreport_filename  2. 新形式  3. 旧形式
resolve_report_file() {
    local ninja="$1"
    local cmd="${2:-$CMD_ID}"
    local explicit_path
    local report_parent

    auto_unwrap_report_yaml() {
        local report_file="$1"
        local unwrap_result
        local report_lock="${report_file}.lock"

        [ -f "$report_file" ] || return 0

        unwrap_result=$(
            (
                flock -w 5 200 || { echo "flock_timeout"; exit 0; }
                REPORT_FILE="$report_file" python3 - <<'PY'
import os
import tempfile
import yaml

report_file = os.environ["REPORT_FILE"]

try:
    with open(report_file, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    print("parse_error")
    raise SystemExit(0)

if not isinstance(data, dict):
    print("skip")
    raise SystemExit(0)

if len(data) == 1 and "report" in data and isinstance(data.get("report"), dict):
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(report_file), suffix=".tmp")
    os.close(tmp_fd)
    try:
        with open(tmp_path, "w", encoding="utf-8") as f:
            yaml.safe_dump(data["report"], f, allow_unicode=True, sort_keys=False)
        os.replace(tmp_path, report_file)
        print("unwrapped")
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
else:
    print("skip")
PY
            ) 200>"$report_lock"
        )

        case "$unwrap_result" in
            unwrapped)
                echo "[gate] report YAML auto-unwrapped: ${report_file}" >&2
                ;;
            parse_error)
                echo "[gate] WARN: report YAML parse failed during auto-unwrapping: ${report_file}" >&2
                ;;
            flock_timeout)
                echo "[gate] WARN: report YAML unwrap flock timeout: ${report_file}" >&2
                ;;
        esac
    }

    # 1. タスクYAMLのreport_filenameを参照(最優先)
    local task_yaml="$TASKS_DIR/${ninja}.yaml"
    if [ -f "$task_yaml" ]; then
        local explicit
        explicit=$(grep 'report_filename:' "$task_yaml" | head -1 | sed 's/.*report_filename:[[:space:]]*//' | tr -d "'" | tr -d '"')
        explicit_path="$SCRIPT_DIR/queue/reports/$explicit"
        if [ -n "$explicit" ] && [ -f "$explicit_path" ]; then
            auto_unwrap_report_yaml "$explicit_path"
            echo "$explicit_path"
            return
        fi
    fi
    # 2. 新形式 (既存)
    local new_fmt="$SCRIPT_DIR/queue/reports/${ninja}_report_${cmd}.yaml"
    # 3. 旧形式フォールバック（安全化: parent_cmd一致チェック）
    local old_fmt="$SCRIPT_DIR/queue/reports/${ninja}_report.yaml"
    [ -f "$new_fmt" ] && auto_unwrap_report_yaml "$new_fmt"
    [ -f "$old_fmt" ] && auto_unwrap_report_yaml "$old_fmt"
    if [ -f "$new_fmt" ]; then
        echo "$new_fmt"
    elif [ -f "$old_fmt" ]; then
        # parent_cmd一致チェック（旧報告の誤採用防止）
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

LAST_GATE_NOTIFY_ROUTE=""

send_high_notification() {
    local message="$1"
    LAST_GATE_NOTIFY_ROUTE="ntfy.sh"
    bash "$SCRIPT_DIR/scripts/ntfy.sh" "$message"
}

send_info_cmd_notification() {
    local cmd_id="$1"
    local message="$2"
    local batch_script="$SCRIPT_DIR/scripts/ntfy_batch.sh"

    if [ -x "$batch_script" ]; then
        LAST_GATE_NOTIFY_ROUTE="ntfy_batch.sh"
        bash "$batch_script" "$cmd_id" "$message"
    else
        LAST_GATE_NOTIFY_ROUTE="ntfy_cmd.sh"
        bash "$SCRIPT_DIR/scripts/ntfy_cmd.sh" "$cmd_id" "$message"
    fi
}

# ─── status自動更新関数 ───
update_status() {
    local cmd_id="$1"
    local current_status
    current_status=$(CMD_ID_ENV="$cmd_id" YAML_FILE_ENV="$YAML_FILE" python3 -c "
import yaml, os, sys
cmd_id = os.environ['CMD_ID_ENV']
yaml_file = os.environ['YAML_FILE_ENV']
try:
    with open(yaml_file) as f:
        data = yaml.safe_load(f)
    if not data:
        sys.exit(0)
    entries = data if isinstance(data, list) else data.get('commands', data.get('cmds', []))
    if not isinstance(entries, list):
        sys.exit(0)
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        if entry.get('id') == cmd_id:
            print(entry.get('status', ''))
            break
except Exception as e:
    print(f'parse_error: {e}', file=sys.stderr)
" 2>/dev/null || true)

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
        /^[ ]*- id:/ { line=$0; sub(/^[ ]*- id: */, "", line); gsub(/[" \t]/, "", line); if (line == cmd) { found=1; next } if (found) exit }
        found && /^[ ]*purpose:/ { sub(/^[ ]*purpose: *"?/, ""); sub(/"$/, ""); print; exit }
    ' "$YAML_FILE")

    local project
    project=$(awk -v cmd="${cmd_id}" '
        /^[ ]*- id:/ { line=$0; sub(/^[ ]*- id: */, "", line); gsub(/[" \t]/, "", line); if (line == cmd) { found=1; next } if (found) exit }
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

# ─── gate_metrics model label helpers ───
agent_pane_target() {
    local agent_name="$1"
    tmux list-panes -t shogun:2 -F '#{session_name}:#{window_index}.#{pane_index}	#{@agent_id}' 2>/dev/null \
        | awk -F '\t' -v agent="$agent_name" '$2==agent {print $1; exit}'
}

normalize_model_label() {
    local raw="$1"
    raw=$(printf '%s' "$raw" | tr -s ' ' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "$raw" ] && return 1
    echo "$raw"
}

encode_model_label_for_tsv() {
    local raw="$1"
    local normalized

    normalized=$(normalize_model_label "$raw" 2>/dev/null || true)
    [ -n "$normalized" ] || return 1
    echo "${normalized// /_}"
}

fallback_model_label_from_settings() {
    local ninja_name="$1"
    local settings_yaml="$SCRIPT_DIR/config/settings.yaml"
    local profiles_yaml="$SCRIPT_DIR/config/cli_profiles.yaml"

    [ -f "$settings_yaml" ] || return 1
    [ -f "$profiles_yaml" ] || return 1

    python3 - "$settings_yaml" "$profiles_yaml" "$ninja_name" <<'PY'
import sys
import yaml

settings_yaml, profiles_yaml, ninja_name = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    with open(settings_yaml, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    raise SystemExit(1)

try:
    with open(profiles_yaml, encoding="utf-8") as f:
        profiles_data = yaml.safe_load(f) or {}
except Exception:
    raise SystemExit(1)

cli = data.get("cli", {}) if isinstance(data, dict) else {}
agents = cli.get("agents", {}) if isinstance(cli, dict) else {}
agent_cfg = agents.get(ninja_name, {})
default_cli = cli.get("default", "claude") if isinstance(cli, dict) else "claude"
effort = str(data.get("effort", "") or "").strip()
profiles = profiles_data.get("profiles", {}) if isinstance(profiles_data, dict) else {}

cli_type = default_cli
model_label = ""
has_explicit_model = False

if isinstance(agent_cfg, str):
    cli_type = agent_cfg.strip() or default_cli
elif isinstance(agent_cfg, dict):
    cli_type = str(agent_cfg.get("type") or default_cli).strip() or default_cli
    model_label = str(agent_cfg.get("model_name") or "").strip()
    has_explicit_model = bool(model_label)

if not model_label:
    profile = profiles.get(cli_type, {}) if isinstance(profiles, dict) else {}
    model_label = str(profile.get("display_name") or cli_type or "").strip()

parts = [model_label]
if effort and has_explicit_model:
    label_words = model_label.split()
    if effort not in label_words:
        parts.append(effort)

raw = " ".join(part for part in parts if part)
print(" ".join(raw.split()))
PY
}

resolve_agent_model_label() {
    local ninja_name="$1"
    local pane_target raw_model normalized

    pane_target=$(agent_pane_target "$ninja_name" 2>/dev/null || true)
    if [ -n "$pane_target" ]; then
        raw_model=$(tmux display-message -t "$pane_target" -p '#{@model_name}' 2>/dev/null || true)
        if [ -n "$raw_model" ] && [ "$raw_model" != '#{@model_name}' ]; then
            normalized=$(normalize_model_label "$raw_model" 2>/dev/null || true)
            if [ -n "$normalized" ]; then
                echo "$normalized"
                return 0
            fi
        fi
    fi

    raw_model=$(fallback_model_label_from_settings "$ninja_name" 2>/dev/null || true)
    normalized=$(normalize_model_label "$raw_model" 2>/dev/null || true)
    if [ -n "$normalized" ]; then
        echo "$normalized"
        return 0
    fi

    return 1
}

# ─── cmd_407: gate_metrics拡張用 — task_type/model/bloom_levelの収集 ───
collect_gate_metrics_extra() {
    local cmd_id="$1"
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

        # model収集: assigned_toのtmux @model_name を優先し、不可時はsettings.yamlへフォールバック
        local ninja_name
        ninja_name=$(field_get "$task_file" "assigned_to" "")
        if [ -n "$ninja_name" ]; then
            local model
            model=$(resolve_agent_model_label "$ninja_name" 2>/dev/null || true)
            model=$(encode_model_label_for_tsv "$model" 2>/dev/null || true)
            [ -z "$model" ] && model="unknown"
            if [[ "$_seen_models" != *"|$model|"* ]]; then
                _seen_models="${_seen_models}|${model}|"
                models_csv="${models_csv:+${models_csv},}${model}"
            fi
        fi
    done

    [ -z "$task_types_csv" ] && task_types_csv="unknown"
    [ -z "$models_csv" ] && models_csv="unknown"
    [ -z "$bloom_levels_csv" ] && bloom_levels_csv="unknown"

    printf '%s\t%s\t%s\n' "${task_types_csv}" "${models_csv}" "${bloom_levels_csv}"
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

# ─── project code stub detection（WARN only, cmd diff added lines only） ───
# cmd_1387: Python→bash/awk化。yaml.safe_load→awk, subprocess→direct git, regex→awk
check_project_code_stubs() {
    local cmd_id="$1"
    local cmd_project="$2"

    # --- Early exit: no project ---
    if [[ -z "$cmd_project" ]]; then
        printf 'SKIP\tproject not found in cmd\n'
        return 0
    fi
    # Strip quotes
    cmd_project="${cmd_project//\'/}"
    cmd_project="${cmd_project//\"/}"

    # --- resolve_project_path (awk on YAML, no python/yaml.safe_load) ---
    local project_path=""
    local pj_yaml="$SCRIPT_DIR/projects/${cmd_project}.yaml"
    if [[ -f "$pj_yaml" ]]; then
        # Try project.path first, then top-level path
        project_path=$(awk '
            /^project:/ { in_proj=1; next }
            in_proj && /^  path:/ { $1=""; gsub(/^[[:space:]]+|[[:space:]]+$|["'"'"']/, ""); print; exit }
            in_proj && /^[^ ]/ { in_proj=0 }
            !in_proj && /^path:/ { $1=""; gsub(/^[[:space:]]+|[[:space:]]+$|["'"'"']/, ""); print; exit }
        ' "$pj_yaml")
    fi
    if [[ -z "$project_path" ]]; then
        local config_yaml="$SCRIPT_DIR/config/projects.yaml"
        if [[ -f "$config_yaml" ]]; then
            project_path=$(awk -v target="$cmd_project" '
                /^  - id:/ { cur=$3; gsub(/["'"'"']/, "", cur) }
                /^    path:/ && cur == target { $1=""; gsub(/^[[:space:]]+|[[:space:]]+$|["'"'"']/, ""); print; exit }
            ' "$config_yaml")
        fi
    fi

    if [[ -z "$project_path" ]]; then
        printf 'SKIP\tproject path not found for: %s\n' "$cmd_project"
        return 0
    fi
    if [[ ! -d "$project_path" ]]; then
        printf 'SKIP\tproject path missing: %s\n' "$project_path"
        return 0
    fi
    if ! git -C "$project_path" rev-parse --git-dir >/dev/null 2>&1; then
        printf 'SKIP\tgit repo not found: %s\n' "$project_path"
        return 0
    fi

    # --- cmd_1244: uncommitted変更検出 — commit漏れをBLOCKで構造的に防止 ---
    local uncommitted
    uncommitted=$({ git -C "$project_path" diff --name-only 2>/dev/null; git -C "$project_path" diff --cached --name-only 2>/dev/null; } | sed '/^$/d')
    if [[ -n "$uncommitted" ]]; then
        local ucount
        ucount=$(printf '%s\n' "$uncommitted" | wc -l)
        printf 'BLOCK\tcommit_missing: %d uncommitted file(s) in %s\n' "$ucount" "$project_path"
        printf '%s\n' "$uncommitted" | head -10
        return 1
    fi

    # --- detect_cmd_commit_count (git log + awk, no python subprocess) ---
    local log_output
    log_output=$(git -C "$project_path" log --format="%H%x1f%s%x1f%b%x1e" -n 100 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        printf 'ERR\tgit log failed for %s\n' "$project_path"
        return 0
    fi

    local commit_count
    commit_count=$(printf '%s' "$log_output" | awk -F'\x1f' -v cmd="$cmd_id" '
        BEGIN { RS="\x1e"; count=0; started=0 }
        {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            if ($0 == "") next
            haystack = $2 "\n" $3
            if (index(haystack, cmd) > 0) {
                count++
                started=1
            } else if (started) {
                exit
            }
        }
        END { print count }
    ')

    if [[ "$commit_count" -le 0 ]]; then
        printf 'SKIP\tno contiguous HEAD commits mention %s in %s\n' "$cmd_id" "$project_path"
        return 0
    fi

    local base_ref="HEAD~${commit_count}"
    if ! git -C "$project_path" rev-parse --verify "$base_ref" >/dev/null 2>&1; then
        printf 'SKIP\t%s not available in %s\n' "$base_ref" "$project_path"
        return 0
    fi

    # --- resolve_extensions (awk on YAML) ---
    local raw_langs=""
    if [[ -f "$pj_yaml" ]]; then
        # Try top-level languages: then project.languages:
        raw_langs=$(awk '
            /^languages:/ { found=1; next }
            found && /^  *- / { val=$2; gsub(/["'"'"']/, "", val); gsub(/^\./, "", val); print tolower(val); next }
            found && /^[^ ]/ { exit }
        ' "$pj_yaml")
        if [[ -z "$raw_langs" ]]; then
            raw_langs=$(awk '
                /^project:/ { in_proj=1; next }
                in_proj && /^[^ ]/ { exit }
                in_proj && /^  languages:/ { found=1; next }
                found && /^    *- / { val=$2; gsub(/["'"'"']/, "", val); gsub(/^\./, "", val); print tolower(val); next }
                found && !/^    / { exit }
            ' "$pj_yaml")
        fi
    fi

    # Map language aliases → file extensions
    local exts_str=""
    if [[ -n "$raw_langs" ]]; then
        exts_str=$(printf '%s\n' "$raw_langs" | while IFS= read -r lang; do
            case "$lang" in
                python)     echo "py" ;;
                typescript) echo "ts"; echo "tsx" ;;
                javascript) echo "js"; echo "jsx" ;;
                kotlin)     echo "kt" ;;
                py|ts|tsx|js|jsx|kt|java) echo "$lang" ;;
                *)          echo "$lang" ;;
            esac
        done | sort -u | paste -sd, -)
    fi
    if [[ -z "$exts_str" ]]; then
        exts_str="java,js,jsx,kt,py,ts,tsx"
    fi

    # --- Diff parsing + stub detection (single awk pass, no python) ---
    local diff_output diff_rc
    diff_output=$(git -C "$project_path" diff --unified=1 --no-color "$base_ref" HEAD -- . 2>&1)
    diff_rc=$?
    if [[ $diff_rc -ne 0 ]]; then
        printf 'ERR\tgit diff failed for %s: %s\n' "$project_path" "$(printf '%s\n' "$diff_output" | head -1)"
        return 0
    fi

    local awk_result
    awk_result=$(printf '%s\n' "$diff_output" | gawk -v exts="$exts_str" -v max_show=10 '
        BEGIN {
            matches = 0; file_count = 0
            n = split(exts, ea, ",")
            for (i = 1; i <= n; i++) ext_set[ea[i]] = 1
        }

        /^\+\+\+ b\// {
            file = substr($0, 7)
            # Extract extension: last dot-delimited segment
            ext = ""
            if (match(file, /\.([^.\/]+)$/, m)) ext = tolower(m[1])
            last_sig = ""
            next
        }

        /^@@/ {
            # Extract +lineno from hunk header
            if (match($0, /\+([0-9]+)/, m))
                lineno = m[1] - 1
            else
                lineno = 0
            last_sig = ""
            next
        }

        # Skip if no file tracked or extension not in allowed set
        file == "" || !(ext in ext_set) { next }

        # Skip deletion lines
        /^-/ && !/^---/ { next }

        # Context lines (space prefix)
        /^ / {
            lineno++
            content = substr($0, 2)
            stripped = content
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", stripped)
            if (stripped != "" && substr(stripped, 1, 1) != "#")
                last_sig = stripped
            next
        }

        # Blank lines in diff (no prefix)
        /^$/ { next }

        # Added lines
        /^\+/ && !/^\+\+\+/ {
            lineno++
            line = substr($0, 2)
            trimmed = line
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", trimmed)

            # --- return_stub: return null/None/{}/[] ---
            if (match(line, /(^|[^a-zA-Z0-9_])return[[:space:]]+(null|None)([^a-zA-Z0-9_]|$)/) ||
                match(line, /(^|[^a-zA-Z0-9_])return[[:space:]]*\{[[:space:]]*\}/) ||
                match(line, /(^|[^a-zA-Z0-9_])return[[:space:]]*\[[[:space:]]*\]/)) {
                if (matches < max_show)
                    details[matches] = file ":" lineno ": [return_stub] " trimmed
                matches++
                if (!(file in seen)) { seen[file] = 1; file_count++ }
            }

            # --- marker_stub: TODO/FIXME/XXX/HACK/PLACEHOLDER (not in test/spec files) ---
            upper_line = toupper(line)
            if (match(upper_line, /(^|[^A-Z0-9_])(TODO|FIXME|XXX|HACK|PLACEHOLDER)([^A-Z0-9_]|$)/)) {
                lower_file = tolower(file)
                if (index(lower_file, "test") == 0 && index(lower_file, "spec") == 0) {
                    if (matches < max_show)
                        details[matches] = file ":" lineno ": [marker_stub] " trimmed
                    matches++
                    if (!(file in seen)) { seen[file] = 1; file_count++ }
                }
            }

            # --- pass_stub: bare pass in Python (except:pass is allowed) ---
            if (ext == "py" && match(line, /^[[:space:]]*pass([[:space:]]*#.*)?[[:space:]]*$/)) {
                allowed = 0
                # Check if last significant line is an except line
                if (last_sig != "" && match(last_sig, /^except([[:space:]]|[:(])/)) {
                    if (index(last_sig, ":") > 0) allowed = 1
                }
                if (!allowed) {
                    if (matches < max_show)
                        details[matches] = file ":" lineno ": [pass_stub] " trimmed
                    matches++
                    if (!(file in seen)) { seen[file] = 1; file_count++ }
                }
            }

            # Update last significant line for except:pass tracking
            if (trimmed != "" && substr(trimmed, 1, 1) != "#")
                last_sig = trimmed
        }

        END {
            if (matches == 0) {
                print "0"
            } else {
                printf "%d %d\n", matches, file_count
                for (i = 0; i < matches && i < max_show; i++)
                    print details[i]
                if (matches > max_show)
                    printf "... (%d hits across %d file(s), first %d shown)\n", matches, file_count, max_show
            }
        }
    ')

    if [[ "$awk_result" == "0" ]]; then
        printf 'OK\tno stub patterns in added lines (base=%s, commits=%d, ext=%s)\n' \
            "$base_ref" "$commit_count" "$exts_str"
    else
        local match_count file_count_out
        match_count=$(printf '%s\n' "$awk_result" | head -1 | cut -d' ' -f1)
        file_count_out=$(printf '%s\n' "$awk_result" | head -1 | cut -d' ' -f2)
        printf 'WARN\t%d stub-like added line(s) across %d file(s) (base=%s, commits=%d)\n' \
            "$match_count" "$file_count_out" "$base_ref" "$commit_count"
        printf '%s\n' "$awk_result" | tail -n +2
    fi
}

# ─── wiring verification（WARN only, existence != integration） ───
check_script_wiring() {
    local cmd_id="$1"

    SCRIPT_DIR_ENV="$SCRIPT_DIR" CMD_ID_ENV="$cmd_id" python3 - <<'PY'
import os
import re
import subprocess

script_dir = os.environ["SCRIPT_DIR_ENV"]
cmd_id = os.environ["CMD_ID_ENV"].strip()
PATH_RE = re.compile(r"(?<![A-Za-z0-9_./-])(scripts/[A-Za-z0-9._/-]+\.sh)(?![A-Za-z0-9_./-])")


def emit(row_type: str, scope: str, status: str, message: str) -> None:
    print(f"{row_type}\t{scope}\t{status}\t{message}")


def git(repo_path: str, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", repo_path, *args],
        text=True,
        capture_output=True,
        check=False,
    )


def detect_cmd_commit_count(repo_path: str, target_cmd_id: str) -> int:
    log_proc = git(repo_path, "log", "--format=%H%x1f%s%x1f%b%x1e", "-n", "100")
    if log_proc.returncode != 0:
        return -1

    count = 0
    for record in log_proc.stdout.split("\x1e"):
        record = record.strip()
        if not record:
            continue
        parts = record.split("\x1f", 2)
        if len(parts) != 3:
            continue
        _commit_hash, subject, body = parts
        haystack = f"{subject}\n{body}"
        if target_cmd_id in haystack:
            count += 1
        elif count > 0:
            break

    return count


def is_script_target(rel_path: str) -> bool:
    return rel_path.startswith("scripts/") and rel_path.endswith(".sh")


def read_text(path: str) -> str:
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def collect_reference_files() -> tuple[list[tuple[str, str]], list[tuple[str, str]]]:
    forward_candidates: list[tuple[str, str]] = []
    reverse_candidates: list[tuple[str, str]] = []

    for root, _dirs, files in os.walk(script_dir):
        files.sort()
        for filename in files:
            rel_path = os.path.relpath(os.path.join(root, filename), script_dir).replace(os.sep, "/")
            abs_path = os.path.join(root, filename)
            if rel_path == "CLAUDE.md":
                forward_candidates.append((rel_path, abs_path))
                reverse_candidates.append((rel_path, abs_path))
                continue
            if rel_path.startswith("instructions/") and rel_path.endswith(".md"):
                forward_candidates.append((rel_path, abs_path))
                reverse_candidates.append((rel_path, abs_path))
                continue
            if is_script_target(rel_path):
                forward_candidates.append((rel_path, abs_path))

    forward_candidates.sort()
    reverse_candidates.sort()
    return forward_candidates, reverse_candidates


forward_candidates, reverse_candidates = collect_reference_files()
commit_count = detect_cmd_commit_count(script_dir, cmd_id)
if commit_count < 0:
    emit("CHECK", "FORWARD", "WARN", "git log failed while resolving cmd diff")
elif commit_count == 0:
    emit("CHECK", "FORWARD", "SKIP", f"no contiguous HEAD commits mention {cmd_id}")
else:
    base_ref = f"HEAD~{commit_count}"
    base_check = git(script_dir, "rev-parse", "--verify", base_ref)
    if base_check.returncode != 0:
        emit("CHECK", "FORWARD", "SKIP", f"{base_ref} not available")
    else:
        diff_proc = git(script_dir, "diff", "--name-status", "--find-renames", base_ref, "HEAD", "--")
        if diff_proc.returncode != 0:
            emit("CHECK", "FORWARD", "WARN", f"git diff failed: {diff_proc.stderr.strip()}")
        else:
            added_scripts: list[str] = []
            for raw in diff_proc.stdout.splitlines():
                if not raw.strip():
                    continue
                parts = raw.split("\t")
                if len(parts) < 2:
                    continue
                status = parts[0]
                rel_path = parts[-1].strip()
                if not status.startswith("A"):
                    continue
                if is_script_target(rel_path):
                    added_scripts.append(rel_path)

            added_scripts = sorted(dict.fromkeys(added_scripts))
            if not added_scripts:
                emit("CHECK", "FORWARD", "OK", f"no new scripts/*.sh in cmd diff (base={base_ref}, commits={commit_count})")
            else:
                unreferenced: list[str] = []
                for rel_path in added_scripts:
                    references: list[str] = []
                    for candidate_rel, candidate_abs in forward_candidates:
                        if candidate_rel == rel_path:
                            continue
                        try:
                            content = read_text(candidate_abs)
                        except OSError:
                            continue
                        if rel_path in content:
                            references.append(candidate_rel)
                    if not references:
                        unreferenced.append(rel_path)

                if unreferenced:
                    emit(
                        "CHECK",
                        "FORWARD",
                        "WARN",
                        f"{len(unreferenced)} new scripts/*.sh file(s) have no references in instructions/*.md, CLAUDE.md, or other scripts/*.sh",
                    )
                    for rel_path in unreferenced:
                        emit("DETAIL", "FORWARD", "-", rel_path)
                else:
                    emit(
                        "CHECK",
                        "FORWARD",
                        "OK",
                        f"all {len(added_scripts)} new scripts/*.sh file(s) are referenced (base={base_ref}, commits={commit_count})",
                    )

references: dict[str, set[str]] = {}
for candidate_rel, candidate_abs in reverse_candidates:
    try:
        content = read_text(candidate_abs)
    except OSError:
        continue
    for match in PATH_RE.findall(content):
        if not is_script_target(match):
            continue
        references.setdefault(match, set()).add(candidate_rel)

missing_refs: list[tuple[str, list[str]]] = []
for rel_path, sources in sorted(references.items()):
    if os.path.isfile(os.path.join(script_dir, rel_path)):
        continue
    missing_refs.append((rel_path, sorted(sources)))

if missing_refs:
    emit("CHECK", "REVERSE", "WARN", f"{len(missing_refs)} referenced scripts/*.sh path(s) do not exist")
    for rel_path, sources in missing_refs:
        emit("DETAIL", "REVERSE", "-", f"{rel_path} <- {', '.join(sources)}")
else:
    emit("CHECK", "REVERSE", "OK", f"all {len(references)} referenced scripts/*.sh path(s) exist")
PY
}

# ─── lesson tracking追記（ベストエフォート） ───
append_lesson_tracking() {
    local cmd_id="$1"
    local gate_result="$2"
    local tracking_file="$LOG_DIR/lesson_tracking.tsv"
    local parsed ninja injected_ids referenced_ids timestamp

    parsed=$(python3 - "$TASKS_DIR" "$SCRIPT_DIR/queue/reports" "$cmd_id" <<'PY'
import glob
import os
import sys
import yaml

tasks_dir = sys.argv[1]
reports_dir = sys.argv[2]
cmd_id = sys.argv[3]
archive_reports_dir = os.path.join(os.path.dirname(reports_dir), "archive", "reports")

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

# Primary: extract ninja/injected/task_type from task files
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

# Fallback: when task files are already idle/reassigned, extract from report filenames
if not ninjas:
    for search_dir in [reports_dir, archive_reports_dir]:
        if not os.path.isdir(search_dir):
            continue
        for rpath in sorted(glob.glob(os.path.join(search_dir, f"*_report_{cmd_id}*.yaml"))):
            bname = os.path.basename(rpath)
            if bname.endswith(".lock"):
                continue
            idx = bname.find(f"_report_{cmd_id}")
            if idx > 0:
                add_unique(ninjas, bname[:idx])
            if not task_types:
                try:
                    with open(rpath, encoding="utf-8") as rf:
                        rdata = yaml.safe_load(rf) or {}
                    if isinstance(rdata, dict):
                        rtid = rdata.get("task_id", "")
                        if rtid:
                            add_unique(task_types, detect_task_type(rtid))
                except Exception:
                    pass

def find_report(ninja_name):
    """Find report file in reports_dir or archive, return path or None."""
    for candidate in [
        os.path.join(reports_dir, f"{ninja_name}_report_{cmd_id}.yaml"),
        os.path.join(reports_dir, f"{ninja_name}_report.yaml"),
    ]:
        if os.path.exists(candidate):
            return candidate
    if os.path.isdir(archive_reports_dir):
        matches = sorted(glob.glob(
            os.path.join(archive_reports_dir, f"{ninja_name}_report_{cmd_id}*.yaml")))
        for m in matches:
            if not m.endswith(".lock"):
                return m
    return None

for ninja in ninjas:
    report_path = find_report(ninja)
    if not report_path:
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
tracked_row_ids = []
referenced_ids = []
referenced_by_row_id = {}

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

    task_row_ids = []
    for key in ("task_id", "subtask_id", "parent_cmd"):
        add_unique(task_row_ids, task.get(key))

    for row_id in task_row_ids:
        add_unique(tracked_row_ids, row_id)
        referenced_by_row_id.setdefault(row_id, [])

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
    report_refs = []
    lessons_useful = report.get("lessons_useful")
    if lessons_useful is None:
        # Backward compatibility for legacy report field.
        lessons_useful = report.get("lesson_referenced")
    if isinstance(lessons_useful, list):
        for item in lessons_useful:
            if isinstance(item, dict):
                add_unique(report_refs, item.get("id"))
            else:
                add_unique(report_refs, item)

    for ref_id in report_refs:
        add_unique(referenced_ids, ref_id)

    task = ninja_tasks.get(ninja, {})
    task_row_ids = []
    for key in ("task_id", "subtask_id", "parent_cmd"):
        add_unique(task_row_ids, task.get(key))
    for row_id in task_row_ids:
        row_refs = referenced_by_row_id.setdefault(row_id, [])
        for ref_id in report_refs:
            add_unique(row_refs, ref_id)

if not tracked_row_ids:
    tracked_row_ids.append(cmd_id)
    referenced_by_row_id.setdefault(cmd_id, [])

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
        row_cmd_id = (row.get("cmd_id") or "").strip()
        matched = row_cmd_id in tracked_row_ids
        if not matched:
            for tid in tracked_row_ids:
                if row_cmd_id.startswith(tid + "_"):
                    matched = True
                    break
        if matched and row.get("result") == "pending":
            row["result"] = gate_result
            if row.get("action") != "withheld":
                row_refs = referenced_by_row_id.get(row_cmd_id, referenced_ids)
                row["referenced"] = "yes" if row.get("lesson_id") in row_refs else "no"
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

level_heading() {
    local level="$1"
    local title="$2"
    echo ""
    echo "${level} ${title}"
}

detect_task_role() {
    local task_file="$1"

    local tokens="" val
    for key in task_type type task_id subtask_id; do
        val=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "$key" "")
        [ -n "$val" ] && tokens="$tokens $(printf '%s' "$val" | tr '[:upper:]' '[:lower:]')"
    done

    case "$tokens" in
        *review*) echo "review" ;;
        *implement*|*impl*) echo "implement" ;;
        *recon*|*scout*) echo "recon" ;;
        *) echo "unknown" ;;
    esac
}

# Helper: check lesson_candidate.found=true in report YAML (#3,#4共通関数 cmd_1387)
_check_lc_found() {
    local rfile="$1"
    if grep -A5 'lesson_candidate:' "$rfile" 2>/dev/null | grep -q 'found: true'; then
        echo "true"
    else
        echo "false"
    fi
}

check_how_it_works_status() {
    local report_file="$1"

    if [ ! -f "$report_file" ]; then
        echo "error"
        return
    fi

    if ! grep -q 'how_it_works' "$report_file" 2>/dev/null; then
        echo "missing"
        return
    fi

    local value
    value=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "how_it_works" "")
    if [ -z "$value" ]; then
        echo "empty"
    else
        echo "ok"
    fi
}

# ─── context_update freshness check (cmd_543 AC2) ───
# cmdにcontext_updateが定義されている場合のみ、context/* の last_updated を検証。
# last_updated(YYYY-MM-DD) < cmd timestamp/delegated_at の日付 なら BLOCK。
check_context_update() {
    local cmd_id="$1"
    local line kind msg

    level_heading "[L3]" "Context update check:"

    while IFS=$'\t' read -r kind msg; do
        [ -n "$kind" ] || continue
        case "$kind" in
            SKIP)
                echo "  SKIP (${msg})"
                ;;
            INFO)
                echo "  ${msg}"
                ;;
            OK)
                echo "  OK: ${msg}"
                ;;
            WARN)
                echo "  [INFO] ${msg}"
                ;;
            BLOCK)
                echo "  [CRITICAL] NG ← ${msg}"
                record_block_reason "$msg"
                ALL_CLEAR=false
                ;;
            *)
                echo "  [INFO] unexpected check_context_update output: ${kind} ${msg}"
                ;;
        esac
    done < <(
        python3 - "$SCRIPT_DIR" "$cmd_id" <<'PY'
import glob
import os
import re
import sys

import yaml

root = sys.argv[1]
cmd_id = sys.argv[2]

def load_yaml(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = yaml.safe_load(f)
            return data if isinstance(data, dict) else {}
    except Exception:
        return {}

def find_cmd_entry():
    candidates = [os.path.join(root, "queue", "shogun_to_karo.yaml")]
    archived = sorted(
        glob.glob(os.path.join(root, "queue", "archive", "cmds", f"{cmd_id}_*.yaml")),
        reverse=True,
    )
    candidates.extend(archived)

    for path in candidates:
        data = load_yaml(path)
        commands = data.get("commands", [])
        if not isinstance(commands, list):
            continue
        for cmd in commands:
            if isinstance(cmd, dict) and str(cmd.get("id", "")).strip() == cmd_id:
                return cmd, path
    return None, None

cmd, source_path = find_cmd_entry()
if not cmd:
    print("WARN\tcmd entry not found in shogun_to_karo.yaml or queue/archive/cmds")
    sys.exit(0)

context_update = cmd.get("context_update")
if not context_update:
    print("SKIP\tcontext_update not set")
    sys.exit(0)

if isinstance(context_update, str):
    targets = [context_update]
elif isinstance(context_update, list):
    targets = [str(v).strip() for v in context_update if str(v).strip()]
else:
    print("WARN\tcontext_update has invalid type (expected list/string)")
    sys.exit(0)

if not targets:
    print("SKIP\tcontext_update empty")
    sys.exit(0)

cmd_ts = str(cmd.get("timestamp") or cmd.get("delegated_at") or "").strip()
if not cmd_ts:
    print("WARN\tcmd timestamp/delegated_at not found; skipping")
    sys.exit(0)

m = re.search(r"(\d{4}-\d{2}-\d{2})", cmd_ts)
if not m:
    print(f"WARN\tcmd timestamp format unsupported: {cmd_ts}")
    sys.exit(0)

cmd_date = m.group(1)
print(f"INFO\treference_date={cmd_date} source={os.path.basename(source_path)}")

for rel in targets:
    rel = rel.strip()
    if not rel:
        continue
    abs_path = os.path.join(root, rel)
    if not os.path.isfile(abs_path):
        print(f"WARN\t{rel}: file not found (skip)")
        continue

    try:
        with open(abs_path, encoding="utf-8") as f:
            text = f.read()
    except Exception:
        print(f"WARN\t{rel}: cannot read file (skip)")
        continue

    m2 = re.search(r"<!--\s*last_updated:\s*(\d{4}-\d{2}-\d{2})\b", text)
    if not m2:
        print(f"WARN\t{rel}: last_updated comment not found (skip)")
        continue

    last_updated = m2.group(1)
    if last_updated < cmd_date:
        print(
            f"BLOCK\tcontext_update:{rel}:stale (last_updated={last_updated}, cmd={cmd_ts})"
        )
    else:
        print(f"OK\t{rel}: last_updated={last_updated} (cmd={cmd_date})")
PY
    )
}

# ─── preflight: ゲートフラグ未存在時の自動生成（冪等） ───
# GATE BLOCK率65%の主因=missing_gate(archive/lesson/review_gate)を解消。
# gate本体チェック前に、対応するフラグ生成処理を先行実行する。
# 既にフラグが存在する場合は何もしない(冪等)。品質BLOCKは維持。
preflight_gate_flags() {
    local cmd_id="$1"
    local gates_dir="$SCRIPT_DIR/queue/gates/${cmd_id}"
    mkdir -p "$gates_dir"

    echo "[L1] Preflight gate flag generation:"

    # 1. review_gate.done — archiveより先に実行（競合防止: review_gate.done不在時にarchiveがスキップするため）
    local pf_gate pf_needs_review=false
    for pf_gate in "${ALL_GATES[@]}"; do
        [ "$pf_gate" = "review_gate" ] && pf_needs_review=true && break
    done
    if [ "$pf_needs_review" = true ] && [ ! -f "$gates_dir/review_gate.done" ]; then
        echo "  review_gate: generating..."
        if bash "$SCRIPT_DIR/scripts/review_gate.sh" "$cmd_id" 2>&1; then
            echo "  review_gate: preflight OK"
        else
            echo "  [INFO] review_gate: preflight WARN (review may not be complete)"
        fi
    elif [ "$pf_needs_review" = true ]; then
        echo "  review_gate: already exists (skip)"
    fi

    # 2. archive.done — GATE CLEAR後に実行（報告YAMLをGATEが読み終わってからアーカイブ）
    #    cmd_1302: archiveをpreflight→GATE CLEAR後に移動。preflight時点ではスキップ。
    if [ ! -f "$gates_dir/archive.done" ]; then
        echo "  archive: deferred (will run after GATE CLEAR)"
    else
        echo "  archive: already exists (skip)"
    fi

    # 3. lesson.done — found:true候補確認後、適切な方法でフラグ生成
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
                pf_lc_found=$(_check_lc_found "$pf_report_file")
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
                echo "  [INFO] lesson: preflight WARN (lesson_check failed, non-blocking)"
            fi
        fi
    else
        # cmd_407: deploy_preflightで生成済みの場合、found:true検出時にsource upgradeする
        # cmd_536 AC2 fix: else分岐でもfound:trueをスキャンする（has_found_trueスコープ不整合修正）
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
                pf_lc_found=$(_check_lc_found "$pf_report_file")
                [ "$pf_lc_found" = "true" ] && has_found_true=true
            fi
        done
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
                echo "  [INFO] report_merge: preflight WARN (merge may not be ready)"
            fi
        else
            echo "  report_merge: SKIP (script not found)"
        fi
    elif [ "$pf_needs_merge" = true ]; then
        echo "  report_merge: already exists (skip)"
    fi

    # 5. GP-027: target_path未commit変更検出（WARN only、BLOCKしない）
    echo "  target_path uncommitted check:"
    local tp_warn_count=0
    local tp_task_file
    for tp_task_file in "$TASKS_DIR"/*.yaml; do
        [ -f "$tp_task_file" ] || continue
        if ! grep -q "parent_cmd: ${cmd_id}" "$tp_task_file" 2>/dev/null; then
            continue
        fi
        local tp_info
        # task.project と task.target_path を取得
        local _tp_project_id _tp_target_raw _tp_project_path
        _tp_project_id=$(FIELD_GET_NO_LOG=1 field_get "$tp_task_file" "project" "")
        # target_path: string or list
        _tp_target_raw=$(awk '
            /^[[:space:]]+target_path:/ {
                # inline value (string)
                val = $0; sub(/.*target_path:[[:space:]]*/, "", val); gsub(/^["'"'"']+|["'"'"']+$/, "", val)
                if (val != "" && val !~ /^\[/) { print val; exit }
                in_tp = 1; next
            }
            in_tp && /^[[:space:]]+- / { val = $0; sub(/^[[:space:]]+- [[:space:]]*/, "", val); gsub(/^["'"'"']+|["'"'"']+$/, "", val); print val; next }
            in_tp && /^[[:space:]]+[^ -]/ { exit }
            in_tp && /^[^ ]/ { exit }
        ' "$tp_task_file" 2>/dev/null)
        [ -z "$_tp_target_raw" ] && continue
        # resolve project path
        _tp_project_path="$SCRIPT_DIR"
        if [ -n "$_tp_project_id" ] && [ "$_tp_project_id" != "infra" ]; then
            local _tp_pj_file="$SCRIPT_DIR/projects/${_tp_project_id}.yaml"
            if [ -f "$_tp_pj_file" ]; then
                local _tp_resolved
                _tp_resolved=$(awk '
                    /^[[:space:]]*path:/ { v=$0; sub(/.*path:[[:space:]]*/, "", v); gsub(/^["'"'"']+|["'"'"']+$/, "", v); if (v != "") { print v; exit } }
                    /project:/ { sec=1; next }
                    sec && /^[[:space:]]+path:/ { v=$0; sub(/.*path:[[:space:]]*/, "", v); gsub(/^["'"'"']+|["'"'"']+$/, "", v); if (v != "") { print v; exit } }
                    sec && /^[^ ]/ { sec=0 }
                ' "$_tp_pj_file" 2>/dev/null)
                [ -n "$_tp_resolved" ] && _tp_project_path="$_tp_resolved"
            fi
        fi
        tp_info=""
        while IFS= read -r _tp_one; do
            [ -z "$_tp_one" ] && continue
            tp_info="${tp_info}${_tp_project_path}	${_tp_one}
"
        done <<< "$_tp_target_raw"
        [ -z "$tp_info" ] && continue
        while IFS=$'\t' read -r tp_proj_path tp_file; do
            [ -z "$tp_file" ] && continue
            if [ ! -d "$tp_proj_path" ]; then
                continue
            fi
            # Get uncommitted files under target_path (staged + unstaged, deduplicated)
            local tp_uncommitted
            tp_uncommitted=$(cd "$tp_proj_path" && {
                git diff --name-only -- "$tp_file" 2>/dev/null
                git diff --cached --name-only -- "$tp_file" 2>/dev/null
            } | sort -u)
            [ -z "$tp_uncommitted" ] && continue
            # Exclude operational files: logs/, queue/, dashboard.md, *.log
            local tp_filtered
            tp_filtered=$(echo "$tp_uncommitted" | grep -v -E '^logs/|^queue/|^dashboard\.md$|\.log$' || true)
            [ -z "$tp_filtered" ] && continue
            while IFS= read -r tp_uf; do
                echo "    [WARN] uncommitted: $tp_uf"
                tp_warn_count=$((tp_warn_count + 1))
            done <<< "$tp_filtered"
        done <<< "$tp_info"
    done
    if [ "$tp_warn_count" -gt 0 ]; then
        echo "    -> ${tp_warn_count} file(s) with uncommitted changes (WARN, non-blocking)"
        echo "$(date '+%Y-%m-%dT%H:%M:%S') [WARN] ${cmd_id} target_path_uncommitted: ${tp_warn_count} file(s)" >> "$LOG_DIR/gate_fire_log.yaml"
    else
        echo "    all target_path committed (OK)"
    fi

    echo ""
}

# ─── DEFERRED_GATES: gate check loopではスキップし、GATE CLEAR後に実行するgate ───
# cmd_1314: archive gateの循環依存修正。archiveはGATE CLEARに報告YAMLを読み終わってから実行する必要がある。
# gate check loop時点でarchive.doneを要求するとGATE CLEARできない→archiveが走れない→永久BLOCK。
# shellcheck disable=SC2034  # Used in gate check loop (L1858)
DEFERRED_GATES=("archive")

# ─── 必須フラグ構築 ───
ALWAYS_REQUIRED=("archive" "lesson")

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
IFS=$'\t' read -r GATE_TASK_TYPE GATE_MODEL GATE_BLOOM_LEVEL <<< "$(collect_gate_metrics_extra "$CMD_ID")"
GATE_INJECTED_LESSONS="$(collect_injected_lessons "$CMD_ID")"
CMD_TITLE="$(collect_cmd_title "$CMD_ID")"

# ─── cmd_776 B層: 報告YAML自動正規化（auto-draft前に実行） ───
NORMALIZE_LOG="$SCRIPT_DIR/logs/normalize_report.log"
echo "Normalize report candidates (B層):"
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi
    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")
    if [ -f "$report_file" ]; then
        normalize_exit=0
        normalize_output=$(bash "$SCRIPT_DIR/scripts/lib/normalize_report.sh" "$report_file" 2>&1) || normalize_exit=$?
        if [ "$normalize_exit" -eq 0 ]; then
            echo "  [INFO] ${ninja_name}: auto-fixed: ${normalize_output}"
            echo "$(date '+%Y-%m-%dT%H:%M:%S') [B層] ${CMD_ID} ${ninja_name}: ${normalize_output}" >> "$NORMALIZE_LOG"
        elif [ "$normalize_exit" -eq 1 ]; then
            echo "  ${ninja_name}: OK (no normalization needed)"
        else
            echo "  ${ninja_name}: ERROR — normalize_report.sh exit=${normalize_exit}: ${normalize_output}"
        fi
    fi
done
echo ""

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
            echo "  [INFO] auto_draft_lesson.sh failed for ${ninja_name} (non-blocking)"
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
    send_high_notification "🚨 緊急override: ${CMD_ID}のゲートをバイパス"
    # gate_yaml_status: YAML status更新（WARNING only）
    if bash "$SCRIPT_DIR/scripts/gates/gate_yaml_status.sh" "$CMD_ID" 2>&1; then
        true
    else
        echo "  [INFO] gate_yaml_status.sh failed (non-blocking)"
    fi
    update_status "$CMD_ID"
    append_changelog "$CMD_ID"
    echo -e "$(date +%Y-%m-%dT%H:%M:%S)\t${CMD_ID}\tOVERRIDE\temergency_override\t${GATE_TASK_TYPE}\t${GATE_MODEL}\t${GATE_BLOOM_LEVEL}\t${GATE_INJECTED_LESSONS}\t${CMD_TITLE}" >> "$GATE_METRICS_LOG"
    if append_lesson_tracking "$CMD_ID" "OVERRIDE" 2>&1; then
        true
    else
        echo "  [INFO] append_lesson_tracking failed (non-blocking)"
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
    if SKIP_AUTO_SECTION=1 bash "$SCRIPT_DIR/scripts/dashboard_update.sh" "$CMD_ID"; then
        echo "  dashboard_update: OK ($CMD_ID)"
    else
        echo "  [INFO] dashboard_update: WARN (failed, continuing)" >&2
    fi

    # gist_sync --once（dashboard更新後。ntfyにGist URLを含めるため）
    if gist_output=$(bash "$SCRIPT_DIR/scripts/gist_sync.sh" --once 2>&1); then
        echo "  gist_sync: OK"
        if echo "$gist_output" | grep -qi "error\|fail"; then
            echo "  [ERROR] GIST_SYNC_VERIFY: success exit but output contains error: $gist_output"
        fi
    else
        echo "  [INFO] gist_sync: WARN (sync failed, non-blocking)" >&2
    fi

    # ntfy_cmd（gist_sync後に実行）
    if send_info_cmd_notification "$CMD_ID" "GATE CLEAR — ${CMD_ID} 完了" 2>/dev/null; then
        echo "  ${LAST_GATE_NOTIFY_ROUTE}: OK (INFO)"
    else
        echo "  [INFO] ${LAST_GATE_NOTIFY_ROUTE:-notification}: WARN (INFO notification failed, non-blocking)" >&2
    fi

    # cmd_531: AC6 — GATE CLEAR時に教訓有効率スキャン+自動退役（緊急override時も実行）
    echo ""
    echo "Lesson effectiveness scan (GATE CLEAR - emergency override):"
    if [ -f "$SCRIPT_DIR/scripts/lesson_deprecation_scan.sh" ]; then
        if bash "$SCRIPT_DIR/scripts/lesson_deprecation_scan.sh" --project all 2>&1; then
            echo "  lesson_deprecation_scan: OK"
        else
            echo "  [INFO] lesson_deprecation_scan: WARN (scan failed, non-blocking)"
        fi
    else
        echo "  SKIP (lesson_deprecation_scan.sh not found)"
    fi

    # ─── git push（GATE CLEAR後、殿裁定2026-03-24: GATE CLEARしたcommitは家老がpush） ───
    echo ""
    echo "Git push (post-GATE CLEAR - emergency override):"
    if git -C "$PROJECT_DIR" push 2>&1; then
        echo "  git push: OK"
    else
        echo "  [INFO] git push: WARN (push failed, non-blocking)"
    fi

    exit 0
fi

# ─── 各フラグの状態確認 ───
MISSING_GATES=()
BLOCK_REASONS=()
ALL_CLEAR=true

level_heading "[L1]" "Gate check: ${CMD_ID}"
echo "  Framework: [L1] Existence | [L2] Substantive | [L3] Integration"
echo "  Required: ${ALL_GATES[*]}"
if [ ${#CONDITIONAL[@]} -gt 0 ]; then
    echo "  Conditional: ${CONDITIONAL[*]} (task_type: recon=${HAS_RECON}, implement=${HAS_IMPLEMENT})"
fi
echo ""

for gate in "${ALL_GATES[@]}"; do
    # cmd_1314: DEFERRED_GATESに含まれるgateはcheck loopでスキップ（GATE CLEAR後に実行）
    is_deferred=false
    for dg in "${DEFERRED_GATES[@]}"; do
        if [ "$gate" = "$dg" ]; then
            is_deferred=true
            break
        fi
    done
    if [ "$is_deferred" = true ]; then
        echo "  ${gate}: DEFERRED (will run after GATE CLEAR)"
        continue
    fi

    done_file="$GATES_DIR/${gate}.done"

    if [ -f "$done_file" ]; then
        detail=$(head -1 "$done_file" 2>/dev/null)
        if [ -n "$detail" ]; then
            echo "  ${gate}: DONE (${detail})"
        else
            echo "  ${gate}: DONE"
        fi
    else
        echo "  [CRITICAL] ${gate}: MISSING ← 未完了"
        MISSING_GATES+=("$gate")
        record_block_reason "missing_gate:${gate}"
        ALL_CLEAR=false
    fi
done

# ─── context_update freshness check（cmd指定時のみBLOCK） ───
check_context_update "$CMD_ID"

# ─── 報告YAML存在チェック（cmd_1192: タスクあり報告なしをBLOCK, GP-026: in_progress忍者はWAIT） ───
level_heading "[L1]" "Report YAML existence check:"
REPORT_TASK_COUNT=0
REPORT_FOUND_COUNT=0
REPORT_MISSING_FILES=()
REPORT_WAIT_NINJAS=()
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi

    REPORT_TASK_COUNT=$((REPORT_TASK_COUNT + 1))
    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")

    if [ -f "$report_file" ]; then
        REPORT_FOUND_COUNT=$((REPORT_FOUND_COUNT + 1))
        echo "  ${ninja_name}: OK ($(basename "$report_file"))"
    else
        # GP-026 B案(cmd_1332): done以外の全状態(assigned/acknowledged/in_progress)でWAIT
        ninja_status=$(grep -E '^\s+status:' "$task_file" | head -1 | sed 's/.*status:[[:space:]]*//' | tr -d "'" | tr -d '"')
        if [ "$ninja_status" != "done" ] && [ "$ninja_status" != "complete" ]; then
            REPORT_WAIT_NINJAS+=("$ninja_name")
            echo "  [WAIT] ${ninja_name}: 報告YAML未着（status=${ninja_status}、リトライ待ち）"
        else
            REPORT_MISSING_FILES+=("$(basename "$report_file")")
            echo "  [CRITICAL] ${ninja_name}: MISSING ← 報告YAML不在(status=${ninja_status}): $(basename "$report_file")"
        fi
    fi
done

# GP-026 B案(cmd_1332): WAIT忍者がいる場合はretry 3回×60秒=最大180秒
if [ "${#REPORT_WAIT_NINJAS[@]}" -gt 0 ]; then
    WAIT_MAX_RETRIES=3
    WAIT_INTERVAL=60
    for wait_retry in $(seq 1 $WAIT_MAX_RETRIES); do
        # 未解決WAIT忍者がいるか確認
        STILL_WAITING=()
        for ninja_name in "${REPORT_WAIT_NINJAS[@]}"; do
            report_file=$(resolve_report_file "$ninja_name")
            if [ ! -f "$report_file" ]; then
                STILL_WAITING+=("$ninja_name")
            fi
        done
        [ "${#STILL_WAITING[@]}" -eq 0 ] && break

        echo "  [WAIT] retry ${wait_retry}/${WAIT_MAX_RETRIES}: ${#STILL_WAITING[@]}名の報告待ち。${WAIT_INTERVAL}秒後に再チェック..."
        sleep "$WAIT_INTERVAL"

        for ninja_name in "${STILL_WAITING[@]}"; do
            report_file=$(resolve_report_file "$ninja_name")
            if [ -f "$report_file" ]; then
                REPORT_FOUND_COUNT=$((REPORT_FOUND_COUNT + 1))
                echo "  ${ninja_name}: OK (retry ${wait_retry}で発見: $(basename "$report_file"))"
            elif [ "$wait_retry" -eq "$WAIT_MAX_RETRIES" ]; then
                REPORT_MISSING_FILES+=("$(basename "$report_file")")
                echo "  [CRITICAL] ${ninja_name}: MISSING ← retry ${WAIT_MAX_RETRIES}回後も報告YAML不在: $(basename "$report_file")"
            fi
        done
    done
fi

if [ "$REPORT_TASK_COUNT" -ge 1 ] && [ "$REPORT_FOUND_COUNT" -eq 0 ]; then
    echo "  [CRITICAL] BLOCK: タスク${REPORT_TASK_COUNT}件に対して報告YAML 0件"
    for missing_f in "${REPORT_MISSING_FILES[@]}"; do
        record_block_reason "report_yaml_missing:${missing_f}"
    done
    ALL_CLEAR=false
elif [ "$REPORT_TASK_COUNT" -gt "$REPORT_FOUND_COUNT" ] && [ "$REPORT_FOUND_COUNT" -gt 0 ]; then
    echo "  [WARNING] タスク${REPORT_TASK_COUNT}件中、報告YAML ${REPORT_FOUND_COUNT}件のみ（一部不在、非BLOCK）"
elif [ "$REPORT_TASK_COUNT" -eq 0 ]; then
    echo "  (no tasks found for this cmd)"
else
    echo "  OK (全${REPORT_TASK_COUNT}件の報告YAML確認済み)"
fi

# ─── 報告YAMLフォーマット検証（cmd_1202: タスクYAML非依存・ディレクトリ直接スキャン） ───
# バイパス経路防止: タスクYAMLは忍者再配備で上書きされるため、
# 報告ディレクトリを直接スキャンしてgate_report_format.shを実行する（最終防衛線）
level_heading "[L1]" "Report format validation (direct scan):"
REPORT_FORMAT_CHECKED=0
REPORT_FORMAT_FAILED=0
for report_file in "$SCRIPT_DIR/queue/reports/"*_report_${CMD_ID}.yaml; do
    [ -f "$report_file" ] || continue
    REPORT_FORMAT_CHECKED=$((REPORT_FORMAT_CHECKED + 1))
    "$SCRIPT_DIR/scripts/gates/gate_report_autofix.sh" "$report_file" 2>/dev/null || true
    GATE_OUTPUT=$("$SCRIPT_DIR/scripts/gates/gate_report_format.sh" "$report_file" 2>&1 || true)
    if echo "$GATE_OUTPUT" | grep -q "^FAIL"; then
        REPORT_FORMAT_FAILED=$((REPORT_FORMAT_FAILED + 1))
        echo "  [CRITICAL] $(basename "$report_file"): $GATE_OUTPUT"
        record_block_reason "report_format:$(basename "$report_file")"
        ALL_CLEAR=false
    else
        echo "  $(basename "$report_file"): PASS"
    fi
done
if [ "$REPORT_FORMAT_CHECKED" -eq 0 ]; then
    echo "  (no report files found for ${CMD_ID})"
elif [ "$REPORT_FORMAT_FAILED" -eq 0 ]; then
    echo "  OK (全${REPORT_FORMAT_CHECKED}件フォーマット検証PASS)"
fi

# ─── related_lessons存在チェック（deploy_task.sh経由確認） ───
level_heading "[L1]" "Related lessons injection check:"
RL_CHECKED=false
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi

    RL_CHECKED=true
    ninja_name=$(basename "$task_file" .yaml)

    if grep -q '^\s*related_lessons:' "$task_file" 2>/dev/null; then
        has_rl_key="yes"
    else
        has_rl_key="no"
    fi

    if [ "$has_rl_key" = "yes" ]; then
        echo "  ${ninja_name}: OK (related_lessons present)"
    elif [ "$has_rl_key" = "no" ]; then
        echo "  [INFO] ${ninja_name}: related_lessonsキー欠落（deploy_task.sh経由でない可能性）"
    else
        echo "  [INFO] ${ninja_name}: related_lessons解析エラー"
    fi
done
if [ "$RL_CHECKED" = false ]; then
    echo "  (no tasks found for this cmd)"
fi

# ─── lessons_useful検証（related_lessonsあり→報告にlessons_useful必須） ───
level_heading "[L2]" "Lessons useful check:"
LESSON_CHECKED=false
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi

    # related_lessonsの有無をチェック（空リスト[]やnullは除外）
    rl_count=$(awk '/related_lessons:/,/^[^ ]/{if(/^\s*- /)c++} END{print c+0}' "$task_file" 2>/dev/null)
    has_lessons=$([ "${rl_count:-0}" -gt 0 ] && echo "yes" || echo "no")

    if [ "$has_lessons" = "yes" ]; then
        LESSON_CHECKED=true
        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name")

        if [ -f "$report_file" ]; then
            # lessons_useful検証: null/空/FILL_THIS/形式不正/ok (cmd_536+cmd_1045+cmd_1180)
            lr_status=$(awk '
                # lessons_useful: または lesson_referenced: セクション検出
                /^lessons_useful:/ {
                    val = $0; sub(/.*lessons_useful:[[:space:]]*/, "", val)
                    if (val == "null" || val == "~") { result = "null"; exit }
                    if (val == "" || val == "[]") { sec = "lu" }
                    else { sec = "lu" }
                    lu_found = 1; next
                }
                /^lesson_referenced:/ && !lu_found {
                    sec = "lr"; next
                }
                (sec == "lu" || sec == "lr") && /^[a-zA-Z]/ { sec = "" }
                # リスト要素 (- id: ...) を検出
                (sec == "lu" || sec == "lr") && /^[[:space:]]*- / {
                    item_count++
                    # FILL_THIS検出 (useful/reason)
                    if ($0 ~ /useful:[[:space:]]*FILL_THIS/ || $0 ~ /reason:[[:space:]]*FILL_THIS/) {
                        fill_this = 1
                    }
                }
                # useful: フィールド（リスト要素の子）
                (sec == "lu" || sec == "lr") && /^[[:space:]]+useful:/ {
                    u = $0; sub(/.*useful:[[:space:]]*/, "", u); gsub(/^["'"'"']+|["'"'"']+$/, "", u)
                    if (u == "FILL_THIS") { fill_this = 1 }
                    else if (u == "true" || u == "false") { bool_count++ }
                    else if (u == "" || u == "null" || u == "~") { null_useful = 1 }
                    else { non_bool = 1 }
                }
                # reason: FILL_THIS検出
                (sec == "lu" || sec == "lr") && /^[[:space:]]+reason:[[:space:]]*FILL_THIS/ { fill_this = 1 }
                END {
                    if (result != "") { print result; exit }
                    if (item_count == 0) { print "empty"; exit }
                    if (fill_this) { print "fill_this_remaining"; exit }
                    if (null_useful || non_bool) { print "invalid_format"; exit }
                    if (bool_count > 0) { print "ok"; exit }
                    print "empty"
                }
            ' "$report_file" 2>/dev/null)

            if [ "$lr_status" = "ok" ]; then
                echo "  ${ninja_name}: OK (lessons_useful present and non-empty)"
            elif [ "$lr_status" = "null" ]; then
                # cmd_536 AC4: lessons_useful=null(明示的未記入)をBLOCK
                echo "  [CRITICAL] ${ninja_name}: NG ← lessons_usefulが未記入(null)。教訓の有用性を記入せよ"
                record_block_reason "${ninja_name}:null_lessons_useful"
                ALL_CLEAR=false
            elif [ "$lr_status" = "fill_this_remaining" ]; then
                # cmd_1180: FILL_THISテンプレートが未置換
                echo "  [CRITICAL] ${ninja_name}: NG ← lessons_usefulにFILL_THISが残っている。各教訓のusefulをtrue/falseに、reasonを理由文に書き換えよ"
                record_block_reason "${ninja_name}:fill_this_remaining"
                ALL_CLEAR=false
            elif [ "$lr_status" = "invalid_format" ]; then
                # cmd_1045: lessons_usefulの要素形式が不正（文字列/useful欠落/non-bool）
                echo "  [CRITICAL] ${ninja_name}: NG ← lessons_usefulの形式が不正。各要素は以下の形式で記載せよ:"
                echo "    lessons_useful:"
                echo "      - id: L028"
                echo "        useful: true"
                echo "        reason: '理由を記載'"
                record_block_reason "${ninja_name}:invalid_lessons_useful_format"
                ALL_CLEAR=false
            else
                # related_lessonsからlesson IDを抽出してメッセージに表示
                rl_ids=$(awk '/related_lessons:/,/^[^ ]/{if(/id:/){val=$0; sub(/.*id:\s*/, "", val); gsub(/[" \t]/, "", val); if(c++) printf ","; printf "%s", val}}' "$task_file" 2>/dev/null)
                [ -z "$rl_ids" ] && rl_ids="(parse_error)"
                echo "  [CRITICAL] ${ninja_name}: NG ← lessons_useful空。related_lessons [${rl_ids}] のうち実際に役立った教訓を報告に記載せよ"
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

# ─── reviewed:false残存チェック（廃止: cmd_533でpush型に移行） ───
# reviewed:falseフィールドはdeploy_task.shで付与されなくなった（detail埋込に移行）
# 旧タスクYAMLにreviewed:falseが残存していても後方互換でブロックしない
level_heading "[L1]" "Lesson reviewed check: SKIP (push型移行済み — cmd_533)"

# ─── ac_version照合（task.ac_version vs report.ac_version_read） ───
level_heading "[L3]" "AC version check:"
AC_VERSION_CHECKED=false
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi

    AC_VERSION_CHECKED=true
    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (report not found)"
        continue
    fi

    # ac_version照合: field_getで取得→比較
    _acv_task=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "ac_version" "")
    _acv_read=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "ac_version_read" "")
    # normalize: 空/null/none → empty
    case "${_acv_task,,}" in ""|null|none|"~") _acv_task="" ;; esac
    case "${_acv_read,,}" in ""|null|none|"~") _acv_read="" ;; esac
    if [ -z "$_acv_task" ]; then
        acv_status="task_missing"
    elif [[ "$_acv_task" =~ ^[0-9]+$ ]]; then
        # legacy numeric → skip
        acv_status=$(printf 'legacy_skip\t%s\t%s' "$_acv_task" "${_acv_read:--}")
    elif [ -z "$_acv_read" ]; then
        acv_status=$(printf 'report_missing\t%s\t-' "$_acv_task")
    elif [ "$_acv_task" = "$_acv_read" ]; then
        acv_status=$(printf 'ok\t%s\t%s' "$_acv_task" "$_acv_read")
    else
        acv_status=$(printf 'mismatch\t%s\t%s' "$_acv_task" "$_acv_read")
    fi

    acv_kind=$(echo "$acv_status" | cut -f1)
    acv_task=$(echo "$acv_status" | cut -f2)
    acv_read=$(echo "$acv_status" | cut -f3)

    case "$acv_kind" in
        ok)
            echo "  ${ninja_name}: OK (ac_version task=${acv_task}, report=${acv_read})"
            ;;
        mismatch)
            echo "  [CRITICAL] ${ninja_name}: NG ← ac_version不一致 (task=${acv_task}, report=${acv_read})"
            record_block_reason "${ninja_name}:ac_version_mismatch:task=${acv_task}:report=${acv_read}"
            ALL_CLEAR=false
            ;;
        report_missing)
            echo "  [INFO] ${ninja_name}: ac_version_read未記載（task=${acv_task}）。後方互換として非BLOCK"
            ;;
        legacy_skip)
            echo "  [INFO] ${ninja_name}: 旧形式(数値)ac_version=${acv_task}のため照合SKIP（後方互換）"
            ;;
        task_missing)
            echo "  [INFO] ${ninja_name}: task.ac_version未設定のため照合SKIP"
            ;;
        *)
            echo "  [INFO] ${ninja_name}: ac_version照合解析エラー（非BLOCK）"
            ;;
    esac
done
if [ "$AC_VERSION_CHECKED" = false ]; then
    echo "  (no tasks found for this cmd)"
fi

# ─── lesson_candidate検証（found:trueなのに未登録を防止） ───
level_heading "[L1]" "Lesson candidate check:"
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

    # lesson_candidateフィールドの検証 (awk: cmd_536+cmd_776+cmd_1180)
    lc_status=$(awk '
        /^lesson_candidate:/ {
            # inline list check (legacy_list: "lesson_candidate: [...]" or next line is "- ")
            val = $0; sub(/.*lesson_candidate:[[:space:]]*/, "", val)
            if (val == "null" || val == "~" || val == "") { in_lc = 1 }
            else if (val ~ /^\[/) { result = "legacy_list" }
            else { result = "malformed" }
            next
        }
        in_lc && /^[a-zA-Z]/ { in_lc = 0 }
        # list形式の検出 (legacy_list)
        in_lc && /^[[:space:]]*- / && !has_found_key { result = "legacy_list"; in_lc = 0 }
        in_lc && /^[[:space:]]+found:/ {
            has_found_key = 1
            v = $0; sub(/.*found:[[:space:]]*/, "", v); gsub(/[" \t]/, "", v)
            found_val = v
        }
        in_lc && /^[[:space:]]+no_lesson_reason:/ {
            v = $0; sub(/.*no_lesson_reason:[[:space:]]*/, "", v); gsub(/^["'"'"']+|["'"'"']+$/, "", v)
            nlr = v
        }
        in_lc && /^[[:space:]]+title:/ {
            v = $0; sub(/.*title:[[:space:]]*/, "", v); gsub(/^["'"'"']+|["'"'"']+$/, "", v)
            lc_title = v
        }
        in_lc && /^[[:space:]]+detail:/ {
            v = $0; sub(/.*detail:[[:space:]]*/, "", v); gsub(/^["'"'"']+|["'"'"']+$/, "", v)
            lc_detail = v
        }
        END {
            if (result != "") { print result; exit }
            if (!in_lc && !has_found_key) { print "missing"; exit }
            if (!has_found_key) { print "found_missing"; exit }
            if (found_val == "false") {
                if (nlr == "") print "ok_false_no_reason"
                else print "ok_false"
                exit
            }
            if (found_val == "true") {
                miss = ""
                if (lc_title == "") { miss = "title" }
                if (lc_detail == "") { if (miss != "") miss = miss ","; miss = miss "detail" }
                if (miss != "") print "found_true_empty:" miss
                else print "found_true"
                exit
            }
            print "malformed"
        }
    ' "$report_file" 2>/dev/null)

    case "$lc_status" in
        ok_false)
            echo "  ${ninja_name}: OK (lesson_candidate: found=false)"
            ;;
        ok_false_no_reason)
            echo "  [CRITICAL] ${ninja_name}: NG ← lesson_candidate found:false but no_lesson_reason is empty"
            record_block_reason "${ninja_name}:lesson_candidate_no_reason_empty"
            ALL_CLEAR=false
            ;;
        found_true_empty:*)
            missing_fields="${lc_status#found_true_empty:}"
            echo "  [CRITICAL] ${ninja_name}: NG ← lesson_candidate found:true but empty fields: ${missing_fields}"
            record_block_reason "${ninja_name}:lesson_candidate_fields_empty:${missing_fields}"
            ALL_CLEAR=false
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
                    echo "  [CRITICAL] ${ninja_name}: NG ← lesson_candidate found:true but lesson.done source=${lsource} (not lesson_write)"
                    record_block_reason "${ninja_name}:lesson_done_source:${lsource}"
                    ALL_CLEAR=false
                fi
            else
                echo "  [CRITICAL] ${ninja_name}: NG ← lesson_candidate found:true but lesson.done not found"
                record_block_reason "${ninja_name}:lesson_done_missing"
                ALL_CLEAR=false
            fi
            ;;
        missing)
            echo "  [CRITICAL] ${ninja_name}: NG ← lesson_candidateフィールド欠落"
            record_block_reason "${ninja_name}:lesson_candidate_missing"
            ALL_CLEAR=false
            ;;
        legacy_list)
            # cmd_776 A層: BLOCK→自動修正+WARN。normalize_report.shで修正を試みる
            a_normalize_output=$(bash "$SCRIPT_DIR/scripts/lib/normalize_report.sh" "$report_file" 2>&1) && {
                echo "  [INFO] ${ninja_name}: lesson_candidate旧形式を自動修正: ${a_normalize_output}"
                echo "$(date '+%Y-%m-%dT%H:%M:%S') [A層] ${CMD_ID} ${ninja_name}: ${a_normalize_output}" >> "$SCRIPT_DIR/logs/normalize_report.log"
                # 修正成功 → 再検証
                if grep -A10 'lesson_candidate:' "$report_file" 2>/dev/null | grep -q 'found:'; then
                    lc_recheck="ok"
                else
                    lc_recheck="ng"
                fi
                if [ "$lc_recheck" != "ok" ]; then
                    echo "  [CRITICAL] ${ninja_name}: NG ← 自動修正後も構造不正"
                    record_block_reason "${ninja_name}:lesson_candidate_normalize_failed"
                    ALL_CLEAR=false
                fi
            } || {
                echo "  [CRITICAL] ${ninja_name}: NG ← lesson_candidate自動修正失敗"
                record_block_reason "${ninja_name}:lesson_candidate_normalize_error"
                ALL_CLEAR=false
            }
            ;;
        found_missing)
            echo "  [CRITICAL] ${ninja_name}: NG ← lesson_candidate.found が未設定。正規フォーマット: found: true/false"
            record_block_reason "${ninja_name}:lesson_candidate_found_missing"
            ALL_CLEAR=false
            ;;
        malformed)
            echo "  [CRITICAL] ${ninja_name}: NG ← lesson_candidate構造不正"
            record_block_reason "${ninja_name}:lesson_candidate_malformed"
            ALL_CLEAR=false
            ;;
        *)
            echo "  [CRITICAL] ${ninja_name}: NG ← lesson_candidate解析エラー"
            record_block_reason "${ninja_name}:lesson_candidate_parse_error"
            ALL_CLEAR=false
            ;;
    esac
done
if [ "$LC_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── binary_checks検証（AC二値チェック全PASS確認） ───
level_heading "[L1]" "Binary checks validation:"
BC_CHECKED=false
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

    BC_CHECKED=true

    # binary_checks: リスト形式の全check→result=PASS確認
    bc_status=$(awk '
        /^binary_checks:/ {
            val = $0; sub(/.*binary_checks:[[:space:]]*/, "", val)
            if (val == "null" || val == "~") { print "missing"; exit }
            in_bc = 1; next
        }
        # セクション終了: 行頭が英字(新キー)の場合のみ (- で始まるリスト項目は含めない)
        in_bc && /^[a-zA-Z]/ { in_bc = 0 }
        # dict形式(AC_id: の行)→malformed (python互換: 即判定)
        in_bc && /^[[:space:]]+[A-Za-z_][A-Za-z_0-9]*:/ && !/^[[:space:]]+check:/ && !/^[[:space:]]+result:/ { print "malformed"; exit }
        in_bc && /[[:space:]]*- check:/ { item_count++; cur_check = $0; sub(/.*- check:[[:space:]]*/, "", cur_check); gsub(/^["'"'"']+|["'"'"']+$/, "", cur_check) }
        in_bc && /[[:space:]]+result:/ {
            r = $0; sub(/.*result:[[:space:]]*/, "", r); gsub(/^["'"'"']+|["'"'"']+$/, "", r)
            upper_r = toupper(r)
            if (upper_r != "PASS") {
                _name = (cur_check != "" ? cur_check : "item_" item_count)
                if (fails != "") fails = fails "|" _name
                else fails = _name
            }
        }
        END {
            if (!in_bc && item_count == 0 && !is_dict) { print "missing"; exit }
            if (is_dict && item_count == 0) { print "malformed"; exit }
            if (item_count == 0) { print "missing"; exit }
            if (fails != "") print "fail:" fails
            else print "ok"
        }
    ' "$report_file" 2>/dev/null)

    case "$bc_status" in
        ok)
            echo "  ${ninja_name}: OK (binary_checks: all PASS)"
            ;;
        missing)
            echo "  [WARN] ${ninja_name}: binary_checks key missing or null"
            ;;
        fail:*)
            failed_checks="${bc_status#fail:}"
            echo "  [CRITICAL] ${ninja_name}: NG ← binary_checks has non-PASS results: ${failed_checks}"
            record_block_reason "${ninja_name}:binary_checks_fail"
            ALL_CLEAR=false
            ;;
        malformed)
            echo "  [WARN] ${ninja_name}: binary_checks is not a list"
            ;;
        *)
            echo "  [WARN] ${ninja_name}: binary_checks parse error"
            ;;
    esac
done
if [ "$BC_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── purpose_validation検証（fit:falseでBLOCK、fit空欄はWARN） ───
level_heading "[L2]" "Purpose validation check:"
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
            echo "[CRITICAL] GATE BLOCK: purpose_validation.fit=false (目的未達成)"
            echo "  ${ninja_name}: fit=false"
            record_block_reason "${ninja_name}:purpose_validation_fit_false"
            ALL_CLEAR=false
            ;;
        "")
            echo "  [INFO] ${ninja_name}: fit未記入（段階導入: 非BLOCK）"
            ;;
        *)
            echo "  [INFO] ${ninja_name}: fit値不正 '${pv_fit}'（段階導入: 非BLOCK）"
            ;;
    esac
done
if [ "$PV_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── decision_candidate重複チェック（resolved PDとの照合、cmd_1179） ───
level_heading "[L2]" "Decision candidate duplicate check (cmd_1179):"
if [ "$HAS_RECON" = true ] && [ "$HAS_IMPLEMENT" = false ]; then
    echo "  SKIP (recon-only cmd)"
else
    DC_DUP_CHECKED=false
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

        DC_DUP_CHECKED=true
        dc_dup_result=$(bash "$SCRIPT_DIR/scripts/gates/gate_dc_duplicate.sh" "$report_file" 2>/dev/null || echo "BLOCK: gate script error")

        case "$dc_dup_result" in
            BLOCK:*)
                echo "  [CRITICAL] ${ninja_name}: ${dc_dup_result}"
                record_block_reason "${ninja_name}:dc_duplicate_block"
                ALL_CLEAR=false
                ;;
            WARN:*)
                echo "  [INFO] ${ninja_name}: ${dc_dup_result}"
                ;;
            OK:*|SKIP:*)
                echo "  ${ninja_name}: ${dc_dup_result}"
                ;;
            *)
                echo "  [INFO] ${ninja_name}: dc_dup unexpected: ${dc_dup_result}"
                ;;
        esac
    done
    if [ "$DC_DUP_CHECKED" = false ]; then
        echo "  (no reports found for this cmd)"
    fi
fi

# ─── deviation回数チェック（WARNのみ、4回以上でWARNING） ───
level_heading "[L2]" "Deviation count check:"
DEVIATION_CHECKED=false
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

    DEVIATION_CHECKED=true
    # result:セクション内のdeviation:リスト要素数を数える
    deviation_status=$(awk '
        /^result:/ { in_result=1; next }
        in_result && /^[^ ]/ { in_result=0 }
        in_result && /^[[:space:]]+deviation:/ {
            has_dev=1; in_dev=1
            match($0, /^[[:space:]]+/)
            dev_indent = RLENGTH
            if ($0 ~ /\[\]/) { has_dev=2 }
            next
        }
        in_dev && NF > 0 {
            match($0, /^[[:space:]]*/); ci = RLENGTH
            if (ci <= dev_indent) { in_dev=0; next }
        }
        in_dev && /^[[:space:]]+- / { count++ }
        END {
            if (!has_dev && count==0) { printf "skip\tresult.deviation not present"; exit }
            if (has_dev==2 || count==0) { printf "skip\tresult.deviation empty (count 0)"; exit }
            if (count >= 4) printf "warn\t%d", count
            else printf "ok\t%d", count
        }
    ' "$report_file" 2>/dev/null)

    deviation_kind=$(printf '%s\n' "$deviation_status" | cut -f1)
    deviation_detail=$(printf '%s\n' "$deviation_status" | cut -f2-)

    case "$deviation_kind" in
        warn)
            echo "  [INFO] ${ninja_name}: deviation count ${deviation_detail} >= 4: 逸脱管理ルール(3回超過)に抵触"
            ;;
        ok)
            echo "  ${ninja_name}: OK (deviation count ${deviation_detail} <= 3)"
            ;;
        skip)
            echo "  ${ninja_name}: SKIP (${deviation_detail})"
            ;;
        *)
            echo "  [INFO] ${ninja_name}: deviation count解析エラー (${deviation_detail})"
            ;;
    esac
done
if [ "$DEVIATION_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── analysis_paralysis_triggeredチェック（WARNのみ） ───
level_heading "[L2]" "Analysis paralysis check:"
ANALYSIS_PARALYSIS_CHECKED=false
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

    ANALYSIS_PARALYSIS_CHECKED=true
    if ! grep -q '^\s*result:' "$report_file" 2>/dev/null; then
        analysis_status=$'skip\tresult missing or not a mapping'
    else
        ap_val=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "analysis_paralysis_triggered" "")
        case "$ap_val" in
            true)  analysis_status=$'warn\tanalysis paralysis was triggered during this task' ;;
            false) analysis_status=$'ok\tanalysis_paralysis_triggered=false' ;;
            "")    analysis_status=$'skip\tanalysis_paralysis_triggered not present' ;;
            *)     analysis_status=$'skip\tanalysis_paralysis_triggered not boolean' ;;
        esac
    fi

    analysis_kind=$(printf '%s\n' "$analysis_status" | cut -f1)
    analysis_detail=$(printf '%s\n' "$analysis_status" | cut -f2-)

    case "$analysis_kind" in
        warn)
            echo "  [INFO] ${ninja_name}: ${analysis_detail}"
            ;;
        ok)
            echo "  ${ninja_name}: OK (${analysis_detail})"
            ;;
        skip)
            echo "  ${ninja_name}: SKIP (${analysis_detail})"
            ;;
        *)
            echo "  [INFO] ${ninja_name}: analysis_paralysis_triggered解析エラー (${analysis_detail})"
            ;;
    esac
done
if [ "$ANALYSIS_PARALYSIS_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── skill_candidate検証（WARNのみ、ブロックしない） ───
level_heading "[L1]" "Skill candidate check:"
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

    if ! grep -q 'skill_candidate:' "$report_file" 2>/dev/null; then
        sc_status="missing"
    elif grep -A5 'skill_candidate:' "$report_file" 2>/dev/null | grep -q 'found:'; then
        sc_status="ok"
    else
        sc_status="no_found"
    fi

    case "$sc_status" in
        ok)
            echo "  ${ninja_name}: OK (skill_candidate.found present)"
            ;;
        missing)
            echo "  [INFO] ${ninja_name}_report.yaml missing skill_candidate.found"
            ;;
        no_found)
            echo "  [INFO] ${ninja_name}_report.yaml missing skill_candidate.found"
            ;;
        malformed)
            echo "  [INFO] ${ninja_name}_report.yaml skill_candidate構造不正"
            ;;
        *)
            echo "  [INFO] ${ninja_name}_report.yaml skill_candidate解析エラー"
            ;;
    esac
done
if [ "$SC_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── decision_candidate検証（WARNのみ、ブロックしない） ───
level_heading "[L1]" "Decision candidate check:"
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

    if ! grep -q 'decision_candidate:' "$report_file" 2>/dev/null; then
        dc_status="missing"
    elif grep -A5 'decision_candidate:' "$report_file" 2>/dev/null | grep -q 'found:'; then
        dc_status="ok"
    else
        dc_status="no_found"
    fi

    case "$dc_status" in
        ok)
            echo "  ${ninja_name}: OK (decision_candidate.found present)"
            ;;
        missing)
            echo "  [INFO] ${ninja_name}_report.yaml missing decision_candidate.found"
            ;;
        no_found)
            echo "  [INFO] ${ninja_name}_report.yaml missing decision_candidate.found"
            ;;
        malformed)
            echo "  [INFO] ${ninja_name}_report.yaml decision_candidate構造不正"
            ;;
        *)
            echo "  [INFO] ${ninja_name}_report.yaml decision_candidate解析エラー"
            ;;
    esac
done
if [ "$DC_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── how_it_works検証（implementタスクはWARN導入） ───
level_heading "[L2]" "Implementation walkthrough check:"
HOW_IT_WORKS_CHECKED=false
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi

    task_role=$(detect_task_role "$task_file")
    [ "$task_role" = "implement" ] || continue

    HOW_IT_WORKS_CHECKED=true
    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")

    if [ ! -f "$report_file" ]; then
        echo "  ${ninja_name}: SKIP (implement report not found)"
        continue
    fi

    walkthrough_status=$(check_how_it_works_status "$report_file")
    case "$walkthrough_status" in
        ok)
            echo "  ${ninja_name}: OK (how_it_works present)"
            ;;
        missing|empty)
            echo "  [INFO] ${ninja_name}: how_it_works missing or empty (implement report)"
            ;;
        *)
            echo "  [INFO] ${ninja_name}: how_it_works parse error (non-blocking)"
            ;;
    esac
done
if [ "$HOW_IT_WORKS_CHECKED" = false ]; then
    echo "  (no implement tasks found for this cmd)"
fi

# ─── review品質機械検査（cmd_607） ───
level_heading "[L2]" "Review quality check:"
REVIEW_TASK_FOUND=false
IMPLEMENTER_IDS="|"
REVIEWER_IDS="|"
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi

    task_role=$(detect_task_role "$task_file")
    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")

    case "$task_role" in
        implement)
            if [ -f "$report_file" ]; then
                impl_worker_id=$(field_get "$report_file" "worker_id" "")
                if [ -n "$impl_worker_id" ] && [[ "$IMPLEMENTER_IDS" != *"|$impl_worker_id|"* ]]; then
                    IMPLEMENTER_IDS="${IMPLEMENTER_IDS}${impl_worker_id}|"
                fi
            fi
            ;;
        review)
            REVIEW_TASK_FOUND=true

            if [ ! -f "$report_file" ]; then
                echo "  ${ninja_name}: SKIP (review report not found)"
                continue
            fi

            # verdict判定: PASS/FAILのいずれかならok
            _rv_verdict=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "verdict" "")
            _rv_verdict_status="ng"
            [ "$_rv_verdict" = "PASS" ] || [ "$_rv_verdict" = "FAIL" ] && _rv_verdict_status="ok"
            # self_gate_check判定: 4項目全てPASSならok
            _rv_gate_status="ng"
            if grep -q 'self_gate_check:' "$report_file" 2>/dev/null; then
                _rv_sg_pass=$(awk '
                    /self_gate_check:/ { sec=1; next }
                    sec && /^[^ ]/ { exit }
                    sec && /lesson_ref:.*PASS/ { c++ }
                    sec && /lesson_candidate:.*PASS/ { c++ }
                    sec && /status_valid:.*PASS/ { c++ }
                    sec && /purpose_fit:.*PASS/ { c++ }
                    END { print c+0 }
                ' "$report_file" 2>/dev/null)
                [ "${_rv_sg_pass:-0}" -eq 4 ] && _rv_gate_status="ok"
            fi
            _rv_worker_id=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "worker_id" "")
            review_status=$(printf '%s\t%s\t%s' "$_rv_verdict_status" "$_rv_gate_status" "$_rv_worker_id")

            verdict_status=$(printf '%s\n' "$review_status" | cut -f1)
            self_gate_status=$(printf '%s\n' "$review_status" | cut -f2)
            review_worker_id=$(printf '%s\n' "$review_status" | cut -f3)

            if [ "$verdict_status" = "ok" ]; then
                echo "  ${ninja_name}: OK (verdict=PASS/FAIL)"
            else
                echo "  [CRITICAL] ${ninja_name}: NG ← verdict欠落または不正値（PASS/FAIL必須）"
                record_block_reason "review report missing verdict field"
                ALL_CLEAR=false
            fi

            if [ "$self_gate_status" = "ok" ]; then
                echo "  ${ninja_name}: OK (self_gate_check all PASS)"
            else
                echo "  [CRITICAL] ${ninja_name}: NG ← self_gate_check 4項目が不足またはPASS以外"
                record_block_reason "review report self_gate_check incomplete or not all PASS"
                ALL_CLEAR=false
            fi

            if [ -n "$review_worker_id" ] && [[ "$REVIEWER_IDS" != *"|$review_worker_id|"* ]]; then
                REVIEWER_IDS="${REVIEWER_IDS}${review_worker_id}|"
            fi
            ;;
    esac
done

if [ "$REVIEW_TASK_FOUND" = false ]; then
    echo "  SKIP (no review reports for this cmd)"
elif [ "$IMPLEMENTER_IDS" = "|" ]; then
    echo "  reviewer/implementer split: SKIP (no implementer reports)"
elif [ "$REVIEWER_IDS" = "|" ]; then
    echo "  reviewer/implementer split: SKIP (no review worker_id)"
else
    overlapping_workers=$(
        comm -12 \
            <(printf '%s\n' "$IMPLEMENTER_IDS" | tr '|' '\n' | sed '/^$/d' | sort -u) \
            <(printf '%s\n' "$REVIEWER_IDS" | tr '|' '\n' | sed '/^$/d' | sort -u) \
        | paste -sd, -
    )
    if [ -n "$overlapping_workers" ]; then
        echo "  [CRITICAL] NG ← reviewer and implementer overlap: ${overlapping_workers}"
        record_block_reason "reviewer is same as implementer"
        ALL_CLEAR=false
    else
        echo "  reviewer/implementer split: OK"
    fi
fi

# ─── draft教訓存在チェック（プロジェクト関連のdraft未査読をブロック） ───
level_heading "[L3]" "Draft lesson check:"
# cmdのprojectを取得
CMD_PROJECT=$(awk -v cmd="${CMD_ID}" '
    /^[ ]*- id:/ { line=$0; sub(/^[ ]*- id: */, "", line); gsub(/[" \t]/, "", line); if (line == cmd) { found=1; next } if (found) exit }
    found && /^[ ]*project:/ { sub(/^[ ]*project: */, ""); print; exit }
' "$YAML_FILE")

if [ -n "$CMD_PROJECT" ]; then
    # projectのSSOTパスを取得
    DRAFT_SSOT_PATH=$(awk -v proj="$CMD_PROJECT" '
        /^\s*- id:/ { id=$0; sub(/.*id:\s*/, "", id); gsub(/[" \t]/, "", id); found=(id==proj) }
        found && /^\s*path:/ { sub(/^\s*path:\s*/, ""); gsub(/["'"'"' \t]/, ""); print; exit }
    ' "$SCRIPT_DIR/config/projects.yaml" 2>/dev/null)

    if [ -n "$DRAFT_SSOT_PATH" ]; then
        DRAFT_LESSONS_FILE="$DRAFT_SSOT_PATH/tasks/lessons.md"
        if [ -f "$DRAFT_LESSONS_FILE" ]; then
            draft_count=$(grep -c '^\- \*\*status\*\*: draft' "$DRAFT_LESSONS_FILE" 2>/dev/null || true)
            draft_count=${draft_count:-0}
            if [ "$draft_count" -gt 0 ]; then
                echo "  [CRITICAL] NG ← ${CMD_PROJECT}に${draft_count}件のdraft未査読教訓あり"
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
level_heading "[L2]" "Raw grep YAML access check (L070):"
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
        echo "  [INFO] ${rel_path} — raw grep YAML access detected:"
        echo "$hits" | head -3 | while IFS= read -r line; do
            echo "    $line"
        done
        RAW_GREP_COUNT=$((RAW_GREP_COUNT + 1))
    fi
done
if [ "$RAW_GREP_COUNT" -eq 0 ]; then
    echo "  OK (no raw grep YAML access detected in scripts/)"
else
    echo "  [INFO] ${RAW_GREP_COUNT} script(s) use raw grep for YAML field access. Migrate to field_get (scripts/lib/field_get.sh)"
fi

# ─── inbox_archive強制チェック（WARNのみ、ブロックしない） ───
level_heading "[L1]" "Inbox archive check:"
KARO_INBOX="$SCRIPT_DIR/queue/inbox/karo.yaml"
if [ -f "$KARO_INBOX" ]; then
    read_count=$(grep -c 'read: true' "$KARO_INBOX" 2>/dev/null || true)
    read_count=${read_count:-0}

    if [ "$read_count" -ge 10 ]; then
        echo "[INFO] INBOX_ARCHIVE_WARN: karo has ${read_count} read messages, running inbox_archive.sh"
        if bash "$SCRIPT_DIR/scripts/inbox_archive.sh" karo; then
            echo "  karo: inbox_archive completed"
        else
            echo "  [INFO] inbox_archive.sh failed for karo"
        fi
    else
        echo "  karo: OK (read:true=${read_count}, threshold=10)"
    fi
else
    echo "  [INFO] karo inbox file not found: ${KARO_INBOX}"
fi

# ─── 未反映PD検出（WARNのみ、ブロックしない） ───
level_heading "[L3]" "Pending decision context sync check:"
PD_FILE="$SCRIPT_DIR/queue/pending_decisions.yaml"
if [ -f "$PD_FILE" ]; then
    unsynced_pds=$(awk -v cmd="${CMD_ID}" '
        /^[[:space:]]*- id:/ {
            if (did != "" && scmd == cmd && stat == "resolved" && synced == "false") print did
            did = $0; sub(/.*- id:[[:space:]]*/, "", did); gsub(/[" \t]/, "", did)
            scmd = ""; stat = ""; synced = ""
            next
        }
        /^[[:space:]]+source_cmd:/ { scmd = $0; sub(/.*source_cmd:[[:space:]]*/, "", scmd); gsub(/[" \t]/, "", scmd) }
        /^[[:space:]]+status:/ { stat = $0; sub(/.*status:[[:space:]]*/, "", stat); gsub(/[" \t]/, "", stat) }
        /^[[:space:]]+context_synced:/ { synced = $0; sub(/.*context_synced:[[:space:]]*/, "", synced); gsub(/[" \t]/, "", synced) }
        END { if (did != "" && scmd == cmd && stat == "resolved" && synced == "false") print did }
    ' "$PD_FILE" 2>/dev/null)

    if [ -n "$unsynced_pds" ]; then
        while IFS= read -r pd_id; do
            echo "  [INFO] ${pd_id} resolved but context not synced"
        done <<< "$unsynced_pds"
    else
        echo "  OK (no unsynced resolved PDs for ${CMD_ID})"
    fi
else
    echo "  SKIP (pending_decisions.yaml not found)"
fi

# ─── 穴4: 調査恒久化チェック（WARNのみ、ブロックしない） ───
level_heading "[L3]" "Recon knowledge persistence check (穴4):"
# purposeを取得（append_changelog内と同じawk）
CMD_PURPOSE=$(awk -v cmd="${CMD_ID}" '
    /^[ ]*- id:/ { line=$0; sub(/^[ ]*- id: */, "", line); gsub(/[" \t]/, "", line); if (line == cmd) { found=1; next } if (found) exit }
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
            echo "  [INFO] 穴4: 調査結果が知識基盤に未反映。context/*.md or projects/*.yaml を更新せよ"
        fi
    else
        echo "  SKIP (project not found in cmd — cannot check knowledge files)"
    fi
else
    echo "  SKIP (non-recon cmd: purpose does not contain recon keywords)"
fi

# ─── 偵察報告 実装直結4要件チェック（WARNのみ、cmd_754） ───
level_heading "[L2]" "Recon implementation_readiness check (cmd_754):"

if [ "$HAS_RECON" = true ]; then
    RECON_4REQ_MISSING=0
    RECON_4REQ_CHECKED=0
    RECON_4REQ_KEYWORDS="files_to_modify affected_files related_tests edge_cases"

    for report_file in "$REPORTS_DIR"/*_report_${CMD_ID}.yaml; do
        [ -f "$report_file" ] || continue

        # task_typeがrecon/scoutの報告のみ対象
        local_task_type=""
        local_task_id=$(field_get "$report_file" "task_id" "")
        if [ -n "$local_task_id" ]; then
            local_task_file="$TASKS_DIR/$(echo "$report_file" | sed 's|.*/\([^/]*\)_report_.*|\1|').yaml"
            if [ -f "$local_task_file" ]; then
                local_task_type=$(field_get "$local_task_file" "task_type" "")
            fi
        fi

        # subtask_idからもrecon/scoutを判定
        if [ -z "$local_task_type" ] || { [ "$local_task_type" != "recon" ] && [ "$local_task_type" != "scout" ]; }; then
            if echo "$local_task_id" | grep -qiE 'scout|recon'; then
                local_task_type="recon"
            fi
        fi

        [ "$local_task_type" = "recon" ] || [ "$local_task_type" = "scout" ] || continue

        RECON_4REQ_CHECKED=$((RECON_4REQ_CHECKED + 1))
        for kw in $RECON_4REQ_KEYWORDS; do
            if ! grep -q "$kw" "$report_file" 2>/dev/null; then
                RECON_4REQ_MISSING=$((RECON_4REQ_MISSING + 1))
                echo "  [INFO] ${report_file##*/} に ${kw} が欠落"
            fi
        done
    done

    if [ "$RECON_4REQ_CHECKED" -eq 0 ]; then
        echo "  SKIP (recon reports not found for ${CMD_ID})"
    elif [ "$RECON_4REQ_MISSING" -eq 0 ]; then
        echo "  OK (全偵察報告に実装直結4要件あり)"
    else
        echo "  [INFO] 偵察報告に実装直結4要件(files_to_modify/affected_files/related_tests/edge_cases)が欠落。偵察品質を確認せよ"
    fi
else
    echo "  SKIP (non-recon cmd)"
fi

# ─── プロジェクトコードのスタブ検出（WARNのみ、cmd差分の追加行のみ） ───
level_heading "[L2]" "Project code stub check:"
STUB_CHECK_OUTPUT=$(check_project_code_stubs "$CMD_ID" "$CMD_PROJECT" 2>/dev/null || true)
STUB_CHECK_STATUS=$(printf '%s\n' "$STUB_CHECK_OUTPUT" | head -1 | cut -f1)
STUB_CHECK_MESSAGE=$(printf '%s\n' "$STUB_CHECK_OUTPUT" | head -1 | cut -f2-)

case "$STUB_CHECK_STATUS" in
    WARN)
        echo "  [INFO] ${STUB_CHECK_MESSAGE}"
        printf '%s\n' "$STUB_CHECK_OUTPUT" | tail -n +2 | while IFS= read -r line; do
            [ -n "$line" ] || continue
            echo "    ${line}"
        done
        ;;
    OK)
        echo "  OK (${STUB_CHECK_MESSAGE})"
        ;;
    SKIP)
        echo "  SKIP (${STUB_CHECK_MESSAGE})"
        ;;
    ERR)
        echo "  [INFO] ${STUB_CHECK_MESSAGE}"
        ;;
    *)
        echo "  [INFO] project code stub check returned no result"
        ;;
esac

# ─── 配線検証（WARNのみ、Existence != Integration） ───
level_heading "[L3]" "Wiring verification:"
WIRING_OUTPUT=$(check_script_wiring "$CMD_ID" 2>/dev/null || true)
if [ -z "$WIRING_OUTPUT" ]; then
    echo "  [INFO] wiring verification returned no result"
else
    while IFS=$'\t' read -r row_type scope status message; do
        case "$row_type" in
            CHECK)
                case "$status" in
                    WARN)
                        echo "  [INFO] ${scope}: WARN (${message})"
                        ;;
                    SKIP)
                        echo "  ${scope}: SKIP (${message})"
                        ;;
                    *)
                        echo "  ${scope}: OK (${message})"
                        ;;
                esac
                ;;
            DETAIL)
                echo "    ${message}"
                ;;
        esac
    done <<< "$WIRING_OUTPUT"
fi

# ─── TODO/FIXME残存チェック（BLOCK） ───
level_heading "[L2]" "TODO/FIXME residual check:"
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
    echo "  [CRITICAL] NG ← ${TODO_COUNT}件のTODO/FIXMEが残存:"
    printf '%s\n' "$TODO_HITS" | head -10 | while IFS= read -r line; do
        echo "    ${line}"
    done
    if [ "$TODO_COUNT" -gt 10 ]; then
        echo "    ... (${TODO_COUNT}件中10件表示)"
    fi
    record_block_reason "todo/fixme residual found"
    ALL_CLEAR=false
else
    echo "  TODO check: OK (0 remaining)"
fi

# ─── テストSKIP検査（skip_count > 0 で BLOCK） ───
level_heading "[L2]" "Test skip count check:"
TEST_SKIP_CHECKED=false
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

    TEST_SKIP_CHECKED=true
    # test_skip_count取得 (top-level優先 → test_results.skippedフォールバック)
    skip_val=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "test_skip_count" "")
    test_skip_status=""
    if [ -z "$skip_val" ]; then
        if ! grep -q '^\s*test_results:' "$report_file" 2>/dev/null; then
            test_skip_status=$'warn\ttest_results not present'
        else
            skip_val=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "skipped" "")
            if [ -z "$skip_val" ]; then
                test_skip_status=$'warn\ttest_results.skipped not present'
            fi
        fi
    fi
    if [ -z "$test_skip_status" ] && [ -n "$skip_val" ]; then
        if [[ "$skip_val" =~ ^-?[0-9]+$ ]]; then
            if [ "$skip_val" -gt 0 ]; then
                test_skip_status=$(printf 'block\t%s' "$skip_val")
            elif [ "$skip_val" -eq 0 ]; then
                test_skip_status=$(printf 'ok\t%s' "$skip_val")
            else
                test_skip_status=$(printf 'warn\ttest_skip_count negative: %s' "$skip_val")
            fi
        else
            test_skip_status=$(printf 'warn\ttest_skip_count not a number: %s' "$skip_val")
        fi
    fi

    test_skip_kind=$(printf '%s\n' "$test_skip_status" | cut -f1)
    test_skip_detail=$(printf '%s\n' "$test_skip_status" | cut -f2-)

    case "$test_skip_kind" in
        block)
            echo "  [CRITICAL] ${ninja_name}: テスト未完了: SKIP ${test_skip_detail}件。SKIP=FAILルール"
            record_block_reason "${ninja_name}:test_skip_count_${test_skip_detail}"
            ALL_CLEAR=false
            ;;
        ok)
            echo "  ${ninja_name}: OK (test_skip_count ${test_skip_detail})"
            ;;
        warn)
            echo "  [INFO] ${ninja_name}: ${test_skip_detail}"
            ;;
        *)
            echo "  [INFO] ${ninja_name}: test_skip_count解析エラー (${test_skip_detail})"
            ;;
    esac
done
if [ "$TEST_SKIP_CHECKED" = false ]; then
    echo "  (no reports found for this cmd)"
fi

# ─── Vercel Phaseリンク整合チェック（context変更時のみ、BLOCK対象） ───
level_heading "[L3]" "Vercel phase link check:"
changed_contexts=$(git -C "$SCRIPT_DIR" diff --name-only HEAD~1 2>/dev/null | grep '^context/' || true)
if [ -n "$changed_contexts" ]; then
    if [ -f "$SCRIPT_DIR/scripts/gates/gate_vercel_phase.sh" ]; then
        if bash "$SCRIPT_DIR/scripts/gates/gate_vercel_phase.sh"; then
            echo "  OK (gate_vercel_phase passed)"
        else
            echo "  [CRITICAL] ALERT: gate_vercel_phase failed (broken docs/research refs)"
            record_block_reason "vercel_phase:broken_references"
            ALL_CLEAR=false
        fi
    else
        echo "  [INFO] gate_vercel_phase.sh not found (skip)"
    fi
else
    echo "  SKIP (no context/*.md changes detected since HEAD~1)"
fi

# ─── CI status check（push済みcmdでCI赤を検知 — WARNのみ） ───
level_heading "[L3]" "CI status check:"
CI_PUSH_DETECTED=false
for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue
    if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
        continue
    fi
    ninja_name=$(basename "$task_file" .yaml)
    report_file=$(resolve_report_file "$ninja_name")
    if [ -f "$report_file" ]; then
        if grep -qE 'git push|files_modified' "$report_file" 2>/dev/null; then
            CI_PUSH_DETECTED=true
            break
        fi
    fi
done

if [ "$CI_PUSH_DETECTED" = true ]; then
    if command -v gh >/dev/null 2>&1; then
        ci_result=$(gh run list --repo simokitafresh/multi-agent-shogun --workflow test.yml --branch main --limit 1 --json conclusion,databaseId 2>/dev/null || true)
        if [ -n "$ci_result" ]; then
            ci_conclusion=$(printf '%s' "$ci_result" | jq -r 'if type == "array" and length > 0 then .[0].conclusion // "" else "" end' 2>/dev/null)
            ci_run_id=$(printf '%s' "$ci_result" | jq -r 'if type == "array" and length > 0 then .[0].databaseId // "" else "" end' 2>/dev/null)
            case "$ci_conclusion" in
                success)
                    echo "  OK (CI green, run ${ci_run_id})"
                    ;;
                failure)
                    echo "  [INFO] CI赤 (run ${ci_run_id})"
                    ;;
                "")
                    echo "  [INFO] CI結果取得不可（進行中またはデータなし）"
                    ;;
                *)
                    echo "  [INFO] CI結果=${ci_conclusion} (run ${ci_run_id})"
                    ;;
            esac
        else
            echo "  SKIP (gh run list returned empty)"
        fi
    else
        echo "  SKIP (gh CLI not available)"
    fi
else
    echo "  SKIP (no push detected in reports)"
fi

# ─── 判定結果 ───
echo ""
if [ "$ALL_CLEAR" = true ]; then
    echo "GATE CLEAR: cmd完了許可"
    echo -e "$(date +%Y-%m-%dT%H:%M:%S)\t${CMD_ID}\tCLEAR\tall_gates_passed\t${GATE_TASK_TYPE}\t${GATE_MODEL}\t${GATE_BLOOM_LEVEL}\t${GATE_INJECTED_LESSONS}\t${CMD_TITLE}" >> "$GATE_METRICS_LOG"
    # gate_yaml_status: YAML status更新（WARNING only）
    if gate_yaml_output=$(bash "$SCRIPT_DIR/scripts/gates/gate_yaml_status.sh" "$CMD_ID" 2>&1); then
        echo "$gate_yaml_output"
        if ! echo "$gate_yaml_output" | grep -qE "UPDATED|ALREADY_OK"; then
            echo "  [ERROR] GATE_YAML_STATUS_VERIFY: expected UPDATED/ALREADY_OK but got: $gate_yaml_output"
        fi
    else
        echo "$gate_yaml_output"
        echo "  [INFO] gate_yaml_status.sh failed (non-blocking)"
    fi
    if status_output=$(update_status "$CMD_ID" 2>&1); then
        echo "$status_output"
        if ! echo "$status_output" | grep -qE "STATUS UPDATED|STATUS ALREADY COMPLETED"; then
            echo "  [ERROR] UPDATE_STATUS_VERIFY: expected STATUS UPDATED/ALREADY COMPLETED but got: $status_output"
        fi
    else
        echo "$status_output"
        echo "  [INFO] update_status failed (non-blocking)"
    fi
    if changelog_output=$(append_changelog "$CMD_ID" 2>&1); then
        echo "$changelog_output"
        if ! grep -q "$CMD_ID" "$SCRIPT_DIR/queue/completed_changelog.yaml" 2>/dev/null; then
            echo "  [ERROR] APPEND_CHANGELOG_VERIFY: $CMD_ID entry not found in completed_changelog.yaml"
        fi
    else
        echo "$changelog_output"
        echo "  [INFO] append_changelog failed (non-blocking)"
    fi
    if tracking_output=$(append_lesson_tracking "$CMD_ID" "CLEAR" 2>&1); then
        echo "$tracking_output"
        if ! echo "$tracking_output" | grep -q "LESSON_TRACKING:"; then
            echo "  [ERROR] APPEND_LESSON_TRACKING_VERIFY: expected LESSON_TRACKING: in output but got: $tracking_output"
        fi
    else
        echo "$tracking_output"
        echo "  [INFO] append_lesson_tracking failed (non-blocking)"
    fi
    if impact_output=$(update_lesson_impact_tsv "$CMD_ID" "CLEAR" 2>&1); then
        echo "$impact_output"
        if echo "$impact_output" | grep -q "no pending rows"; then
            echo "  [ERROR] LESSON_IMPACT_VERIFY: updated=0 for $CMD_ID"
        fi
    else
        echo "$impact_output"
        echo "  [INFO] update_lesson_impact_tsv failed (non-blocking)"
    fi
    if sync_output=$(bash "$SCRIPT_DIR/scripts/lesson_impact_analysis.sh" --sync-counters 2>&1); then
        echo "$sync_output"
        if echo "$sync_output" | grep -qi "error"; then
            echo "  [ERROR] SYNC_COUNTERS_VERIFY: sync-counters output contains error: $sync_output"
        fi
    else
        echo "$sync_output"
        echo "  [INFO] sync-counters failed (non-blocking)"
    fi

    echo ""
    echo "Context freshness nudge (GATE CLEAR):"
    if [ -f "$SCRIPT_DIR/scripts/context_freshness_check.sh" ]; then
        context_warn_lines=$(bash "$SCRIPT_DIR/scripts/context_freshness_check.sh" --cmd-warnings "$CMD_ID" 2>/dev/null || true)
        if [ -n "$context_warn_lines" ]; then
            while IFS= read -r warn_line; do
                [ -n "$warn_line" ] || continue
                echo "  ${warn_line}"
            done <<< "$context_warn_lines"
        else
            echo "  OK: no stale project context files"
        fi
    else
        echo "  [INFO] context_freshness_check.sh not found (skip)"
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
                # lessons_useful/lesson_referenced からexplicit IDs抽出
                _se_explicit=$(awk '
                    /^lessons_useful:/ || /^lesson_referenced:/ { sec=1; next }
                    sec && /^[a-zA-Z]/ { sec=0 }
                    sec && /id:/ { v=$0; sub(/.*id:[[:space:]]*/, "", v); gsub(/^["'"'"']+|["'"'"']+$/, "", v); gsub(/[[:space:]]/, "", v); if (v != "" && !seen[v]++) print v }
                ' "$report_file" 2>/dev/null)
                # related_lessons から IDs抽出
                _se_related=$(awk '
                    /^[[:space:]]+related_lessons:/ { sec=1; next }
                    sec && /^[[:space:]]+[^ -]/ && !/^[[:space:]]+- / { sec=0 }
                    sec && /id:/ { v=$0; sub(/.*id:[[:space:]]*/, "", v); gsub(/^["'"'"']+|["'"'"']+$/, "", v); gsub(/[[:space:]]/, "", v); if (v != "" && !seen[v]++) print v }
                ' "$task_file" 2>/dev/null)
                score_entries=""
                # explicit entries
                while IFS= read -r _se_lid; do
                    [ -z "$_se_lid" ] && continue
                    score_entries="${score_entries}explicit	${_se_lid}
"
                done <<< "$_se_explicit"
                # auto entries: related IDs not in explicit, found in report text
                _se_explicit_list="|${_se_explicit//$'\n'/|}|"
                while IFS= read -r _se_rlid; do
                    [ -z "$_se_rlid" ] && continue
                    # skip if already explicit
                    case "$_se_explicit_list" in *"|${_se_rlid}|"*) continue ;; esac
                    # word-boundary check in report text
                    if grep -qP "(?<![A-Za-z0-9_])$(printf '%s' "$_se_rlid" | sed 's/[.[\*^$()+?{|\\]/\\&/g')(?![A-Za-z0-9_])" "$report_file" 2>/dev/null; then
                        score_entries="${score_entries}auto	${_se_rlid}
"
                    fi
                done <<< "$_se_related"
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
                        echo "  [INFO] ${lid}: score update failed (non-blocking)"
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
    if SKIP_AUTO_SECTION=1 bash "$SCRIPT_DIR/scripts/dashboard_update.sh" "$CMD_ID"; then
        echo "  dashboard_update: OK ($CMD_ID)"
    else
        echo "  [INFO] dashboard_update: WARN (failed, continuing)" >&2
    fi

    # gist_sync --once（dashboard更新後。ntfyにGist URLを含めるため）
    if bash "$SCRIPT_DIR/scripts/gist_sync.sh" --once >/dev/null 2>&1; then
        echo "  gist_sync: OK"
    else
        echo "  [INFO] gist_sync: WARN (sync failed, non-blocking)" >&2
    fi

    # ntfy_cmd（gist_sync後に実行）
    if send_info_cmd_notification "$CMD_ID" "GATE CLEAR — ${CMD_ID} 完了" 2>/dev/null; then
        echo "  ${LAST_GATE_NOTIFY_ROUTE}: OK (INFO)"
    else
        echo "  [INFO] ${LAST_GATE_NOTIFY_ROUTE:-notification}: WARN (INFO notification failed, non-blocking)" >&2
    fi

    # ─── GATE CLEAR時 淘汰候補自動deprecate（ベストエフォート） ───
    echo ""
    echo "Auto-deprecate check (unused - GATE CLEAR):"
    if [ -f "$SCRIPT_DIR/scripts/knowledge_metrics.sh" ] && [ -f "$SCRIPT_DIR/scripts/lesson_deprecate.sh" ]; then
        UNUSED_DEPRECATE_COUNT=0
        if metrics_json=$(bash "$SCRIPT_DIR/scripts/knowledge_metrics.sh" --json 2>/dev/null); then
            elimination_ids=$(echo "$metrics_json" | jq -r '.elimination_candidates[]? | select(.lesson_id != "" and .lesson_id != null and .project != "" and .project != null) | [.lesson_id, .project, (.inject_count // 0 | tostring)] | join("\t")' 2>/dev/null)
            if [ -n "$elimination_ids" ]; then
                while IFS=$'\t' read -r lid project injected; do
                    [ -z "$lid" ] && continue
                    if bash "$SCRIPT_DIR/scripts/lesson_deprecate.sh" "$project" "$lid" "AUTO-DEPRECATE(unused): injected=${injected} referenced=0" 2>&1; then
                        echo "  [gate] AUTO-DEPRECATE(unused): ${lid} project=${project} (injected=${injected} referenced=0)"
                        UNUSED_DEPRECATE_COUNT=$((UNUSED_DEPRECATE_COUNT + 1))
                    else
                        echo "  [INFO] ${lid}: auto-deprecate failed (non-blocking)"
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

    # cmd_531: AC6 — GATE CLEAR時に教訓有効率スキャン+自動退役
    echo ""
    echo "Lesson effectiveness scan (GATE CLEAR):"
    if [ -f "$SCRIPT_DIR/scripts/lesson_deprecation_scan.sh" ]; then
        if bash "$SCRIPT_DIR/scripts/lesson_deprecation_scan.sh" --project all 2>&1; then
            echo "  lesson_deprecation_scan: OK"
        else
            echo "  [INFO] lesson_deprecation_scan: WARN (scan failed, non-blocking)"
        fi
    else
        echo "  SKIP (lesson_deprecation_scan.sh not found)"
    fi

    # ─── cmd品質ログ記録（GATE CLEAR時、ベストエフォート） ───
    echo ""
    echo "Cmd quality log (GATE CLEAR):"
    if [ -f "$SCRIPT_DIR/scripts/cmd_quality_log.sh" ]; then
        if bash "$SCRIPT_DIR/scripts/cmd_quality_log.sh" "$CMD_ID" "CLEAR" "no" "0" 2>&1; then
            echo "  cmd_quality_log: OK"
        else
            echo "  [INFO] cmd_quality_log: WARN (logging failed, non-blocking)"
        fi
    else
        echo "  SKIP (cmd_quality_log.sh not found)"
    fi

    # ─── 軍師gate_result自動還流（GATE CLEAR時、ベストエフォート） ───
    echo ""
    echo "Gunshi gate_result reflux (GATE CLEAR):"
    if [ -f "$SCRIPT_DIR/scripts/gunshi_gate_reflux.sh" ]; then
        bash "$SCRIPT_DIR/scripts/gunshi_gate_reflux.sh" "$CMD_ID" "CLEAR" 2>&1 || true
    else
        echo "  SKIP (gunshi_gate_reflux.sh not found)"
    fi

    # ─── GATE CLEAR時 insight候補通知（cmd_1217: lesson_candidate/decision_candidate found:true検出） ───
    echo ""
    echo "Insight candidate detection (GATE CLEAR):"
    INSIGHT_TMP=$(mktemp)
    trap 'rm -f "$INSIGHT_TMP"' EXIT
    INSIGHT_COUNT=0
    for task_file in "$TASKS_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
            continue
        fi
        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name")
        [ -f "$report_file" ] || continue

        insight_line=$(awk '
            /lesson_candidate:/{sec="lc"; next}
            /decision_candidate:/{sec="dc"; next}
            /^[^ ]/ && sec!=""{sec=""}
            sec=="lc" && /found: true/{lc_found=1}
            sec=="lc" && /title:/ && !lc_title{t=$0; sub(/.*title:\s*/, "", t); gsub(/^["'"'"']+|["'"'"']+$/, "", t); lc_title=t}
            sec=="lc" && /summary:/ && !lc_title{t=$0; sub(/.*summary:\s*/, "", t); gsub(/^["'"'"']+|["'"'"']+$/, "", t); lc_title=t}
            sec=="dc" && /found: true/{dc_found=1}
            sec=="dc" && /title:/ && !dc_title{t=$0; sub(/.*title:\s*/, "", t); gsub(/^["'"'"']+|["'"'"']+$/, "", t); dc_title=t}
            sec=="dc" && /summary:/ && !dc_title{t=$0; sub(/.*summary:\s*/, "", t); gsub(/^["'"'"']+|["'"'"']+$/, "", t); dc_title=t}
            sec=="dc" && /question:/ && !dc_title{t=$0; sub(/.*question:\s*/, "", t); gsub(/^["'"'"']+|["'"'"']+$/, "", t); dc_title=t}
            END{
                out=""
                if(lc_found){t=substr(lc_title,1,80); out="LC: " (t?t:"(untitled)")}
                if(dc_found){t=substr(dc_title,1,80); if(out) out=out " / "; out=out "DC: " (t?t:"(untitled)")}
                if(out) print out
            }
        ' "$report_file" 2>/dev/null)

        if [ -n "$insight_line" ]; then
            INSIGHT_COUNT=$((INSIGHT_COUNT + 1))
            echo "  ${ninja_name}: ${insight_line}"
            echo "${ninja_name}: ${insight_line}" >> "$INSIGHT_TMP"
        fi
    done

    if [ "$INSIGHT_COUNT" -gt 0 ]; then
        DASHBOARD="$SCRIPT_DIR/dashboard.md"
        if [ -f "$DASHBOARD" ]; then
            # Build insert text from INSIGHT_TMP
            _insight_insert=""
            while IFS= read -r _note; do
                [ -z "$_note" ] && continue
                _insight_insert="${_insight_insert}- [INSIGHT] ${CMD_ID} ${_note}\n"
            done < "$INSIGHT_TMP"
            if [ -n "$_insight_insert" ]; then
                awk -v ins="$_insight_insert" '
                    { print }
                    /^## 将軍宛報告[[:space:]]*$/ { printf "%s", ins }
                ' "$DASHBOARD" > "${DASHBOARD}.tmp" && mv "${DASHBOARD}.tmp" "$DASHBOARD" 2>/dev/null \
                    || echo "  [INFO] dashboard insight append failed (non-blocking)"
            fi
            echo "  Notified: ${INSIGHT_COUNT} insight candidate(s) → dashboard 将軍宛セクション"
        fi
    else
        echo "  OK: no insight candidates (found:true=0)"
    fi
    rm -f "$INSIGHT_TMP"

    # ─── lesson_candidate未登録 WARN（cmd_1256: GATE CLEAR時、情報提供のみ） ───
    echo ""
    echo "Lesson candidate registration check (GATE CLEAR):"
    LC_WARN_COUNT=0
    for task_file in "$TASKS_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        if ! grep -q "parent_cmd: ${CMD_ID}" "$task_file" 2>/dev/null; then
            continue
        fi
        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name")
        [ -f "$report_file" ] || continue

        lc_warn=$(awk '
            /lesson_candidate:/ { sec=1; next }
            sec && /^[^ ]/ { exit }
            sec && /found: true/ { found=1 }
            sec && /title:/ && !title { t=$0; sub(/.*title:[[:space:]]*/, "", t); gsub(/^["'"'"']+|["'"'"']+$/, "", t); title=t }
            END { if (found && title) print substr(title, 1, 80) }
        ' "$report_file" 2>/dev/null)

        if [ -n "$lc_warn" ]; then
            LC_WARN_COUNT=$((LC_WARN_COUNT + 1))
            echo "  WARN: lesson_candidate未登録 — ${ninja_name}: ${lc_warn} — lesson_write.shで登録せよ"
        fi
    done
    if [ "$LC_WARN_COUNT" -eq 0 ]; then
        echo "  OK: no pending lesson_candidates"
    fi

    # ─── Workaround率表示（情報のみ、BLOCKしない） ───
    echo ""
    echo "Workaround rate (GATE CLEAR):"
    if [ -x "$SCRIPT_DIR/scripts/gates/gate_workaround_rate.sh" ]; then
        bash "$SCRIPT_DIR/scripts/gates/gate_workaround_rate.sh" --last 10 2>&1 || echo "  [INFO] gate_workaround_rate.sh failed (non-blocking)"
    else
        echo "  SKIP (gate_workaround_rate.sh not found)"
    fi

    # ─── 第三層loop健全性チェック（GATE CLEAR時、自動insight起票+情報表示） ───
    echo ""
    echo "Loop health (GATE CLEAR):"
    if [ -f "$SCRIPT_DIR/scripts/gates/gate_loop_health.sh" ]; then
        loop_output=$(bash "$SCRIPT_DIR/scripts/gates/gate_loop_health.sh" 2>&1) || true
        if echo "$loop_output" | grep -q "Auto-Insight"; then
            echo "$loop_output" | grep -E "CREATED:|計.*件" | head -5
        fi
        if echo "$loop_output" | grep -q "WARNING:"; then
            echo "  [WARN] $(echo "$loop_output" | grep 'WARNING:' | head -1)"
        else
            echo "  OK"
        fi
    else
        echo "  SKIP (gate_loop_health.sh not found)"
    fi

    # ─── archive実行（GATE CLEAR後、全チェック+ポストプロセス完了後） ───
    # cmd_1302: 報告YAMLをGATEが読み終わってからアーカイブ
    echo ""
    echo "Archive (post-GATE CLEAR):"
    if [ ! -f "$GATES_DIR/archive.done" ]; then
        if bash "$SCRIPT_DIR/scripts/archive_completed.sh" "$CMD_ID" 2>&1; then
            echo "  archive: OK"
        else
            echo "  [INFO] archive: WARN (failed, non-blocking)"
        fi
    else
        echo "  archive: already exists (skip)"
    fi

    # ─── git push（GATE CLEAR後、殿裁定2026-03-24: GATE CLEARしたcommitは家老がpush） ───
    echo ""
    echo "Git push (post-GATE CLEAR):"
    if git -C "$PROJECT_DIR" push 2>&1; then
        echo "  git push: OK"
    else
        echo "  [INFO] git push: WARN (push failed, non-blocking)"
    fi

    # cmd_1337: ダッシュボード自動更新（GATE CLEAR時のみ、バックグラウンド実行）
    bash "$SCRIPT_DIR/scripts/dashboard_auto_section.sh" &

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
        echo "  [INFO] append_lesson_tracking failed (non-blocking)"
    fi
    if update_lesson_impact_tsv "$CMD_ID" "BLOCK" 2>&1; then
        true
    else
        echo "  [INFO] update_lesson_impact_tsv failed (non-blocking)"
    fi
    bash "$SCRIPT_DIR/scripts/lesson_impact_analysis.sh" --sync-counters 2>&1 || echo "  [INFO] sync-counters failed (non-blocking)"

    # ─── GATE BLOCK時自動draft教訓生成（ベストエフォート） ───
    echo ""
    echo "Auto-draft lessons for GATE BLOCK:"
    if [ -n "$CMD_PROJECT" ]; then
        DRAFT_GENERATED=0

        # Pattern 1: lessons_useful empty
        lr_empty_ninjas=()
        for reason in "${BLOCK_REASONS[@]}"; do
            if [[ "$reason" == *":empty_lessons_useful:"* || "$reason" == *":empty_lesson_referenced:"* || "$reason" == *":null_lessons_useful"* ]]; then
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
                echo "  [INFO] draft生成失敗 (lessons_useful_empty)"
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
                    echo "  [INFO] draft生成失敗 (draft_remaining)"
                fi
                break
            fi
        done

        # Pattern 3: reviewed_false — 廃止 (cmd_533: push型移行)

        echo "  Generated: ${DRAFT_GENERATED} draft lesson(s)"
    else
        echo "  SKIP (project not found in cmd)"
    fi

    # ─── GATE BLOCK時 harmful判定（教訓参照しなかった忍者の注入教訓にharmful +1） ───
    echo ""
    echo "Lesson score update (harmful - GATE BLOCK):"
    # harmful判定はACE Reflector方式に移行(cmd_470)。自己申告不在での一律harmful廃止。
    echo "  SKIP (disabled)"

    # ─── cmd品質ログ記録（GATE BLOCK時、ベストエフォート） ───
    echo ""
    echo "Cmd quality log (GATE BLOCK):"
    if [ -f "$SCRIPT_DIR/scripts/cmd_quality_log.sh" ]; then
        block_notes=""
        if [ ${#BLOCK_REASONS[@]} -gt 0 ]; then
            block_notes=$(IFS='|'; echo "${BLOCK_REASONS[*]}")
        fi
        if bash "$SCRIPT_DIR/scripts/cmd_quality_log.sh" "$CMD_ID" "BLOCK" "no" "0" "$block_notes" 2>&1; then
            echo "  cmd_quality_log: OK"
        else
            echo "  [INFO] cmd_quality_log: WARN (logging failed, non-blocking)"
        fi
    else
        echo "  SKIP (cmd_quality_log.sh not found)"
    fi

    # ─── Workaround率表示（情報のみ、BLOCKしない） ───
    echo ""
    echo "Workaround rate (GATE BLOCK):"
    if [ -x "$SCRIPT_DIR/scripts/gates/gate_workaround_rate.sh" ]; then
        bash "$SCRIPT_DIR/scripts/gates/gate_workaround_rate.sh" --last 10 2>&1 || echo "  [INFO] gate_workaround_rate.sh failed (non-blocking)"
    else
        echo "  SKIP (gate_workaround_rate.sh not found)"
    fi

    # ─── GATE BLOCK時 harmful閾値による教訓自動deprecate ───
    echo ""
    echo "Auto-deprecate check (harmful threshold):"
    if [ -n "$CMD_PROJECT" ] && [ -f "$SCRIPT_DIR/scripts/lesson_deprecate.sh" ]; then
        DEPRECATE_COUNT=0
        DEPRECATE_LESSONS_FILE="$SCRIPT_DIR/projects/${CMD_PROJECT}/lessons.yaml"
        if [ -f "$DEPRECATE_LESSONS_FILE" ]; then
            # harmful_count >= 5 かつ harmful_count > helpful_count の教訓を検出
            deprecate_targets=$(awk '
                /^[[:space:]]*- id:/ {
                    if (lid != "" && !deprecated && harmful >= 5 && harmful > helpful)
                        printf "%s\t%d\t%d\n", lid, harmful, helpful
                    lid = $0; sub(/.*- id:[[:space:]]*/, "", lid); gsub(/[" \t]/, "", lid)
                    harmful = 0; helpful = 0; deprecated = 0
                    next
                }
                /^[[:space:]]+harmful_count:/ { v=$0; sub(/.*harmful_count:[[:space:]]*/, "", v); gsub(/[" \t]/, "", v); harmful = v + 0 }
                /^[[:space:]]+helpful_count:/ { v=$0; sub(/.*helpful_count:[[:space:]]*/, "", v); gsub(/[" \t]/, "", v); helpful = v + 0 }
                /^[[:space:]]+deprecated: true/ { deprecated = 1 }
                /^[[:space:]]+status:[[:space:]]*deprecated/ { deprecated = 1 }
                /^[[:space:]]+deprecated_by:/ { v=$0; sub(/.*deprecated_by:[[:space:]]*/, "", v); gsub(/[" \t]/, "", v); if (v != "") deprecated = 1 }
                END {
                    if (lid != "" && !deprecated && harmful >= 5 && harmful > helpful)
                        printf "%s\t%d\t%d\n", lid, harmful, helpful
                }
            ' "$DEPRECATE_LESSONS_FILE" 2>/dev/null)

            if [ -n "$deprecate_targets" ]; then
                while IFS=$'\t' read -r lid harmful helpful; do
                    [ -z "$lid" ] && continue
                    if bash "$SCRIPT_DIR/scripts/lesson_deprecate.sh" "$CMD_PROJECT" "$lid" "AUTO-DEPRECATE: harmful=${harmful} > helpful=${helpful}" 2>&1; then
                        echo "  [gate] AUTO-DEPRECATE: ${lid} (harmful=${harmful} > helpful=${helpful})"
                        DEPRECATE_COUNT=$((DEPRECATE_COUNT + 1))
                    else
                        echo "  [INFO] ${lid}: auto-deprecate failed (non-blocking)"
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
