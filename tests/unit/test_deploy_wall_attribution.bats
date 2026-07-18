#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  OUT="$BATS_TEST_TMPDIR/out"
  mkdir -p "$OUT"
}

fixture() {
  local total="$1" body="$2" file="$BATS_TEST_TMPDIR/$total.log"
  printf '%b\nDEPLOY_RECEIPT result=success rc=0 wall_ms=%s phase=post_delivery\n' "$body" "$total" >"$file"
  echo "$file"
}

@test "normal intervals close total and emit durable JSON TSV" {
  f="$(fixture 100000 'DEPLOY_WALL_EVENT name=preflight start_ms=0 end_ms=20000\nDEPLOY_WALL_EVENT name=git_lock_wait start_ms=20000 end_ms=50000\nDEPLOY_WALL_EVENT name=delivery_wait start_ms=50000 end_ms=100000')"
  run bash "$ROOT/scripts/deploy_wall_attribution.sh" --artifact-dir "$OUT" --input "$f"
  [ "$status" -eq 0 ]
  grep -q '"top_contributor": "delivery_wait"' "$OUT"/*.json
  grep -q $'sum_error_ratio\t0.0' "$OUT"/*.tsv
}

@test "84.773 124.104 157.716 161.758 second fixtures select exact maximum with no FP FN" {
  for total in 84773 124104 157716 161758; do
    a=$((total/5)); b=$((total-a))
    f="$(fixture "$total" "DEPLOY_WALL_EVENT name=preflight start_ms=0 end_ms=$a\nDEPLOY_WALL_EVENT name=delivery_wait start_ms=$a end_ms=$b\nDEPLOY_WALL_EVENT name=git_lock_wait start_ms=$b end_ms=$total")"
    run bash "$ROOT/scripts/deploy_wall_attribution.sh" --artifact-dir "$OUT/$total" --input "$f"
    [ "$status" -eq 0 ]
    grep -q '"top_contributor": "delivery_wait"' "$OUT/$total"/*.json
    grep -q '"unattributed": 0' "$OUT/$total"/*.json
  done
}

@test "missing phase leaves exact gap and blocks above five percent" {
  f="$(fixture 100000 'DEPLOY_WALL_EVENT name=preflight start_ms=0 end_ms=40000\nDEPLOY_WALL_EVENT name=delivery_wait start_ms=60000 end_ms=100000')"
  run bash "$ROOT/scripts/deploy_wall_attribution.sh" --artifact-dir "$OUT" --input "$f"
  [ "$status" -eq 0 ]
  grep -q '"phase_gap": 20000' "$OUT"/*.json
}

@test "duration-only partial telemetry fails closed with exact unattributed" {
  f="$(fixture 100000 'TASK_MUTATION_PHASE phase=render wall_ms=40000 rc=0 subprocesses=0 report_scans=0')"
  run bash "$ROOT/scripts/deploy_wall_attribution.sh" --artifact-dir "$OUT" --input "$f"
  [ "$status" -eq 3 ]
  grep -q '"unattributed": 60000' "$OUT"/*.json
}

@test "overlap and missing receipt are rejected without false attribution" {
  f="$(fixture 100000 'DEPLOY_WALL_EVENT name=a start_ms=0 end_ms=70000\nDEPLOY_WALL_EVENT name=b start_ms=60000 end_ms=100000')"
  run bash "$ROOT/scripts/deploy_wall_attribution.sh" --artifact-dir "$OUT/a" --input "$f"
  [ "$status" -ne 0 ]
  echo plain >"$BATS_TEST_TMPDIR/missing.log"
  run bash "$ROOT/scripts/deploy_wall_attribution.sh" --artifact-dir "$OUT/b" --input "$BATS_TEST_TMPDIR/missing.log"
  [ "$status" -ne 0 ]
}
