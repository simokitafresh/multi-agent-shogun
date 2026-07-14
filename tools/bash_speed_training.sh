#!/usr/bin/env bash
# bash_speed_training.sh - ledger and dispatch helper for script speed training.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER_DEFAULT="$SCRIPT_DIR/logs/script_speed_training_ledger.yaml"
LEDGER="${SPEED_TRAINING_LEDGER:-$LEDGER_DEFAULT}"
STATE_DIR="${SHOGUN_STATE_DIR:-/tmp}"
TASK_DIR="${SPEED_TRAINING_TASK_DIR:-$SCRIPT_DIR/queue/tasks}"

usage() {
    cat <<'EOF'
Usage:
  bash tools/bash_speed_training.sh init-ledger [ledger]
  bash tools/bash_speed_training.sh next [ledger]
  bash tools/bash_speed_training.sh set-global-status <running|paused> [ledger]
  bash tools/bash_speed_training.sh status-count <status> [ledger]
  bash tools/bash_speed_training.sh mark-assigned <script_path> <ninja> [ledger]
  bash tools/bash_speed_training.sh record-after <script_path> <status> <after_ms> <test_result> <commit> [ledger]
  bash tools/bash_speed_training.sh record-real <script_path> <status> <before_real_ms> <after_real_ms> <real_measurement_command> <test_result> <commit> [ledger]
  bash tools/bash_speed_training.sh re-enqueue [limit] [ledger] [max_iteration]
  bash tools/bash_speed_training.sh auto-deploy <ninja> [ledger]
  bash tools/bash_speed_training.sh reconcile [ledger]
EOF
}

now_iso() {
    date '+%Y-%m-%dT%H:%M:%S'
}

append_selection_event() {
    local result="$1" reason="$2"
    local log_file="${GATE_FIRE_LOG_FILE:-$SCRIPT_DIR/logs/gate_fire_log.yaml}"
    mkdir -p "$(dirname "$log_file")"
    (
        flock -w 5 8 || exit 1
        printf -- '- ts: "%s"\n  detector: "script_speed_target_selection"\n  source: "gate_fire_log"\n  result: "%s"\n  reason: "%s"\n' \
            "$(now_iso)" "$result" "$reason" >> "$log_file"
    ) 8>"${log_file}.lock"
}

yaml_quote() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

is_non_negative_number() {
    [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

is_strictly_lower_number() {
    awk -v left="$1" -v right="$2" 'BEGIN { exit !(left < right) }'
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

measure_bash_n_inventory() {
    local result_dir="$1"
    shift
    local max_jobs="${SPEED_TRAINING_SYNTAX_JOBS:-16}"
    local active=0 index=0 job_index path
    [[ "$max_jobs" =~ ^[1-9][0-9]*$ ]] || { echo "SPEED_TRAINING_SYNTAX_JOBS must be a positive integer" >&2; return 2; }

    for path in "$@"; do
        job_index=$index
        (
            local measured
            measured=$(measure_bash_n_ms "$path")
            printf '%s\n' "$measured" > "$result_dir/$job_index"
        ) &
        active=$((active + 1))
        index=$((index + 1))
        if [ "$active" -ge "$max_jobs" ]; then
            wait -n
            active=$((active - 1))
        fi
    done
    wait
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
    local tmp count path ms syntax_status generated_at result_dir index
    local -a script_paths
    tmp=$(mktemp "${ledger}.XXXXXX")
    result_dir=$(mktemp -d "${ledger}.syntax.XXXXXX")
    trap 'rm -f "$result_dir"/* "$tmp"; rmdir "$result_dir" 2>/dev/null || true' RETURN
    generated_at=$(now_iso)
    mapfile -d '' -t script_paths < <(find "$SCRIPT_DIR/scripts" -type f -name '*.sh' -printf '%P\0' | sort -z)
    for index in "${!script_paths[@]}"; do
        script_paths[$index]="scripts/${script_paths[$index]}"
    done
    count=${#script_paths[@]}
    measure_bash_n_inventory "$result_dir" "${script_paths[@]}"
    {
        printf 'global_status: running\n'
        printf 'generated_at: %s\n' "$(yaml_quote "$generated_at")"
        printf 'measurement_command: %s\n' "$(yaml_quote 'timeout 5 bash -n <script_path> (syntax baseline only; not runtime speed)')"
        printf 'real_measurement_policy: %s\n' "$(yaml_quote 'Ninja must choose a safe runtime command per script: time bash script.sh <args>, --help, dry-run mode, or sandboxed equivalent. Record before_real_ms/after_real_ms with the same command before and after.')"
        printf 'script_count: %s\n' "$count"
        printf 'entries:\n'
        index=0
        for path in "${script_paths[@]}"; do
            read -r ms syntax_status < "$result_dir/$index"
            printf '  - script_path: %s\n' "$(yaml_quote "$path")"
            printf '    status: pending\n'
            printf '    before_ms: %s\n' "$ms"
            printf '    after_ms: ""\n'
            printf '    before_real_ms: ""\n'
            printf '    after_real_ms: ""\n'
            printf '    iteration: 0\n'
            printf '    real_measurement_command: ""\n'
            printf '    test_result: %s\n' "$(yaml_quote "baseline_bash_n_exit_${syntax_status}")"
            printf '    commit: ""\n'
            printf '    assigned_to: ""\n'
            printf '    updated_at: ""\n'
            index=$((index + 1))
        done
    } > "$tmp"
    mv "$tmp" "$ledger"
    rm -f "$result_dir"/*
    rmdir "$result_dir"
    trap - RETURN
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
    is_non_negative_number "$before_real_ms" || { echo "before_real_ms must be numeric" >&2; return 2; }
    is_non_negative_number "$after_real_ms" || { echo "after_real_ms must be numeric" >&2; return 2; }
    if [ "$status" = "completed" ] && ! is_strictly_lower_number "$after_real_ms" "$before_real_ms"; then
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
    python3 - "$ledger" <<'PY'
import sys, yaml

data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
hot = ("pre-bash", "guard14", "prompt_state_inject", "session_start_inject")
plateau = ("review_two_phase", "memory_db", "ninja_monitor")
def rank(e):
    path = str(e.get("script_path", ""))
    axis = 2 if any(x in path for x in hot) else 1 if any(x in path for x in plateau) else 0
    measured = e.get("before_real_ms") or e.get("after_real_ms") or e.get("before_ms") or 0
    try: measured = float(measured)
    except (TypeError, ValueError): measured = 0
    return axis, measured, path
candidates = [e for e in data.get("entries", []) if e.get("status") == "pending"]
if not candidates:
    raise SystemExit(1)
e = max(candidates, key=rank)
print(e.get("script_path", ""))
PY
}

ledger_status_count() {
    local status_name="$1"
    local ledger="${2:-$LEDGER}"
    [ -f "$ledger" ] || { printf '0\n'; return 0; }
    awk -v wanted="$status_name" '
        /^[[:space:]]+status:/ {
            status = $0
            sub(/^.*status:[[:space:]]*"?/, "", status)
            sub(/"?[[:space:]]*$/, "", status)
            if (status == wanted) count++
        }
        END { print count + 0 }
    ' "$ledger"
}

re_enqueue_completed_unlocked() {
    local ledger="$1"
    local limit="$2"
    local now="$3"
    local max_iteration="$4"
    local selected tmp
    selected=$(mktemp "${ledger}.reenqueue.XXXXXX")
    tmp=$(mktemp "${ledger}.XXXXXX")

    awk -v max_iteration="$max_iteration" '
        /^[[:space:]]*-[[:space:]]+script_path:/ {
            if (path != "" && status == "completed" && after_real_ms ~ /^[0-9]+([.][0-9]+)?$/ && iteration < max_iteration) {
                rows[++n] = after_real_ms "\t" path
            }
            path = $0
            sub(/^.*script_path:[[:space:]]*"?/, "", path)
            sub(/"?[[:space:]]*$/, "", path)
            status = after_real_ms = ""
            iteration = 0
            next
        }
        /^[[:space:]]+status:/ {
            status = $0
            sub(/^.*status:[[:space:]]*"?/, "", status)
            sub(/"?[[:space:]]*$/, "", status)
            next
        }
        /^[[:space:]]+iteration:/ {
            iteration = $0
            sub(/^.*iteration:[[:space:]]*"?/, "", iteration)
            sub(/"?[[:space:]]*$/, "", iteration)
            if (iteration !~ /^[0-9]+$/) iteration = 0
            next
        }
        /^[[:space:]]+after_real_ms:/ {
            after_real_ms = $0
            sub(/^.*after_real_ms:[[:space:]]*"?/, "", after_real_ms)
            sub(/"?[[:space:]]*$/, "", after_real_ms)
            next
        }
        END {
            if (path != "" && status == "completed" && after_real_ms ~ /^[0-9]+([.][0-9]+)?$/ && iteration < max_iteration) {
                rows[++n] = after_real_ms "\t" path
            }
            for (i = 1; i <= n; i++) print rows[i]
        }
    ' "$ledger" | sort -rn -k1,1 | head -n "$limit" | cut -f2- > "$selected"

    awk -v selected_file="$selected" -v now="$now" '
        BEGIN {
            while ((getline line < selected_file) > 0) {
                selected[line] = 1
            }
            close(selected_file)
        }
        /^[[:space:]]*-[[:space:]]+script_path:/ {
            if (in_target) flush_block()
            path = $0
            sub(/^.*script_path:[[:space:]]*"?/, "", path)
            sub(/"?[[:space:]]*$/, "", path)
            in_target = (path in selected)
            if (in_target) {
                block = $0 ORS
                status_seen = before_seen = after_seen = iteration_seen = assigned_seen = updated_seen = 0
                after_value = ""
                next
            }
            print
            next
        }
        in_target {
            line = $0
            if ($0 ~ /^[[:space:]]+status:/) {
                line = "    status: pending"
                status_seen = 1
            } else if ($0 ~ /^[[:space:]]+before_real_ms:/) {
                line = "    before_real_ms: __BEFORE_REAL_MS__"
                before_seen = 1
            } else if ($0 ~ /^[[:space:]]+after_real_ms:/) {
                after_value = $0
                sub(/^.*after_real_ms:[[:space:]]*"?/, "", after_value)
                sub(/"?[[:space:]]*$/, "", after_value)
                line = "    after_real_ms: \"\""
                after_seen = 1
            } else if ($0 ~ /^[[:space:]]+iteration:/) {
                iteration_value = $0
                sub(/^.*iteration:[[:space:]]*"?/, "", iteration_value)
                sub(/"?[[:space:]]*$/, "", iteration_value)
                if (iteration_value !~ /^[0-9]+$/) iteration_value = 0
                line = "    iteration: " (iteration_value + 1)
                iteration_seen = 1
            } else if ($0 ~ /^[[:space:]]+assigned_to:/) {
                line = "    assigned_to: \"\""
                assigned_seen = 1
            } else if ($0 ~ /^[[:space:]]+updated_at:/) {
                line = "    updated_at: \"" now "\""
                updated_seen = 1
            }
            block = block line ORS
            next
        }
        { print }
        END {
            if (in_target) flush_block()
        }
        function flush_block(    before_line) {
            if (after_value == "" || after_value !~ /^[0-9]+([.][0-9]+)?$/) {
                printf "%s", block
                in_target = 0
                return
            }
            if (!status_seen) block = block "    status: pending" ORS
            before_line = "    before_real_ms: " after_value ORS
            if (before_seen) {
                gsub(/    before_real_ms: __BEFORE_REAL_MS__\n/, before_line, block)
            } else {
                block = block before_line
            }
            if (!after_seen) block = block "    after_real_ms: \"\"" ORS
            if (!iteration_seen) block = block "    iteration: 1" ORS
            if (!assigned_seen) block = block "    assigned_to: \"\"" ORS
            if (!updated_seen) block = block "    updated_at: \"" now "\"" ORS
            printf "%s", block
            count++
            in_target = 0
        }
    ' "$ledger" > "$tmp"
    mv "$tmp" "$ledger"
    local count
    count=$(wc -l < "$selected" | tr -d ' ')
    rm -f "$selected"
    printf '%s\n' "$count"
}

cmd_re_enqueue() {
    local limit="${1:-20}"
    local ledger="${2:-$LEDGER}"
    local max_iteration="${3:-${SPEED_TRAINING_MAX_ITERATION:-3}}"
    [[ "$limit" =~ ^[0-9]+$ ]] || { echo "limit must be numeric" >&2; return 2; }
    [ "$limit" -gt 0 ] 2>/dev/null || { echo "limit must be > 0" >&2; return 2; }
    [[ "$max_iteration" =~ ^[0-9]+$ ]] || { echo "max_iteration must be numeric" >&2; return 2; }
    [ "$max_iteration" -gt 0 ] 2>/dev/null || { echo "max_iteration must be > 0" >&2; return 2; }
    [ -f "$ledger" ] || return 1
    with_ledger_lock "$ledger" re_enqueue_completed_unlocked "$ledger" "$limit" "$(now_iso)" "$max_iteration"
}

cmd_status_count() {
    local status_name="${1:-}"
    local ledger="${2:-$LEDGER}"
    [ -n "$status_name" ] || { usage >&2; return 2; }
    ledger_status_count "$status_name" "$ledger"
}

active_task_targets() {
    local task_dir="${1:-$TASK_DIR}"
    local task_file
    [ -d "$task_dir" ] || return 0
    for task_file in "$task_dir"/*.yaml; do
        [ -f "$task_file" ] || continue
        awk '
            /^[[:space:]]+status:/ {
                status = $0
                sub(/^.*status:[[:space:]]*"?/, "", status)
                sub(/"?[[:space:]]*$/, "", status)
            }
            /^[[:space:]]+target_path:/ {
                target = $0
                sub(/^.*target_path:[[:space:]]*"?/, "", target)
                sub(/"?[[:space:]]*$/, "", target)
            }
            END {
                if (target != "" && status ~ /^(assigned|acknowledged|in_progress)$/) print target
            }
        ' "$task_file"
    done
}

reserve_next_unlocked() {
    local ledger="$1"
    local ninja="$2"
    local now="$3"
    local task_dir="${4:-$TASK_DIR}"
    local reserved_file="$5"
    local tmp
    tmp=$(mktemp "${ledger}.XXXXXX")
    active_task_targets "$task_dir" | awk '
        NF { active[$0] = 1 }
        END {
            for (target in active) print target
        }
    ' > "${tmp}.active"
    local wanted
    wanted=$(python3 - "$ledger" "${tmp}.active" <<'PY'
import sys, yaml
ledger, active_file = sys.argv[1:]
data = yaml.safe_load(open(ledger, encoding="utf-8")) or {}
active = {line.strip() for line in open(active_file, encoding="utf-8") if line.strip()}
hot = ("pre-bash", "guard14", "prompt_state_inject", "session_start_inject")
plateau = ("review_two_phase", "memory_db", "ninja_monitor")
def rank(e):
    path = str(e.get("script_path", ""))
    axis = 2 if any(x in path for x in hot) else 1 if any(x in path for x in plateau) else 0
    measured = e.get("before_real_ms") or e.get("after_real_ms") or e.get("before_ms") or 0
    try: measured = float(measured)
    except (TypeError, ValueError): measured = 0
    return axis, measured, path
candidates = [e for e in data.get("entries", [])
              if e.get("status") == "pending" and str(e.get("script_path", "")) not in active]
if candidates: print(max(candidates, key=rank).get("script_path", ""))
PY
)
    awk -v ninja="$ninja" -v now="$now" -v wanted="$wanted" -v reserved_file="$reserved_file" '
        /^[[:space:]]*-[[:space:]]+script_path:/ {
            if (in_target && !reserved) emit_pending()
            path = $0
            sub(/^.*script_path:[[:space:]]*"?/, "", path)
            sub(/"?[[:space:]]*$/, "", path)
            in_target = (reserved == 0 && path == wanted)
            if (in_target) {
                block = $0 ORS
                status_seen = assigned_seen = updated_seen = 0
                pending_target = 0
                next
            }
            print
            next
        }
        in_target {
            line = $0
            if ($0 ~ /^[[:space:]]+status:[[:space:]]*pending[[:space:]]*$/) {
                line = "    status: assigned"
                pending_target = 1
                status_seen = 1
            } else if ($0 ~ /^[[:space:]]+status:/) {
                status_seen = 1
                in_target = 0
                printf "%s", block
                print
                next
            } else if ($0 ~ /^[[:space:]]+assigned_to:/) {
                line = "    assigned_to: \"" ninja "\""
                assigned_seen = 1
            } else if ($0 ~ /^[[:space:]]+updated_at:/) {
                line = "    updated_at: \"" now "\""
                updated_seen = 1
            }
            block = block line ORS
            next
        }
        { print }
        END {
            if (in_target && !reserved) emit_pending()
        }
        function emit_pending() {
            if (pending_target) {
                if (!assigned_seen) block = block "    assigned_to: \"" ninja "\"" ORS
                if (!updated_seen) block = block "    updated_at: \"" now "\"" ORS
                printf "%s", block
                print path > reserved_file
                reserved = 1
            } else {
                printf "%s", block
            }
        }
    ' "$ledger" > "$tmp"
    rm -f "${tmp}.active"
    mv "$tmp" "$ledger"
}

cmd_reserve_next() {
    local ninja="${1:-}"
    local ledger="${2:-$LEDGER}"
    local reserved_file
    [ -n "$ninja" ] || { usage >&2; return 2; }
    [ -f "$ledger" ] || return 1
    if [ "$(ledger_global_status "$ledger")" != "running" ]; then
        return 2
    fi
    mkdir -p "${SHOGUN_STATE_DIR:-/tmp}"
    reserved_file=$(mktemp "${SHOGUN_STATE_DIR:-/tmp}/speed_training_reserved.XXXXXX")
    with_ledger_lock "$ledger" reserve_next_unlocked "$ledger" "$ninja" "$(now_iso)" "$TASK_DIR" "$reserved_file"
    cat "$reserved_file"
    rm -f "$reserved_file"
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
            in_target = (index($0, "script_path: \"" script_path "\"") > 0 || \
                         index($0, "script_path: " script_path) > 0)
            print
            next
        }
        in_target && $0 ~ "^[[:space:]]+" field ":" {
            match($0, /^[[:space:]]+/)
            indent = substr($0, 1, RLENGTH)
            if (value ~ /^[0-9]+([.][0-9]+)?$/ && field ~ /_ms$/) print indent field ": " value
            else if (field == "status" && value ~ /^[A-Za-z0-9_.-]+$/) print indent field ": " value
            else print indent field ": " q(value)
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
    [ "$status" != "no_improvement" ] || status="saturated"
    with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "status" "$status"
    with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "after_ms" "$after_ms"
    with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "test_result" "$test_result"
    with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "commit" "$commit"
    with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "updated_at" "$(now_iso)"
    append_selection_event "$([ "$status" = completed ] && printf PASS || printf WARN)" \
        "target=${script_path} status=${status}"
}

cmd_reconcile() {
    local ledger="${1:-$LEDGER}"
    [ -f "$ledger" ] || return 1
    local reconciled=0 skipped=0
    # Build script->commit map in one git log call (newest-first, first match wins)
    local commit_map
    commit_map=$(mktemp)
    git -C "$SCRIPT_DIR" log --oneline --name-only --grep='training(' -- 'scripts/*.sh' 2>/dev/null | awk '
        /^[0-9a-f]{7,}[[:space:]]/ { current = $1; next }
        /^scripts\// { if (!(seen[$0]++)) print $0, current }
    ' > "$commit_map"
    # Get pending entries
    local pending_paths
    pending_paths=$(awk '
        /script_path:/ {
            path = $0
            sub(/^.*script_path:[[:space:]]*"?/, "", path)
            sub(/"?[[:space:]]*$/, "", path)
        }
        /^[[:space:]]+status:[[:space:]]*pending[[:space:]]*$/ { print path }
    ' "$ledger")
    while IFS= read -r script_path; do
        [ -z "$script_path" ] && continue
        local commit
        commit=$(awk -v p="$script_path" '$1==p{print $2; exit}' "$commit_map" || true)
        if [ -n "$commit" ]; then
            with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "status" "completed"
            with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "commit" "$commit"
            with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "test_result" "reconciled"
            with_ledger_lock "$ledger" update_entry_field_unlocked "$ledger" "$script_path" "updated_at" "$(now_iso)"
            reconciled=$((reconciled + 1))
        else
            skipped=$((skipped + 1))
        fi
    done <<< "$pending_paths"
    rm -f "$commit_map"
    echo "reconcile: ${reconciled} completed, ${skipped} still pending (no training commit found)"
}

write_training_task() {
    local tmp_task="$1"
    local cmd_id="$2"
    local script_path="$3"
    local evidence axis
    evidence=$(python3 - "$LEDGER" "$script_path" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
entry = next((e for e in data.get("entries", []) if e.get("script_path") == sys.argv[2]), {})
print(entry.get("before_real_ms") or entry.get("after_real_ms") or entry.get("before_ms") or 0)
PY
)
    case "$script_path" in
        *pre-bash*|*guard14*|*prompt_state_inject*|*session_start_inject*) axis="high-frequency hook/gate hot path" ;;
        *review_two_phase*|*memory_db*|*ninja_monitor*) axis="test-side plateau production target" ;;
        *) axis="measured runtime fallback" ;;
    esac
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
  selection_evidence:
    measured_ms: ${evidence}
    priority_axis: "${axis}"
    source: "logs/script_speed_training_ledger.yaml"
  acceptance_criteria:
    - id: AC1
      checks:
        - check: "before_ms bash -n baseline is read from script_speed_training_ledger as syntax-only reference"
        - check: "before_real_ms is measured with a safe runtime command chosen for this script (time bash script.sh <args>, --help, dry-run, or sandboxed equivalent)"
    - id: AC2
      checks:
        - check: "implementation improves runtime without reducing behavior or safety; async timeout shortening and other feature thinning (LS081) are forbidden"
        - check: "safety patterns (|| true, 2>/dev/null, cat 2>/dev/null, trap, timeout, set +e) are NOT deleted. git diff must show zero removed safety lines"
        - check: "if new functions are added, all test files that source/export -f the parent script have updated mock/export lists"
        - check: "all related tests pass with FAIL=0 and SKIP=0; expectations, coverage, and target count are unchanged"
    - id: AC3
      checks:
        - check: "dominant cost is measured before editing; after_real_ms is measured with the same command as before_real_ms (exact command equality required)"
        - check: "after_real_ms is strictly lower than before_real_ms"
        - check: "bash tools/bash_speed_training.sh record-after ${script_path} completed <after_real_ms> \"<test_result>\" <commit> is called; no improvement uses status saturated and is not redeployed"
        - check: "deployment/result event is appended to gate_fire_log and measurable by detector_fp_rate"
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
    script_path=$(cmd_reserve_next "$ninja" "$ledger" || true)
    [ -n "$script_path" ] || { echo "no_pending"; return 1; }
    safe_name="${script_path#scripts/}"
    safe_name="${safe_name%.sh}"
    safe_name="${safe_name//[^A-Za-z0-9]/_}"
    cmd_id="cmd_training_speed_${safe_name}_$(date '+%Y%m%d%H%M%S')"
    mkdir -p "$STATE_DIR"
    tmp_task=$(mktemp "${STATE_DIR}/speed_training_${ninja}.XXXXXX.yaml")
    write_training_task "$tmp_task" "$cmd_id" "$script_path"
    append_selection_event PASS "target=${script_path} event=deploy ninja=${ninja}"
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
        reserve-next) cmd_reserve_next "$@" ;;
        re-enqueue) cmd_re_enqueue "$@" ;;
        status-count) cmd_status_count "$@" ;;
        set-global-status) cmd_set_global_status "$@" ;;
        mark-assigned) cmd_mark_assigned "$@" ;;
        record-after) cmd_record_after "$@" ;;
        record-real) cmd_record_real "$@" ;;
        auto-deploy) cmd_auto_deploy "$@" ;;
        reconcile) cmd_reconcile "$@" ;;
        *) usage >&2; return 2 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
