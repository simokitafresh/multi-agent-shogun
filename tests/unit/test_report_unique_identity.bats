#!/usr/bin/env bats

setup() {
    export ROOT="$BATS_TEST_TMPDIR/root"
    mkdir -p "$ROOT/queue/reports" "$ROOT/queue/archive/reports" "$ROOT/queue/tasks"
    export HELPER="$BATS_TEST_DIRNAME/../../scripts/lib/report_unique_identity.py"
}

@test "legacy fallback includes canonical path and never collides for equal content" {
    printf 'parent_cmd: cmd_same\n' > "$ROOT/queue/reports/a.yaml"
    cp "$ROOT/queue/reports/a.yaml" "$ROOT/queue/reports/b.yaml"
    run python3 "$HELPER" resolve --root "$ROOT" --path "$ROOT/queue/reports/a.yaml"
    [ "$status" -eq 0 ]
    id_a="${output%%$'\t'*}"
    run python3 "$HELPER" resolve --root "$ROOT" --path "$ROOT/queue/reports/b.yaml"
    [ "$status" -eq 0 ]
    id_b="${output%%$'\t'*}"
    [ "$id_a" != "$id_b" ]
}

@test "fallback resolves a referenced legacy path even before the file exists" {
    run python3 "$HELPER" fallback --root "$ROOT" --path "$ROOT/queue/reports/missing.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == legacy-*$'\t'1$'\t'queue/reports/missing.yaml ]]
}

@test "v2 task and report require one matching immutable id" {
    cat > "$ROOT/queue/reports/a.yaml" <<'YAML'
report_id: rpt-fixed
report_identity_version: 2
YAML
    cat > "$ROOT/queue/tasks/ninja.yaml" <<'YAML'
task:
  report_id: rpt-fixed
  report_identity_version: 2
YAML
    run python3 "$HELPER" verify --root "$ROOT" --path "$ROOT/queue/reports/a.yaml" --task "$ROOT/queue/tasks/ninja.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == rpt-fixed$'\t'2$'\t'* ]]

    sed -i 's/rpt-fixed/rpt-reused/' "$ROOT/queue/tasks/ninja.yaml"
    run python3 "$HELPER" verify --root "$ROOT" --path "$ROOT/queue/reports/a.yaml" --task "$ROOT/queue/tasks/ninja.yaml"
    [ "$status" -eq 2 ]
    [[ "$output" == *mismatched* ]]
}

@test "v2 missing report_id fails closed" {
    printf 'report_identity_version: 2\n' > "$ROOT/queue/reports/a.yaml"
    run python3 "$HELPER" resolve --root "$ROOT" --path "$ROOT/queue/reports/a.yaml"
    [ "$status" -eq 2 ]
    [[ "$output" == *missing* ]]
}

@test "archive move retains explicit v2 identity" {
    printf 'report_id: rpt-fixed\nreport_identity_version: 2\n' > "$ROOT/queue/reports/a.yaml"
    cat > "$ROOT/queue/tasks/ninja.yaml" <<'YAML'
task:
  report_id: rpt-fixed
  report_identity_version: 2
YAML
    run python3 "$HELPER" verify --root "$ROOT" --path "$ROOT/queue/reports/a.yaml" --task "$ROOT/queue/tasks/ninja.yaml"
    [ "$status" -eq 0 ]
    mv "$ROOT/queue/reports/a.yaml" "$ROOT/queue/archive/reports/a.yaml"
    run python3 "$HELPER" resolve --root "$ROOT" --path "$ROOT/queue/archive/reports/a.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == rpt-fixed$'\t'2$'\t'* ]]
}

@test "v2 report_id reuse by a second path fails closed" {
    printf 'report_id: rpt-fixed\nreport_identity_version: 2\n' > "$ROOT/queue/reports/a.yaml"
    cp "$ROOT/queue/reports/a.yaml" "$ROOT/queue/reports/b.yaml"
    cat > "$ROOT/queue/tasks/ninja.yaml" <<'YAML'
task:
  report_id: rpt-fixed
  report_identity_version: 2
YAML
    run python3 "$HELPER" verify --root "$ROOT" --path "$ROOT/queue/reports/a.yaml" --task "$ROOT/queue/tasks/ninja.yaml"
    [ "$status" -eq 0 ]
    run python3 "$HELPER" verify --root "$ROOT" --path "$ROOT/queue/reports/b.yaml" --task "$ROOT/queue/tasks/ninja.yaml"
    [ "$status" -eq 2 ]
    [[ "$output" == *reused* ]]
}
