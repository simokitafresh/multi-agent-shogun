#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_lesson_health.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1

    export BASE_FIXTURE
    BASE_FIXTURE="$(mktemp -d "$BATS_TMPDIR/gate_lesson_health.base.XXXXXX")"
    mkdir -p "$BASE_FIXTURE/scripts/gates" \
             "$BASE_FIXTURE/config" \
             "$BASE_FIXTURE/context" \
             "$BASE_FIXTURE/projects/infra" \
             "$BASE_FIXTURE/tasks" \
             "$BASE_FIXTURE/logs" \
             "$BASE_FIXTURE/queue"

    cp "$SRC_SCRIPT" "$BASE_FIXTURE/scripts/gates/gate_lesson_health.sh"
    chmod +x "$BASE_FIXTURE/scripts/gates/gate_lesson_health.sh"
    cp "$PROJECT_ROOT/scripts/gates/lesson_context_routes.sh" \
        "$BASE_FIXTURE/scripts/gates/lesson_context_routes.sh"
    printf '#!/bin/bash\nexit 0\n' > "$BASE_FIXTURE/scripts/ntfy.sh"
    chmod +x "$BASE_FIXTURE/scripts/ntfy.sh"

    cat > "$BASE_FIXTURE/config/projects.yaml" <<'EOF'
projects:
  - id: infra
    path: "/tmp/test-project"
    context_file: "context/infrastructure.md"
    status: active
EOF

    cat > "$BASE_FIXTURE/context/infrastructure.md" <<'EOF'
<!-- last_synced_lesson: L001 -->

## 教訓索引（自動追記）
- L001 sample
EOF

    cat > "$BASE_FIXTURE/projects/infra/lessons.yaml" <<'EOF'
ssot_path: __TEST_TMPDIR__/tasks/lessons.md
last_synced: '2026-04-24T00:00:00'
archive_path: __TEST_TMPDIR__/projects/infra/lessons_archive.yaml
lesson_count: 1
lessons:
- id: L001
  title: sample
  summary: sample
EOF

    cat > "$BASE_FIXTURE/tasks/lessons.md" <<'EOF'
# lessons

## L001
sample
EOF

    cat > "$BASE_FIXTURE/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	lesson_id	action	result	referenced	project	extra
2026-04-24T00:00:00	cmd_1	L001	injected		true	infra	-
EOF
}

teardown_file() {
    [ -n "${BASE_FIXTURE:-}" ] && [ -d "$BASE_FIXTURE" ] && rm -rf "$BASE_FIXTURE"
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gate_lesson_health.XXXXXX")"
    cp -a "$BASE_FIXTURE/." "$TEST_TMPDIR/"
    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh"
    sed -i "s|__TEST_TMPDIR__|$TEST_TMPDIR|g" \
        "$TEST_TMPDIR/projects/infra/lessons.yaml"
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "gate_lesson_health reports OK when SSOT has no conflict markers" {
    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: infra SSOT conflict markersなし"* ]]
    [[ "$output" == *"OK: infraのlesson統合状況は健全"* ]]
}

@test "GA-244 repairs stale infra marker only when every pending lesson body exists" {
    cat > "$TEST_TMPDIR/projects/infra/lessons.yaml" <<EOF
ssot_path: $TEST_TMPDIR/tasks/lessons.md
lessons:
- id: L001
  title: one
  summary: one
- id: L002
  title: two
  summary: two
- id: L003
  title: three
  summary: three
EOF
    cat > "$TEST_TMPDIR/context/infrastructure.md" <<'EOF'
<!-- last_synced_lesson: L001 -->
## Infra教訓索引
- L001: one
- L002: two
- L003: three
EOF
    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    grep -q 'last_synced_lesson: L3' "$TEST_TMPDIR/context/infrastructure.md"

    sed -i 's/L3/L1/' "$TEST_TMPDIR/context/infrastructure.md"
    sed -i '/^- L002:/d' "$TEST_TMPDIR/context/infrastructure.md"
    run bash "$TEST_GATE" infra
    [[ "$output" == *"NO-FIX: infra marker L1 (本文欠落1/2)"* ]]
    grep -q 'last_synced_lesson: L1' "$TEST_TMPDIR/context/infrastructure.md"
}

@test "gate_lesson_health ignores missing ssot_path when lessons cache has zero lessons" {
    : > "$TEST_TMPDIR/projects/infra/lessons.yaml"

    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: infra lesson 0件"* ]]
    [[ "$output" != *"ssot_path未設定"* ]]

    cat > "$TEST_TMPDIR/projects/infra/lessons.yaml" <<'EOF'
lessons: []
EOF

    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: infra lesson 0件"* ]]
    [[ "$output" != *"ssot_path未設定"* ]]
}

@test "gate_lesson_health warns and reports fill rate when lessons miss when/how" {
    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: infra when/how充足率: when=0/1(0.0%) how=0/1(0.0%)"* ]]
    [[ "$output" == *"WARN: infra when/how欠落教訓あり(when欠落:1, how欠落:1, total:1)"* ]]
}

@test "gate_lesson_health warns when project lessons miss origin" {
    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: infra origin充足率: origin=0/1(0.0%)"* ]]
    [[ "$output" == *"WARN: infra origin欠落教訓あり(origin欠落:1, total:1)"* ]]
}

@test "gate_lesson_health reports full when/how coverage" {
    cat > "$TEST_TMPDIR/projects/infra/lessons.yaml" <<EOF
ssot_path: $TEST_TMPDIR/tasks/lessons.md
last_synced: '2026-04-24T00:00:00'
archive_path: $TEST_TMPDIR/projects/infra/lessons_archive.yaml
lesson_count: 1
lessons:
- id: L001
  title: sample
  summary: sample
  when: 同種条件
  how: 実行手順
EOF

    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: infra when/how充足率: when=1/1(100.0%) how=1/1(100.0%)"* ]]
    [[ "$output" != *"when/how欠落教訓あり"* ]]
}

@test "gate_lesson_health warns when role lesson origins are missing, empty, or linkless" {
    cat > "$TEST_TMPDIR/projects/infra/lessons_karo.yaml" <<'EOF'
lessons:
- id: LK001
  title: missing origin
  detail: test detail
- id: LK002
  title: empty origin
  origin: ''
  detail: test detail
- id: LK003
  title: no causal link
  origin: plain text only
  detail: test detail
EOF

    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: lessons_karo.yaml origin因果リンク不備 3/3件"* ]]
    [[ "$output" == *"origin欠落: LK001"* ]]
    [[ "$output" == *"origin空: LK002"* ]]
    [[ "$output" == *"リンク0件: LK003"* ]]
}

@test "gate_lesson_health reports OK when role lesson origins have causal links" {
    cat > "$TEST_TMPDIR/projects/infra/lessons_karo.yaml" <<'EOF'
lessons:
- id: LK001
  title: linked origin
  origin: '[[cmd_001]]'
  detail: test detail
EOF

    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: lessons_karo.yaml origin因果リンク (1件)"* ]]
    [[ "$output" != *"lessons_karo.yaml origin因果リンク不備"* ]]
}

@test "gate_lesson_health alerts when SSOT contains git conflict markers" {
    cat > "$TEST_TMPDIR/tasks/lessons.md" <<'EOF'
# lessons
<<<<<<< Updated upstream
alpha
=======
beta
>>>>>>> Stashed changes
EOF

    run bash "$TEST_GATE" infra
    [ "$status" -eq 1 ]
    [[ "$output" == *"ALERT: infra SSOTにgit conflict markers検出"* ]]
    [[ "$output" == *"tasks/lessons.md:2:<<<<<<< Updated upstream"* ]]
    [[ "$output" == *"tasks/lessons.md:4:======="* ]]
    [[ "$output" == *"tasks/lessons.md:6:>>>>>>> Stashed changes"* ]]
}

@test "gate_lesson_health excludes feedback samples below min sample threshold from useful_rate" {
    cat > "$TEST_TMPDIR/projects/infra/lessons.yaml" <<EOF
ssot_path: $TEST_TMPDIR/tasks/lessons.md
last_synced: '2026-04-24T00:00:00'
archive_path: $TEST_TMPDIR/projects/infra/lessons_archive.yaml
lesson_count: 2
lessons:
- id: L001
  title: sample one
  summary: sample one
- id: L002
  title: sample two
  summary: sample two
EOF

    cat > "$TEST_TMPDIR/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score	traversal_depth
2026-05-28T00:00:00	cmd_900	saizo	L001	injected		yes	infra	single_script	routine	5	0
2026-05-28T00:01:00	cmd_900	saizo	L001	feedback	USEFUL	yes	infra	single_script	routine	5	0
2026-05-28T00:02:00	cmd_901	saizo	L002	injected		yes	infra	single_script	routine	5	0
2026-05-28T00:03:00	cmd_901	saizo	L002	feedback	NOT_USEFUL	no	infra	single_script	routine	5	0
EOF

    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: useful率(直近2cmd): 0/0 = 0.0%"* ]]
    [[ "$output" == *"METRIC: lesson_effectiveness_threshold status=OK rate=100.0% useful_rate=0.0% window_cmds=2 referenced=2 injected=2 useful=0 total_feedback=0 scope=infra"* ]]
}

@test "gate_lesson_health includes feedback samples once deprecation-review threshold is met" {
    cat > "$TEST_TMPDIR/projects/infra/lessons.yaml" <<EOF
ssot_path: $TEST_TMPDIR/tasks/lessons.md
last_synced: '2026-04-24T00:00:00'
archive_path: $TEST_TMPDIR/projects/infra/lessons_archive.yaml
lesson_count: 1
lessons:
- id: L001
  title: sample one
  summary: sample one
EOF

    cat > "$TEST_TMPDIR/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score	traversal_depth
2026-05-28T00:00:00	cmd_900	saizo	L001	injected		yes	infra	single_script	routine	5	0
2026-05-28T00:01:00	cmd_900	saizo	L001	feedback	USEFUL	yes	infra	single_script	routine	5	0
2026-05-28T00:02:00	cmd_901	saizo	L001	injected		yes	infra	single_script	routine	5	0
2026-05-28T00:03:00	cmd_901	saizo	L001	feedback	NOT_USEFUL	no	infra	single_script	routine	5	0
2026-05-28T00:04:00	cmd_902	saizo	L001	injected		yes	infra	single_script	routine	5	0
2026-05-28T00:05:00	cmd_902	saizo	L001	feedback	USEFUL	yes	infra	single_script	routine	5	0
2026-05-28T00:06:00	cmd_903	saizo	L001	injected		yes	infra	single_script	routine	5	0
2026-05-28T00:07:00	cmd_903	saizo	L001	feedback	NOT_USEFUL	no	infra	single_script	routine	5	0
2026-05-28T00:08:00	cmd_904	saizo	L001	injected		yes	infra	single_script	routine	5	0
2026-05-28T00:09:00	cmd_904	saizo	L001	feedback	USEFUL	yes	infra	single_script	routine	5	0
EOF

    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: useful率(直近5cmd): 3/5 = 60.0%"* ]]
    [[ "$output" == *"METRIC: lesson_effectiveness_threshold status=OK rate=100.0% useful_rate=60.0% window_cmds=5 referenced=5 injected=5 useful=3 total_feedback=5 scope=infra"* ]]
}

@test "gate_lesson_health excludes hotfix feedback from useful_rate health signal" {
    cat > "$TEST_TMPDIR/projects/infra/lessons.yaml" <<EOF
ssot_path: $TEST_TMPDIR/tasks/lessons.md
last_synced: '2026-04-24T00:00:00'
archive_path: $TEST_TMPDIR/projects/infra/lessons_archive.yaml
lesson_count: 1
lessons:
- id: L001
  title: sample one
  summary: sample one
EOF

    cat > "$TEST_TMPDIR/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score	traversal_depth
2026-05-28T00:00:00	cmd_900	saizo	L001	injected		yes	infra	hotfix	routine	5	0
2026-05-28T00:01:00	cmd_900	saizo	L001	feedback	NOT_USEFUL	no	infra	hotfix	routine	5	0
2026-05-28T00:02:00	cmd_901	saizo	L001	injected		yes	infra	hotfix	routine	5	0
2026-05-28T00:03:00	cmd_901	saizo	L001	feedback	NOT_USEFUL	no	infra	hotfix	routine	5	0
2026-05-28T00:04:00	cmd_902	saizo	L001	injected		yes	infra	hotfix	routine	5	0
2026-05-28T00:05:00	cmd_902	saizo	L001	feedback	NOT_USEFUL	no	infra	hotfix	routine	5	0
2026-05-28T00:06:00	cmd_903	saizo	L001	injected		yes	infra	hotfix	routine	5	0
2026-05-28T00:07:00	cmd_903	saizo	L001	feedback	NOT_USEFUL	no	infra	hotfix	routine	5	0
2026-05-28T00:08:00	cmd_904	saizo	L001	injected		yes	infra	hotfix	routine	5	0
2026-05-28T00:09:00	cmd_904	saizo	L001	feedback	NOT_USEFUL	no	infra	hotfix	routine	5	0
2026-05-28T00:10:00	cmd_905	saizo	L001	injected		yes	infra	full	routine	5	0
2026-05-28T00:11:00	cmd_905	saizo	L001	feedback	USEFUL	yes	infra	full	routine	5	0
2026-05-28T00:12:00	cmd_906	saizo	L001	injected		yes	infra	full	routine	5	0
2026-05-28T00:13:00	cmd_906	saizo	L001	feedback	USEFUL	yes	infra	full	routine	5	0
2026-05-28T00:14:00	cmd_907	saizo	L001	injected		yes	infra	full	routine	5	0
2026-05-28T00:15:00	cmd_907	saizo	L001	feedback	USEFUL	yes	infra	full	routine	5	0
2026-05-28T00:16:00	cmd_908	saizo	L001	injected		yes	infra	full	routine	5	0
2026-05-28T00:17:00	cmd_908	saizo	L001	feedback	USEFUL	yes	infra	full	routine	5	0
2026-05-28T00:18:00	cmd_909	saizo	L001	injected		yes	infra	full	routine	5	0
2026-05-28T00:19:00	cmd_909	saizo	L001	feedback	USEFUL	yes	infra	full	routine	5	0
EOF

    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: useful率(直近10cmd): 5/5 = 100.0%"* ]]
    [[ "$output" == *"METRIC: lesson_effectiveness_threshold status=OK rate=100.0% useful_rate=100.0% window_cmds=10 referenced=5 injected=5 useful=5 total_feedback=5 scope=infra"* ]]
}

@test "gate_lesson_health excludes pending injection rows from lesson effectiveness window" {
    cat > "$TEST_TMPDIR/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score	traversal_depth
2026-05-28T00:00:00	cmd_900	saizo	L001	injected		yes	infra	single_script	routine	5	0
2026-05-28T00:01:00	cmd_900	saizo	L001	feedback	USEFUL	yes	infra	single_script	routine	5	0
2026-05-28T00:02:00	cmd_901	saizo	L001	injected	pending	pending	infra	single_script	routine	5	0
EOF

    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: 教訓効果率(直近1cmd): 1/1 = 100.0%"* ]]
    [[ "$output" == *"METRIC: lesson_effectiveness_threshold status=OK rate=100.0% useful_rate=0.0% window_cmds=1 referenced=1 injected=1 useful=0 total_feedback=0 scope=infra"* ]]
}

@test "gate_lesson_health excludes deprecated lessons from lesson effectiveness" {
    cat > "$TEST_TMPDIR/projects/infra/lessons.yaml" <<EOF
ssot_path: $TEST_TMPDIR/tasks/lessons.md
last_synced: '2026-04-24T00:00:00'
archive_path: $TEST_TMPDIR/projects/infra/lessons_archive.yaml
lesson_count: 2
lessons:
- id: L001
  title: active sample
  summary: active sample
- id: L002
  title: deprecated sample
  summary: deprecated sample
  deprecated: true
EOF

    cat > "$TEST_TMPDIR/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score	traversal_depth
2026-05-28T00:00:00	cmd_900	saizo	L001	injected		yes	infra	single_script	routine	5	0
2026-05-28T00:01:00	cmd_900	saizo	L001	feedback	USEFUL	yes	infra	single_script	routine	5	0
2026-05-28T00:02:00	cmd_901	saizo	L002	injected		no	infra	single_script	routine	5	0
2026-05-28T00:03:00	cmd_901	saizo	L002	feedback	NOT_USEFUL	no	infra	single_script	routine	5	0
EOF

    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: 教訓効果率(直近2cmd): 1/1 = 100.0%"* ]]
    [[ "$output" == *"INFO: useful率(直近2cmd): 0/0 = 0.0%"* ]]
    [[ "$output" == *"METRIC: lesson_effectiveness_threshold status=OK rate=100.0% useful_rate=0.0% window_cmds=2 referenced=1 injected=1 useful=0 total_feedback=0 scope=infra"* ]]
}

@test "gate_lesson_health does not fallback to infra when project has deprecated same lesson id" {
    mkdir -p "$TEST_TMPDIR/projects/dm-signal"
    cat > "$TEST_TMPDIR/config/projects.yaml" <<'EOF'
projects:
  - id: infra
    path: "/tmp/test-project"
    context_file: "context/infrastructure.md"
    status: active
  - id: dm-signal
    path: "/tmp/test-project"
    context_file: "context/dm-signal.md"
    status: active
EOF

    cat > "$TEST_TMPDIR/context/dm-signal.md" <<'EOF'
<!-- last_synced_lesson: L002 -->
EOF

    cat > "$TEST_TMPDIR/projects/infra/lessons.yaml" <<EOF
ssot_path: $TEST_TMPDIR/tasks/lessons.md
lessons:
- id: L002
  title: infra active same id
  summary: infra active same id
EOF

    cat > "$TEST_TMPDIR/projects/dm-signal/lessons.yaml" <<EOF
ssot_path: $TEST_TMPDIR/tasks/lessons.md
lessons:
- id: L002
  title: dm deprecated same id
  summary: dm deprecated same id
  deprecated: true
EOF

    cat > "$TEST_TMPDIR/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score	traversal_depth
2026-05-28T00:00:00	cmd_900	saizo	L002	injected		no	dm-signal	full	routine	5	0
2026-05-28T00:01:00	cmd_900	saizo	L002	feedback	NOT_USEFUL	no	dm-signal	full	routine	5	0
2026-05-28T00:02:00	cmd_901	saizo	L002	injected		no	dm-signal	full	routine	5	0
2026-05-28T00:03:00	cmd_901	saizo	L002	feedback	NOT_USEFUL	no	dm-signal	full	routine	5	0
EOF

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: 教訓効果率(直近2cmd): 0/0 = 0.0%"* ]]
    [[ "$output" == *"METRIC: lesson_effectiveness_threshold status=OK rate=0.0% useful_rate=0.0% window_cmds=2 referenced=0 injected=0 useful=0 total_feedback=0 scope=all"* ]]
}

@test "gate_lesson_health excludes bootstrap lessons from useful_rate (all-time feedback < useful_min)" {
    # L001: mature (all-time feedback=3 >= useful_min=2) → counted
    # L002: bootstrap (all-time feedback=1 < useful_min=2) → excluded from useful_rate
    cat > "$TEST_TMPDIR/projects/infra/lessons.yaml" <<EOF
ssot_path: $TEST_TMPDIR/tasks/lessons.md
last_synced: '2026-04-24T00:00:00'
archive_path: $TEST_TMPDIR/projects/infra/lessons_archive.yaml
lesson_count: 2
lessons:
- id: L001
  title: mature lesson
  summary: mature lesson
- id: L002
  title: bootstrap lesson
  summary: bootstrap lesson
EOF

    # L001 has 3 feedback entries (all-time) → mature
    # L002 has 1 feedback entry (all-time) → bootstrap
    # In the 3-cmd window: L001 has 2 feedback (1 USEFUL + 1 NOT_USEFUL), L002 has 1 (NOT_USEFUL)
    # Without bootstrap filter: useful=1/3=33%
    # With bootstrap filter: useful=1/2=50% (L002 excluded)
    cat > "$TEST_TMPDIR/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score	traversal_depth
2026-05-28T00:00:00	cmd_900	saizo	L001	injected		yes	infra	single_script	routine	5	0
2026-05-28T00:01:00	cmd_900	saizo	L001	feedback	USEFUL	yes	infra	single_script	routine	5	0
2026-05-28T00:02:00	cmd_901	saizo	L001	injected		yes	infra	single_script	routine	5	0
2026-05-28T00:03:00	cmd_901	saizo	L001	feedback	NOT_USEFUL	no	infra	single_script	routine	5	0
2026-05-28T00:04:00	cmd_902	saizo	L002	injected		yes	infra	single_script	routine	5	0
2026-05-28T00:05:00	cmd_902	saizo	L002	feedback	NOT_USEFUL	no	infra	single_script	routine	5	0
2026-05-28T00:06:00	cmd_903	saizo	L001	injected		yes	infra	single_script	routine	5	0
2026-05-28T00:07:00	cmd_903	saizo	L001	feedback	NOT_USEFUL	no	infra	single_script	routine	5	0
EOF

    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    # L001 is mature (3 feedback all-time), L002 is bootstrap (1 feedback all-time)
    # Only L001 feedback counted: 1 USEFUL + 2 NOT_USEFUL = useful=1/3
    [[ "$output" == *"useful=1"* ]]
    [[ "$output" == *"total_feedback=3"* ]]
}

@test "gate_lesson_health does not alert on useful_rate below min total feedback samples" {
    cat > "$TEST_TMPDIR/projects/infra/lessons.yaml" <<EOF
ssot_path: $TEST_TMPDIR/tasks/lessons.md
last_synced: '2026-04-24T00:00:00'
archive_path: $TEST_TMPDIR/projects/infra/lessons_archive.yaml
lesson_count: 1
lessons:
- id: L001
  title: mature low sample lesson
  summary: mature low sample lesson
EOF

    cat > "$TEST_TMPDIR/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score	traversal_depth
2026-05-28T00:00:00	cmd_900	saizo	L001	injected		yes	infra	single_script	routine	5	0
2026-05-28T00:01:00	cmd_900	saizo	L001	feedback	NOT_USEFUL	no	infra	single_script	routine	5	0
2026-05-28T00:02:00	cmd_901	saizo	L001	injected		yes	infra	single_script	routine	5	0
2026-05-28T00:03:00	cmd_901	saizo	L001	feedback	NOT_USEFUL	no	infra	single_script	routine	5	0
EOF

    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: useful率(直近2cmd): 0/2 = 0.0%"* ]]
    [[ "$output" == *"METRIC: lesson_effectiveness_threshold status=OK rate=100.0% useful_rate=0.0% window_cmds=2 referenced=2 injected=2 useful=0 total_feedback=2 scope=infra"* ]]
}

@test "gate_lesson_health stays OK just below the early-route warn threshold (4 unsorted)" {
    cat > "$TEST_TMPDIR/context/infrastructure.md" <<'EOF'
<!-- last_synced_lesson: L001 -->

## 教訓索引（自動追記）
- L010 sample
- L011 sample
- L012 sample
- L013 sample
EOF

    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: infraの未振り分け教訓4件(閾値10以下, ids: L010,L011,L012,L013)"* ]]
    [[ "$output" != *"WARN: infraの未振り分け教訓"* ]]
    [[ "$output" != *"ALERT: infraの未振り分け教訓"* ]]
}

@test "gate_lesson_health warns with early route (project+ids+action) at 5 unsorted lessons" {
    cat > "$TEST_TMPDIR/context/infrastructure.md" <<'EOF'
<!-- last_synced_lesson: L001 -->

## 教訓索引（自動追記）
- L010 sample
- L011 sample
- L012 sample
- L013 sample
- L014 sample
EOF

    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: infraの未振り分け教訓5件(早期導線, ALERT閾値10未満, ids: L010,L011,L012,L013,L014)"* ]]
    [[ "$output" == *"action: ALERT閾値(10件)に達する前に /lesson-sort を実行し、infraの未振り分け教訓の蓄積を防げ。"* ]]
    [[ "$output" != *"ALERT: infraの未振り分け教訓"* ]]
}

@test "gate_lesson_health still warns (not silently OK) at the upper edge of the early-route band (10 unsorted)" {
    cat > "$TEST_TMPDIR/context/infrastructure.md" <<'EOF'
<!-- last_synced_lesson: L001 -->

## 教訓索引（自動追記）
- L010 sample
- L011 sample
- L012 sample
- L013 sample
- L014 sample
- L015 sample
- L016 sample
- L017 sample
- L018 sample
- L019 sample
EOF

    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: infraの未振り分け教訓10件(早期導線, ALERT閾値10未満, ids: L010,L011,L012,L013,L014,L015,L016,L017,L018,L019)"* ]]
    [[ "$output" != *"ALERT: infraの未振り分け教訓"* ]]
}

@test "gate_lesson_health still alerts unchanged (existing action text, exit 1) at 11 unsorted lessons" {
    cat > "$TEST_TMPDIR/context/infrastructure.md" <<'EOF'
<!-- last_synced_lesson: L001 -->

## 教訓索引（自動追記）
- L010 sample
- L011 sample
- L012 sample
- L013 sample
- L014 sample
- L015 sample
- L016 sample
- L017 sample
- L018 sample
- L019 sample
- L020 sample
EOF

    run bash "$TEST_GATE" infra
    [ "$status" -eq 1 ]
    [[ "$output" == *"ALERT: infraの未振り分け教訓11件 → /lesson-sort推奨 (ids: L010,L011,L012,L013,L014,L015,L016,L017,L018,L019,L020)"* ]]
    [[ "$output" == *"action: /lesson-sort を実行し、未振り分け教訓を適切なcontextセクションへ移動せよ。"* ]]
    [[ "$output" != *"WARN: infraの未振り分け教訓"* ]]
}
