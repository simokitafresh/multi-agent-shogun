#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    FIXTURE_ROOT="$(mktemp -d)"
    BASE_LEDGER="$FIXTURE_ROOT/script_speed_training_ledger.yaml"
    export PROJECT_ROOT FIXTURE_ROOT BASE_LEDGER

    bash "$PROJECT_ROOT/tools/bash_speed_training.sh" init-ledger "$BASE_LEDGER"
}

setup() {
    # setup_file already owns an isolated suite root. A deterministic per-test
    # directory avoids one mktemp process per case while preserving isolation.
    TMP_ROOT="$FIXTURE_ROOT/test_$BATS_TEST_NUMBER"
    mkdir -p "$TMP_ROOT"
    LEDGER="$TMP_ROOT/script_speed_training_ledger.yaml"
    cp "$BASE_LEDGER" "$LEDGER"
    export SPEED_TRAINING_LEDGER="$LEDGER"
    export SHOGUN_STATE_DIR="$TMP_ROOT/state"
    export SPEED_TRAINING_TASK_DIR="$TMP_ROOT/tasks"
    export GATE_FIRE_LOG_FILE="$TMP_ROOT/gate_fire_log.yaml"
    mkdir -p "$SPEED_TRAINING_TASK_DIR"
    AB_SEQUENCE="L,C,L,C,L,C,L,C,L,C,L,C,L,C,L,C,L,C,L,C"
    AB_ARGS=(alternating 1 env-fixture-sha256 0 0 CLEAR "$AB_SEQUENCE")

    # Source the CLI once per test so repeated subcommand assertions exercise
    # the same functions without paying a fresh Bash startup for every call.
    source "$PROJECT_ROOT/tools/bash_speed_training.sh"
}

write_multiline_ledger_fixture() {
    cat > "$LEDGER" <<'EOF'
global_status: running
entries:
- script_path: scripts/ninja_monitor.sh
  status: assigned
  before_ms: 24
  after_ms: 72
  before_real_ms: 63
  after_real_ms: 57
  real_measurement_command: NINJA_MONITOR_LIB_ONLY=1 bash scripts/ninja_monitor.sh
    (10-run median)
  test_result: bash -n OK; SCRIPT_DIR correct; tests/unit/test_ninja_monitor_*.bats
    56/56 PASS SKIP=0; before_63ms_after_57ms; 10pct_reduction
  commit: 6ddf70e86
  assigned_to: "tobisaru"
  updated_at: "2026-07-16T20:49:02"
  iteration: 1
- script_path: scripts/next.sh
  status: pending
  before_ms: 5
  after_ms: ""
  before_real_ms: ""
  after_real_ms: ""
  real_measurement_command: ""
  test_result: "baseline"
  commit: ""
  assigned_to: ""
  updated_at: ""
  iteration: 0
EOF
}

teardown() {
    rm -rf "$TMP_ROOT"
}

teardown_file() {
    rm -rf "$FIXTURE_ROOT"
}

@test "init-ledger records every scripts/*.sh file with non-destructive bash -n syntax baseline and real timing columns" {
    expected=$(find "$PROJECT_ROOT/scripts" -type f -name '*.sh' | wc -l | tr -d ' ')
    entry_count=$(grep -c 'script_path:' "$LEDGER")

    [ "$entry_count" = "$expected" ]
    grep -Fq "script_count: $expected" "$LEDGER"
    grep -Fq 'measurement_command: "timeout 5 bash -n <script_path> (syntax baseline only; not runtime speed)"' "$LEDGER"
    grep -Fq 'real_measurement_policy: "Ninja must choose a safe runtime command per script:' "$LEDGER"
    grep -Eq 'before_ms: [0-9]+' "$LEDGER"
    grep -Fq 'before_real_ms: ""' "$LEDGER"
    grep -Fq 'after_real_ms: ""' "$LEDGER"
    grep -Fq 'real_measurement_command: ""' "$LEDGER"
    grep -Fq 'global_status: running' "$LEDGER"

    # Mutation regression: deterministic ordering must not hide syntax failures.
    fixture_project="$TMP_ROOT/mutated-project"
    mkdir -p "$fixture_project/tools" "$fixture_project/scripts"
    cp "$PROJECT_ROOT/tools/bash_speed_training.sh" "$fixture_project/tools/"
    printf '#!/usr/bin/env bash\nprintf ok\n' > "$fixture_project/scripts/a_valid.sh"
    printf '#!/usr/bin/env bash\nif then\n' > "$fixture_project/scripts/b_invalid.sh"

    run bash "$fixture_project/tools/bash_speed_training.sh" init-ledger "$TMP_ROOT/mutated-ledger.yaml"
    [ "$status" -eq 0 ]
    [ "$(grep -c 'script_path:' "$TMP_ROOT/mutated-ledger.yaml")" -eq 2 ]
    awk '
        /script_path: "scripts\/a_valid.sh"/ { target = "valid" }
        /script_path: "scripts\/b_invalid.sh"/ { target = "invalid" }
        target == "valid" && /test_result: "baseline_bash_n_exit_0"/ { valid = 1; target = "" }
        target == "invalid" && /test_result: "baseline_bash_n_exit_[1-9][0-9]*"/ { invalid = 1; target = "" }
        END { exit !(valid && invalid) }
    ' "$TMP_ROOT/mutated-ledger.yaml"
}

@test "paused ledger prevents auto-deploy" {
    cmd_set_global_status paused "$LEDGER"

    run cmd_auto_deploy hayate "$LEDGER"
    [ "$status" -eq 0 ]
    [ "$output" = "paused" ]
    ! grep -Fq 'status: assigned' "$LEDGER"
}

@test "auto-deploy dry-run assigns exactly one pending script and emits deploy_task command" {
    export SPEED_TRAINING_DRY_RUN=1
    run cmd_auto_deploy hayate "$LEDGER"
    [ "$status" -eq 0 ]
    [[ "$output" == DRY_RUN\ deploy_task* ]]
    [[ "$output" == *" hayate cmd_training_speed_"* ]]

    assigned_count=$(grep -c 'status: assigned' "$LEDGER")
    [ "$assigned_count" = "1" ]
    grep -Fq 'assigned_to: "hayate"' "$LEDGER"
}

@test "failed deploy rolls reservation back while successful deploy keeps assignment" {
    fake="$TMP_ROOT/deploy.sh"
    printf '#!/usr/bin/env bash\nexit 7\n' > "$fake"
    chmod +x "$fake"
    export SPEED_TRAINING_DEPLOY_SCRIPT="$fake"
    first=$(cmd_next "$LEDGER")

    run cmd_auto_deploy hayate "$LEDGER"
    [ "$status" -eq 7 ]
    [ "$(find "$SHOGUN_STATE_DIR" -maxdepth 1 -name 'speed_training_hayate.*.yaml' | wc -l)" -eq 0 ]
    awk -v first="$first" '
        $0 ~ "script_path: \"" first "\"" { hit=1; next }
        hit && /status:/ { if ($2 != "pending") exit 1; status_ok=1 }
        hit && /assigned_to:/ { if ($2 != "\"\"") exit 1; owner_ok=1; exit }
        END { exit !(status_ok && owner_ok) }
    ' "$LEDGER"

    printf '#!/usr/bin/env bash\nexit 0\n' > "$fake"
    run cmd_auto_deploy hayate "$LEDGER"
    [ "$status" -eq 0 ]
    [ "$(find "$SHOGUN_STATE_DIR" -maxdepth 1 -name 'speed_training_hayate.*.yaml' | wc -l)" -eq 0 ]
    grep -Fq 'status: assigned' "$LEDGER"
    grep -Fq 'assigned_to: "hayate"' "$LEDGER"
}

@test "assignment preserves ledger indentation and concurrent reservations remain parseable" {
    compact="$TMP_ROOT/compact.yaml"
    cat > "$compact" <<'EOF'
global_status: running
entries:
- script_path: scripts/a.sh
  status: pending
  before_ms: 2
  assigned_to: ""
  updated_at: ""
- script_path: scripts/b.sh
  status: pending
  before_ms: 1
  assigned_to: ""
  updated_at: ""
EOF
    cmd_reserve_next hayate "$compact" > "$TMP_ROOT/one" &
    p1=$!
    cmd_reserve_next kagemaru "$compact" > "$TMP_ROOT/two" &
    p2=$!
    wait "$p1"
    wait "$p2"

    run python3 -c 'import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); assert len(d["entries"]) == 2; assert sum(e["status"] == "assigned" for e in d["entries"]) == 2' "$compact"
    [ "$status" -eq 0 ]
}

@test "malformed writer output is rejected before replacing the ledger" {
    original=$(sha256sum "$LEDGER" | cut -d' ' -f1)
    bad="$TMP_ROOT/bad.yaml"
    printf 'entries:\n- script_path: ok\n  status: [\n' > "$bad"

    run publish_ledger_yaml "$bad" "$LEDGER"
    [ "$status" -ne 0 ]
    [ "$(sha256sum "$LEDGER" | cut -d' ' -f1)" = "$original" ]
}

@test "auto-deploy skips scripts already active in task yaml" {
    first=$(cmd_next "$LEDGER")
    cat > "$SPEED_TRAINING_TASK_DIR/hayate.yaml" <<EOF
task:
  status: in_progress
  target_path: $first
EOF

    export SPEED_TRAINING_DRY_RUN=1
    run cmd_auto_deploy kagemaru "$LEDGER"
    [ "$status" -eq 0 ]
    [[ "$output" == DRY_RUN\ deploy_task* ]]

    awk -v first="$first" '
        $0 ~ "script_path: \"" first "\"" { in_first = 1; next }
        in_first && /status:/ { first_status = $2; in_first = 0 }
        /status: assigned/ { assigned_count++ }
        END { exit !(first_status == "pending" && assigned_count == 1) }
    ' "$LEDGER"
}

@test "no improvement becomes saturated and is not redeployed" {
    first=$(cmd_next "$LEDGER")
    cmd_record_after "$first" no_improvement 12 "no improvement" no_change "$LEDGER"

    grep -Fq 'status: saturated' "$LEDGER"
    export SPEED_TRAINING_DRY_RUN=1
    run cmd_auto_deploy hayate "$LEDGER"
    [ "$status" -eq 0 ]
    awk -v first="$first" '
        $0 ~ "script_path: \"" first "\"" { in_first = 1; next }
        in_first && /status: saturated/ { saturated = 1 }
        in_first && /assigned_to: "hayate"/ { bad = 1 }
        in_first && /^[[:space:]]*-[[:space:]]+script_path:/ { in_first = 0 }
        END { exit !(saturated && !bad) }
    ' "$LEDGER"
}

@test "priority selection favors hot production paths and embeds evidence contract" {
    cat > "$LEDGER" <<'EOF'
global_status: running
entries:
  - script_path: "scripts/zzz_slow.sh"
    status: pending
    before_ms: 999
    before_real_ms: ""
  - script_path: "scripts/hooks/prompt_state_inject.sh"
    status: pending
    before_ms: 12
    before_real_ms: 25
EOF
    [ "$(cmd_next "$LEDGER")" = "scripts/hooks/prompt_state_inject.sh" ]
    export SPEED_TRAINING_DRY_RUN=1
    run cmd_auto_deploy hayate "$LEDGER"
    [ "$status" -eq 0 ]
    generated_task=$(find "$SHOGUN_STATE_DIR" -type f -name 'speed_training_hayate.*.yaml' | head -n 1)
    grep -Fq 'measured_ms: 25' "$generated_task"
    grep -Fq 'priority_axis: "high-frequency hook/gate hot path"' "$generated_task"
    grep -Fq 'async timeout shortening' "$generated_task"
    grep -Fq 'FAIL=0 and SKIP=0' "$generated_task"
    grep -Fq 'detector_fp_rate' "$generated_task"
}

@test "auto-deploy generated task preserves speed purpose and real runtime ACs" {
    export SPEED_TRAINING_DRY_RUN=1
    run cmd_auto_deploy hayate "$LEDGER"
    [ "$status" -eq 0 ]

    generated_task=$(find "$SHOGUN_STATE_DIR" -type f -name 'speed_training_hayate.*.yaml' | head -n 1)
    [ -n "$generated_task" ]
    grep -Fq 'task_type: speed_training' "$generated_task"
    grep -Fq 'estimated_minutes: 5' "$generated_task"
    grep -Fq 'purpose: "Speed-train ' "$generated_task"
    grep -Fq 'historical ledger timing is selection evidence only' "$generated_task"
    grep -Fq 'alternate last-good/candidate A/B runs' "$generated_task"
    grep -Fq 'record-real stores both commits' "$generated_task"
    ! grep -Fq 'L4修行:' "$generated_task"

    run env FIELD_GET_NO_LOG=1 bash -c '
        source "$1/scripts/lib/field_get.sh"
        printf "%s %s" "$(field_get "$2" task_type "")" "$(field_get "$2" scout_exempt "")"
    ' _ "$PROJECT_ROOT" "$generated_task"
    [ "$status" -eq 0 ]
    [ "$output" = "speed_training true" ]

    run env DEPLOY_TASK_LIB_ONLY=1 bash -c '
        set -euo pipefail
        source "$1/scripts/deploy_task.sh"
        log() { :; }
        inject_direct_training_template "$2" cmd_training_speed_sample_20260606213918
    ' _ "$PROJECT_ROOT" "$generated_task"
    [ "$status" -eq 0 ]
    grep -Fq 'task_type: speed_training' "$generated_task"
    grep -Fq 'purpose: "Speed-train ' "$generated_task"
    grep -Fq 'historical ledger timing is selection evidence only' "$generated_task"
    grep -Fq 'alternate last-good/candidate A/B runs' "$generated_task"
    grep -Fq 'record-real stores both commits' "$generated_task"
    ! grep -Fq 'L4修行:' "$generated_task"
}

@test "record-after writes after measurement, test result, commit, and terminal status" {
    first=$(cmd_next "$LEDGER")

    cmd_record_after "$first" completed 12 "bats target PASS SKIP=0" abc123 "$LEDGER"

    awk -v script="$first" '
        $0 ~ "script_path: \"" script "\"" { in_target = 1 }
        in_target && /status: completed/ { status_seen = 1 }
        in_target && /after_ms: 12/ { after_seen = 1 }
        in_target && /test_result: "bats target PASS SKIP=0"/ { test_seen = 1 }
        in_target && /commit: "abc123"/ { commit_seen = 1 }
        END { exit !(status_seen && after_seen && test_seen && commit_seen) }
    ' "$LEDGER"
}

@test "record-real writes runtime before and after with measurement command" {
    first=$(cmd_next "$LEDGER")

    cmd_record_real "$first" completed good123 cand123 "time bash $first --help" 10 101 140 72 100 "bats target PASS SKIP=0" "${AB_ARGS[@]}" "$LEDGER"

    awk -v script="$first" '
        $0 ~ "script_path: \"" script "\"" { in_target = 1 }
        in_target && /status: completed/ { status_seen = 1 }
        in_target && /before_real_ms: 101/ { before_seen = 1 }
        in_target && /after_real_ms: 72/ { after_seen = 1 }
        in_target && /real_measurement_command: "time bash / { command_seen = 1 }
        in_target && /test_result: "bats target PASS SKIP=0"/ { test_seen = 1 }
        in_target && /commit: "cand123"/ { commit_seen = 1 }
        in_target && /ab_samples_per_arm: "?10"?/ { samples_seen = 1 }
        in_target && /candidate_p95_ms: 100/ { p95_seen = 1 }
        END { exit !(status_seen && before_seen && after_seen && command_seen && test_seen && commit_seen && samples_seen && p95_seen) }
    ' "$LEDGER"
}

@test "record-real read-back compares millisecond values numerically when YAML drops trailing zeroes" {
    first=$(cmd_next "$LEDGER")

    run cmd_record_real "$first" completed good123 cand123 "time bash $first --help" \
        10 137.597 181.299 120.433 171.820 "bats target PASS SKIP=0" "${AB_ARGS[@]}" "$LEDGER"

    [ "$status" -eq 0 ]
    run python3 - "$LEDGER" <<'PY'
import sys, yaml
entry = yaml.safe_load(open(sys.argv[1]))["entries"][0]
assert entry["candidate_p95_ms"] == 171.82
assert entry["status"] == "completed"
PY
    [ "$status" -eq 0 ]
}

@test "record-real batch upserts missing evidence and emits exactly one measurable event" {
    cat > "$LEDGER" <<'EOF'
global_status: running
entries:
  - script_path: scripts/legacy.sh
    status: assigned
    real_measurement_command: old command
      stale continuation
EOF

    cmd_record_real scripts/legacy.sh completed good123 cand123 $'bash scripts/legacy.sh --flag\nsecond line' \
        10 100 120 80 90 $'PASS=1 FAIL=0 SKIP=0\nverified' "${AB_ARGS[@]}" "$LEDGER"

    run python3 - "$LEDGER" "$GATE_FIRE_LOG_FILE" <<'PY'
import sys, yaml
entry = yaml.safe_load(open(sys.argv[1]))["entries"][0]
required = ("last_good_commit", "candidate_commit", "ab_samples_per_arm", "last_good_p50_ms",
            "last_good_p95_ms", "candidate_p50_ms", "candidate_p95_ms", "ab_order", "warmup_each",
            "environment_fingerprint", "fail_count", "skip_count", "hook_gate_result", "ab_sequence")
assert all(entry.get(key) not in (None, "") for key in required)
assert entry["real_measurement_command"] == "bash scripts/legacy.sh --flag\nsecond line"
assert entry["test_result"] == "PASS=1 FAIL=0 SKIP=0\nverified"
assert sum('gate: "script_speed_record_real"' in line for line in open(sys.argv[2])) == 1
PY
    [ "$status" -eq 0 ]
    ! grep -Fq 'stale continuation' "$LEDGER"

    cmd_record_real scripts/legacy.sh completed good123 cand123 $'bash scripts/legacy.sh --flag\nsecond line' \
        10 100 120 80 90 $'PASS=1 FAIL=0 SKIP=0\nverified' "${AB_ARGS[@]}" "$LEDGER"
    [ "$(grep -Fc 'gate: "script_speed_record_real"' "$GATE_FIRE_LOG_FILE")" -eq 1 ]

    out="$TMP_ROOT/fp.yaml"
    run env DETECTOR_FP_ROOT="$PROJECT_ROOT" DETECTOR_FP_GATE_FIRE_LOG="$GATE_FIRE_LOG_FILE" \
        DETECTOR_FP_CMD_QUALITY_LOG="$TMP_ROOT/quality.yaml" DETECTOR_FP_GATE_ALERTS_LOG="$TMP_ROOT/alerts.yaml" \
        bash "$PROJECT_ROOT/scripts/detector_fp_rate.sh" --out "$out"
    [ "$status" -eq 0 ]
    grep -Fq 'detector: "script_speed_record_real"' "$out"
}

@test "record-real event failure rolls ledger back without partial commit" {
    first=$(cmd_next "$LEDGER")
    original=$(sha256sum "$LEDGER" | cut -d' ' -f1)
    mkdir -p "$TMP_ROOT/event-is-directory"
    export GATE_FIRE_LOG_FILE="$TMP_ROOT/event-is-directory"

    run cmd_record_real "$first" completed good123 cand123 "bash help" 10 100 120 80 90 PASS "${AB_ARGS[@]}" "$LEDGER"
    [ "$status" -ne 0 ]
    [ "$(sha256sum "$LEDGER" | cut -d' ' -f1)" = "$original" ]
}

@test "record-real concurrent scripts commit atomically without lost entries" {
    cat > "$LEDGER" <<'EOF'
global_status: running
entries:
  - script_path: scripts/a.sh
    status: assigned
  - script_path: scripts/b.sh
    status: assigned
EOF
    cmd_record_real scripts/a.sh completed good-a cand-a "bash a" 10 100 120 80 90 "PASS A" "${AB_ARGS[@]}" "$LEDGER" &
    p1=$!
    cmd_record_real scripts/b.sh completed good-b cand-b "bash b" 10 110 130 70 80 "PASS B" "${AB_ARGS[@]}" "$LEDGER" &
    p2=$!
    wait "$p1"
    wait "$p2"
    run python3 - "$LEDGER" <<'PY'
import sys, yaml
entries = {e["script_path"]: e for e in yaml.safe_load(open(sys.argv[1]))["entries"]}
assert entries["scripts/a.sh"]["candidate_commit"] == "cand-a"
assert entries["scripts/b.sh"]["candidate_commit"] == "cand-b"
PY
    [ "$status" -eq 0 ]
}

@test "record-after replaces a multiline result without leaving stale continuation lines" {
    write_multiline_ledger_fixture

    cmd_record_after scripts/ninja_monitor.sh completed 41 "bats target PASS=72 FAIL=0 SKIP=0" abc789 "$LEDGER"

    run python3 - "$LEDGER" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
target, untouched = data["entries"]
assert target["script_path"] == "scripts/ninja_monitor.sh"
assert target["status"] == "completed"
assert target["after_ms"] == 41
assert target["test_result"] == "bats target PASS=72 FAIL=0 SKIP=0"
assert target["commit"] == "abc789"
assert untouched["script_path"] == "scripts/next.sh"
assert untouched["test_result"] == "baseline"
PY
    [ "$status" -eq 0 ]
    ! grep -Fq '56/56 PASS SKIP=0' "$LEDGER"
}

@test "record-real replaces multiline command and result without leaving stale continuation lines" {
    write_multiline_ledger_fixture

    cmd_record_real scripts/ninja_monitor.sh completed good789 abc789 \
        "NINJA_MONITOR_LIB_ONLY=1 bash scripts/ninja_monitor.sh (20-run alternating A/B)" \
        10 57 70 41 55 "bats target PASS=72 FAIL=0 SKIP=0" "${AB_ARGS[@]}" "$LEDGER"

    run python3 - "$LEDGER" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
target, untouched = data["entries"]
assert target["script_path"] == "scripts/ninja_monitor.sh"
assert target["status"] == "completed"
assert target["before_real_ms"] == 57
assert target["after_real_ms"] == 41
assert target["real_measurement_command"] == "NINJA_MONITOR_LIB_ONLY=1 bash scripts/ninja_monitor.sh (20-run alternating A/B)"
assert target["test_result"] == "bats target PASS=72 FAIL=0 SKIP=0"
assert target["commit"] == "abc789"
assert untouched["script_path"] == "scripts/next.sh"
assert untouched["test_result"] == "baseline"
PY
    [ "$status" -eq 0 ]
    ! grep -Fq '(10-run median)' "$LEDGER"
    ! grep -Fq '56/56 PASS SKIP=0' "$LEDGER"
}

@test "record-real completed rejects non-improving runtime" {
    first=$(cmd_next "$LEDGER")

    run cmd_record_real "$first" completed good123 cand123 "time bash $first --help" 10 101 140 101 140 "bats target PASS SKIP=0" "${AB_ARGS[@]}" "$LEDGER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"strict improvement"* ]]
}

@test "record-real blocks historical-only evidence and p95 regression" {
    first=$(cmd_next "$LEDGER")

    run cmd_record_real "$first" completed 101 72 "time bash $first --help" "PASS SKIP=0" old123 "$LEDGER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"complete same-environment A/B evidence"* ]]

    run cmd_record_real "$first" completed good123 bad123 "time bash $first --help" 10 101 120 90 121 "PASS SKIP=0" "${AB_ARGS[@]}" "$LEDGER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"p95 regression"* ]]
}

@test "record-real rejects invalid A/B identity order environment and quality before ledger mutation" {
    first=$(cmd_next "$LEDGER")
    original=$(sha256sum "$LEDGER" | cut -d' ' -f1)
    base=("$first" completed good123 cand123 "time bash $first --help" 10 101 120 90 110 "PASS SKIP=0")

    run cmd_record_real "${base[@]:0:3}" good123 "${base[@]:4}" "${AB_ARGS[@]}" "$LEDGER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"must differ"* ]]
    [ "$(sha256sum "$LEDGER" | cut -d' ' -f1)" = "$original" ]

    run cmd_record_real "${base[@]}" grouped 1 env-fixture-sha256 0 0 CLEAR "$AB_SEQUENCE" "$LEDGER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"ab_order must be alternating"* ]]

    run cmd_record_real "${base[@]}" alternating 1 '' 0 0 CLEAR "$AB_SEQUENCE" "$LEDGER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"environment_fingerprint is required"* ]]

    run cmd_record_real "${base[@]}" alternating 1 env-fixture-sha256 1 0 CLEAR "$AB_SEQUENCE" "$LEDGER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"FAIL=0 and SKIP=0"* ]]

    run cmd_record_real "${base[@]}" alternating 1 env-fixture-sha256 0 1 CLEAR "$AB_SEQUENCE" "$LEDGER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"FAIL=0 and SKIP=0"* ]]

    run cmd_record_real "${base[@]}" alternating 1 env-fixture-sha256 0 0 BLOCK "$AB_SEQUENCE" "$LEDGER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"hook/gate result must be CLEAR"* ]]

    run cmd_record_real "${base[@]}" alternating 1 env-fixture-sha256 0 0 CLEAR 'L,L,C,C' "$LEDGER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"sequence must alternate"* ]]
    [ "$(sha256sum "$LEDGER" | cut -d' ' -f1)" = "$original" ]
}

@test "record-real saturated retains last-good and re-enqueue cannot adopt regression" {
    first=$(cmd_next "$LEDGER")

    cmd_record_real "$first" saturated good123 bad123 "time bash $first --help" 10 101 120 90 121 "PASS SKIP=0" "${AB_ARGS[@]}" "$LEDGER"
    run python3 - "$LEDGER" "$first" <<'PY'
import sys, yaml
entry = next(e for e in yaml.safe_load(open(sys.argv[1]))["entries"] if e["script_path"] == sys.argv[2])
assert entry["status"] == "saturated"
assert entry["commit"] == "good123"
assert entry["last_good_commit"] == "good123"
assert entry["candidate_commit"] == "bad123"
PY
    [ "$status" -eq 0 ]
    run cmd_re_enqueue 20 "$LEDGER"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "re-enqueue returns top completed entries to pending and carries after_real_ms into next before_real_ms" {
    first=$(cmd_next "$LEDGER")
    cmd_record_real "$first" completed good123 abc123 "time bash $first --help" 10 200 240 50 80 "PASS SKIP=0" "${AB_ARGS[@]}" "$LEDGER"
    second=$(cmd_next "$LEDGER")
    cmd_record_real "$second" completed good456 def456 "time bash $second --help" 10 300 340 100 140 "PASS SKIP=0" "${AB_ARGS[@]}" "$LEDGER"

    run cmd_re_enqueue 1 "$LEDGER"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]

    awk -v first="$first" -v second="$second" '
        $0 ~ "script_path: \"" first "\"" { in_first = 1; in_second = 0; next }
        $0 ~ "script_path: \"" second "\"" { in_second = 1; in_first = 0; next }
        in_first && /status: completed/ { first_completed = 1 }
        in_second && /status: pending/ { second_pending = 1 }
        in_second && /before_real_ms: 100/ { second_before = 1 }
        in_second && /after_real_ms: ""/ { second_after_cleared = 1 }
        in_second && /iteration: 1/ { second_iteration = 1 }
        END { exit !(first_completed && second_pending && second_before && second_after_cleared && second_iteration) }
    ' "$LEDGER"
}

@test "re-enqueue preserves decimal after_real_ms values" {
    first=$(cmd_next "$LEDGER")
    cmd_record_real "$first" completed good123 abc123 "time bash $first --help" 10 24.565 30 16.634 20 "PASS SKIP=0" "${AB_ARGS[@]}" "$LEDGER"

    run cmd_re_enqueue 1 "$LEDGER"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]

    awk -v first="$first" '
        $0 ~ "script_path: \"" first "\"" { in_first = 1; next }
        in_first && /status: pending/ { pending = 1 }
        in_first && /before_real_ms: 16.634/ { before_decimal = 1 }
        in_first && /after_real_ms: ""/ { after_cleared = 1 }
        END { exit !(pending && before_decimal && after_cleared) }
    ' "$LEDGER"
}

@test "re-enqueue stops at max iteration" {
    first=$(cmd_next "$LEDGER")
    cmd_record_real "$first" completed good123 abc123 "time bash $first --help" 10 200 240 100 140 "PASS SKIP=0" "${AB_ARGS[@]}" "$LEDGER"
    cmd_re_enqueue 1 "$LEDGER" 1
    cmd_record_real "$first" completed abc123 def456 "time bash $first --help" 10 100 140 80 120 "PASS SKIP=0" "${AB_ARGS[@]}" "$LEDGER"

    run cmd_re_enqueue 1 "$LEDGER" 1
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]

    awk -v first="$first" '
        $0 ~ "script_path: \"" first "\"" { in_first = 1; next }
        in_first && /status: completed/ { completed = 1 }
        in_first && /iteration: 1/ { iteration = 1 }
        END { exit !(completed && iteration) }
    ' "$LEDGER"
}

@test "re-enqueue default max iteration is 3 and excludes iteration 3 completed entries" {
    cat > "$LEDGER" <<EOF
global_status: running
entries:
  - script_path: "scripts/iteration_three.sh"
    status: completed
    before_real_ms: 80
    after_real_ms: 40
    iteration: 3
    assigned_to: ""
    updated_at: ""
EOF

    run cmd_re_enqueue 20 "$LEDGER"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]

    awk '
        /script_path: "scripts\/iteration_three.sh"/ { in_target = 1; next }
        in_target && /status: completed/ { completed = 1 }
        in_target && /iteration: 3/ { iteration = 1 }
        END { exit !(completed && iteration) }
    ' "$LEDGER"
}

@test "ninja_monitor re-enqueues completed speed training when no pending or assigned work remains" {
    cat > "$LEDGER" <<EOF
global_status: running
entries:
  - script_path: "scripts/sample_slow.sh"
    status: completed
    before_real_ms: 200
    after_real_ms: 100
    iteration: 0
    assigned_to: ""
    updated_at: ""
EOF

    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export SPEED_TRAINING_LEDGER="'"$LEDGER"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
log() { :; }
if _speed_training_pipeline_has_work; then
    printf "work"
else
    printf "none"
fi
'
    [ "$status" -eq 0 ]
    [ "$output" = "work" ]
    grep -Fq 'status: pending' "$LEDGER"
    grep -Fq 'before_real_ms: 100' "$LEDGER"
    grep -Fq 'iteration: 1' "$LEDGER"
}

@test "ninja_monitor handles speed training before legacy training auto-deploy" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

calls=""
_handle_post_clear_pending() { return 1; }
_handle_deploy_stall() { return 1; }
_clear_stall_tracking_for_completed_idle() { :; }
_handle_idle_notify() { :; }
_record_training_effect() { :; }
_trigger_training_completion_check() { :; }
_handle_reflux_auto_deploy() { return 1; }
_handle_test_speed_auto_deploy() { return 1; }
_handle_speed_training_auto_deploy() { calls="${calls}speed "; return 0; }
_handle_training_auto_deploy() { calls="${calls}legacy "; return 0; }
_handle_auto_clear() { calls="${calls}clear "; return 0; }

declare -gA PREV_STATE
handle_confirmed_idle hayate
printf "%s" "$calls"
'
    [ "$status" -eq 0 ]
    [ "$output" = "speed " ]
}
