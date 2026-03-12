#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCAN_SCRIPT="$PROJECT_ROOT/scripts/lesson_deprecation_scan.sh"
    [ -f "$SRC_SCAN_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/deprecation_scan.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    export EXT_DM_SIGNAL="$TEST_TMPDIR/dm-signal"

    mkdir -p \
        "$TEST_PROJECT/scripts" \
        "$TEST_PROJECT/config" \
        "$TEST_PROJECT/logs" \
        "$TEST_PROJECT/queue/archive/cmds" \
        "$TEST_PROJECT/projects/infra" \
        "$TEST_PROJECT/projects/dm-signal" \
        "$TEST_PROJECT/tasks" \
        "$EXT_DM_SIGNAL/tasks"

    cp "$SRC_SCAN_SCRIPT" "$TEST_PROJECT/scripts/lesson_deprecation_scan.sh"
    chmod +x "$TEST_PROJECT/scripts/lesson_deprecation_scan.sh"

    cat > "$TEST_PROJECT/scripts/lesson_deprecate.sh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$(cd "$(dirname "$0")/.." && pwd)/deprecate_calls.log"
exit 0
EOF
    chmod +x "$TEST_PROJECT/scripts/lesson_deprecate.sh"

    cat > "$TEST_PROJECT/config/projects.yaml" <<EOF
projects:
  - id: infra
    path: $TEST_PROJECT
    status: active
  - id: dm-signal
    path: $EXT_DM_SIGNAL
    status: active
EOF

    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L001
    title: infra lesson
    summary: infra summary
    helpful_count: 0
    harmful_count: 0
    injection_count: 0
EOF

    cat > "$TEST_PROJECT/projects/dm-signal/lessons.yaml" <<'EOF'
lessons:
  - id: L001
    title: dm lesson
    summary: tasks/existing.txt を参照
    helpful_count: 3
    harmful_count: 0
    injection_count: 0
EOF

    cat > "$EXT_DM_SIGNAL/tasks/existing.txt" <<'EOF'
ok
EOF

    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-03-13T01:00:00	cmd_100	sasuke	L001	injected	BLOCK	no	infra	impl	routine
2026-03-13T01:01:00	cmd_101	sasuke	L001	injected	BLOCK	no	infra	impl	routine
2026-03-13T01:02:00	cmd_102	sasuke	L001	injected	BLOCK	no	infra	impl	routine
2026-03-13T01:03:00	cmd_103	sasuke	L001	injected	BLOCK	no	infra	impl	routine
2026-03-13T01:04:00	cmd_104	sasuke	L001	injected	BLOCK	no	infra	impl	routine
2026-03-13T01:05:00	cmd_105	sasuke	L001	injected	BLOCK	no	infra	impl	routine
2026-03-13T01:06:00	cmd_106	sasuke	L001	injected	BLOCK	no	infra	impl	routine
2026-03-13T01:07:00	cmd_107	sasuke	L001	injected	BLOCK	no	infra	impl	routine
2026-03-13T01:08:00	cmd_108	sasuke	L001	injected	BLOCK	no	infra	impl	routine
2026-03-13T01:09:00	cmd_109	sasuke	L001	injected	BLOCK	no	infra	impl	routine
2026-03-13T01:10:00	cmd_200	sasuke	L001	injected	BLOCK	no	dm-signal	impl	routine
2026-03-13T01:11:00	cmd_201	sasuke	L001	injected	BLOCK	no	dm-signal	impl	routine
EOF
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "lesson_deprecation_scan avoids cross-project contamination and external project file_missing false positives" {
    run bash "$TEST_PROJECT/scripts/lesson_deprecation_scan.sh" --project dm-signal
    [ "$status" -eq 0 ]
    [[ "$output" == *"合計: 0件 自動退役"* ]]
    [ ! -f "$TEST_PROJECT/deprecate_calls.log" ]

    run python3 -c "
import yaml
with open('$TEST_PROJECT/projects/dm-signal/lessons.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
lesson = data['lessons'][0]
assert lesson.get('deprecated') is not True
print('ok')
"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "lesson_deprecation_scan uses MAX(YAML, TSV) for effectiveness counts" {
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L002
    title: infra lesson
    summary: infra summary
    helpful_count: 3
    harmful_count: 0
    injection_count: 0
EOF

    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-03-13T01:00:00	cmd_100	sasuke	L002	injected	BLOCK	no	infra	impl	routine
2026-03-13T01:01:00	cmd_101	sasuke	L002	injected	BLOCK	no	infra	impl	routine
2026-03-13T01:02:00	cmd_102	sasuke	L002	injected	BLOCK	no	infra	impl	routine
2026-03-13T01:03:00	cmd_103	sasuke	L002	injected	BLOCK	no	infra	impl	routine
2026-03-13T01:04:00	cmd_104	sasuke	L002	injected	BLOCK	no	infra	impl	routine
2026-03-13T01:05:00	cmd_105	sasuke	L002	injected	BLOCK	no	infra	impl	routine
2026-03-13T01:06:00	cmd_106	sasuke	L002	injected	BLOCK	no	infra	impl	routine
2026-03-13T01:07:00	cmd_107	sasuke	L002	injected	BLOCK	no	infra	impl	routine
2026-03-13T01:08:00	cmd_108	sasuke	L002	injected	BLOCK	no	infra	impl	routine
2026-03-13T01:09:00	cmd_109	sasuke	L002	injected	BLOCK	no	infra	impl	routine
EOF

    run bash "$TEST_PROJECT/scripts/lesson_deprecation_scan.sh" --project infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"合計: 0件 自動退役"* ]]
    [ ! -f "$TEST_PROJECT/deprecate_calls.log" ]
}

@test "lesson_deprecation_scan ignores pending lesson_impact rows" {
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L003
    title: infra lesson
    summary: infra summary
    helpful_count: 0
    harmful_count: 0
    injection_count: 0
EOF

    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-03-13T01:00:00	cmd_100	sasuke	L003	injected	PENDING	pending	infra	impl	routine
2026-03-13T01:01:00	cmd_101	sasuke	L003	injected	PENDING	pending	infra	impl	routine
2026-03-13T01:02:00	cmd_102	sasuke	L003	injected	PENDING	pending	infra	impl	routine
2026-03-13T01:03:00	cmd_103	sasuke	L003	injected	PENDING	pending	infra	impl	routine
2026-03-13T01:04:00	cmd_104	sasuke	L003	injected	PENDING	pending	infra	impl	routine
2026-03-13T01:05:00	cmd_105	sasuke	L003	injected	PENDING	pending	infra	impl	routine
2026-03-13T01:06:00	cmd_106	sasuke	L003	injected	PENDING	pending	infra	impl	routine
2026-03-13T01:07:00	cmd_107	sasuke	L003	injected	PENDING	pending	infra	impl	routine
2026-03-13T01:08:00	cmd_108	sasuke	L003	injected	PENDING	pending	infra	impl	routine
2026-03-13T01:09:00	cmd_109	sasuke	L003	injected	PENDING	pending	infra	impl	routine
EOF

    run bash "$TEST_PROJECT/scripts/lesson_deprecation_scan.sh" --project infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"合計: 0件 自動退役"* ]]
    [ ! -f "$TEST_PROJECT/deprecate_calls.log" ]
}
