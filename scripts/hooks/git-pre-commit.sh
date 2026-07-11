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
_STDERR_FILE="/tmp/_hook_stderr_precommit_$$"
declare -a _STAGED_FILES=()
declare -a _ADDED_TEST_FILES=()
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
        if [[ "$status" == A* && "$path" == tests/unit/test_*.bats ]]; then
            _ADDED_TEST_FILES+=("$path")
        fi
    done < <(git diff --cached --name-status --diff-filter=ACMR 2>/dev/null)
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

warn_test_file_granularity() {
    local added_file base group candidates
    local warned=false

    while IFS= read -r added_file; do
        [[ -n "$added_file" ]] || continue
        base="$(basename "$added_file" .bats)"
        base="${base#test_}"
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
    local current_file="" current_matches="" violations="" line added_line

    flush_current_matches() {
        if [[ -n "$current_matches" ]] && [[ -n "$current_file" ]]; then
            violations+=$(printf '  %s: %s\n' "$current_file" "$(printf '%s' "$current_matches" | paste -sd ' ' -)")
        fi
        current_matches=""
    }

    while IFS= read -r line; do
        case "$line" in
            "+++ b/"*)
                flush_current_matches
                current_file="${line#+++ b/}"
                if ! is_yaml_dump_scan_target "$current_file"; then
                    current_file=""
                fi
                ;;
            "+"*)
                [[ "$line" == "+++"* ]] && continue
                [[ -n "$current_file" ]] || continue
                added_line="${line#+}"
                [[ "$added_line" =~ ^[[:space:]]*# ]] && continue
                if [[ "$added_line" == *"yaml.dump"* || "$added_line" == *"yaml.safe_dump"* ]]; then
                    current_matches+="${line}"$'\n'
                fi
                ;;
        esac
    done < <(git diff --cached --unified=0 --no-color --diff-filter=ACMR 2>/dev/null)

    flush_current_matches
    printf '%s' "$violations"
}

main() {
    local _yaml_dump_violations="" _task_yaml_mixed_violations="" _instructions_changed=false _has_yaml_dump_scan_target=false
    local _staged_file

    warn_test_file_granularity

    _task_yaml_mixed_violations="$(collect_task_yaml_mixed_commit_violations)"

    if [[ -n "$_task_yaml_mixed_violations" ]]; then
        echo "BLOCKED: queue/tasks/*.yaml cannot be committed with implementation files (GA-408)" >&2
        echo "Commit task/status YAML separately from scripts/lib/context/docs/tests changes." >&2
        echo "$_task_yaml_mixed_violations" >&2
        exit 1
    fi

    while IFS= read -r _staged_file; do
        [[ -n "$_staged_file" ]] || continue
        if is_yaml_dump_scan_target "$_staged_file"; then
            _has_yaml_dump_scan_target=true
        fi
        if [[ "$_staged_file" == instructions/*.md && "$_staged_file" != instructions/generated/* ]]; then
            _instructions_changed=true
        fi
    done < <(list_staged_files)

    if [[ "$_has_yaml_dump_scan_target" == "true" ]]; then
        _yaml_dump_violations="$(collect_yaml_dump_violations)"
    fi

    if [[ -n "$_yaml_dump_violations" ]]; then
        echo "BLOCKED: yaml.dump/yaml.safe_dump detected in staged files (GP-136)" >&2
        echo "Data loss risk on operational YAML. Use yaml_field_set.sh instead." >&2
        echo "$_yaml_dump_violations" >&2
        exit 1
    fi

    if [[ "$_instructions_changed" == "true" ]]; then
        echo "instructions/*.md staged — checking generated/ sync..."
        if ! bash "$REPO_ROOT/scripts/build_instructions.sh" > /dev/null 2>&1; then
            echo "BLOCKED: build_instructions.sh failed" >&2
            exit 1
        fi
        if ! git diff --exit-code instructions/generated/ > /dev/null 2>&1; then
            echo "AUTO-FIX: generated instructions were out of sync — re-synced and staged automatically (GA-190)." >&2
            git add instructions/generated/
            git diff --cached --name-only -- instructions/generated/ | sed 's/^/    staged: /' >&2
        else
            echo "  OK: generated instructions in sync."
        fi
    fi

    run_semantic_propagation_for_staged_files
}

# --- Failure recording trap (cmd_1117) ---
# shellcheck disable=SC2317  # Called indirectly via trap EXIT below
_record_hook_failure() {
    local exit_code=$1
    if [ "$exit_code" -ne 0 ]; then
        (
            ninja_name=$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || echo "unknown")
            stderr_summary=""
            [ -s "$_STDERR_FILE" ] && stderr_summary=$(head -c 200 "$_STDERR_FILE" 2>/dev/null | tr '\n' ' ')
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
trap '_ec=$?; _record_hook_failure "$_ec"; exit "$_ec"' EXIT

# Capture stderr for failure recording while still showing on terminal
exec 2> >(tee "$_STDERR_FILE" >&2)

main
