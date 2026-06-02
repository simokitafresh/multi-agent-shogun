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

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JOBS="${BATS_JOBS:-8}"
FILE_JOBS="${BATS_FILE_JOBS:-32}"
INNER_JOBS="${BATS_INNER_JOBS:-4}"
MAX_TEST_JOBS="${BATS_MAX_TEST_JOBS:-128}"
BATS_CACHE="${BATS_CACHE:-1}"
BATS_CACHE_DIR="${BATS_CACHE_DIR:-$REPO_ROOT/.cache/bats}"

bats_source_fingerprint() {
    if [ -n "${BATS_SOURCE_FINGERPRINT:-}" ]; then
        printf '%s\n' "$BATS_SOURCE_FINGERPRINT"
        return 0
    fi
    (
        cd "$REPO_ROOT"
        git ls-files scripts lib tests/helpers 2>/dev/null \
            | grep -v '^scripts/run_tests.sh$' \
            | sort \
            | xargs -r sha256sum
    ) | sha256sum | awk '{print $1}'
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
            test_cmd_complete_gate_small_consolidated.bats|test_cmd_quality_memory_db.bats|test_cmd_save_diagnosis_quality.bats|test_cmd_save_warn_logging.bats|test_insight_write.bats|test_session_state_hooks.bats)
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
            bats "$file" --jobs "$file_inner_jobs" --timing
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
