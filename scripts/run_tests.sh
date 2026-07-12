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
MAX_TEST_JOBS="${BATS_MAX_TEST_JOBS:-128}"
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

run_bats_files_parallel() {
    local -a files=("$@")
    local total="${#files[@]}"
    local out_dir pid file failed file_inner_jobs file_weight active_weight running_pids
    local source_fp cache_key cache_path cached_count launched_count
    local -a pids=()
    local -a all_pids=()
    local -A pid_file=()
    local -A pid_out=()
    local -A pid_weight=()
    local -A pid_cache_path=()

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
    if [ "$BATS_CACHE" = "1" ]; then
        mkdir -p "$BATS_CACHE_DIR"
    fi

    reap_finished() {
        local running pid next=()
        running="$(jobs -rp || true)"
        active_weight=0
        for pid in "${pids[@]}"; do
            if printf '%s\n' "$running" | grep -qx "$pid"; then
                next+=("$pid")
                active_weight=$((active_weight + pid_weight[$pid]))
            fi
        done
        pids=("${next[@]}")
    }

    wait_for_capacity() {
        local required="$1"
        while true; do
            reap_finished
            if [ $((active_weight + required)) -le "$MAX_TEST_JOBS" ]; then
                return 0
            fi
            wait -n || failed=1
        done
    }

    for file in "${files[@]}"; do
        file_inner_jobs="$INNER_JOBS"
        file_weight="$INNER_JOBS"
        case "$(basename "$file")" in
            test_cmd_save.bats|test_gate_shogun_startup.bats|test_semantic_index_update.bats|test_deploy_task_ac_handling.bats)
                file_inner_jobs="${BATS_HEAVY_INNER_JOBS:-64}"
                file_weight="$file_inner_jobs"
                ;;
        esac
        case "$(basename "$file")" in
            test_cmd_complete_gate_small_consolidated.bats|test_cmd_quality_memory_db.bats|test_cmd_save_diagnosis_quality.bats|test_cmd_save_warn_logging.bats|test_insight_write.bats|test_session_state_hooks.bats|test_three_layer_preflight.bats)
                file_inner_jobs="${BATS_ISOLATED_INNER_JOBS:-8}"
                file_weight="$MAX_TEST_JOBS"
                ;;
        esac
        if [ "$file_weight" -gt "$MAX_TEST_JOBS" ]; then
            file_weight="$MAX_TEST_JOBS"
        fi
        cache_path=""
        if [ "$BATS_CACHE" = "1" ]; then
            cache_key="$(bats_cache_key "$file" "$file_inner_jobs" "$source_fp")"
            cache_path="$BATS_CACHE_DIR/$cache_key.pass"
            if [ -f "$cache_path" ]; then
                cached_count=$((cached_count + 1))
                continue
            fi
        fi
        wait_for_capacity "$file_weight"
        (
            run_bats_file_isolated "$file" "$file_inner_jobs"
        ) >"$out_dir/$(basename "$file").$$.out" 2>&1 &
        pid=$!
        launched_count=$((launched_count + 1))
        pids+=("$pid")
        all_pids+=("$pid")
        pid_file["$pid"]="$file"
        pid_out["$pid"]="$out_dir/$(basename "$file").$$.out"
        pid_weight["$pid"]="$file_weight"
        pid_cache_path["$pid"]="$cache_path"
    done

    for pid in "${pids[@]}"; do
        if wait "$pid" 2>/dev/null; then
            :
        else
            failed=1
        fi
    done

    if [ "$failed" -ne 0 ]; then
        echo "One or more bats files failed:" >&2
        for pid in "${all_pids[@]}"; do
            out="${pid_out[$pid]}"
            file="${pid_file[$pid]}"
            if [ -f "$out" ] && grep -q '^not ok ' "$out"; then
                echo "==== $file ====" >&2
                tail -120 "$out" >&2
            fi
        done
        return 1
    fi

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
            mapfile -t test_files < <(
                find "$REPO_ROOT/tests/unit" -maxdepth 1 -name '*.bats' -type f -print
                find "$REPO_ROOT/tests" -maxdepth 1 -name '*.bats' -type f -print
            )
            run_bats_files_parallel "${test_files[@]}"
            ;;
        unit)
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
