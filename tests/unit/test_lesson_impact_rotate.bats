#!/usr/bin/env bats
# test_necessity: Rotation writes temp file beside TSV before atomic rename; violation is BLOCK.

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

@test "cmd_karo_hotfix_lesson_impact_yaml_dump: --sync-counters on a flow-style lessons.yaml does not change line count or style" {
    mkdir -p "$TEST_PROJECT/projects/fixtureproj"
    cat > "$TEST_PROJECT/projects/fixtureproj/lessons.yaml" <<'EOF'
lesson_count: 2
lessons:
- {id: L9001, title: fixture flow-style entry 1, tags: [a, b]}
- {id: L9002, title: fixture flow-style entry 2, tags: [c, d]}
EOF
    local before_lines
    before_lines="$(wc -l < "$TEST_PROJECT/projects/fixtureproj/lessons.yaml")"

    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	agent	lesson_id	action	result	referenced
2026-07-27T10:00:00	tobisaru	L9001	injected	CLEAR	yes
2026-07-27T10:05:00	tobisaru	L9001	injected	BLOCK	yes
2026-07-27T10:10:00	tobisaru	L9002	injected	CLEAR	yes
EOF

    run bash "$TEST_PROJECT/scripts/lesson_impact_analysis.sh" --sync-counters
    [ "$status" -eq 0 ]

    local after_lines
    after_lines="$(wc -l < "$TEST_PROJECT/projects/fixtureproj/lessons.yaml")"
    # LINE-COUNT INVARIANT: a full yaml_module.dump() rewrite would expand this
    # 4-line flow-style file to 1 line per scalar field (regression this test
    # guards against).
    [ "$before_lines" -eq "$after_lines" ]

    run grep -c '^- {' "$TEST_PROJECT/projects/fixtureproj/lessons.yaml"
    [ "$output" = "2" ]
    run grep -c '^- id:' "$TEST_PROJECT/projects/fixtureproj/lessons.yaml"
    [ "$output" = "0" ]

    run python3 -c "
import yaml
d = yaml.safe_load(open('$TEST_PROJECT/projects/fixtureproj/lessons.yaml'))
assert d['lessons'][0]['helpful_count'] == 1
assert d['lessons'][0]['harmful_count'] == 1
assert isinstance(d['lessons'][0]['last_referenced'], str)
assert d['lessons'][1]['helpful_count'] == 1
assert d['lessons'][1]['harmful_count'] == 0
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == "OK" ]]
}

@test "cmd_karo_hotfix_lesson_impact_yaml_dump: --sync-counters updates counters on a block-style lessons.yaml in place" {
    mkdir -p "$TEST_PROJECT/projects/fixtureproj2"
    cat > "$TEST_PROJECT/projects/fixtureproj2/lessons.yaml" <<'EOF'
lesson_count: 2
lessons:
- id: L9003
  title: fixture block-style entry 1
  tags:
  - a
  - b
- id: L9004
  title: fixture block-style entry 2
  tags:
  - c
EOF

    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	agent	lesson_id	action	result	referenced
2026-07-27T10:00:00	tobisaru	L9003	injected	CLEAR	yes
2026-07-27T10:10:00	tobisaru	L9004	injected	BLOCK	yes
EOF

    run bash "$TEST_PROJECT/scripts/lesson_impact_analysis.sh" --sync-counters
    [ "$status" -eq 0 ]

    run python3 -c "
import yaml
d = yaml.safe_load(open('$TEST_PROJECT/projects/fixtureproj2/lessons.yaml'))
assert d['lessons'][0]['helpful_count'] == 1
assert d['lessons'][0]['harmful_count'] == 0
assert d['lessons'][1]['helpful_count'] == 0
assert d['lessons'][1]['harmful_count'] == 1
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == "OK" ]]

    # No stray blank line is introduced before the appended fields of the last
    # entry (regression guard for the trailing-newline split() artifact).
    run grep -c '^$' "$TEST_PROJECT/projects/fixtureproj2/lessons.yaml"
    [ "$output" = "0" ]
}

@test "cmd_karo_hotfix_lesson_impact_yaml_dump: --sync-counters is idempotent (line count stable across repeated runs)" {
    mkdir -p "$TEST_PROJECT/projects/fixtureproj3"
    cat > "$TEST_PROJECT/projects/fixtureproj3/lessons.yaml" <<'EOF'
lesson_count: 1
lessons:
- {id: L9005, title: fixture idempotency entry}
EOF
    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	agent	lesson_id	action	result	referenced
2026-07-27T10:00:00	tobisaru	L9005	injected	CLEAR	yes
EOF

    run bash "$TEST_PROJECT/scripts/lesson_impact_analysis.sh" --sync-counters
    [ "$status" -eq 0 ]
    local first_lines
    first_lines="$(wc -l < "$TEST_PROJECT/projects/fixtureproj3/lessons.yaml")"

    run bash "$TEST_PROJECT/scripts/lesson_impact_analysis.sh" --sync-counters
    [ "$status" -eq 0 ]
    local second_lines
    second_lines="$(wc -l < "$TEST_PROJECT/projects/fixtureproj3/lessons.yaml")"

    [ "$first_lines" -eq "$second_lines" ]
    run grep -o 'helpful_count: [0-9]*' "$TEST_PROJECT/projects/fixtureproj3/lessons.yaml"
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]
}

@test "lesson_impact_analysis filters candidate sections to actual low-ref and block cases" {
    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-07-01T00:00:01	cmd_1	saizo	L001	injected	CLEAR	yes	infra	exact	routine
2026-07-01T00:00:02	cmd_2	saizo	L001	injected	CLEAR	yes	infra	exact	routine
2026-07-01T00:00:03	cmd_3	saizo	L002	injected	CLEAR	no	infra	exact	routine
2026-07-01T00:00:04	cmd_4	saizo	L002	injected	CLEAR	no	infra	exact	routine
2026-07-01T00:00:05	cmd_5	saizo	L002	injected	CLEAR	no	infra	exact	routine
2026-07-01T00:00:06	cmd_6	saizo	L003	injected	BLOCK	no	infra	exact	routine
2026-07-01T00:00:07	cmd_7	saizo	L003	injected	CLEAR	no	infra	exact	routine
2026-07-01T00:00:08	cmd_8	saizo	L003	injected	CLEAR	no	infra	exact	routine
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
