#!/usr/bin/env bash
# bash_speed_training.sh - ledger and dispatch helper for script speed training.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER_DEFAULT="$SCRIPT_DIR/logs/script_speed_training_ledger.yaml"
LEDGER="${SPEED_TRAINING_LEDGER:-$LEDGER_DEFAULT}"
STATE_DIR="${SHOGUN_STATE_DIR:-/tmp}"

usage() {
    cat <<'EOF'
Usage:
  bash tools/bash_speed_training.sh init-ledger [ledger]
  bash tools/bash_speed_training.sh next [ledger]
  bash tools/bash_speed_training.sh set-global-status <running|paused> [ledger]
  bash tools/bash_speed_training.sh mark-assigned <script_path> <ninja> [ledger]
  bash tools/bash_speed_training.sh record-after <script_path> <status> <after_ms> <test_result> <commit> [ledger]
  bash tools/bash_speed_training.sh record-real <script_path> <status> <before_real_ms> <after_real_ms> <real_measurement_command> <test_result> <commit> [ledger]
  bash tools/bash_speed_training.sh auto-deploy <ninja> [ledger]
EOF
}

now_iso() {
    date '+%Y-%m-%dT%H:%M:%S'
}

yaml_quote() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

measure_bash_n_ms() {
    local path="$1"
    local start end status
    start=$(date +%s%N)
    if timeout "${SPEED_TRAINING_BASELINE_TIMEOUT:-5}" bash -n "$SCRIPT_DIR/$path" >/dev/null 2>&1; then
        status=0
    else
        status=$?
    fi
    end=$(date +%s%N)
    printf '%s %s\n' "$(((end - start) / 1000000))" "$status"
}

lock_path() {
    local file_path="$1"
    local sanitized
    sanitized="${file_path//[\/: .#*?!]/_}"
    printf '/tmp/shogun_lock_%s.lock' "${sanitized: -48}"
}

with_ledger_lock() {
    local ledger="$1"
    shift
    mkdir -p "$(dirname "$ledger")"
    local lock
    lock=$(lock_path "$ledger")
    (
        flock -w 10 9
        "$@"
    ) 9>"$lock"
}

ledger_global_status() {
    local ledger="$1"
    awk -F': *' '$1 == "global_status" { gsub(/["'\'']/, "", $2); print $2; exit }' "$ledger" 2>/dev/null
}

init_ledger_unlocked() {
    local ledger="$1"
    local tmp count path ms syntax_status generated_at
    tmp=$(mktemp "${ledger}.XXXXXX")
    generated_at=$(now_iso)
    count=$(find "$SCRIPT_DIR/scripts" -type f -name '*.sh' | wc -l | tr -d ' ')
    {
        printf 'global_status: running\n'
        printf 'generated_at: %s\n' "$(yaml_quote "$generated_at")"
        printf 'measurement_command: %s\n' "$(yaml_quote 'timeout 5 bash -n <script_path> (syntax baseline only; not runtime speed)')"
        printf 'real_measurement_policy: %s\n' "$(yaml_quote 'Ninja must choose a safe runtime command per script: time bash script.sh <args>, --help, dry-run mode, or sandboxed equivalent. Record before_real_ms/after_real_ms with the same command before and after.')"
        printf 'script_count: %s\n' "$count"
        printf 'entries:\n'
        while IFS= read -r abs_path; do
            path="${abs_path#$SCRIPT_DIR/}"
            read -r ms syntax_status < <(measure_bash_n_ms "$path")
            printf '  - script_path: %s\n' "$(yaml_quote "$path")"
            printf '    status: pending\n'
            printf '    before_ms: %s\n' "$ms"
            printf '    after_ms: ""\n'
            printf '    before_real_ms: ""\n'
            printf '    after_real_ms: ""\n'
            printf '    real_measurement_command: ""\n'
            printf '    test_result: %s\n' "$(yaml_quote "baseline_bash_n_exit_${syntax_status}")"
            printf '    commit: ""\n'
            printf '    assigned_to: ""\n'
            printf '    updated_at: ""\n'
        done < <(find "$SCRIPT_DIR/scripts" -type f -name '*.sh' | sort)
    } > "$tmp"
    mv "$tmp" "$ledger"
}

cmd_record_real() {
    local script_path="${1:-}"
    local status="${2:-}"
    local before_real_ms="${3:-}"
    local after_real_ms="${4:-}"
    local real_measurement_command="${5:-}"
    local test_result="${6:-}"
    local commit="${7:-}"
    local ledger="${8:-$LEDGER}"
    [ -n "$script_path" ] && [ -n "$status" ] && [ -n "$before_real_ms" ] && [ -n "$after_real_ms" ] && [ -n "$real_measurement_command" ] && [ -n "$test_result" ] && [ -n "$commit" ] || { usage >&2; return 2; }
    [[ "$before_real_ms" =~ ^[0-9]+$ ]] || { echo "before_real_ms must be numeric" >&2; return 2; }
    [[ "$after_real_ms" =~ ^[0-9]+$ ]] || { echo "after_real_ms must be numeric" >&2; return 2; }
    if [ "$status" = "completed" ] && [ "$after_real_ms" -ge "$before_real_ms" ]; then
        echo "completed requires after_real_ms < before_real_ms" >&2
        return 2
    fi
    [ -f "$ledger" ] || return 1
    with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "status" "$status"
    with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "before_real_ms" "$before_real_ms"
    with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "after_real_ms" "$after_real_ms"
    with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "real_measurement_command" "$real_measurement_command"
    with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "test_result" "$test_result"
    with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "commit" "$commit"
    with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "updated_at" "$(now_iso)"
}

cmd_init_ledger() {
    local ledger="${1:-$LEDGER}"
    with_ledger_lock "$ledger" init_ledger_unlocked "$ledger"
}

cmd_next() {
    local ledger="${1:-$LEDGER}"
    [ -f "$ledger" ] || return 1
    if [ "$(ledger_global_status "$ledger")" != "running" ]; then
        return 2
    fi
    awk '
        /script_path:/ {
            path = $0
            sub(/^.*script_path:[[:space:]]*"?/, "", path)
            sub(/"?[[:space:]]*$/, "", path)
        }
        /^[[:space:]]+status:[[:space:]]*pending[[:space:]]*$/ {
            print path
            exit
        }
    ' "$ledger"
}

set_global_status_unlocked() {
    local ledger="$1"
    local new_status="$2"
    local tmp
    tmp=$(mktemp "${ledger}.XXXXXX")
    awk -v new_status="$new_status" '
        BEGIN { done = 0 }
        /^global_status:[[:space:]]*/ {
            print "global_status: " new_status
            done = 1
            next
        }
        { print }
        END {
            if (!done) print "global_status: " new_status
        }
    ' "$ledger" > "$tmp"
    mv "$tmp" "$ledger"
}

cmd_set_global_status() {
    local new_status="${1:-}"
    local ledger="${2:-$LEDGER}"
    case "$new_status" in
        running|paused) ;;
        *) usage >&2; return 2 ;;
    esac
    [ -f "$ledger" ] || cmd_init_ledger "$ledger"
    with_ledger_lock "$ledger" set_global_status_unlocked "$ledger" "$new_status"
}

update_entry_field_unlocked() {
    local ledger="$1"
    local script_path="$2"
    local field="$3"
    local value="$4"
    local tmp
    tmp=$(mktemp "${ledger}.XXXXXX")
    awk -v script_path="$script_path" -v field="$field" -v value="$value" '
        function q(v,    s) {
            s = v
            gsub(/\\/, "\\\\", s)
            gsub(/"/, "\\\"", s)
            return "\"" s "\""
        }
        /^[[:space:]]*-[[:space:]]+script_path:/ {
            in_target = (index($0, "script_path: \"" script_path "\"") > 0)
            print
            next
        }
        in_target && $0 ~ "^[[:space:]]+" field ":" {
            if (value ~ /^[0-9]+$/ && field ~ /_ms$/) print "    " field ": " value
            else if (field == "status" && value ~ /^[A-Za-z0-9_.-]+$/) print "    " field ": " value
            else print "    " field ": " q(value)
            in_target = 0
            next
        }
        { print }
    ' "$ledger" > "$tmp"
    mv "$tmp" "$ledger"
}

cmd_mark_assigned() {
    local script_path="${1:-}"
    local ninja="${2:-}"
    local ledger="${3:-$LEDGER}"
    [ -n "$script_path" ] && [ -n "$ninja" ] || { usage >&2; return 2; }
    [ -f "$ledger" ] || return 1
    with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "status" "assigned"
    with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "assigned_to" "$ninja"
    with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "updated_at" "$(now_iso)"
}

cmd_record_after() {
    local script_path="${1:-}"
    local status="${2:-}"
    local after_ms="${3:-}"
    local test_result="${4:-}"
    local commit="${5:-}"
    local ledger="${6:-$LEDGER}"
    [ -n "$script_path" ] && [ -n "$status" ] && [ -n "$after_ms" ] && [ -n "$test_result" ] && [ -n "$commit" ] || { usage >&2; return 2; }
    [ -f "$ledger" ] || return 1
    with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "status" "$status"
    with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "after_ms" "$after_ms"
    with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "test_result" "$test_result"
    with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "commit" "$commit"
    with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "updated_at" "$(now_iso)"
}

write_training_task() {
    local tmp_task="$1"
    local cmd_id="$2"
    local script_path="$3"
    cat > "$tmp_task" <<EOF
task:
  parent_cmd: ${cmd_id}
  task_id: ${cmd_id}_standard
  task_type: speed_training
  project: infra
  target_path: ${script_path}
  scout_exempt: true
  status: assigned
  purpose: "Speed-train ${script_path}: measure real runtime before, improve safely, run script-specific tests, measure the same command after, and record real timings in ledger."
  acceptance_criteria:
    - id: AC1
      checks:
        - check: "before_ms bash -n baseline is read from script_speed_training_ledger as syntax-only reference"
        - check: "before_real_ms is measured with a safe runtime command chosen for this script (time bash script.sh <args>, --help, dry-run, or sandboxed equivalent)"
    - id: AC2
      checks:
        - check: "implementation improves runtime without reducing behavior or safety"
        - check: "script-specific verification passes with SKIP=0"
    - id: AC3
      checks:
        - check: "after_real_ms is measured with the same command as before_real_ms"
        - check: "after_real_ms is strictly lower than before_real_ms"
        - check: "real_measurement_command/test_result/commit are written back to script_speed_training_ledger"
EOF
}

cmd_auto_deploy() {
    local ninja="${1:-}"
    local ledger="${2:-$LEDGER}"
    local status script_path safe_name cmd_id tmp_task deploy_script
    [ -n "$ninja" ] || { usage >&2; return 2; }
    [ -f "$ledger" ] || cmd_init_ledger "$ledger"
    status=$(ledger_global_status "$ledger")
    if [ "$status" = "paused" ]; then
        echo "paused"
        return 0
    fi
    script_path=$(cmd_next "$ledger" || true)
    [ -n "$script_path" ] || { echo "no_pending"; return 1; }
    cmd_mark_assigned "$script_path" "$ninja" "$ledger"
    safe_name="${script_path#scripts/}"
    safe_name="${safe_name%.sh}"
    safe_name="${safe_name//[^A-Za-z0-9]/_}"
    cmd_id="cmd_training_speed_${safe_name}_$(date '+%Y%m%d%H%M%S')"
    mkdir -p "$STATE_DIR"
    tmp_task=$(mktemp "${STATE_DIR}/speed_training_${ninja}.XXXXXX.yaml")
    write_training_task "$tmp_task" "$cmd_id" "$script_path"
    deploy_script="$SCRIPT_DIR/scripts/deploy_task.sh"
    if [ "${SPEED_TRAINING_DRY_RUN:-0}" = "1" ]; then
        printf 'DRY_RUN deploy_task --direct --yaml %s %s %s\n' "$tmp_task" "$ninja" "$cmd_id"
        return 0
    fi
    bash "$deploy_script" --direct --yaml "$tmp_task" "$ninja" "$cmd_id"
}

main() {
    local cmd="${1:-}"
    shift || true
    case "$cmd" in
        init-ledger) cmd_init_ledger "$@" ;;
        next) cmd_next "$@" ;;
        set-global-status) cmd_set_global_status "$@" ;;
        mark-assigned) cmd_mark_assigned "$@" ;;
        record-after) cmd_record_after "$@" ;;
        record-real) cmd_record_real "$@" ;;
        auto-deploy) cmd_auto_deploy "$@" ;;
        *) usage >&2; return 2 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
