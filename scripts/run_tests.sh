#!/usr/bin/env bash
# run_tests.sh — テスト実行ラッパー（並列化自動適用）
# 誰が実行しても --jobs 8 が適用される。直接batsを呼ぶな。
#
# Usage:
#   bash scripts/run_tests.sh              # unit + top-level 全量
#   bash scripts/run_tests.sh unit         # unit のみ
#   bash scripts/run_tests.sh file <path>  # 特定ファイル
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JOBS=8

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
    *)
        echo "Usage: bash scripts/run_tests.sh [all|unit|file <path>]" >&2
        exit 1
        ;;
esac
