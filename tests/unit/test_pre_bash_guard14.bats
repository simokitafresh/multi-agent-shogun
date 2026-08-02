#!/usr/bin/env bats
# test_necessity: Guard14 passes non-DB .env reads while retaining structural DB markers.
setup() { source "$BATS_TEST_DIRNAME/../../scripts/lib/guard14_db_trust_classify.sh"; }
@test "three non-DB credential reads are not connections" {
  for command in "grep VIEWER_PASS .env" "rg '^API_TOKEN=' .env" "sed -n '/VIEWER_PASS/p' .env"; do run guard14_maybe_connection "$command"; [ "$status" -ne 0 ]; done
}
@test "DB markers remain connection candidates" {
  for command in "grep DATABASE_URL .env" "rg POSTGRES_DSN .env" "psql -h db" "python -c 'db.connect()'"; do run guard14_maybe_connection "$command"; [ "$status" -eq 0 ]; done
}
