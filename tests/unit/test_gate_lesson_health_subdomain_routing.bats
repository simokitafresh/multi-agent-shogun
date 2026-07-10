#!/usr/bin/env bats
# GA-216/GA-217 regression: gate_lesson_health.sh must not flag lessons as
# "unsynced" when they were correctly routed (via subdomain) to a context file
# other than the project's default context_file. Before the fix, the gate only
# checked the default context_file's <!-- last_synced_lesson --> marker, so any
# lesson with subdomain fe/be/gs (routed to dm-signal-frontend.md /
# dm-signal-ops.md) was permanently reported as unsynced even though
# lesson_write.sh had already synced it to the correct file.

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_lesson_health.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gate_lesson_health_routing.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" \
             "$TEST_TMPDIR/config" \
             "$TEST_TMPDIR/context" \
             "$TEST_TMPDIR/projects/dm-signal" \
             "$TEST_TMPDIR/tasks" \
             "$TEST_TMPDIR/logs" \
             "$TEST_TMPDIR/queue"

    cp "$SRC_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh"
    cp "$PROJECT_ROOT/scripts/gates/lesson_context_routes.sh" \
        "$TEST_TMPDIR/scripts/gates/lesson_context_routes.sh"
    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh"

    printf '#!/bin/bash\nexit 0\n' > "$TEST_TMPDIR/scripts/ntfy.sh"
    chmod +x "$TEST_TMPDIR/scripts/ntfy.sh"

    cat > "$TEST_TMPDIR/config/projects.yaml" <<'EOF'
projects:
  - id: dm-signal
    path: "/tmp/test-project"
    context_file: "context/dm-signal.md"
    status: active
EOF

    cat > "$TEST_TMPDIR/tasks/lessons.md" <<'EOF'
# lessons
EOF

    : > "$TEST_TMPDIR/logs/lesson_impact.tsv"
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "GA-216/217: lessons already synced to their subdomain-routed file are not reported unsynced" {
    # Default context file's marker is stale (L100) — this is the state the old
    # gate checked exclusively and would have flagged L101-L103 as unsynced.
    cat > "$TEST_TMPDIR/context/dm-signal.md" <<'EOF'
<!-- last_synced_lesson: L100 -->

## 教訓索引（自動追記）
EOF

    # But the fe/gs subdomain-routed files already advanced past those lessons —
    # lesson_write.sh really did sync them there.
    cat > "$TEST_TMPDIR/context/dm-signal-frontend.md" <<'EOF'
## 12. Frontend関連教訓
<!-- last_synced_lesson: L101 -->
- L101: fe lesson already synced here
EOF

    cat > "$TEST_TMPDIR/context/dm-signal-ops.md" <<'EOF'
## §33 GS
<!-- last_synced_lesson: L103 -->
- L102: gs lesson already synced here
- L103: another gs lesson already synced here
EOF

    cat > "$TEST_TMPDIR/projects/dm-signal/lessons.yaml" <<EOF
ssot_path: $TEST_TMPDIR/tasks/lessons.md
last_synced: '2026-07-10T00:00:00'
archive_path: $TEST_TMPDIR/projects/dm-signal/lessons_archive.yaml
lesson_count: 3
lessons:
- id: L103
  title: another gs lesson
  summary: another gs lesson
  subdomain: gs
  when: t
  how: t
  origin: '[[cmd_1]]'
- id: L102
  title: gs lesson
  summary: gs lesson
  subdomain: gs
  when: t
  how: t
  origin: '[[cmd_1]]'
- id: L101
  title: fe lesson
  summary: fe lesson
  subdomain: fe
  when: t
  how: t
  origin: '[[cmd_1]]'
EOF

    run bash "$TEST_GATE" dm-signal
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: dm-signalのlesson統合状況は健全(未合流0件,total:3,synced:L100)"* ]]
    [[ "$output" != *"ALERT: dm-signal"*"未合流"* ]]
}

@test "GA-216/217: a lesson genuinely behind its own routed file's marker is still reported unsynced" {
    # The fix must not create false negatives: if the gs-routed file itself
    # hasn't advanced past a lesson yet, that lesson is genuinely unsynced.
    cat > "$TEST_TMPDIR/context/dm-signal.md" <<'EOF'
<!-- last_synced_lesson: L100 -->
EOF

    cat > "$TEST_TMPDIR/context/dm-signal-ops.md" <<'EOF'
## §33 GS
<!-- last_synced_lesson: L100 -->
EOF

    for i in 1 2 3 4 5 6; do
        cat >> "$TEST_TMPDIR/projects/dm-signal/lessons.yaml" <<EOF
- id: L10${i}
  title: unsynced gs lesson ${i}
  summary: unsynced gs lesson ${i}
  subdomain: gs
  when: t
  how: t
  origin: '[[cmd_1]]'
EOF
    done
    {
        printf 'ssot_path: %s/tasks/lessons.md\n' "$TEST_TMPDIR"
        printf 'lesson_count: 6\nlessons:\n'
        cat "$TEST_TMPDIR/projects/dm-signal/lessons.yaml"
    } > "$TEST_TMPDIR/projects/dm-signal/lessons.yaml.tmp"
    mv "$TEST_TMPDIR/projects/dm-signal/lessons.yaml.tmp" "$TEST_TMPDIR/projects/dm-signal/lessons.yaml"

    run bash "$TEST_GATE" dm-signal
    [ "$status" -eq 1 ]
    [[ "$output" == *"ALERT: dm-signalのlesson→context未合流6件(total:6,synced:L100,max:L106)"* ]]
}

@test "routing fix keeps single-marker behavior for projects with no subdomain routes" {
    cat > "$TEST_TMPDIR/config/projects.yaml" <<'EOF'
projects:
  - id: dm-signal
    path: "/tmp/test-project"
    context_file: "context/dm-signal.md"
    status: active
  - id: nosdproj
    path: "/tmp/test-project"
    context_file: "context/nosdproj.md"
    status: active
EOF

    mkdir -p "$TEST_TMPDIR/projects/nosdproj"
    cat > "$TEST_TMPDIR/context/nosdproj.md" <<'EOF'
<!-- last_synced_lesson: L200 -->
EOF

    cat > "$TEST_TMPDIR/projects/nosdproj/lessons.yaml" <<EOF
ssot_path: $TEST_TMPDIR/tasks/lessons.md
lesson_count: 7
lessons:
$(for i in 201 202 203 204 205 206 207; do printf -- '- id: L%s\n  title: t\n  summary: t\n  subdomain: gs\n  when: t\n  how: t\n  origin: "[[cmd_1]]"\n' "$i"; done)
EOF

    run bash "$TEST_GATE" nosdproj
    [ "$status" -eq 1 ]
    [[ "$output" == *"ALERT: nosdprojのlesson→context未合流7件(total:7,synced:L200,max:L207)"* ]]
}
