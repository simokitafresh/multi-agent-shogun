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

case "${1:-all}" in
    all)
        bats "$REPO_ROOT/tests/unit/" "$REPO_ROOT/tests/"*.bats --jobs "$JOBS" --timing
        ;;
    unit)
        bats "$REPO_ROOT/tests/unit/" --jobs "$JOBS" --timing
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
