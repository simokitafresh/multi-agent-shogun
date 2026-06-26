#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/weekly_metrics_trend.sh"
    [ -x "$SRC_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/weekly_metrics.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/logs"
    export WEEKLY_METRICS_ROOT="$TEST_TMPDIR"
    export WEEKLY_METRICS_NOW="2026-06-26T00:00:00Z"
}

teardown() {
    unset WEEKLY_METRICS_ROOT
    unset WEEKLY_METRICS_NOW
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "weekly_metrics_trend appends current weekly snapshot" {
    cat > "$TEST_TMPDIR/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score	traversal_depth
2026-06-25T00:00:00Z	cmd_1	hayate	L001	feedback	USEFUL	yes	infra	full	unknown	0	0
2026-06-25T01:00:00Z	cmd_2	hayate	L002	feedback	NOT_USEFUL	no	infra	full	unknown	0	0
2026-06-10T01:00:00Z	cmd_old	hayate	L003	feedback	NOT_USEFUL	no	infra	full	unknown	0	0
EOF

    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries:
- cmd_id: "cmd_1"
  gate_result: "PASS"
  karo_rework: "no"
  timestamp: "2026-06-25T00:00:00Z"
- cmd_id: "cmd_2"
  gate_result: "BLOCK"
  karo_rework: "yes"
  timestamp: "2026-06-25T01:00:00Z"
- cmd_id: "cmd_old"
  gate_result: "BLOCK"
  karo_rework: "yes"
  timestamp: "2026-06-10T00:00:00Z"
EOF

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"METRIC: weekly_metrics_trend useful_rate=50.0%(1/2) rework_rate=50.0%(1/2) block_rate=50.0%(1/2)"* ]]
    [[ "$output" == *"OK: weekly metrics trend"* ]]
    grep -q 'week_end: "2026-06-26T00:00:00Z"' "$TEST_TMPDIR/logs/weekly_metrics_trend.yaml"
    grep -q 'useful_rate: 50.0' "$TEST_TMPDIR/logs/weekly_metrics_trend.yaml"
    grep -q 'rework_rate: 50.0' "$TEST_TMPDIR/logs/weekly_metrics_trend.yaml"
    grep -q 'block_rate: 50.0' "$TEST_TMPDIR/logs/weekly_metrics_trend.yaml"
}

@test "weekly_metrics_trend alerts on three-week worsening" {
    cat > "$TEST_TMPDIR/logs/weekly_metrics_trend.yaml" <<'EOF'
snapshots:
- week_start: "2026-06-05T00:00:00Z"
  week_end: "2026-06-12T00:00:00Z"
  useful_rate: 80.0
  useful: 8
  feedback_total: 10
  rework_rate: 10.0
  rework: 1
  cmd_quality_total: 10
  block_rate: 10.0
  blocks: 1
  source: "weekly_metrics_trend.sh"
- week_start: "2026-06-12T00:00:00Z"
  week_end: "2026-06-19T00:00:00Z"
  useful_rate: 70.0
  useful: 7
  feedback_total: 10
  rework_rate: 20.0
  rework: 2
  cmd_quality_total: 10
  block_rate: 20.0
  blocks: 2
  source: "weekly_metrics_trend.sh"
EOF

    cat > "$TEST_TMPDIR/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score	traversal_depth
2026-06-25T00:00:00Z	cmd_1	hayate	L001	feedback	USEFUL	yes	infra	full	unknown	0	0
2026-06-25T01:00:00Z	cmd_2	hayate	L002	feedback	NOT_USEFUL	no	infra	full	unknown	0	0
EOF

    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries:
- cmd_id: "cmd_1"
  gate_result: "BLOCK"
  karo_rework: "yes"
  timestamp: "2026-06-25T00:00:00Z"
- cmd_id: "cmd_2"
  gate_result: "PASS"
  karo_rework: "no"
  timestamp: "2026-06-25T01:00:00Z"
EOF

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ALERT: useful_rate 3週連続悪化: 80.0% -> 70.0% -> 50.0%"* ]]
    [[ "$output" == *"ALERT: rework_rate 3週連続悪化: 10.0% -> 20.0% -> 50.0%"* ]]
    [[ "$output" == *"ALERT: block_rate 3週連続悪化: 10.0% -> 20.0% -> 50.0%"* ]]
    grep -q 'alerts:' "$TEST_TMPDIR/logs/weekly_metrics_trend.yaml"
    grep -q 'useful_rate 3週連続悪化' "$TEST_TMPDIR/logs/weekly_metrics_trend.yaml"
}
