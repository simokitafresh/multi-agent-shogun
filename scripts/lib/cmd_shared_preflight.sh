#!/usr/bin/env bash
# Shared, read-only preflight gates used by cmd_save and cmd_publish.
# test_necessity: cmd_save --preflight and cmd_publish must apply the same lesson-cap contract.

CMD_SHARED_PREFLIGHT_GATES=(lesson_cap)

cmd_shared_count_active_shogun_lessons() {
    local lessons_file="${1:-}"
    [[ -f "$lessons_file" ]] || {
        echo 0
        return 0
    }
    awk 'BEGIN { count = 0 } /^- id:/ { count++ } /superseded_by:/ { count-- } END { print (count > 0 ? count : 0) }' "$lessons_file" 2>/dev/null || echo 0
}

cmd_shared_preflight() {
    local lessons_file="${1:-}"
    local lesson_limit="${2:-35}"
    local lesson_count lesson_block_at lesson_max_pass

    lesson_count="$(cmd_shared_count_active_shogun_lessons "$lessons_file")"
    [[ "$lesson_count" =~ ^[0-9]+$ ]] || lesson_count=0
    [[ "$lesson_limit" =~ ^[0-9]+$ ]] || lesson_limit=35
    lesson_block_at=$((lesson_limit - 2))
    lesson_max_pass=$((lesson_block_at - 1))

    if (( lesson_count >= lesson_block_at )); then
        echo "BLOCK: lessons_shogun.yaml が ${lesson_count}件。active件数を ${lesson_max_pass}件以下にせよ(${lesson_block_at}件以上でBLOCK、上限${lesson_limit}件)。" >&2
        echo "  解消: 既存LSを統合し、active件数を${lesson_max_pass}件以下にしてから再実行。" >&2
        echo "  参考: bash scripts/lesson_write_shogun.sh --supersedes LS旧 LS新 \"統合理由\"" >&2
        return 1
    fi
    return 0
}
