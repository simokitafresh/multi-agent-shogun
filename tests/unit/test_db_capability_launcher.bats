#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LAUNCHER="$ROOT/scripts/db_capability_launcher.py"
  CREDS="$BATS_TEST_TMPDIR/db.env"
  printf 'DATABASE_URL=postgresql://invalid\n' > "$CREDS"
  chmod 600 "$CREDS"
}

@test "unknown capability fails closed before child" {
  run python3 "$LAUNCHER" --capability unknown --mode readonly --confirm nope --nonce "$BATS_TEST_NAME" --credential-file "$CREDS"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown capability"* ]]
}

@test "readonly rejects altered mode" {
  run python3 "$LAUNCHER" --capability readonly_query --mode write --confirm READONLY_DB_CHECK --nonce "$BATS_TEST_NAME" --credential-file "$CREDS"
  [ "$status" -ne 0 ]
  [[ "$output" == *"mode is not permitted"* ]]
}

@test "restore requires current expected commit" {
  run python3 "$LAUNCHER" --capability transactional_restore --mode transactional_restore --confirm TRANSACTIONAL_RESTORE_ROLLBACK_READY --nonce "$BATS_TEST_NAME" --credential-file "$CREDS" --expected-commit deadbeef
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected commit mismatch"* ]]
}

@test "reused nonce fails closed" {
  nonce="reuse-$RANDOM"
  run python3 "$LAUNCHER" --capability readonly_query --mode readonly --confirm READONLY_DB_CHECK --nonce "$nonce" --credential-file "$CREDS"
  [ "$status" -ne 0 ]
  run python3 "$LAUNCHER" --capability readonly_query --mode readonly --confirm READONLY_DB_CHECK --nonce "$nonce" --credential-file "$CREDS"
  [ "$status" -ne 0 ]
  [[ "$output" == *"nonce already used"* ]]
}

@test "registry working-tree alteration fails closed" {
  registry="$ROOT/config/db_capabilities.json"
  cp "$registry" "$BATS_TEST_TMPDIR/registry.save"
  printf '\n ' >> "$registry"
  run python3 "$LAUNCHER" --capability readonly_query --mode readonly --confirm READONLY_DB_CHECK --nonce "$BATS_TEST_NAME" --credential-file "$CREDS"
  mv "$BATS_TEST_TMPDIR/registry.save" "$registry"
  [ "$status" -ne 0 ]
  [[ "$output" == *"registry is untracked or altered"* ]]
}
