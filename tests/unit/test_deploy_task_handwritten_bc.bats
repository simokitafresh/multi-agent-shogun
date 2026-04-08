#!/usr/bin/env bats
# test_deploy_task_handwritten_bc.bats - AC1: hand-written YAML binary_checks extraction + AC2: scout_gate AC id confusion

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "deploy_hbc"
}

teardown() {
    deploy_task_teardown
}

# ─── AC1: hand-written YAML explicit check extraction ───

@test "explicit check AWK extracts AC ids from hand-written YAML (- id: ACx same line)" {
    # Hand-written format: "  - id: AC1" on same line (NOT yaml.dump "    id: AC1" on separate line)
    local task_yaml
    task_yaml=$(cat <<'YAML'
task:
  acceptance_criteria:
  - id: AC1
    criteria: "first check"
    - check: "check item 1"
  - id: AC2
    criteria: "second check"
    - check: "check item 2"
YAML
)

    local result
    result=$(echo "$task_yaml" | awk '
        /^  acceptance_criteria:/ { in_ac=1; next }
        in_ac && /^  [a-z]/ { exit }
        in_ac && /^  - / {
            if (cur_id != "" && cc > 0) {
                printf "  %s:\n", cur_id
                for (i=1; i<=cc; i++) { printf "  - check: \"%s\"\n    result: \"\"  # yes or no\n", chk[i] }
            }
            cur_id=""; cc=0
            if (/id:/) { s=$0; sub(/.*id:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); cur_id=s }
        }
        in_ac && /    id:/ { sub(/.*id:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); cur_id=$0 }
        in_ac && /    - check:/ { sub(/.*- check:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); cc++; chk[cc]=$0 }
        END {
            if (cur_id != "" && cc > 0) {
                printf "  %s:\n", cur_id
                for (i=1; i<=cc; i++) { printf "  - check: \"%s\"\n    result: \"\"  # yes or no\n", chk[i] }
            }
        }
    ')

    # AC1 and AC2 should both appear
    echo "$result" | grep -q "AC1:" || { echo "AC1 not found in: $result"; false; }
    echo "$result" | grep -q "AC2:" || { echo "AC2 not found in: $result"; false; }
    echo "$result" | grep -q "check item 1" || { echo "check item 1 not found in: $result"; false; }
    echo "$result" | grep -q "check item 2" || { echo "check item 2 not found in: $result"; false; }
}

@test "explicit check AWK still works with yaml.dump format (    id: ACx on separate line)" {
    # yaml.dump format: id on separate indented line
    local task_yaml
    task_yaml=$(cat <<'YAML'
task:
  acceptance_criteria:
  - criteria: "first check"
    id: AC1
    - check: "check item 1"
  - criteria: "second check"
    id: AC2
    - check: "check item 2"
YAML
)

    local result
    result=$(echo "$task_yaml" | awk '
        /^  acceptance_criteria:/ { in_ac=1; next }
        in_ac && /^  [a-z]/ { exit }
        in_ac && /^  - / {
            if (cur_id != "" && cc > 0) {
                printf "  %s:\n", cur_id
                for (i=1; i<=cc; i++) { printf "  - check: \"%s\"\n    result: \"\"  # yes or no\n", chk[i] }
            }
            cur_id=""; cc=0
            if (/id:/) { s=$0; sub(/.*id:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); cur_id=s }
        }
        in_ac && /    id:/ { sub(/.*id:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); cur_id=$0 }
        in_ac && /    - check:/ { sub(/.*- check:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); cc++; chk[cc]=$0 }
        END {
            if (cur_id != "" && cc > 0) {
                printf "  %s:\n", cur_id
                for (i=1; i<=cc; i++) { printf "  - check: \"%s\"\n    result: \"\"  # yes or no\n", chk[i] }
            }
        }
    ')

    echo "$result" | grep -q "AC1:" || { echo "AC1 not found in: $result"; false; }
    echo "$result" | grep -q "AC2:" || { echo "AC2 not found in: $result"; false; }
}

# ─── AC2: scout_gate AC id confusion ───

@test "scout_gate AWK does not confuse AC id with cmd id in shogun_to_karo.yaml" {
    # shogun_to_karo.yaml with acceptance_criteria containing "id: AC1" lines
    local stk_yaml
    stk_yaml=$(cat <<'YAML'
commands:
  cmd_1656:
    status: pending
    title: "test cmd"
    acceptance_criteria:
      - id: AC1
        description: "first"
      - id: AC2
        description: "second"
    scout_exempt: true
YAML
)

    local result
    result=$(echo "$stk_yaml" | awk -v cmd="cmd_1656" '
        /^  [a-zA-Z_].*:$/ { sub(/^[[:space:]]*/, ""); sub(/:$/, ""); cur_id=$0 }
        /^[[:space:]]*id:[[:space:]]/ { s=$0; sub(/.*id:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); if (s ~ /^cmd_/) cur_id=s }
        cur_id == cmd && /scout_exempt:[[:space:]]*true/ { print "true"; exit }
    ')

    [ "$result" = "true" ] || { echo "Expected 'true' but got '$result'"; false; }
}

@test "scout_gate AWK detects scout_exempt with yaml.dump style id on separate line" {
    # yaml.dump format where id: cmd_xxx is on its own line
    local stk_yaml
    stk_yaml=$(cat <<'YAML'
commands:
  cmd_1700:
    status: pending
    id: cmd_1700
    title: "test cmd"
    acceptance_criteria:
    - criteria: "first"
      id: AC1
    - criteria: "second"
      id: AC2
    scout_exempt: true
YAML
)

    local result
    result=$(echo "$stk_yaml" | awk -v cmd="cmd_1700" '
        /^  [a-zA-Z_].*:$/ { sub(/^[[:space:]]*/, ""); sub(/:$/, ""); cur_id=$0 }
        /^[[:space:]]*id:[[:space:]]/ { s=$0; sub(/.*id:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); if (s ~ /^cmd_/) cur_id=s }
        cur_id == cmd && /scout_exempt:[[:space:]]*true/ { print "true"; exit }
    ')

    [ "$result" = "true" ] || { echo "Expected 'true' but got '$result'"; false; }
}

@test "scout_gate AWK detects scout_exempt with list format parent cmd id" {
    local stk_yaml
    stk_yaml=$(cat <<'YAML'
commands:
  - id: cmd_1805
    status: pending
    title: "list format cmd"
    acceptance_criteria:
      - id: AC1
        description: "first"
      - id: AC2
        description: "second"
    scout_exempt: true
YAML
)

    local result
    result=$(echo "$stk_yaml" | awk -v cmd="cmd_1805" '
        /^  [a-zA-Z_].*:$/ { sub(/^[[:space:]]*/, ""); sub(/:$/, ""); cur_id=$0 }
        /^[[:space:]]*-?[[:space:]]*id:[[:space:]]/ { s=$0; sub(/.*id:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); if (s ~ /^cmd_/) cur_id=s }
        cur_id == cmd && /scout_exempt:[[:space:]]*true/ { print "true"; exit }
    ')

    [ "$result" = "true" ] || { echo "Expected 'true' but got '$result'"; false; }
}

@test "scout_gate AWK returns empty when scout_exempt is false" {
    local stk_yaml
    stk_yaml=$(cat <<'YAML'
commands:
  cmd_1656:
    status: pending
    acceptance_criteria:
      - id: AC1
        description: "first"
    scout_exempt: false
YAML
)

    local result
    result=$(echo "$stk_yaml" | awk -v cmd="cmd_1656" '
        /^  [a-zA-Z_].*:$/ { sub(/^[[:space:]]*/, ""); sub(/:$/, ""); cur_id=$0 }
        /^[[:space:]]*id:[[:space:]]/ { s=$0; sub(/.*id:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); if (s ~ /^cmd_/) cur_id=s }
        cur_id == cmd && /scout_exempt:[[:space:]]*true/ { print "true"; exit }
    ')

    [ -z "$result" ] || { echo "Expected empty but got '$result'"; false; }
}
