#!/usr/bin/env bash
# pre-commit hook with failure recording (cmd_1117)
#
# Non-zero exitで logs/hook_failures.yaml に自動記録。
# 記録部分は || true で防御（記録エラーでhookの動作を阻害しない）。

# GA-222: git rev-parseを第一手段にする。.git/hooks/直接配置(symlinkでない)場合でも
# BASH_SOURCEパターン除去に頼らず常にREPO_ROOTを正しく解決する(L519の意図をより堅牢に踏襲)。
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
    _git_pre_commit_self="${BASH_SOURCE[0]:-$0}"
    [[ "$_git_pre_commit_self" != /* ]] && _git_pre_commit_self="$PWD/$_git_pre_commit_self"
    REPO_ROOT="${_git_pre_commit_self%/scripts/hooks/git-pre-commit.sh}"
    unset _git_pre_commit_self
fi

# Timing persistence is best-effort and must never participate in the
# synchronous allow/BLOCK decision.
# shellcheck source=scripts/lib/defense_overhead_writer.sh
source "$REPO_ROOT/scripts/lib/defense_overhead_writer.sh"

# One monotonic-in-process clock and one terminal receipt make every commit
# diagnosable without adding external telemetry I/O to this hot path.
declare -A _PRECOMMIT_STEP_MS=() _PRECOMMIT_STEP_RC=()
_PRECOMMIT_STEP_ORDER=(self_sync staged_snapshot test_granularity task_scope yaml_ast shell_syntax sourced_dep instruction_sync context_metadata codd_context_freshness tobe_no_line_numbers doc_no_changelog semantic)
_PRECOMMIT_COMMAND_ID="${NINJA_COMMIT_COMMAND_ID:-${COMMAND_ID:-precommit-$$}}"
_PRECOMMIT_STARTED_US="${EPOCHREALTIME/./}"
_PRECOMMIT_TERMINAL_EMITTED=false
_PRECOMMIT_SELF_SYNC_RUNNING_IS_LIVE_HOOK="${PRECOMMIT_SELF_SYNC_RUNNING_IS_LIVE_HOOK:-false}"
_PRECOMMIT_SELF_SYNC_STAGED_HOOK_RELATED="${PRECOMMIT_SELF_SYNC_STAGED_HOOK_RELATED:-false}"
_PRECOMMIT_SELF_SYNC_CMP_EQUAL="${PRECOMMIT_SELF_SYNC_CMP_EQUAL:-false}"
_PRECOMMIT_SELF_SYNC_SYNC_CALLED="${PRECOMMIT_SELF_SYNC_SYNC_CALLED:-false}"
_PRECOMMIT_SELF_SYNC_REEXEC="${PRECOMMIT_SELF_SYNC_REEXEC:-false}"
_PRECOMMIT_SELF_SYNC_STARTED_US="${PRECOMMIT_SELF_SYNC_STARTED_US:-}"
# cmd_karo_hotfix_hot_script_instruction_sync_20260728 AC3: record which
# branch build_instructions.sh actually took so future re-measurement reads
# skip/rebuild counts straight from the ledger instead of reconstructing them
# from git log (as this task's own AC1/AC3 analysis had to).
_PRECOMMIT_INSTRUCTION_SYNC_REBUILT=0
_PRECOMMIT_INSTRUCTION_SYNC_SKIPPED=0
_PRECOMMIT_TEST_RECEIPT="${NINJA_TEST_RECEIPT:-}"

precommit_staged_tree_hash() {
    git write-tree 2>/dev/null
}

precommit_staged_blob_hashes() {
    local path
    while IFS= read -r path; do
        [[ "$path" == *.sh ]] || continue
        printf '%s=%s\n' "$path" "$(git rev-parse ":$path" 2>/dev/null || true)"
    done < <(list_staged_files)
}

# A receipt is only a cache of an already completed test run.  Reuse is
# deliberately fail-closed: old receipts without the exact commit-boundary
# identity simply take the normal execution path.
precommit_receipt_matches() {
    local task_file="$1" receipt="$_PRECOMMIT_TEST_RECEIPT" identity tree blobs
    [[ -f "$receipt" ]] || return 1
    identity="${receipt}.precommit-identity.json"
    [[ -f "$identity" ]] || identity="$receipt"
    tree="$(precommit_staged_tree_hash)" || return 1
    blobs="$(precommit_staged_blob_hashes)"
    python3 - "$receipt" "$identity" "$task_file" "$(git rev-parse HEAD)" "$tree" "$blobs" <<'PY'
import hashlib, json, os, sys, yaml
receipt, identity_file, task_file, head, staged_tree, blobs = sys.argv[1:]
try:
    data = yaml.safe_load(open(receipt, encoding="utf-8")) or {}
    identity_data = yaml.safe_load(open(identity_file, encoding="utf-8")) or {}
    task_doc = yaml.safe_load(open(task_file, encoding="utf-8")) or {}
    task = task_doc.get("task", task_doc)
    ident = identity_data.get("precommit_identity") or {}
    paths = data.get("test_paths") or []
    selected = hashlib.sha256(("\n".join(sorted(paths)) + "\n").encode()).hexdigest()
    ok = (
        data.get("complete") is True and data.get("result") == "PASS"
        and data.get("rc") == 0 and data.get("skip_count") == 0
        and data.get("source_head") == head
        and ident.get("task_id") == task.get("task_id")
        and ident.get("source_head") == head
        and ident.get("selected_tests_sha256") == selected
        and ident.get("staged_tree") == staged_tree
        and ident.get("staged_shell_blobs", "") == blobs
    )
except (OSError, ValueError, TypeError, KeyError, yaml.YAMLError):
    ok = False
raise SystemExit(0 if ok else 1)
PY
}

precommit_publish_receipt_identity() {
    local task_file="$1" receipt="$_PRECOMMIT_TEST_RECEIPT" tree blobs
    [[ -f "$receipt" ]] || return 0
    tree="$(precommit_staged_tree_hash)" || return 0
    blobs="$(precommit_staged_blob_hashes)"
    python3 - "$receipt" "${receipt}.precommit-identity.json" "$task_file" \
        "$(git rev-parse HEAD)" "$tree" "$blobs" <<'PY'
import hashlib, json, os, sys, tempfile, yaml
receipt, output, task_file, head, tree, blobs = sys.argv[1:]
try:
    data=yaml.safe_load(open(receipt, encoding='utf-8')) or {}
    task=(yaml.safe_load(open(task_file, encoding='utf-8')) or {}).get('task', {})
    paths=data.get('test_paths') or []
    if not (data.get('complete') is True and data.get('result') == 'PASS'
            and data.get('rc') == 0 and data.get('skip_count') == 0
            and data.get('source_head') == head): raise ValueError('not reusable')
    payload={'precommit_identity': {
        'task_id': task.get('task_id'), 'source_head': head,
        'selected_tests_sha256': hashlib.sha256(('\n'.join(sorted(paths))+'\n').encode()).hexdigest(),
        'staged_tree': tree, 'staged_shell_blobs': blobs}}
    fd,tmp=tempfile.mkstemp(prefix='.precommit-identity.', dir=os.path.dirname(output) or '.')
    with os.fdopen(fd,'w',encoding='utf-8') as f: json.dump(payload,f,sort_keys=True); f.write('\n')
    os.replace(tmp,output)
except (OSError, ValueError, TypeError, yaml.YAMLError):
    pass
PY
}

precommit_epoch_us() {
    local value="${EPOCHREALTIME/./}"
    printf -v "$1" '%s' "${value:0:16}"
}

precommit_step_begin() {
    _PRECOMMIT_CURRENT_STEP="$1"
    precommit_epoch_us _PRECOMMIT_STEP_STARTED_US
}

precommit_step_end() {
    local rc="${1:-0}" finished_us
    precommit_epoch_us finished_us
    _PRECOMMIT_STEP_MS["$_PRECOMMIT_CURRENT_STEP"]=$(((finished_us - _PRECOMMIT_STEP_STARTED_US + 999) / 1000))
    _PRECOMMIT_STEP_RC["$_PRECOMMIT_CURRENT_STEP"]="$rc"
}

precommit_self_sync_write_async() {
    local wall_ms="$1" verdict="$2" event_id="$3"
    local ledger="${DEFENSE_OVERHEAD_LEDGER:-$REPO_ROOT/logs/defense_overhead.jsonl}"
    (
        python3 - "$ledger" "$wall_ms" "$verdict" "$event_id" \
            "$_PRECOMMIT_SELF_SYNC_RUNNING_IS_LIVE_HOOK" \
            "$_PRECOMMIT_SELF_SYNC_STAGED_HOOK_RELATED" \
            "$_PRECOMMIT_SELF_SYNC_CMP_EQUAL" \
            "$_PRECOMMIT_SELF_SYNC_SYNC_CALLED" \
            "$_PRECOMMIT_SELF_SYNC_REEXEC" <<'PY'
import datetime
import fcntl
import json
import os
import sys

ledger, wall_ms, verdict, event_id, *flags = sys.argv[1:]
keys = (
    "running_is_live_hook", "staged_hook_related", "cmp_equal",
    "sync_called", "reexec",
)
row = {
    "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "source": "git_pre_commit",
    "check_id": "self_sync",
    "wall_ms": int(wall_ms),
    "verdict": verdict,
    "event_id": event_id,
    **dict(zip(keys, (flag == "true" for flag in flags))),
}
lock_path = ledger + ".lock"
os.makedirs(os.path.dirname(ledger), exist_ok=True)
with open(lock_path, "a", encoding="utf-8") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    if os.path.exists(ledger):
        with open(ledger, encoding="utf-8") as current:
            if any(json.loads(line).get("event_id") == event_id for line in current if line.strip()):
                raise SystemExit(0)
    with open(ledger, "a", encoding="utf-8") as output:
        output.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
PY
    ) >/dev/null 2>&1 &
}

precommit_instruction_sync_write_async() {
    local wall_ms="$1" verdict="$2" event_id="$3"
    local ledger="${DEFENSE_OVERHEAD_LEDGER:-$REPO_ROOT/logs/defense_overhead.jsonl}"
    (
        python3 - "$ledger" "$wall_ms" "$verdict" "$event_id" \
            "$_PRECOMMIT_INSTRUCTION_SYNC_REBUILT" \
            "$_PRECOMMIT_INSTRUCTION_SYNC_SKIPPED" <<'PY'
import datetime
import fcntl
import json
import os
import sys

ledger, wall_ms, verdict, event_id, rebuilt, skipped = sys.argv[1:]
row = {
    "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "source": "git_pre_commit",
    "check_id": "instruction_sync",
    "wall_ms": int(wall_ms),
    "verdict": verdict,
    "event_id": event_id,
    "rebuilt": int(rebuilt),
    "skipped": int(skipped),
}
lock_path = ledger + ".lock"
os.makedirs(os.path.dirname(ledger), exist_ok=True)
with open(lock_path, "a", encoding="utf-8") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    if os.path.exists(ledger):
        with open(ledger, encoding="utf-8") as current:
            if any(json.loads(line).get("event_id") == event_id for line in current if line.strip()):
                raise SystemExit(0)
    with open(ledger, "a", encoding="utf-8") as output:
        output.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
PY
    ) >/dev/null 2>&1 &
}

precommit_terminal_receipt() {
    local rc="${1:-0}" finished_us total_ms step step_rc step_verdict
    local -a timing_events=()
    [[ "$_PRECOMMIT_TERMINAL_EMITTED" == false ]] || return 0
    precommit_epoch_us finished_us
    total_ms=$(((finished_us - _PRECOMMIT_STARTED_US + 999) / 1000))
    printf 'PRECOMMIT_RECEIPT command_id=%s result=%s rc=%s wall_ms=%s' \
        "$_PRECOMMIT_COMMAND_ID" "$([[ "$rc" -eq 0 ]] && echo success || echo blocked)" "$rc" "$total_ms" >&2
    for step in "${_PRECOMMIT_STEP_ORDER[@]}"; do
        printf ' %s_ms=%s %s_rc=%s' "$step" "${_PRECOMMIT_STEP_MS[$step]:-0}" \
            "$step" "${_PRECOMMIT_STEP_RC[$step]:-0}" >&2
        if [[ -v "_PRECOMMIT_STEP_RC[$step]" ]]; then
            step_rc="${_PRECOMMIT_STEP_RC[$step]}"
            step_verdict="$([[ "$step_rc" -eq 0 ]] && echo PASS || echo BLOCK)"
            if [[ "$step" == self_sync ]]; then
                precommit_self_sync_write_async "${_PRECOMMIT_STEP_MS[$step]}" \
                    "$step_verdict" "${_PRECOMMIT_COMMAND_ID}-${step}"
            elif [[ "$step" == instruction_sync ]]; then
                precommit_instruction_sync_write_async "${_PRECOMMIT_STEP_MS[$step]}" \
                    "$step_verdict" "${_PRECOMMIT_COMMAND_ID}-${step}"
            else
                timing_events+=(git_pre_commit "$step" "${_PRECOMMIT_STEP_MS[$step]}" \
                    "$step_verdict" "${_PRECOMMIT_COMMAND_ID}-${step}")
            fi
        fi
    done
    defense_overhead_write_batch_async "${timing_events[@]}" || true
    printf '\n' >&2
    _PRECOMMIT_TERMINAL_EMITTED=true
}

# The staged snapshot is shared by self-sync and every downstream check.  Keep
# this before self-sync so the hook never pays a second git diff --cached scan.
declare -a _STAGED_FILES=()
declare -a _ADDED_TEST_FILES=()
declare -A _STAGED_FILE_STATUS=()
_STAGED_FILES_LOADED=false

load_staged_file_cache() {
    local status path_a path_b path

    [[ "$_STAGED_FILES_LOADED" == "true" ]] && return 0
    _STAGED_FILES_LOADED=true

    while IFS=$'\t' read -r status path_a path_b; do
        [[ -n "$status" ]] || continue
        path="${path_b:-$path_a}"
        [[ -n "$path" ]] || continue
        _STAGED_FILES+=("$path")
        _STAGED_FILE_STATUS["$path"]="$status"
        if [[ "$status" == A* && "$path" == tests/unit/test_*.bats ]]; then
            _ADDED_TEST_FILES+=("$path")
        fi
    done < <(git diff --cached --name-status --diff-filter=ACMRD 2>/dev/null)
}

list_staged_files() {
    load_staged_file_cache
    ((${#_STAGED_FILES[@]} == 0)) && return 0
    printf '%s\n' "${_STAGED_FILES[@]}"
}

list_added_test_files() {
    load_staged_file_cache
    ((${#_ADDED_TEST_FILES[@]} == 0)) && return 0
    printf '%s\n' "${_ADDED_TEST_FILES[@]}"
}

staged_file_exists() {
    local wanted="${1:-}" staged_file
    [[ -n "$wanted" ]] || return 1
    load_staged_file_cache
    for staged_file in "${_STAGED_FILES[@]}"; do
        [[ "$staged_file" == "$wanted" ]] && return 0
    done
    return 1
}

staged_hook_related_exists() {
    local staged_file
    load_staged_file_cache
    for staged_file in "${_STAGED_FILES[@]}"; do
        case "$staged_file" in
            # Keep this list identical to sync_git_hooks.sh's HOOK_MANIFEST.
            # scripts/hooks/ also contains Codex/runtime hooks that Git never
            # installs.  Treating that whole directory as git-hook-related
            # forced a redundant full synchronizer inside pre-commit after
            # ninja_scope_commit had already synchronized the real manifest.
            scripts/hooks/git-pre-commit.sh|.githooks/post-commit|.githooks/pre-push) return 0 ;;
        esac
    done
    return 1
}

precommit_shell_syntax_cache_hit() {
    local cache_file="$1" blob_oid="$2" content_sha="$3"
    local version="" cached_oid="" cached_sha="" cached_bash="" extra=""
    [[ -f "$cache_file" ]] || return 1
    IFS=$'\t' read -r version cached_oid cached_sha cached_bash extra < "$cache_file" || return 1
    [[ -z "$extra" && "$version" == v1 ]] || return 1
    [[ "$cached_oid" == "$blob_oid" && "$cached_sha" == "$content_sha" ]] || return 1
    [[ "$cached_bash" == "$BASH_VERSION" ]] || return 1
}

precommit_shell_syntax_cache_publish() {
    local cache_file="$1" blob_oid="$2" content_sha="$3"
    local cache_dir cache_tmp
    cache_dir="${cache_file%/*}"
    mkdir -p "$cache_dir" 2>/dev/null || return 0
    cache_tmp="$(mktemp "$cache_dir/.shell-syntax.XXXXXX" 2>/dev/null)" || return 0
    if printf 'v1\t%s\t%s\t%s\n' "$blob_oid" "$content_sha" "$BASH_VERSION" > "$cache_tmp"; then
        mv "$cache_tmp" "$cache_file" 2>/dev/null || rm -f "$cache_tmp"
    else
        rm -f "$cache_tmp"
    fi
}

check_staged_shell_syntax() {
    local staged_sh blob_oid content_sha bash_key cache_root cache_file syntax_input tmp_input
    local -a staged_shells=()
    local -A worktree_differs=()

    while IFS= read -r staged_sh; do
        [[ "$staged_sh" == *.sh ]] || continue
        staged_file_exists "$staged_sh" || continue
        # A staged deletion has no index blob; parsing it is impossible and must
        # not fail closed (2026-09-01: `git rm scripts/shutsujin_departure.sh`
        # was BLOCKed as "bash -n failed"). Only blobs present in the index parse.
        git cat-file -e ":$staged_sh" 2>/dev/null || continue
        staged_shells+=("$staged_sh")
    done < <(list_staged_files)

    # A single target is cheaper through the original index-blob pipeline.
    # For multiple targets, pay for one bounded diff and parse unchanged
    # worktree files directly. Files with unstaged changes still parse the
    # staged blob, so the allow/BLOCK decision remains index-based.
    if ((${#staged_shells[@]} > 1)); then
        while IFS= read -r staged_sh; do
            [[ -n "$staged_sh" ]] && worktree_differs["$staged_sh"]=1
        done < <(git diff --name-only -- "${staged_shells[@]}" 2>/dev/null)
    fi

    cache_root="${PRECOMMIT_SHELL_SYNTAX_CACHE_DIR:-$REPO_ROOT/.cache/precommit-shell-syntax}"
    bash_key="$(printf '%s' "$BASH_VERSION" | sha256sum | awk '{print $1}')" || bash_key=""

    for staged_sh in "${staged_shells[@]}"; do
        blob_oid="$(git rev-parse ":$staged_sh" 2>/dev/null || true)"
        if [[ ! "$blob_oid" =~ ^[0-9a-fA-F]{40,64}$ || -z "$bash_key" ]]; then
            printf '%s\n' "$staged_sh"
            continue
        fi

        syntax_input=""
        tmp_input=""
        if ((${#staged_shells[@]} > 1)) &&
            [[ -f "$REPO_ROOT/$staged_sh" ]] &&
            [[ ! -v "worktree_differs[$staged_sh]" ]]; then
            syntax_input="$REPO_ROOT/$staged_sh"
        else
            tmp_input="$(mktemp "${TMPDIR:-/tmp}/precommit-shell-syntax.XXXXXX")" || {
                printf '%s\n' "$staged_sh"
                continue
            }
            if ! git show ":$staged_sh" > "$tmp_input" 2>/dev/null; then
                rm -f "$tmp_input"
                printf '%s\n' "$staged_sh"
                continue
            fi
            syntax_input="$tmp_input"
        fi

        content_sha="$(sha256sum "$syntax_input" 2>/dev/null | awk '{print $1}')"
        if [[ ! "$content_sha" =~ ^[0-9a-f]{64}$ ]]; then
            [[ -z "$tmp_input" ]] || rm -f "$tmp_input"
            printf '%s\n' "$staged_sh"
            continue
        fi
        cache_file="$cache_root/${blob_oid}.${bash_key}.pass"
        if precommit_shell_syntax_cache_hit "$cache_file" "$blob_oid" "$content_sha"; then
            [[ -z "$tmp_input" ]] || rm -f "$tmp_input"
            continue
        fi
        if bash -n "$syntax_input" 2>/dev/null; then
            precommit_shell_syntax_cache_publish "$cache_file" "$blob_oid" "$content_sha"
        else
            printf '%s\n' "$staged_sh"
        fi
        [[ -z "$tmp_input" ]] || rm -f "$tmp_input"
    done
}

# Return 1 only when the sole manifest-backed staged path is the pre-commit
# SSOT and its index blob already equals the installed hook.  Any other
# manifest path, unreadable identity, or byte difference remains fail-closed.
staged_hook_sync_required() {
    local installed_hook="$1" staged_file saw_precommit=false
    load_staged_file_cache
    for staged_file in "${_STAGED_FILES[@]}"; do
        case "$staged_file" in
            scripts/hooks/git-pre-commit.sh)
                saw_precommit=true
                ;;
            .githooks/post-commit|.githooks/pre-push)
                return 0
                ;;
        esac
    done
    [[ "$saw_precommit" == true && -r "$installed_hook" ]] || return 0
    cmp -s <(git -C "$REPO_ROOT" show :scripts/hooks/git-pre-commit.sh 2>/dev/null) \
        "$installed_hook" || return 0
    return 1
}

# Return 0 when the full synchronizer must run, 1 only for the proven-clean
# fast path. Content-read failure deliberately falls back to synchronization;
# PRECOMMIT_RECEIPT self_sync_ms measures this decision independently.
precommit_self_sync_required() {
    local installed_hook="$1" source_hook
    _PRECOMMIT_SELF_SYNC_STAGED_HOOK_RELATED=false
    _PRECOMMIT_SELF_SYNC_CMP_EQUAL=false
    if staged_hook_related_exists; then
        _PRECOMMIT_SELF_SYNC_STAGED_HOOK_RELATED=true
        if staged_hook_sync_required "$installed_hook"; then
            return 0
        fi
        _PRECOMMIT_SELF_SYNC_CMP_EQUAL=true
        return 1
    fi
    source_hook="$REPO_ROOT/scripts/hooks/git-pre-commit.sh"
    [[ -r "$source_hook" && -r "$installed_hook" ]] || return 0
    if cmp -s "$source_hook" "$installed_hook"; then
        _PRECOMMIT_SELF_SYNC_CMP_EQUAL=true
        return 1
    fi
    return 0
}

# Self-sync runs before failure-log plumbing is initialized, but it is still a
# fail-closed terminal step and must publish the same truthful receipt.
trap '_ec=$?; precommit_terminal_receipt "$_ec"; exit "$_ec"' EXIT

# The tracked hook is the SSOT, while Git executes an untracked copy under
# .git/hooks.  ninja_scope_commit.sh syncs that copy explicitly, but direct
# `git commit` callers are also valid and previously left the live hook stale.
# A live hook therefore reconciles itself from the commit index (when this
# commit includes the SSOT) or HEAD, then re-execs the atomically replaced copy.
# Populate the parent-shell snapshot even when this tracked source is invoked
# directly (tests and diagnostics); live-hook self-sync reuses the same data.
load_staged_file_cache
if [[ -n "$_PRECOMMIT_SELF_SYNC_STARTED_US" ]]; then
    _PRECOMMIT_CURRENT_STEP=self_sync
    _PRECOMMIT_STEP_STARTED_US="$_PRECOMMIT_SELF_SYNC_STARTED_US"
else
    precommit_step_begin self_sync
    _PRECOMMIT_SELF_SYNC_STARTED_US="$_PRECOMMIT_STEP_STARTED_US"
fi
if [[ "${GIT_PRE_COMMIT_SELF_SYNCED:-0}" != "1" && -f "$REPO_ROOT/scripts/sync_git_hooks.sh" ]]; then
    _installed_hook="$(git -C "$REPO_ROOT" rev-parse --git-path hooks/pre-commit 2>/dev/null || true)"
    [[ "$_installed_hook" = /* ]] || _installed_hook="$REPO_ROOT/$_installed_hook"
    _running_hook="${BASH_SOURCE[0]:-$0}"
    [[ "$_running_hook" = /* ]] || _running_hook="$PWD/$_running_hook"
    if [[ -e "$_installed_hook" && "$_running_hook" -ef "$_installed_hook" ]]; then
        _PRECOMMIT_SELF_SYNC_RUNNING_IS_LIVE_HOOK=true
        _sync_args=()
        # Do not put the cache loader on the left side of a pipeline: Bash
        # would populate the array in a subshell and main() would rescan the
        # DrvFS index.  This parent-shell lookup is both exact and persistent.
        if staged_file_exists scripts/hooks/git-pre-commit.sh; then
            _sync_args+=(--scope-path scripts/hooks/git-pre-commit.sh)
        fi
        if precommit_self_sync_required "$_installed_hook"; then
            # sha256sum is only needed to detect whether sync_git_hooks.sh
            # actually rewrote the installed hook; computing it before this
            # branch spent a subprocess (~10-40ms on DrvFS) on every commit,
            # including the common case where precommit_self_sync_required
            # already decided (via cmp) that no sync is required at all.
            _hook_hash_before="$(sha256sum "$_installed_hook" | awk '{print $1}')"
            _PRECOMMIT_SELF_SYNC_SYNC_CALLED=true
            bash "$REPO_ROOT/scripts/sync_git_hooks.sh" "${_sync_args[@]}" || {
                precommit_step_end 1
                echo "BLOCK(GA-222): live pre-commit hook self-sync failed" >&2
                exit 1
            }
            _hook_hash_after="$(sha256sum "$_installed_hook" | awk '{print $1}')"
            if [[ "$_hook_hash_before" != "$_hook_hash_after" ]]; then
                _PRECOMMIT_SELF_SYNC_REEXEC=true
                exec env GIT_PRE_COMMIT_SELF_SYNCED=1 \
                    PRECOMMIT_SELF_SYNC_RUNNING_IS_LIVE_HOOK="$_PRECOMMIT_SELF_SYNC_RUNNING_IS_LIVE_HOOK" \
                    PRECOMMIT_SELF_SYNC_STAGED_HOOK_RELATED="$_PRECOMMIT_SELF_SYNC_STAGED_HOOK_RELATED" \
                    PRECOMMIT_SELF_SYNC_CMP_EQUAL="$_PRECOMMIT_SELF_SYNC_CMP_EQUAL" \
                    PRECOMMIT_SELF_SYNC_SYNC_CALLED="$_PRECOMMIT_SELF_SYNC_SYNC_CALLED" \
                    PRECOMMIT_SELF_SYNC_REEXEC="$_PRECOMMIT_SELF_SYNC_REEXEC" \
                    PRECOMMIT_SELF_SYNC_STARTED_US="$_PRECOMMIT_SELF_SYNC_STARTED_US" \
                    "$_installed_hook" "$@"
            fi
        fi
        unset _installed_hook _running_hook _hook_hash_before _hook_hash_after _sync_args
    fi
fi
precommit_step_end 0
_STDERR_FILE="/tmp/_hook_stderr_precommit_$$"

# A staged script may not `source` a repo file that this commit neither tracks
# nor stages.  2026-07-25: 239d663ff added
# `source .../scripts/lib/gate_report_format_classify.sh` to cmd_complete_gate.sh
# while the lib itself stayed untracked.  It worked on every machine that had the
# file on disk and broke every fresh checkout and CI run — the completion GATE
# aborted at source time.  Only paths that exist in the working tree are
# inspected, so dynamic or genuinely external sources cannot false-positive.
check_staged_sourced_deps() {
    local staged_sh dep tracked_path missing="" tracked_loaded=false
    local -A tracked_paths=()
    while IFS= read -r staged_sh; do
        [[ "$staged_sh" == *.sh ]] || continue
        staged_file_exists "$staged_sh" || continue
        while IFS= read -r dep; do
            [[ -n "$dep" ]] || continue
            [[ -f "$REPO_ROOT/$dep" ]] || continue
            # `git ls-files --error-unmatch` once per dependency made this
            # guard scale with source-edge count and produced second-level
            # outliers.  The index is invariant during this check, so load it
            # once on the first real repo dependency and use exact-key lookups.
            if [[ "$tracked_loaded" == false ]]; then
                while IFS= read -r tracked_path; do
                    [[ -n "$tracked_path" ]] && tracked_paths["$tracked_path"]=1
                done < <(git ls-files)
                tracked_loaded=true
            fi
            [[ -v "tracked_paths[$dep]" ]] && continue
            missing+="    $staged_sh -> $dep"$'\n'
        done < <(
            git show ":$staged_sh" 2>/dev/null \
                | grep -oE '^[[:space:]]*(source|\.)[[:space:]]+"?[^"[:space:]]+' \
                | grep -oE '(scripts|tests|config)/[A-Za-z0-9_./-]+'
        )
    done < <(list_staged_files)
    [[ -z "$missing" ]] && return 0
    echo "BLOCKED: staged script sources a repo file that is not tracked and not staged:" >&2
    printf '%s' "$missing" >&2
    echo "It exists on your disk only. Fresh checkouts and CI would fail at source time." >&2
    echo "Stage the sourced file in this same commit (git add <path>)." >&2
    return 1
}

# AC2 (cmd_karo_impl_precommit_affected_link_20260725): a staged scripts/lib/
# change can break a caller whose own test never touches the lib path
# directly. CI RED run 30150910971 was exactly this shape: the changed file's
# own tests passed, the dependent side broke. Trace both `source`/`.` edges
# AND `bash <path>` subprocess-invocation edges forward via grep (same
# technique as check_staged_sourced_deps, reused here to find callers instead
# of dependencies) and emit each caller path so its tests ride along into the
# affected-test run below. `bash` matters as much as `source` here: 軍師's
# review measured scripts/lib/yaml_field_set.sh at 59 real callers and
# scripts/lib/agent_config.sh at 46 — git grep -hF confirmed the overwhelming
# majority of yaml_field_set.sh's own 37 repo references are `bash
# .../yaml_field_set.sh "$file" ...` CLI-style calls, not `source`. A
# source-only pattern would silently miss almost all of them.
resolve_reverse_lib_deps() {
    local staged_sh line caller base
    local -a batched_lib_bases=()
    declare -A batched_seen=()
    while IFS= read -r staged_sh; do
        [[ "$staged_sh" == scripts/lib/*.sh ]] || continue
        staged_file_exists "$staged_sh" || continue
        batched_lib_bases+=("${staged_sh##*/}")
    done < <(list_staged_files)
    (("${#batched_lib_bases[@]} > 0")) || return 0
    while IFS= read -r line; do
        caller="${line%%:*}"
        for base in "${batched_lib_bases[@]}"; do
            if [[ "$line" == *"/$base"* && "$caller" != "scripts/lib/$base" ]]; then
                [[ "${batched_seen["$caller"]+x}" ]] || {
                    printf '%s\n' "$caller"
                    batched_seen["$caller"]=1
                }
                break
            fi
        done
    done < <(
        git -C "$REPO_ROOT" grep -nE '(source|\.|bash)[[:space:]].*/[A-Za-z0-9_.-]+\.sh([[:space:]]|\"|$)' \
            -- 'scripts' '.githooks' '.claude/hooks' 2>/dev/null
    )
    return 0
}

# LG042/LK-A14: reverse-dependency reports must state how many locations were
# searched, not just how many matched, so the scan's honesty is auditable.
reverse_lib_dep_scan_scope() {
    git -C "$REPO_ROOT" ls-files -- 'scripts' '.githooks' '.claude/hooks' 2>/dev/null | wc -l | tr -d ' '
}

# AC3 threshold decision (n=10 direct measurement, this repo's current scale,
# real shared-worktree contention): a single non-lib code file staged →
# median 1844ms / max 3262ms added latency, dominated by test_select.sh's
# fixed-cost mapping construction, not by anything this task added. Budget:
# median <=2000ms / max <=5000ms for that common code-touching case (measured
# max sits ~35% under budget). Non-code commits (queue/*.yaml, projects/*.yaml,
# logs/*, the majority of traffic in this repo) are filtered to ~0ms below via
# staged_file_could_have_tests(). A widely-shared scripts/lib/ change (e.g.
# yaml_field_set.sh, 29 real callers) is the deliberate exception: selection
# alone measured 6.8s there, and narrowing it away would defeat AC2's whole
# purpose — that IS the incident class AC2 exists to catch, so it is accepted
# out-of-budget rather than narrowed. Exceeding the common-case budget in
# production (visible via logs/defense_overhead.jsonl check_id=affected_tests)
# is the trigger to narrow staged_file_could_have_tests() further, not to make
# this async (殿裁定「削るな速くしろ」).
staged_file_could_have_tests() {
    local file="${1:-}"
    case "$file" in
        *.sh|*.py) return 0 ;;
        .githooks/*|.claude/hooks/*) return 0 ;;
        context/*.md|docs/rule/*.md|docs/research/*.md) return 0 ;;
        instructions/gunshi.md) return 0 ;;
        tests/unit/test_*.bats) return 0 ;;
        *) return 1 ;;
    esac
}

# AC1 (cmd_4182): "文書系パス" definition — non-executable, non-test asset
# directories where a change cannot regress runtime behavior. This is a
# stricter, override-taking-priority set than staged_file_could_have_tests():
# context/*.md, docs/rule/*.md and docs/research/*.md are deliberately
# "could have tests" above (they route to focused freshness/index gate
# tests), but those gate tests are large fixture suites (test_context_
# freshness_check.bats=57 cases, test_semantic_index_update.bats=43 cases),
# not tests of the edited doc's content. A single-line docs/research/*.md
# annotation commit (将軍, 2026-07-27) measured 41.2s here and, worse, still
# had to queue for the host-wide heavy_job_admission.sh semaphore behind it
# — 11m12s total holding the shared ninja-scope-commit lock and failing
# hayate's cmd_4181 commit twice on its 120s timeout (blt_20260727_201344,
# PID 3923473). *.sh/*.py are excluded even under these directories as a
# defense-in-depth guard against a future executable file landing there.
is_doc_only_fastpath_path() {
    local file="${1:-}"
    case "$file" in
        *.sh|*.py) return 1 ;;
        docs/*|context/*|memory/*|archive/*) return 0 ;;
        *) return 1 ;;
    esac
}

# AC1: true only when every staged file matches the doc-only fast-path set
# above. A single non-matching file (script, test, or any other path) falls
# through to the normal affected_tests resolution below — this is what keeps
# AC2's mixed-diff and code-only negative controls on the unchanged path.
all_staged_files_are_doc_only_fastpath() {
    local staged saw_any=false
    while IFS= read -r staged; do
        [[ -n "$staged" ]] || continue
        saw_any=true
        is_doc_only_fastpath_path "$staged" || return 1
    done < <(list_staged_files)
    [[ "$saw_any" == "true" ]]
}

# ninja_scope_commit carries the reviewed task contract in this variable.
# Unset means an ordinary manual commit; set-but-invalid must fail closed.
resolve_precommit_task_file() {
    local configured="${NINJA_SCOPE_TASK_FILE:-}" resolved
    [[ -n "$configured" ]] || return 1
    resolved="$(realpath -e -- "$configured" 2>/dev/null)" || {
        echo "[pre-commit] BLOCK(GA-PRECOMMIT1): NINJA_SCOPE_TASK_FILE does not exist: $configured" >&2
        return 2
    }
    case "$resolved" in
        "$REPO_ROOT"/queue/tasks/*.yaml) ;;
        *)
            echo "[pre-commit] BLOCK(GA-PRECOMMIT1): NINJA_SCOPE_TASK_FILE must resolve inside $REPO_ROOT/queue/tasks: $configured" >&2
            return 2
            ;;
    esac
    printf '%s\n' "$resolved"
}

# Phase1 commit reservation contract: pre-commit tests are bounded and marked
# explicitly so run_tests can remove the recursive scoped-commit contract test.
# A timeout is a hard failure, with a durable local evidence path for diagnosis.
run_precommit_tests_bounded() {
    local run_tests="$1" mode="$2"; shift 2
    # 60→180秒に引き上げ(2026-08-09 殿指示: テスト高速化が根治だがD0でタイムアウト緩和も併用)
    # test_heavy_job_admission.bats単体で61秒(実測)のため60秒では常にタイムアウト
    local timeout_seconds="${PRECOMMIT_TEST_TIMEOUT_SECONDS:-180}"
    local agent timestamp evidence timeout_marker rc
    [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] || {
        echo "BLOCK: PRECOMMIT_TEST_TIMEOUT_SECONDS must be a positive integer" >&2
        return 2
    }
    agent="${TMUX_AGENT_ID:-${AGENT_ID:-${USER:-unknown}}}"
    agent="${agent//[^[:alnum:]_.-]/_}"
    timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
    evidence="/tmp/precommit_timeout_${agent}_${timestamp}.log"
    set +e
    env -u GIT_INDEX_FILE -u GIT_DIR -u GIT_WORK_TREE -u GIT_OBJECT_DIRECTORY -u GIT_COMMON_DIR \
        PRECOMMIT=1 timeout --signal=TERM --kill-after=5 "$timeout_seconds" \
        bash "$run_tests" "$mode" "$@" >"$evidence" 2>&1
    rc=$?
    set -e
    cat "$evidence" >&2
    if [[ "$rc" -eq 124 || "$rc" -eq 137 ]]; then
        timeout_marker="PRECOMMIT_TIMEOUT result=FAIL timeout_seconds=$timeout_seconds evidence=$evidence"
        printf '%s\n' "$timeout_marker" >>"$evidence"
        printf '%s\n' "$timeout_marker" >&2
        echo "BLOCK: pre-commit test timeout; evidence=$evidence" >&2
        return "$rc"
    fi
    rm -f -- "$evidence"
    return "$rc"
}

# AC1: resolve staged paths (plus AC2's reverse-dependency expansion) to
# affected tests and run them, reusing scripts/run_tests.sh's existing
# `affected` mode (which itself delegates to scripts/test_select.sh) instead
# of reimplementing selection here. AC4: PRECOMMIT_TIMEOUT_OVERRIDE
# (renamed from SHOGUN_PRECOMMIT_AFFECTED_BYPASS 2026-08-09 殿指示: 目的明示名へ変更)
# mirrors the escape-hatch pattern established for SHOGUN_PUSH_DIRTY_TREE_BYPASS
# (cmd_karo_impl_commander_scope_commit_20260725) — logged, not silent.
# 使用条件: (1) rc≠0がタイムアウト起因 (2) 対象テストを個別実行でPASS確認済み (3) 理由をjsonlに記録
check_precommit_affected_tests() {
    local -a target_files=() reverse_deps=()
    local staged reverse scope_count has_relevant=false task_file task_rc
    local run_tests="$REPO_ROOT/scripts/run_tests.sh"
    [[ -f "$run_tests" ]] || return 0

    task_file="$(resolve_precommit_task_file)"
    task_rc=$?
    if [[ "$task_rc" -eq 0 ]]; then
        echo "[pre-commit] affected-test mode=task task_file=${task_file#"$REPO_ROOT"/}" >&2
        if precommit_receipt_matches "$task_file"; then
            echo "[pre-commit] affected-test exact PASS receipt reused; test process launches=0" >&2
            return 0
        fi
        if ! run_precommit_tests_bounded "$run_tests" task "$task_file"; then
            echo "[pre-commit] BLOCK(GA-PRECOMMIT1): task-contract tests failed." >&2
            return 1
        fi
        precommit_publish_receipt_identity "$task_file"
        return 0
    elif [[ "$task_rc" -ne 1 ]]; then
        return 1
    fi

    # AC1 doc-only fast-path: skip affected_tests AND heavy_job_admission
    # (the latter fires only from inside run_tests.sh below, so simply never
    # invoking run_tests.sh here structurally skips both stages at once).
    # All other guard steps in main() (yaml_ast, shell_syntax, sourced_dep,
    # context_metadata, codd_context_freshness, semantic, etc.) still run
    # unconditionally around this function and are unaffected.
    if all_staged_files_are_doc_only_fastpath; then
        echo "[pre-commit] AC1(cmd_4182) doc-only fast-path: staged diff is entirely docs/context/memory/archive — affected_tests and heavy_job_admission skipped" >&2
        defense_overhead_write_async git_pre_commit affected_tests_docs_fastpath 0 PASS "${_PRECOMMIT_COMMAND_ID}-affected_tests_docs_fastpath" || true
        return 0
    fi

    while IFS= read -r staged; do
        [[ -n "$staged" ]] || continue
        target_files+=("$staged")
        staged_file_could_have_tests "$staged" && has_relevant=true
    done < <(list_staged_files)
    [[ "$has_relevant" == "true" ]] || return 0
    ((${#target_files[@]} > 0)) || return 0

    while IFS= read -r reverse; do
        [[ -n "$reverse" ]] || continue
        reverse_deps+=("$reverse")
    done < <(resolve_reverse_lib_deps)

    if ((${#reverse_deps[@]} > 0)); then
        scope_count="$(reverse_lib_dep_scan_scope)"
        echo "[pre-commit] AC2 reverse-dep scan: scope=${scope_count} tracked scripts/.githooks/.claude-hooks files, caller_matches=${#reverse_deps[@]}" >&2
        target_files+=("${reverse_deps[@]}")
    fi

    # Accept both new (PRECOMMIT_TIMEOUT_OVERRIDE) and legacy name for backward compat
    local _override_reason="${PRECOMMIT_TIMEOUT_OVERRIDE:-${SHOGUN_PRECOMMIT_AFFECTED_BYPASS:-}}"
    if [[ -n "$_override_reason" ]]; then
        mkdir -p "$REPO_ROOT/logs"
        PRECOMMIT_TIMEOUT_OVERRIDE="$_override_reason" \
        TMUX_AGENT_ID="${TMUX_AGENT_ID:-}" \
        python3 - "$REPO_ROOT/logs/precommit_affected_bypass.jsonl" <<'PY' 2>/dev/null || true
import json, os, sys, datetime
path = sys.argv[1]
entry = {
    "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "reason": os.environ.get("PRECOMMIT_TIMEOUT_OVERRIDE", ""),
    "agent": os.environ.get("TMUX_AGENT_ID") or "unknown",
    }
with open(path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
PY
        echo "[pre-commit] WARN(GA-PRECOMMIT1): affected-test timeout override used (PRECOMMIT_TIMEOUT_OVERRIDE). Logged to logs/precommit_affected_bypass.jsonl" >&2
        return 0
    fi

    # ninja_scope_commit.sh exports GIT_INDEX_FILE (and callers may export
    # GIT_DIR/GIT_WORK_TREE) around its private-index commit-tree flow, which
    # invokes this hook. Matched bats fixtures that build their own isolated
    # `git init` repo under $BATS_TEST_TMPDIR inherit that leaked context and
    # corrupt their tree ("invalid object ... for <unrelated staged path>")
    # when this hook actually runs them for the first time (discovered live:
    # this exact commit's own affected-test run broke on it). Strip the git
    # plumbing env for the child process so nested test repos resolve purely
    # from their own `-C <path>`, not from this commit's private index.
    echo "[pre-commit] affected-test mode=affected files_selected=${#target_files[@]}" >&2
    if ! run_precommit_tests_bounded "$run_tests" affected "${target_files[@]}"; then
        echo "BLOCK(GA-PRECOMMIT1): staged changes broke an affected test (directly, or via a scripts/lib/ reverse dependency)." >&2
        echo "  action: fix the failing test and re-commit." >&2
        echo "  emergency: PRECOMMIT_TIMEOUT_OVERRIDE='<reason>' git commit ... (logged to logs/precommit_affected_bypass.jsonl)" >&2
        return 1
    fi
    return 0
}

is_semantic_propagation_file() {
    local file="${1:-}"
    [[ -n "$file" ]] || return 1
    case "$file" in
        context/*) return 0 ;;
        # In a case pattern, `*` also spans `/`; these two patterns cover both
        # top-level and nested project YAML without unreachable alternatives.
        projects/*.yaml|projects/*.yml) return 0 ;;
        *) return 1 ;;
    esac
}

collect_semantic_propagation_files() {
    local file
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        if is_semantic_propagation_file "$file"; then
            printf '%s\n' "$file"
        fi
    done < <(list_staged_files)
}

build_semantic_propagation_payload() {
    python3 - "$@" <<'PY'
import json
import sys
from datetime import datetime, timezone

files = [item for item in sys.argv[1:] if item]
payload = {
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "summary": "git pre-commit semantic propagation for context/projects changes",
    "files": files,
}
print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
PY
}

run_semantic_propagation_for_staged_files() {
    local files payload update_cmd map_cmd log_path
    files="$(collect_semantic_propagation_files)"
    [[ -n "$files" ]] || return 0

    update_cmd="$REPO_ROOT/scripts/semantic_index_update.sh"
    map_cmd="$REPO_ROOT/scripts/semantic_map_generate.sh"
    [[ -f "$update_cmd" || -f "$map_cmd" ]] || return 0

    # Keep commit latency low in normal use; tests can force sync with SEMANTIC_HOOK_SYNC=1.
    mapfile -t _semantic_files <<< "$files"
    payload="$(build_semantic_propagation_payload "${_semantic_files[@]}")"
    log_path="${SEMANTIC_HOOK_LOG:-$REPO_ROOT/logs/semantic_hook.log}"

    if [[ "${SEMANTIC_HOOK_SYNC:-0}" == "1" ]]; then
        [[ -f "$update_cmd" ]] && bash "$update_cmd" discussion "$payload"
        [[ -f "$map_cmd" ]] && bash "$map_cmd"
        return 0
    fi

    (
        mkdir -p "$(dirname "$log_path")"
        {
            [[ -f "$update_cmd" ]] && bash "$update_cmd" discussion "$payload"
            [[ -f "$map_cmd" ]] && bash "$map_cmd"
        } >>"$log_path" 2>&1 || true
    ) &
}

is_codd_context_source_file() {
    local file="${1:-}"
    case "$file" in
        scripts/codd*|skills/codd/*|skills/codd-refactor/*) return 0 ;;
        *) return 1 ;;
    esac
}

is_codd_inspection_metadata_only_change() {
    local file="${1:-}" status line content saw_change=false
    status="${_STAGED_FILE_STATUS[$file]:-}"

    # A new/deleted/renamed source contract is substantive even if its current
    # text happens to contain only inspection comments.  Unknown status also
    # fails closed instead of silently weakening the freshness pair.
    [[ "$status" == M* ]] || return 1
    case "$file" in
        skills/codd/SKILL.md|skills/codd-refactor/SKILL.md) ;;
        *) return 1 ;;
    esac

    while IFS= read -r line; do
        case "$line" in
            '+++'*|'---'*|'@@'*) continue ;;
            '+'*|'-'*)
                saw_change=true
                content="${line:1}"
                if [[ "$content" =~ ^[[:space:]]*\<!--[[:space:]]*script_refs_checked_at:[[:space:]]*[^[:space:]].*--\>[[:space:]]*$ ]]; then
                    continue
                fi
                if [[ "$content" =~ ^[[:space:]]*\<!--[[:space:]]*.*(検分|Script[[:space:]]refs[[:space:]]verified:).*(契約|contract|本文|変更|差分|不変|維持).*(--\>)[[:space:]]*$ ]]; then
                    continue
                fi
                return 1
                ;;
        esac
    done < <(git diff --cached --no-ext-diff --unified=0 -- "$file" 2>/dev/null)
    [[ "$saw_change" == "true" ]]
}

check_codd_context_freshness_pair() {
    local file has_source=false
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        if is_codd_context_source_file "$file" && ! is_codd_inspection_metadata_only_change "$file"; then
            has_source=true
            break
        fi
    done < <(list_staged_files)
    [[ "$has_source" == "true" ]] || return 0
    if ! staged_file_exists context/codd.md; then
        echo "BLOCK(GA-288): CoDD source change requires staged context/codd.md freshness evidence" >&2
        echo "  action: inspect the source diff, update context/codd.md, and stage both in one commit" >&2
        return 1
    fi
}

context_freshness_excluded() {
    local wanted="${1:-}" line
    local exclude_file="$REPO_ROOT/config/context_freshness_excludes.txt"
    [[ -f "$exclude_file" ]] || return 1
    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -n "$line" ]] || continue
        [[ "$line" == "$wanted" || "$line" == "${wanted##*/}" ]] && return 0
    done < "$exclude_file"
    return 1
}

check_staged_context_last_updated() {
    local file header
    while IFS= read -r file; do
        [[ "$file" == context/*.md ]] || continue
        [[ "${_STAGED_FILE_STATUS[$file]:-}" != D* ]] || continue
        context_freshness_excluded "$file" && continue
        header="$(git show ":$file" 2>/dev/null | sed -n '1,5p')"
        if ! grep -qE '<!--[[:space:]]*last_updated:[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}\b' <<<"$header"; then
            echo "BLOCK(GA-318): $file lacks last_updated metadata in its first 5 lines" >&2
            echo "  action: add <!-- last_updated: YYYY-MM-DD cmd_id --> after verifying the document" >&2
            return 1
        fi
    done < <(list_staged_files)
}

infer_test_group_prefix() {
    local base="${1:-}"
    case "$base" in
        cmd_save*) echo "cmd_save" ;;
        cmd_complete_gate*) echo "cmd_complete_gate" ;;
        deploy_task*) echo "deploy_task" ;;
        gate_*) echo "gate" ;;
        inbox_watcher*) echo "inbox_watcher" ;;
        lesson_write*) echo "lesson_write" ;;
        *) echo "$base" ;;
    esac
}

collect_script_refs_from_staged_test() {
    local file="${1:-}"
    [[ -n "$file" ]] || return 0
    git show ":$file" 2>/dev/null | grep -oE '(scripts|lib)/[A-Za-z0-9_./-]+\.sh' | sort -u || true
}

find_existing_test_candidates() {
    local added_file="${1:-}" base="${2:-}" group="${3:-}" script_ref
    local candidate
    declare -A seen=()

    for candidate in \
        "$REPO_ROOT/tests/unit/test_${base}"*.bats \
        "$REPO_ROOT/tests/unit/test_${group}"*.bats; do
        [[ -f "$candidate" ]] || continue
        candidate="${candidate#"$REPO_ROOT"/}"
        [[ "$candidate" == "$added_file" ]] && continue
        seen["$candidate"]=1
    done

    while IFS= read -r script_ref; do
        [[ -n "$script_ref" ]] || continue
        while IFS= read -r candidate; do
            [[ -n "$candidate" ]] || continue
            [[ "$candidate" == "$added_file" ]] && continue
            seen["$candidate"]=1
        done < <(grep -RIlF "$script_ref" "$REPO_ROOT/tests/unit" --include='test_*.bats' 2>/dev/null | sed "s|^$REPO_ROOT/||")
    done < <(collect_script_refs_from_staged_test "$added_file")

    if ((${#seen[@]} > 0)); then
        printf '%s\n' "${!seen[@]}" | sort
    fi
}

has_added_matching_script() {
    local base="${1:-}" candidate added
    [[ -n "$base" ]] || return 1
    added="$(git diff --cached --diff-filter=A --name-only)"
    for candidate in \
        "scripts/${base}.sh" "scripts/${base}.py" \
        "scripts/lib/${base}.sh" "scripts/lib/${base}.py"; do
        if grep -Fxq "$candidate" <<< "$added"; then
            return 0
        fi
    done
    return 1
}

warn_test_file_granularity() {
    local added_file base group candidates
    local warned=false

    while IFS= read -r added_file; do
        [[ -n "$added_file" ]] || continue
        base="$(basename "$added_file" .bats)"
        base="${base#test_}"
        # A brand-new production script needs a dedicated same-name test file;
        # references to shared helpers inside that test are not duplication.
        has_added_matching_script "$base" && continue
        group="$(infer_test_group_prefix "$base")"
        candidates="$(find_existing_test_candidates "$added_file" "$base" "$group")"
        [[ -n "$candidates" ]] || continue

        if [[ "$warned" == "false" ]]; then
            echo "WARN: new test_*.bats file may duplicate existing script-level tests." >&2
            echo "Prefer adding cases to an existing test file or consolidated suite when the target script is the same." >&2
            warned=true
        fi
        echo "  added: $added_file" >&2
        echo "$candidates" | sed 's/^/    candidate: /' >&2
    done < <(list_added_test_files)
}

is_yaml_dump_scan_target() {
    local file="${1:-}"
    [[ -n "$file" ]] || return 1
    [[ "$file" == tests/* ]] && return 1
    [[ "$file" == *yaml-dump-guard* ]] && return 1
    [[ "$file" == *pre_bash_combined_guard* ]] && return 1
    [[ "$file" == scripts/hooks/* ]] && return 1
    [[ "$file" == skills/* ]] && return 1  # skills/のスクリプトはcli_profiles.yaml操作用。運用YAML非対象
    [[ "$file" == scripts/lib/yaml_atomic.py ]] && return 1  # GA-101: yaml.dump集中管理の正当な場所。除外対象
    [[ "$file" == *.sh || "$file" == *.py ]]
}

is_operational_yaml_commit_file() {
    local file="${1:-}"
    [[ -n "$file" ]] || return 1
    [[ "$file" == queue/*.yaml || "$file" == queue/**/*.yaml || "$file" == logs/*.yaml ]]
}

collect_task_yaml_mixed_commit_violations() {
    local has_task_yaml=false file violations=""

    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        if [[ "$file" == queue/tasks/*.yaml ]]; then
            has_task_yaml=true
            continue
        fi
        if ! is_operational_yaml_commit_file "$file"; then
            violations+=$(printf '  %s\n' "$file")
        fi
    done < <(list_staged_files)

    if [[ "$has_task_yaml" == "true" && -n "$violations" ]]; then
        printf '%s' "$violations"
    fi
}

collect_yaml_dump_violations() {
    # GA-250: inspect the staged blob with Python's AST, but report only dump
    # calls introduced by this commit.  A dump word alone is harmless (for
    # example StringIO/stdout projection); the dangerous condition is a data
    # flow into an operational YAML path through a write-capable sink.
    python3 - "$REPO_ROOT" <<'PY'
import ast
import re
import subprocess
import sys

root = sys.argv[1]

def git(*args):
    return subprocess.run(
        ["git", "-C", root, *args], text=True, check=False,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    ).stdout

def scan_target(path):
    return (
        path.endswith((".py", ".sh"))
        and not path.startswith(("tests/", "scripts/hooks/", "skills/"))
        and "yaml-dump-guard" not in path
        and "pre_bash_combined_guard" not in path
        and path != "scripts/lib/yaml_atomic.py"
    )

def added_lines(path):
    out = set()
    diff = git("diff", "--cached", "--unified=0", "--no-color", "--", path)
    for line in diff.splitlines():
        match = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", line)
        if match:
            start, count = int(match.group(1)), int(match.group(2) or 1)
            out.update(range(start, start + count))
    return out

def call_name(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        base = call_name(node.value)
        return f"{base}.{node.attr}" if base else node.attr
    return ""

def literal(node, values):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        return values.get(node.id)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left, right = literal(node.left, values), literal(node.right, values)
        return left + right if left is not None and right is not None else None
    return None

def operational(path):
    if not path:
        return False
    path = path.replace("\\", "/").lstrip("./")
    return bool(re.match(r"^(queue(?:/|$)|logs/[^/]+\.ya?ml$)", path)) and path.endswith((".yaml", ".yml"))

def mode_writes(node, values, default="r"):
    mode = literal(node, values) if node is not None else default
    return bool(mode and any(flag in mode for flag in "wax+"))

def analyse(path, source, introduced):
    try:
        tree = ast.parse(source, filename=path)
    except SyntaxError:
        return []
    values, path_vars, sink_vars = {}, {}, {}
    findings = []

    def resolve_path(expr):
        value = literal(expr, values)
        if value is not None:
            return value
        if isinstance(expr, ast.Name):
            return path_vars.get(expr.id)
        if isinstance(expr, ast.Call) and call_name(expr.func) in ("Path", "pathlib.Path") and expr.args:
            return resolve_path(expr.args[0])
        return None

    def sink(expr):
        if isinstance(expr, ast.Name):
            return sink_vars.get(expr.id)
        if not isinstance(expr, ast.Call):
            return None
        name = call_name(expr.func)
        if name in ("open", "io.open") and expr.args:
            mode = expr.args[1] if len(expr.args) > 1 else next((k.value for k in expr.keywords if k.arg == "mode"), None)
            path_value = resolve_path(expr.args[0])
            return path_value if operational(path_value) and mode_writes(mode, values) else None
        if isinstance(expr.func, ast.Attribute) and expr.func.attr == "open":
            mode = expr.args[0] if expr.args else next((k.value for k in expr.keywords if k.arg == "mode"), None)
            path_value = resolve_path(expr.func.value)
            return path_value if operational(path_value) and mode_writes(mode, values) else None
        return None

    # Iterate to a fixed point because ast.walk() does not promise source
    # order, and a handle may depend on a path variable discovered later.
    bindings = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            bindings.extend((target, node.value) for target in targets)
        elif isinstance(node, (ast.With, ast.AsyncWith)):
            bindings.extend((item.optional_vars, item.context_expr) for item in node.items if item.optional_vars)
    for _ in range(len(bindings) + 1):
        changed = False
        for target, value in bindings:
            if not isinstance(target, ast.Name):
                continue
            before = (values.get(target.id), path_vars.get(target.id), sink_vars.get(target.id))
            text = literal(value, values)
            if text is not None:
                values[target.id] = text
            resolved = resolve_path(value)
            if resolved is not None:
                path_vars[target.id] = resolved
            resolved_sink = sink(value)
            if resolved_sink:
                sink_vars[target.id] = resolved_sink
            after = (values.get(target.id), path_vars.get(target.id), sink_vars.get(target.id))
            changed |= before != after
        if not changed:
            break

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or node.lineno not in introduced:
            continue
        name = call_name(node.func)
        if name in ("yaml.dump", "yaml.safe_dump", "yaml.dump_all"):
            stream = node.args[1] if len(node.args) > 1 else next((k.value for k in node.keywords if k.arg in ("stream", "file")), None)
            target = sink(stream) if stream is not None else None
            if target:
                snippet = ast.get_source_segment(source, node) or name
                findings.append((node.lineno, target, f"{name} -> write-capable sink; source={snippet}"))
        elif isinstance(node.func, ast.Attribute) and node.func.attr == "write_text":
            target = resolve_path(node.func.value)
            if not operational(target):
                continue
            for arg in node.args:
                if isinstance(arg, ast.Call) and call_name(arg.func) in ("yaml.dump", "yaml.safe_dump", "yaml.dump_all"):
                    snippet = ast.get_source_segment(source, node) or call_name(arg.func)
                    findings.append((node.lineno, target, f"{call_name(arg.func)} -> Path.write_text; source={snippet}"))
    return findings

for path in git("diff", "--cached", "--name-only", "--diff-filter=ACMR").splitlines():
    if not scan_target(path):
        continue
    source = git("show", f":{path}")
    for lineno, target, reason in analyse(path, source, added_lines(path)):
        source_part = reason.partition("; source=")[2]
        reason_part = reason.partition("; source=")[0]
        print(f"  {path}:{lineno}: source={source_part} target={target} reason={reason_part}")
PY
}

run_yaml_dump_closure_gate() {
    # Preserve gate_no_direct_yaml_dump.sh's full scripts/**/*.sh closure, but
    # avoid opening every shell file through pathlib on WSL's /mnt/c mount.
    # ripgrep walks the same working-tree population (tracked and untracked)
    # in one process; Python only applies the gate's exact line exclusions to
    # the small candidate set.  Scanner errors remain fail-closed.
    python3 - "$REPO_ROOT" <<'PY'
import re
import subprocess
import sys

root = sys.argv[1]
pattern = r"(yaml[a-zA-Z_]*|[a-zA-Z_]*yaml[a-zA-Z_]*)\.(safe_)?dump\("
scan = subprocess.run(
    [
        "rg", "-n", "--no-heading", "--color=never", "--glob", "*.sh",
        pattern, f"{root}/scripts",
    ],
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if scan.returncode not in (0, 1):
    print(
        f"BLOCK: YAML dump closure scanner failed (rc={scan.returncode}): "
        f"{scan.stderr.strip()}",
        file=sys.stderr,
    )
    raise SystemExit(1)

violations = []
for hit in scan.stdout.splitlines():
    path, lineno, line = hit.split(":", 2)
    rel = path.removeprefix(root + "/")
    if rel == "scripts/gates/gate_no_direct_yaml_dump.sh":
        continue
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        continue
    if any(token in stripped for token in ("grep", "rg ", "BLOCK", "detected")):
        continue
    violations.append(f"{rel}:{lineno}: {stripped}")

if violations:
    print(
        "BLOCK: direct yaml.dump/yaml.safe_dump in shell-controlled scripts",
        file=sys.stderr,
    )
    print(
        "Use scripts.lib.yaml_atomic.atomic_yaml_write or yaml_text.",
        file=sys.stderr,
    )
    print(*violations, sep="\n", file=sys.stderr)
    raise SystemExit(1)

print("OK: direct yaml.dump/yaml.safe_dump active hits = 0")
PY
}

main() {
    local _yaml_dump_violations="" _task_yaml_mixed_violations="" _instructions_changed=false _has_yaml_dump_scan_target=false
    local _staged_file

    # Populate the cache in the parent shell.  The consumers below mostly run
    # through process substitutions; loading lazily there would repeat the
    # same `git diff --cached` once per subshell instead of inheriting one
    # immutable snapshot of the commit index.
    precommit_step_begin staged_snapshot
    load_staged_file_cache
    precommit_step_end 0

    precommit_step_begin test_granularity
    warn_test_file_granularity
    precommit_step_end 0

    precommit_step_begin task_scope
    _task_yaml_mixed_violations="$(collect_task_yaml_mixed_commit_violations)"

    if [[ -n "$_task_yaml_mixed_violations" ]]; then
        precommit_step_end 1
        echo "BLOCKED: queue/tasks/*.yaml cannot be committed with implementation files (GA-408)" >&2
        echo "Commit task/status YAML separately from scripts/lib/context/docs/tests changes." >&2
        echo "$_task_yaml_mixed_violations" >&2
        exit 1
    fi
    precommit_step_end 0

    while IFS= read -r _staged_file; do
        [[ -n "$_staged_file" ]] || continue
        if is_yaml_dump_scan_target "$_staged_file"; then
            _has_yaml_dump_scan_target=true
        fi
        if [[ "$_staged_file" == instructions/*.md && "$_staged_file" != instructions/generated/* ]]; then
            _instructions_changed=true
        fi
    done < <(list_staged_files)

    precommit_step_begin yaml_ast
    if [[ "$_has_yaml_dump_scan_target" == "true" ]]; then
        _yaml_dump_violations="$(collect_yaml_dump_violations)"

        if [[ -n "$_yaml_dump_violations" ]]; then
            precommit_step_end 1
            echo "BLOCKED: yaml.dump/yaml.safe_dump detected in staged files (GP-136)" >&2
            echo "Data loss risk on operational YAML. Use yaml_field_set.sh instead." >&2
            echo "$_yaml_dump_violations" >&2
            exit 1
        fi
        # The global closure gate scans every scripts/*.sh file.  Running it
        # when this commit has no eligible .sh/.py target added ~1.2-3.0s to
        # every commit while it could not change the verdict.  Preserve the
        # full-tree backstop for relevant staged code, but make the proven
        # affected=0 branch an immediate no-op.
        if ! run_yaml_dump_closure_gate >&2; then
            precommit_step_end 1
            exit 1
        fi
    fi
    precommit_step_end 0

    # shell_syntax: staged .sh must parse (bash -n on STAGED content).
    # 2026-07-20: commit 6845c0041 shipped an if-less block into ninja_monitor.sh,
    # killing the monitor for 47min. Syntax-broken shell must never reach the tree.
    precommit_step_begin shell_syntax
    _shell_syntax_fail=""
    _task_file="$(resolve_precommit_task_file 2>/dev/null || true)"
    if [[ -n "$_task_file" ]] && precommit_receipt_matches "$_task_file"; then
        echo "[pre-commit] shell_syntax exact staged-blob PASS receipt reused; bash processes=0" >&2
    else
        while IFS= read -r _staged_sh; do
            [[ -n "$_staged_sh" ]] && _shell_syntax_fail+="    $_staged_sh"$'\n'
        done < <(check_staged_shell_syntax)
    fi
    if [[ -n "$_shell_syntax_fail" ]]; then
        precommit_step_end 1
        echo "BLOCKED: bash -n failed on staged shell script(s):" >&2
        printf '%s' "$_shell_syntax_fail" >&2
        exit 1
    fi
    precommit_step_end 0

    # sourced_dep: a staged script may not `source` a repo file that this commit
    # neither tracks nor stages.  2026-07-25: 239d663ff added
    # `source .../scripts/lib/gate_report_format_classify.sh` to cmd_complete_gate.sh
    # while the lib itself stayed untracked.  It worked on every machine that had
    # the file on disk and broke every fresh checkout and CI run — the completion
    # GATE aborted at source time.  Only paths that exist in the working tree are
    # inspected, so dynamic or genuinely external sources cannot false-positive.
    precommit_step_begin sourced_dep
    if ! check_staged_sourced_deps; then
        precommit_step_end 1
        exit 1
    fi
    precommit_step_end 0

    # Intermediate commit lane must stay below three seconds. Runtime/task/
    # affected tests belong to the final checkpoint, never to commit creation.
    # Scope isolation, syntax and secret guards remain active above.
    echo "[pre-commit] runtime tests deferred to final checkpoint; launches=0" >&2

    precommit_step_begin instruction_sync
    if [[ "$_instructions_changed" == "true" ]]; then
        echo "instructions/*.md staged — checking generated/ sync..."
        _build_instructions_output=""
        if ! _build_instructions_output="$(bash "$REPO_ROOT/scripts/build_instructions.sh" 2>&1)"; then
            precommit_step_end 1
            echo "BLOCKED: build_instructions.sh failed" >&2
            exit 1
        fi
        if [[ "$_build_instructions_output" =~ BUILD_INSTRUCTIONS_SUMMARY\ rebuilt=([0-9]+)\ skipped=([0-9]+) ]]; then
            _PRECOMMIT_INSTRUCTION_SYNC_REBUILT="${BASH_REMATCH[1]}"
            _PRECOMMIT_INSTRUCTION_SYNC_SKIPPED="${BASH_REMATCH[2]}"
        fi
        unset _build_instructions_output
        if ! git diff --exit-code instructions/generated/ > /dev/null 2>&1; then
            echo "AUTO-FIX: generated instructions were out of sync — re-synced and staged automatically (GA-190)." >&2
            git add instructions/generated/
            git diff --cached --name-only -- instructions/generated/ | sed 's/^/    staged: /' >&2
        else
            echo "  OK: generated instructions in sync."
        fi
    fi
    precommit_step_end 0

    precommit_step_begin context_metadata
    if ! check_staged_context_last_updated; then
        precommit_step_end 1
        exit 1
    fi
    precommit_step_end 0

    precommit_step_begin codd_context_freshness
    if ! check_codd_context_freshness_pair; then
        precommit_step_end 1
        exit 1
    fi
    precommit_step_end 0

    precommit_step_begin tobe_no_line_numbers
    check_tobe_no_line_numbers
    precommit_step_end 0

    precommit_step_begin doc_no_changelog
    if ! check_doc_no_changelog; then
        precommit_step_end 1
        exit 1
    fi
    precommit_step_end 0

    precommit_step_begin semantic
    run_semantic_propagation_for_staged_files
    precommit_step_end "$?"
}


# ToBe節に現実の行番号(:NNN)/ファイル名.py:が混入したらWARN(BLOCKしない)。
# 原則(殿裁定2026-08-15): ToBeは現実の関数名・行番号・実測値で理想を縛らない。
# 発端: v3.1/v3.2でToBe図へ実装の行番号を持ち込み殿16:01/16:06指摘。
check_tobe_no_line_numbers() {
    local f hits
    while IFS= read -r f; do
        [[ "$f" == docs/research/*.md ]] || continue
        hits=$(git show ":$f" 2>/dev/null | awk '
            /^## /{intobe = ($0 ~ /ToBe/) ? 1 : 0}
            intobe && (/:[0-9][0-9][0-9]+/ || /\.py:/) {print NR": "$0}' | head -5)
        if [[ -n "$hits" ]]; then
            echo "  WARN(tobe_no_line_numbers): $f のToBe節に実装の行番号/ファイル参照が混入。ToBeは理想。AsIs側へ移すか削れ:" >&2
            echo "$hits" | cut -c1-160 | sed 's/^/    /' >&2
        fi
    done < <(git diff --cached --name-only --diff-filter=AM)
    return 0
}

# 設計書(docs/research/*.md)へ変更履歴を書き込んだらBLOCK。
# 殿指示2026-08-15 16:33「変更点を文書で書く必要はない。粒度が足りなければ一番下にAsIs注釈/ToBe注釈をレイヤー単位で書け」
# 発端: 同日16:33以降も将軍が見出しへ「（v3.x=…殿指示hh:mm ← v3.y=…）」を書き続け17:00に殿再指摘。指示違反=バグ→構造で根治。
# 検出: 明示的な履歴語(変更履歴/変更点)、版遷移、殿指示/殿指摘、または
# 行頭「変更:」「変更履歴」。一般設計語(変更内容/変更境界/変更なし等)は許可。
check_doc_no_changelog() {
    local f hits rc=0
    while IFS= read -r f; do
        [[ "$f" == docs/research/*.md ]] || continue
        hits=$(git show ":$f" 2>/dev/null | awk '
            /^#{2,3} / && (/変更履歴/ || /変更点/ || /←/ || /→ *v[0-9]/ || /殿指示/ || /殿指摘/ || /変更内容.*(commit|cmd_[0-9]+|20[0-9][0-9]-[0-9][0-9]-[0-9][0-9])/) {print NR": "$0; next}
            /^変更[:：]/ || /^変更履歴/ || /^#{2,3} .*変更履歴/ {print NR": "$0}' | head -5)
        if [[ -n "$hits" ]]; then
            echo "  BLOCK(doc_no_changelog): $f に変更履歴の記述。変更点は文書に書かない(殿指示2026-08-15 16:33)。" >&2
            echo "$hits" | cut -c1-160 | sed 's/^/    /' >&2
            echo "    修正文: 該当行を削除し、見出しは「## vX.Y (YYYY-MM-DD)」のような版番号+タイムスタンプだけにする。説明は文末のAsIs/ToBe注釈へ移す。" >&2
            rc=1
        fi
    done < <(git diff --cached --name-only --diff-filter=AM)
    return $rc
}

# Keep the failure detail bounded without cutting through a UTF-8 codepoint.
# `head -c` counts bytes and can leave an incomplete multibyte sequence in the
# YAML log.  Decode the bounded byte prefix with invalid tails/bytes ignored;
# the emitted text is therefore always valid UTF-8 and never exceeds the byte
# cap before YAML indentation is added.
_bounded_utf8_summary() {
    local source_file="$1"
    local byte_cap="${2:-200}"
    python3 - "$source_file" "$byte_cap" <<'PY'
from pathlib import Path
import sys

source, cap_text = sys.argv[1:]
cap = int(cap_text)
bounded = Path(source).read_bytes()[:cap]
summary = bounded.decode("utf-8", errors="ignore").replace("\n", " ")
sys.stdout.buffer.write(summary.encode("utf-8"))
PY
}

# --- Failure recording trap (cmd_1117) ---
# shellcheck disable=SC2317  # Called indirectly via trap EXIT below
_record_hook_failure() {
    local exit_code=$1
    if [ "$exit_code" -ne 0 ]; then
        (
            ninja_name=$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || echo "unknown")
            stderr_summary=""
            [ -s "$_STDERR_FILE" ] && stderr_summary=$(_bounded_utf8_summary "$_STDERR_FILE" 200)
            printf -v _hook_failure_ts '%(%Y-%m-%dT%H:%M:%S%z)T' -1
            if [[ "$_hook_failure_ts" =~ ^(.+)([+-][0-9]{2})([0-9]{2})$ ]]; then
                _hook_failure_ts="${BASH_REMATCH[1]}${BASH_REMATCH[2]}:${BASH_REMATCH[3]}"
            fi
            mkdir -p "$REPO_ROOT/logs"
            {
                echo "- timestamp: ${_hook_failure_ts}"
                echo "  hook: pre-commit"
                echo "  ninja: $ninja_name"
                echo "  exit_code: $exit_code"
                echo "  detail: |-"
                printf '    %s\n' "$stderr_summary"
            } >> "$REPO_ROOT/logs/hook_failures.yaml"
        ) || true
    fi
    rm -f "$_STDERR_FILE" 2>/dev/null
}
_ec=0
# shellcheck disable=SC2154  # _ec is assigned in the trap string before use
trap '_ec=$?; precommit_terminal_receipt "$_ec"; _record_hook_failure "$_ec"; exit "$_ec"' EXIT

# Capture stderr for failure recording while still showing on terminal
exec 2> >(tee "$_STDERR_FILE" >&2)

main
