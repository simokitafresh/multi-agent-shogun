#!/usr/bin/env bash
# cmd_karo_hotfix_test_runner_drvfs_admission_20260723_normal
# run_tests.sh — テスト実行ラッパー（並列化自動適用）
# 誰が実行しても --jobs 8 が適用される。直接batsを呼ぶな。
# cmd_4105 周期時間実測(2026-07-24): unit=284s(144files) / affected(1file)=3.9s / direct-bats(1file)=0.8s
# 削減率: 全量→direct=99.7%(355x) / affected→direct=79.6%(4.9x) / mechanism-overhead=1.6s固定
#
# Usage:
#   bash scripts/run_tests.sh              # unit + top-level 全量
#   bash scripts/run_tests.sh unit         # unit のみ
#   bash scripts/run_tests.sh affected     # git diffから影響テストのみ
#   bash scripts/run_tests.sh task <task>  # task/reportの所有pathから影響テストのみ
#   bash scripts/run_tests.sh push         # test_necessity宣言済みCI境界のみ
#   bash scripts/run_tests.sh file <path>  # 特定ファイル
set -euo pipefail

# REPO_ROOT: テスト容易性のため既存環境変数があれば優先する(test_heavy_job_admission.bats
# がFAIL fixtureをtests/unit/相当のディレクトリに用意しexit code集約を検証する用途)。
# This file is intentionally sourceable so scheduler functions can be reused
# by regression harnesses.  In that mode $0 belongs to the caller (often
# `bash`), while BASH_SOURCE[0] remains this script's real path.
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
JOBS="${BATS_JOBS:-8}"
FILE_JOBS="${BATS_FILE_JOBS:-32}"
INNER_JOBS="${BATS_INNER_JOBS:-1}"
# A runner may split the suite into many bats roots, but the aggregate number
# of live tests must still honour the public --jobs 8 contract.  The previous
# default (128) let a 2-core CI runner launch 64 tests from one "heavy" file
# while other files were also live, producing timeout/cross-fixture cascades.
# File roots are process-heavy even when their inner bats jobs stay at one:
# each test commonly launches Python, git, tmux, or another shell.  Treating
# an N-core host as eight interchangeable roots oversubscribed GitHub runners
# and made internal timeout/daemon fixtures fail nondeterministically.  Keep
# eight as the public ceiling, but default the live-root budget to the host's
# reported CPU count.  BATS_MAX_TEST_JOBS remains an explicit override.
_detected_test_cpus="$(nproc 2>/dev/null || printf '1')"
[[ "$_detected_test_cpus" =~ ^[1-9][0-9]*$ ]] || _detected_test_cpus=1
if [ "$_detected_test_cpus" -gt 8 ]; then
    _detected_test_cpus=8
fi
MAX_TEST_JOBS="${BATS_MAX_TEST_JOBS:-$_detected_test_cpus}"
unset _detected_test_cpus
BATS_FILE_TIMEOUT_SECONDS="${BATS_FILE_TIMEOUT_SECONDS:-900}"
if [[ -v BATS_CACHE ]]; then
    BATS_CACHE_EXPLICIT=1
else
    BATS_CACHE_EXPLICIT=0
fi
BATS_CACHE="${BATS_CACHE:-1}"
BATS_CACHE_DIR="${BATS_CACHE_DIR:-$REPO_ROOT/.cache/bats}"

snapshot_test_tree() {
    local mode="$1" out="$2"
    case "$mode" in
        all) find "$REPO_ROOT/tests/unit" "$REPO_ROOT/tests" -maxdepth 1 -name '*.bats' -type f -print0 ;;
        unit) find "$REPO_ROOT/tests/unit" -maxdepth 1 -name '*.bats' -type f -print0 ;;
        *) return 1 ;;
    esac | sort -zu | xargs -0 sha256sum > "$out"
}

verify_test_tree_snapshot() {
    local snapshot="$1" expected actual file
    while read -r expected file; do
        [ -f "$file" ] || { echo "BLOCK: test snapshot path disappeared: $file" >&2; return 2; }
        actual="$(sha256sum "$file" | awk '{print $1}')"
        [ "$actual" = "$expected" ] || { echo "BLOCK: test snapshot changed during run: $file" >&2; return 2; }
    done < "$snapshot"
}

# run_embedded_test() (tests/unit/*_small_consolidated.bats) writes a throwaway
# nested-bats file as tests/unit/_tmp_<N>_<name>.<rand>.bats and removes it after
# the nested run finishes. If that nested run is killed (CI timeout/OOM/Ctrl-C)
# before cleanup, the file is orphaned. A bats-side trap can't fix this: EXIT
# traps set inside a @test are silently overridden by bats' own teardown trap,
# and RETURN traps leak into every later function return in the same process
# (both confirmed empirically, not just in bats docs). So orphans are swept here
# by age instead, on every mandated test run, rather than at creation time.
sweep_stale_embedded_test_tmp() {
    local ttl_minutes="${BATS_EMBEDDED_TMP_TTL_MINUTES:-15}"
    local dir="$REPO_ROOT/tests/unit"
    [ -d "$dir" ] || return 0
    find "$dir" -maxdepth 1 -type f -name '_tmp_*.bats' -mmin +"$ttl_minutes" -delete 2>/dev/null || true
}

# Resolve the files owned by one deployed task.  A shared worktree contains
# concurrent diffs from other ninjas, so global `git diff` is not task
# provenance.  target/files_to_modify/owned paths are available at assignment;
# the report's files_modified extends that set at the final checkpoint.
task_scope_paths() {
    local task_file="$1"
    local scope_root
    scope_root="$(task_scope_root "$task_file")" || return 1
    python3 - "$scope_root" "$task_file" "$REPO_ROOT" <<'PY'
import json
import os
import sys

import yaml

root = os.path.realpath(sys.argv[1])
task_path = os.path.realpath(sys.argv[2])
control_root = os.path.realpath(sys.argv[3])

def load(path):
    with open(path, encoding="utf-8") as handle:
        value = yaml.safe_load(handle) or {}
    if not isinstance(value, dict):
        raise ValueError(f"mapping required: {path}")
    return value

task_doc = load(task_path)
task = task_doc.get("task", task_doc)
if not isinstance(task, dict):
    raise ValueError("task mapping missing")

commit_contract = task.get("commit_contract")
external_roots = []
external_candidates = [
    task.get("task_worktree_repo"),
    commit_contract.get("repo_root") if isinstance(commit_contract, dict) else None,
]
for candidate in external_candidates:
    if isinstance(candidate, str) and candidate.strip():
        candidate_root = os.path.realpath(candidate)
        if candidate_root != root and candidate_root not in external_roots:
            external_roots.append(candidate_root)

values = []

def collect(value):
    if isinstance(value, str):
        if value.strip():
            values.append(value.strip())
    elif isinstance(value, dict):
        collect(value.get("path"))
    elif isinstance(value, list):
        for item in value:
            collect(item)

for key in ("target_path", "test_path", "files_to_modify", "files_modified", "owned_paths"):
    collect(task.get(key))

owned_json = task.get("owned_paths_json")
if isinstance(owned_json, str) and owned_json.strip():
    collect(json.loads(owned_json))
else:
    collect(owned_json)

top_planned = task.get("planned_paths")
nested_planned = commit_contract.get("planned_paths") if isinstance(commit_contract, dict) else None

def normalized_paths(value):
    raw_paths = []

    def gather(item):
        if isinstance(item, str):
            if item.strip():
                raw_paths.append(item.strip())
        elif isinstance(item, dict):
            gather(item.get("path"))
        elif isinstance(item, list):
            for child in item:
                gather(child)

    gather(value)
    normalized = set()
    for raw in raw_paths:
        path = raw if os.path.isabs(raw) else os.path.join(root, raw)
        resolved = os.path.realpath(path)
        if resolved != root and not resolved.startswith(root + os.sep):
            if any(
                resolved == candidate or resolved.startswith(candidate + os.sep)
                for candidate in external_roots
            ):
                print(f"WARN: external task scope path excluded: {raw}", file=sys.stderr)
                continue
            raise ValueError(f"scope path outside repository: {raw}")
        normalized.add(os.path.relpath(resolved, root))
    return normalized

top_paths = normalized_paths(top_planned)
nested_paths = normalized_paths(nested_planned)
scope_source = top_planned if top_paths else nested_planned
if top_paths and nested_paths and top_paths != nested_paths:
    expansion_reason = ""
    if isinstance(commit_contract, dict):
        expansion_reason = str(commit_contract.get("scope_expansion_reason") or "").strip()
    # A legitimate expansion (target_path outgrew its original scope during
    # implementation) must go through declare_scope_expansion(), which
    # records a non-empty reason alongside the widened commit_contract.
    # planned_paths. Without that reason, a top/nested mismatch is either
    # accidental drift or an undeclared scope grab, and stays a hard BLOCK
    # exactly as before (bulletin blt_20260724_162804 (d)).
    declared = bool(expansion_reason) and nested_paths.issuperset(top_paths)
    status = "declared" if declared else "undeclared"
    added = sorted(nested_paths - top_paths)
    print(f"SCOPE_EXPANSION status={status} added={added} reason={expansion_reason!r}", file=sys.stderr)
    if not declared:
        raise ValueError("planned_paths mismatch between task and commit_contract")
    scope_source = nested_planned
collect(scope_source)

report_path = task.get("report_path")
if isinstance(report_path, str) and report_path.strip():
    candidate = report_path if os.path.isabs(report_path) else os.path.join(control_root, report_path)
    if os.path.isfile(candidate):
        report = load(candidate)
        collect(report.get("files_modified"))

seen = set()
for raw in values:
    path = raw if os.path.isabs(raw) else os.path.join(root, raw)
    resolved = os.path.realpath(path)
    if resolved != root and not resolved.startswith(root + os.sep):
        if any(
            resolved == candidate or resolved.startswith(candidate + os.sep)
            for candidate in external_roots
        ):
            print(f"WARN: external task scope path excluded: {raw}", file=sys.stderr)
            continue
        raise ValueError(f"scope path outside repository: {raw}")
    relative = os.path.relpath(resolved, root)
    if relative not in seen:
        seen.add(relative)
        sys.stdout.buffer.write(relative.encode() + b"\0")
PY
}

# Resolve only tests explicitly named by the task author or final report.
# Top-level planned_paths belongs to the authored task and its test entries are
# direct execution requests. The nested commit_contract remains an inferred
# ownership boundary and is deliberately excluded.
task_explicit_test_paths() {
    local task_file="$1"
    local scope_root
    scope_root="$(task_scope_root "$task_file")" || return 1
    python3 - "$scope_root" "$task_file" "$REPO_ROOT" <<'PY'
import os
import sys

import yaml

root = os.path.realpath(sys.argv[1])
task_path = os.path.realpath(sys.argv[2])
control_root = os.path.realpath(sys.argv[3])

def load(path):
    with open(path, encoding="utf-8") as handle:
        value = yaml.safe_load(handle) or {}
    if not isinstance(value, dict):
        raise ValueError(f"mapping required: {path}")
    return value

def collect(value, output):
    if isinstance(value, str):
        if value.strip():
            output.append(value.strip())
    elif isinstance(value, dict):
        collect(value.get("path"), output)
    elif isinstance(value, list):
        for item in value:
            collect(item, output)

def is_test(path):
    name = os.path.basename(path)
    return (
        path.startswith("tests/")
        or "/tests/" in path
        or path.endswith((".bats", ".spec.js", ".test.js"))
        or (name.startswith("test_") and name.endswith(".py"))
    )

document = load(task_path)
task = document.get("task", document)
if not isinstance(task, dict):
    raise ValueError("task mapping missing")

contract = task.get("commit_contract") if isinstance(task.get("commit_contract"), dict) else {}
external_roots = []
external_candidates = [
    task.get("task_worktree_repo"),
    contract.get("repo_root"),
]
for candidate in external_candidates:
    if isinstance(candidate, str) and candidate.strip():
        candidate_root = os.path.realpath(candidate)
        if candidate_root != root and candidate_root not in external_roots:
            external_roots.append(candidate_root)

values = []
declared_values = []
collect(task.get("test_path"), declared_values)
collect(task.get("test_necessity"), declared_values)
planned_values = []
collect(task.get("planned_paths"), planned_values)
declared_values.extend(path for path in planned_values if is_test(path))
for raw in declared_values:
    path = raw if os.path.isabs(raw) else os.path.join(root, raw)
    resolved = os.path.realpath(path)
    if resolved != root and not resolved.startswith(root + os.sep):
        if any(
            resolved == candidate or resolved.startswith(candidate + os.sep)
            for candidate in external_roots
        ):
            print(f"WARN: external task test path excluded: {raw}", file=sys.stderr)
            continue
        raise ValueError(f"explicit test path outside repository: {raw}")
    relative = os.path.relpath(resolved, root)
    if not is_test(relative):
        raise ValueError(f"explicit test path has no supported engine: {raw}")
    if not os.path.isfile(resolved):
        raise ValueError(f"explicit test path is missing: {raw}")
    values.append(raw)
collect(task.get("files_modified"), values)
report_path = task.get("report_path")
if isinstance(report_path, str) and report_path.strip():
    candidate = report_path if os.path.isabs(report_path) else os.path.join(control_root, report_path)
    if os.path.isfile(candidate):
        collect(load(candidate).get("files_modified"), values)

seen = set()
for raw in values:
    path = raw if os.path.isabs(raw) else os.path.join(root, raw)
    resolved = os.path.realpath(path)
    if resolved != root and not resolved.startswith(root + os.sep):
        if any(
            resolved == candidate or resolved.startswith(candidate + os.sep)
            for candidate in external_roots
        ):
            print(f"WARN: external task test path excluded: {raw}", file=sys.stderr)
            continue
        raise ValueError(f"explicit test path outside repository: {raw}")
    relative = os.path.relpath(resolved, root)
    if is_test(relative) and relative not in seen:
        seen.add(relative)
        sys.stdout.buffer.write(relative.encode() + b"\0")
PY
}

# A directory in a task contract is an ownership boundary, not a dependency
# selector input.  Resolve it to the concrete tracked/untracked files changed
# beneath that boundary; passing the literal directory makes test_select map
# every dependency in the tree.
expand_task_directory_scope() {
    local root="$1"; shift
    local path rel
    local -a expanded=()
    for path in "$@"; do
        if [ -d "$root/$path" ]; then
            while IFS= read -r rel; do
                [ -n "$rel" ] && expanded+=("$rel")
            done < <(
                { git -C "$root" diff --name-only HEAD -- "$path"
                  git -C "$root" ls-files --others --exclude-standard -- "$path"; } |
                    awk 'NF && !seen[$0]++'
            )
        else
            expanded+=("$path")
        fi
    done
    [ "${#expanded[@]}" -gt 0 ] || {
        echo "BLOCK: directory task scope has no concrete changed files" >&2
        return 2
    }
    printf '%s\0' "${expanded[@]}"
}

is_test_contract_path() {
    local path="$1" name="${1##*/}"
    [[ "$path" == tests/* || "$path" == */tests/* \
        || "$path" == *.bats || "$path" == *.spec.js \
        || "$path" == *.test.js || ( "$name" == test_*.py ) ]]
}

# Record a task_scope_paths() SCOPE_EXPANSION stderr line into gate_fire_log
# for detector_fp_rate visibility (AC1: 検査発火はgate_fire_logへ記録し
# detector_fp_rateで計測可能に接続する). No-op when task_scope_paths did not
# hit a top/nested planned_paths mismatch at all.
log_scope_expansion_fire() {
    local task_yaml="$1"
    local stderr_file="$2"
    local scope_rc="$3"
    local line
    line="$(grep '^SCOPE_EXPANSION ' "$stderr_file" 2>/dev/null | tail -1 || true)"
    [ -n "$line" ] || return 0
    local log_dir="${LOG_DIR:-$REPO_ROOT/logs}"
    mkdir -p "$log_dir" 2>/dev/null || true
    local result="BLOCK"
    [ "$scope_rc" -eq 0 ] && result="PASS"
    local detail="${line#SCOPE_EXPANSION }"
    detail="${detail//\"/\\\"}"
    (
        flock -w 5 204 || true
        printf -- '- ts: "%s", file: "%s", gate: "scope_expansion", result: %s, checks: "%s"\n' \
            "$(date '+%Y-%m-%dT%H:%M:%S')" "$task_yaml" "$result" "$detail" \
            >> "$log_dir/gate_fire_log.yaml"
    ) 204>"$log_dir/gate_fire_log.yaml.lock"
}

# A source-owned external backend task must never silently widen to the entire
# pytest suite.  Full-unit execution is a wave checkpoint, not a per-task
# fallback.  Authorization is deliberately machine-readable and bound to the
# external repository HEAD so prose mentioning "checkpoint" cannot enable it.
task_allows_full_unit_checkpoint() {
    local task_yaml="$1"
    local project_root="$2"
    python3 - "$task_yaml" "$project_root" <<'PY'
import re
import subprocess
import sys

import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    document = yaml.safe_load(handle) or {}
task = document.get("task", document)
if not isinstance(task, dict):
    raise SystemExit(2)

execution = task.get("test_execution")
checkpoint = execution.get("full_unit_checkpoint") if isinstance(execution, dict) else None
if not isinstance(checkpoint, dict):
    raise SystemExit(1)

fixed_sha = str(checkpoint.get("fixed_sha") or "")
allowed = checkpoint.get("allowed") is True
wave_final = checkpoint.get("wave_final") is True
if not (allowed and wave_final and re.fullmatch(r"[0-9a-f]{40}", fixed_sha)):
    raise SystemExit(1)

head = subprocess.run(
    ["git", "-C", sys.argv[2], "rev-parse", "HEAD"],
    check=True, capture_output=True, text=True,
).stdout.strip()
raise SystemExit(0 if head == fixed_sha else 1)
PY
}

log_full_unit_scope_guard() {
    local task_yaml="$1"
    local result="$2"
    local detail="$3"
    local log_dir="${LOG_DIR:-$REPO_ROOT/logs}"
    mkdir -p "$log_dir" 2>/dev/null || true
    (
        flock -w 5 206 || true
        printf -- '- ts: "%s", file: "%s", gate: "full_unit_scope_guard", result: %s, checks: "%s"\n' \
            "$(date '+%Y-%m-%dT%H:%M:%S')" "$task_yaml" "$result" "$detail" \
            >> "$log_dir/gate_fire_log.yaml"
    ) 206>"$log_dir/gate_fire_log.yaml.lock"
}

# Canonical, audited way to expand a task's commit_contract.planned_paths
# beyond its originally declared scope. Writing planned_paths directly, or
# via yaml_field_set on a raw dotted nested field name, either desyncs the
# top-level/commit_contract copies or corrupts the YAML with a literal
# "commit_contract.planned_paths" key (bulletin blt_20260724_162804 (a): the
# case-driven field router in yaml_field_set() only recognizes the exact
# field name "commit_contract" for its structured mapping lane, not a
# dotted path into it). This is the only supported entry point: it requires
# a non-empty reason, rewrites commit_contract as one atomic mapping via
# that existing structured lane, and records the event to gate_fire_log.
declare_scope_expansion() {
    local task_yaml="$1"
    local reason="$2"
    shift 2 || true
    local -a new_paths=("$@")

    [ -f "$task_yaml" ] || { echo "BLOCK: task yaml not found: $task_yaml" >&2; return 2; }
    reason="${reason#"${reason%%[![:space:]]*}"}"
    reason="${reason%"${reason##*[![:space:]]}"}"
    [ -n "$reason" ] || { echo "BLOCK: scope expansion reason must be non-empty" >&2; return 2; }
    [ "${#new_paths[@]}" -gt 0 ] || { echo "BLOCK: at least one new path is required" >&2; return 2; }

    local new_contract_json
    new_contract_json="$(REASON="$reason" python3 - "$task_yaml" "${new_paths[@]}" <<'PY'
import json
import os
import sys

import yaml

task_path = sys.argv[1]
new_paths = sys.argv[2:]
reason = os.environ["REASON"]

with open(task_path, encoding="utf-8") as fh:
    doc = yaml.safe_load(fh) or {}
task = doc.get("task", doc)
if not isinstance(task, dict):
    print("BLOCK: task mapping missing", file=sys.stderr)
    raise SystemExit(2)

contract = task.get("commit_contract")
if not isinstance(contract, dict):
    print("BLOCK: task.commit_contract must be a mapping", file=sys.stderr)
    raise SystemExit(2)

existing = contract.get("planned_paths") or []
if not isinstance(existing, list):
    print("BLOCK: commit_contract.planned_paths must be a list", file=sys.stderr)
    raise SystemExit(2)

merged = list(dict.fromkeys([*[str(p) for p in existing], *new_paths]))
updated = dict(contract)
updated["planned_paths"] = merged
updated["scope_expansion_reason"] = reason
print(json.dumps(updated))
PY
)" || return 2

    if ! bash "$REPO_ROOT/scripts/lib/yaml_field_set.sh" "$task_yaml" task commit_contract "$new_contract_json"; then
        echo "BLOCK: failed to write expanded commit_contract" >&2
        return 1
    fi

    local log_dir="${LOG_DIR:-$REPO_ROOT/logs}"
    mkdir -p "$log_dir" 2>/dev/null || true
    (
        flock -w 5 205 || true
        printf -- '- ts: "%s", file: "%s", gate: "scope_expansion_declared", result: PASS, checks: "reason=%s added=%s"\n' \
            "$(date '+%Y-%m-%dT%H:%M:%S')" "$task_yaml" "${reason//\"/\\\"}" "${new_paths[*]}" \
            >> "$log_dir/gate_fire_log.yaml"
    ) 205>"$log_dir/gate_fire_log.yaml.lock"

    echo "OK: commit_contract.planned_paths expanded (reason recorded)"
}

# A read-only recon owns no source path.  Treating inspection references as
# implementation ownership expands dependency tests and attributes unrelated
# failures to the recon.  Keep this predicate narrow and fail closed: only the
# explicit no-commit recon/scout contract with inspection-only inputs qualifies.
task_is_readonly_probe() {
    local task_file="$1"
    python3 - "$task_file" <<'PY'
import json
import sys

import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    document = yaml.safe_load(handle) or {}
task = document.get("task", document)
if not isinstance(task, dict):
    raise SystemExit(2)

commit = task.get("commit_contract")
is_no_commit = isinstance(commit, dict) and commit.get("required") is False
is_recon = task.get("task_type") in {"recon", "recon2", "scout"}
has_inspection = bool(task.get("inspection_path") or task.get("readonly_refs"))

owned = []
for key in ("target_path", "test_path", "files_to_modify", "files_modified", "owned_paths"):
    value = task.get(key)
    if value not in (None, "", [], {}):
        owned.append(key)
owned_json = task.get("owned_paths_json")
if isinstance(owned_json, str) and owned_json.strip():
    if json.loads(owned_json):
        owned.append("owned_paths_json")
elif owned_json not in (None, "", [], {}):
    owned.append("owned_paths_json")

top_planned = task.get("planned_paths")
commit_planned = commit.get("planned_paths") if isinstance(commit, dict) else None
if top_planned not in (None, "", [], {}):
    owned.append("planned_paths")
if commit_planned not in (None, "", [], {}):
    owned.append("commit_contract.planned_paths")

raise SystemExit(0 if is_no_commit and is_recon and has_inspection and not owned else 1)
PY
}

# Resolve the task's repository from the project registry.  Unknown projects,
# malformed registry paths, and non-git directories fail closed.
task_scope_root() {
    local task_file="$1"
    python3 - "$REPO_ROOT" "$task_file" <<'PY'
import os, subprocess, sys, yaml
control_root, task_path = map(os.path.realpath, sys.argv[1:])
doc = yaml.safe_load(open(task_path, encoding="utf-8")) or {}
task = doc.get("task", doc)
contract = task.get("commit_contract") if isinstance(task.get("commit_contract"), dict) else {}
project = str(task.get("project") or "infra").strip()
contract_root = str(contract.get("repo_root") or "").strip()
task_worktree_root = str(task.get("task_worktree_repo") or "").strip()
task_worktree_path = str(task.get("task_worktree_path") or "").strip()
if task_worktree_path:
    candidate = task_worktree_path
elif task_worktree_root:
    candidate = task_worktree_root
elif contract_root:
    candidate = contract_root
elif project == "infra":
    candidate = control_root
else:
    registry = os.path.join(control_root, "projects", project + ".yaml")
    if not os.path.isfile(registry):
        raise SystemExit(f"unknown project: {project}")
    pdata = yaml.safe_load(open(registry, encoding="utf-8")) or {}
    candidate = str((pdata.get("project") or {}).get("path") or "").strip()
candidate = os.path.realpath(candidate)
if not os.path.isdir(candidate):
    raise SystemExit(f"invalid project path: {candidate}")
check = subprocess.run(["git", "-C", candidate, "rev-parse", "--show-toplevel"],
                       text=True, capture_output=True)
if check.returncode or os.path.realpath(check.stdout.strip()) != candidate:
    raise SystemExit(f"project path is not repository root: {candidate}")
print(candidate)
PY
}

# A throwaway fixture must never retain a live path back into the checkout.
# The dangerous shape is an untracked symlink below tests/ whose resolved
# target is a tracked file in this repository: a test redirection/cp then
# mutates the source checkout instead of its isolated fixture.  Tracked
# symlinks are an explicit repository contract (normally read-only), while a
# regular copy and a broken link cannot write through to a tracked source.
guard_fixture_symlink_write_through() {
    local tests_root="$REPO_ROOT/tests" link resolved relative
    [ -d "$tests_root" ] || return 0
    while IFS= read -r -d '' link; do
        # Repository-owned links are intentional, reviewable fixtures.
        relative="${link#"$REPO_ROOT"/}"
        git -C "$REPO_ROOT" ls-files --error-unmatch -- "$relative" >/dev/null 2>&1 && continue
        resolved="$(readlink -f -- "$link" 2>/dev/null || true)"
        [ -n "$resolved" ] || continue
        case "$resolved" in
            "$REPO_ROOT"/*) ;;
            *) continue ;;
        esac
        relative="${resolved#"$REPO_ROOT"/}"
        if git -C "$REPO_ROOT" ls-files --error-unmatch -- "$relative" >/dev/null 2>&1; then
            printf 'BLOCK: untracked test fixture symlink resolves to tracked source: %s -> %s\n' \
                "${link#"$REPO_ROOT"/}" "$relative" >&2
            return 2
        fi
    done < <(find "$tests_root" -type l -print0 2>/dev/null)
}

bats_source_fingerprint() {
    if [ -n "${BATS_SOURCE_FINGERPRINT:-}" ]; then
        printf '%s\n' "$BATS_SOURCE_FINGERPRINT"
        return 0
    fi
    # git index object hashes: reads git's in-memory index (no NTFS file I/O).
    # Captures committed+staged changes (~30x faster than sha256sum of 288 files).
    # Unstaged-only changes not captured; use BATS_CACHE=0 or set
    # BATS_SOURCE_FINGERPRINT manually when running against uncommitted edits.
    git -C "$REPO_ROOT" ls-files --format='%(objectname)' \
        -- scripts lib tests/helpers ':!scripts/run_tests.sh' 2>/dev/null \
        | sha256sum | awk '{print $1}'
}

bats_cache_key() {
    local file="$1"
    local inner_jobs="$2"
    local source_fp="$3"
    local file_fp
    file_fp="$(sha256sum "$file" | awk '{print $1}')"
    printf '%s\n' "${source_fp}:${file_fp}:jobs=${inner_jobs}" | sha256sum | awk '{print $1}'
}

order_bats_files_lpt() {
    local source_fp="$1" commit_sha ledger
    shift
    commit_sha="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf unknown)"
    ledger="${TEST_TIMING_LEDGER:-$REPO_ROOT/logs/test_timing_ledger.tsv}"
    if [ ! -s "$ledger" ]; then
        printf '%s\n' "$@"
        return 0
    fi
    awk -F '\t' -v commit="$commit_sha" -v fp="$source_fp" '
        NR == 1 { next }
        $3 == commit && $9 == "pass" && $11 == "0" && $12 == fp {
            run[$1] = $13
            row[$1, $6] = $8
        }
        END {
            latest = ""
            for (r in run) if (run[r] > run[latest]) latest = r
            if (latest != "")
                for (key in row) {
                    split(key, p, SUBSEP)
                    if (p[1] == latest) print p[2] "\t" row[key]
                }
        }
    ' "$ledger" >"${TMPDIR:-/tmp}/shogun-lpt.$$.tsv"
    # With an existing ledger but no row for the current commit/fingerprint,
    # the first awk input is empty.  Plain NR==FNR then remains true for the
    # second input too and silently consumes every requested test file as
    # timing metadata, yielding the false success "N files (0 run, 0 cached)".
    # Keep input 1 structurally non-empty so input 2 is always scheduled.
    [ -s "${TMPDIR:-/tmp}/shogun-lpt.$$.tsv" ] || printf '\t\n' >"${TMPDIR:-/tmp}/shogun-lpt.$$.tsv"
    awk -F '\t' 'NR==FNR { measured[$1]=$2; next }
        { score=(($0 in measured) ? measured[$0] : 1e12); print score "\t" NR "\t" $0 }
    ' "${TMPDIR:-/tmp}/shogun-lpt.$$.tsv" <(printf '%s\n' "$@") \
        | sort -t $'\t' -k1,1nr -k2,2n | cut -f3-
    rm -f "${TMPDIR:-/tmp}/shogun-lpt.$$.tsv"
}

aggregate_bats_outputs() {
    local manifest="$1" stats="$2" tap_path="${BATS_TAP_OUTPUT:-}"
    awk -F '\t' -v stats="$stats" -v tap="$tap_path" '
        function count_source(path, line, n) {
            n=0
            while ((getline line < path) > 0) if (line ~ /^@test /) n++
            close(path)
            return n
        }
        {
            pid=$1; file=$2; out=$3; timing=$4; cache_hit=$5
            skip=0; abnormal=0
            if (cache_hit == 0) {
                while ((getline line < out) > 0) {
                    if (line ~ /# skip/) skip++
                    if (line ~ /^not ok /) abnormal++
                    if (tap != "") print line >> tap
                }
                close(out)
            }
            tests=count_source(file)
            if (cache_hit == 1 && tap != "") {
                print "1.." tests >> tap
                for (i=1; i<=tests; i++) print "ok " i " cached" >> tap
            }
            print pid "\t" file "\t" tests "\t" skip "\t" abnormal > stats
        }
    ' "$manifest"
}

run_bats_files_parallel() {
    local -a files=("$@")
    if [[ "${PRECOMMIT:-0}" == "1" ]]; then
        local -a precommit_files=()
        local precommit_file
        for precommit_file in "${files[@]}"; do
            if [[ "${precommit_file##*/}" == "test_ninja_scope_commit.bats" ]]; then
                printf 'PRECOMMIT_EXCLUDED_SELF_TEST path=%s reason=commit_queue_recursion\n' \
                    "$precommit_file" >&2
                continue
            fi
            precommit_files+=("$precommit_file")
        done
        files=("${precommit_files[@]}")
        if [ "${#files[@]}" -eq 0 ]; then
            printf 'PRECOMMIT_TEST_SELECTION files=0 excluded_self_test=1\n' >&2
            return 0
        fi
    fi
    if [[ -n "${RUN_TESTS_SELECTED_PATHS_FILE:-}" ]]; then
        if [[ "${RUN_TESTS_PRESERVE_SELECTED_PATHS:-0}" != "1" ]]; then
            : > "$RUN_TESTS_SELECTED_PATHS_FILE"
        fi
        local selected_path
        for selected_path in "${files[@]}"; do
            if [[ "${RUN_TESTS_PRESERVE_SELECTED_PATHS:-0}" != "1" ]]; then
                printf '%s\n' "${selected_path#"$REPO_ROOT"/}" >> "$RUN_TESTS_SELECTED_PATHS_FILE"
            fi
        done
    fi
    local total="${#files[@]}"
    local out_dir pid file failed file_inner_jobs file_weight active_weight running_pids
    local source_fp cache_key cache_path cached_count launched_count timing_path out manifest stats suite_started_ns
    local -a pids=()
    local -a all_pids=()
    local -A pid_file=()
    local -A pid_out=()
    local -A pid_weight=()
    local -A pid_cache_path=()
    local -A pid_time=()
    local -A pid_rc=()
    suite_started_ns="$(date +%s%N)"

    # Each file is a separate bats-core root process.  Never let it inherit a
    # caller/previous bats root's transport namespace: bats uses BATS_* state
    # plus fd 3 for formatter communication, and inherited transport state can
    # make concurrently-started roots consume one another's test events
    # ("unknown test name" / executed-count mismatch).  Keep ordinary test
    # environment variables intact; scrub only bats-core's private runtime
    # state and close its reserved formatter fd at the process boundary.
    run_bats_file_isolated() {
        local test_file="$1"
        local test_jobs="$2"
        local rc=0
        timeout --foreground --kill-after=10s "${BATS_FILE_TIMEOUT_SECONDS}s" env \
            -u BATS_ROOT_PID \
            -u BATS_RUN_TMPDIR \
            -u BATS_SUITE_TMPDIR \
            -u BATS_FILE_TMPDIR \
            -u BATS_TEST_TMPDIR \
            -u BATS_TEST_FILENAME \
            -u BATS_TEST_NAME \
            -u BATS_TEST_NUMBER \
            -u BATS_SUITE_TEST_NUMBER \
            -u BATS_TEST_FILE_NUMBER \
            -u BATS_OUT \
            -u BATS_TAP_OUTPUT \
            -u RUN_TESTS_BATS_BIN \
            -u RUN_TESTS_RECEIPT_PATH \
            -u RUN_TESTS_RUN_ID \
            -u RUN_TESTS_COMMIT_SHA \
            -u RUN_TESTS_SOURCE_FINGERPRINT \
            -u RUN_TESTS_PENDING_FILE_BATCH \
            -u RUN_TESTS_PENDING_SUITE_BATCH \
            -u RUN_TESTS_SELECTED_PATHS_FILE \
            -u SHOGUN_HEAVY_JOB_LOCK_HELD \
            -u SHOGUN_HEAVY_JOB_ADMITTED \
            -u SHOGUN_HEAVY_JOB_TOKEN \
            -u SHOGUN_HEAVY_JOB_OWNER_GENERATION \
            -u SHOGUN_HEAVY_JOB_OWNER_PID \
            "${RUN_TESTS_BATS_BIN:-bats}" "$test_file" --jobs "$test_jobs" --timing 3>&- || rc=$?
        if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
            printf 'TIMEOUT: %s exceeded %ss (rc=%s)\n' \
                "${test_file##*/}" "$BATS_FILE_TIMEOUT_SECONDS" "$rc" >&2
        fi
        return "$rc"
    }

    if [ "$total" -eq 0 ]; then
        echo "No test files selected."
        return 0
    fi

    if [ "${BATS_SPLIT_FILES:-1}" != "1" ]; then
        env \
            -u RUN_TESTS_BATS_BIN \
            -u RUN_TESTS_RECEIPT_PATH \
            -u RUN_TESTS_RUN_ID \
            -u RUN_TESTS_COMMIT_SHA \
            -u RUN_TESTS_SOURCE_FINGERPRINT \
            -u RUN_TESTS_PENDING_FILE_BATCH \
            -u RUN_TESTS_PENDING_SUITE_BATCH \
            -u RUN_TESTS_SELECTED_PATHS_FILE \
            "${RUN_TESTS_BATS_BIN:-bats}" "${files[@]}" --jobs "$JOBS" --timing
        return $?
    fi

    out_dir="$(mktemp -d "${TMPDIR:-/tmp}/shogun-bats.XXXXXX")"
    failed=0
    active_weight=0
    cached_count=0
    launched_count=0
    source_fp="$(bats_source_fingerprint)"
    mapfile -t files < <(order_bats_files_lpt "$source_fp" "${files[@]}")
    # Full-budget fixtures force the live queue to drain.  If they are mixed
    # through LPT order, every drain strands capacity on both sides.  Run the
    # same protected fixtures as one leading block, then let normal LPT work
    # remain work-conserving; protection is unchanged, fragmentation is not.
    local -a protected_files=() normal_files=()
    local file_base
    for file in "${files[@]}"; do
        file_base="${file##*/}"
        case "$file_base" in
            test_cmd_quality_memory_db.bats|test_cmd_save_diagnosis_quality.bats|test_cmd_save_warn_logging.bats|test_session_state_hooks.bats|test_three_layer_preflight.bats|test_gunshi_log_append_obs.bats|test_ninja_monitor_stall.bats|test_hook_dispatchers.bats|test_statusline.bats|test_sqlite3_cli_removal.bats|test_small_workflow_consolidated.bats|test_skill_recommend_metrics.bats|test_insight_write.bats|test_shogun_cli_switch_probe.bats|test_gate_shogun_startup.bats|test_heavy_job_admission.bats|test_daemon_maintenance_lock.bats|test_heavy_job_classifier_newline.bats|test_cmd_complete_insight_consumption.bats|test_pending_approval.bats|test_pre_bash_guard1_git_commit_tokenizer.bats|test_ninja_scope_commit.bats|test_deploy_task_template_generation.bats|test_campaign_lane_shard_item.bats)
                protected_files+=("$file") ;;
            *) normal_files+=("$file") ;;
        esac
    done
    files=("${protected_files[@]}" "${normal_files[@]}")
    if [ "$BATS_CACHE" = "1" ]; then
        mkdir -p "$BATS_CACHE_DIR"
    fi

    reap_finished() {
        local pid
        active_weight=0
        for pid in "${pids[@]}"; do
            active_weight=$((active_weight + pid_weight[$pid]))
        done
    }

    wait_for_one() {
        local finished_pid="${pids[0]}" rc=0 pid next=()
        # Bind completion to one PID that is still present in our bookkeeping.
        # `wait -n -p ... "${pids[@]}"` can reap a different short-lived child
        # while another becomes non-waitable; the fallback then observes
        # "no such job" and loses that child's execution/timing record.
        # Waiting for the selected tracked PID remains event-driven and keeps
        # every completion exactly once.
        wait "$finished_pid" || rc=$?
        [ "$rc" -eq 0 ] || failed=1
        pid_rc["$finished_pid"]="$rc"
        printf 'DONE: %s rc=%s\n' "${pid_file[$finished_pid]##*/}" "$rc" >&2
        for pid in "${pids[@]}"; do
            [ "$pid" = "$finished_pid" ] || next+=("$pid")
        done
        pids=("${next[@]}")
        reap_finished
    }

    local -a queued_files=("${files[@]}") queued_inner=() queued_weight=() queued_cache=()
    local idx selected pending_count
    for file in "${queued_files[@]}"; do
        file_base="${file##*/}"
        file_inner_jobs="$INNER_JOBS"
        file_weight="$INNER_JOBS"
        case "$file_base" in
            test_cmd_save.bats|test_gate_shogun_startup.bats|test_semantic_index_update.bats|test_deploy_task_ac_handling.bats)
                file_inner_jobs="${BATS_HEAVY_INNER_JOBS:-$INNER_JOBS}"
                file_weight="$file_inner_jobs"
                ;;
        esac
        case "$file_base" in
            test_cmd_quality_memory_db.bats|test_cmd_save_diagnosis_quality.bats|test_cmd_save_warn_logging.bats|test_session_state_hooks.bats|test_three_layer_preflight.bats|test_gunshi_log_append_obs.bats|test_ninja_monitor_stall.bats|test_hook_dispatchers.bats|test_statusline.bats|test_sqlite3_cli_removal.bats|test_small_workflow_consolidated.bats|test_skill_recommend_metrics.bats|test_insight_write.bats|test_shogun_cli_switch_probe.bats)
                file_inner_jobs="${BATS_ISOLATED_INNER_JOBS:-$INNER_JOBS}"
                file_weight="$MAX_TEST_JOBS"
                ;;
        esac
        # These fixture suites exercise process-wide hooks, git configuration,
        # daemon locks/children, startup caches, or a reusable mutable scaffold.
        # They are serial internally, but are not independent from other bats
        # roots on a clean runner.  CI run 29435270210 overlapped the 106-case
        # startup gate with three roots and produced 39 assertion failures plus
        # one post-plan daemon timeout.  One such fixture therefore owns the
        # aggregate budget until it exits.
        case "$file_base" in
            test_gate_shogun_startup.bats|test_heavy_job_admission.bats|test_daemon_maintenance_lock.bats|test_heavy_job_classifier_newline.bats|test_cmd_complete_insight_consumption.bats|test_pending_approval.bats|test_pre_bash_guard1_git_commit_tokenizer.bats|test_ninja_scope_commit.bats|test_deploy_task_template_generation.bats|test_campaign_lane_shard_item.bats)
                file_inner_jobs=1
                file_weight="$MAX_TEST_JOBS"
                ;;
        esac
        # Per-file overrides are hints, never permission to exceed the
        # host-wide admission budget.
        if [ "$file_inner_jobs" -gt "$MAX_TEST_JOBS" ]; then
            file_inner_jobs="$MAX_TEST_JOBS"
        fi
        if [ "$file_weight" -gt "$MAX_TEST_JOBS" ]; then
            file_weight="$MAX_TEST_JOBS"
        fi
        cache_path=""
        if [ "$BATS_CACHE" = "1" ]; then
            cache_key="$(bats_cache_key "$file" "$file_inner_jobs" "$source_fp")"
            cache_path="$BATS_CACHE_DIR/$cache_key.pass"
            if [ -f "$cache_path" ]; then
                cached_count=$((cached_count + 1))
                queued_inner+=(0); queued_weight+=(0); queued_cache+=("$cache_path")
                continue
            fi
        fi
        queued_inner+=("$file_inner_jobs"); queued_weight+=("$file_weight"); queued_cache+=("$cache_path")
    done

    pending_count="${#queued_files[@]}"
    while [ "$pending_count" -gt 0 ]; do
        reap_finished
        selected=-1
        for idx in "${!queued_files[@]}"; do
            [ -n "${queued_files[$idx]}" ] || continue
            if [ "${queued_inner[$idx]}" -eq 0 ]; then
                queued_files[$idx]=""; pending_count=$((pending_count - 1)); continue
            fi
            if [ $((active_weight + queued_weight[$idx])) -le "$MAX_TEST_JOBS" ]; then
                selected="$idx"; break
            fi
        done
        # Every remaining file may have become a cache hit in the scan above.
        # In that case there is no live child to reap and the queue is done.
        [ "$pending_count" -gt 0 ] || break
        if [ "$selected" -lt 0 ]; then
            wait_for_one
            # A terminal receipt covers the complete frozen selection, not
            # merely the files admitted before the first failure.  Keep
            # admitting every queued file after a child fails; aggregate the
            # concrete rc only after all selected files have reached a
            # terminal state.  Otherwise a two-slot runner can report 2/9 and
            # leave the public invocation without a valid terminal receipt.
            continue
        fi
        file="${queued_files[$selected]}"
        file_base="${file##*/}"
        file_inner_jobs="${queued_inner[$selected]}"
        file_weight="${queued_weight[$selected]}"
        cache_path="${queued_cache[$selected]}"
        queued_files[$selected]=""
        pending_count=$((pending_count - 1))
        timing_path="$out_dir/$file_base.$$.time"
        (
            _started_ns="$(date +%s%N)"
            _rc=0
            run_bats_file_isolated "$file" "$file_inner_jobs" || _rc=$?
            printf '%s\t%s\n' "$_started_ns" "$(date +%s%N)" >"$timing_path"
            exit "$_rc"
        ) >"$out_dir/$file_base.$$.out" 2>&1 &
        pid=$!
        if [ -n "${BATS_SCHEDULER_TRACE:-}" ]; then
            printf '%s\t%s\t%s\n' "$file_base" "$file_weight" "$active_weight" >>"$BATS_SCHEDULER_TRACE"
        fi
        launched_count=$((launched_count + 1))
        pids+=("$pid")
        all_pids+=("$pid")
        pid_file["$pid"]="$file"
        pid_out["$pid"]="$out_dir/$file_base.$$.out"
        pid_weight["$pid"]="$file_weight"
        pid_cache_path["$pid"]="$cache_path"
        pid_time["$pid"]="$timing_path"
        printf 'START: %s pid=%s weight=%s timeout=%ss\n' \
            "$file_base" "$pid" "$file_weight" "$BATS_FILE_TIMEOUT_SECONDS" >&2
    done

    for pid in "${pids[@]}"; do
        if wait "$pid" 2>/dev/null; then
            pid_rc["$pid"]=0
        else
            pid_rc["$pid"]=$?
            failed=1
        fi
        printf 'DONE: %s rc=%s\n' "${pid_file[$pid]##*/}" "${pid_rc[$pid]}" >&2
    done

    manifest="$(mktemp "${TMPDIR:-/tmp}/shogun-manifest.XXXXXX")"
    stats="$(mktemp "${TMPDIR:-/tmp}/shogun-stats.XXXXXX")"
    if [ -n "${BATS_TAP_OUTPUT:-}" ] \
       && [[ "${RUN_TESTS_PRESERVE_SELECTED_PATHS:-0}" != "1" ]]; then
        : >"$BATS_TAP_OUTPUT"
    fi
    for pid in "${all_pids[@]}"; do
        printf '%s\t%s\t%s\t%s\t0\n' "$pid" "${pid_file[$pid]}" "${pid_out[$pid]}" "${pid_time[$pid]}" >>"$manifest"
    done
    local _manifest_file _manifest_live _manifest_index=0
    for _manifest_file in "${files[@]}"; do
        _manifest_live=0
        for pid in "${all_pids[@]}"; do
            if [ "${pid_file[$pid]}" = "$_manifest_file" ]; then
                _manifest_live=1
                break
            fi
        done
        if [ "$_manifest_live" -eq 0 ]; then
            _manifest_index=$((_manifest_index + 1))
            printf 'cache-%s\t%s\t/dev/null\t/dev/null\t1\n' \
                "$_manifest_index" "$_manifest_file" >>"$manifest"
        fi
    done
    aggregate_bats_outputs "$manifest" "$stats"
    if [ -n "${BATS_TAP_OUTPUT:-}" ] && [ -f "$BATS_TAP_OUTPUT" ]; then
        cat "$BATS_TAP_OUTPUT"
    fi

    if [ "$failed" -ne 0 ]; then
        echo "One or more bats files failed:" >&2
        # Preserve the first concrete runner failure (for example rc=7); a
        # generic rc=1 would hide dependency failures such as exec rc=127.
        local _first_fail_rc=1
        for pid in "${all_pids[@]}"; do
            out="${pid_out[$pid]}"
            file="${pid_file[$pid]}"
            if [ "${pid_rc[$pid]:-0}" -ne 0 ]; then
                [ "$_first_fail_rc" -ne 1 ] || _first_fail_rc="${pid_rc[$pid]}"
                echo "==== $file ====" >&2
                tail -120 "$out" >&2
            elif awk -F '\t' -v p="$pid" '$1==p && $5>0 {found=1} END{exit !found}' "$stats"; then
                echo "==== $file ====" >&2
                tail -120 "$out" >&2
            fi
        done
        return "$_first_fail_rc"
    fi

    # Publish timing only after the whole selected suite completed.  Thus an
    # interrupted/failed run cannot claim all/unit freshness.  Cache rows are
    # retained for accounting but gate_test_health deliberately excludes them
    # from timing freshness and regression comparisons.
    local mode="${RUN_TESTS_MODE:-file}" run_id commit_sha measured_at batch
    local test_count skip_count elapsed_ns wall_sec status cache_hit
    # A focused file run is a partial diagnostic, not suite-freshness
    # evidence. Preserve the historical contract: only aggregate modes may
    # update timing ledgers.
    if [[ "$mode" != file ]]; then
        run_id="${RUN_TESTS_RUN_ID:-$(date -u +%Y%m%dT%H%M%S).$$}"
        commit_sha="${RUN_TESTS_COMMIT_SHA:-$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf unknown)}"
        source_fp="${RUN_TESTS_SOURCE_FINGERPRINT:-$source_fp}"
        measured_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        batch="$(mktemp "${TMPDIR:-/tmp}/shogun-timing.XXXXXX")"
        for file in "${files[@]}"; do
            cache_hit=1
            wall_sec=0
            skip_count=0
            status=pass
            for pid in "${all_pids[@]}"; do
                [ "${pid_file[$pid]}" = "$file" ] || continue
                cache_hit=0
                IFS=$'\t' read -r started_ns ended_ns <"${pid_time[$pid]}"
                elapsed_ns=$((ended_ns - started_ns))
                wall_sec="$(awk -v ns="$elapsed_ns" 'BEGIN {printf "%.3f", ns/1000000000}')"
                skip_count="$(awk -F '\t' -v p="$pid" '$1==p {print $4; exit}' "$stats")"
                break
            done
            test_count="$(awk -F '\t' -v f="$file" '$2==f {print $3; exit}' "$stats")"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
              "$run_id" "${REPO_ROOT##*/}" "$commit_sha" "$mode" bats \
              "$file" "$test_count" "$wall_sec" "$status" "$skip_count" "$cache_hit" \
              "$source_fp" "$measured_at" "mode=$mode;jobs=$MAX_TEST_JOBS" >>"$batch"
        done
        local suite_ended_ns suite_wall_sec sum_file_sec suite_batch
        suite_ended_ns="$(date +%s%N)"
        suite_wall_sec="$(awk -v a="$suite_started_ns" -v b="$suite_ended_ns" 'BEGIN {printf "%.3f", (b-a)/1000000000}')"
        sum_file_sec="$(awk -F '\t' '{s+=$8} END {printf "%.3f", s+0}' "$batch")"
        suite_batch="$(mktemp "${TMPDIR:-/tmp}/shogun-suite-timing.XXXXXX")"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\tpass\t%s\t%s\n' \
          "$run_id" "${REPO_ROOT##*/}" "$commit_sha" "$mode" "$suite_wall_sec" \
          "$sum_file_sec" "$total" "$source_fp" "$measured_at" >"$suite_batch"
        if [ -n "${RUN_TESTS_PENDING_FILE_BATCH:-}" ] \
          && [ -n "${RUN_TESTS_PENDING_SUITE_BATCH:-}" ]; then
            mv -f "$batch" "$RUN_TESTS_PENDING_FILE_BATCH"
            mv -f "$suite_batch" "$RUN_TESTS_PENDING_SUITE_BATCH"
        else
            rm -f "$batch" "$suite_batch"
        fi
    fi
    rm -f "$manifest" "$stats"

    if [ "$BATS_CACHE" = "1" ]; then
        for pid in "${all_pids[@]}"; do
            cache_path="${pid_cache_path[$pid]}"
            [ -n "$cache_path" ] || continue
            printf 'passed_at=%s\nfile=%s\n' "$(date -Is)" "${pid_file[$pid]}" > "$cache_path"
        done
    fi

    printf 'PASS: %s bats file(s) (%s run, %s cached)\n' "$total" "$launched_count" "$cached_count"
}

run_task_test_paths() {
    local -a selected=("$@") bats_paths=() pytest_paths=()
    local path resolved

    for path in "${selected[@]}"; do
        resolved="$path"
        [ -f "$resolved" ] || resolved="$REPO_ROOT/$path"
        if [ ! -f "$resolved" ]; then
            echo "BLOCK: selected task test is missing: $path" >&2
            return 2
        fi
        case "$path" in
            *.bats) bats_paths+=("$path") ;;
            *.py) pytest_paths+=("$path") ;;
            *)
                echo "BLOCK: no task test engine for suffix: $path" >&2
                return 2
                ;;
        esac
    done

    if [[ -n "${RUN_TESTS_SELECTED_PATHS_FILE:-}" ]]; then
        : > "$RUN_TESTS_SELECTED_PATHS_FILE"
        for path in "${selected[@]}"; do
            printf '%s\n' "${path#"$REPO_ROOT"/}" >> "$RUN_TESTS_SELECTED_PATHS_FILE"
        done
    fi
    if [ "${#pytest_paths[@]}" -gt 0 ]; then
        printf 'TEST_DISPATCH engine=pytest files=%s\n' "${#pytest_paths[@]}"
        local pytest_output pytest_rc=0 pytest_path
        pytest_output="$(mktemp)"
        for pytest_path in "${pytest_paths[@]}"; do
            printf 'START: %s pid=%s engine=pytest\n' "${pytest_path##*/}" "$$" >&2
        done
        (cd "$REPO_ROOT" && env \
            -u RUN_TESTS_RECEIPT_PATH \
            -u RUN_TESTS_RUN_ID \
            -u RUN_TESTS_COMMIT_SHA \
            -u RUN_TESTS_SOURCE_FINGERPRINT \
            -u RUN_TESTS_PENDING_FILE_BATCH \
            -u RUN_TESTS_PENDING_SUITE_BATCH \
            -u RUN_TESTS_SELECTED_PATHS_FILE \
            python3 -m pytest -q "${pytest_paths[@]}") \
            2>&1 | tee "$pytest_output" || pytest_rc=${PIPESTATUS[0]}
        for pytest_path in "${pytest_paths[@]}"; do
            printf 'DONE: %s rc=%s engine=pytest\n' "${pytest_path##*/}" "$pytest_rc" >&2
        done
        if [[ -n "${BATS_TAP_OUTPUT:-}" ]]; then
            python3 - "$pytest_output" "$BATS_TAP_OUTPUT" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
lines = [line for line in text.splitlines()
         if re.search(r"\b\d+\s+(?:passed|failed|skipped)\b", line)
         and (re.match(r"^\s*=+\s+.*\s+=+\s*$", line)
              or re.match(r"^\s*\d+\s+(?:passed|failed|skipped)\b", line))]
if lines:
    counts = {"passed": 0, "failed": 0, "skipped": 0}
    for count, outcome in re.findall(r"\b(\d+)\s+(passed|failed|skipped)\b", lines[-1]):
        counts[outcome] = int(count)
    total = sum(counts.values())
    with open(sys.argv[2], "a", encoding="utf-8") as tap:
        tap.write(f"1..{total}\n")
        index = 0
        for outcome in ("passed", "failed", "skipped"):
            for _ in range(counts[outcome]):
                index += 1
                marker = "not ok" if outcome == "failed" else "ok"
                suffix = " # skip" if outcome == "skipped" else ""
                tap.write(f"{marker} {index} pytest-{outcome}{suffix}\n")
PY
        fi
        rm -f "$pytest_output"
        [ "$pytest_rc" -eq 0 ] || return "$pytest_rc"
    fi
    if [ "${#bats_paths[@]}" -gt 0 ]; then
        printf 'TEST_DISPATCH engine=bats files=%s\n' "${#bats_paths[@]}"
        RUN_TESTS_PRESERVE_SELECTED_PATHS=1 run_bats_files_parallel "${bats_paths[@]}" || return $?
    elif [[ -n "${BATS_TAP_OUTPUT:-}" && -f "$BATS_TAP_OUTPUT" ]]; then
        cat "$BATS_TAP_OUTPUT"
    fi
}

verify_run_tests_receipt() {
    python3 - "$1" <<'PY'
import hashlib, json, re, sys
try:
    d=json.load(open(sys.argv[1], encoding='utf-8'))
    required={'version','complete','result','rc','duration_ms','output_sha256',
              'declared_test_count','observed_test_count','skip_count','artifact',
              'signal','command','source_head','test_paths'}
    if d.get('version') == 3:
        required.update({'drvfs_p9_client_rpc','run_manifest','run_id','commit_sha','source_fingerprint'})
    elif 'drvfs_p9_client_rpc' in d: required.add('drvfs_p9_client_rpc')
    if set(d) != required or d.get('version') not in (2,3): raise ValueError('schema')
    if not re.fullmatch(r'[0-9a-f]{40}', d['source_head']): raise ValueError('source_head')
    if d['version'] == 3 and (
        not d['run_id'] or not re.fullmatch(r'[0-9a-f]{40}', d['commit_sha'])
        or not re.fullmatch(r'[0-9a-f]{64}', d['source_fingerprint'])
    ): raise ValueError('run identity')
    if not isinstance(d['test_paths'], list) or not all(isinstance(x,str) and x for x in d['test_paths']):
        raise ValueError('test_paths')
    if d['version'] == 3:
        m=d['run_manifest']
        _rm_req={'cache','commit_sha','selector_input_fingerprint','selected_paths_fingerprint',
                 'estimated_cost','scope_identity'}
        _rm_opt=_rm_req|{'changed_files'}
        if not isinstance(m,dict) or not _rm_req<=set(m)<=_rm_opt:
            raise ValueError('run_manifest')
        # Scope identity is part of the terminal contract: a receipt must carry
        # how many files it ran and how many the mode discovers, so "full suite"
        # is machine-refutable after RUN_TESTS_SELECTED_PATHS_FILE is removed.
        s=m['scope_identity']
        if not isinstance(s,dict) or set(s) != {'mode','selected_file_count','discovered_file_count',
                                                'started_file_count','executed_file_count',
                                                'cached_file_count','failed_files','failed_file_count',
                                                'complete','full_scope','full_scope_claimable'}:
            raise ValueError('scope_identity')
        if s['selected_file_count'] != len(d['test_paths']): raise ValueError('scope_identity count')
        if s['complete'] is not bool(d['complete']): raise ValueError('scope_identity complete')
        # A count claim must be backed by its own enumeration, never by a
        # truncated listing the reader has to re-derive.
        if not isinstance(s['failed_files'], list) or s['failed_file_count'] != len(s['failed_files']):
            raise ValueError('scope_identity failed_files')
        # "Full scope" is the four-condition claim: unit full-scope mode, every
        # discovered file selected, every selected file actually executed, and the
        # run finished. A complete=false receipt can never prove a full suite.
        if s['full_scope'] is not (bool(s['full_scope_claimable'])
                                   and s['discovered_file_count'] is not None
                                   and s['selected_file_count'] == s['discovered_file_count']
                                   and s['executed_file_count'] == s['discovered_file_count']
                                   and bool(s['complete'])):
            raise ValueError('scope_identity full_scope')
    actual=hashlib.sha256(open(d['artifact'],'rb').read()).hexdigest()
    counts_valid=(
        (d['declared_test_count'] > 0 and d['observed_test_count'] == d['declared_test_count'])
        or (d['declared_test_count'] == 0 and d['observed_test_count'] == 0 and not d['test_paths'])
    )
    valid=(actual == d['output_sha256'] and d['complete'] is True and
           d['result'] == 'PASS' and d['rc'] == 0 and d['skip_count'] == 0 and
           counts_valid)
    if not valid: raise ValueError('terminal contract')
except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError) as exc:
    print(f'RECEIPT_FAIL {exc}', file=sys.stderr); raise SystemExit(1)
print('RECEIPT_PASS')
PY
}

validate_run_tests_terminal_receipt() {
    python3 - "$1" <<'PY'
import hashlib, json, re, sys
try:
    d=json.load(open(sys.argv[1], encoding='utf-8'))
    required={'version','complete','result','rc','duration_ms','output_sha256',
              'declared_test_count','observed_test_count','skip_count','artifact',
              'signal','command','source_head','test_paths'}
    if d.get('version') == 3:
        required.update({'drvfs_p9_client_rpc','run_manifest','run_id','commit_sha','source_fingerprint'})
    elif 'drvfs_p9_client_rpc' in d: required.add('drvfs_p9_client_rpc')
    if set(d) != required or d.get('version') not in (2,3): raise ValueError('schema')
    if not re.fullmatch(r'[0-9a-f]{40}', d['source_head']): raise ValueError('source_head')
    if d['version'] == 3 and (
        not d['run_id'] or not re.fullmatch(r'[0-9a-f]{40}', d['commit_sha'])
        or not re.fullmatch(r'[0-9a-f]{64}', d['source_fingerprint'])
    ): raise ValueError('run identity')
    if not isinstance(d['test_paths'], list) or not all(isinstance(x,str) and x for x in d['test_paths']):
        raise ValueError('test_paths')
    actual=hashlib.sha256(open(d['artifact'],'rb').read()).hexdigest()
    if actual != d['output_sha256'] or d['complete'] is not True: raise ValueError('terminal contract')
    if d['result'] not in ('PASS','FAIL') or not isinstance(d['rc'], int): raise ValueError('result')
except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError) as exc:
    print(f'RECEIPT_FAIL {exc}', file=sys.stderr); raise SystemExit(1)
print('RECEIPT_TERMINAL')
PY
}

# A timing cohort is rankable only when one successful receipt joins to exactly
# one suite row and at least one per-file row on all four immutable identities.
validate_run_identity_join() {
    python3 - "$1" "$2" "$3" <<'PY'
import csv, json, re, sys
receipt_path, file_ledger, suite_ledger = sys.argv[1:]
try:
    r=json.load(open(receipt_path, encoding='utf-8'))
    keys=('run_id','commit_sha','source_fingerprint','output_sha256')
    identity=tuple(r[k] for k in keys)
    if r.get('result') != 'PASS' or r.get('rc') != 0 or r.get('complete') is not True:
        raise ValueError('non-success receipt')
    if not identity[0] or not re.fullmatch(r'[0-9a-f]{40}', identity[1]) \
       or not re.fullmatch(r'[0-9a-f]{64}', identity[2]) \
       or not re.fullmatch(r'[0-9a-f]{64}', identity[3]):
        raise ValueError('identity')
    def matches(path):
        with open(path, newline='', encoding='utf-8') as fh:
            return [row for row in csv.DictReader(fh, delimiter='\t')
                    if tuple(row.get(k,'') for k in keys) == identity]
    files, suites = matches(file_ledger), matches(suite_ledger)
    if len(files) < 1 or len(suites) != 1:
        raise ValueError(f'join cardinality files={len(files)} suites={len(suites)}')
except (OSError, KeyError, ValueError, TypeError, json.JSONDecodeError) as exc:
    print(f'RUN_IDENTITY_EXCLUDED {exc}', file=sys.stderr)
    raise SystemExit(1)
print(f'RUN_IDENTITY_RANKABLE files={len(files)} suites=1')
PY
}

read_run_tests_receipt_rc() {
    python3 - "$1" <<'PY'
import json, sys
try:
    value = json.load(open(sys.argv[1], encoding="utf-8")).get("rc")
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= 255:
        raise ValueError("rc")
except (OSError, ValueError, TypeError, json.JSONDecodeError):
    raise SystemExit(2)
print(value)
PY
}

emit_run_tests_terminal_receipt() {
    local receipt="$1"
    shift
    validate_run_tests_terminal_receipt "$receipt" >/dev/null || {
        printf 'TEST_RECEIPT_BLOCK path=%s rc=2\n' "$receipt" >&2
        return 2
    }
    # AC4 (cmd_karo_impl_singleflight_tree_identity_20260726): whether this
    # invocation joined another run's receipt was previously only visible as
    # a "joined=1" token in this stdout line -- an indirect, body-grep-only
    # signal (today's cross-cutting theme). The shared receipt JSON itself
    # cannot gain a "joined" key without changing its strict schema (which
    # run_with_receipt.sh, the leader's own receipt writer, is not part of
    # this task's scope to touch). Instead, write a small structured sidecar
    # a caller can read directly instead of parsing process output.
    python3 - "$receipt" "$@" <<'PY'
import json, sys
path=sys.argv[1]; suffix=" ".join(sys.argv[2:])
flags = dict(tok.split("=", 1) for tok in sys.argv[2:] if "=" in tok)
d=json.load(open(path, encoding="utf-8")); rc=d["rc"]
label="PASS" if rc == 0 else "FAIL"
if flags.get("joined") == "1":
    sidecar_path = path + ".join_status.json"
    with open(sidecar_path, "w", encoding="utf-8") as fh:
        json.dump({
            "joined": True,
            "stale_owner": flags.get("stale_owner") == "1",
            "leader_receipt": path,
        }, fh)
print("TEST_RECEIPT_{} path={} rc={} tests={}/{} skip={} sha256={} duration_ms={}{}".format(
    label, path, rc, d["observed_test_count"], d["declared_test_count"],
    d["skip_count"], d["output_sha256"], d["duration_ms"],
    (" " + suffix) if suffix else ""))
raise SystemExit(rc)
PY
}

recover_run_tests_terminal_receipt() {
    local identity="$1" receipt=""
    if [ -f "$identity" ]; then
        receipt="$identity"
    elif [ -s "${RUN_TESTS_SINGLEFLIGHT_DIR:-/tmp/shogun-run-tests-singleflight-v2}/${identity}.state" ]; then
        receipt="$(sed -n '1p' "${RUN_TESTS_SINGLEFLIGHT_DIR:-/tmp/shogun-run-tests-singleflight-v2}/${identity}.state")"
    elif [ -f "${RUN_TESTS_RECEIPT_DIR:-$REPO_ROOT/logs/test_receipts}/${identity}" ]; then
        receipt="${RUN_TESTS_RECEIPT_DIR:-$REPO_ROOT/logs/test_receipts}/${identity}"
    elif [ -f "${RUN_TESTS_RECEIPT_DIR:-$REPO_ROOT/logs/test_receipts}/${identity}.json" ]; then
        receipt="${RUN_TESTS_RECEIPT_DIR:-$REPO_ROOT/logs/test_receipts}/${identity}.json"
    fi
    [ -n "$receipt" ] || { printf 'TEST_RECEIPT_RECOVERY_BLOCK identity=%s rc=2\n' "$identity" >&2; return 2; }
    validate_run_tests_terminal_receipt "$receipt" >/dev/null || {
        printf 'TEST_RECEIPT_RECOVERY_BLOCK identity=%s path=%s rc=2\n' "$identity" "$receipt" >&2
        return 2
    }
    python3 - "$identity" "$receipt" <<'PY'
import json,sys
d=json.load(open(sys.argv[2], encoding="utf-8"))
print("TEST_RECEIPT_RECOVERED identity={} path={} rc={}".format(sys.argv[1],sys.argv[2],d["rc"]))
PY
}

selection_manifest_for_singleflight() {
    local mode="$1"
    shift
    case "$mode" in
        all) find "$REPO_ROOT/tests/unit" "$REPO_ROOT/tests" -maxdepth 1 -name '*.bats' -type f -print | sort -u ;;
        unit) find "$REPO_ROOT/tests/unit" -maxdepth 1 -name '*.bats' -type f -print | sort -u ;;
        file)
            [ "$#" -gt 0 ] || return 2
            realpath -- "$@" | sort -u
            ;;
        task)
            [ "$#" -eq 1 ] || return 2
            local _sf_task_identity
            _sf_task_identity="$(python3 - "$1" <<'PY'
import hashlib
import json
import os
import sys

import yaml

path = os.path.realpath(sys.argv[1])
document = yaml.safe_load(open(path, encoding="utf-8")) or {}
task = document.get("task", document)
if not isinstance(task, dict):
    raise SystemExit(2)

def paths(value):
    result = []
    if isinstance(value, str) and value.strip():
        result.append(value.strip())
    elif isinstance(value, dict):
        result.extend(paths(value.get("path")))
    elif isinstance(value, list):
        for item in value:
            result.extend(paths(item))
    return result

contract = task.get("commit_contract")
planned = paths(task.get("planned_paths"))
if isinstance(contract, dict):
    planned.extend(paths(contract.get("planned_paths")))
identity = {
    "task_file": path,
    "task_id": str(task.get("task_id") or task.get("subtask_id") or ""),
    "planned_paths": sorted(set(planned)),
}
blob = json.dumps(identity, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
print(hashlib.sha256(blob.encode()).hexdigest())
PY
            )" || return 2
            printf 'task-identity:%s\n' "$_sf_task_identity"
            # Read-only probes own no executable source scope, including when
            # their inspection target belongs to an external project.  Emit
            # the sentinel before external-project identity so the public
            # receipt freezes an empty test_paths list.
            if task_is_readonly_probe "$1"; then
                printf 'readonly-probe:%s\n' "$(realpath -- "$1")"
                return 0
            fi
            local _sf_task_root
            _sf_task_root="$(task_scope_root "$1")" || return 2
            if [ "$_sf_task_root" != "$REPO_ROOT" ]; then
                printf 'external-project:%s\n' "$_sf_task_root"
                return 0
            fi
            local scope
            scope="$(mktemp)"
            task_scope_paths "$1" >"$scope" || { rm -f "$scope"; return 2; }
            mapfile -d '' -t _sf_scoped <"$scope"
            rm -f "$scope"
            [ "${#_sf_scoped[@]}" -gt 0 ] || return 2
            local -a _sf_declared_tests=()
            local _sf_path
            for _sf_path in "${_sf_scoped[@]}"; do
                if is_test_contract_path "$_sf_path"; then
                    _sf_declared_tests+=("$_sf_path")
                fi
            done
            if [ "${#_sf_declared_tests[@]}" -gt 0 ]; then
                printf '%s\n' "${_sf_declared_tests[@]}" \
                    | while IFS= read -r _sf_path; do realpath --canonicalize-missing -- "$_sf_path"; done \
                    | sort -u
            else
                bash "$REPO_ROOT/scripts/test_select.sh" "${_sf_scoped[@]}" \
                    | while IFS= read -r _sf_path; do realpath --canonicalize-missing -- "$_sf_path"; done \
                    | sort -u
            fi
            ;;
        *) return 1 ;;
    esac
}

publish_run_tests_metadata() {
    python3 - "$1" "$2" "$3" "$4" "${5:-}" "${6:-${REPO_ROOT:-.}}" \
        "${7:-}" "${8:-}" "${9:-}" <<'PY'
import glob, hashlib, json, os, re, sys, tempfile
path, head, paths_file, selector_input_fp, run_mode, repo_root, run_id, commit_sha, source_fp=sys.argv[1:10]
d=json.load(open(path, encoding='utf-8'))
paths=[]
if os.path.isfile(paths_file):
    paths=[line.strip() for line in open(paths_file, encoding='utf-8') if line.strip()]
selected_blob=('\n'.join(paths)+'\n').encode()
run_id=run_id or f"metadata-{os.getpid()}"
commit_sha=commit_sha or head
source_fp=source_fp or hashlib.sha256(selected_blob).hexdigest()
cache={'enabled': os.environ.get('BATS_CACHE','1') != '0',
       'directory': os.environ.get('BATS_CACHE_DIR','')}
# Scope identity (cmd_karo_impl_receipt_scope_identity_20260726): selected_files
# alone cannot refute a "full suite" claim, because nothing in the receipt says
# how many files a full suite has. RUN_TESTS_SELECTED_PATHS_FILE is removed right
# after this call, so the comparison must be frozen here. discovered_file_count
# mirrors selection_manifest_for_singleflight()'s own find for the same mode;
# full_scope is only true when the run actually covered every discovered file.
discovered={'unit': ('tests/unit',), 'all': ('tests/unit', 'tests')}.get(run_mode)
discovered_count=None
if discovered:
    found=set()
    for rel in discovered:
        found.update(p for p in glob.glob(os.path.join(repo_root, rel, '*.bats')) if os.path.isfile(p))
    discovered_count=len(found)
# selected==discovered is NOT enough (gunshi self-correction 2026-07-26 18:47): the
# 18:03 run had selected=171/discovered=171 yet only 94 files ever started and the
# receipt was complete=false. Executed (started AND finished, plus cache hits whose
# result is reused) is the third value, and "full scope" additionally requires the
# run to have completed. Only the unit full-scope mode may claim it, so a legitimate
# partial run (affected/file/task) is never mislabelled as an incomplete full run.
scope_identity={'mode': run_mode or 'unknown',
                'selected_file_count': len(paths),
                'discovered_file_count': discovered_count,
                'started_file_count': None,
                'executed_file_count': None,
                'cached_file_count': None,
                'failed_files': [],
                'failed_file_count': 0,
                'complete': bool(d.get('complete')),
                'full_scope': False,
                'full_scope_claimable': run_mode == 'unit'}
d.update(version=3, source_head=head, test_paths=paths, run_id=run_id,
         commit_sha=commit_sha, source_fingerprint=source_fp,
         run_manifest={'cache': cache, 'commit_sha': head,
                       'selector_input_fingerprint': selector_input_fp,
                       'selected_paths_fingerprint': hashlib.sha256(selected_blob).hexdigest(),
                       'scope_identity': scope_identity,
                       'estimated_cost': {
                           'selected_files': len(paths),
                           'suite_timeout_sec': int(os.environ.get('RUN_TESTS_SUITE_TIMEOUT_SEC', '1800')),
                           'selection_reason': 'unknown',
                           'direct_files': 0,
                           'transitive_files': 0,
                       }})
artifact=d.get('artifact', '')
p9={'persistent': False, 'probe_timeout_sec': None, 'pids': []}
try:
    artifact_text=open(artifact, encoding='utf-8', errors='replace').read()
    for line in artifact_text.splitlines():
            if line.startswith('DRVFS_P9_STATE '):
                fields=dict(item.split('=',1) for item in line.split()[1:] if '=' in item)
                p9['persistent']=fields.get('persistent') == '1'
                p9['probe_timeout_sec']=int(fields['probe_timeout_sec'])
                p9['pids']=[] if fields.get('pids') == 'none' else fields.get('pids','').split(',')
    # External project runners (notably Jest) do not emit TAP, so the generic
    # receipt wrapper cannot count them.  Adopt Jest's terminal summary into
    # the same declared/observed/skip contract before the receipt is verified.
    clean=re.sub(r'\x1b\[[0-9;]*m', '', artifact_text)
    reasons=list(re.finditer(
        r'^TEST_SELECTION_REASON direct=(\d+) transitive=(\d+) source=([A-Za-z0-9_-]+)\s*$',
        clean, re.MULTILINE,
    ))
    if reasons:
        direct, transitive, source=reasons[-1].groups()
        d['run_manifest']['estimated_cost'].update(
            selection_reason=source,
            direct_files=int(direct),
            transitive_files=int(transitive),
        )
    # The artifact may contain START/DONE emitted by a selected test's nested
    # child runner.  Scope identity belongs to this run's frozen selection,
    # so child events must not inflate or fail the outer receipt.
    selected_names={os.path.basename(path) for path in paths}
    started={m.group(1) for m in re.finditer(r'^START: (\S+) pid=', clean, re.MULTILINE)
             if m.group(1) in selected_names}
    done_lines=[m for m in re.finditer(r'^DONE: (\S+) rc=(\d+)', clean, re.MULTILINE)
                if m.group(1) in selected_names]
    finished={m.group(1) for m in done_lines}
    # Enumerate every failing file rather than leaving callers to count a
    # truncated view (karo/shogun 2026-07-26 19:00: three claims that day were
    # made from head/tail-cut output). A count must never be derived from a
    # clipped listing, so the receipt carries the full list next to its length.
    failed_files=sorted({m.group(1) for m in done_lines if m.group(2) != '0'})
    summaries=list(re.finditer(r'^PASS: (\d+) bats file\(s\) \((\d+) run, (\d+) cached\)\s*$', clean, re.MULTILINE))
    cached=int(summaries[-1].group(3)) if summaries else 0
    scope_identity.update(
        started_file_count=len(started),
        cached_file_count=cached,
        failed_files=failed_files,
        failed_file_count=len(failed_files),
        # A cache hit contributes its file's result without starting a process,
        # so it counts as executed for coverage purposes; a started-but-unfinished
        # file does not.
        executed_file_count=len(started & finished) + cached,
    )
    scope_identity['full_scope']=bool(
        scope_identity['full_scope_claimable']
        and discovered_count is not None
        and scope_identity['selected_file_count'] == discovered_count
        and scope_identity['executed_file_count'] == discovered_count
        and scope_identity['complete'])
    changed_lines=list(re.finditer(r'^TEST_SELECTION_CHANGED_FILES (.+)\s*$', clean, re.MULTILINE))
    if changed_lines:
        raw=changed_lines[-1].group(1).strip()
        d['run_manifest']['changed_files']=[] if raw=='none' else [f for f in raw.split(',') if f]
    jest=list(re.finditer(
        r'^Tests:\s+(?:(\d+)\s+failed,\s*)?(?:(\d+)\s+skipped,\s*)?'
        r'(?:(\d+)\s+passed,\s*)?(\d+)\s+total\s*$',
        clean, re.MULTILINE,
    ))
    if jest:
        failed, skipped, passed, total=(int(value or 0) for value in jest[-1].groups())
        d['declared_test_count']=total
        d['observed_test_count']=failed + skipped + passed
        d['skip_count']=skipped
    vitest=list(re.finditer(
        r'^\s*Tests\s+(?:(\d+)\s+failed\s*\|\s*)?'
        r'(?:(\d+)\s+skipped\s*\|\s*)?(?:(\d+)\s+passed\s*)'
        r'(?:\((\d+)\))?\s*$',
        clean, re.MULTILINE,
    ))
    if vitest:
        failed, skipped, passed, total=(int(value or 0) for value in vitest[-1].groups())
        total = total or failed + skipped + passed
        d['declared_test_count']=total
        d['observed_test_count']=failed + skipped + passed
        d['skip_count']=skipped
    # Pytest's terminal summary is decoration-delimited rather than TAP/Jest.
    # Count only the three receipt-contract outcomes; warnings, deselected,
    # xfail/xpass, and duration are not selected test results.
    pytest_summaries=[
        line for line in clean.splitlines()
        if re.search(r'\b\d+\s+(?:passed|failed|skipped)\b', line)
        and (re.match(r'^\s*=+\s+.*\s+=+\s*$', line)
             or re.match(r'^\s*\d+\s+(?:passed|failed|skipped)\b', line))
    ]
    if pytest_summaries:
        counts={'passed': 0, 'failed': 0, 'skipped': 0}
        for count, outcome in re.findall(
            r'\b(\d+)\s+(passed|failed|skipped)\b',
            pytest_summaries[-1],
        ):
            counts[outcome]=int(count)
        total=sum(counts.values())
        if total:
            # task dispatch emits pytest outcomes into the same TAP stream as
            # Bats, so the generic receipt already owns the aggregate count.
            # External pytest lanes have no TAP and still need this fallback.
            if 'TEST_DISPATCH engine=pytest' not in clean:
                d['declared_test_count']=total
                d['observed_test_count']=total
                d['skip_count']=counts['skipped']
except (OSError, ValueError):
    pass
d['drvfs_p9_client_rpc']=p9
# A selected test scope with no observable test is never a successful test run.
# Empty selection remains valid only for explicit affected=0 fast exits.
if paths and d.get('rc') == 0 and (
    d.get('declared_test_count', 0) == 0 or d.get('observed_test_count', 0) == 0
):
    d['rc']=2
    d['result']='FAIL'
fd,tmp=tempfile.mkstemp(prefix='.run_tests_receipt.', dir=os.path.dirname(path) or '.')
with os.fdopen(fd,'w',encoding='utf-8') as fh:
    json.dump(d,fh,sort_keys=True); fh.write('\n'); fh.flush(); os.fsync(fh.fileno())
os.replace(tmp,path)
PY
}

probe_persistent_p9_rpc() {
    local probe_timeout="${SHOGUN_DRVFS_P9_PROBE_TIMEOUT:-2}" first second
    [[ "$probe_timeout" =~ ^[1-9][0-9]*$ ]] || { echo "BLOCK: invalid p9 probe timeout" >&2; return 2; }
    first="$(timeout "$probe_timeout" ps -e -o pid=,stat=,wchan= 2>/dev/null \
        | awk '$2 ~ /^D/ && $3 == "p9_client_rpc" {print $1}' | sort -n | paste -sd, -)" || return 2
    [[ -n "$first" ]] || { printf 'DRVFS_P9_STATE persistent=0 probe_timeout_sec=%s pids=none\n' "$probe_timeout"; return 1; }
    sleep 0.1
    second="$(timeout "$probe_timeout" ps -e -o pid=,stat=,wchan= 2>/dev/null \
        | awk '$2 ~ /^D/ && $3 == "p9_client_rpc" {print $1}' | sort -n | paste -sd, -)" || return 2
    if [[ -n "$second" ]]; then
        printf 'DRVFS_P9_STATE persistent=1 probe_timeout_sec=%s pids=%s\n' "$probe_timeout" "$second"
        return 0
    fi
    printf 'DRVFS_P9_STATE persistent=0 probe_timeout_sec=%s pids=none\n' "$probe_timeout"
    return 1
}

provision_frontend_ext4_fallback() {
    local task_root="$1"
    shift
    local source_head fallback patch_file scope_path
    source_head="$(git -C "$task_root" rev-parse HEAD)" || return 2
    fallback="$(mktemp -d /tmp/shogun-frontend-fallback.XXXXXX)" || return 2
    patch_file="$(mktemp /tmp/shogun-frontend-fallback-patch.XXXXXX)" || {
        rm -rf -- "$fallback"
        return 2
    }
    if ! git clone --quiet --shared --no-checkout "$task_root" "$fallback" \
        || ! git -C "$fallback" checkout --quiet "$source_head" \
        || ! git -C "$task_root" diff --binary "$source_head" -- "$@" >"$patch_file"; then
        rm -f -- "$patch_file"
        rm -rf -- "$fallback"
        return 2
    fi
    if [[ -s "$patch_file" ]] && ! git -C "$fallback" apply --binary "$patch_file"; then
        rm -f -- "$patch_file"
        rm -rf -- "$fallback"
        return 2
    fi
    rm -f -- "$patch_file"
    for scope_path in "$@"; do
        if [[ -e "$task_root/$scope_path" ]] \
            && ! git -C "$task_root" ls-files --error-unmatch -- "$scope_path" >/dev/null 2>&1; then
            mkdir -p "$fallback/$(dirname "$scope_path")"
            cp -a -- "$task_root/$scope_path" "$fallback/$scope_path"
        fi
    done
    if [[ -d "$task_root/frontend/node_modules" && ! -e "$fallback/frontend/node_modules" ]]; then
        ln -s "$task_root/frontend/node_modules" "$fallback/frontend/node_modules"
    fi
    printf '%s\n' "$source_head" >"$fallback/.shogun-source-head"
    printf 'DRVFS_EXT4_FALLBACK result=provisioned root=%s source_head=%s dirty_paths=%s\n' \
        "$fallback" "$source_head" "$#" >&2
    printf '%s\n' "$fallback"
}

cleanup_frontend_ext4_fallback() {
    local fallback="$1"
    [[ "$fallback" == /tmp/shogun-frontend-fallback.* && -d "$fallback" ]] || return 2
    rm -rf -- "$fallback"
}

# _run_tests_main(): sourceされても副作用ゼロ(関数定義+変数初期化のみ)にするため、
# self-reexec判定・sweep呼び出し・case分岐(=実行を伴う処理)を全てこの関数にまとめる。
# ファイル末尾の "BASH_SOURCE[0]==$0" ガードが直接実行時のみこれを呼ぶ。
# test_heavy_job_admission.batsがrun_bats_files_parallel()単体をsourceして直接検証
# する際、nested bats実行(bats-core内部通信FDの継承)がbats-core自体のTAP出力集計と
# 衝突し"unknown test name"でスイート全体を破壊する問題を、nested batsを起動しない
# 経路(関数直接呼出し)で回避するために必要な構造。
_run_tests_main() {
    # cmd_karo_hotfix_heavy_job_admission_202607121348: 全量/unit/affectedモードは
    # host-wide flock semaphore(scripts/heavy_job_admission.sh)経由で自分自身を
    # self-reexecし、同時に1本だけが動くようhost全体で強制する(内部の並列bats実行も
    # 同一ロックの傘下に入る)。file <path>単発実行は軽量とみなしadmission対象外。
    if [[ "${SHOGUN_HEAVY_JOB_LOCK_HELD:-0}" != "1" && "${1:-}" != "file" && "${1:-}" != "task" ]]; then
        local _self="${BASH_SOURCE[0]:-$0}"
        # An empty affected selection has no heavy work to protect.  Resolve it
        # before admission, but persist a non-empty result so the admitted
        # process consumes the exact same selection instead of re-reading a
        # concurrently changing worktree.
        if [[ "${1:-affected}" == "affected" ]]; then
            local _early_selector_log _early_selector_rc _early_selector_output _early_manifest
            _early_selector_log="$(mktemp)"
            set +e
            _early_selector_output="$(bash "$REPO_ROOT/scripts/test_select.sh" "${@:2}" 2>"$_early_selector_log")"
            _early_selector_rc=$?
            set -e
            cat "$_early_selector_log" >&2
            rm -f "$_early_selector_log"
            if [[ "$_early_selector_rc" -eq 0 && -z "$_early_selector_output" ]]; then
                echo "TEST_SELECTION result=selected reason=no_mapped_tests files=0 admission=skipped"
                return 0
            fi
            if [[ "$_early_selector_rc" -eq 0 ]]; then
                _early_manifest="$(mktemp)"
                printf '%s\n' "$_early_selector_output" >"$_early_manifest"
                export RUN_TESTS_AFFECTED_SELECTION_MANIFEST="$_early_manifest"
            fi
        fi
        # This function is entered behind the public receipt wrapper.  Keep
        # that inner identity across the admission re-exec; otherwise the
        # admitted process is mistaken for a second public invocation and
        # publishes a duplicate terminal receipt for the same run.
        exec env SHOGUN_HEAVY_JOB_ADMISSION_METRICS=1 \
            bash "$(dirname "$_self")/heavy_job_admission.sh" -- \
            bash "$_self" --receipt-inner "$@"
    fi

    if [[ "${RUN_TESTS_SINGLEFLIGHT_LEADER_PENDING:-0}" == "1" ]]; then
        printf 'SINGLE_FLIGHT_LEADER mode=%s selection_count=%s admission=%s\n' \
            "${RUN_TESTS_SINGLEFLIGHT_MODE:-unknown}" "${RUN_TESTS_SINGLEFLIGHT_SELECTION_COUNT:-0}" \
            "$([[ "${SHOGUN_HEAVY_JOB_LOCK_HELD:-0}" == 1 ]] && echo acquired || echo lightweight)" >&2
        unset RUN_TESTS_SINGLEFLIGHT_LEADER_PENDING
    fi

    # A full/unit/affected runner is a checkpoint root, never a reusable test
    # helper.  Bats fixtures, hooks, or campaign deployers spawned below this
    # point inherit RUN_TESTS_ACTIVE; allowing one of them to start another
    # aggregate scheduler duplicates TAP plans/counts and may leave the nested
    # admission process group alive after the outer root has completed.  File
    # mode remains the explicit bounded primitive for focused nested checks.
    if [[ "${RUN_TESTS_ACTIVE:-0}" == "1" && "${1:-}" != "file" ]]; then
        echo "BLOCK: nested aggregate run_tests invocation (${1:-affected}); use file mode for focused child checks" >&2
        return 2
    fi
    if [[ "${1:-affected}" != "file" ]]; then
        export RUN_TESTS_ACTIVE=1
    fi

    guard_fixture_symlink_write_through
    sweep_stale_embedded_test_tmp

    case "${1:-affected}" in
        all)
            RUN_TESTS_MODE=all
            # A full checkpoint must execute every selected file. Reusing
            # per-file pass cache here silently turns a warm "all" run into
            # an affected subset while still reporting the full file count.
            [ "$BATS_CACHE_EXPLICIT" -eq 1 ] || BATS_CACHE=0
            if [ -n "${RUN_TESTS_SNAPSHOT_MANIFEST:-}" ]; then
                verify_test_tree_snapshot "$RUN_TESTS_SNAPSHOT_MANIFEST"
                mapfile -t test_files < <(sed 's/^[^ ]*  //' "$RUN_TESTS_SNAPSHOT_MANIFEST")
            else
                mapfile -t test_files < <(
                    find "$REPO_ROOT/tests/unit" -maxdepth 1 -name '*.bats' -type f -print
                    find "$REPO_ROOT/tests" -maxdepth 1 -name '*.bats' -type f -print
                )
            fi
            run_bats_files_parallel "${test_files[@]}"
            [ -z "${RUN_TESTS_SNAPSHOT_MANIFEST:-}" ] || verify_test_tree_snapshot "$RUN_TESTS_SNAPSHOT_MANIFEST"
            ;;
        unit)
            RUN_TESTS_MODE=unit
            if [ -n "${RUN_TESTS_SNAPSHOT_MANIFEST:-}" ]; then
                verify_test_tree_snapshot "$RUN_TESTS_SNAPSHOT_MANIFEST"
                mapfile -t test_files < <(sed 's/^[^ ]*  //' "$RUN_TESTS_SNAPSHOT_MANIFEST")
            else
                mapfile -t test_files < <(find "$REPO_ROOT/tests/unit" -maxdepth 1 -name '*.bats' -type f -print)
            fi
            run_bats_files_parallel "${test_files[@]}"
            [ -z "${RUN_TESTS_SNAPSHOT_MANIFEST:-}" ] || verify_test_tree_snapshot "$RUN_TESTS_SNAPSHOT_MANIFEST"
            ;;
        push)
            RUN_TESTS_MODE=push
            inventory="$REPO_ROOT/docs/research/ci-test-elimination-inventory-20260719.csv"
            [ -r "$inventory" ] || { echo "BLOCK: push inventory missing" >&2; exit 2; }
            mapfile -t test_files < <(awk -F, 'NR>1 && $7=="push-maintain"{print $2}' "$inventory" | sort -u)
            [ "${#test_files[@]}" -gt 0 ] || { echo "BLOCK: canonical push set empty" >&2; exit 2; }
            declared_cases=$(awk -F, 'NR>1 && $7=="push-maintain"{n++} END{print n+0}' "$inventory")
            unique_cases=$(awk -F, 'NR>1 && $7=="push-maintain"{seen[$1]=1} END{for(k in seen)n++; print n+0}' "$inventory")
            [ "$declared_cases" -eq "$unique_cases" ] || { echo "BLOCK: duplicate canonical case identity rows=$declared_cases unique=$unique_cases" >&2; exit 2; }
            for file in "${test_files[@]}"; do
                [ -f "$REPO_ROOT/$file" ] || { echo "BLOCK: canonical push test missing: $file" >&2; exit 2; }
            done
            BATS_CACHE=0
            BATS_FILE_TIMEOUT_SECONDS=300
            printf 'CANONICAL_PUSH files=%s cases=%s\n' "${#test_files[@]}" "$declared_cases" >&2
            run_bats_files_parallel "${test_files[@]}"
            ;;
        file)
            shift
            test_files=("$@")
            # Multiple files must use the same per-file process boundary as
            # all/unit/affected. A single bats root shares formatter state and
            # process-global fixture variables across files, producing
            # order-dependent false failures in otherwise passing suites.
            run_bats_files_parallel "${test_files[@]}"
            ;;
        affected)
            shift || true
            local _selector_log _selector_rc _selector_output _changed_files_str
            # Capture the input set for receipt rationale. Explicit paths take
            # precedence; otherwise snapshot the live git diff at run time.
            if [ "$#" -gt 0 ]; then
                _changed_files_str="$(printf '%s,' "$@" | sed 's/,$//')"
            else
                _changed_files_str="$(cd "$REPO_ROOT" && { git diff --name-only 2>/dev/null; git diff --cached --name-only 2>/dev/null; } | sort -u | paste -sd',' -)"
            fi
            if [[ -n "${RUN_TESTS_AFFECTED_SELECTION_MANIFEST:-}" ]]; then
                _selector_output="$(cat "$RUN_TESTS_AFFECTED_SELECTION_MANIFEST")"
                rm -f "$RUN_TESTS_AFFECTED_SELECTION_MANIFEST"
                unset RUN_TESTS_AFFECTED_SELECTION_MANIFEST
                _selector_rc=0
                _selector_log=""
            else
                _selector_log="$(mktemp)"
                set +e
                _selector_output="$(bash "$REPO_ROOT/scripts/test_select.sh" "$@" 2>"$_selector_log")"
                _selector_rc=$?
                set -e
                cat "$_selector_log" >&2
            fi
            if [ "$_selector_rc" -ne 0 ]; then
                printf 'TEST_SELECTION_CHANGED_FILES %s\n' "${_changed_files_str:-none}"
                printf 'TEST_SELECTION_REASON direct=0 transitive=0 source=fallback_selector_error\n'
                printf 'TEST_SELECTION result=fallback reason=selector_exit_%s target=unit\n' "$_selector_rc"
                [ -z "$_selector_log" ] || rm -f "$_selector_log"
                RUN_TESTS_MODE=unit
                mapfile -t test_files < <(find "$REPO_ROOT/tests/unit" -maxdepth 1 -name '*.bats' -type f -print)
                run_bats_files_parallel "${test_files[@]}"
                exit $?
            fi
            [ -z "$_selector_log" ] || rm -f "$_selector_log"
            mapfile -t selected <<<"$_selector_output"
            [ -n "$_selector_output" ] || selected=()
            printf 'TEST_SELECTION_CHANGED_FILES %s\n' "${_changed_files_str:-none}"
            if [ "${#selected[@]}" -eq 0 ]; then
                printf 'TEST_SELECTION_REASON direct=0 transitive=0 source=git_diff_changed_files\n'
                echo "TEST_SELECTION result=selected reason=no_mapped_tests files=0"
                exit 0
            fi
            printf 'TEST_SELECTION_REASON direct=0 transitive=%s source=git_diff_changed_files\n' "${#selected[@]}"
            printf 'TEST_SELECTION result=selected reason=changed_files files=%s\n' "${#selected[@]}"
            RUN_TESTS_MODE=affected
            run_task_test_paths "${selected[@]}"
            ;;
        task)
            shift || true
            [ "$#" -eq 1 ] || { echo "Usage: bash scripts/run_tests.sh task <task_yaml>" >&2; exit 2; }
            [ -r "$1" ] || { echo "BLOCK: task scope file is unreadable: $1" >&2; exit 2; }
            # Six ninjas may validate concurrently. Giving every task runner
            # all host CPUs creates 48 workers on the normal 8-core host and
            # reduces fleet throughput. Keep one worker per task by default;
            # the six-agent fleet then stays within the host CPU budget while
            # full/wave checkpoints retain host-wide parallelism.
            if [[ -z "${BATS_MAX_TEST_JOBS:-}" ]]; then
                MAX_TEST_JOBS=1
            fi
            printf 'TEST_CONCURRENCY mode=task jobs=%s fleet_budget=6\n' "$MAX_TEST_JOBS"
            if task_is_readonly_probe "$1"; then
                echo "TEST_SCOPE result=readonly_probe files=0 task=$1"
                echo "TEST_SELECTION result=selected reason=readonly_probe_no_source_tests files=0"
                exit 0
            fi
            local _scope_tmp _scope_err _scope_rc
            _scope_tmp="$(mktemp)"
            _scope_err="$(mktemp)"
            set +e
            task_scope_paths "$1" >"$_scope_tmp" 2>"$_scope_err"
            _scope_rc=$?
            set -e
            cat "$_scope_err" >&2
            log_scope_expansion_fire "$1" "$_scope_err" "$_scope_rc"
            local _scope_external_filtered=0
            if grep -q '^WARN: external task scope path excluded:' "$_scope_err"; then
                _scope_external_filtered=1
            fi
            rm -f "$_scope_err"
            if [ "$_scope_rc" -ne 0 ]; then
                rm -f "$_scope_tmp"
                echo "BLOCK: task scope could not be resolved" >&2
                exit 2
            fi
            mapfile -d '' -t scoped_paths <"$_scope_tmp"
            rm -f "$_scope_tmp"
            [ "${#scoped_paths[@]}" -gt 0 ] || {
                [ "$_scope_external_filtered" -eq 1 ] || {
                    echo "BLOCK: task scope is empty" >&2
                    exit 2
                }
            }
            local _task_root
            _task_root="$(task_scope_root "$1")" || { echo "BLOCK: task project root could not be resolved" >&2; exit 2; }
            local _explicit_tests_tmp
            local -a _declared_contract_tests=()
            _explicit_tests_tmp="$(mktemp)"
            task_explicit_test_paths "$1" >"$_explicit_tests_tmp" \
                || { rm -f "$_explicit_tests_tmp"; echo "BLOCK: explicit task tests could not be resolved" >&2; exit 2; }
            mapfile -d '' -t _declared_contract_tests <"$_explicit_tests_tmp"
            rm -f "$_explicit_tests_tmp"
            printf 'TEST_SCOPE result=task files=%s task=%s\n' "${#scoped_paths[@]}" "$1"
            if [ "${#scoped_paths[@]}" -eq 0 ] && [ "${#_declared_contract_tests[@]}" -eq 0 ]; then
                echo "TEST_SELECTION result=selected reason=external_scope_paths_excluded files=0"
                exit 0
            fi
            if [ "$_task_root" != "$REPO_ROOT" ]; then
                if [ -x "$_task_root/scripts/run_tests.sh" ]; then
                    (cd "$_task_root" && bash scripts/run_tests.sh affected "${scoped_paths[@]}")
                else
                    local _external_backend=0 _external_frontend=0 _external_path
                    local -a _external_backend_tests=() _external_frontend_sources=()
                    for _external_path in "${scoped_paths[@]}"; do
                        if [[ "$_external_path" == backend/* ]]; then
                            _external_backend=1
                        fi
                        if [[ "$_external_path" == frontend/* ]]; then
                            _external_frontend=1
                            _external_frontend_sources+=("${_external_path#frontend/}")
                        fi
                    done
                    for _external_path in "${_declared_contract_tests[@]}"; do
                        case "$_external_path" in
                            backend/tests/*.py) _external_backend_tests+=("${_external_path#backend/}") ;;
                            frontend/*.spec.js|frontend/*.test.js) _external_frontend_sources+=("${_external_path#frontend/}") ;;
                            *) echo "BLOCK: no external task test engine for path: $_external_path" >&2; exit 2 ;;
                        esac
                    done
                    if [ "$_external_backend" -eq 1 ] && [ -d "$_task_root/backend/tests" ]; then
                        local _external_python="python3"
                        # An explicit backend contract is already a concrete
                        # pytest execution request. Keep its repo_root, test
                        # path, and interpreter in one deterministic boundary:
                        # probing imports before dispatch can reject a valid
                        # wrapper interpreter and silently fall back to the
                        # control repository's environment. Full-unit fallback
                        # retains the capability probe because it has no
                        # explicit contract proving the requested engine.
                        if [ -x "$_task_root/.venv/bin/python" ] \
                            && { [ "${#_external_backend_tests[@]}" -gt 0 ] \
                                || "$_task_root/.venv/bin/python" -c 'import pytest' >/dev/null 2>&1; }; then
                            _external_python="$_task_root/.venv/bin/python"
                        fi
                        local -a _external_backend_nearby_tests=()
                        if [ "${#_external_backend_tests[@]}" -eq 0 ]; then
                            local _external_backend_module _external_backend_candidate _external_backend_seen
                            for _external_path in "${scoped_paths[@]}"; do
                                [[ "$_external_path" == backend/*.py ]] || continue
                                _external_backend_module="${_external_path##*/}"
                                _external_backend_module="${_external_backend_module%.py}"
                                _external_backend_candidate="tests/test_${_external_backend_module}.py"
                                [ -f "$_task_root/backend/$_external_backend_candidate" ] || continue
                                _external_backend_seen=0
                                for _external_backend_existing in "${_external_backend_tests[@]}" \
                                    "${_external_backend_nearby_tests[@]}"; do
                                    [ "$_external_backend_existing" = "$_external_backend_candidate" ] \
                                        && _external_backend_seen=1
                                done
                                if [ "$_external_backend_seen" -eq 0 ]; then
                                    _external_backend_nearby_tests+=("$_external_backend_candidate")
                                fi
                            done
                            _external_backend_tests+=("${_external_backend_nearby_tests[@]}")
                        fi
                        if [ "${#_external_backend_tests[@]}" -gt 0 ]; then
                            local _external_backend_scope="backend_contract"
                            [ "${#_external_backend_nearby_tests[@]}" -gt 0 ] \
                                && _external_backend_scope="backend_nearby"
                            printf 'TEST_SELECTION result=external runner=pytest scope=%s project_root=%s files=%s\n' \
                                "$_external_backend_scope" "$_task_root" "${#_external_backend_tests[@]}"
                            (cd "$_task_root/backend" \
                                && PYTHONPATH="$_task_root${PYTHONPATH:+:$PYTHONPATH}" \
                                    "$_external_python" -m pytest -q "${_external_backend_tests[@]}") || exit $?
                        else
                            if ! task_allows_full_unit_checkpoint "$1" "$_task_root"; then
                                log_full_unit_scope_guard "$1" BLOCK \
                                    "reason=implicit_external_backend_full_unit selected=0"
                                echo "BLOCK: external backend task has no explicit contract tests; full-unit fallback requires test_execution.full_unit_checkpoint allowed=true, wave_final=true, fixed_sha=current_HEAD" >&2
                                exit 2
                            fi
                            log_full_unit_scope_guard "$1" PASS \
                                "reason=explicit_fixed_sha_wave_final_checkpoint"
                            printf 'TEST_SELECTION result=external runner=pytest scope=backend_full_unit_checkpoint project_root=%s\n' "$_task_root"
                            (cd "$_task_root/backend" \
                                && PYTHONPATH="$_task_root${PYTHONPATH:+:$PYTHONPATH}" \
                                    "$_external_python" -m pytest -q) || exit $?
                        fi
                    fi
                    if [ "$_external_frontend" -eq 1 ] && [ -f "$_task_root/frontend/package.json" ]; then
                        printf 'TEST_SELECTION result=external runner=npm-test scope=frontend project_root=%s\n' "$_task_root"
                        local _frontend_root="$_task_root/frontend"
                        if [[ -z "${RUN_TESTS_DRVFS_P9_DETECTED+x}" ]]; then
                            set +e
                            probe_persistent_p9_rpc
                            local _p9_rc=$?
                            set -e
                            case "$_p9_rc" in
                                0) export RUN_TESTS_DRVFS_P9_DETECTED=1 ;;
                                1) export RUN_TESTS_DRVFS_P9_DETECTED=0 ;;
                                *) echo "BLOCK: bounded p9_client_rpc probe failed" >&2; exit 2 ;;
                            esac
                        fi
                        if [[ "${RUN_TESTS_DRVFS_P9_DETECTED:-0}" == "1" ]]; then
                            local _fallback="${RUN_TESTS_FRONTEND_EXT4_FALLBACK:-}"
                            local _fallback_owned=0
                            if [[ -z "$_fallback" ]]; then
                                _fallback="$(provision_frontend_ext4_fallback "$_task_root" "${scoped_paths[@]}")" \
                                    || { echo "BLOCK: frontend ext4 fallback provisioning failed" >&2; exit 2; }
                                _fallback_owned=1
                            fi
                            [[ -d "$_fallback/frontend" ]] \
                                || { echo "BLOCK: frontend ext4 fallback is missing frontend/" >&2; exit 2; }
                            local _fallback_fs
                            _fallback_fs="$(findmnt -n -o FSTYPE -T "$_fallback" 2>/dev/null || true)"
                            [[ "$_fallback_fs" != 9p && "$_fallback_fs" != drvfs && "$_fallback" == /tmp/* ]] \
                                || { echo "BLOCK: frontend fallback must be isolated ext4 under /tmp" >&2; exit 2; }
                            [[ -f "$_fallback/.shogun-source-head" && "$(cat "$_fallback/.shogun-source-head")" == "$(git -C "$_task_root" rev-parse HEAD)" ]] \
                                || { echo "BLOCK: frontend ext4 fallback source identity mismatch" >&2; exit 2; }
                            _frontend_root="$_fallback/frontend"
                            printf 'DRVFS_EXT4_FALLBACK result=selected root=%s receipt=required\n' "$_fallback"
                        fi
                        # cmd_karo_hotfix_run_tests_vitest_cli_20260804:
                        # CLI options are owned by the detected test engine.
                        local _frontend_engine
                        _frontend_engine="$(python3 - "$_frontend_root/package.json" <<'PY'
import json, re, sys
script = str((json.load(open(sys.argv[1], encoding="utf-8")).get("scripts") or {}).get("test") or "")
if re.search(r'(^|[ /])vitest(?:[ /]|$)', script):
    print("vitest")
elif re.search(r'(^|[ /])jest(?:[ /]|$)', script):
    print("jest")
else:
    raise SystemExit(2)
PY
)" || { echo "BLOCK: unsupported external frontend test engine" >&2; exit 2; }
                        local _frontend_rc=0
                        if [[ "$_frontend_engine" == "vitest" ]]; then
                            # Vitest uses positional filters and does not expose
                            # Jest's related-test CLI options.
                            (cd "$_frontend_root" && npm test -- --passWithNoTests "${_external_frontend_sources[@]}") \
                                || _frontend_rc=$?
                        else
                            (cd "$_frontend_root" && npm test -- --runInBand --passWithNoTests --findRelatedTests "${_external_frontend_sources[@]}") \
                                || _frontend_rc=$?
                        fi
                        if [[ "${_fallback_owned:-0}" == "1" ]]; then
                            cleanup_frontend_ext4_fallback "$_fallback" \
                                || { echo "BLOCK: frontend ext4 fallback cleanup failed" >&2; exit 2; }
                        fi
                        [[ "$_frontend_rc" -eq 0 ]] || exit "$_frontend_rc"
                    fi
                    if [ "$_external_backend" -eq 0 ] && [ "$_external_frontend" -eq 0 ]; then
                        if [ "$_scope_external_filtered" -eq 1 ]; then
                            echo "TEST_SELECTION result=selected reason=external_scope_paths_excluded files=0"
                            exit 0
                        fi
                        echo "TEST_SELECTION result=selected reason=external_scope_no_mapped_tests files=0"
                        echo "BLOCK: external task scope has no mapped tests and no explicit contract" >&2
                        exit 2
                    fi
                fi
                exit $?
            fi
            local _selector_log _selector_rc _selector_output
            local -a _direct_scope_tests=()
            local -a _production_scope=()
            local _scoped_path
            for _scoped_path in "${scoped_paths[@]}"; do
                if is_test_contract_path "$_scoped_path"; then
                    _direct_scope_tests+=("$_scoped_path")
                else
                    _production_scope+=("$_scoped_path")
                fi
            done
            if [ "${#_production_scope[@]}" -gt 0 ]; then
                local _concrete_scope_tmp
                _concrete_scope_tmp="$(mktemp)"
                expand_task_directory_scope "$_task_root" "${_production_scope[@]}" >"$_concrete_scope_tmp" \
                    || { rm -f "$_concrete_scope_tmp"; exit 2; }
                mapfile -d '' -t _production_scope <"$_concrete_scope_tmp"
                rm -f "$_concrete_scope_tmp"
            fi
            if [ "${#_declared_contract_tests[@]}" -gt 0 ]; then
                _selector_output="$(printf '%s\n' "${_declared_contract_tests[@]}")"
                _selector_rc=0
                echo "TEST_SELECTION_REASON direct=${#_declared_contract_tests[@]} transitive=0 source=task_explicit_contract"
            elif [ "${#_production_scope[@]}" -gt 0 ]; then
                _selector_log="$(mktemp)"
                set +e
                _selector_output="$(bash "$REPO_ROOT/scripts/test_select.sh" "${_production_scope[@]}" 2>"$_selector_log")"
                _selector_rc=$?
                set -e
                cat "$_selector_log" >&2
                rm -f "$_selector_log"
                local _transitive_count
                _transitive_count="$(printf '%s\n' "$_selector_output" | sed '/^$/d' | wc -l)"
                if [ "${#_direct_scope_tests[@]}" -gt 0 ]; then
                    _selector_output="$(
                        {
                            for _scoped_path in "${_direct_scope_tests[@]}"; do
                                if [[ "$_scoped_path" == /* ]]; then
                                    printf '%s\n' "$_scoped_path"
                                else
                                    printf '%s/%s\n' "$REPO_ROOT" "$_scoped_path"
                                fi
                            done
                            printf '%s\n' "$_selector_output"
                        } \
                            | sed '/^$/d' | awk '!seen[$0]++'
                    )"
                fi
                echo "TEST_SELECTION_REASON direct=${#_direct_scope_tests[@]} transitive=${_transitive_count} source=dependency_map"
            else
                # A test-only task has no production dependency edge to map.
                # Its resolved ownership scope is already the complete,
                # fail-closed execution contract: every scoped path passed
                # is_test_contract_path() above.  Promote only this all-test
                # set; mixed production scopes continue through test_select.
                _selector_output="$(printf '%s\n' "${scoped_paths[@]}")"
                _selector_rc=0
                echo "TEST_SELECTION_REASON direct=${#scoped_paths[@]} transitive=0 source=task_test_only_scope"
            fi
            [ "$_selector_rc" -eq 0 ] || { echo "BLOCK: task-scoped selector failed rc=$_selector_rc" >&2; exit 2; }
            mapfile -t selected <<<"$_selector_output"
            [ -n "$_selector_output" ] || selected=()
            if [ "${#selected[@]}" -eq 0 ]; then
                echo "TEST_SELECTION result=selected reason=task_scope_no_mapped_tests files=0"
                exit 0
            fi
            printf 'TEST_SELECTION result=selected reason=task_scope files=%s\n' "${#selected[@]}"
            RUN_TESTS_MODE=affected
            run_task_test_paths "${selected[@]}"
            ;;
        *)
            echo "Usage: bash scripts/run_tests.sh [all|unit|push|affected|task <task_yaml>|file <path>]" >&2
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    if [[ "${1:-}" == "receipt" ]]; then
        [ "$#" -eq 2 ] || { echo "Usage: bash scripts/run_tests.sh receipt <run-or-selection-identity>" >&2; exit 2; }
        recover_run_tests_terminal_receipt "$2"
        exit $?
    fi
    if [[ "${1:-}" == "declare-scope-expansion" ]]; then
        shift
        [ "$#" -ge 3 ] || {
            echo "Usage: bash scripts/run_tests.sh declare-scope-expansion <task_yaml> <reason> <new_path...>" >&2
            exit 2
        }
        declare_scope_expansion "$@"
        exit $?
    fi
    if [[ "${1:-}" == "--receipt-inner" ]]; then
        shift
        _run_tests_main "$@"
    else
        _requested_tap="${BATS_TAP_OUTPUT:-}"
        _receipt_dir="${RUN_TESTS_RECEIPT_DIR:-$REPO_ROOT/logs/test_receipts}"
        mkdir -p "$_receipt_dir"
        _mode="${1:-affected}"
        _singleflight=0
        # Explicit heavy_job_admission callers already own the outer lock.
        # Taking the single-flight lock underneath it would invert the normal
        # order (single-flight -> admission) and deadlock two callers.
        _admission_claim="${SHOGUN_HEAVY_JOB_ADMITTED:-${SHOGUN_HEAVY_JOB_LOCK_HELD:-0}}"
        if [[ "${SHOGUN_HEAVY_JOB_ADMITTED:-0}" == "1" ]]; then
            bash "$REPO_ROOT/scripts/heavy_job_admission.sh" --validate-token \
                || { echo "BLOCK: invalid heavy admission capability" >&2; exit 2; }
        fi
        if [[ "$_admission_claim" != "1" && ( "$_mode" == "all" || "$_mode" == "unit" || "$_mode" == "task" || "$_mode" == "file" ) ]]; then
            _singleflight=1
            _sf_dir="${RUN_TESTS_SINGLEFLIGHT_DIR:-/tmp/shogun-run-tests-singleflight-v2}"
            mkdir -p "$_sf_dir"
            _sf_selection="$(selection_manifest_for_singleflight "$_mode" "${@:2}")" \
                || { echo "BLOCK: single-flight selection could not be resolved" >&2; exit 2; }
            if [[ "$_mode" == all || "$_mode" == unit ]]; then
                _sf_key="$_mode"
            else
                _sf_key="$(printf '%s\n' "$_sf_selection" | sha256sum | awk '{print $1}')"
            fi
            _sf_lock="$_sf_dir/${_sf_key}.lock"
            _sf_state="$_sf_dir/${_sf_key}.state"
            _sf_heartbeat="${RUN_TESTS_SINGLEFLIGHT_HEARTBEAT_SECONDS:-5}"
            _sf_stale_timeout="${RUN_TESTS_SINGLEFLIGHT_STALE_SECONDS:-10}"
            [[ "$_sf_heartbeat" =~ ^[1-9][0-9]*$ ]] || { echo "BLOCK: invalid single-flight heartbeat interval" >&2; exit 2; }
            [[ "$_sf_stale_timeout" =~ ^[1-9][0-9]*$ ]] || { echo "BLOCK: invalid single-flight stale timeout" >&2; exit 2; }
            # This invocation's own tree identity (source root/HEAD/dirty-hash).
            # Recorded by the leader so a joiner can prove it is the SAME tree
            # the leader actually tested, not merely "the same file selection"
            # (cmd_karo_impl_singleflight_tree_identity_20260726: join previously
            # validated only the receipt's FORM, never tree identity, so a
            # joiner's terminal-receipt could silently be someone else's tree).
            # Scoped to source_head + selection input + the SELECTED test
            # files' own dirty status only (gunshi draft review, adopted by
            # karo): a whole-repo `git status --porcelain` changes every
            # second in a shared worktree with 6 ninjas writing concurrently,
            # so an unscoped exact-match would almost never hold and would
            # defeat the join optimization entirely for everyone (conflicts
            # with "削るな速くしろ"). Only changes to the files that actually
            # affect THIS run's test results should count as a mismatch.
            _sf_tree_root="$REPO_ROOT"
            if [[ "$_mode" == task ]]; then
                _sf_tree_root="$(task_scope_root "${2:-}")" \
                    || { echo "BLOCK: task source root could not be resolved" >&2; exit 2; }
            fi
            _sf_tree_head="$(git -C "$_sf_tree_root" rev-parse HEAD)"
            # `file` mode may legitimately target a path outside this repo
            # entirely (an isolated test fixture, e.g. a bats tmpdir); `git
            # status --porcelain -- <path>` fatals on a pathspec outside the
            # tree, and that fatal exit propagates through `set -eo pipefail`
            # even with stderr redirected. Only ask git about paths that are
            # actually inside this tree; an external path has no repo-tracked
            # dirty state to compare, so it is simply excluded from the hash.
            mapfile -t _sf_dirty_scope_paths < <(
                printf '%s\n' "$_sf_selection" | sed '/^$/d; /^readonly-probe:/d; /^task-identity:/d' \
                    | while IFS= read -r _sf_candidate; do
                        _sf_candidate_real="$(realpath -- "$_sf_candidate" 2>/dev/null)" || continue
                        case "$_sf_candidate_real" in
                            "$_sf_tree_root"/*) printf '%s\n' "$_sf_candidate" ;;
                        esac
                    done
            )
            _sf_tree_dirty="$(
                {
                    printf '%s\n' "$_sf_selection"
                    if [ "${#_sf_dirty_scope_paths[@]}" -gt 0 ]; then
                        git -C "$_sf_tree_root" status --porcelain -- "${_sf_dirty_scope_paths[@]}" 2>/dev/null
                    fi
                } | sha256sum | awk '{print $1}'
            )"
            exec {_sf_fd}>"$_sf_lock"
            if ! flock -n "$_sf_fd"; then
                printf 'SINGLE_FLIGHT_FOLLOWER mode=%s waiting_for_leader=1\n' "$_mode" >&2
                _sf_wait_started=$SECONDS
                while ! flock -w "$_sf_heartbeat" "$_sf_fd"; do
                    printf 'SINGLE_FLIGHT_HEARTBEAT mode=%s waited_sec=%s\n' "$_mode" "$(( ${_sf_waited:-0} + _sf_heartbeat ))" >&2
                    _sf_waited=$(( ${_sf_waited:-0} + _sf_heartbeat ))
                    if (( SECONDS - _sf_wait_started >= _sf_stale_timeout )); then
                        _receipt="$(sed -n '1p' "$_sf_state" 2>/dev/null || true)"
                        _sf_owner="$(sed -n '2p' "$_sf_state" 2>/dev/null || true)"
                        _sf_generation="$(sed -n '3p' "$_sf_state" 2>/dev/null || true)"
                        _sf_owner_pgid="$(sed -n '4p' "$_sf_state" 2>/dev/null || true)"
                        _sf_leader_tree_head="$(sed -n '5p' "$_sf_state" 2>/dev/null || true)"
                        _sf_leader_tree_dirty="$(sed -n '6p' "$_sf_state" 2>/dev/null || true)"
                        [[ "$_sf_owner" =~ ^[1-9][0-9]*$ ]] \
                            || { echo "BLOCK: single-flight stale owner metadata invalid" >&2; exit 2; }
                        if kill -0 "$_sf_owner" 2>/dev/null; then
                            continue
                        fi
                        if ! validate_run_tests_terminal_receipt "$_receipt" >/dev/null; then
                            # A dead owner may leave a state file whose receipt was
                            # cleaned with its isolated checkout.  This is recoverable:
                            # discard only the stale coordination record and become the
                            # new leader.  Treating it as a terminal BLOCK strands every
                            # subsequent run (and can make CI red without a test failure).
                            rm -f "$_sf_state"
                            printf 'SINGLE_FLIGHT_STALE_RECEIPT mode=%s action=restart_leader receipt=%s\n' \
                                "$_mode" "$_receipt" >&2
                            break 2
                        fi
                        # Tree identity: the dead leader's receipt is only a valid
                        # stand-in for THIS invocation if it tested the exact same
                        # HEAD + working-tree dirty state we would test right now.
                        # Missing fields (older state file format) count as a
                        # mismatch -- unproven identity is never treated as a match.
                        if [[ -z "$_sf_leader_tree_head" || "$_sf_tree_head" != "$_sf_leader_tree_head" \
                              || "$_sf_tree_dirty" != "$_sf_leader_tree_dirty" ]]; then
                            rm -f "$_sf_state"
                            printf 'SINGLE_FLIGHT_TREE_MISMATCH mode=%s action=restart_leader receipt=%s\n' \
                                "$_mode" "$_receipt" >&2
                            break 2
                        fi
                        _sf_holders="$(fuser "$_sf_lock" 2>/dev/null | awk '{print NF}' || true)"
                        _sf_holders="${_sf_holders:-0}"
                        _sf_descendants="$(ps -e -o pgid=,pid= 2>/dev/null | awk -v pgid="$_sf_owner_pgid" -v owner="$_sf_owner" '$1 == pgid && $2 != owner { n++ } END { print n+0 }')"
                        printf 'SINGLE_FLIGHT_STALE_OWNER mode=%s owner_pid=%s generation=%s descendants=%s lock_holders=%s followers=1 waited_sec=%s action=join_terminal_receipt\n' \
                            "$_mode" "$_sf_owner" "${_sf_generation:-unknown}" "$_sf_descendants" "$_sf_holders" "$(( SECONDS - _sf_wait_started ))" >&2
                        printf 'SINGLE_FLIGHT_JOINED mode=%s receipt=%s stale_owner=1\n' "$_mode" "$_receipt" >&2
                        emit_run_tests_terminal_receipt "$_receipt" joined=1 stale_owner=1
                        exit $?
                    fi
                done
                [ -s "$_sf_state" ] || { echo "BLOCK: single-flight leader state missing" >&2; exit 2; }
                _receipt="$(sed -n '1p' "$_sf_state")"
                _sf_leader_tree_head="$(sed -n '5p' "$_sf_state" 2>/dev/null || true)"
                _sf_leader_tree_dirty="$(sed -n '6p' "$_sf_state" 2>/dev/null || true)"
                validate_run_tests_terminal_receipt "$_receipt" >/dev/null \
                    || { echo "BLOCK: single-flight leader receipt invalid" >&2; exit 2; }
                if [[ -n "$_sf_leader_tree_head" && "$_sf_tree_head" == "$_sf_leader_tree_head" \
                      && "$_sf_tree_dirty" == "$_sf_leader_tree_dirty" ]]; then
                    printf 'SINGLE_FLIGHT_JOINED mode=%s receipt=%s\n' "$_mode" "$_receipt" >&2
                    emit_run_tests_terminal_receipt "$_receipt" joined=1
                    exit $?
                fi
                # Tree mismatch: the leader tested a different tree than the one
                # this invocation actually has. Do not claim its receipt as our
                # own -- fall through and become the new leader instead.
                printf 'SINGLE_FLIGHT_TREE_MISMATCH mode=%s action=restart_leader receipt=%s\n' \
                    "$_mode" "$_receipt" >&2
            fi
        fi
        _selector_input="${_sf_selection:-$_mode}"
        _selector_input_fp="$(printf '%s\n' "$_selector_input" | sha256sum | awk '{print $1}')"
        _receipt="${RUN_TESTS_RECEIPT_PATH:-$_receipt_dir/run_tests_$(date -u +%Y%m%dT%H%M%S)_$$.json}"
        if [ "$_singleflight" = 1 ]; then
            _snapshot=""
            if [[ "$_mode" == all || "$_mode" == unit ]]; then
                _snapshot="$_sf_dir/${_mode}.$$.snapshot"
                snapshot_test_tree "$_mode" "$_snapshot"
                export RUN_TESTS_SNAPSHOT_MANIFEST="$_snapshot"
            fi
            _sf_generation="$(date -u +%s%N)-$$"
            _sf_owner_pgid="$(ps -o pgid= -p $$ | tr -d ' ')"
            printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$_receipt" "$$" "$_sf_generation" "$_sf_owner_pgid" "$_sf_tree_head" "$_sf_tree_dirty" > "$_sf_state"
            export RUN_TESTS_SINGLEFLIGHT_LEADER_PENDING=1
            export RUN_TESTS_SINGLEFLIGHT_MODE="$_mode"
            export RUN_TESTS_SINGLEFLIGHT_SELECTION_COUNT
            RUN_TESTS_SINGLEFLIGHT_SELECTION_COUNT="$(printf '%s\n' "$_sf_selection" | sed '/^$/d' | wc -l)"
            # Publish leadership before run_with_receipt captures child output.
            # Followers and monitors must observe the leader while it is live,
            # not only after the terminal artifact is flushed.
            printf 'SINGLE_FLIGHT_LEADER mode=%s selection_count=%s admission=pending generation=%s receipt=%s\n' \
                "$_mode" "$RUN_TESTS_SINGLEFLIGHT_SELECTION_COUNT" "$_sf_generation" "$_receipt" >&2
            export RUN_TESTS_SINGLEFLIGHT_LEADER_PENDING=0
        fi
        _tap="${_receipt%.json}.tap"
        _selected_paths="${_receipt%.json}.paths"
        _source_root="$REPO_ROOT"
        if [[ "$_mode" == task ]]; then
            _source_root="$(task_scope_root "${2:-}")" \
                || { echo "BLOCK: task source root could not be resolved" >&2; exit 2; }
        fi
        _source_head="$(git -C "$_source_root" rev-parse HEAD)"
        _run_id="$(date -u +%Y%m%dT%H%M%S).$$.$RANDOM"
        _source_fp="$(bats_source_fingerprint)"
        _pending_file_batch="${_receipt%.json}.timing.pending"
        _pending_suite_batch="${_receipt%.json}.suite-timing.pending"
        # Freeze the selector result before any test process starts. Nested
        # fixture runners must not overwrite the public run's selected set.
        printf '%s\n' "${_sf_selection:-}" \
            | sed '/^$/d; /^readonly-probe:/d; /^task-identity:/d' >"$_selected_paths"
        # Resolve at this public-call boundary.  RUN_TESTS_BATS_BIN may belong
        # to an enclosing bats root; inheriting it would bypass an isolated
        # fixture's PATH and execute the wrong runner.
        _bats_bin="$(command -v bats 2>/dev/null || true)"
        [ -n "$_bats_bin" ] || { echo "BLOCK: bats executable could not be resolved" >&2; exit 2; }
        _suite_timeout="${RUN_TESTS_SUITE_TIMEOUT_SEC:-1800}"
        [[ "$_suite_timeout" =~ ^[1-9][0-9]*$ ]] \
            || { echo "BLOCK: RUN_TESTS_SUITE_TIMEOUT_SEC must be a positive integer" >&2; exit 2; }
        export RUN_TESTS_SUITE_TIMEOUT_SEC="$_suite_timeout"
        set +e
        if [ "$_singleflight" = 1 ]; then
            # The parent retains the mode lock until receipt publication, but
            # test descendants must never inherit its FD and leak the lock.
            (
                eval "exec ${_sf_fd}>&-"
                BATS_TAP_OUTPUT="$_tap" bash "$REPO_ROOT/scripts/run_with_receipt.sh" \
                    --summary-only --live-progress --receipt "$_receipt" -- \
                    timeout --signal=TERM --kill-after=5 "$_suite_timeout" \
                    env PATH="${PATH:-/usr/bin:/bin}:/usr/local/bin:/usr/bin:/bin" RUN_TESTS_BATS_BIN="$_bats_bin" BATS_TAP_OUTPUT="$_tap" RUN_TESTS_SELECTED_PATHS_FILE="$_selected_paths" RUN_TESTS_RUN_ID="$_run_id" RUN_TESTS_COMMIT_SHA="$_source_head" RUN_TESTS_SOURCE_FINGERPRINT="$_source_fp" RUN_TESTS_PENDING_FILE_BATCH="$_pending_file_batch" RUN_TESTS_PENDING_SUITE_BATCH="$_pending_suite_batch" bash "${BASH_SOURCE[0]}" --receipt-inner "$@"
            )
        else
            BATS_TAP_OUTPUT="$_tap" bash "$REPO_ROOT/scripts/run_with_receipt.sh" \
                --summary-only --live-progress --receipt "$_receipt" -- \
                timeout --signal=TERM --kill-after=5 "$_suite_timeout" \
                env PATH="${PATH:-/usr/bin:/bin}:/usr/local/bin:/usr/bin:/bin" RUN_TESTS_BATS_BIN="$_bats_bin" BATS_TAP_OUTPUT="$_tap" RUN_TESTS_SELECTED_PATHS_FILE="$_selected_paths" RUN_TESTS_RUN_ID="$_run_id" RUN_TESTS_COMMIT_SHA="$_source_head" RUN_TESTS_SOURCE_FINGERPRINT="$_source_fp" RUN_TESTS_PENDING_FILE_BATCH="$_pending_file_batch" RUN_TESTS_PENDING_SUITE_BATCH="$_pending_suite_batch" bash "${BASH_SOURCE[0]}" --receipt-inner "$@"
        fi
        _rc=$?
        set -e
        _output_sha256="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["output_sha256"])' "$_receipt")"
        # Timing rows are a terminal-success cohort.  A failed test run still
        # publishes its receipt, but must never make either timing ledger
        # eligible for an exact four-identity join.
        if [ "$_rc" -eq 0 ] && { [ -s "$_pending_file_batch" ] || [ -s "$_pending_suite_batch" ]; }; then
            TEST_TIMING_LEDGER="${TEST_TIMING_LEDGER:-$REPO_ROOT/logs/test_timing_ledger.tsv}" \
            TEST_SUITE_TIMING_LEDGER="${TEST_SUITE_TIMING_LEDGER:-$REPO_ROOT/logs/test_suite_timing_ledger.tsv}" \
              bash "$REPO_ROOT/scripts/test_suite_timing_ledger_write.sh" --pair \
                "$_pending_file_batch" "$_pending_suite_batch" "$_output_sha256"
        fi
        publish_run_tests_metadata "$_receipt" "$_source_head" "$_selected_paths" \
          "$_selector_input_fp" "$_mode" "$REPO_ROOT" "$_run_id" "$_source_head" "$_source_fp"
        rm -f "$_pending_file_batch" "$_pending_suite_batch"
        rm -f "$_selected_paths"
        # This branch runs under nounset.  A truncated/missing receipt must
        # therefore have a value before any parser or validator can fail.
        # Invalid receipt identity is an infrastructure BLOCK (rc=2), never a
        # guessed test failure rc=1 and never an unbound-variable abort.
        _receipt_rc=2
        if _parsed_receipt_rc="$(read_run_tests_receipt_rc "$_receipt" 2>/dev/null)"; then
            _receipt_rc="$_parsed_receipt_rc"
        fi
        if ! validate_run_tests_terminal_receipt "$_receipt" >/dev/null; then
            printf 'TEST_RECEIPT_FAIL path=%s\n' "$_receipt" >&2
            [ "$_receipt_rc" -ne 0 ] || _receipt_rc=1
            exit "$_receipt_rc"
        fi
        if [ "$_receipt_rc" -ne 0 ]; then
            printf 'TEST_RECEIPT_FAIL path=%s rc=%s\n' "$_receipt" "$_receipt_rc" >&2
            exit "$_receipt_rc"
        fi
        verify_run_tests_receipt "$_receipt" >/dev/null \
            || { printf 'TEST_RECEIPT_FAIL path=%s rc=%s\n' "$_receipt" "$_rc" >&2; exit 1; }
        if [ -n "$_requested_tap" ]; then
            mkdir -p "$(dirname "$_requested_tap")"
            _tap_source="$_tap"
            if [ ! -s "$_tap_source" ]; then
                _tap_source=$(python3 - "$_receipt" <<'PY'
import json,sys
print(json.load(open(sys.argv[1], encoding="utf-8")).get("artifact", ""))
PY
)
            fi
            [ -n "$_tap_source" ] && [ -s "$_tap_source" ] || { printf 'TEST_TAP_FAIL internal TAP/artifact missing\n' >&2; exit 1; }
            cp "$_tap_source" "$_requested_tap"
            [ -s "$_requested_tap" ] || { printf 'TEST_TAP_FAIL requested TAP missing: %s\n' "$_requested_tap" >&2; exit 1; }
        fi
        python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); scope=(d.get("run_manifest") or {}).get("scope_identity") or {}; print("TEST_RECEIPT_PASS path={} rc={} tests={}/{} skip={} sha256={} duration_ms={} files_selected={} files_discovered={} files_executed={} complete={} full_scope={}".format(sys.argv[1],d["rc"],d["observed_test_count"],d["declared_test_count"],d["skip_count"],d["output_sha256"],d["duration_ms"],scope.get("selected_file_count"),scope.get("discovered_file_count"),scope.get("executed_file_count"),"1" if scope.get("complete") else "0","1" if scope.get("full_scope") else "0"))' "$_receipt"
        [ "$_singleflight" != 1 ] || [ -z "$_snapshot" ] || rm -f "$_snapshot"
        exit "$_rc"
    fi
fi
