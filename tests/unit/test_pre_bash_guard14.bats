#!/usr/bin/env bats
# test_necessity: Guard14 passes non-DB .env reads while retaining structural DB markers.
setup() { source "$BATS_TEST_DIRNAME/../../scripts/lib/guard14_db_trust_classify.sh"; }
@test "three non-DB credential reads are not connections" {
  for command in "grep VIEWER_PASS .env" "rg '^API_TOKEN=' .env" "sed -n '/VIEWER_PASS/p' .env"; do run guard14_maybe_connection "$command"; [ "$status" -ne 0 ]; done
}
@test "DB markers remain connection candidates" {
  for command in "grep DATABASE_URL .env" "rg POSTGRES_DSN .env" "psql -h db" "python -c 'db.connect()'"; do run guard14_maybe_connection "$command"; [ "$status" -eq 0 ]; done
}

@test "CDP auth adapter is internal HTTP capability, not a DB connection" {
  local relative="python3 scripts/cdp/dm_signal_adapters.py --receipt /tmp/cdp-receipt.json auth-strategy --target-url https://dm-signal.example --required-capability viewer --env-file /mnt/c/Python_app/DM-signal/.env"
  local absolute="python3 $BATS_TEST_DIRNAME/../../scripts/cdp/dm_signal_adapters.py --receipt /tmp/cdp-receipt.json auth-strategy --target-url https://dm-signal.example --required-capability viewer --env-file /mnt/c/Python_app/DM-signal/.env"
  for command in "$relative" "$absolute"; do
    run env BATS_TEST_FILENAME="$BATS_TEST_FILENAME" COMMAND="$command" python3 -S "$BATS_TEST_DIRNAME/../../scripts/lib/guard14_db_trust_classify.py"
    [ "$status" -eq 0 ]
    [ "$output" = "not_connection" ]
  done
}

@test "CDP auth exemption rejects wrong adapter contract and chained DB access" {
  local base="python3 scripts/cdp/dm_signal_adapters.py --receipt /tmp/cdp-receipt.json"
  local commands=(
    "$base deploy-verifier --target-commit abc --repo . --env-file /mnt/c/Python_app/DM-signal/.env"
    "$base auth-strategy --target-url https://dm-signal.example --required-capability viewer --env-file /mnt/c/Python_app/DM-signal/.env --unexpected value"
    "$base auth-strategy --target-url https://dm-signal.example --required-capability viewer --env-file /mnt/c/Python_app/DM-signal/.env && python3 -c 'psycopg.connect(host=\"prod-db.example\")'"
  )
  for command in "${commands[@]}"; do
    run env BATS_TEST_FILENAME="$BATS_TEST_FILENAME" COMMAND="$command" python3 -S "$BATS_TEST_DIRNAME/../../scripts/lib/guard14_db_trust_classify.py"
    [ "$status" -eq 0 ]
    [ "$output" = "connection:untrusted" ]
  done

  for command in "python3 -c 'import psycopg; psycopg.connect(host=\"prod-db.example\")'" "DATABASE_URL=postgresql://prod-db.example/app python3 -c 'print(1)'" "psql -h prod-db.example"; do
    run env BATS_TEST_FILENAME="$BATS_TEST_FILENAME" GUARD14_BATS_ONLY=1 GUARD14_BATS_COMMAND="$command" bash "$BATS_TEST_DIRNAME/../../.claude/hooks/pre-bash-combined.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Guard14"* ]]
  done
}
