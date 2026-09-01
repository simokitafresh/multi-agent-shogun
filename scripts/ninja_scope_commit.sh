#!/usr/bin/env bash
# ninja_scope_commit.sh — shared index上で指定pathだけを安全にcommitする
set -euo pipefail

# GA-222: このscript自身が置かれているdirectory(=multi-agent-shogunの
# scripts/)を動的に求める。ninja_scope_commit.shはDM-Signal等、別repoを
# cwdにして呼ばれることがあるため($repo_rootはそちらのrepo rootになる)、
# 後段でsourceするSSOT(scripts/lib/scope_path.sh)は「操作対象repo」ではなく
# 「このscript自身の設置場所」基準で解決する。cd実行より前に計算すること
# (BASH_SOURCEが相対pathの場合、後のcdでPWD基準の解決が狂うため)。
_ninja_scope_commit_self="${BASH_SOURCE[0]:-$0}"
[[ "$_ninja_scope_commit_self" = /* ]] || _ninja_scope_commit_self="$PWD/$_ninja_scope_commit_self"
_ninja_scope_commit_script_dir="$(cd "$(dirname "$_ninja_scope_commit_self")" && pwd)"
# Reserve the shared commit lane before this helper creates its private index.
# The wrapper owns the EXIT/INT/TERM release trap, so every early return in the
# large scoped-commit state machine releases the reservation without having to
# duplicate cleanup calls at each existing exit point.
# The helper already keeps hooks/tests outside its repository transaction lock
# and serializes only the final ref publication in
# acquire_transaction_lock_and_rebase_index().  Wrapping the entire helper in
# commit_queue serialized six agents' pre-commit suites and turned a seconds-
# long atomic boundary into a multi-minute global lane.  Keep the legacy outer
# queue as an explicit diagnostic opt-in only; the internal lock is the normal
# safe and high-throughput path.
if [[ "${NINJA_SCOPE_COMMIT_USE_OUTER_QUEUE:-0}" == "1" \
    && -z "${COMMIT_QUEUE_ACTIVE:-}" \
    && -f "$_ninja_scope_commit_script_dir/commit_queue.sh" ]]; then
    _ninja_scope_commit_repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "$_ninja_scope_commit_repo" ]]; then
        _ninja_scope_commit_agent_base="${COMMIT_QUEUE_AGENT_ID:-${AGENT_ID:-}}"
        if [[ -z "$_ninja_scope_commit_agent_base" && -n "${TMUX_PANE:-}" ]] && command -v tmux >/dev/null 2>&1; then
            _ninja_scope_commit_agent_base="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
        fi
        _ninja_scope_commit_agent_base="${_ninja_scope_commit_agent_base:-${USER:-ninja}}"
        # An explicit queue identity is a logical retry key and therefore
        # participates in duplicate-reservation rejection.  Without one,
        # concurrent helper invocations from the same agent are independent
        # commit attempts; use the run id when supplied, otherwise the child
        # PID, so unrelated scopes do not collide in the reservation ledger.
        if [[ -n "${COMMIT_QUEUE_AGENT_ID:-}" ]]; then
            _ninja_scope_commit_agent="$_ninja_scope_commit_agent_base"
        else
            _ninja_scope_commit_run="${NINJA_SCOPE_COMMIT_RUN_ID:-pid-${BASHPID}}"
            _ninja_scope_commit_agent="${_ninja_scope_commit_agent_base}:${_ninja_scope_commit_run}"
        fi
        exec env COMMIT_QUEUE_ACTIVE=1 COMMIT_QUEUE_AGENT_ID="$_ninja_scope_commit_agent" \
            bash "$_ninja_scope_commit_script_dir/commit_queue.sh" run \
            --agent "$_ninja_scope_commit_agent" --repo "$_ninja_scope_commit_repo" -- \
            bash "$_ninja_scope_commit_self" "$@"
    fi
fi
if [[ -z "${NINJA_SCOPE_COMMIT_SNAPSHOT_ACTIVE:-}" ]]; then
    _ninja_scope_commit_original_dir="$(cd "$(dirname "$_ninja_scope_commit_self")" && pwd)"
    _ninja_scope_commit_snapshot="$(mktemp "${TMPDIR:-/tmp}/ninja-scope-commit.XXXXXX")"
    cp -- "$_ninja_scope_commit_self" "$_ninja_scope_commit_snapshot"
    chmod 700 "$_ninja_scope_commit_snapshot"
    exec env \
        NINJA_SCOPE_COMMIT_SNAPSHOT_ACTIVE=1 \
        NINJA_SCOPE_COMMIT_ORIGINAL_DIR="$_ninja_scope_commit_original_dir" \
        NINJA_SCOPE_COMMIT_SNAPSHOT_PATH="$_ninja_scope_commit_snapshot" \
        bash "$_ninja_scope_commit_snapshot" "$@"
fi
NINJA_SCOPE_COMMIT_SCRIPT_DIR="${NINJA_SCOPE_COMMIT_ORIGINAL_DIR:?snapshot original directory missing}"
# The child shell already has the immutable file open.  Unlink its pathname so
# every exit path, including signals and fail-closed guards, leaves no temp
# artifact while the current process continues reading the same inode.
rm -f -- "${NINJA_SCOPE_COMMIT_SNAPSHOT_PATH:?snapshot path missing}"
if [[ -n "${NINJA_SCOPE_COMMIT_TEST_SNAPSHOT_READY_FILE:-}" ]]; then
    printf 'ready\n' > "$NINJA_SCOPE_COMMIT_TEST_SNAPSHOT_READY_FILE"
fi
if [[ -n "${NINJA_SCOPE_COMMIT_TEST_AFTER_SNAPSHOT_DELAY:-}" ]]; then
    sleep "$NINJA_SCOPE_COMMIT_TEST_AFTER_SNAPSHOT_DELAY"
fi
unset _ninja_scope_commit_self

# Round8 lane #0': complete entrypoint wall-clock telemetry.  This is placed
# after the snapshot re-exec so one invocation emits one row, not a parent and
# child pair.
NINJA_SCOPE_COMMIT_TOTAL_T0_US="${EPOCHREALTIME/./}"
NINJA_SCOPE_COMMIT_TOTAL_T0_US="${NINJA_SCOPE_COMMIT_TOTAL_T0_US:0:16}"
DEFENSE_OVERHEAD_REPO_ROOT="${DEFENSE_OVERHEAD_REPO_ROOT:-$NINJA_SCOPE_COMMIT_SCRIPT_DIR}"
# shellcheck source=scripts/lib/defense_overhead_writer.sh
if [[ -f "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/lib/defense_overhead_writer.sh" ]]; then
    source "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/lib/defense_overhead_writer.sh"
else
    # Isolated contract fixtures intentionally copy only scope-path helpers;
    # telemetry must not turn a valid scoped commit into a dependency failure.
    defense_overhead_write_async() { return 0; }
fi
NINJA_SCOPE_COMMIT_TOTAL_RECORDED=0
ninja_scope_commit_record_total() {
    local rc="${1:-0}" now_us wall_ms verdict
    [ "${NINJA_SCOPE_COMMIT_TOTAL_RECORDED:-0}" -eq 0 ] || return 0
    NINJA_SCOPE_COMMIT_TOTAL_RECORDED=1
    now_us="${EPOCHREALTIME/./}"
    now_us="${now_us:0:16}"
    wall_ms=$(( (now_us - NINJA_SCOPE_COMMIT_TOTAL_T0_US + 999) / 1000 ))
    verdict=PASS
    [ "$rc" -eq 0 ] || verdict=FAIL
    defense_overhead_write_async ninja_scope_commit ninja_scope_commit_total "$wall_ms" "$verdict" \
        "ninja-scope-commit-${BASHPID}-${NINJA_SCOPE_COMMIT_TOTAL_T0_US}" || true
}
ninja_scope_commit_total_on_exit() { local rc=$?; ninja_scope_commit_record_total "$rc"; return "$rc"; }
trap ninja_scope_commit_total_on_exit EXIT

usage() {
    echo "Usage: bash scripts/ninja_scope_commit.sh [--task-worktree-exec <task.yaml> -- <command> ...] [-m <message>] [--reflux-mode synced|non-target --reflux-evidence <text>] [--repair-index | --patch <file> --base-blob <hash>] -- <path> [path ...]" >&2
}

# Level5 edit wrapper: source-task commands start in the deploy-created linked
# worktree. The task's target_path/planned_paths remain repo-relative; only
# this execution root is absolute and task-owned.
run_task_worktree_command() {
    local task_file="$1"
    shift
    local worktree
    worktree="$(python3 - "$task_file" <<'PY'
import sys
import yaml
task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("task", {})
print(str(task.get("task_worktree_workdir") or task.get("task_worktree_path") or "").strip())
PY
)"
    [ -n "$worktree" ] || { echo "BLOCK: task worktree edit wrapper requires task_worktree_workdir" >&2; return 2; }
    [ -d "$worktree" ] || { echo "BLOCK: task worktree edit wrapper path missing: $worktree" >&2; return 2; }
    git -C "$worktree" rev-parse --show-toplevel >/dev/null 2>&1 \
        || { echo "BLOCK: task worktree edit wrapper path is not a Git worktree: $worktree" >&2; return 2; }
    [ "$#" -gt 0 ] || { echo "BLOCK: task worktree edit wrapper command is empty" >&2; return 2; }
    (cd "$worktree" && export TASK_WORKTREE_ACTIVE=1 TASK_WORKTREE_ROOT="$worktree" && "$@")
}

if [[ "${1:-}" == "--task-worktree-exec" ]]; then
    (($# >= 4)) || { usage; exit 2; }
    task_worktree_exec_task="$2"
    shift 2
    [[ "$1" == "--" ]] || { echo "BLOCK: --task-worktree-exec requires -- before command" >&2; exit 2; }
    shift
    run_task_worktree_command "$task_worktree_exec_task" "$@"
    exit $?
fi

message=""
patch_file=""
base_blob=""
repair_index=false
reflux_mode=""
reflux_evidence=""
while (($#)); do
    case "$1" in
        -m|--message)
            (($# >= 2)) || { usage; exit 2; }
            message="$2"
            shift 2
            ;;
        --patch)
            (($# >= 2)) || { usage; exit 2; }
            patch_file="$2"
            shift 2
            ;;
        --base-blob)
            (($# >= 2)) || { usage; exit 2; }
            base_blob="$2"
            shift 2
            ;;
        --repair-index)
            repair_index=true
            shift
            ;;
        --reflux-mode)
            (($# >= 2)) || { usage; exit 2; }
            reflux_mode="$2"
            shift 2
            ;;
        --reflux-evidence)
            (($# >= 2)) || { usage; exit 2; }
            reflux_evidence="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -h|--help)
            # 2026-09-01: 家老が --help を 3 回連続で BLOCK(rc=2)され使用法確認に往復した。
            # help は usage を出して rc=0(BLOCK ではない)。
            usage
            exit 0
            ;;
        *)
            echo "BLOCK: unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

if [[ "$repair_index" == false ]]; then
    [[ -n "$message" ]] || { echo "BLOCK: commit message is required" >&2; exit 2; }
fi

# The report gate requires every ninja-task commit to identify its task_id or
# parent_cmd in the subject.  Inject that identity from the reviewed task
# contract so callers do not need to remember a second, manually maintained
# subject token.  An unset task file means an ordinary/manual or karo commit;
# preserve that legacy path exactly.
if [[ -n "${NINJA_SCOPE_TASK_FILE:-}" && "$repair_index" == false ]]; then
    message="$(python3 - "$NINJA_SCOPE_TASK_FILE" "$message" <<'PY'
import re
import sys

import yaml

task_path, subject = sys.argv[1:]
try:
    with open(task_path, encoding="utf-8") as handle:
        raw = yaml.safe_load(handle) or {}
except (OSError, yaml.YAMLError) as exc:
    print(f"BLOCK: cannot read NINJA_SCOPE_TASK_FILE: {exc}", file=sys.stderr)
    raise SystemExit(2)

task = raw.get("task", raw) if isinstance(raw, dict) else {}
identity = ""
for key in ("task_id", "parent_cmd"):
    value = str(task.get(key) or "").strip()
    if value:
        identity = value
        break
if not identity:
    # Some legacy helper fixtures pass a task file only for transient-test
    # cleanup/receipt validation.  Without a task identity this is not a
    # ninja commit contract, so preserve the historical subject unchanged.
    print(subject)
    raise SystemExit(0)

# Match the same identifier boundary used by gate_report_format_main.py so a
# shorter task id cannot be mistaken for a prefix of another id.
if re.search(rf"\b{re.escape(identity)}\b", subject) is None:
    subject = f"{identity}: {subject}"
print(subject)
PY
)" || exit 2
fi
if [[ -n "$reflux_mode" || -n "$reflux_evidence" ]]; then
    [[ "$reflux_mode" =~ ^(synced|non-target)$ && -n "$reflux_evidence" ]] \
        || { echo "BLOCK: --reflux-mode and --reflux-evidence must be supplied together" >&2; exit 2; }
fi
(($# > 0)) || { echo "BLOCK: commit scope is empty" >&2; exit 2; }
if [[ "$repair_index" == true && ( -n "$patch_file" || -n "$base_blob" ) ]]; then
    echo "BLOCK: --repair-index cannot be combined with patch mode" >&2
    exit 2
fi
if [[ -n "$patch_file" || -n "$base_blob" ]]; then
    [[ -n "$patch_file" && -n "$base_blob" ]] \
        || { echo "BLOCK: --patch and --base-blob must be used together" >&2; exit 2; }
    (($# == 1)) \
        || { echo "BLOCK: patch mode requires exactly one scope path" >&2; exit 2; }
    [[ "$base_blob" =~ ^[0-9a-f]{40}$ ]] \
        || { echo "BLOCK: --base-blob must be a full 40-hex object id" >&2; exit 2; }
fi

# Git itself reads command-scope config on the first repository probe.  Reject
# malformed ambient state before that probe so the helper owns a stable,
# actionable fail-closed diagnostic instead of leaking a version-specific Git
# error from `rev-parse`.
[[ "${GIT_CONFIG_COUNT:-0}" =~ ^[0-9]+$ ]] \
    || { echo "BLOCK: GIT_CONFIG_COUNT must be a non-negative integer" >&2; exit 2; }

# A source task may be published from the deploy-created remote-tip linked
# worktree. Resolve it from the task contract before discovering repo_root so
# the private index and commit transaction belong to that worktree, never the
# shared main checkout.
if [[ -n "${NINJA_SCOPE_TASK_FILE:-}" && -f "$NINJA_SCOPE_TASK_FILE" ]]; then
    _task_worktree_path="$(python3 - "$NINJA_SCOPE_TASK_FILE" <<'PY'
import sys, yaml
task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("task", {})
print(str(task.get("task_worktree_path") or "").strip())
PY
)"
    if [[ -n "$_task_worktree_path" ]]; then
        [[ -d "$_task_worktree_path" ]] || { echo "BLOCK: task worktree missing: $_task_worktree_path" >&2; exit 2; }
        git -C "$_task_worktree_path" rev-parse --show-toplevel >/dev/null 2>&1 \
            || { echo "BLOCK: task worktree is not a Git worktree: $_task_worktree_path" >&2; exit 2; }
        cd "$_task_worktree_path"
        export NINJA_SCOPE_TASK_WORKTREE_ACTIVE=1
    fi
fi

assert_task_shared_source_clean() {
    local task_file="$1" task_worktree="$2" shared_git_dir shared_repo dirty path
    [ -n "$task_worktree" ] || return 0
    shared_git_dir="$(git -C "$task_worktree" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
    [ -n "$shared_git_dir" ] || { echo "BLOCK: cannot resolve task worktree common Git dir" >&2; return 2; }
    shared_repo="$(dirname "$shared_git_dir")"
    [ "$shared_repo" != "$task_worktree" ] || return 0
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        dirty="$(git -C "$shared_repo" status --porcelain --untracked-files=all -- "$path" 2>/dev/null || true)"
        if [ -n "$dirty" ]; then
            echo "BLOCK: shared source path was edited outside task worktree: $path" >&2
            return 2
        fi
    done < <(python3 - "$task_file" <<'PY'
import sys
import yaml
task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}).get("task", {})
values = task.get("task_worktree_source_paths") or []
if isinstance(values, str):
    try:
        values = yaml.safe_load(values) or []
    except yaml.YAMLError:
        values = [values]
if not isinstance(values, list):
    values = [values]
runtime = ("queue/", "logs/", "context/", "projects/", "archive/", ".cache/")
for value in dict.fromkeys(str(item).strip().lstrip("./") for item in values):
    if value and value != "dashboard.md" and not value.startswith(runtime):
        print(value)
PY
)
}

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "BLOCK: not inside a git repository" >&2; exit 2; }
cd "$repo_root"
if [[ -n "${_task_worktree_path:-}" ]]; then
    assert_task_shared_source_clean "$NINJA_SCOPE_TASK_FILE" "$repo_root" || exit $?
fi

# A private GIT_INDEX_FILE isolates each commit tree, but `git commit` still
# shares COMMIT_EDITMSG, hooks, and the branch ref.  Concurrent callers used to
# overwrite one another's message and one loser could fail the ref update;
# callers running with `set -e` then lost their parent shell before its next
# command.  Serialize the complete transaction in the common git directory so
# linked worktrees and the main worktree use the same lock.
git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" \
    || { echo "BLOCK: cannot resolve git common directory" >&2; exit 2; }
[[ "$git_common_dir" = /* ]] || git_common_dir="$repo_root/$git_common_dir"
# WSL2/DrvFs上のflockは不安定なため、repository identityはcommon dirで
# 共有しつつ実lockはlock_path SSOTでext4側へ写像する。
# shellcheck source=scripts/lib/lock_path.sh
source "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/lib/lock_path.sh"
commit_lock_path="$(lock_path "$git_common_dir/ninja-scope-commit")"
exec {commit_lock_fd}>"$commit_lock_path" \
    || { echo "BLOCK: cannot open ninja scope commit lock" >&2; exit 2; }
lock_requested_epoch_ms=0
lock_acquired_epoch_ms=0
lock_wait_ms=0
transaction_lock_held=false

# The private index isolates tree contents only.  Repository operation state
# (MERGE_HEAD, rebase state and CHERRY_PICK_HEAD) lives in the common git dir
# and changes the parent/author semantics of `git commit`.  Never inherit that
# ambient state into a scoped commit.  Capture HEAD under the common-dir lock;
# every commit path must still observe this exact generation immediately before
# publishing and must produce exactly one parent pointing at it.
transaction_head="$(git rev-parse HEAD)"

acquire_transaction_lock_and_rebase_index() {
    local operation_state operation_path current_head path entry mode blob
    local -a staged_paths=() staged_entries=()

    # Hooks and heavy-job admission are deliberately outside this critical
    # section.  Snapshot the caller's private scoped entries, then converge the
    # private index onto the newest HEAD after acquiring the repository lock.
    # This preserves owned blobs while incorporating unrelated commits that
    # completed during pre-commit.
    # `git diff --cached` without an explicit base is unsafe here: HEAD may
    # have advanced while the hook ran, making unrelated parent changes look
    # like reverse staged changes.  `paths` is the already validated effective
    # scope captured before the hook and is therefore the ownership SSOT.
    staged_paths=("${paths[@]}")
    for path in "${staged_paths[@]}"; do
        entry="$(git ls-files -s -- "$path" | awk '$3 == 0 {print $1 " " $2; exit}')"
        staged_entries+=("$entry")
    done

    lock_requested_epoch_ms="$(date +%s%3N)"
    flock -w 120 "$commit_lock_fd" \
        || { echo "BLOCK: cannot acquire ninja scope commit lock" >&2; return 2; }
    transaction_lock_held=true
    lock_acquired_epoch_ms="$(date +%s%3N)"
    lock_wait_ms=$((lock_acquired_epoch_ms - lock_requested_epoch_ms))

    current_head="$(git rev-parse HEAD)"
    if [[ -n "${verification_head:-}" && "$verification_head" != "$current_head" ]]; then
        # cmd_karo_hotfix_speed_ninja_scope_commit_r2_20260809: lock取得までの
        # 間に無関係commitがHEADを進めただけなら再テストを強制しない。判定は
        # ninja_scope_commit_receipt_stale_reason(下方で定義、呼出し時点では既に
        # 利用可能)で対象path/検証済みtest/source fingerprintの3点一致を確認する。
        lock_stale_reason="$(ninja_scope_commit_receipt_stale_reason "$verification_head" "$current_head")" \
            || { echo "BLOCK: HEAD advanced after test verification; rerun verification against $current_head ($lock_stale_reason)" >&2; return 2; }
    fi
    transaction_head="$current_head"
    for operation_state in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
        operation_path="$(git rev-parse --git-path "$operation_state")"
        [[ ! -e "$operation_path" ]] \
            || { echo "BLOCK: repository operation state is active: $operation_state" >&2; return 2; }
    done

    git read-tree "$transaction_head" \
        || { echo "BLOCK: failed to rebuild private index from current HEAD" >&2; return 2; }
    for i in "${!staged_paths[@]}"; do
        path="${staged_paths[$i]}"
        entry="${staged_entries[$i]}"
        if [[ "$path" == "queue/insights.yaml" ]]; then
            local head_insights candidate_insights merged_insights merged_blob
            head_insights="$(mktemp "${TMPDIR:-/tmp}/scope-insights-head.XXXXXX")"
            candidate_insights="$(mktemp "${TMPDIR:-/tmp}/scope-insights-candidate.XXXXXX")"
            merged_insights="$(mktemp "${TMPDIR:-/tmp}/scope-insights-merged.XXXXXX")"
            trap 'rm -f -- "$head_insights" "$candidate_insights" "$merged_insights"' RETURN
            git show "$transaction_head:$path" >"$head_insights" \
                || { echo "BLOCK: HEAD insights blob unavailable during rebase" >&2; return 2; }
            if [[ -n "$entry" ]]; then
                read -r mode blob <<<"$entry"
                git cat-file blob "$blob" >"$candidate_insights" \
                    || { echo "BLOCK: staged insights blob unavailable during rebase" >&2; return 2; }
            else
                printf 'insights:\n' >"$candidate_insights"
            fi
            bash "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/restore_insights_from_corrupt.sh" \
                --id-union "$head_insights" "$candidate_insights" "$merged_insights" \
                || { echo "BLOCK: insights ID union failed during rebase" >&2; return 2; }
            merged_blob="$(git hash-object -w "$merged_insights")" \
                || { echo "BLOCK: failed to store rebased insights union" >&2; return 2; }
            git update-index --add --cacheinfo "100644,$merged_blob,$path" \
                || { echo "BLOCK: failed to restore rebased insights union" >&2; return 2; }
            cp -- "$merged_insights" "$repo_root/$path" \
                || { echo "BLOCK: failed to project rebased insights union" >&2; return 2; }
            rm -f -- "$head_insights" "$candidate_insights" "$merged_insights"
            trap - RETURN
            continue
        fi
        if [[ -n "$entry" ]]; then
            read -r mode blob <<<"$entry"
            git update-index --add --cacheinfo "$mode,$blob,$path" \
                || { echo "BLOCK: failed to restore scoped index entry: $path" >&2; return 2; }
        else
            git update-index --force-remove -- "$path" \
                || { echo "BLOCK: failed to restore scoped deletion: $path" >&2; return 2; }
        fi
    done
}

release_transaction_lock() {
    if [[ "$transaction_lock_held" == true ]]; then
        flock -u "$commit_lock_fd" \
            || { echo "BLOCK: cannot release ninja scope commit lock" >&2; return 2; }
        transaction_lock_held=false
    fi
}

assert_head_generation() {
    local current_head
    current_head="$(git rev-parse HEAD)"
    [[ "$current_head" == "$transaction_head" ]] \
        || { echo "BLOCK: HEAD generation changed during scoped transaction (expected $transaction_head, got $current_head)" >&2; return 2; }
}

assert_single_parent_commit() {
    local commit_hash="$1" parents
    parents="$(git show -s --format=%P "$commit_hash")"
    [[ "$parents" == "$transaction_head" ]] \
        || { echo "BLOCK: scoped commit parent invariant violated (expected sole parent $transaction_head, got ${parents:-<none>})" >&2; return 1; }
}

# A scoped commit holds the repository-wide transaction lock until its ref,
# shared-index entry and postconditions have converged.  Git may otherwise run
# `maintenance run --auto` as a child of `git commit`; on WSL/DrvFS that child
# can block in p9_client_rpc and keep every scoped committer behind this lock.
# Append (rather than replace) one command-scoped config entry so caller-supplied
# GIT_CONFIG_COUNT contracts remain intact.  Invalid ambient config is a hard
# BLOCK: silently dropping it would change hook/commit behaviour.
run_scoped_precommit() {
    local config_count="${GIT_CONFIG_COUNT:-0}" config_key config_value
    [[ "$config_count" =~ ^[0-9]+$ ]] \
        || { echo "BLOCK: GIT_CONFIG_COUNT must be a non-negative integer" >&2; return 2; }
    config_key="GIT_CONFIG_KEY_${config_count}=maintenance.auto"
    config_value="GIT_CONFIG_VALUE_${config_count}=false"
    # Publish nonterminal progress before potentially slow external-repo
    # hooks.  Observers must not mistake a bounded wait expiry for rc0.
    printf 'event=progress run_id=%s phase=pre_commit complete=false ledger=%s\n' \
        "$terminal_run_id" "$terminal_ledger" >&2
    helper_repo_root="$(cd "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/.." && pwd)"
    if [[ "$repo_root" != "$helper_repo_root" && -f "$repo_root/lefthook.yml" && -x "$repo_root/.git/hooks/pre-commit" && \
          -f "$repo_root/scripts/run_precommit_checks.sh" ]] && \
       grep -q 'run: bash scripts/run_precommit_checks.sh' "$repo_root/lefthook.yml"; then
        # The configured hook command is the contract; invoke it directly.
        # Lefthook first runs an unbounded repository-wide `git status`, which
        # can stall for minutes on DrvFS despite our private scoped index.
        if [[ -n "$patch_file" && "$scope_path" == frontend/*.ts* ]]; then
            # Patch mode's private index intentionally differs from the full
            # worktree.  The canonical hook's `biome --write; git add <file>`
            # would widen that index back to every foreign hunk.  Run the same
            # formatter check read-only, then the mixed-change contract against
            # the exact private index.
            (cd "$repo_root/frontend" && npx biome check -- "${scope_path#frontend/}") >&2 \
                && python3 "$repo_root/scripts/check_mixed_format_commit.py" --repo "$repo_root" >&2 \
                || { echo "BLOCK: patch pre-commit checks rejected scoped commit" >&2; return 1; }
        else
            env -u NINJA_SCOPE_COMMIT_SNAPSHOT_ACTIVE \
                -u NINJA_SCOPE_COMMIT_ORIGINAL_DIR \
                -u NINJA_SCOPE_COMMIT_SNAPSHOT_PATH \
                "GIT_CONFIG_COUNT=$((config_count + 1))" "$config_key" "$config_value" \
                bash "$repo_root/scripts/run_precommit_checks.sh" >&2 \
                || { echo "BLOCK: pre-commit hook command rejected scoped commit" >&2; return 1; }
        fi
    else
        env -u NINJA_SCOPE_COMMIT_SNAPSHOT_ACTIVE \
            -u NINJA_SCOPE_COMMIT_ORIGINAL_DIR \
            -u NINJA_SCOPE_COMMIT_SNAPSHOT_PATH \
            "GIT_CONFIG_COUNT=$((config_count + 1))" "$config_key" "$config_value" \
            git hook run --ignore-missing pre-commit >&2 \
            || { echo "BLOCK: pre-commit hook rejected scoped commit" >&2; return 1; }
    fi
}

create_and_publish_scoped_commit() {
    local config_count="${GIT_CONFIG_COUNT:-0}" config_key config_value
    [[ "$config_count" =~ ^[0-9]+$ ]] \
        || { echo "BLOCK: GIT_CONFIG_COUNT must be a non-negative integer" >&2; return 2; }
    config_key="GIT_CONFIG_KEY_${config_count}=maintenance.auto"
    config_value="GIT_CONFIG_VALUE_${config_count}=false"
    local tree_hash commit_hash command_stderr command_rc
    # The slow safety hook has already passed without the repository lock.
    # Construct the object from the rebased private index and publish HEAD by
    # old-value CAS while the caller holds the short transaction lock.
    # Last irreversible-boundary check: the private index may have been
    # rebuilt after a concurrent HEAD advance or changed by a hook.  Compare
    # the exact candidate tree with its captured parent before creating an
    # object or publishing HEAD.  Post-publication checks are too late: the
    # 980b4110 incident already made eight paths visible when only four were
    # owned by its caller.
    local candidate_path
    # Contract-test seam: inject a real foreign index entry at the final
    # boundary so the detector is exercised against tree data, not a mock.
    if [[ -n "${NINJA_SCOPE_COMMIT_TEST_INJECT_FOREIGN_PATH:-}" ]]; then
        git add -- "$NINJA_SCOPE_COMMIT_TEST_INJECT_FOREIGN_PATH"
    fi
    while IFS= read -r candidate_path; do
        [[ -n "$candidate_path" ]] || continue
        scope_path_is_in_scope "$candidate_path" "${requested_paths[@]}" \
            || { echo "BLOCK: out-of-scope path entered private commit tree before publish: $candidate_path" >&2; return 2; }
    done < <(git diff --cached --name-only "$transaction_head")
    tree_hash="$(git write-tree)" \
        || { echo "BLOCK: failed to write scoped commit tree" >&2; return 1; }
    command_stderr="$(mktemp "${TMPDIR:-/tmp}/ninja-scope-git-exit.XXXXXX")"
    if commit_hash="$(printf '%s\n' "$message" | git commit-tree "$tree_hash" -p "$transaction_head" 2>"$command_stderr")"; then
        command_rc=0
    else
        command_rc=$?
    fi
    record_git_exit commit_tree "$command_rc" "$command_stderr" "$commit_hash"
    [[ ! -s "$command_stderr" ]] || cat "$command_stderr" >&2
    rm -f -- "$command_stderr"
    ((command_rc == 0)) \
        || { echo "BLOCK: failed to create scoped commit object" >&2; return 1; }
    [[ "$commit_hash" =~ ^[0-9a-f]{40}$ ]] \
        || { echo "BLOCK: commit-tree did not return a 40hex object" >&2; return 1; }
    command_stderr="$(mktemp "${TMPDIR:-/tmp}/ninja-scope-git-exit.XXXXXX")"
    if git update-ref -m "$message" HEAD "$commit_hash" "$transaction_head" 2>"$command_stderr"; then
        command_rc=0
    else
        command_rc=$?
    fi
    record_git_exit update_ref "$command_rc" "$command_stderr" "$commit_hash"
    [[ ! -s "$command_stderr" ]] || cat "$command_stderr" >&2
    rm -f -- "$command_stderr"
    ((command_rc == 0)) \
        || { echo "BLOCK: failed to publish scoped commit ref" >&2; return 1; }
    # Preserve the observable post-commit contract for repository automation.
    # It runs only after the CAS publication, matching porcelain ordering.
    local post_commit_hook
    post_commit_hook="$(git rev-parse --git-path hooks/post-commit)"
    if [[ -x "$post_commit_hook" ]]; then
        env "GIT_CONFIG_COUNT=$((config_count + 1))" "$config_key" "$config_value" \
            git hook run post-commit >&2 \
            || { echo "BLOCK: post-commit hook failed after ref publication" >&2; return 1; }
    fi
    printf '%s\n' "$commit_hash"
}

# Phase telemetry starts before private-index construction.  The repository
# lock wait is reported separately and now begins only after pre-commit.
declare -A phase_wall_ms=() phase_rc=()
phase_order=(read_tree add scope_sync guard git_commit advance_shared_index post_check)
current_phase="read_tree"
phase_started_epoch_ms="$(date +%s%3N)"
telemetry_started_epoch_ms="$phase_started_epoch_ms"
terminal_event_emitted=false
terminal_status_clean_hint=false
published_commit_hash=""
telemetry_overhead_us=0
telemetry_clock_calls=0
singleflight_receipt=""
singleflight_key=""
singleflight_role="owner"
terminal_run_id="${NINJA_SCOPE_COMMIT_RUN_ID:-${message:-repair-index}}"
terminal_ledger_dir="$(lock_path "$git_common_dir/ninja-scope-terminal-ledger")"
mkdir -p -- "$terminal_ledger_dir"
terminal_run_key="$(printf '%s' "$repo_root:$terminal_run_id" | sha256sum | awk '{print $1}')"
terminal_ledger="$terminal_ledger_dir/$terminal_run_key.ledger"
git_exit_receipt="$terminal_ledger_dir/$terminal_run_key.git-exit"

record_git_exit() {
    local command_name="$1" command_rc="$2" stderr_file="$3" commit_hash="${4:-none}"
    local stderr_b64 tmp
    stderr_b64="$(base64 -w0 < "$stderr_file")"
    [[ "$commit_hash" =~ ^[0-9a-f]{40}$ ]] || commit_hash=none
    tmp="${git_exit_receipt}.tmp.$$"
    if [[ -f "$git_exit_receipt" ]]; then
        cp -- "$git_exit_receipt" "$tmp"
    else
        printf 'version=1\n' > "$tmp"
    fi
    printf '%s_rc=%s\n%s_stderr_b64=%s\n%s_commit_hash=%s\n' \
        "$command_name" "$command_rc" "$command_name" "$stderr_b64" \
        "$command_name" "$commit_hash" >> "$tmp"
    mv -f -- "$tmp" "$git_exit_receipt"
}

write_terminal_ledger() {
    local rc="$1" commit_hash="${2:-}" complete="$3" phase="$4"
    local tmp head_generation status_clean="${terminal_status_clean_hint:-false}"
    head_generation="$(git rev-parse HEAD 2>/dev/null || printf unavailable)"
    [[ "$commit_hash" =~ ^[0-9a-f]{40}$ ]] || commit_hash=none
    tmp="${terminal_ledger}.tmp.$$"
    printf 'version=1\nrun_id=%s\ncommit_hash=%s\nrc=%s\nphase=%s\nstatus_clean=%s\nhead_generation=%s\ncomplete=%s\n' \
        "$terminal_run_id" "$commit_hash" "$rc" "$phase" "$status_clean" "$head_generation" "$complete" > "$tmp"
    if [[ -f "$git_exit_receipt" ]]; then
        sed '1{/^version=/d;}' "$git_exit_receipt" >> "$tmp"
    fi
    mv -f -- "$tmp" "$terminal_ledger"
}

epoch_ms() {
    local output_var="$1" before="$EPOCHREALTIME" after before_us after_us sec frac value
    sec="${before%.*}"
    frac="${before#*.}000000"
    frac="${frac:0:6}"
    value=$((10#$sec * 1000 + 10#$frac / 1000))
    printf -v "$output_var" '%s' "$value"
    after="$EPOCHREALTIME"
    before_us=$((10#${before%.*} * 1000000 + 10#$frac))
    frac="${after#*.}000000"
    frac="${frac:0:6}"
    after_us=$((10#${after%.*} * 1000000 + 10#$frac))
    telemetry_overhead_us=$((telemetry_overhead_us + after_us - before_us))
    telemetry_clock_calls=$((telemetry_clock_calls + 1))
}

finish_phase() {
    local rc="${1:-0}" finished
    epoch_ms finished
    phase_wall_ms["$current_phase"]=$((finished - phase_started_epoch_ms))
    phase_rc["$current_phase"]="$rc"
}

begin_phase() {
    current_phase="$1"
    epoch_ms phase_started_epoch_ms
}

phase_fields() {
    local phase
    for phase in "${phase_order[@]}"; do
        [[ -v "phase_wall_ms[$phase]" ]] || continue
        printf ' phase_%s_ms=%s phase_%s_rc=%s' \
            "$phase" "${phase_wall_ms[$phase]}" "$phase" "${phase_rc[$phase]}"
    done
}

publish_terminal_failure() {
    local rc="${1:-1}" finished phase sum=0 total unattributed
    [[ "$terminal_event_emitted" == false && "$rc" -ne 0 ]] || return 0
    if [[ ! -v "phase_wall_ms[$current_phase]" ]]; then
        finish_phase "$rc"
    fi
    epoch_ms finished
    for phase in "${phase_order[@]}"; do sum=$((sum + ${phase_wall_ms[$phase]:-0})); done
    total=$((finished - telemetry_started_epoch_ms))
    unattributed=$((total - sum))
    printf 'event=failed lock_wait_ms=%s acquired_at=%s finished_at=%s last_phase=%s rc=%s commit_hash=%s phase_total_ms=%s phase_unattributed_ms=%s telemetry_overhead_ms=%s telemetry_clock_calls=%s' \
        "$lock_wait_ms" "$lock_acquired_epoch_ms" "$finished" "$current_phase" "$rc" "${published_commit_hash:-none}" "$sum" "$unattributed" "$(((telemetry_overhead_us + 999) / 1000))" "$telemetry_clock_calls" >&2
    phase_fields >&2
    printf '\n' >&2
    write_terminal_ledger "$rc" "$published_commit_hash" false "$current_phase"
    printf 'event=terminal_ledger run_id=%s rc=%s commit_hash=%s complete=false ledger=%s\n' \
        "$terminal_run_id" "$rc" "${published_commit_hash:-none}" "$terminal_ledger" >&2
    if [[ -n "$singleflight_receipt" && -n "$published_commit_hash" ]]; then
        receipt_tmp="${singleflight_receipt}.tmp.$$"
        printf 'version=2\nkey=%s\nrc=%s\ncommit_hash=%s\nfinished_at=%s\nlast_phase=%s\n' \
            "$singleflight_key" "$rc" "$published_commit_hash" "$finished" "$current_phase" > "$receipt_tmp"
        mv -f -- "$receipt_tmp" "$singleflight_receipt"
        printf 'event=terminal_receipt role=%s key=%s rc=%s commit_hash=%s receipt=%s\n' \
            "$singleflight_role" "$singleflight_key" "$rc" "$published_commit_hash" "$singleflight_receipt" >&2
    fi
    terminal_event_emitted=true
}
ninja_scope_commit_failure_on_exit() {
    local rc=$?
    publish_terminal_failure "$rc"
    ninja_scope_commit_record_total "$rc"
    return "$rc"
}
trap ninja_scope_commit_failure_on_exit EXIT

# A successful return is one terminal contract: the commit object exists, the
# published branch/HEAD ref resolves to that object, all post-checks finished,
# and only then is completion made observable.  Metadata goes to stderr so
# stdout remains the stable, single-line commit-hash API used by callers.
publish_terminal_success() {
    local terminal_hash="$1" finished_epoch_ms sum=0 total unattributed receipt_tmp completed_event
    [[ "$terminal_hash" =~ ^[0-9a-f]{40}$ ]] \
        || { echo "BLOCK: invalid terminal commit hash" >&2; return 1; }
    git cat-file -e "${terminal_hash}^{commit}" 2>/dev/null \
        || { echo "BLOCK: terminal commit object disappeared: $terminal_hash" >&2; return 1; }
    [[ "$(git rev-parse HEAD)" == "$terminal_hash" ]] \
        || { echo "BLOCK: terminal ref does not publish commit: $terminal_hash" >&2; return 1; }
    finish_phase 0
    local phase
    for phase in "${phase_order[@]}"; do
        if [[ ! -v "phase_wall_ms[$phase]" ]]; then
            phase_wall_ms["$phase"]=0
            phase_rc["$phase"]=0
        fi
    done
    epoch_ms finished_epoch_ms
    for phase in "${phase_order[@]}"; do sum=$((sum + ${phase_wall_ms[$phase]:-0})); done
    total=$((finished_epoch_ms - telemetry_started_epoch_ms))
    unattributed=$((total - sum))
    printf -v completed_event 'event=completed lock_wait_ms=%s acquired_at=%s finished_at=%s commit_hash=%s phase_total_ms=%s phase_unattributed_ms=%s telemetry_overhead_ms=%s telemetry_clock_calls=%s' \
        "$lock_wait_ms" "$lock_acquired_epoch_ms" "$finished_epoch_ms" "$terminal_hash" "$sum" "$unattributed" "$(((telemetry_overhead_us + 999) / 1000))" "$telemetry_clock_calls"
    completed_event+="$(phase_fields)"
    # Persist the complete terminal contract before publishing any success
    # bytes to the caller.  A PTY/session disconnect after HEAD publication can
    # therefore reconnect with the same run id and recover hash + telemetry
    # instead of falling through to a misleading no-change BLOCK.
    if [[ -n "$singleflight_receipt" ]]; then
        receipt_tmp="${singleflight_receipt}.tmp.$$"
        printf 'version=2\nkey=%s\nrc=0\ncommit_hash=%s\nfinished_at=%s\ncompleted_event=%s\n' \
            "$singleflight_key" "$terminal_hash" "$finished_epoch_ms" "$completed_event" > "$receipt_tmp"
        mv -f -- "$receipt_tmp" "$singleflight_receipt"
    fi
    # Content-only receipt (paths + blob, no run id/message) so a differently
    # identified peer that raced the same owned bytes can recognize this
    # commit as already covering its intended change instead of BLOCKing on a
    # since-converged worktree.  See the scope_content_key computation above.
    if [[ -n "${scope_content_receipt:-}" ]]; then
        receipt_tmp="${scope_content_receipt}.tmp.$$"
        printf 'version=1\nkey=%s\ncommit_hash=%s\nfinished_at=%s\n' \
            "$scope_content_key" "$terminal_hash" "$finished_epoch_ms" > "$receipt_tmp"
        mv -f -- "$receipt_tmp" "$scope_content_receipt"
    fi
    write_terminal_ledger 0 "$terminal_hash" true complete
    printf '%s\n' "$completed_event" >&2
    printf 'event=terminal_ledger run_id=%s rc=0 commit_hash=%s complete=true ledger=%s\n' \
        "$terminal_run_id" "$terminal_hash" "$terminal_ledger" >&2
    if [[ -n "$singleflight_receipt" ]]; then
        printf 'event=terminal_receipt role=%s key=%s rc=0 commit_hash=%s receipt=%s\n' \
            "$singleflight_role" "$singleflight_key" "$terminal_hash" "$singleflight_receipt" >&2
    fi
    terminal_event_emitted=true
    ninja_scope_commit_record_total 0
    printf '%s\n' "$terminal_hash"
}

# The lock serializes this helper, but a direct `git add` does not participate
# in it.  Keep the real shared-index path and update entries with a compare
# against the snapshot taken before the commit.  This is the common boundary
# for patch and normal mode: a foreign stage is preserved, never reset merely
# because HEAD advanced.
shared_index_file="$(git rev-parse --git-path index)"
[[ "$shared_index_file" = /* ]] || shared_index_file="$repo_root/$shared_index_file"
repo_core_filemode="$(git config --bool core.filemode 2>/dev/null || printf false)"

# A killed git process may leave index.lock behind.  Under the repository-wide
# helper lock it cannot belong to another scoped commit.  Remove it only when
# the OS confirms that no process has the file open; otherwise fail closed.
shared_index_lock="${shared_index_file}.lock"
if [[ -e "$shared_index_lock" ]]; then
    if command -v fuser >/dev/null 2>&1 && fuser "$shared_index_lock" >/dev/null 2>&1; then
        echo "BLOCK: active shared index lock: $shared_index_lock" >&2
        exit 2
    fi
    rm -f -- "$shared_index_lock"
fi

# Compare exact owned paths without porcelain status or diff's whole-index
# refresh. HEAD and the shared index are read once; only named worktree blobs
# are hashed. Foreign paths are never enumerated.
collect_owned_paths_not_at_head() {
    local record meta path mode blob work_mode work_blob
    local -a exact_paths=("$@")
    local -A head_entries=() index_entries=()
    ((${#exact_paths[@]} > 0)) || return 0
    if [[ "${terminal_head_snapshot_ready:-false}" == true ]]; then
        for path in "${exact_paths[@]}"; do
            [[ -z "${terminal_head_entries[$path]-}" ]] || head_entries["$path"]="${terminal_head_entries[$path]}"
        done
    else
        while IFS= read -r -d '' record; do
            meta="${record%%$'\t'*}"
            path="${record#*$'\t'}"
            read -r mode _ blob <<<"$meta"
            head_entries["$path"]="$mode $blob"
        done < <(git ls-tree -rz HEAD -- "${exact_paths[@]}")
    fi
    if [[ "${terminal_index_snapshot_ready:-false}" == true &&
          "$(stat -c '%y:%s' "$shared_index_file" 2>/dev/null || printf missing)" == "$terminal_index_signature" ]]; then
        for path in "${exact_paths[@]}"; do
            [[ -z "${terminal_index_entries[$path]-}" ]] || index_entries["$path"]="${terminal_index_entries[$path]}"
        done
    else
        while IFS= read -r -d '' record; do
            meta="${record%%$'\t'*}"
            path="${record#*$'\t'}"
            index_entries["$path"]="${meta% 0}"
        done < <(GIT_INDEX_FILE="$shared_index_file" git ls-files -s -z -- "${exact_paths[@]}")
    fi
    for path in "${exact_paths[@]}"; do
        if [[ "${index_entries[$path]-}" != "${head_entries[$path]-}" ]]; then
            printf '%s\n' "$path"
            continue
        fi
        if [[ -z "${head_entries[$path]-}" ]]; then
            [[ ! -e "$path" && ! -L "$path" ]] || printf '%s\n' "$path"
            continue
        fi
        if [[ ! -e "$path" && ! -L "$path" ]]; then
            printf '%s\n' "$path"
            continue
        fi
        read -r mode blob <<<"${head_entries[$path]}"
        if [[ -L "$path" ]]; then
            work_mode=120000
        elif [[ "$repo_core_filemode" == true && -x "$path" ]]; then
            work_mode=100755
        elif [[ "$repo_core_filemode" == true ]]; then
            work_mode=100644
        else
            # DrvFS commonly exposes every file as executable while Git has
            # core.filemode=false.  In that mode Git deliberately ignores the
            # filesystem execute bit, so preserve the HEAD mode for comparison.
            work_mode="$mode"
        fi
        work_blob="$(git hash-object -- "$path" 2>/dev/null || printf unavailable)"
        [[ "$work_mode $work_blob" == "$mode $blob" ]] || printf '%s\n' "$path"
    done
}

advance_shared_index_entry() {
    local path="$1" expected_entry="$2" current_entry new_blob new_mode attempt
    local attempts="${NINJA_SCOPE_COMMIT_INDEX_RETRY_ATTEMPTS:-50}"
    local delay="${NINJA_SCOPE_COMMIT_INDEX_RETRY_DELAY:-0.02}"
    [[ "$attempts" =~ ^[1-9][0-9]*$ ]] \
        || { echo "BLOCK: index retry attempts must be a positive integer" >&2; return 2; }
    for ((attempt=1; attempt<=attempts; attempt++)); do
        current_entry="$(GIT_INDEX_FILE="$shared_index_file" git ls-files -s -- "$path" | awk '$3 == 0 {print $1 " " $2; exit}')"
        if [[ "$current_entry" != "$expected_entry" ]]; then
            echo "WARN: shared index changed concurrently; preserving newer staged entry: $path" >&2
            return 0
        fi
        if git cat-file -e "HEAD:$path" 2>/dev/null; then
            new_blob="$(git rev-parse "HEAD:$path")"
            new_mode="$(git ls-tree HEAD -- "$path" | awk 'NR==1 {print $1}')"
            [[ "$current_entry" == "$new_mode $new_blob" ]] && return 0
            if GIT_INDEX_FILE="$shared_index_file" git update-index --add --cacheinfo "$new_mode,$new_blob,$path" 2>/dev/null; then
                return 0
            fi
        else
            [[ -z "$current_entry" ]] && return 0
            if GIT_INDEX_FILE="$shared_index_file" git update-index --force-remove -- "$path" 2>/dev/null; then
                return 0
            fi
        fi
        ((attempt < attempts)) && sleep "$delay"
    done
    echo "BLOCK: shared index did not converge after $attempts attempts: $path" >&2
    return 1
}

declare -A terminal_head_entries=()
terminal_head_snapshot_ready=false
declare -A terminal_index_entries=()
terminal_index_snapshot_ready=false
terminal_index_signature=""

# Normal-mode commits can contain hundreds of exact files.  Advancing them via
# advance_shared_index_entry() rereads the shared index and HEAD tree once per
# file; on DrvFS that turns a bounded index reconciliation into O(paths) Git
# process and filesystem round trips.  Reconcile the same exact committed paths
# as one index transaction instead.  The ownership/CAS contract is unchanged:
# each path is updated only while its current shared entry still equals the
# pre-commit snapshot, and every changed entry (including a same-path foreign
# stage) is preserved.  Unspecified index entries are never part of
# --index-info, so unrelated staged work remains byte-for-byte untouched.
advance_shared_index_entries() {
    local attempts="${NINJA_SCOPE_COMMIT_INDEX_RETRY_ATTEMPTS:-50}"
    local delay="${NINJA_SCOPE_COMMIT_INDEX_RETRY_DELAY:-0.02}"
    local attempt index_record index_meta path mode blob
    local expected_entry current_entry target_entry
    local -a exact_paths=("$@") update_paths=() update_modes=() update_blobs=()
    local -A head_entries=() current_entries=() warned_paths=()

    [[ "$attempts" =~ ^[1-9][0-9]*$ ]] \
        || { echo "BLOCK: index retry attempts must be a positive integer" >&2; return 2; }
    ((${#exact_paths[@]} > 0)) || return 0

    # HEAD cannot advance while the caller holds commit_lock_fd.  Resolve all
    # target mode/blob pairs once, NUL-delimited so exact Git paths are retained.
    while IFS= read -r -d '' index_record; do
        index_meta="${index_record%%$'\t'*}"
        path="${index_record#*$'\t'}"
        read -r mode _ blob <<<"$index_meta"
        head_entries["$path"]="$mode $blob"
    done < <(git ls-tree -rz HEAD -- "${exact_paths[@]}")
    terminal_head_entries=()
    for path in "${exact_paths[@]}"; do
        [[ -z "${head_entries[$path]-}" ]] || terminal_head_entries["$path"]="${head_entries[$path]}"
    done
    terminal_head_snapshot_ready=true

    for ((attempt=1; attempt<=attempts; attempt++)); do
        current_entries=()
        while IFS= read -r -d '' index_record; do
            index_meta="${index_record%%$'\t'*}"
            path="${index_record#*$'\t'}"
            current_entries["$path"]="${index_meta% 0}"
        done < <(GIT_INDEX_FILE="$shared_index_file" git ls-files -s -z -- "${exact_paths[@]}")

        update_paths=()
        update_modes=()
        update_blobs=()
        terminal_index_entries=()
        for path in "${exact_paths[@]}"; do
            [[ -z "${current_entries[$path]-}" ]] || terminal_index_entries["$path"]="${current_entries[$path]}"
        done
        for path in "${exact_paths[@]}"; do
            expected_entry="${shared_index_before[$path]-}"
            current_entry="${current_entries[$path]-}"
            if [[ "$current_entry" != "$expected_entry" ]]; then
                if [[ -z "${warned_paths[$path]-}" ]]; then
                    echo "WARN: shared index changed concurrently; preserving newer staged entry: $path" >&2
                    warned_paths["$path"]=1
                fi
                continue
            fi

            target_entry="${head_entries[$path]-}"
            [[ "$current_entry" != "$target_entry" ]] || continue
            update_paths+=("$path")
            if [[ -n "$target_entry" ]]; then
                read -r mode blob <<<"$target_entry"
                update_modes+=("$mode")
                update_blobs+=("$blob")
            else
                update_modes+=(0)
                update_blobs+=(0000000000000000000000000000000000000000)
            fi
        done

        if ((${#update_paths[@]} == 0)); then
            terminal_index_signature="$(stat -c '%y:%s' "$shared_index_file" 2>/dev/null || printf missing)"
            terminal_index_snapshot_ready=true
            return 0
        fi
        if {
            for i in "${!update_paths[@]}"; do
                printf '%s %s\t%s\0' "${update_modes[$i]}" "${update_blobs[$i]}" "${update_paths[$i]}"
            done
        } | GIT_INDEX_FILE="$shared_index_file" git update-index -z --index-info 2>/dev/null; then
            for i in "${!update_paths[@]}"; do
                path="${update_paths[$i]}"
                target_entry="${head_entries[$path]-}"
                if [[ -n "$target_entry" ]]; then
                    terminal_index_entries["$path"]="$target_entry"
                else
                    unset 'terminal_index_entries[$path]'
                fi
            done
            terminal_index_signature="$(stat -c '%y:%s' "$shared_index_file" 2>/dev/null || printf missing)"
            terminal_index_snapshot_ready=true
            return 0
        fi
        ((attempt < attempts)) && sleep "$delay"
    done
    echo "BLOCK: shared index did not converge after $attempts attempts: ${exact_paths[*]}" >&2
    return 1
}

# GA-222: scope path正規化はscripts/lib/scope_path.sh(SSOT)に集約する。
# ここ(commit scopeのバリデーション)とsync_git_hooks.sh(is_in_scope判定)で
# 別々に正規化ロジックを持つと、片方だけ直して片方が取り残される形で
# 同じ穴が別のpath表現で繰り返し再発したため、両scriptとも同一helperのみを使う。
# shellcheck source=scripts/lib/scope_path.sh
source "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/lib/scope_path.sh"

paths=()
for path in "$@"; do
    [[ -n "$path" && "$path" != -* ]] \
        || { echo "BLOCK: invalid scope path: ${path:-<empty>}" >&2; exit 2; }
    if [[ "$path" = /* && -n "${_task_worktree_path:-}" ]]; then
        case "$path" in
            "$repo_root"/*) path="${path#"$repo_root/"}" ;;
            *) echo "BLOCK: absolute scope path is outside task worktree: $path" >&2; exit 2 ;;
        esac
    fi
    # scope_path_normalizeは絶対path・".."を含むpath(出現位置を問わず)・
    # root相当に解決されるpath(空/"."/".."単体等)を全てfail-closedし、
    # 理由をstderrへ書く(このtry/exitはその理由をそのまま伝播させる)。
    normalized="$(scope_path_normalize "$path")" || exit 2
    paths+=("$normalized")
done
requested_paths=("${paths[@]}")

# Transient tests are proof artifacts, not contract code.  Immediately before
# the commit boundary, require a complete primary receipt and remove only
# untracked transient tests explicitly listed by the current task.  Tracked
# files, undeclared paths, failed/skipped tests, and missing receipts fail
# closed without deleting anything.
transient_task_file="${NINJA_SCOPE_TASK_FILE:-}"
transient_receipt_file="${NINJA_TEST_RECEIPT:-}"
verification_head="${NINJA_SCOPE_EXPECTED_HEAD:-}"
verification_test_paths=()
verification_source_fingerprint=""
if [[ -z "$verification_head" && -n "$transient_receipt_file" && -f "$transient_receipt_file" ]]; then
    verification_head="$(python3 - "$transient_receipt_file" <<'PY'
import sys, yaml
d=yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}
head=d.get('source_head') or d.get('source_commit') or d.get('head') or ''
manifest=d.get('run_manifest')
if isinstance(manifest, dict):
    commit_sha=manifest.get('commit_sha') or ''
    if commit_sha and commit_sha != head:
        print('BLOCK: test receipt source_head/run_manifest.commit_sha mismatch', file=sys.stderr)
        raise SystemExit(2)
print(head)
PY
)" || exit 2
    if [[ -n "$verification_head" ]]; then
        mapfile -t verification_test_paths < <(python3 - "$transient_receipt_file" <<'PY'
import sys, yaml
d=yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}
for p in (d.get('test_paths') or []):
    p=str(p or '').strip()
    if p:
        print(p)
PY
)
        verification_source_fingerprint="$(python3 - "$transient_receipt_file" <<'PY'
import sys, yaml
d=yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}
print(str(d.get('source_fingerprint') or '').strip())
PY
)"
    fi
fi
if [[ -z "$verification_head" && -n "$transient_task_file" && -f "$transient_task_file" ]]; then
    verification_head="$(python3 - "$transient_task_file" <<'PY'
import sys, yaml
d=yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}; t=d.get('task', d)
print(t.get('deployed_head') or t.get('source_head') or t.get('source_commit') or '')
PY
)"
fi
# cmd_karo_hotfix_speed_ninja_scope_commit_r2_20260809: 無関係commitで
# transaction_headが進んだだけでは再テストを強制しない。verification_headから
# 比較先headまでの間に(1)対象scope path (2)receiptが検証したtest_paths
# (3)既存source_fingerprint機構(scripts/lib/tests-helpers全体)の3点全てが
# byte単位で不変なら、test結果は依然有効として再利用する(L1439: 対象path
# 限定diffで判定)。いずれか1つでも変化していれば従来通りBLOCKする。receiptに
# test_paths/source_fingerprintが無ければ(旧形式receiptやtask fileの
# deployed_head経由)、この限定判定の材料が無いため安全側へ倒し従来どおり
# 厳密一致を要求する。lock取得直前の再検証(acquire_transaction_lock_and_rebase_index)
# でも同じ判定を使い、二重に定義しない。
ninja_scope_commit_receipt_stale_reason() {
    local from_head="$1" to_head="$2"
    if [[ "$from_head" == "$to_head" ]]; then
        return 0
    fi
    if ((${#verification_test_paths[@]} == 0)) || [[ -z "$verification_source_fingerprint" ]]; then
        echo "receipt lacks test_paths/source_fingerprint for scoped reuse"
        return 1
    fi
    if ! git diff --quiet "$from_head" "$to_head" -- "${paths[@]}" 2>/dev/null; then
        echo "target scope path bytes changed between verification and transaction head"
        return 1
    fi
    if ! git diff --quiet "$from_head" "$to_head" -- "${verification_test_paths[@]}" 2>/dev/null; then
        echo "verified test path bytes changed between verification and transaction head"
        return 1
    fi
    local current_source_fingerprint
    current_source_fingerprint="$(git -C "$repo_root" ls-files --format='%(objectname)' -- scripts lib tests/helpers ':!scripts/run_tests.sh' 2>/dev/null | sha256sum | awk '{print $1}')"
    if [[ "$current_source_fingerprint" != "$verification_source_fingerprint" ]]; then
        # The receipt fingerprint is intentionally broad for test-cache safety,
        # but commit reuse must not inherit that blast radius.  Resolve only the
        # committed source paths that changed since verification through the
        # repository's dependency selector.  A disjoint test set is safe to
        # reuse; a selected dependency (or missing selector evidence) remains
        # fail-closed.  This keeps parallel agents from invalidating every
        # receipt merely by committing an unrelated script.
        local selector="$repo_root/scripts/test_select.sh"
        local selector_output selector_rc=0 changed_path affected_path verified_path
        local -a changed_source_paths=()
        mapfile -t changed_source_paths < <(
            git -C "$repo_root" diff --name-only "$from_head" "$to_head" -- \
                scripts lib tests/helpers ':!scripts/run_tests.sh' 2>/dev/null
        )
        if ((${#changed_source_paths[@]} == 0)); then
            echo "source fingerprint changed without committed dependency paths"
            return 1
        fi
        [[ -x "$selector" || -f "$selector" ]] || {
            echo "source fingerprint changed and dependency selector is unavailable"
            return 1
        }
        set +e
        selector_output="$(bash "$selector" "${changed_source_paths[@]}" 2>/dev/null)"
        selector_rc=$?
        set -e
        if [[ "$selector_rc" -ne 0 ]]; then
            echo "source fingerprint changed and dependency selector failed rc=$selector_rc"
            return 1
        fi
        while IFS= read -r affected_path; do
            [[ -n "$affected_path" ]] || continue
            affected_path="${affected_path#"$repo_root"/}"
            for verified_path in "${verification_test_paths[@]}"; do
                verified_path="${verified_path#"$repo_root"/}"
                if [[ "$affected_path" == "$verified_path" ]]; then
                    echo "verified test dependency changed: $verified_path"
                    return 1
                fi
            done
        done <<<"$selector_output"
    fi
    return 0
}
if [[ -n "$verification_head" ]]; then
    [[ "$verification_head" =~ ^[0-9a-f]{40}$ ]] && git cat-file -e "${verification_head}^{commit}" 2>/dev/null \
        || { echo "BLOCK: test verification HEAD evidence is invalid: ${verification_head:-<missing>}" >&2; exit 2; }
    stale_reason="$(ninja_scope_commit_receipt_stale_reason "$verification_head" "$transaction_head")" \
        || { echo "BLOCK: stale test receipt source_head: expected $transaction_head got $verification_head ($stale_reason)" >&2; exit 2; }
fi
if [[ -n "$transient_task_file" && -f "$transient_task_file" ]]; then
    deletion_justification="$(python3 - "$transient_task_file" <<'PY'
import sys,yaml
d=yaml.safe_load(open(sys.argv[1],encoding='utf-8')) or {}; print((d.get('task',d).get('deletion_justification') or '').strip())
PY
)"
    canonical_test_inventory="${NINJA_SCOPE_TEST_INVENTORY:-$repo_root/docs/research/ci-test-elimination-inventory-20260719.csv}"
    for scope_path in "${paths[@]}"; do
        if git cat-file -e "HEAD:$scope_path" 2>/dev/null && [[ "$scope_path" == tests/* || "$scope_path" == *.bats || "${scope_path##*/}" == test_* ]]; then
            read -r added deleted < <(git diff --numstat -- "$scope_path" | awk 'NR==1{print $1,$2}')
            added=${added:-0}; deleted=${deleted:-0}
            if ((deleted > added)) && [[ -z "$deletion_justification" ]]; then
                echo "BLOCK: existing test net deletion requires deletion_justification: $scope_path" >&2; exit 2
            fi
            if [[ ! -e "$scope_path" ]]; then
                if [[ -f "$canonical_test_inventory" ]] && awk -F, -v path="$scope_path" 'NR > 1 && $2 == path { found=1; exit } END { exit !found }' "$canonical_test_inventory"; then
                    echo "BLOCK: deleted tracked test remains referenced by canonical inventory column 2: $scope_path" >&2; exit 2
                fi
                base="${scope_path##*/}"
                if git grep -l -F "$base" HEAD -- ':!'"$scope_path" ':!'"${canonical_test_inventory#$repo_root/}" | grep -q .; then
                    echo "BLOCK: deleted test/helper remains referenced by shared fixture: $scope_path" >&2; exit 2
                fi
            fi
        fi
    done
    necessity_classification="$(
        python3 - "$transient_task_file" "$repo_root" "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/.." "${paths[@]}" <<'PY'
import json, subprocess, sys, yaml
task_file, repo, code_root, *scope = sys.argv[1:]
sys.path.insert(0, code_root)
from scripts.lib.test_necessity_contract import validate_entries
d=yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}
t=d.get('task', d)
new_tests=[]
for p in scope:
    p=str(p)
    is_test='/tests/' in f'/{p}' or p.startswith('tests/') or p.endswith(('.bats','.spec.js','.test.js')) or p.rsplit('/',1)[-1].startswith('test_')
    if is_test and subprocess.run(['git','-C',repo,'cat-file','-e',f'HEAD:{p}'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode != 0:
        new_tests.append(p)
raw=t.get('test_necessity')
entries=[dict(entry) for entry in raw if isinstance(entry,dict)] if isinstance(raw,list) else []
task_ids={str(t.get(key) or '').strip() for key in ('task_id','subtask_id','parent_cmd')}
task_ids.discard('')
new_set=set(new_tests)
current_entries=[]
retained=[]
errors=[]
for entry in entries:
    path=str(entry.get('path') or '').strip()
    if path in new_set:
        current_entries.append(entry)
        continue
    if not path:
        current_entries.append(entry)
        continue
    exists=subprocess.run(
        ['git','-C',repo,'cat-file','-e',f'HEAD:{path}'],
        stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,
    ).returncode == 0
    history=subprocess.run(
        ['git','-C',repo,'log','--format=%s','--',path],
        text=True,capture_output=True,
    )
    subjects=history.stdout.splitlines() if history.returncode == 0 else []
    same_task=exists and any(
        identity in subject for identity in task_ids for subject in subjects
    )
    if same_task:
        retained.append(path)
    else:
        errors.append(
            f'test_necessity path is neither an actual new test nor retained '
            f'in same-task history: {path}'
        )
persistent, validation_errors=validate_entries(current_entries, new_tests)
errors.extend(validation_errors)
if errors:
    print('BLOCK: new test necessity contract failed: ' + '; '.join(errors), file=sys.stderr)
    raise SystemExit(2)
print(json.dumps({
    'transient':[p for p in new_tests if p not in persistent],
    'retained':retained,
}))
PY
    )" || exit 2
    mapfile -t transient_tests < <(
        python3 -c 'import json,sys; [print(p) for p in json.loads(sys.argv[1])["transient"]]' \
            "$necessity_classification"
    )
    if ((${#transient_tests[@]})); then
        [[ -n "$verification_head" ]] || { echo "BLOCK: test verification HEAD evidence missing before transient deletion" >&2; exit 2; }
        [[ -n "$transient_receipt_file" && -f "$transient_receipt_file" ]] || { echo "BLOCK: transient test receipt missing" >&2; exit 2; }
        python3 - "$transient_receipt_file" "${transient_tests[@]}" <<'PY' || exit 2
import json, sys, yaml
d=yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}
tests=sys.argv[2:]
# Compatibility is input-only: legacy fields normalize into the canonical
# terminal contract and are never evaluated as a second source of truth.
if 'complete' not in d and any(k in d for k in ('status','pass','fail','skip')):
    d={**d, 'complete': d.get('status') == 'complete',
       'result': 'PASS' if d.get('pass') is True else 'FAIL',
       'rc': 0 if d.get('fail') == 0 else 1,
       'skip_count': d.get('skip'),
       'observed_test_count': len(d.get('test_paths') or [])}
ok=(d.get('complete') is True and d.get('result') == 'PASS' and d.get('rc') == 0 and
    d.get('skip_count') == 0 and isinstance(d.get('observed_test_count'), int) and
    d.get('observed_test_count') >= len(tests))
covered=set(map(str,d.get('test_paths') or []))
if not ok or not set(tests) <= covered:
    print('BLOCK: transient test receipt must prove complete PASS, FAIL0, SKIP0 for every candidate', file=sys.stderr); raise SystemExit(2)
PY
        for transient in "${transient_tests[@]}"; do
            git ls-files --error-unmatch -- "$transient" >/dev/null 2>&1 && { echo "BLOCK: transient deletion target is tracked: $transient" >&2; exit 2; }
            [[ -f "$transient" ]] || { echo "BLOCK: transient deletion target missing: $transient" >&2; exit 2; }
        done
        printf 'TRANSIENT_DELETE_CANDIDATES=%s\n' "$(IFS=,; echo "${transient_tests[*]}")" >&2
        for transient in "${transient_tests[@]}"; do
            git diff --no-index -- /dev/null "$transient" >&2 || [[ $? -eq 1 ]]
            rm -- "$transient"
        done
        kept=()
        for scope_path in "${paths[@]}"; do
            skip=false
            for transient in "${transient_tests[@]}"; do
                if [[ "$scope_path" == "$transient" ]]; then
                    skip=true
                fi
            done
            [[ "$skip" == false ]] && kept+=("$scope_path")
        done
        paths=("${kept[@]}")
        ((${#paths[@]})) || { echo "BLOCK: no production scope remains after transient test deletion" >&2; exit 2; }
    fi
fi

# Idempotent single-flight boundary.  The repository lock above serializes
# ref/COMMIT_EDITMSG updates, but serialization alone makes followers retry the
# same commit after the owner has already advanced HEAD.  Key the invocation by
# explicit run identity, message/mode, normalized paths, and the current
# worktree bytes.  The bytes keep a later edit from reusing a stale receipt;
# NINJA_SCOPE_COMMIT_RUN_ID lets orchestrators distinguish separate tasks that
# intentionally use the same message and paths.
singleflight_run_id="$terminal_run_id"
singleflight_material="run=$singleflight_run_id
message=$message
patch=$patch_file
base=$base_blob
repair=$repair_index"
for scope_path in "${paths[@]}"; do
    if [[ -f "$scope_path" || -L "$scope_path" ]]; then
        scope_fingerprint="$(git hash-object -- "$scope_path" 2>/dev/null || printf missing)"
    elif [[ -d "$scope_path" ]]; then
        scope_fingerprint="$(find "$scope_path" -type f -print0 2>/dev/null | sort -z | xargs -0 -r git hash-object -- 2>/dev/null | sha256sum | awk '{print $1}')"
    else
        scope_fingerprint="missing"
    fi
    singleflight_material+=$'\n'"path=$scope_path blob=$scope_fingerprint"
done
singleflight_key="$(printf '%s' "$singleflight_material" | sha256sum | awk '{print $1}')"
singleflight_dir="$(lock_path "$git_common_dir/ninja-scope-receipts")"
mkdir -p -- "$singleflight_dir"
singleflight_receipt="$singleflight_dir/$singleflight_key.receipt"

if [[ -f "$singleflight_receipt" ]]; then
    receipt_key="$(awk -F= '$1 == "key" {print $2; exit}' "$singleflight_receipt")"
    receipt_rc="$(awk -F= '$1 == "rc" {print $2; exit}' "$singleflight_receipt")"
    receipt_hash="$(awk -F= '$1 == "commit_hash" {print $2; exit}' "$singleflight_receipt")"
    receipt_completed_event="$(sed -n 's/^completed_event=//p' "$singleflight_receipt" | head -1)"
    # A receipt is only a cache of a previously proven terminal state.  It is
    # not itself proof that the current ref/index/worktree still publish that
    # state: a later failed ref/index advance can leave the same worktree bytes
    # (and therefore the same key) beside a stale receipt.  Followers must
    # re-establish the complete scoped terminal invariant before returning 0.
    receipt_scope_converged=false
    if [[ "$receipt_key" == "$singleflight_key" && "$receipt_rc" == 0 && "$receipt_hash" =~ ^[0-9a-f]{40}$ ]] && \
       git cat-file -e "${receipt_hash}^{commit}" 2>/dev/null && \
       git merge-base --is-ancestor "$receipt_hash" HEAD 2>/dev/null && \
       git diff --quiet "$receipt_hash" HEAD -- "${paths[@]}" && \
       git diff --quiet -- "${paths[@]}" && \
       git diff --cached --quiet -- "${paths[@]}"; then
        receipt_scope_converged=true
    fi
    if [[ "$receipt_scope_converged" == true ]]; then
        singleflight_role="follower"
        published_commit_hash="$receipt_hash"
        write_terminal_ledger 0 "$receipt_hash" true complete
        [[ "$receipt_completed_event" == event=completed\ * ]] && printf '%s\n' "$receipt_completed_event" >&2
        printf 'event=terminal_ledger run_id=%s rc=0 commit_hash=%s complete=true ledger=%s\n' \
            "$terminal_run_id" "$receipt_hash" "$terminal_ledger" >&2
        printf 'event=terminal_receipt role=follower key=%s rc=0 commit_hash=%s receipt=%s\n' \
            "$singleflight_key" "$receipt_hash" "$singleflight_receipt" >&2
        terminal_event_emitted=true
        printf '%s\n' "$receipt_hash"
        trap - EXIT
        exit 0
    fi
    echo "BLOCK: single-flight receipt does not match current scoped HEAD/index/worktree: $singleflight_receipt" >&2
    exit 2
fi

# Content-only receipt: unlike the singleflight receipt above (keyed on
# run id/message too), this is keyed purely on normalized paths + worktree
# blob content.  Same-scope callers must not run their hooks concurrently:
# the final publication lock is intentionally short and therefore cannot
# prevent duplicate pre-commit execution.  Serialize only identical
# normalized scopes here, leaving disjoint scopes free to run in parallel.
scope_content_material="$(printf '%s\n' "${paths[@]}")"
for scope_path in "${paths[@]}"; do
    if [[ -f "$scope_path" || -L "$scope_path" ]]; then
        scope_content_fingerprint="$(git hash-object -- "$scope_path" 2>/dev/null || printf missing)"
    elif [[ -d "$scope_path" ]]; then
        scope_content_fingerprint="$(find "$scope_path" -type f -print0 2>/dev/null | sort -z | xargs -0 -r git hash-object -- 2>/dev/null | sha256sum | awk '{print $1}')"
    else
        scope_content_fingerprint="missing"
    fi
    scope_content_material+=$'\n'"path=$scope_path blob=$scope_content_fingerprint"
done
scope_content_key="$(printf '%s' "$scope_content_material" | sha256sum | awk '{print $1}')"
scope_content_receipt_dir="$(lock_path "$git_common_dir/ninja-scope-content-receipts")"
mkdir -p -- "$scope_content_receipt_dir"
scope_content_receipt="$scope_content_receipt_dir/$scope_content_key.receipt"

# A repository-wide transaction lock protects ref publication, but it is too
# narrow to deduplicate two helpers that race the same owned bytes: both can
# reach pre-commit before either publishes HEAD.  Lock the normalized scope
# set only, so same-scope hooks are single-flight while unrelated scopes retain
# parallel pre-commit throughput.  The descriptor is closed automatically on
# every process exit, including fail-closed and signal paths.
scope_lock_material="$(printf '%s\n' "${paths[@]}" | LC_ALL=C sort -u)"
scope_lock_key="$(printf '%s' "$scope_lock_material" | sha256sum | awk '{print $1}')"
scope_lock_path="$(lock_path "$git_common_dir/ninja-scope-owned-$scope_lock_key")"
exec {scope_lock_fd}>"$scope_lock_path" \
    || { echo "BLOCK: cannot open ninja owned-scope lock" >&2; exit 2; }
scope_lock_waited=false
if ! flock -n "$scope_lock_fd"; then
    scope_lock_waited=true
    flock -w 120 "$scope_lock_fd" \
        || { echo "BLOCK: cannot acquire ninja owned-scope lock" >&2; exit 2; }
fi

if [[ -z "$patch_file" && "$repair_index" == false ]]; then
    for scope_path in "${paths[@]}"; do
        scope_is_tracked_deletion=false
        if [[ ! -e "$scope_path" && ! -L "$scope_path" ]] &&
           git cat-file -e "HEAD:$scope_path" 2>/dev/null; then
            scope_is_tracked_deletion=true
        fi
        [[ -e "$scope_path" || -L "$scope_path" || "$scope_is_tracked_deletion" == true ]] \
            || { echo "BLOCK: scope path does not exist: $scope_path" >&2; exit 2; }
    done
fi

# Repair the proven residual state where worktree bytes already equal HEAD but
# the shared index alone contains an older blob (porcelain MM, `git diff HEAD`
# empty).  This is deliberately path-bounded and runs under the same common-dir
# transaction lock.  It never resets or rewrites unrelated index entries.
if [[ "$repair_index" == true ]]; then
    for scope_path in "${paths[@]}"; do
        [[ -f "$scope_path" || -L "$scope_path" ]] \
            || { echo "BLOCK: repair path must be an existing tracked file: $scope_path" >&2; exit 2; }
        git cat-file -e "HEAD:$scope_path" 2>/dev/null \
            || { echo "BLOCK: repair path is not tracked in HEAD: $scope_path" >&2; exit 2; }
        head_blob="$(git rev-parse "HEAD:$scope_path")"
        worktree_blob="$(git hash-object -- "$scope_path")"
        [[ "$worktree_blob" == "$head_blob" ]] \
            || { echo "BLOCK: repair would hide worktree content differing from HEAD: $scope_path" >&2; exit 2; }
    done
    for scope_path in "${paths[@]}"; do
        head_blob="$(git rev-parse "HEAD:$scope_path")"
        head_mode="$(git ls-tree HEAD -- "$scope_path" | awk 'NR==1 {print $1}')"
        GIT_INDEX_FILE="$shared_index_file" git update-index --add --cacheinfo "$head_mode,$head_blob,$scope_path"
    done
    [[ -z "$(collect_owned_paths_not_at_head "${paths[@]}")" ]] \
        || { echo "BLOCK: scoped index repair did not converge to clean state" >&2; exit 1; }
    terminal_status_clean_hint=true
    [[ ! -e "$shared_index_lock" ]] \
        || { echo "BLOCK: shared index lock remained after repair: $shared_index_lock" >&2; exit 1; }
    publish_terminal_success "$(git rev-parse HEAD)"
    trap - EXIT
    exit 0
fi

# 同一pathに複数agentのhunkが混在する場合の非対話入口。共有index/working treeを
# sourceにせず、HEADから作った専用indexへ明示patchだけを適用してcommitする。
# --base-blobはpatch作成時の基準を固定し、古いpatchの誤適用を事前BLOCKする。
if [[ -n "$patch_file" ]]; then
    [[ -f "$patch_file" && -s "$patch_file" ]] \
        || { echo "BLOCK: patch is missing or empty: $patch_file" >&2; exit 2; }
    patch_file="$(cd "$(dirname "$patch_file")" && pwd)/$(basename "$patch_file")"
    scope_path="${paths[0]}"
    if git cat-file -e "$transaction_head:$scope_path" 2>/dev/null; then
        head_blob="$(git rev-parse "$transaction_head:$scope_path")"
    else
        head_blob="0000000000000000000000000000000000000000"
    fi
    [[ "$head_blob" == "$base_blob" ]] \
        || { echo "BLOCK: base blob mismatch for $scope_path (expected $base_blob, HEAD has $head_blob)" >&2; exit 2; }
    # B27: shared indexが既にHEAD差分のforeign stageを持つことは、この関数が
    # commitソースとして共有indexを使わない(専用indexをHEADから作る)以上、
    # commit自体の正当性には無関係である。事前BLOCKするとnormal modeの
    # 「partial/foreign staged content...use --patch」誘導が必ず自己矛盾で
    # 再BLOCKする無限escape不能状態になる(2026-07-25 logs/push_dirty_tree_bypass.jsonl
    # で実証済み)。ここではBLOCKせず、pre-existingなforeign stageの有無だけ記録し、
    # 破壊防止はcommit後のshared index追随(advance_shared_index_entry呼び出し)側で行う。
    shared_index_blob="$(git ls-files -s -- "$scope_path" | awk 'NR==1 {print $2}')"
    shared_index_entry_before="$(GIT_INDEX_FILE="$shared_index_file" git ls-files -s -- "$scope_path" | awk '$3 == 0 {print $1 " " $2; exit}')"
    shared_index_had_foreign_stage=false
    [[ "${shared_index_blob:-0000000000000000000000000000000000000000}" == "$head_blob" ]] \
        || shared_index_had_foreign_stage=true

    mapfile -t patch_paths < <(git apply --numstat -- "$patch_file" 2>/dev/null | awk '{print $3}')
    ((${#patch_paths[@]} > 0)) \
        || { echo "BLOCK: patch has no applicable file changes" >&2; exit 2; }
    for patch_path in "${patch_paths[@]}"; do
        [[ "$patch_path" == "$scope_path" ]] \
            || { echo "BLOCK: patch contains out-of-scope path: $patch_path" >&2; exit 2; }
    done

    temp_index="$(mktemp "${TMPDIR:-/tmp}/ninja-scope-index.XXXXXX")"
    rm -f "$temp_index"
    cleanup_patch_index() { local rc=$?; rm -f "$temp_index" "$temp_index.lock"; publish_terminal_failure "$rc"; ninja_scope_commit_record_total "$rc"; }
    trap cleanup_patch_index EXIT
    export GIT_INDEX_FILE="$temp_index"
    git read-tree "$transaction_head"
    # Deterministic contract-test seam: prove that all validation below stays
    # bound to the captured generation even when an unrelated commit advances
    # live HEAD after private-index construction.
    if [[ -n "${NINJA_SCOPE_PATCH_INDEX_READY_FILE:-}" ]]; then
        : > "$NINJA_SCOPE_PATCH_INDEX_READY_FILE"
    fi
    if [[ -n "${NINJA_SCOPE_PATCH_AFTER_INDEX_DELAY:-}" ]]; then
        sleep "$NINJA_SCOPE_PATCH_AFTER_INDEX_DELAY"
    fi
    finish_phase 0
    begin_phase add
    git apply --cached --check -- "$patch_file" \
        || { echo "BLOCK: patch does not apply cleanly to the declared base" >&2; exit 2; }
    git apply --cached -- "$patch_file"
    finish_phase 0
    begin_phase scope_sync
    [[ -n "$(git diff --cached --name-only "$transaction_head")" ]] \
        || { echo "BLOCK: patch produced an empty index diff" >&2; exit 2; }
    [[ "$(git diff --cached --name-only "$transaction_head")" == "$scope_path" ]] \
        || { echo "BLOCK: patch polluted temporary index scope" >&2; exit 2; }
    # git apply may relocate a hunk when identical context exists elsewhere.  A
    # clean exit alone therefore does not prove that the requested line range
    # entered the index.  Compare the patch's exact +/- line coordinates and
    # content with a zero-context diff generated from the temporary index.
    staged_patch="$(mktemp "${TMPDIR:-/tmp}/ninja-scope-staged.XXXXXX")"
    cleanup_patch_index() { local rc=$?; rm -f "$temp_index" "$temp_index.lock" "$staged_patch"; ninja_scope_commit_record_total "$rc"; }
    git diff --cached --no-ext-diff --no-color --unified=0 "$transaction_head" -- "$scope_path" > "$staged_patch"
    python3 - "$patch_file" "$staged_patch" <<'PY' \
        || { echo "BLOCK: staged diff does not exactly match requested patch position/content" >&2; exit 2; }
import re
import sys

HUNK = re.compile(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@')

def changes(path):
    result = []
    old_line = new_line = None
    with open(path, encoding='utf-8', errors='surrogateescape') as stream:
        for raw in stream:
            line = raw.rstrip('\n')
            match = HUNK.match(line)
            if match:
                old_line, new_line = int(match.group(1)), int(match.group(3))
                continue
            if old_line is None or line.startswith(('--- ', '+++ ', '\\')):
                continue
            if line.startswith('-'):
                result.append(('-', old_line, line[1:]))
                old_line += 1
            elif line.startswith('+'):
                result.append(('+', new_line, line[1:]))
                new_line += 1
            elif line.startswith(' '):
                old_line += 1
                new_line += 1
    return result

expected, actual = changes(sys.argv[1]), changes(sys.argv[2])
if not expected or expected != actual:
    print(f'expected changes={expected!r}', file=sys.stderr)
    print(f'actual changes={actual!r}', file=sys.stderr)
    raise SystemExit(1)
PY
    finish_phase 0
    begin_phase guard
    # Patch validation above is the patch-mode guard boundary.  Keep an
    # explicit zero/near-zero phase so both modes publish one identical schema.
    finish_phase 0
    begin_phase git_commit
    acquire_transaction_lock_and_rebase_index
    assert_head_generation
    if git diff --cached --quiet "$transaction_head" -- "${paths[@]}"; then
        finish_phase 0
        begin_phase advance_shared_index
        unset GIT_INDEX_FILE
        finish_phase 0
        begin_phase post_check
        cleanup_patch_index
        trap - EXIT
        publish_terminal_success "$transaction_head"
        trap - EXIT
        exit 0
    fi
    release_transaction_lock
    run_scoped_precommit
    acquire_transaction_lock_and_rebase_index
    assert_head_generation
    # Another helper for the same task may have published these exact owned
    # blobs while this caller was running pre-commit.  Rebuilding the private
    # index on the latest HEAD then yields no owned diff.  Treat that as an
    # idempotent success instead of manufacturing an empty commit.
    if git diff --cached --quiet "$transaction_head" -- "${paths[@]}"; then
        finish_phase 0
        begin_phase advance_shared_index
        unset GIT_INDEX_FILE
        finish_phase 0
        begin_phase post_check
        cleanup_patch_index
        trap - EXIT
        publish_terminal_success "$transaction_head"
        trap - EXIT
        exit 0
    fi
    commit_hash="$(create_and_publish_scoped_commit)"
    published_commit_hash="$commit_hash"
    assert_single_parent_commit "$commit_hash"
    # HEAD更新後、共有indexの対象pathだけを新HEADへ追随させる。他pathのstageは
    # 一切変更せず、対象pathが旧HEAD由来の逆差分として残るindex汚染を防ぐ。
    # B27: pre-existingなforeign stage(このcommit開始前から既にHEAD差分だった
    # shared index entry)は、それが自分のcommitと無関係な他者の意図的staged
    # 内容である可能性を排除できないため、advanceで上書きしない。単に追随を
    # skipしてそのまま保全する(他者のstageを破壊するな — B27 AC2)。
    finish_phase 0
    begin_phase advance_shared_index
    unset GIT_INDEX_FILE
    if [[ "$shared_index_had_foreign_stage" == true ]]; then
        echo "INFO: shared index entry predates this commit and differs from prior HEAD; leaving it untouched to avoid clobbering foreign stage: $scope_path" >&2
    else
        advance_shared_index_entry "$scope_path" "$shared_index_entry_before"
    fi
    finish_phase 0
    begin_phase post_check
    cleanup_patch_index
    trap - EXIT
    [[ ! -e "$shared_index_lock" ]] \
        || { echo "BLOCK: shared index lock remained after commit: $shared_index_lock" >&2; exit 1; }
    publish_terminal_success "$commit_hash"
    trap - EXIT
    exit 0
fi

# Normal modeも共有indexをcommit sourceにしない。HEAD由来の専用indexへ
# 指定scopeだけをaddし、commit objectの入力自体を所有権分離する。
# 共有indexにscope自身が既にstage済みでも、それがprivate indexへaddした
# worktree blobと完全一致するなら所有内容は同一なので安全に続行できる。
# partial stage等で両者が異なる場合だけfail-closedする。これにより別workerの
# unrelated stageを保持したまま、各workerが事前stageした自身のscopeをcommit
# できる。post-commit更新用に共有index entryをsnapshotしておく。
declare -A shared_index_before=()
declare -A shared_scope_entries_before=()
declare -A shared_scope_staged_before=()
shared_index_paths=()
temp_index="$(mktemp "${TMPDIR:-/tmp}/ninja-scope-index.XXXXXX")"
rm -f "$temp_index"
cleanup_normal_index() { local rc=$?; rm -f "$temp_index" "$temp_index.lock"; publish_terminal_failure "$rc"; ninja_scope_commit_record_total "$rc"; }
trap cleanup_normal_index EXIT
export GIT_INDEX_FILE="$temp_index"
git read-tree HEAD
finish_phase 0
begin_phase add
# The private index is already bounded to the caller's explicit scope.  Force
# only those pathspecs so newly generated owned files remain committable even
# when the fixed checkout intentionally carries a broad `.gitignore` (for
# example `*`).  Never force-add a discovered or repository-wide path.
git add -f -- "${paths[@]}"
# The private index is already HEAD + exact owned worktree paths.  Its cached
# tree is therefore the no-change oracle; unlike porcelain status/diff against
# the shared index, this cannot refresh or lock foreign worktree entries.
if git diff --cached --quiet HEAD -- "${paths[@]}"; then
    if [[ -f "$scope_content_receipt" ]]; then
        content_receipt_hash="$(awk -F= '$1 == "commit_hash" {print $2; exit}' "$scope_content_receipt")"
        if [[ "$content_receipt_hash" =~ ^[0-9a-f]{40}$ ]] && \
           git cat-file -e "${content_receipt_hash}^{commit}" 2>/dev/null && \
           git merge-base --is-ancestor "$content_receipt_hash" HEAD 2>/dev/null; then
            published_commit_hash="$content_receipt_hash"
            terminal_status_clean_hint=true
            unset GIT_INDEX_FILE
            rm -f "$temp_index" "$temp_index.lock"
            trap - EXIT
            write_terminal_ledger 0 "$content_receipt_hash" true complete
            printf 'event=terminal_ledger run_id=%s rc=0 commit_hash=%s complete=true ledger=%s\n' \
                "$terminal_run_id" "$content_receipt_hash" "$terminal_ledger" >&2
            printf 'event=scope_content_receipt role=follower key=%s rc=0 commit_hash=%s receipt=%s\n' \
                "$scope_content_key" "$content_receipt_hash" "$scope_content_receipt" >&2
            terminal_event_emitted=true
            ninja_scope_commit_record_total 0
            printf '%s\n' "$content_receipt_hash"
            exit 0
        fi
    fi
    echo "BLOCK: scope paths have no changes" >&2
    exit 2
fi
finish_phase 0
begin_phase scope_sync

# GA-282: task YAML is live orchestration state, not implementation source.
# A caller can legitimately arrive with both paths already staged and pass both
# to this helper (lesson writers and report finalization are common examples).
# Raw `git add` is stopped earlier by GA-228, while GA-408 correctly remains a
# fail-closed pre-commit boundary.  This helper uses a private index, so split
# the two ownership domains here before hooks run: implementation commits omit
# task YAML, task-only commits remain valid, and the shared index is untouched.
is_task_yaml_commit_path() {
    local candidate="${1:-}"
    [[ "$candidate" == queue/tasks/*.yaml ]]
}

is_operational_yaml_commit_path() {
    local candidate="${1:-}"
    [[ "$candidate" == queue/*.yaml || "$candidate" == queue/**/*.yaml || "$candidate" == logs/*.yaml ]]
}

mapfile -t private_commit_paths < <(git diff --cached --name-only --diff-filter=ACMRD)
has_task_yaml=false
has_implementation=false
task_yaml_paths=()
for candidate_path in "${private_commit_paths[@]}"; do
    if is_task_yaml_commit_path "$candidate_path"; then
        has_task_yaml=true
        task_yaml_paths+=("$candidate_path")
    elif ! is_operational_yaml_commit_path "$candidate_path"; then
        has_implementation=true
    fi
done

if [[ "$has_task_yaml" == true && "$has_implementation" == true ]]; then
    for task_yaml_path in "${task_yaml_paths[@]}"; do
        if git cat-file -e "HEAD:$task_yaml_path" 2>/dev/null; then
            git reset -q HEAD -- "$task_yaml_path"
        else
            git update-index --force-remove -- "$task_yaml_path"
        fi
        printf 'INFO(GA-282): separated live task YAML from implementation commit: %s\n' "$task_yaml_path" >&2
    done
fi

mapfile -t paths < <(git diff --cached --name-only --diff-filter=ACMRD)
((${#paths[@]} > 0)) \
    || { echo "BLOCK: scope produced an empty private index after task-YAML separation" >&2; exit 2; }

# Snapshot the shared index once for the full effective scope.  The previous
# per-scope `git ls-files` plus full-scope `git ls-files` repeated the same
# DrvFS index read N+1 times on every commit.  Keep one ordered snapshot and
# derive each pathspec aggregate in bash so directory scopes and exact-file
# scopes retain identical comparison semantics.
while IFS= read -r -d '' index_record; do
    index_meta="${index_record%%$'\t'*}"
    index_path="${index_record#*$'\t'}"
    shared_index_before["$index_path"]="${index_meta% 0}"
    shared_index_paths+=("$index_path")
done < <(GIT_INDEX_FILE="$shared_index_file" git ls-files -s -z -- "${paths[@]}")

# Snapshot only the effective commit paths.  A separated task YAML may remain
# staged by another worker in the shared index; excluding it here is what keeps
# that foreign stage byte-for-byte intact instead of treating it as our scope.
for scope_path in "${paths[@]}"; do
    shared_entries=""
    for index_path in "${shared_index_paths[@]}"; do
        if scope_path_is_in_scope "$index_path" "$scope_path"; then
            index_entry="${shared_index_before[$index_path]}"
            shared_entries+="${index_entry} 0"$'\t'"${index_path}"$'\n'
        fi
    done
    shared_scope_entries_before["$scope_path"]="${shared_entries%$'\n'}"
    if GIT_INDEX_FILE="$shared_index_file" git diff --cached --quiet -- "$scope_path"; then
        shared_scope_staged_before["$scope_path"]=0
    else
        shared_scope_staged_before["$scope_path"]=1
    fi
done

for scope_path in "${paths[@]}"; do
    private_entries="$(git ls-files -s -- "$scope_path")"
    shared_entries="${shared_scope_entries_before[$scope_path]}"
    if [[ "${shared_scope_staged_before[$scope_path]}" == 1 && "$shared_entries" != "$private_entries" ]]; then
        echo "BLOCK: scope path has partial/foreign staged content that differs from worktree: $scope_path (use --patch)" >&2
        exit 2
    fi
done

# GA-222: commit前にgitが実際に発火するhookを正本(scripts/hooks/*.sh)と同期する。
# git add後に呼ぶことで、対象正本がこのcommitのscope内ならstaged(index)版、
# scope外(他agentの作業中/未確定分含む)ならHEAD(直近commit済み)版を使い分けられる。
# 正本が存在しないrepo(このrepoの規約非対象)では無害にno-op。
if [[ -f "$repo_root/scripts/sync_git_hooks.sh" ]]; then
    sync_args=()
    for scope_path in "${paths[@]}"; do
        sync_args+=(--scope-path "$scope_path")
    done
    bash "$repo_root/scripts/sync_git_hooks.sh" "${sync_args[@]}" \
        || { echo "BLOCK(GA-222): git hook sync failed — commit aborted" >&2; exit 1; }
fi
finish_phase 0
begin_phase guard
# GA-222と同じ理由(script冒頭コメント参照): 呼び出し時のcwdは対象repo
# ($repo_root、DM-Signal等)になり得るため、"$repo_root/../multi-agent-shogun"の
# 相対推測やユーザー固有のWSL2固定パスはCI runner等の
# 別環境で解決に失敗しguardが無言でno-opになる。このscript自身の設置場所
# (NINJA_SCOPE_COMMIT_SCRIPT_DIR)は常にmulti-agent-shogun/scripts/を指すため
# それを基準にguardを解決する。
if [[ -f "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/dm_signal_research_reflux_guard.sh" ]]; then
    if [[ -n "$reflux_mode" ]]; then
        # Prepare from this helper's exact private index after scope
        # normalization.  Running prepare beforehand observes the shared index
        # and is inherently ambiguous while other ninjas have research WIP.
        bash "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/dm_signal_research_reflux_guard.sh" prepare \
            --repo "$repo_root" --mode "$reflux_mode" --evidence "$reflux_evidence"
    fi
    bash "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/dm_signal_research_reflux_guard.sh" check --repo "$repo_root"
fi
finish_phase 0
begin_phase git_commit
acquire_transaction_lock_and_rebase_index
assert_head_generation
if git diff --cached --quiet "$transaction_head" -- "${paths[@]}"; then
    finish_phase 0
    begin_phase advance_shared_index
    unset GIT_INDEX_FILE
    finish_phase 0
    begin_phase post_check
    cleanup_normal_index
    trap - EXIT
    publish_terminal_success "$transaction_head"
    trap - EXIT
    exit 0
fi
release_transaction_lock
run_scoped_precommit
acquire_transaction_lock_and_rebase_index
assert_head_generation
if git diff --cached --quiet "$transaction_head" -- "${paths[@]}"; then
    finish_phase 0
    begin_phase advance_shared_index
    unset GIT_INDEX_FILE
    finish_phase 0
    begin_phase post_check
    cleanup_normal_index
    trap - EXIT
    publish_terminal_success "$transaction_head"
    trap - EXIT
    exit 0
fi
commit_hash="$(create_and_publish_scoped_commit)"
published_commit_hash="$commit_hash"
assert_single_parent_commit "$commit_hash"
mapfile -t committed < <(git diff-tree --no-commit-id --name-only -r HEAD)
finish_phase 0
begin_phase advance_shared_index
unset GIT_INDEX_FILE

# 共有indexは指定scopeだけ新HEADへ追随。他pathのstageはblob/modeとも不変。
# commit中に別processがscopeの共有index entryを書き換えた場合は、その新しい
# stageを上書きせず保持する。事前stageがprivate entryと同一なら既にnew HEADと
# 一致するためupdate不要、cleanな旧HEAD entryだけをnew HEADへ進める。
advance_shared_index_entries "${committed[@]}"
finish_phase 0
begin_phase post_check
cleanup_normal_index
trap - EXIT

# 二値postcondition: commit treeは指定scopeのみ、他者stageはそのまま残る。
# scope_path_is_in_scope(SSOT)で判定することで、正規化ロジックの重複を避ける。
for committed_path in "${committed[@]}"; do
    scope_path_is_in_scope "$committed_path" "${requested_paths[@]}" \
        || { echo "FATAL: out-of-scope path entered commit: $committed_path" >&2; exit 1; }
done

# Commit公開後に到着したdirty hunkは別eventであり、既にterminalなcommitを
# 失敗へ巻き戻さない。重複は可視WARNに留め、最終report/checkpointで照合する。
dirty_scope_paths="$(collect_owned_paths_not_at_head "${committed[@]}" | sort -u | sed '/^$/d')"
if [[ -f "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/lib/report_commit_nonoverlap_filter.sh" ]]; then
    # shellcheck source=scripts/lib/report_commit_nonoverlap_filter.sh
    source "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/lib/report_commit_nonoverlap_filter.sh"
    if [[ -n "$dirty_scope_paths" ]]; then
        commit_probe="$(mktemp)"
        trap 'rm -f "${commit_probe:-}"' EXIT
        printf 'commit_hash: %s\n' "$commit_hash" > "$commit_probe"
        overlapping_dirty="$(filter_report_commit_nonoverlap_uncommitted "$repo_root" "$commit_probe" "$dirty_scope_paths")"
        rm -f "$commit_probe"
        trap - EXIT
        if [[ -n "$overlapping_dirty" ]]; then
            echo "WARN(GA-260): post-commit mutation — terminal commit後に同一scopeの未commit差分あり:" >&2
            while IFS= read -r dirty_path; do
                [[ -n "$dirty_path" ]] && printf '  %s\n' "$dirty_path" >&2
            done <<< "$overlapping_dirty"
            echo "公開済みcommitは成功のまま維持し、追加差分は次eventとして最終checkpointで照合する" >&2
        fi
    fi
fi

[[ ! -e "$shared_index_lock" ]] \
    || { echo "BLOCK: shared index lock remained after commit: $shared_index_lock" >&2; exit 1; }

[[ -n "${dirty_scope_paths:-}" ]] || terminal_status_clean_hint=true
publish_terminal_success "$commit_hash"
trap - EXIT
