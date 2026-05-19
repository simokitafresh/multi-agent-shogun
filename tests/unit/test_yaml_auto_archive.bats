#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TEST_ROOT="$(mktemp -d)"
    export TEST_ROOT
    mkdir -p "$TEST_ROOT/logs" "$TEST_ROOT/queue" "$TEST_ROOT/config"
}

teardown() {
    rm -rf "$TEST_ROOT"
}

@test "yaml_auto_archive keeps configured recent entries and appends archives" {
    cat > "$TEST_ROOT/config/yaml_auto_archive.tsv" <<'EOF'
logs/cmd_design_quality.yaml	2	entries	^\s*-\s+cmd_id:	logs/archive/cmd_design_quality.yaml
logs/karo_workarounds.yaml	1	-	^\s*-\s+cmd_id:	logs/archive/karo_workarounds.yaml
queue/bulletin_board.yaml	1	entries	^\s*-\s+id:	queue/archive/bulletin_board_archive.yaml
queue/insights.yaml	1	insights	^\s*-\s+id:	queue/archive/insights_archive.yaml
EOF
    cat > "$TEST_ROOT/logs/cmd_design_quality.yaml" <<'EOF'
entries:
- cmd_id: cmd_old
  gate_result: PASS
- cmd_id: cmd_mid
  gate_result: WARN
- cmd_id: cmd_new
  gate_result: BLOCK
EOF
    cat > "$TEST_ROOT/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: wa_old
  category: old
- cmd_id: wa_new
  category: new
EOF
    cat > "$TEST_ROOT/queue/bulletin_board.yaml" <<'EOF'
entries:
- id: blt_old
  content: old
- id: blt_new
  content: new
EOF
    cat > "$TEST_ROOT/queue/insights.yaml" <<'EOF'
insights:
- id: ins_old
  insight: old
- id: ins_new
  insight: new
EOF

    run env SHOGUN_ROOT="$TEST_ROOT" YAML_AUTO_ARCHIVE_CONFIG="$TEST_ROOT/config/yaml_auto_archive.tsv" bash "$PROJECT_ROOT/scripts/yaml_auto_archive.sh"
    [ "$status" -eq 0 ]

    [ "$(grep -c 'cmd_id:' "$TEST_ROOT/logs/cmd_design_quality.yaml")" -eq 2 ]
    [ "$(grep -c 'cmd_id:' "$TEST_ROOT/logs/archive/cmd_design_quality.yaml")" -eq 1 ]
    [ "$(grep -c 'cmd_id:' "$TEST_ROOT/logs/karo_workarounds.yaml")" -eq 1 ]
    [ "$(grep -c 'cmd_id:' "$TEST_ROOT/logs/archive/karo_workarounds.yaml")" -eq 1 ]
    [ "$(grep -c '^- id:' "$TEST_ROOT/queue/bulletin_board.yaml")" -eq 1 ]
    [ "$(grep -c '^- id:' "$TEST_ROOT/queue/archive/bulletin_board_archive.yaml")" -eq 1 ]
    [ "$(grep -c '^- id:' "$TEST_ROOT/queue/insights.yaml")" -eq 1 ]
    [ "$(grep -c '^- id:' "$TEST_ROOT/queue/archive/insights_archive.yaml")" -eq 1 ]
}

@test "yaml_auto_archive is a no-op when count is within keep limit" {
    cat > "$TEST_ROOT/config/yaml_auto_archive.tsv" <<'EOF'
logs/cmd_design_quality.yaml	2	entries	^\s*-\s+cmd_id:	logs/archive/cmd_design_quality.yaml
EOF
    cat > "$TEST_ROOT/logs/cmd_design_quality.yaml" <<'EOF'
entries:
- cmd_id: cmd_one
  gate_result: PASS
- cmd_id: cmd_two
  gate_result: WARN
EOF

    run env SHOGUN_ROOT="$TEST_ROOT" YAML_AUTO_ARCHIVE_CONFIG="$TEST_ROOT/config/yaml_auto_archive.tsv" bash "$PROJECT_ROOT/scripts/yaml_auto_archive.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK logs/cmd_design_quality.yaml: entries=2 keep=2"* ]]
    [ ! -e "$TEST_ROOT/logs/archive/cmd_design_quality.yaml" ]
    [ "$(grep -c 'cmd_id:' "$TEST_ROOT/logs/cmd_design_quality.yaml")" -eq 2 ]
}
