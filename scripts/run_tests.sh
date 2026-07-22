#!/usr/bin/env bash
# cmd_karo_hotfix_test_runner_drvfs_admission_20260723_normal
# run_tests.sh — テスト実行ラッパー（並列化自動適用）
# 誰が実行しても --jobs 8 が適用される。直接batsを呼ぶな。
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
        raise ValueError(f"scope path outside repository: {raw}")
    relative = os.path.relpath(resolved, root)
    if relative not in seen:
        seen.add(relative)
        sys.stdout.buffer.write(relative.encode() + b"\0")
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
project = str(task.get("project") or "infra").strip()
if project == "infra":
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
            print pid "\t" file "\t" tests "\t" skip "\t" abnormal > stats
        }
    ' "$manifest"
}

run_bats_files_parallel() {
    local -a files=("$@")
    if [[ -n "${RUN_TESTS_SELECTED_PATHS_FILE:-}" ]]; then
        : > "$RUN_TESTS_SELECTED_PATHS_FILE"
        local selected_path
        for selected_path in "${files[@]}"; do
            printf '%s\n' "${selected_path#"$REPO_ROOT"/}" >> "$RUN_TESTS_SELECTED_PATHS_FILE"
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
        env -u RUN_TESTS_BATS_BIN \
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
            test_cmd_quality_memory_db.bats|test_cmd_save_diagnosis_quality.bats|test_cmd_save_warn_logging.bats|test_session_state_hooks.bats|test_three_layer_preflight.bats|test_gunshi_log_append_obs.bats|test_ninja_monitor_stall.bats|test_hook_dispatchers.bats|test_statusline.bats|test_sqlite3_cli_removal.bats|test_small_workflow_consolidated.bats|test_skill_recommend_metrics.bats|test_gate_shogun_startup.bats|test_heavy_job_admission.bats|test_daemon_maintenance_lock.bats|test_heavy_job_classifier_newline.bats|test_cmd_complete_insight_consumption.bats|test_pending_approval.bats|test_pre_bash_guard1_git_commit_tokenizer.bats|test_ninja_scope_commit.bats|test_deploy_task_template_generation.bats|test_campaign_lane_shard_item.bats)
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
        local finished_pid="" rc=0 pid next=()
        # A very short child may exit before wait -n is entered.  In that
        # case wait -n can report 127 while bookkeeping still contains an
        # unwaited PID.  Fall back to waiting for the first tracked child so
        # the scheduler always makes progress without probing or signalling.
        wait -n -p finished_pid "${pids[@]}" || rc=$?
        if [ "$rc" -eq 127 ] || [ -z "$finished_pid" ]; then
            finished_pid="${pids[0]}"
            rc=0
            wait "$finished_pid" || rc=$?
        fi
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
            test_cmd_quality_memory_db.bats|test_cmd_save_diagnosis_quality.bats|test_cmd_save_warn_logging.bats|test_session_state_hooks.bats|test_three_layer_preflight.bats|test_gunshi_log_append_obs.bats|test_ninja_monitor_stall.bats|test_hook_dispatchers.bats|test_statusline.bats|test_sqlite3_cli_removal.bats|test_small_workflow_consolidated.bats|test_skill_recommend_metrics.bats)
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
            if [ "$failed" -ne 0 ]; then
                # Close the queue immediately, but let already-admitted light
                # files finish under their existing per-file timeout.  Heavy
                # files consume the full budget and therefore never overlap.
                pending_count=0
                break
            fi
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
    [ -z "${BATS_TAP_OUTPUT:-}" ] || : >"$BATS_TAP_OUTPUT"
    for pid in "${all_pids[@]}"; do
        printf '%s\t%s\t%s\t%s\t0\n' "$pid" "${pid_file[$pid]}" "${pid_out[$pid]}" "${pid_time[$pid]}" >>"$manifest"
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
    run_id="$(date -u +%Y%m%dT%H%M%S).$$"
    commit_sha="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf unknown)"
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
    TEST_TIMING_LEDGER="${TEST_TIMING_LEDGER:-$REPO_ROOT/logs/test_timing_ledger.tsv}" \
      bash "$REPO_ROOT/scripts/test_timing_ledger_write.sh" "$batch"
    local suite_ended_ns suite_wall_sec sum_file_sec suite_batch
    suite_ended_ns="$(date +%s%N)"
    suite_wall_sec="$(awk -v a="$suite_started_ns" -v b="$suite_ended_ns" 'BEGIN {printf "%.3f", (b-a)/1000000000}')"
    sum_file_sec="$(awk -F '\t' '{s+=$8} END {printf "%.3f", s+0}' "$batch")"
    suite_batch="$(mktemp "${TMPDIR:-/tmp}/shogun-suite-timing.XXXXXX")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\tpass\t%s\t%s\n' \
      "$run_id" "${REPO_ROOT##*/}" "$commit_sha" "$mode" "$suite_wall_sec" \
      "$sum_file_sec" "$total" "$source_fp" "$measured_at" >"$suite_batch"
    TEST_SUITE_TIMING_LEDGER="${TEST_SUITE_TIMING_LEDGER:-$REPO_ROOT/logs/test_suite_timing_ledger.tsv}" \
      bash "$REPO_ROOT/scripts/test_suite_timing_ledger_write.sh" "$suite_batch"
    rm -f "$suite_batch"
    rm -f "$batch"
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

verify_run_tests_receipt() {
    python3 - "$1" <<'PY'
import hashlib, json, re, sys
try:
    d=json.load(open(sys.argv[1], encoding='utf-8'))
    required={'version','complete','result','rc','duration_ms','output_sha256',
              'declared_test_count','observed_test_count','skip_count','artifact',
              'signal','command','source_head','test_paths'}
    if d.get('version') == 3: required.update({'drvfs_p9_client_rpc','run_manifest'})
    elif 'drvfs_p9_client_rpc' in d: required.add('drvfs_p9_client_rpc')
    if set(d) != required or d.get('version') not in (2,3): raise ValueError('schema')
    if not re.fullmatch(r'[0-9a-f]{40}', d['source_head']): raise ValueError('source_head')
    if not isinstance(d['test_paths'], list) or not all(isinstance(x,str) and x for x in d['test_paths']):
        raise ValueError('test_paths')
    if d['version'] == 3:
        m=d['run_manifest']
        if not isinstance(m,dict) or set(m) != {'cache','commit_sha','selector_input_fingerprint','selected_paths_fingerprint','estimated_cost'}:
            raise ValueError('run_manifest')
    actual=hashlib.sha256(open(d['artifact'],'rb').read()).hexdigest()
    valid=(actual == d['output_sha256'] and d['complete'] is True and
           d['result'] == 'PASS' and d['rc'] == 0 and d['skip_count'] == 0 and
           (d['declared_test_count'] == 0 or d['observed_test_count'] == d['declared_test_count']))
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
    if d.get('version') == 3: required.update({'drvfs_p9_client_rpc','run_manifest'})
    elif 'drvfs_p9_client_rpc' in d: required.add('drvfs_p9_client_rpc')
    if set(d) != required or d.get('version') not in (2,3): raise ValueError('schema')
    if not re.fullmatch(r'[0-9a-f]{40}', d['source_head']): raise ValueError('source_head')
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

emit_run_tests_terminal_receipt() {
    local receipt="$1"
    shift
    validate_run_tests_terminal_receipt "$receipt" >/dev/null || {
        printf 'TEST_RECEIPT_BLOCK path=%s rc=2\n' "$receipt" >&2
        return 2
    }
    python3 - "$receipt" "$@" <<'PY'
import json, sys
path=sys.argv[1]; suffix=" ".join(sys.argv[2:])
d=json.load(open(path, encoding="utf-8")); rc=d["rc"]
label="PASS" if rc == 0 else "FAIL"
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
            bash "$REPO_ROOT/scripts/test_select.sh" "${_sf_scoped[@]}" \
                | while IFS= read -r _sf_path; do realpath --canonicalize-missing -- "$_sf_path"; done \
                | sort -u
            ;;
        *) return 1 ;;
    esac
}

publish_run_tests_metadata() {
    python3 - "$1" "$2" "$3" "$4" <<'PY'
import hashlib, json, os, sys, tempfile
path, head, paths_file, selector_input_fp=sys.argv[1:]
d=json.load(open(path, encoding='utf-8'))
paths=[]
if os.path.isfile(paths_file):
    paths=[line.strip() for line in open(paths_file, encoding='utf-8') if line.strip()]
selected_blob=('\n'.join(paths)+'\n').encode()
cache={'enabled': os.environ.get('BATS_CACHE','1') != '0',
       'directory': os.environ.get('BATS_CACHE_DIR','')}
d.update(version=3, source_head=head, test_paths=paths,
         run_manifest={'cache': cache, 'commit_sha': head,
                       'selector_input_fingerprint': selector_input_fp,
                       'selected_paths_fingerprint': hashlib.sha256(selected_blob).hexdigest(),
                       'estimated_cost': {'selected_files': len(paths)}})
artifact=d.get('artifact', '')
p9={'persistent': False, 'probe_timeout_sec': None, 'pids': []}
try:
    with open(artifact, encoding='utf-8', errors='replace') as fh:
        for line in fh:
            if line.startswith('DRVFS_P9_STATE '):
                fields=dict(item.split('=',1) for item in line.split()[1:] if '=' in item)
                p9['persistent']=fields.get('persistent') == '1'
                p9['probe_timeout_sec']=int(fields['probe_timeout_sec'])
                p9['pids']=[] if fields.get('pids') == 'none' else fields.get('pids','').split(',')
except (OSError, ValueError):
    pass
d['drvfs_p9_client_rpc']=p9
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
        exec bash "$(dirname "$_self")/heavy_job_admission.sh" -- \
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
            if [[ -n "${RUN_TESTS_SELECTED_PATHS_FILE:-}" ]]; then
                : > "$RUN_TESTS_SELECTED_PATHS_FILE"
                printf '%s\n' "$@" >> "$RUN_TESTS_SELECTED_PATHS_FILE"
            fi
            # file mode is commonly invoked from a bats regression suite. Do
            # not let the nested bats root inherit the outer root's formatter
            # transport: otherwise nested TAP is counted as outer tests and
            # bats reports "Executed N instead of expected M tests" even when
            # both roots completed successfully.
            env \
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
                "${RUN_TESTS_BATS_BIN:-bats}" "$@" --jobs "$JOBS" --timing 3>&-
            ;;
        affected)
            shift || true
            local _selector_log _selector_rc _selector_output
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
            if [ "${#selected[@]}" -eq 0 ]; then
                echo "TEST_SELECTION result=selected reason=no_mapped_tests files=0"
                exit 0
            fi
            printf 'TEST_SELECTION result=selected reason=changed_files files=%s\n' "${#selected[@]}"
            RUN_TESTS_MODE=affected
            run_bats_files_parallel "${selected[@]}"
            ;;
        task)
            shift || true
            [ "$#" -eq 1 ] || { echo "Usage: bash scripts/run_tests.sh task <task_yaml>" >&2; exit 2; }
            [ -r "$1" ] || { echo "BLOCK: task scope file is unreadable: $1" >&2; exit 2; }
            local _scope_tmp _scope_rc
            _scope_tmp="$(mktemp)"
            set +e
            task_scope_paths "$1" >"$_scope_tmp"
            _scope_rc=$?
            set -e
            if [ "$_scope_rc" -ne 0 ]; then
                rm -f "$_scope_tmp"
                echo "BLOCK: task scope could not be resolved" >&2
                exit 2
            fi
            mapfile -d '' -t scoped_paths <"$_scope_tmp"
            rm -f "$_scope_tmp"
            [ "${#scoped_paths[@]}" -gt 0 ] || { echo "BLOCK: task scope is empty" >&2; exit 2; }
            local _task_root
            _task_root="$(task_scope_root "$1")" || { echo "BLOCK: task project root could not be resolved" >&2; exit 2; }
            printf 'TEST_SCOPE result=task files=%s task=%s\n' "${#scoped_paths[@]}" "$1"
            if [ "$_task_root" != "$REPO_ROOT" ]; then
                if [ -x "$_task_root/scripts/run_tests.sh" ]; then
                    (cd "$_task_root" && bash scripts/run_tests.sh affected "${scoped_paths[@]}")
                else
                    local _external_backend=0 _external_frontend=0 _external_path
                    local -a _external_backend_tests=() _external_frontend_sources=()
                    for _external_path in "${scoped_paths[@]}"; do
                        if [[ "$_external_path" == backend/* ]]; then
                            _external_backend=1
                            [[ "$_external_path" == backend/tests/* ]] && _external_backend_tests+=("${_external_path#backend/}")
                        fi
                        if [[ "$_external_path" == frontend/* ]]; then
                            _external_frontend=1
                            _external_frontend_sources+=("${_external_path#frontend/}")
                        fi
                    done
                    if [ "$_external_backend" -eq 1 ] && [ -d "$_task_root/backend/tests" ]; then
                        printf 'TEST_SELECTION result=external runner=pytest scope=backend project_root=%s\n' "$_task_root"
                        if [ "${#_external_backend_tests[@]}" -gt 0 ]; then
                            (cd "$_task_root/backend" && python3 -m pytest -q "${_external_backend_tests[@]}") || exit $?
                        else
                            (cd "$_task_root/backend" && python3 -m pytest -q) || exit $?
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
                            [[ -n "$_fallback" && -d "$_fallback/frontend" ]] \
                                || { echo "BLOCK: persistent p9_client_rpc requires RUN_TESTS_FRONTEND_EXT4_FALLBACK" >&2; exit 2; }
                            local _fallback_fs
                            _fallback_fs="$(findmnt -n -o FSTYPE -T "$_fallback" 2>/dev/null || true)"
                            [[ "$_fallback_fs" != 9p && "$_fallback_fs" != drvfs && "$_fallback" == /tmp/* ]] \
                                || { echo "BLOCK: frontend fallback must be isolated ext4 under /tmp" >&2; exit 2; }
                            [[ -f "$_fallback/.shogun-source-head" && "$(cat "$_fallback/.shogun-source-head")" == "$(git -C "$_task_root" rev-parse HEAD)" ]] \
                                || { echo "BLOCK: frontend ext4 fallback source identity mismatch" >&2; exit 2; }
                            _frontend_root="$_fallback/frontend"
                            printf 'DRVFS_EXT4_FALLBACK result=selected root=%s receipt=required\n' "$_fallback"
                        fi
                        (cd "$_frontend_root" && npm test -- --runInBand --passWithNoTests --findRelatedTests "${_external_frontend_sources[@]}") || exit $?
                    fi
                    if [ "$_external_backend" -eq 0 ] && [ "$_external_frontend" -eq 0 ]; then
                        echo "TEST_SELECTION result=selected reason=external_scope_no_mapped_tests files=0"
                    fi
                fi
                exit $?
            fi
            local _selector_log _selector_rc _selector_output
            _selector_log="$(mktemp)"
            set +e
            _selector_output="$(bash "$REPO_ROOT/scripts/test_select.sh" "${scoped_paths[@]}" 2>"$_selector_log")"
            _selector_rc=$?
            set -e
            cat "$_selector_log" >&2
            rm -f "$_selector_log"
            [ "$_selector_rc" -eq 0 ] || { echo "BLOCK: task-scoped selector failed rc=$_selector_rc" >&2; exit 2; }
            mapfile -t selected <<<"$_selector_output"
            [ -n "$_selector_output" ] || selected=()
            if [ "${#selected[@]}" -eq 0 ]; then
                echo "TEST_SELECTION result=selected reason=task_scope_no_mapped_tests files=0"
                exit 0
            fi
            printf 'TEST_SELECTION result=selected reason=task_scope files=%s\n' "${#selected[@]}"
            RUN_TESTS_MODE=affected
            run_bats_files_parallel "${selected[@]}"
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
                validate_run_tests_terminal_receipt "$_receipt" >/dev/null \
                    || { echo "BLOCK: single-flight leader receipt invalid" >&2; exit 2; }
                printf 'SINGLE_FLIGHT_JOINED mode=%s receipt=%s\n' "$_mode" "$_receipt" >&2
                emit_run_tests_terminal_receipt "$_receipt" joined=1
                exit $?
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
            printf '%s\n%s\n%s\n%s\n' "$_receipt" "$$" "$_sf_generation" "$_sf_owner_pgid" > "$_sf_state"
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
        _source_head="$(git -C "$REPO_ROOT" rev-parse HEAD)"
        # Freeze the selector result before any test process starts. Nested
        # fixture runners must not overwrite the public run's selected set.
        printf '%s\n' "${_sf_selection:-}" | sed '/^$/d' >"$_selected_paths"
        # Resolve at this public-call boundary.  RUN_TESTS_BATS_BIN may belong
        # to an enclosing bats root; inheriting it would bypass an isolated
        # fixture's PATH and execute the wrong runner.
        _bats_bin="$(command -v bats 2>/dev/null || true)"
        [ -n "$_bats_bin" ] || { echo "BLOCK: bats executable could not be resolved" >&2; exit 2; }
        set +e
        if [ "$_singleflight" = 1 ]; then
            # The parent retains the mode lock until receipt publication, but
            # test descendants must never inherit its FD and leak the lock.
            (
                eval "exec ${_sf_fd}>&-"
                BATS_TAP_OUTPUT="$_tap" bash "$REPO_ROOT/scripts/run_with_receipt.sh" \
                    --summary-only --receipt "$_receipt" -- \
                    env PATH="${PATH:-/usr/bin:/bin}:/usr/local/bin:/usr/bin:/bin" RUN_TESTS_BATS_BIN="$_bats_bin" BATS_TAP_OUTPUT="$_tap" RUN_TESTS_SELECTED_PATHS_FILE= bash "${BASH_SOURCE[0]}" --receipt-inner "$@"
            )
        else
            BATS_TAP_OUTPUT="$_tap" bash "$REPO_ROOT/scripts/run_with_receipt.sh" \
                --summary-only --receipt "$_receipt" -- \
                env PATH="${PATH:-/usr/bin:/bin}:/usr/local/bin:/usr/bin:/bin" RUN_TESTS_BATS_BIN="$_bats_bin" BATS_TAP_OUTPUT="$_tap" RUN_TESTS_SELECTED_PATHS_FILE= bash "${BASH_SOURCE[0]}" --receipt-inner "$@"
        fi
        _rc=$?
        set -e
        publish_run_tests_metadata "$_receipt" "$_source_head" "$_selected_paths" "$_selector_input_fp"
        rm -f "$_selected_paths"
        _receipt_rc="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["rc"])' "$_receipt" 2>/dev/null || printf 1)"
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
        python3 - "$_receipt" <<'PY'
import json, sys
with open(sys.argv[1]) as fh: d=json.load(fh)
print("TEST_RECEIPT_PASS path={} rc={} tests={}/{} skip={} sha256={} duration_ms={}".format(
    sys.argv[1], d["rc"], d["observed_test_count"], d["declared_test_count"],
    d["skip_count"], d["output_sha256"], d["duration_ms"]))
PY
        [ "$_singleflight" != 1 ] || [ -z "$_snapshot" ] || rm -f "$_snapshot"
        exit "$_rc"
    fi
fi
