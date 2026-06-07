#!/bin/bash
# reset_harmful_counts.sh
# One-shot: reset harmful_count to 0 in selected project lessons.

set -euo pipefail

# cmd_training_speed_oneshot_reset_harmful_counts_20260607143225: サブシェル不要の純bash文字列演算でSCRIPT_DIR解決
_RHC_SELF="${BASH_SOURCE[0]}"
[[ "$_RHC_SELF" != /* ]] && _RHC_SELF="$PWD/$_RHC_SELF"
SCRIPT_DIR="${_RHC_SELF%/scripts/oneshot/reset_harmful_counts.sh}"
TARGET_FILES=(
    "$SCRIPT_DIR/projects/infra/lessons.yaml"
    "$SCRIPT_DIR/projects/dm-signal/lessons.yaml"
)

for file in "${TARGET_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "ERROR: file not found: $file" >&2
        exit 1
    fi
done

for file in "${TARGET_FILES[@]}"; do
    total_count=$(rg -c '^[[:space:]]*harmful_count:' "$file" 2>/dev/null || true)
    nonzero_before=$(rg -c '^[[:space:]]*harmful_count:[[:space:]]*[1-9][0-9]*' "$file" 2>/dev/null || true)
    total_count=${total_count:-0}
    nonzero_before=${nonzero_before:-0}

    perl -i -pe 's/^(\s*harmful_count:\s*)\d+\s*$/${1}0/' "$file"

    nonzero_after=$(rg -c '^[[:space:]]*harmful_count:[[:space:]]*[1-9][0-9]*' "$file" 2>/dev/null || true)
    nonzero_after=${nonzero_after:-0}

    if [ "$nonzero_after" -ne 0 ]; then
        echo "ERROR: reset verification failed: $file (remaining non-zero: $nonzero_after)" >&2
        exit 1
    fi

    echo "RESET: $file (harmful_count lines=$total_count, non-zero before=$nonzero_before, after=0)"
done

echo "DONE: harmful_count reset completed."
