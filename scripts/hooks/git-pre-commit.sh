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

# The tracked hook is the SSOT, while Git executes an untracked copy under
# .git/hooks.  ninja_scope_commit.sh syncs that copy explicitly, but direct
# `git commit` callers are also valid and previously left the live hook stale.
# A live hook therefore reconciles itself from the commit index (when this
# commit includes the SSOT) or HEAD, then re-execs the atomically replaced copy.
if [[ "${GIT_PRE_COMMIT_SELF_SYNCED:-0}" != "1" && -f "$REPO_ROOT/scripts/sync_git_hooks.sh" ]]; then
    _installed_hook="$(git -C "$REPO_ROOT" rev-parse --git-path hooks/pre-commit 2>/dev/null || true)"
    [[ "$_installed_hook" = /* ]] || _installed_hook="$REPO_ROOT/$_installed_hook"
    _running_hook="${BASH_SOURCE[0]:-$0}"
    [[ "$_running_hook" = /* ]] || _running_hook="$PWD/$_running_hook"
    if [[ -e "$_installed_hook" && "$_running_hook" -ef "$_installed_hook" ]]; then
        _hook_hash_before="$(sha256sum "$_installed_hook" | awk '{print $1}')"
        _sync_args=()
        if git -C "$REPO_ROOT" diff --cached --name-only --diff-filter=ACMR -- \
            scripts/hooks/git-pre-commit.sh | grep -Fxq scripts/hooks/git-pre-commit.sh; then
            _sync_args+=(--scope-path scripts/hooks/git-pre-commit.sh)
        fi
        bash "$REPO_ROOT/scripts/sync_git_hooks.sh" "${_sync_args[@]}" || {
            echo "BLOCK(GA-222): live pre-commit hook self-sync failed" >&2
            exit 1
        }
        _hook_hash_after="$(sha256sum "$_installed_hook" | awk '{print $1}')"
        if [[ "$_hook_hash_before" != "$_hook_hash_after" ]]; then
            exec env GIT_PRE_COMMIT_SELF_SYNCED=1 "$_installed_hook" "$@"
        fi
        unset _installed_hook _running_hook _hook_hash_before _hook_hash_after _sync_args
    fi
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
