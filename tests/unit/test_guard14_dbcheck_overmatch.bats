#!/usr/bin/env bats
# test_necessity: Guard14 must admit only structurally proven local read-only DB capabilities, including canonical launchers and file-backed SQLite URIs confined to configured project roots, while blocking writable, dynamic, escaped-path, and unknown direct connections.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CLASSIFIER="$ROOT/scripts/lib/guard14_db_trust_classify.py"
  HOOK="$ROOT/.claude/hooks/pre-bash-combined.sh"
  FIXTURE_ROOT="$BATS_TEST_TMPDIR/allowed-project"
  SQLITE_DB="$FIXTURE_ROOT/analysis_runs/fixture.db"
  PROJECTS_YAML="$BATS_TEST_TMPDIR/projects.yaml"
  mkdir -p "$FIXTURE_ROOT/analysis_runs"
  : > "$SQLITE_DB"
  printf 'projects:\n  - id: fixture\n    path: "%s"\n' "$FIXTURE_ROOT" > "$PROJECTS_YAML"
}

classify() {
  local command="$1"
  run env BATS_TEST_FILENAME="$BATS_TEST_FILENAME" GUARD14_PROJECTS_YAML="$PROJECTS_YAML" \
    COMMAND="$command" python3 -S "$CLASSIFIER"
  [ "$status" -eq 0 ]
}

run_hook() {
  local command="$1"
  run env BATS_TEST_FILENAME="$BATS_TEST_FILENAME" GUARD14_PROJECTS_YAML="$PROJECTS_YAML" GUARD14_BATS_ONLY=1 \
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

@test "canonical launcher ignores known Python option values before script operand" {
  local args="scripts/db_capability_launcher.py --capability readonly_query --mode readonly --confirm READONLY_DB_CHECK --nonce n1 --credential-file /tmp/dm-signal-db-check.env"
  cd /tmp
  for prefix in "-X utf8" "-W ignore" "--check-hash-based-pycs never"; do
    classify "python3 $prefix $args"
    [ "$output" = "not_connection" ]
  done
}

@test "launcher contract rejects unknown capability flags and shell chaining" {
  local base="python3 scripts/db_capability_launcher.py"
  local commands=(
    "$base --capability unknown --mode readonly --confirm READONLY_DB_CHECK --nonce n1 --credential-file /tmp/dm-signal-db-check.env"
    "$base --capability readonly_query --mode writable --confirm READONLY_DB_CHECK --nonce n1 --credential-file /tmp/dm-signal-db-check.env"
    "$base --capability readonly_query --mode readonly --confirm READONLY_DB_CHECK --nonce n1 --credential-file /tmp/dm-signal-db-check.env --unexpected value"
    "$base --capability readonly_query --mode readonly --confirm READONLY_DB_CHECK --nonce n1 --credential-file /tmp/dm-signal-db-check.env && python3 -c 'psycopg.connect(host=\"prod-db.example\")'"
  )
  for command in "${commands[@]}"; do
    classify "$command"
    [ "$output" = "connection:untrusted" ]
  done
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

@test "literal readonly SQLite URI inside configured project root is local ephemeral" {
  local command="python3 -c 'import sqlite3; sqlite3.connect(\"file:$SQLITE_DB?mode=ro&immutable=1\", uri=True)'"
  classify "$command"
  [ "$output" = "connection:local_ephemeral" ]
  run_hook "$command"
  [ "$status" -eq 0 ]
}

@test "readonly SQLite trust proof rejects writable missing-uri dynamic and escaped paths" {
  local outside_db="$BATS_TEST_TMPDIR/outside.db"
  local escaped_db="$FIXTURE_ROOT/analysis_runs/escaped.db"
  : > "$outside_db"
  ln -s "$outside_db" "$escaped_db"

  classify "python3 -c 'import sqlite3; sqlite3.connect(\"file:$SQLITE_DB?mode=rwc\", uri=True)'"
  [ "$output" = "connection:untrusted" ]

  classify "python3 -c 'import sqlite3; sqlite3.connect(\"file:$SQLITE_DB?mode=ro\")'"
  [ "$output" = "connection:untrusted" ]

  classify "python3 -c 'import sqlite3, sys; sqlite3.connect(sys.argv[1], uri=True)' 'file:$SQLITE_DB?mode=ro'"
  [ "$output" = "connection:untrusted" ]

  classify "python3 -c 'import sqlite3; sqlite3.connect(\"file:$outside_db?mode=ro\", uri=True)'"
  [ "$output" = "connection:untrusted" ]

  classify "python3 -c 'import sqlite3; sqlite3.connect(\"file:$escaped_db?mode=ro\", uri=True)'"
  [ "$output" = "connection:untrusted" ]

  classify "python3 -c 'import sqlite3; from sqlalchemy import create_engine; sqlite3.connect(\"file:$SQLITE_DB?mode=ro\", uri=True); create_engine(\"postgresql://prod-db.example/app\")'"
  [ "$output" = "connection:untrusted" ]
}
