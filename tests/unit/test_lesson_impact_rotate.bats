#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_ROTATE="$PROJECT_ROOT/scripts/lesson_impact_rotate.sh"
    export SRC_ANALYSIS="$PROJECT_ROOT/scripts/lesson_impact_analysis.sh"
    export SRC_LOCK_PATH="$PROJECT_ROOT/scripts/lib/lock_path.sh"
    [ -f "$SRC_ROTATE" ] || return 1
    [ -f "$SRC_ANALYSIS" ] || return 1
    [ -f "$SRC_LOCK_PATH" ] || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/lesson_impact_rotate.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    mkdir -p "$TEST_PROJECT/scripts/lib" "$TEST_PROJECT/logs"
    cp "$SRC_ROTATE" "$TEST_PROJECT/scripts/lesson_impact_rotate.sh"
    cp "$SRC_ANALYSIS" "$TEST_PROJECT/scripts/lesson_impact_analysis.sh"
    cp "$SRC_LOCK_PATH" "$TEST_PROJECT/scripts/lib/lock_path.sh"
    chmod +x "$TEST_PROJECT/scripts/lesson_impact_rotate.sh" "$TEST_PROJECT/scripts/lesson_impact_analysis.sh"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

write_impact_rows() {
    python3 - "$TEST_PROJECT/logs/lesson_impact.tsv" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
with path.open("w", encoding="utf-8") as f:
    f.write("timestamp\tcmd_id\tninja\tlesson_id\taction\tresult\treferenced\tproject\ttask_type\tbloom_level\n")
    for i in range(1, 2006):
        f.write(f"2026-05-22T00:00:{i % 60:02d}\tcmd_{i}\tsaizo\tL{i % 7:03d}\tinjected\tCLEAR\tyes\tinfra\texact\troutine\n")
PY
}

@test "lesson_impact_rotate writes temp file beside TSV before atomic rename" {
    run grep -F 'mktemp "$tsv_dir/.lesson_impact.XXXXXX.tmp"' "$SRC_ROTATE"
    [ "$status" -eq 0 ]

    run grep -F 'mv -f "$tmpfile" "$TSV_FILE"' "$SRC_ROTATE"
    [ "$status" -eq 0 ]
}

@test "lesson_impact_rotate keeps TSV readable by analysis immediately after rotate" {
    write_impact_rows

    run bash "$TEST_PROJECT/scripts/lesson_impact_rotate.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[lesson_impact_rotate] archived=5 lines, kept=2000 lines"* ]]

    run wc -l "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" == "2001 "* ]]

    run bash "$TEST_PROJECT/scripts/lesson_impact_analysis.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"=== Lesson Impact Analysis ==="* ]]
    [[ "$output" == *"Total injections: 2000"* ]]
}

@test "lesson_impact_analysis filters candidate sections to actual low-ref and block cases" {
    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-07-01T00:00:01	cmd_1	saizo	L001	injected	CLEAR	yes	infra	exact	routine
2026-07-01T00:00:02	cmd_2	saizo	L001	injected	CLEAR	yes	infra	exact	routine
2026-07-01T00:00:03	cmd_3	saizo	L002	injected	CLEAR	no	infra	exact	routine
2026-07-01T00:00:04	cmd_4	saizo	L002	injected	CLEAR	no	infra	exact	routine
2026-07-01T00:00:05	cmd_5	saizo	L003	injected	BLOCK	no	infra	exact	routine
EOF

    run bash "$TEST_PROJECT/scripts/lesson_impact_analysis.sh"
    [ "$status" -eq 0 ]
    low_section="$(printf '%s\n' "$output" | awk '/^Low Reference Rate/,/^$/')"
    high_section="$(printf '%s\n' "$output" | awk '/^High BLOCK Rate/,/^$/')"

    [[ "$low_section" == *"L002"* ]]
    [[ "$low_section" == *"L003"* ]]
    [[ "$low_section" != *"L001"* ]]
    [[ "$high_section" == *"L003"* ]]
    [[ "$high_section" != *"L001"* ]]
    [[ "$high_section" != *"L002"* ]]
}
