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
  fixture="$BATS_TEST_TMPDIR/restore-repo"
  mkdir -p "$fixture/scripts/lib" "$fixture/scripts/oneshot" "$fixture/config"
  cp "$LAUNCHER" "$fixture/scripts/db_capability_launcher.py"
  cp "$ROOT/scripts/lib/db_capability_tool.py" "$fixture/scripts/lib/db_capability_tool.py"
  cp "$ROOT/config/db_capabilities.json" "$fixture/config/db_capabilities.json"
  printf '#!/usr/bin/env python3\n' > "$fixture/scripts/oneshot/cmd_p4_prod_restore_contract.py"
  printf 'projects:\n  - id: dm-signal\n    path: %s\n' "$fixture" > "$fixture/config/projects.yaml"
  git -C "$fixture" init -q
  git -C "$fixture" config user.email fixture@example.invalid
  git -C "$fixture" config user.name fixture
  git -C "$fixture" add scripts/db_capability_launcher.py scripts/lib/db_capability_tool.py \
    scripts/oneshot/cmd_p4_prod_restore_contract.py config/db_capabilities.json config/projects.yaml
  git -C "$fixture" commit -qm fixture

  run python3 "$fixture/scripts/db_capability_launcher.py" --capability transactional_restore --mode transactional_restore --confirm TRANSACTIONAL_RESTORE_ROLLBACK_READY --nonce "$BATS_TEST_NAME" --credential-file "$CREDS" --expected-commit deadbeef -- dry-run --artifact /tmp/a
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
  fixture="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$fixture/scripts/lib" "$fixture/config"
  cp "$LAUNCHER" "$fixture/scripts/db_capability_launcher.py"
  cp "$ROOT/scripts/lib/db_capability_tool.py" "$fixture/scripts/lib/db_capability_tool.py"
  cp "$ROOT/config/db_capabilities.json" "$fixture/config/db_capabilities.json"
  git -C "$fixture" init -q
  git -C "$fixture" config user.email fixture@example.invalid
  git -C "$fixture" config user.name fixture
  git -C "$fixture" add scripts/db_capability_launcher.py scripts/lib/db_capability_tool.py config/db_capabilities.json
  git -C "$fixture" commit -qm fixture
  registry="$fixture/config/db_capabilities.json"
  printf '\n ' >> "$registry"
  run python3 "$fixture/scripts/db_capability_launcher.py" --capability readonly_query --mode readonly --confirm READONLY_DB_CHECK --nonce "$BATS_TEST_NAME" --credential-file "$CREDS"
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

@test "credential preparation extracts only registered keys into owner-only tmp file" {
  project="$BATS_TEST_TMPDIR/project"
  mkdir -p "$project/backend"
  source="$project/backend/.env"
  destination="/tmp/dm-signal-db-test-${BATS_TEST_NUMBER}-${RANDOM}.env"
  printf 'DATABASE_URL=postgresql://secret\nUNRELATED=must-not-copy\n' > "$source"
  run python3 - "$LAUNCHER" "$source" "$destination" "$project" <<'PY'
import importlib.util, pathlib, stat, sys
spec = importlib.util.spec_from_file_location("launcher", sys.argv[1])
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
destination = pathlib.Path(sys.argv[3])
module._prepare_credential_file(
    pathlib.Path(sys.argv[2]), destination, pathlib.Path(sys.argv[4]), {"DATABASE_URL"}
)
assert destination.read_text() == "DATABASE_URL=postgresql://secret\n"
assert stat.S_IMODE(destination.stat().st_mode) == 0o600
PY
  [ "$status" -eq 0 ]
  rm -f "$destination"
}

@test "credential preparation rejects arbitrary source and overwrite" {
  project="$BATS_TEST_TMPDIR/project"
  mkdir -p "$project/backend"
  printf 'DATABASE_URL=postgresql://canonical\n' > "$project/backend/.env"
  arbitrary="$BATS_TEST_TMPDIR/arbitrary.env"
  destination="/tmp/dm-signal-db-test-${BATS_TEST_NUMBER}-${RANDOM}.env"
  printf 'DATABASE_URL=postgresql://attack\n' > "$arbitrary"
  run python3 - "$LAUNCHER" "$arbitrary" "$destination" "$project" <<'PY'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("launcher", sys.argv[1])
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
module._prepare_credential_file(
    pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]), pathlib.Path(sys.argv[4]), {"DATABASE_URL"}
)
PY
  [ "$status" -ne 0 ]
  [[ "$output" == *"project backend/.env"* ]]
  printf 'sentinel\n' > "$destination"
  run python3 - "$LAUNCHER" "$project/backend/.env" "$destination" "$project" <<'PY'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("launcher", sys.argv[1])
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
module._prepare_credential_file(
    pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]), pathlib.Path(sys.argv[4]), {"DATABASE_URL"}
)
PY
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to overwrite"* ]]
  [ "$(cat "$destination")" = sentinel ]
  rm -f "$destination"
}

@test "prepare-only provisions owner-only credential without executing DB capability or consuming nonce" {
  fixture="$BATS_TEST_TMPDIR/prepare-repo"
  mkdir -p "$fixture/scripts/lib" "$fixture/config" "$fixture/backend"
  cp "$LAUNCHER" "$fixture/scripts/db_capability_launcher.py"
  cp "$ROOT/scripts/lib/db_capability_tool.py" "$fixture/scripts/lib/db_capability_tool.py"
  cp "$ROOT/config/db_capabilities.json" "$fixture/config/db_capabilities.json"
  printf 'projects:\n  - id: dm-signal\n    path: %s\n' "$fixture" > "$fixture/config/projects.yaml"
  printf 'DATABASE_URL=postgresql://secret\nUNRELATED=must-not-copy\n' > "$fixture/backend/.env"
  git -C "$fixture" init -q
  git -C "$fixture" config user.email fixture@example.invalid
  git -C "$fixture" config user.name fixture
  git -C "$fixture" add scripts/db_capability_launcher.py scripts/lib/db_capability_tool.py \
    config/db_capabilities.json config/projects.yaml
  git -C "$fixture" commit -qm fixture
  destination="/tmp/dm-signal-db-prepare-${BATS_TEST_NUMBER}-${RANDOM}.env"

  run python3 "$fixture/scripts/db_capability_launcher.py" \
    --capability readonly_query --mode readonly --confirm READONLY_DB_CHECK \
    --credential-file "$destination" --credential-source-file "$fixture/backend/.env" \
    --prepare-only

  [ "$status" -eq 0 ]
  [[ "$output" == *"prepared credential file"* ]]
  [ "$(stat -c %a "$destination")" = 600 ]
  [ "$(cat "$destination")" = 'DATABASE_URL=postgresql://secret' ]
  [ ! -d "$fixture/.runtime/db-capability-nonces" ]
  rm -f "$destination"
}

@test "prepare-only fails closed without canonical source and normal execution still requires nonce" {
  run python3 "$LAUNCHER" --capability readonly_query --mode readonly \
    --confirm READONLY_DB_CHECK --credential-file "$CREDS" --prepare-only
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires --credential-source-file"* ]]

  run python3 "$LAUNCHER" --capability readonly_query --mode readonly \
    --confirm READONLY_DB_CHECK --credential-file "$CREDS"
  [ "$status" -ne 0 ]
  [[ "$output" == *"nonce is required"* ]]
}

@test "transactional capability accepts backup dry-run restore and rejects unknown flags" {
  run python3 - "$LAUNCHER" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("launcher", sys.argv[1])
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
contract = {"actions": ["backup", "dry-run", "restore", "restore-locked"], "allowed_child_flags": ["--artifact", "--service"]}
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

@test "transactional tool passes artifact as Path for every registered action" {
  dependency="$BATS_TEST_TMPDIR/dependency.py"
  cat > "$dependency" <<'PY'
from pathlib import Path
def backup(dsn, artifact, service, expected_commit):
    assert isinstance(artifact, Path)
def restore(dsn, artifact, expected_commit, production, confirm_a, confirm_b,
            allow_local_clone_identity, *, dry_run=False):
    assert isinstance(artifact, Path)
PY
  for action in backup dry-run restore; do
    run env DB_CAPABILITY=transactional_restore DB_CAPABILITY_MODE=transactional_restore \
      DB_CAPABILITY_DEPENDENCY_TOOL="$dependency" DB_CAPABILITY_EXPECTED_COMMIT=deadbeef \
      DATABASE_URL=unused python3 "$ROOT/scripts/lib/db_capability_tool.py" \
      "$action" --artifact "$BATS_TEST_TMPDIR/artifact"
    [ "$status" -eq 0 ]
  done
}

@test "production role probe binds identities to credential DSN and keeps secret out of argv" {
  project="$BATS_TEST_TMPDIR/probe-project"
  mkdir -p "$project/outputs/analysis"
  dependency="$BATS_TEST_TMPDIR/probe-dependency.py"
  artifact="$project/outputs/analysis/probe.json"
  printf '%s\n' \
    'import json, os, pathlib, sys' \
    'assert os.environ["CMD3881_PRODUCTION_PROBE_DSN"] == os.environ["DATABASE_URL"]' \
    'assert os.environ["DATABASE_URL"] not in " ".join(sys.argv)' \
    'pathlib.Path(sys.argv[sys.argv.index("--output") + 1]).write_text(json.dumps({"argv": sys.argv[1:]}))' \
    > "$dependency"

  run env DB_CAPABILITY=production_role_probe DB_CAPABILITY_MODE=production_role_probe \
    DB_CAPABILITY_DEPENDENCY_TOOL="$dependency" DB_CAPABILITY_PROJECT_ROOT="$project" \
    DATABASE_URL='postgresql://user:secret@dpg-test-a.singapore-postgres.render.com/dm_signal' \
    python3 "$ROOT/scripts/lib/db_capability_tool.py" run \
    --probe-role cmd3881_cap_probe_deadbeef --output "$artifact"
  [ "$status" -eq 0 ]
  [ -f "$artifact" ]
  ! grep -q secret "$artifact"

  run env DB_CAPABILITY=production_role_probe DB_CAPABILITY_MODE=production_role_probe \
    DB_CAPABILITY_DEPENDENCY_TOOL="$dependency" DB_CAPABILITY_PROJECT_ROOT="$project" \
    DATABASE_URL='postgresql://user:secret@wrong.example.invalid/dm_signal' \
    python3 "$ROOT/scripts/lib/db_capability_tool.py" run \
    --probe-role cmd3881_cap_probe_deadbeef --output "$artifact"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not the registered Render production resource"* ]]

  run env DB_CAPABILITY=production_role_probe DB_CAPABILITY_MODE=production_role_probe \
    DB_CAPABILITY_DEPENDENCY_TOOL="$dependency" DB_CAPABILITY_PROJECT_ROOT="$project" \
    DATABASE_URL='postgresql://user:secret@dpg-test-a.singapore-postgres.render.com/wrong_db' \
    python3 "$ROOT/scripts/lib/db_capability_tool.py" run \
    --probe-role cmd3881_cap_probe_deadbeef --output "$artifact"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not the registered production database"* ]]
}

@test "locked restore excludes writers and proves empty tables before COPY" {
  run python3 - "$ROOT/scripts/lib/db_capability_tool.py" "$BATS_TEST_TMPDIR" <<'PY'
import hashlib, importlib.util, pathlib, tempfile, types, sys

spec = importlib.util.spec_from_file_location("tool", sys.argv[1])
tool = importlib.util.module_from_spec(spec); spec.loader.exec_module(tool)
root = pathlib.Path(sys.argv[2])
artifact = root / "artifact"; artifact.mkdir()
tables = ("alpha", "beta")
for table in tables:
    (artifact / f"{table}.copy").write_bytes((table + "-payload").encode())
manifest = {"tables": {
    table: {"columns": ["id"], "order": ["id"], "rows": 1,
            "sha256": hashlib.sha256((artifact / f"{table}.copy").read_bytes()).hexdigest()}
    for table in tables
}}

class Fragment:
    def __init__(self, value): self.value = str(value)
    def format(self, *values):
        text = self.value
        for value in values: text = text.replace("{}", str(value), 1)
        return Fragment(text)
    def join(self, values): return Fragment(self.value.join(map(str, values)))
    def as_string(self, _cur): return self.value
    def __str__(self): return self.value
class SQL:
    SQL = staticmethod(Fragment)
    Identifier = staticmethod(lambda value: Fragment(f'"{value}"'))

class Cursor:
    def __init__(self):
        self.events=[]; self.counts={table: 9 for table in tables}; self.result=None
    def execute(self, query, params=None):
        text=str(query); self.events.append(text)
        if text.startswith("SELECT pg_try_advisory_lock"): self.result=(True,)
        elif text.startswith("SELECT EXISTS"): self.result=(False,)
        elif text.startswith("DELETE FROM"):
            table=text.split('"')[1]; self.counts[table]=0
        elif text.startswith("SELECT count(*)"):
            table=text.split('"')[1]; self.result=(self.counts[table],)
    def fetchone(self): return self.result
    def copy_expert(self, query, stream):
        text=str(query); self.events.append(text)
        table=text.split('"')[1]; stream.read(); self.counts[table]=1
class Connection:
    def __init__(self): self.cur=Cursor(); self.committed=False; self.rolled_back=False; self.closed=False
    def cursor(self): return self.cur
    def commit(self): self.committed=True
    def rollback(self): self.rolled_back=True
    def close(self): self.closed=True
conn=Connection()

def copy_out(cur, table, columns, order, destination):
    destination.write_bytes((artifact / f"{table}.copy").read_bytes()); return 1
module = types.SimpleNamespace(
    psycopg2=types.SimpleNamespace(connect=lambda _dsn: conn), LOCK_KEY=8675309,
    validate_artifact=lambda *_args, **_kwargs: manifest,
    contract=lambda: types.SimpleNamespace(INVENTORY={table: None for table in tables}),
    sql=SQL, tempfile=tempfile, copy_out=copy_out,
    sha256=lambda path: hashlib.sha256(path.read_bytes()).hexdigest(),
)
tool._restore_with_writer_lock(module, "unused", artifact, "deadbeef")
events=conn.cur.events
lock_index=next(i for i,e in enumerate(events) if e.startswith("LOCK TABLE"))
first_delete=next(i for i,e in enumerate(events) if e.startswith("DELETE FROM"))
first_copy=next(i for i,e in enumerate(events) if e.startswith("COPY "))
zero_checks=[i for i,e in enumerate(events) if e.startswith("SELECT count(*)") and i < first_copy]
assert lock_index < first_delete < first_copy
assert len(zero_checks) == len(tables)
assert "SHARE ROW EXCLUSIVE" in events[lock_index]
assert conn.committed and not conn.rolled_back and conn.closed
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
