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

@test "registry working-tree alteration fails closed against HEAD" {
  registry="$ROOT/config/db_capabilities.json"
  cp "$registry" "$BATS_TEST_TMPDIR/registry.save"
  printf '\n ' >> "$registry"
  run python3 "$LAUNCHER" --capability readonly_query --mode readonly --confirm READONLY_DB_CHECK --nonce "$BATS_TEST_NAME" --credential-file "$CREDS"
  mv "$BATS_TEST_TMPDIR/registry.save" "$registry"
  [ "$status" -ne 0 ]
  [[ "$output" == *"registry is untracked or altered"* ]]
}

@test "credential file rejects PYTHONPATH and every undeclared key" {
  printf 'DATABASE_URL=postgresql://invalid\nPYTHONPATH=/tmp/attack\n' > "$CREDS"
  run python3 - "$LAUNCHER" "$CREDS" <<'PY'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("launcher", sys.argv[1])
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
try:
    module._load_env(pathlib.Path(sys.argv[2]), {"DATABASE_URL"})
except ValueError as exc:
    print(exc); raise SystemExit(0)
raise SystemExit(1)
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"exactly match"* ]]
}

@test "transactional capability accepts backup dry-run restore and rejects unknown flags" {
  run python3 - "$LAUNCHER" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("launcher", sys.argv[1])
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
contract = {"actions": ["backup", "dry-run", "restore"], "allowed_child_flags": ["--artifact", "--service"]}
for action in contract["actions"]:
    assert module._validate_child_args(contract, ["--", action, "--artifact", "/tmp/a"])[0] == action
try:
    module._validate_child_args(contract, ["restore", "--dsn", "secret"])
except SystemExit as exc:
    assert "BLOCK" in str(exc)
else:
    raise AssertionError("unknown flag allowed")
PY
  [ "$status" -eq 0 ]
}

@test "readonly tool forces database transaction readonly before executing attack corpus" {
  cat > "$BATS_TEST_TMPDIR/psycopg2.py" <<'PY'
import os
class Cursor:
    description = None
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def execute(self, sql):
        with open(os.environ['CALL_LOG'], 'a') as f: f.write('EXECUTE ' + sql + '\n')
class Conn:
    def set_session(self, **kwargs):
        with open(os.environ['CALL_LOG'], 'a') as f: f.write('SET_SESSION ' + repr(kwargs) + '\n')
    def cursor(self): return Cursor()
    def rollback(self): pass
    def close(self): pass
def connect(dsn): return Conn()
PY
  for sql in 'WITH x AS (DELETE FROM t RETURNING *) SELECT * FROM x' 'EXPLAIN ANALYZE DELETE FROM t'; do
    log="$BATS_TEST_TMPDIR/calls-$RANDOM"
    run env PYTHONPATH="$BATS_TEST_TMPDIR" CALL_LOG="$log" DB_CAPABILITY=readonly_query DB_CAPABILITY_MODE=readonly DATABASE_URL=x \
      python3 "$ROOT/scripts/lib/db_capability_tool.py" <<< "$sql"
    [ "$status" -eq 0 ]
    [ "$(sed -n '1p' "$log")" = "SET_SESSION {'readonly': True, 'autocommit': False}" ]
    [[ "$(sed -n '2p' "$log")" == EXECUTE* ]]
  done
}
