#!/usr/bin/env bash
# Reclaim deploy-owned task worktrees without touching active work.
#
# The normal CLEAR/FAIL_CLOSE cleanup remains owned by archive_completed.sh.
# This command supplies the bounded orphan sweep used by terminal lifecycle
# paths and deliberately refuses to remove a dirty worktree.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="${TASK_WORKTREE_RECLAIM_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
WORKTREE_ROOT="${DEPLOY_TASK_WORKTREE_ROOT:-${HOME}/shogun-task-worktrees}"
TASK_DIR="${TASK_WORKTREE_RECLAIM_TASK_DIR:-$REPO/queue/tasks}"
GATES_DIR="${TASK_WORKTREE_RECLAIM_GATES_DIR:-$REPO/queue/gates}"

usage() {
    printf '%s\n' \
        "Usage: $0 --dry-run [--repo PATH] [--worktree-root PATH]" \
        "       $0 --sweep [--repo PATH] [--worktree-root PATH]" \
        "       $0 --terminal --cmd CMD_ID --report REPORT [--reason fail-close]" >&2
}

mode=""
cmd_id=""
report=""
reason=""
while (($#)); do
    case "$1" in
        --dry-run|--sweep|--terminal)
            [ -z "$mode" ] || { echo "BLOCK: only one mode is allowed" >&2; exit 2; }
            mode="${1#--}"
            shift
            ;;
        --repo)
            [ $# -ge 2 ] || { usage; exit 2; }
            REPO="$2"
            shift 2
            ;;
        --worktree-root)
            [ $# -ge 2 ] || { usage; exit 2; }
            WORKTREE_ROOT="$2"
            shift 2
            ;;
        --task-dir)
            [ $# -ge 2 ] || { usage; exit 2; }
            TASK_DIR="$2"
            shift 2
            ;;
        --cmd)
            [ $# -ge 2 ] || { usage; exit 2; }
            cmd_id="$2"
            shift 2
            ;;
        --report)
            [ $# -ge 2 ] || { usage; exit 2; }
            report="$2"
            shift 2
            ;;
        --reason)
            [ $# -ge 2 ] || { usage; exit 2; }
            reason="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "BLOCK: unknown option: $1" >&2
            usage
            exit 2
            ;;
    esac
done

[ -n "$mode" ] || { usage; exit 2; }
REPO="$(realpath -e -- "$REPO")"
WORKTREE_ROOT="$(realpath -m -- "$WORKTREE_ROOT")"
TASK_DIR="$(realpath -m -- "$TASK_DIR")"
GATES_DIR="$(realpath -m -- "$GATES_DIR")"

terminal_cleanup() {
    [ "$mode" = terminal ] || return 0
    [ -n "$cmd_id" ] && [ -n "$report" ] || {
        echo "BLOCK: --terminal requires --cmd and --report" >&2
        return 2
    }
    [ "$reason" = "" ] || [ "$reason" = fail-close ] || {
        echo "BLOCK: unsupported terminal cleanup reason: $reason" >&2
        return 2
    }
    report="$(realpath -e -- "$report")"
    generation="$(sha256sum -- "$report" | awk '{print $1}')"
    [[ "$generation" =~ ^[0-9a-f]{64}$ ]] || {
        echo "BLOCK: report generation unavailable: $report" >&2
        return 1
    }
    # Reuse the existing normal cleanup-only entrypoint. It validates the
    # durable CLEAR or formal FAIL_CLOSE receipt, preserves runtime artifacts,
    # refuses dirty trees, removes only the registered path, and verifies the
    # worktree no longer appears in git's registry.
    ARCHIVE_TASK_WORKTREE_CLEANUP_ONLY=1 \
    ARCHIVE_REQUIRE_CLEAR_RECEIPT=1 \
    SHOGUN_COMPLETION_GENERATION="$generation" \
    bash "$SCRIPT_DIR/archive_completed.sh" "$cmd_id" 3
}

if [ "$mode" = terminal ]; then
    terminal_cleanup
    exit $?
fi

is_under_root() {
    local path="$1"
    [[ "$path" == "$WORKTREE_ROOT"/* ]] && [ "$path" != "$WORKTREE_ROOT" ]
}

declare -A marker_rows=()
declare -A task_rows=()
invalid_marker_count=0
marker_inventory=""
if [ -d "$GATES_DIR" ]; then
    marker_inventory=$(python3 - "$GATES_DIR" <<'PY'
import json
import pathlib
import sys

for marker in sorted(pathlib.Path(sys.argv[1]).glob("*/task_worktree.json")):
    try:
        data = json.loads(marker.read_text(encoding="utf-8"))
        worktree = str(data.get("worktree") or "").strip()
        if not worktree:
            raise ValueError("worktree missing")
        print("\t".join((str(pathlib.Path(worktree).resolve()), str(marker),
                          str(data.get("state") or ""), str(data.get("task_id") or ""),
                          str(data.get("parent_cmd") or ""))))
    except (OSError, TypeError, ValueError, json.JSONDecodeError):
        print("__INVALID__\t" + str(marker))
PY
    )
fi
while IFS=$'\t' read -r marker_path marker marker_state marker_task marker_parent; do
    [ -n "$marker_path" ] || continue
    if [ "$marker_path" = __INVALID__ ]; then
        invalid_marker_count=$((invalid_marker_count + 1))
        continue
    fi
    if [[ -n "${marker_rows[$marker_path]+present}" ]]; then
        marker_rows["$marker_path"]=$'AMBIGUOUS\t'
    else
        marker_rows["$marker_path"]=$(printf '%s\t%s\t%s\t%s' "$marker" "$marker_state" "$marker_task" "$marker_parent")
    fi
done <<< "$marker_inventory"

task_inventory=""
if [ -d "$TASK_DIR" ]; then
    task_inventory=$(python3 - "$TASK_DIR" <<'PY'
import pathlib
import sys
import yaml

for task_path in sorted(pathlib.Path(sys.argv[1]).glob("*.yaml")):
    try:
        data = yaml.safe_load(task_path.read_text(encoding="utf-8")) or {}
    except (OSError, TypeError, ValueError, yaml.YAMLError):
        continue
    task = data.get("task") or {}
    workdir = str(task.get("task_worktree_workdir") or task.get("task_worktree_path") or "").strip()
    if workdir:
        print("\t".join((str(pathlib.Path(workdir).resolve()), str(task_path),
                          str(task.get("status") or ""),
                          str(task.get("task_id") or task.get("_ac_task_id") or ""))))
PY
    )
fi
while IFS=$'\t' read -r task_path task_file task_status task_id; do
    [ -n "$task_path" ] || continue
    if [[ -n "${task_rows[$task_path]+present}" ]]; then
        task_rows["$task_path"]=$'AMBIGUOUS\t'
    else
        task_rows["$task_path"]=$(printf '%s\t%s\t%s' "$task_file" "$task_status" "$task_id")
    fi
done <<< "$task_inventory"

printf 'worktree_root=%s\n' "$WORKTREE_ROOT"
linked_count=0
candidate_count=0
removed_count=0
dirty_count=0
uncertain_count=0
remove_failed=0

while IFS= read -r path; do
    [ -n "$path" ] || continue
    is_under_root "$path" || continue
    linked_count=$((linked_count + 1))

    marker_meta="${marker_rows[$path]:-}"
    marker=""; marker_state=""; marker_task=""; marker_parent=""
    if [ -n "$marker_meta" ]; then
        IFS=$'\t' read -r marker marker_state marker_task marker_parent <<< "$marker_meta"
    elif [ "$invalid_marker_count" -gt 0 ]; then
        marker=INVALID
    fi
    task_meta="${task_rows[$path]:-}"
    task_count=0
    task_file=""; task_status=""; task_id=""
    if [ "$task_meta" = $'AMBIGUOUS\t' ]; then
        task_count=2
    elif [ -n "$task_meta" ]; then
        task_count=1
        IFS=$'\t' read -r task_file task_status task_id <<< "$task_meta"
    fi
    dirty=0
    if [ -d "$path" ] && [ -n "$(git -C "$path" status --porcelain --untracked-files=all 2>/dev/null || true)" ]; then
        dirty=1
    fi

    reason_text=""
    if [ "$marker" = AMBIGUOUS ]; then
        reason_text=ambiguous_marker
    elif [ "$marker" = INVALID ]; then
        reason_text=invalid_marker
    elif [ -z "$marker" ]; then
        reason_text=missing_marker
    elif [ "$marker_state" != active ]; then
        reason_text="marker_state_${marker_state:-missing}"
    elif [ "$task_count" -ne 1 ]; then
        reason_text="task_pointer_count_${task_count}"
    fi

    if [ "$marker" = AMBIGUOUS ] || [ "$marker" = INVALID ]; then
        uncertain_count=$((uncertain_count + 1))
        printf 'retain path=%s reason=%s dirty=%d marker=%s task=%s\n' "$path" "$reason_text" "$dirty" "${marker:-none}" "${task_file:-none}"
        continue
    fi
    if [ -z "$reason_text" ]; then
        printf 'retain path=%s reason=active_task marker=%s task=%s dirty=%d\n' "$path" "${marker:-none}" "${task_file:-none}" "$dirty"
        continue
    fi

    candidate_count=$((candidate_count + 1))
    if [ "$dirty" -eq 1 ]; then
        dirty_count=$((dirty_count + 1))
        printf 'retain path=%s reason=%s dirty=1 marker=%s task=%s\n' "$path" "$reason_text" "${marker:-none}" "${task_file:-none}"
        continue
    fi
    if [ "$mode" = dry-run ]; then
        printf 'candidate path=%s reason=%s dirty=0 marker=%s task=%s\n' "$path" "$reason_text" "${marker:-none}" "${task_file:-none}"
        continue
    fi

    printf 'remove path=%s reason=%s dirty=0 marker=%s task=%s\n' "$path" "$reason_text" "${marker:-none}" "${task_file:-none}"
    if git -C "$REPO" worktree remove --force -- "$path"; then
        removed_count=$((removed_count + 1))
    else
        remove_failed=$((remove_failed + 1))
        printf 'retain path=%s reason=remove_failed\n' "$path"
    fi
done < <(git -C "$REPO" worktree list --porcelain | awk '/^worktree / { sub(/^worktree /, ""); print }')

if [ "$mode" = sweep ]; then
    git -C "$REPO" worktree prune
fi

printf 'summary linked=%d candidates=%d removed=%d dirty_retained=%d uncertain=%d remove_failed=%d\n' \
    "$linked_count" "$candidate_count" "$removed_count" "$dirty_count" "$uncertain_count" "$remove_failed"
[ "$remove_failed" -eq 0 ]
