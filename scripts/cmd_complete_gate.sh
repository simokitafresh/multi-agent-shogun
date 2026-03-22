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
check_project_code_stubs() {
    local cmd_id="$1"
    local cmd_project="$2"

    SCRIPT_DIR_ENV="$SCRIPT_DIR" CMD_ID_ENV="$cmd_id" CMD_PROJECT_ENV="$cmd_project" python3 - <<'PY'
import os
import re
import subprocess
import sys

import yaml

script_dir = os.environ["SCRIPT_DIR_ENV"]
cmd_id = os.environ["CMD_ID_ENV"].strip()
cmd_project = os.environ["CMD_PROJECT_ENV"].strip().strip("'\"")

DEFAULT_EXTS = ["py", "ts", "tsx", "js", "jsx", "kt", "java"]
LANGUAGE_ALIASES = {
    "python": ["py"],
    "py": ["py"],
    "typescript": ["ts", "tsx"],
    "ts": ["ts"],
    "tsx": ["tsx"],
    "javascript": ["js", "jsx"],
    "js": ["js"],
    "jsx": ["jsx"],
    "kotlin": ["kt"],
    "kt": ["kt"],
    "java": ["java"],
}
TOKEN_RE = re.compile(r"\b(?:TODO|FIXME|XXX|HACK|PLACEHOLDER)\b", re.IGNORECASE)
RETURN_RE = re.compile(r"\breturn\s+(?:null|None)\b|\breturn\s*\{\s*\}|\breturn\s*\[\s*\]")
PASS_RE = re.compile(r"^\s*pass(?:\s*#.*)?\s*$")
EXCEPT_RE = re.compile(r"^\s*except\b.*:\s*(?:pass(?:\s*#.*)?\s*)?$")
HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")


def emit(kind: str, message: str, details: list[str] | None = None) -> None:
    print(f"{kind}\t{message}")
    for line in details or []:
        print(line)


def load_yaml(path: str) -> dict:
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    return data if isinstance(data, dict) else {}


def resolve_project_path(project_id: str) -> str:
    project_yaml = load_yaml(os.path.join(script_dir, "projects", f"{project_id}.yaml"))
    for candidate in (
        project_yaml.get("project", {}).get("path"),
        project_yaml.get("path"),
    ):
        if isinstance(candidate, str) and candidate.strip():
            return candidate.strip()

    config_yaml = load_yaml(os.path.join(script_dir, "config", "projects.yaml"))
    for project in config_yaml.get("projects", []):
        if not isinstance(project, dict):
            continue
        if str(project.get("id", "")).strip() != project_id:
            continue
        candidate = str(project.get("path", "")).strip()
        if candidate:
            return candidate
    return ""


def resolve_extensions(project_id: str) -> set[str]:
    project_yaml = load_yaml(os.path.join(script_dir, "projects", f"{project_id}.yaml"))
    raw = project_yaml.get("languages")
    if raw is None and isinstance(project_yaml.get("project"), dict):
        raw = project_yaml["project"].get("languages")

    values: list[str] = []
    if isinstance(raw, str):
        values = [raw]
    elif isinstance(raw, list):
        values = [item for item in raw if isinstance(item, str)]

    extensions: set[str] = set()
    for value in values:
        normalized = value.strip().lower().lstrip(".")
        if not normalized:
            continue
        mapped = LANGUAGE_ALIASES.get(normalized)
        if mapped:
            extensions.update(mapped)
        else:
            extensions.add(normalized)

    if not extensions:
        extensions.update(DEFAULT_EXTS)
    return extensions


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


def is_test_file(path: str) -> bool:
    lowered = path.lower()
    return "test" in lowered or "spec" in lowered


def classify_line(file_path: str, ext: str, line: str, prior_lines: list[str]) -> list[str]:
    findings: list[str] = []
    if RETURN_RE.search(line):
        findings.append("return_stub")

    if TOKEN_RE.search(line) and not is_test_file(file_path):
        findings.append("marker_stub")

    if ext == "py" and PASS_RE.match(line):
        allowed = False
        for previous in reversed(prior_lines):
            stripped = previous.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if EXCEPT_RE.match(stripped):
                allowed = True
            break
        if not allowed:
            findings.append("pass_stub")

    return findings


if not cmd_project:
    emit("SKIP", "project not found in cmd")
    raise SystemExit(0)

project_path = resolve_project_path(cmd_project)
if not project_path:
    emit("SKIP", f"project path not found for: {cmd_project}")
    raise SystemExit(0)

if not os.path.isdir(project_path):
    emit("SKIP", f"project path missing: {project_path}")
    raise SystemExit(0)

git_dir_proc = git(project_path, "rev-parse", "--git-dir")
if git_dir_proc.returncode != 0:
    emit("SKIP", f"git repo not found: {project_path}")
    raise SystemExit(0)

# cmd_1244: uncommitted変更検出 — commit漏れをBLOCKで構造的に防止
unstaged = git(project_path, "diff", "--name-only")
staged = git(project_path, "diff", "--cached", "--name-only")
uncommitted_files: list[str] = []
if unstaged.returncode == 0 and unstaged.stdout.strip():
    uncommitted_files.extend(unstaged.stdout.strip().splitlines())
if staged.returncode == 0 and staged.stdout.strip():
    uncommitted_files.extend(staged.stdout.strip().splitlines())
if uncommitted_files:
    emit("BLOCK", f"commit_missing: {len(uncommitted_files)} uncommitted file(s) in {project_path}", uncommitted_files[:10])
    raise SystemExit(1)

commit_count = detect_cmd_commit_count(project_path, cmd_id)
if commit_count < 0:
    emit("ERR", f"git log failed for {project_path}")
    raise SystemExit(0)
if commit_count == 0:
    emit("SKIP", f"no contiguous HEAD commits mention {cmd_id} in {project_path}")
    raise SystemExit(0)

base_ref = f"HEAD~{commit_count}"
base_check = git(project_path, "rev-parse", "--verify", base_ref)
if base_check.returncode != 0:
    emit("SKIP", f"{base_ref} not available in {project_path}")
    raise SystemExit(0)

extensions = resolve_extensions(cmd_project)
diff_proc = git(project_path, "diff", "--unified=1", "--no-color", base_ref, "HEAD", "--", ".")
if diff_proc.returncode != 0:
    emit("ERR", f"git diff failed for {project_path}: {diff_proc.stderr.strip()}")
    raise SystemExit(0)

current_file = ""
current_ext = ""
current_line = 0
prior_lines: list[str] = []
matches: list[tuple[str, int, str, str]] = []
seen_files: set[str] = set()

for raw in diff_proc.stdout.splitlines():
    if raw.startswith("+++ b/"):
        current_file = raw[6:]
        current_ext = os.path.splitext(current_file)[1].lstrip(".").lower()
        prior_lines = []
        continue

    if raw.startswith("@@"):
        match = HUNK_RE.match(raw)
        current_line = int(match.group(1)) - 1 if match else 0
        prior_lines = []
        continue

    if not current_file or current_ext not in extensions:
        continue

    if raw.startswith("-") and not raw.startswith("---"):
        continue

    if raw.startswith(" ") or raw == "":
        if raw.startswith(" "):
            current_line += 1
            prior_lines.append(raw[1:])
        continue

    if raw.startswith("+") and not raw.startswith("+++"):
        current_line += 1
        line = raw[1:]
        for finding in classify_line(current_file, current_ext, line, prior_lines):
            matches.append((current_file, current_line, finding, line.strip()))
            seen_files.add(current_file)
        prior_lines.append(line)

if not matches:
    emit(
        "OK",
        f"no stub patterns in added lines (base={base_ref}, commits={commit_count}, ext={','.join(sorted(extensions))})",
    )
    raise SystemExit(0)

details = []
for file_path, line_no, finding, snippet in matches[:10]:
    details.append(f"{file_path}:{line_no}: [{finding}] {snippet}")

if len(matches) > 10:
    details.append(f"... ({len(matches)} hits across {len(seen_files)} file(s), first 10 shown)")

emit(
    "WARN",
    f"{len(matches)} stub-like added line(s) across {len(seen_files)} file(s) (base={base_ref}, commits={commit_count})",
    details,
)
PY
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
        if row_cmd_id in tracked_row_ids and row.get("result") == "pending":
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

    TASK_FILE_ENV="$task_file" python3 - <<'PY'
import os
import yaml

task_file = os.environ["TASK_FILE_ENV"]

try:
    with open(task_file, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    print("unknown")
    raise SystemExit(0)

task = data.get("task", {}) if isinstance(data, dict) else {}
if not isinstance(task, dict):
    print("unknown")
    raise SystemExit(0)

tokens = []
for key in ("task_type", "type", "task_id", "subtask_id"):
    value = task.get(key)
    if value is not None:
        tokens.append(str(value).strip().lower())

text = " ".join(tokens)
if "review" in text:
    print("review")
elif "implement" in text or "impl" in text:
    print("implement")
elif "recon" in text or "scout" in text:
    print("recon")
else:
    print("unknown")
PY
}

check_how_it_works_status() {
    local report_file="$1"

    REPORT_FILE_ENV="$report_file" python3 - <<'PY'
import os
import yaml

report_file = os.environ["REPORT_FILE_ENV"]

try:
    with open(report_file, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    print("error")
    raise SystemExit(0)

if not isinstance(data, dict):
    print("error")
    raise SystemExit(0)

value = data.get("how_it_works")
if value is None:
    print("missing")
elif isinstance(value, str):
    print("ok" if value.strip() else "empty")
elif isinstance(value, list):
    has_text = any(isinstance(item, str) and item.strip() for item in value)
    print("ok" if has_text else "empty")
else:
    print("empty")
PY
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

    # 1. archive.done — archive_completed.sh を先に実行
    if [ ! -f "$gates_dir/archive.done" ]; then
        echo "  archive: generating..."
        if bash "$SCRIPT_DIR/scripts/archive_completed.sh" "$cmd_id" 2>&1; then
            echo "  archive: preflight OK"
        else
            echo "  [INFO] archive: preflight WARN (failed, non-blocking)"
        fi
    else
        echo "  archive: already exists (skip)"
    fi

    # 2. lesson.done — found:true候補確認後、適切な方法でフラグ生成
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
            echo "  [INFO] review_gate: preflight WARN (review may not be complete)"
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
                echo "  [INFO] report_merge: preflight WARN (merge may not be ready)"
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
    if bash "$SCRIPT_DIR/scripts/dashboard_update.sh" "$CMD_ID"; then
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

# ─── 報告YAML存在チェック（cmd_1192: タスクあり報告なしをBLOCK） ───
level_heading "[L1]" "Report YAML existence check:"
REPORT_TASK_COUNT=0
REPORT_FOUND_COUNT=0
REPORT_MISSING_FILES=()
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
        REPORT_MISSING_FILES+=("$(basename "$report_file")")
        echo "  [CRITICAL] ${ninja_name}: MISSING ← 報告YAML不在: $(basename "$report_file")"
    fi
done

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
            # Python判定: lessons_usefulが非空リスト+各要素の形式チェック（cmd_536 null検知 + cmd_1045 形式厳格化）
            lr_status=$(python3 -c "
import yaml
result = 'error'
try:
    with open('$report_file') as f:
        data = yaml.safe_load(f)
    if not data:
        result = 'empty'
    elif 'lessons_useful' in data and data['lessons_useful'] is None:
        # cmd_536 AC4: lessons_useful=null(明示的未記入)を検出
        result = 'null'
    else:
        lr = data.get('lessons_useful')
        if lr is None:
            lr = data.get('lesson_referenced')
        if lr and isinstance(lr, list) and len(lr) > 0:
            # cmd_1045: 各要素の形式検証（dict + useful:bool 必須）
            valid = True
            fill_this = False
            for item in lr:
                if not isinstance(item, dict):
                    valid = False
                    break
                # cmd_1180: FILL_THIS検出（invalid_formatより先にチェック）
                if item.get('useful') == 'FILL_THIS' or item.get('reason') == 'FILL_THIS':
                    fill_this = True
                    break
                if item.get('useful') is None:
                    valid = False
                    break
                if not isinstance(item.get('useful'), bool):
                    valid = False
                    break
            if fill_this:
                result = 'fill_this_remaining'
            elif valid:
                result = 'ok'
            else:
                result = 'invalid_format'
        else:
            result = 'empty'
except Exception:
    result = 'error'
print(result)
" 2>/dev/null)

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

    acv_status=$(python3 -c "
import yaml, sys

def is_legacy_numeric(v):
    # Legacy numeric ac_version check
    if v is None:
        return False
    if isinstance(v, bool):
        return False
    if isinstance(v, (int, float)):
        return True
    s = str(v).strip()
    try:
        int(s)
        return True
    except (ValueError, TypeError):
        return False

def normalize(v):
    if v is None:
        return None
    s = str(v).strip()
    if s == '' or s.lower() in ('none', 'null'):
        return None
    return s

try:
    with open('$task_file') as tf:
        tdata = yaml.safe_load(tf) or {}
    with open('$report_file') as rf:
        rdata = yaml.safe_load(rf) or {}

    task = tdata.get('task', {}) if isinstance(tdata, dict) else {}
    raw_task_ac = task.get('ac_version')
    raw_read_ac = rdata.get('ac_version_read')
    task_ac = normalize(raw_task_ac)
    read_ac = normalize(raw_read_ac)

    if task_ac is None:
        print('task_missing')
    elif is_legacy_numeric(raw_task_ac):
        _r = read_ac or '-'
        print(f'legacy_skip\\t{task_ac}\\t{_r}')
    elif read_ac is None:
        print(f'report_missing\\t{task_ac}\\t-')
    elif task_ac == read_ac:
        print(f'ok\\t{task_ac}\\t{read_ac}')
    else:
        print(f'mismatch\\t{task_ac}\\t{read_ac}')
except Exception:
    print('error')
" 2>/dev/null)

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
        nlr = lc.get('no_lesson_reason', '')
        if not nlr or not str(nlr).strip():
            print('ok_false_no_reason')
        else:
            print('ok_false')
    elif lc['found'] == True:
        title = lc.get('title', '')
        detail = lc.get('detail', '')
        missing = []
        if not title or not str(title).strip():
            missing.append('title')
        if not detail or not str(detail).strip():
            missing.append('detail')
        if missing:
            print('found_true_empty:' + ','.join(missing))
        else:
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
                lc_recheck=$(python3 -c "
import yaml, sys
try:
    with open('$report_file') as f:
        data = yaml.safe_load(f)
    lc = data.get('lesson_candidate')
    if isinstance(lc, dict) and 'found' in lc:
        print('ok')
    else:
        print('ng')
except:
    print('ng')
" 2>/dev/null)
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

    bc_status=$(python3 -c "
import yaml, sys
try:
    with open('$report_file') as f:
        data = yaml.safe_load(f)
    if not data:
        print('missing')
        sys.exit(0)
    bc = data.get('binary_checks')
    if bc is None:
        print('missing')
    elif not isinstance(bc, list):
        print('malformed')
    else:
        fails = []
        for i, item in enumerate(bc):
            if not isinstance(item, dict):
                fails.append(f'item_{i}:not_dict')
                continue
            result = item.get('result', '')
            if str(result).strip().upper() != 'PASS':
                check_name = item.get('check', f'item_{i}')
                fails.append(str(check_name))
        if fails:
            print('fail:' + '|'.join(fails))
        else:
            print('ok')
except:
    print('error')
" 2>/dev/null)

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
    deviation_status=$(REPORT_FILE_ENV="$report_file" python3 - <<'PY'
import os
import yaml

report_file = os.environ["REPORT_FILE_ENV"]

try:
    with open(report_file, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    print("error\tparse_error")
    raise SystemExit(0)

if not isinstance(data, dict):
    print("error\treport_not_dict")
    raise SystemExit(0)

result = data.get("result")
if not isinstance(result, dict):
    print("skip\tresult missing or not a mapping")
    raise SystemExit(0)

deviation = result.get("deviation")
if deviation is None:
    print("skip\tresult.deviation not present")
elif not isinstance(deviation, list):
    print("skip\tresult.deviation not a list")
elif len(deviation) == 0:
    print("skip\tresult.deviation empty (count 0)")
elif len(deviation) >= 4:
    print(f"warn\t{len(deviation)}")
else:
    print(f"ok\t{len(deviation)}")
PY
)

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
    analysis_status=$(REPORT_FILE_ENV="$report_file" python3 - <<'PY'
import os
import yaml

report_file = os.environ["REPORT_FILE_ENV"]

try:
    with open(report_file, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    print("error\tparse_error")
    raise SystemExit(0)

if not isinstance(data, dict):
    print("error\treport_not_dict")
    raise SystemExit(0)

result = data.get("result")
if not isinstance(result, dict):
    print("skip\tresult missing or not a mapping")
    raise SystemExit(0)

value = result.get("analysis_paralysis_triggered")
if value is True:
    print("warn\tanalysis paralysis was triggered during this task")
elif value is False:
    print("ok\tanalysis_paralysis_triggered=false")
elif value is None:
    print("skip\tanalysis_paralysis_triggered not present")
else:
    print("skip\tanalysis_paralysis_triggered not boolean")
PY
)

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

            review_status=$(REPORT_FILE_ENV="$report_file" python3 - <<'PY'
import os
import yaml

report_file = os.environ["REPORT_FILE_ENV"]

try:
    with open(report_file, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    print("parse_error\tparse_error\t")
    raise SystemExit(0)

if not isinstance(data, dict):
    print("parse_error\tparse_error\t")
    raise SystemExit(0)

verdict = data.get("verdict")
if isinstance(verdict, str) and verdict in ("PASS", "FAIL"):
    verdict_status = "ok"
else:
    verdict_status = "ng"

self_gate = data.get("self_gate_check")
required = ("lesson_ref", "lesson_candidate", "status_valid", "purpose_fit")
if isinstance(self_gate, dict) and all(str(self_gate.get(key, "")).strip() == "PASS" for key in required):
    gate_status = "ok"
else:
    gate_status = "ng"

worker_id = str(data.get("worker_id", "")).strip()
print(f"{verdict_status}\t{gate_status}\t{worker_id}")
PY
)

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
    overlapping_workers=$(python3 - "$IMPLEMENTER_IDS" "$REVIEWER_IDS" <<'PY'
import sys

implementers = {item for item in sys.argv[1].strip("|").split("|") if item}
reviewers = {item for item in sys.argv[2].strip("|").split("|") if item}
overlap = sorted(implementers & reviewers)
print(",".join(overlap))
PY
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
    test_skip_status=$(REPORT_FILE_ENV="$report_file" python3 - <<'PY'
import os
import yaml

report_file = os.environ["REPORT_FILE_ENV"]

try:
    with open(report_file, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    print("error\tparse_error")
    raise SystemExit(0)

if not isinstance(data, dict):
    print("error\treport_not_dict")
    raise SystemExit(0)

# test_skip_count (top-level) を優先検索
skip_count = data.get("test_skip_count")

# フォールバック: test_results.skipped
if skip_count is None:
    test_results = data.get("test_results")
    if test_results is None:
        print("warn\ttest_results not present")
        raise SystemExit(0)
    elif isinstance(test_results, dict):
        skip_count = test_results.get("skipped")
        if skip_count is None:
            print("warn\ttest_results.skipped not present")
            raise SystemExit(0)
    else:
        print("warn\ttest_results not a mapping")
        raise SystemExit(0)

try:
    count = int(skip_count)
except (ValueError, TypeError):
    print(f"warn\ttest_skip_count not a number: {skip_count}")
    raise SystemExit(0)

if count > 0:
    print(f"block\t{count}")
elif count == 0:
    print(f"ok\t{count}")
else:
    print(f"warn\ttest_skip_count negative: {count}")
PY
)

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
            ci_conclusion=$(printf '%s' "$ci_result" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if data and isinstance(data, list) and len(data) > 0:
        print(data[0].get('conclusion', ''))
    else:
        print('')
except:
    print('')
" 2>/dev/null)
            ci_run_id=$(printf '%s' "$ci_result" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if data and isinstance(data, list) and len(data) > 0:
        print(data[0].get('databaseId', ''))
    else:
        print('')
except:
    print('')
" 2>/dev/null)
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
    if bash "$SCRIPT_DIR/scripts/gates/gate_yaml_status.sh" "$CMD_ID" 2>&1; then
        true
    else
        echo "  [INFO] gate_yaml_status.sh failed (non-blocking)"
    fi
    update_status "$CMD_ID" || echo "  [INFO] update_status failed (non-blocking)"
    append_changelog "$CMD_ID" || echo "  [INFO] append_changelog failed (non-blocking)"
    if append_lesson_tracking "$CMD_ID" "CLEAR" 2>&1; then
        true
    else
        echo "  [INFO] append_lesson_tracking failed (non-blocking)"
    fi
    if update_lesson_impact_tsv "$CMD_ID" "CLEAR" 2>&1; then
        true
    else
        echo "  [INFO] update_lesson_impact_tsv failed (non-blocking)"
    fi
    bash "$SCRIPT_DIR/scripts/lesson_impact_analysis.sh" --sync-counters 2>&1 || echo "  [INFO] sync-counters failed (non-blocking)"

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
    if bash "$SCRIPT_DIR/scripts/dashboard_update.sh" "$CMD_ID"; then
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

        insight_line=$(REPORT_FILE="$report_file" python3 -c "
import yaml, os, sys
try:
    with open(os.environ['REPORT_FILE']) as f:
        data = yaml.safe_load(f) or {}
    lc = data.get('lesson_candidate', {})
    dc = data.get('decision_candidate', {})
    lc_found = isinstance(lc, dict) and lc.get('found') is True
    dc_found = isinstance(dc, dict) and dc.get('found') is True
    parts = []
    if lc_found:
        title = str(lc.get('title', lc.get('summary', '')))[:80]
        parts.append('LC: ' + title if title else 'LC: (untitled)')
    if dc_found:
        title = str(dc.get('title', dc.get('summary', dc.get('question', ''))))[:80]
        parts.append('DC: ' + title if title else 'DC: (untitled)')
    if parts:
        print(' / '.join(parts))
except:
    pass
" 2>/dev/null)

        if [ -n "$insight_line" ]; then
            INSIGHT_COUNT=$((INSIGHT_COUNT + 1))
            echo "  ${ninja_name}: ${insight_line}"
            echo "${ninja_name}: ${insight_line}" >> "$INSIGHT_TMP"
        fi
    done

    if [ "$INSIGHT_COUNT" -gt 0 ]; then
        DASHBOARD="$SCRIPT_DIR/dashboard.md"
        if [ -f "$DASHBOARD" ]; then
            DASHBOARD_FILE="$DASHBOARD" CMD_ID_ENV="$CMD_ID" INSIGHT_FILE="$INSIGHT_TMP" python3 -c "
import os, sys
dashboard = os.environ['DASHBOARD_FILE']
cmd_id = os.environ['CMD_ID_ENV']
insight_file = os.environ['INSIGHT_FILE']
try:
    with open(insight_file, 'r', encoding='utf-8') as f:
        notes = [line.strip() for line in f if line.strip()]
    if not notes:
        sys.exit(0)
    with open(dashboard, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    insert_idx = None
    for i, line in enumerate(lines):
        if line.strip() == '## 将軍宛報告':
            insert_idx = i + 1
            break
    if insert_idx is not None:
        for note in notes:
            lines.insert(insert_idx, f'- [INSIGHT] {cmd_id} {note}\n')
            insert_idx += 1
        with open(dashboard, 'w', encoding='utf-8') as f:
            f.writelines(lines)
except Exception as e:
    print(f'  [INFO] dashboard insight append failed: {e}', file=sys.stderr)
" 2>/dev/null || echo "  [INFO] dashboard insight append failed (non-blocking)"
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

        lc_warn=$(REPORT_FILE="$report_file" python3 -c "
import yaml, os
try:
    with open(os.environ['REPORT_FILE']) as f:
        data = yaml.safe_load(f) or {}
    lc = data.get('lesson_candidate', {})
    if isinstance(lc, dict) and lc.get('found') is True:
        title = str(lc.get('title', '')).strip()
        if title:
            print(title[:80])
except:
    pass
" 2>/dev/null)

        if [ -n "$lc_warn" ]; then
            LC_WARN_COUNT=$((LC_WARN_COUNT + 1))
            echo "  WARN: lesson_candidate未登録 — ${ninja_name}: ${lc_warn} — lesson_write.shで登録せよ"
        fi
    done
    if [ "$LC_WARN_COUNT" -eq 0 ]; then
        echo "  OK: no pending lesson_candidates"
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
