#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  TMP="$(mktemp -d "$BATS_TMPDIR/reflux-ledger.XXXXXX")"
  mkdir -p "$TMP/queue/reports" "$TMP/archive/reports" "$TMP/logs"
}
teardown() { rm -rf "$TMP"; }

@test "foreign-dirty decision defers until target fingerprint changes" {
  mkdir -p "$TMP/scripts/gates" "$TMP/projects/dm-signal" "$TMP/tasks" "$TMP/state"
  cat > "$TMP/scripts/gates/gate_lesson_enforcement_level.sh" <<'EOF'
#!/usr/bin/env bash
echo '##ENFORCEMENT_LEVEL_BELOW4_COUNT##'; echo 1; echo '=== 昇格候補一覧'; echo '  - [dm-signal] L900 guarded'
EOF
  chmod +x "$TMP/scripts/gates/gate_lesson_enforcement_level.sh"
  echo lesson-v1 > "$TMP/projects/dm-signal/lessons.yaml"
  echo cache-v1 > "$TMP/tasks/lessons.md"
  cat > "$TMP/queue/reports/kagemaru_report_cmd_reflux_promotion_fixture.yaml" <<'EOF'
parent_cmd: cmd_reflux_promotion_fixture
status: completed
verdict: PASS
result: {summary: "L900 foreign dirty cacheで停止"}
decision_candidate: {found: true, title: "L900 foreign dirty解消待ち"}
binary_checks: {AC1: [{check: "昇格候補 L900", result: yes}]}
EOF
  run bash -c 'export NINJA_MONITOR_LIB_ONLY=1; source "$1/scripts/ninja_monitor.sh"; SCRIPT_DIR="$2"; STATE_DIR="$2/state"; REFLUX_PROMOTION_LEDGER="$2/logs/completed.tsv"; REFLUX_PROMOTION_DEFERRED_LEDGER="$2/logs/deferred.tsv"; _reflux_promotion_inventory; _reflux_promotion_inventory; grep -c $'"'"'\tL900\t'"'"' "$2/logs/deferred.tsv"' _ "$ROOT" "$TMP"
  [ "$status" -eq 0 ]; [ "$(printf '%s\n' "$output" | grep -c $'^0\t-\tok$')" -eq 2 ]; [ "${output##*$'\n'}" = 1 ]
  echo cache-v2 > "$TMP/tasks/lessons.md"
  run bash -c 'export NINJA_MONITOR_LIB_ONLY=1; source "$1/scripts/ninja_monitor.sh"; SCRIPT_DIR="$2"; STATE_DIR="$2/state"; REFLUX_PROMOTION_LEDGER="$2/logs/completed.tsv"; REFLUX_PROMOTION_DEFERRED_LEDGER="$2/logs/deferred.tsv"; _reflux_promotion_inventory' _ "$ROOT" "$TMP"
  [ "$status" -eq 0 ]; [[ "$output" == $'1\t[dm-signal] L900 guarded\tok' ]]
}

@test "four parallel inventories create one deferred row and suppress one lesson" {
  mkdir -p "$TMP/scripts/gates" "$TMP/projects/dm-signal" "$TMP/tasks" "$TMP/state"
  printf '#!/usr/bin/env bash\necho "##ENFORCEMENT_LEVEL_BELOW4_COUNT##"; echo 1; echo "=== 昇格候補一覧"; echo "  - [dm-signal] L900 guarded"\n' > "$TMP/scripts/gates/gate_lesson_enforcement_level.sh"; chmod +x "$TMP/scripts/gates/gate_lesson_enforcement_level.sh"
  echo lesson > "$TMP/projects/dm-signal/lessons.yaml"; echo cache > "$TMP/tasks/lessons.md"
  cat > "$TMP/queue/reports/kagemaru_report_cmd_reflux_promotion_fixture.yaml" <<'EOF'
parent_cmd: cmd_reflux_promotion_fixture
status: failed
verdict: FAIL
result: {summary: "L900 foreign-dirty cache"}
decision_candidate: {found: true, title: blocked}
EOF
  run bash -c 'export NINJA_MONITOR_LIB_ONLY=1; source "$1/scripts/ninja_monitor.sh"; SCRIPT_DIR="$2"; STATE_DIR="$2/state"; REFLUX_PROMOTION_LEDGER="$2/logs/completed.tsv"; REFLUX_PROMOTION_DEFERRED_LEDGER="$2/logs/deferred.tsv"; for _ in 1 2 3 4; do _reflux_promotion_inventory & done; wait; grep -c $'"'"'\tL900\t'"'"' "$2/logs/deferred.tsv"' _ "$ROOT" "$TMP"
  [ "$status" -eq 0 ]; [ "$(printf '%s\n' "$output" | grep -c $'^0\t-\tok$')" -eq 4 ]; [ "${output##*$'\n'}" = 1 ]
}

@test "completion append is idempotent and hot lookup avoids report parsing" {
  cat > "$TMP/queue/reports/hayate_report_cmd_reflux_promotion_x.yaml" <<'EOF'
parent_cmd: cmd_reflux_promotion_x
status: completed
verdict: PASS
result: {summary: "LS-A16をLevel5へ昇格済み"}
binary_checks: {AC1: [{check: "昇格候補 LS-A16 を確認", result: yes}]}
EOF
  run bash -c 'export NINJA_MONITOR_LIB_ONLY=1; source "$1/scripts/ninja_monitor.sh"; SCRIPT_DIR="$2"; REFLUX_PROMOTION_LEDGER="$2/logs/ledger.tsv"; _reflux_promotion_record_completion "$2/queue/reports/hayate_report_cmd_reflux_promotion_x.yaml"; _reflux_promotion_record_completion "$2/queue/reports/hayate_report_cmd_reflux_promotion_x.yaml"; _reflux_promotion_completed_ids' _ "$ROOT" "$TMP"
  [ "$status" -eq 0 ]
  [ "$output" = LS-A16 ]
  [ "$(grep -c $'\tLS-A16\t' "$TMP/logs/ledger.tsv")" -eq 1 ]
  mv "$TMP/queue/reports/hayate_report_cmd_reflux_promotion_x.yaml" "$TMP/archive/reports/"
  run bash -c 'export NINJA_MONITOR_LIB_ONLY=1; source "$1/scripts/ninja_monitor.sh"; SCRIPT_DIR="$2"; REFLUX_PROMOTION_LEDGER="$2/logs/ledger.tsv"; _reflux_promotion_completed_ids' _ "$ROOT" "$TMP"
  [ "$status" -eq 0 ]
  [ "$output" = LS-A16 ]
}

@test "done task still reconciles completed PASS report before returning" {
  mkdir -p "$TMP/queue/tasks" "$TMP/scripts/lib" "$TMP/state"
  cp "$ROOT/scripts/lib/yaml_field_set.sh" "$TMP/scripts/lib/"
  cat > "$TMP/queue/tasks/hanzo.yaml" <<'EOF'
task:
  parent_cmd: cmd_reflux_promotion_fixture
  task_id: promotion_fixture
  status: done
EOF
  cat > "$TMP/queue/reports/hanzo_report_cmd_reflux_promotion_fixture.yaml" <<'EOF'
worker_id: hanzo
task_id: promotion_fixture
parent_cmd: cmd_reflux_promotion_fixture
status: completed
verdict: PASS
result: {summary: "LS092をLevel5へ昇格済み"}
binary_checks: {AC1: [{check: "昇格候補 LS092 の恒久防御を確認", result: yes}]}
EOF
  run bash -c 'export NINJA_MONITOR_LIB_ONLY=1; source "$1/scripts/ninja_monitor.sh"; SCRIPT_DIR="$2"; STATE_DIR="$2/state"; REFLUX_PROMOTION_LEDGER="$2/logs/ledger.tsv"; check_and_update_done_task hanzo; check_and_update_done_task hanzo; grep -c $'"'"'\tLS092\t'"'"' "$2/logs/ledger.tsv"' _ "$ROOT" "$TMP"
  [ "$status" -eq 0 ]
  [ "$output" = 1 ]
}

@test "backfill produces zero diff and extra ledger entry blocks" {
  cat > "$TMP/queue/reports/hayate_report_cmd_reflux_promotion_x.yaml" <<'EOF'
parent_cmd: cmd_reflux_promotion_x
status: completed
verdict: PASS
result: {summary: "LG044をLevel5へ昇格済み"}
EOF
  run bash -c 'export NINJA_MONITOR_LIB_ONLY=1; source "$1/scripts/ninja_monitor.sh"; SCRIPT_DIR="$2"; REFLUX_PROMOTION_LEDGER="$2/logs/ledger.tsv"; _reflux_promotion_backfill_and_check' _ "$ROOT" "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"diff=0"* ]]
  printf 'x\tLS999\ttampered\n' >> "$TMP/logs/ledger.tsv"
  run bash -c 'export NINJA_MONITOR_LIB_ONLY=1; source "$1/scripts/ninja_monitor.sh"; SCRIPT_DIR="$2"; REFLUX_PROMOTION_LEDGER="$2/logs/ledger.tsv"; _reflux_promotion_backfill_and_check' _ "$ROOT" "$TMP"
  [ "$status" -ne 0 ]
  [[ "$output" == BLOCK* ]]
}

@test "inventory cache invalidates when lesson primary data changes" {
  mkdir -p "$TMP/scripts/gates" "$TMP/projects/infra" "$TMP/state"
  cat > "$TMP/scripts/gates/gate_lesson_enforcement_level.sh" <<'EOF'
#!/usr/bin/env bash
echo run >> "$LESSON_ENFORCEMENT_ROOT/gate.calls"
echo '##ENFORCEMENT_LEVEL_BELOW4_COUNT##'; echo 0; echo '=== 昇格候補一覧'
EOF
  chmod +x "$TMP/scripts/gates/gate_lesson_enforcement_level.sh"
  echo 'lessons: []' > "$TMP/projects/infra/lessons_shogun.yaml"
  run bash -c 'export NINJA_MONITOR_LIB_ONLY=1; source "$1/scripts/ninja_monitor.sh"; SCRIPT_DIR="$2"; STATE_DIR="$2/state"; REFLUX_PROMOTION_LEDGER="$2/logs/ledger.tsv"; _reflux_promotion_inventory; _reflux_promotion_inventory; echo "calls=$(wc -l < "$2/gate.calls")"' _ "$ROOT" "$TMP"
  [ "$status" -eq 0 ]; [[ "$output" == *"calls=1"* ]]
  sleep 1; echo '# changed' >> "$TMP/projects/infra/lessons_shogun.yaml"
  run bash -c 'export NINJA_MONITOR_LIB_ONLY=1; source "$1/scripts/ninja_monitor.sh"; SCRIPT_DIR="$2"; STATE_DIR="$2/state"; REFLUX_PROMOTION_LEDGER="$2/logs/ledger.tsv"; _reflux_promotion_inventory; echo "calls=$(wc -l < "$2/gate.calls")"' _ "$ROOT" "$TMP"
  [ "$status" -eq 0 ]; [[ "$output" == *"calls=2"* ]]
}

@test "existing ledger reconciles LS092 once under sequential and parallel inventory" {
  mkdir -p "$TMP/scripts/gates" "$TMP/projects/infra" "$TMP/state"
  cat > "$TMP/scripts/gates/gate_lesson_enforcement_level.sh" <<'EOF'
#!/usr/bin/env bash
echo '##ENFORCEMENT_LEVEL_BELOW4_COUNT##'; echo 1; echo '=== 昇格候補一覧'; echo '  - [lessons_shogun.yaml] LS092 stale metadata'
EOF
  chmod +x "$TMP/scripts/gates/gate_lesson_enforcement_level.sh"
  echo 'lessons: []' > "$TMP/projects/infra/lessons_shogun.yaml"
  printf 'completed_at\tlesson_id\treport\n' > "$TMP/logs/ledger.tsv"
  cat > "$TMP/queue/reports/saizo_report_cmd_reflux_promotion_fixture.yaml" <<'EOF'
parent_cmd: cmd_reflux_promotion_fixture
status: completed
verdict: PASS
result: {summary: "LS092はLevel4へ昇格済み"}
EOF
  run bash -c 'export NINJA_MONITOR_LIB_ONLY=1; source "$1/scripts/ninja_monitor.sh"; SCRIPT_DIR="$2"; STATE_DIR="$2/state"; REFLUX_PROMOTION_LEDGER="$2/logs/ledger.tsv"; for _ in 1 2 3 4; do _reflux_promotion_inventory; done; wait' _ "$ROOT" "$TMP"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c $'^0\t-\tok$')" -eq 4 ]
  run bash -c 'export NINJA_MONITOR_LIB_ONLY=1; source "$1/scripts/ninja_monitor.sh"; SCRIPT_DIR="$2"; STATE_DIR="$2/state"; REFLUX_PROMOTION_LEDGER="$2/logs/ledger.tsv"; for _ in 1 2 3 4; do _reflux_promotion_inventory & done; wait; grep -c $'"'"'\tLS092\t'"'"' "$2/logs/ledger.tsv"' _ "$ROOT" "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'0\t-\tok'* ]]
  [ "${output##*$'\n'}" = 1 ]
}

@test "warm inventory never rescans completed reports after one-time reconciliation" {
  mkdir -p "$TMP/scripts/gates" "$TMP/projects/infra" "$TMP/state"
  cat > "$TMP/scripts/gates/gate_lesson_enforcement_level.sh" <<'EOF'
#!/usr/bin/env bash
echo '##ENFORCEMENT_LEVEL_BELOW4_COUNT##'; echo 0; echo '=== 昇格候補一覧'
EOF
  chmod +x "$TMP/scripts/gates/gate_lesson_enforcement_level.sh"
  echo 'lessons: []' > "$TMP/projects/infra/lessons_shogun.yaml"
  printf 'completed_at\tlesson_id\treport\n' > "$TMP/logs/ledger.tsv"
  run bash -c 'export NINJA_MONITOR_LIB_ONLY=1; source "$1/scripts/ninja_monitor.sh"; SCRIPT_DIR="$2"; STATE_DIR="$2/state"; REFLUX_PROMOTION_LEDGER="$2/logs/ledger.tsv"; _reflux_promotion_inventory >/dev/null; _reflux_promotion_scan_completed_ids() { echo unexpected-rescan; return 99; }; for _ in 1 2 3 4; do _reflux_promotion_inventory; done' _ "$ROOT" "$TMP"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c $'^0\t-\tok$')" -eq 4 ]
}
