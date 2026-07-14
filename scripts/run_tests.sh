#!/usr/bin/env bash
# run_tests.sh — テスト実行ラッパー（並列化自動適用）
# 誰が実行しても --jobs 8 が適用される。直接batsを呼ぶな。
#
# Usage:
#   bash scripts/run_tests.sh              # unit + top-level 全量
#   bash scripts/run_tests.sh unit         # unit のみ
#   bash scripts/run_tests.sh affected     # git diffから影響テストのみ
#   bash scripts/run_tests.sh file <path>  # 特定ファイル
set -euo pipefail

# REPO_ROOT: テスト容易性のため既存環境変数があれば優先する(test_heavy_job_admission.bats
# がFAIL fixtureをtests/unit/相当のディレクトリに用意しexit code集約を検証する用途)。
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
JOBS="${BATS_JOBS:-8}"
FILE_JOBS="${BATS_FILE_JOBS:-32}"
INNER_JOBS="${BATS_INNER_JOBS:-4}"
# A runner may split the suite into many bats roots, but the aggregate number
# of live tests must still honour the public --jobs 8 contract.  The previous
# default (128) let a 2-core CI runner launch 64 tests from one "heavy" file
# while other files were also live, producing timeout/cross-fixture cascades.
MAX_TEST_JOBS="${BATS_MAX_TEST_JOBS:-8}"
BATS_CACHE="${BATS_CACHE:-1}"
BATS_CACHE_DIR="${BATS_CACHE_DIR:-$REPO_ROOT/.cache/bats}"

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
    local total="${#files[@]}"
    local out_dir pid file failed file_inner_jobs file_weight active_weight running_pids
    local source_fp cache_key cache_path cached_count launched_count timing_path out manifest stats
    local -a pids=()
    local -a all_pids=()
    local -A pid_file=()
    local -A pid_out=()
    local -A pid_weight=()
    local -A pid_cache_path=()
    local -A pid_time=()

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
            bats "$test_file" --jobs "$test_jobs" --timing 3>&-
    }

    if [ "$total" -eq 0 ]; then
        echo "No test files selected."
        return 0
    fi

    if [ "${BATS_SPLIT_FILES:-1}" != "1" ]; then
        bats "${files[@]}" --jobs "$JOBS" --timing
        return $?
    fi

    out_dir="$(mktemp -d "${TMPDIR:-/tmp}/shogun-bats.XXXXXX")"
    failed=0
    active_weight=0
    cached_count=0
    launched_count=0
    source_fp="$(bats_source_fingerprint)"
    mapfile -t files < <(order_bats_files_lpt "$source_fp" "${files[@]}")
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
        wait -n -p finished_pid || rc=$?
        if [ "$rc" -eq 127 ]; then
            return 0
        fi
        [ "$rc" -eq 0 ] || failed=1
        for pid in "${pids[@]}"; do
            [ "$pid" = "$finished_pid" ] || next+=("$pid")
        done
        pids=("${next[@]}")
        reap_finished
    }

    local -a queued_files=("${files[@]}") queued_inner=() queued_weight=() queued_cache=()
    local idx selected pending_count
    for file in "${queued_files[@]}"; do
        file_inner_jobs="$INNER_JOBS"
        file_weight="$INNER_JOBS"
        case "$(basename "$file")" in
            test_cmd_save.bats|test_gate_shogun_startup.bats|test_semantic_index_update.bats|test_deploy_task_ac_handling.bats)
                file_inner_jobs="${BATS_HEAVY_INNER_JOBS:-64}"
                file_weight="$file_inner_jobs"
                ;;
        esac
        case "$(basename "$file")" in
            test_cmd_complete_gate_small_consolidated.bats|test_cmd_quality_memory_db.bats|test_cmd_save_diagnosis_quality.bats|test_cmd_save_warn_logging.bats|test_insight_write.bats|test_session_state_hooks.bats|test_three_layer_preflight.bats|test_gunshi_log_append_obs.bats|test_ninja_monitor_stall.bats)
                file_inner_jobs="${BATS_ISOLATED_INNER_JOBS:-8}"
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
        if [ "$selected" -lt 0 ]; then
            wait_for_one
            continue
        fi
        file="${queued_files[$selected]}"
        file_inner_jobs="${queued_inner[$selected]}"
        file_weight="${queued_weight[$selected]}"
        cache_path="${queued_cache[$selected]}"
        queued_files[$selected]=""
        pending_count=$((pending_count - 1))
        timing_path="$out_dir/$(basename "$file").$$.time"
        (
            _started_ns="$(date +%s%N)"
            _rc=0
            run_bats_file_isolated "$file" "$file_inner_jobs" || _rc=$?
            printf '%s\t%s\n' "$_started_ns" "$(date +%s%N)" >"$timing_path"
            exit "$_rc"
        ) >"$out_dir/$(basename "$file").$$.out" 2>&1 &
        pid=$!
        if [ -n "${BATS_SCHEDULER_TRACE:-}" ]; then
            printf '%s\t%s\t%s\n' "$(basename "$file")" "$file_weight" "$active_weight" >>"$BATS_SCHEDULER_TRACE"
        fi
        launched_count=$((launched_count + 1))
        pids+=("$pid")
        all_pids+=("$pid")
        pid_file["$pid"]="$file"
        pid_out["$pid"]="$out_dir/$(basename "$file").$$.out"
        pid_weight["$pid"]="$file_weight"
        pid_cache_path["$pid"]="$cache_path"
        pid_time["$pid"]="$timing_path"
    done

    for pid in "${pids[@]}"; do
        if wait "$pid" 2>/dev/null; then
            :
        else
            failed=1
        fi
    done

    manifest="$(mktemp "${TMPDIR:-/tmp}/shogun-manifest.XXXXXX")"
    stats="$(mktemp "${TMPDIR:-/tmp}/shogun-stats.XXXXXX")"
    [ -z "${BATS_TAP_OUTPUT:-}" ] || : >"$BATS_TAP_OUTPUT"
    for pid in "${all_pids[@]}"; do
        printf '%s\t%s\t%s\t%s\t0\n' "$pid" "${pid_file[$pid]}" "${pid_out[$pid]}" "${pid_time[$pid]}" >>"$manifest"
    done
    aggregate_bats_outputs "$manifest" "$stats"

    if [ "$failed" -ne 0 ]; then
        echo "One or more bats files failed:" >&2
        for pid in "${all_pids[@]}"; do
            out="${pid_out[$pid]}"
            file="${pid_file[$pid]}"
            if awk -F '\t' -v p="$pid" '$1==p && $5>0 {found=1} END{exit !found}' "$stats"; then
                echo "==== $file ====" >&2
                tail -120 "$out" >&2
            fi
        done
        return 1
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
          "$run_id" "$(basename "$REPO_ROOT")" "$commit_sha" "$mode" bats \
          "$file" "$test_count" "$wall_sec" "$status" "$skip_count" "$cache_hit" \
          "$source_fp" "$measured_at" "mode=$mode;jobs=$MAX_TEST_JOBS" >>"$batch"
    done
    TEST_TIMING_LEDGER="${TEST_TIMING_LEDGER:-$REPO_ROOT/logs/test_timing_ledger.tsv}" \
      bash "$REPO_ROOT/scripts/test_timing_ledger_write.sh" "$batch"
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
    if [[ "${SHOGUN_HEAVY_JOB_LOCK_HELD:-0}" != "1" && "${1:-}" != "file" ]]; then
        local _self="${BASH_SOURCE[0]:-$0}"
        exec bash "$(dirname "$_self")/heavy_job_admission.sh" -- bash "$_self" "$@"
    fi

    sweep_stale_embedded_test_tmp

    case "${1:-all}" in
        all)
            RUN_TESTS_MODE=all
            mapfile -t test_files < <(
                find "$REPO_ROOT/tests/unit" -maxdepth 1 -name '*.bats' -type f -print
                find "$REPO_ROOT/tests" -maxdepth 1 -name '*.bats' -type f -print
            )
            run_bats_files_parallel "${test_files[@]}"
            ;;
        unit)
            RUN_TESTS_MODE=unit
            mapfile -t test_files < <(find "$REPO_ROOT/tests/unit" -maxdepth 1 -name '*.bats' -type f -print)
            run_bats_files_parallel "${test_files[@]}"
            ;;
        file)
            shift
            bats "$@" --jobs "$JOBS" --timing
            ;;
        affected)
            shift || true
            mapfile -t selected < <(bash "$REPO_ROOT/scripts/test_select.sh" "$@")
            if [ "${#selected[@]}" -eq 0 ]; then
                echo "No affected tests selected."
                exit 0
            fi
            printf 'Selected %s affected test file(s).\n' "${#selected[@]}"
            bats "${selected[@]}" --jobs "$JOBS" --timing
            ;;
        *)
            echo "Usage: bash scripts/run_tests.sh [all|unit|affected|file <path>]" >&2
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    _run_tests_main "$@"
fi
