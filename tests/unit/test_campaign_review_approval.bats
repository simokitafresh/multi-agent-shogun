#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  T="$BATS_TEST_TMPDIR/root"
  mkdir -p "$T/scripts/lib" "$T/queue/reports" "$T/queue/campaign_lane/run/state/shards/A1/output_dir"
  cp "$ROOT/scripts/lib/review_approval.sh" "$T/scripts/lib/review_approval.sh"
  printf 'state_dir: %s\nitems:\n- id: A1\n  contract_fingerprint: %s\n' "$T/queue/campaign_lane/run/state" "$(printf 'a%.0s' {1..64})" >"$T/queue/campaign_lane/run/manifest.yaml"
  printf 'status: completed\ncommit_hash: %s\nparent_contract_fingerprint: %s\nfiles_modified: []\n' "$(printf '1%.0s' {1..40})" "$(printf 'a%.0s' {1..64})" >"$T/queue/reports/report.yaml"
  printf '{"status":"success","item_id":"A1","commit_sha":"%s","fail_count":0,"skip_count":0}\n' "$(printf '1%.0s' {1..40})" >"$T/queue/campaign_lane/run/state/shards/A1/output_dir/result.json"
}

validate() { env PROJECT_ROOT="$T" bash -c 'source "$1/scripts/lib/review_approval.sh"; review_validate_report campaign_lane_A1 "$1/queue/reports/report.yaml"' _ "$T"; }

@test "manifest result and report fingerprints approve a parentless campaign shard" {
  run validate
  [ "$status" -eq 0 ]
}

@test "changed report commit is fail closed" {
  sed -i "s/$(printf '1%.0s' {1..40})/$(printf '2%.0s' {1..40})/" "$T/queue/reports/report.yaml"
  run validate
  [ "$status" -ne 0 ]
}

@test "stale manifest contract is fail closed" {
  sed -i "s/$(printf 'a%.0s' {1..64})/$(printf 'b%.0s' {1..64})/" "$T/queue/reports/report.yaml"
  run validate
  [ "$status" -ne 0 ]
}

@test "recovery cache reuses unchanged content and invalidates changed content" {
  local cache="$BATS_TEST_TMPDIR/cache" required="$BATS_TEST_TMPDIR/deepdive.md"
  printf 'phase1\nphase2\n' >"$required"
  run env GUNSHI_RECOVERY_SESSION_ID=s1 GUNSHI_RECOVERY_CACHE_DIR="$cache" bash "$ROOT/scripts/gates/gate_gunshi_startup.sh" --recovery-cache-check "$required"
  [ "$status" -eq 0 ]; [[ "$output" == "READ_REQUIRED "* ]]
  run env GUNSHI_RECOVERY_SESSION_ID=s1 GUNSHI_RECOVERY_CACHE_DIR="$cache" bash "$ROOT/scripts/gates/gate_gunshi_startup.sh" --recovery-cache-mark "$required"
  [ "$status" -eq 0 ]
  run env GUNSHI_RECOVERY_SESSION_ID=s1 GUNSHI_RECOVERY_CACHE_DIR="$cache" bash "$ROOT/scripts/gates/gate_gunshi_startup.sh" --recovery-cache-check "$required"
  [ "$status" -eq 0 ]; [[ "$output" == "CACHED "* ]]
  printf 'phase3\n' >>"$required"
  run env GUNSHI_RECOVERY_SESSION_ID=s1 GUNSHI_RECOVERY_CACHE_DIR="$cache" bash "$ROOT/scripts/gates/gate_gunshi_startup.sh" --recovery-cache-check "$required"
  [ "$status" -eq 0 ]; [[ "$output" == "READ_REQUIRED "* ]]
}

@test "recovery cache is isolated by session" {
  local cache="$BATS_TEST_TMPDIR/cache" required="$BATS_TEST_TMPDIR/skill.md"
  printf 'required SG contract\n' >"$required"
  env GUNSHI_RECOVERY_SESSION_ID=s1 GUNSHI_RECOVERY_CACHE_DIR="$cache" bash "$ROOT/scripts/gates/gate_gunshi_startup.sh" --recovery-cache-mark "$required"
  run env GUNSHI_RECOVERY_SESSION_ID=s2 GUNSHI_RECOVERY_CACHE_DIR="$cache" bash "$ROOT/scripts/gates/gate_gunshi_startup.sh" --recovery-cache-check "$required"
  [ "$status" -eq 0 ]; [[ "$output" == "READ_REQUIRED "* ]]
}
