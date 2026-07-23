#!/usr/bin/env bats
# test_necessity: Guard14 must admit only the canonical DB capability launcher independent of hook cwd, treat dot-env prose as inert argv, and continue blocking unknown direct DB connections.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CLASSIFIER="$ROOT/scripts/lib/guard14_db_trust_classify.py"
  HOOK="$ROOT/.claude/hooks/pre-bash-combined.sh"
}

classify() {
  local command="$1"
  run env COMMAND="$command" python3 -S "$CLASSIFIER"
  [ "$status" -eq 0 ]
}

run_hook() {
  local command="$1"
  run env BATS_TEST_FILENAME="$BATS_TEST_FILENAME" GUARD14_BATS_ONLY=1 \
    GUARD14_BATS_PROJECT_ROOT="$ROOT" GUARD14_BATS_COMMAND="$command" bash "$HOOK"
}

@test "canonical launcher relative and absolute operands are exempt outside repo cwd" {
  local args="--capability readonly_query --mode readonly --confirm READONLY_DB_CHECK --nonce n1 --credential-file /tmp/dm-signal-db-check.env"
  cd /tmp
  classify "python3 scripts/db_capability_launcher.py $args"
  [ "$output" = "not_connection" ]
  classify "python3 $ROOT/scripts/db_capability_launcher.py $args"
  [ "$output" = "not_connection" ]
}

@test "canonical prepare-only and two-step db-check remain exempt" {
  local prepare="python3 scripts/db_capability_launcher.py --capability readonly_query --mode readonly --confirm READONLY_DB_CHECK --prepare-only --credential-source-file backend/.env --credential-file /tmp/dm-signal-db-check.env"
  local query="printf 'SELECT 1' | python3 scripts/db_capability_launcher.py --capability readonly_query --mode readonly --confirm READONLY_DB_CHECK --nonce n2 --credential-file /tmp/dm-signal-db-check.env"
  cd /tmp
  classify "$prepare"
  [ "$output" = "not_connection" ]
  classify "$prepare && $query"
  [ "$output" = "not_connection" ]
  run_hook "$prepare && $query"
  [ "$status" -eq 0 ]
}

@test "dot-env prose in inbox and git commands is not a credential source" {
  classify "bash scripts/inbox_write.sh karo 'mention backend/.env.production as prose' info hayate notify"
  [ "$output" = "not_connection" ]
  classify "git commit -m 'document backend/.env.production token'"
  [ "$output" = "not_connection" ]
  run_hook "bash scripts/inbox_write.sh karo 'mention backend/.env.production as prose' info hayate notify"
  [ "$status" -eq 0 ]
}

@test "unknown direct DB connection remains fail-closed" {
  classify "python3 -c 'import psycopg2; psycopg2.connect(host=\"prod-db.example\")'"
  [ "$output" = "connection:untrusted" ]
  run_hook "python3 -c 'import psycopg2; psycopg2.connect(host=\"prod-db.example\")'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Guard14"* ]]
}
