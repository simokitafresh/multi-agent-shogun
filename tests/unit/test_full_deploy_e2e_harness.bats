#!/usr/bin/env bats
# test_necessity: full-deploy harnessはlost・duplicate・stale・telemetry異常を成功として受理しない

load '../helpers/deploy_task_scaffold'

setup_file() { deploy_task_setup_file; }
setup() {
    full_deploy_e2e_setup
    export BENCH="$PROJECT_ROOT/scripts/benchmark_full_deploy_e2e.sh"
    export FAKE="$TEST_TMPDIR/fake_full_deploy.sh"
    cat > "$FAKE" <<'EOF'
#!/usr/bin/env bash
set -eu
mode=$1 run=$2 telemetry=$3
printf -- '- id: msg_%s\n  read: false\n' "$run" >> "$PROJECT_ROOT/queue/inbox/sasuke.yaml"
printf 'status: completed\n' > "$PROJECT_ROOT/queue/reports/report_${run}.yaml"
printf 'phase=deploy cache=%s subprocess=1 rc=0\n' "$([[ $mode == warm ]] && echo hit || echo miss)" >> "$telemetry"
EOF
    chmod +x "$FAKE"
}

@test "canonical cold3 warm3 emits durable N6 summary" {
    run bash "$BENCH" --project "$TEST_PROJECT" --runner "$FAKE" --output "$FULL_DEPLOY_E2E_RESULTS"
    [ "$status" -eq 0 ]
    [ "$(grep -c $'^\([1-6]\)\t' "$FULL_DEPLOY_E2E_RESULTS")" -eq 6 ]
    grep -q $'^SUMMARY\tN6\t.*\tPASS$' "$FULL_DEPLOY_E2E_RESULTS"
    [ "$(grep -c $'\tcold\t' "$FULL_DEPLOY_E2E_RESULTS")" -eq 3 ]
    [ "$(grep -c $'\twarm\t' "$FULL_DEPLOY_E2E_RESULTS")" -eq 3 ]
}

@test "missing fixture blocks before runner" {
    rm "$TEST_PROJECT/logs/gates.log"
    run bash "$BENCH" --project "$TEST_PROJECT" --runner "$FAKE" --output "$FULL_DEPLOY_E2E_RESULTS"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK: missing fixture"* ]]
}

@test "detects lost duplicate stale and telemetry failures" {
    sed -i '/printf --/d; /queue\/reports/d; /phase=/d' "$FAKE"
    printf 'touch "$PROJECT_ROOT/archive/reports/stale_${run}.yaml"\n' >> "$FAKE"
    run bash "$BENCH" --project "$TEST_PROJECT" --runner "$FAKE" --output "$FULL_DEPLOY_E2E_RESULTS" --runs 1 --cold-runs 1
    [ "$status" -eq 1 ]
    grep -q $'^1\t.*\t0\t0\t0\t0\t0\t1\tFAIL$' "$FULL_DEPLOY_E2E_RESULTS"

    cat > "$FAKE" <<'EOF'
#!/usr/bin/env bash
printf -- '- id: a\n- id: b\n' >> "$PROJECT_ROOT/queue/inbox/sasuke.yaml"
printf 'x\n' > "$PROJECT_ROOT/queue/reports/a"
printf 'y\n' > "$PROJECT_ROOT/queue/reports/b"
printf 'phase=x cache=x subprocess=x\n' >> "$3"
EOF
    chmod +x "$FAKE"
    run bash "$BENCH" --project "$TEST_PROJECT" --runner "$FAKE" --output "$FULL_DEPLOY_E2E_RESULTS" --runs 1 --cold-runs 1
    [ "$status" -eq 1 ]
    grep -q $'^SUMMARY\tN1\t.*\t1\tFAIL$' "$FULL_DEPLOY_E2E_RESULTS"
}
