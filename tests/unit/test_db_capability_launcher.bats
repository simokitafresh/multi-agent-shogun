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

@test "bounded July drift restore uses invariant scope and stays non-generic" {
  run python3 - "$ROOT/config/db_capabilities.json" "$ROOT/scripts/lib/db_capability_tool.py" <<'PY'
import json, pathlib, sys
config = json.loads(pathlib.Path(sys.argv[1]).read_text())
contract = config["capabilities"]["bounded_signal_july_drift_restore_20260714"]
assert contract["modes"] == ["bounded_signal_july_drift_restore"]
assert contract["confirm"] == "RESTORE_ALL_23FOF_JULY_LEDGER_DRIFT"
assert contract["actions"] == ["restore"]
assert contract["allowed_child_flags"] == ["--output"]
assert contract["requires_expected_commit"] is True
source = pathlib.Path(sys.argv[2]).read_text()
required = (
    "def _restore_signal_july_drift_20260714",
    "s.date >= DATE '2026-07-01'",
    "s.date <  DATE '2026-08-01'",
    "s.holding_signal IS DISTINCT FROM l.decision_holding_signal",
    "if not drift_rows",
    "len(target_rows), len(target_rows), len(target_rows)",
    "os.O_CREAT | os.O_EXCL | os.O_WRONLY",
)
assert all(item in source for item in required)
PY
  [ "$status" -eq 0 ]
}

@test "cmd_3909 baseline capability is exact-cardinality and non-generic" {
  run python3 - "$ROOT/config/db_capabilities.json" "$ROOT/scripts/lib/db_capability_tool.py" "$BATS_TEST_TMPDIR/inventory.json" <<'PY'
import importlib.util
import json
import pathlib
import sys
import types
from datetime import date, timedelta

registry_path, tool_path, output_path = map(pathlib.Path, sys.argv[1:])
contract = json.loads(registry_path.read_text())["capabilities"]["bounded_signal_ledger_baseline_20260715"]
assert contract["modes"] == ["bounded_signal_ledger_baseline"]
assert contract["confirm"] == "FREEZE_EXACT_478_SIGNAL_LEDGER_BASELINES"
assert contract["actions"] == ["freeze"]
assert contract["allowed_child_flags"] == ["--output"]
assert contract["requires_expected_commit"] is True

spec = importlib.util.spec_from_file_location("db_capability_tool", tool_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
rows = [
    (
        f"pf-{i % 76:02d}",
        date(2020, 1, 1) + timedelta(days=i // 76),
        "raw",
        "hold",
        {"SPY": 1.0},
    )
    for i in range(478)
]

class Cursor:
    def __init__(self):
        self.value = None
        self.statements = []
        self.ledger_reads = 0
        self.coverage_reads = 0
        self.rowcount = -1
    def execute(self, statement, params=None):
        text = str(statement)
        self.statements.append((text, params))
        if text.startswith("SELECT current_user"):
            self.value = ("writer", "writer", "dm_signal", "127.0.0.1")
        elif "pg_try_advisory_lock" in text:
            self.value = (True,)
        elif "recalculation_status" in text:
            self.value = (False,)
        elif text.startswith("SELECT COUNT(*) FROM signal_decision_ledger"):
            self.ledger_reads += 1
            self.value = (15160 if self.ledger_reads == 1 else 15638,)
        elif "WITH scope AS" in text:
            self.coverage_reads += 1
            self.value = (341409, 340931 if self.coverage_reads == 1 else 341409)
        elif "FROM signals s" in text and "NOT EXISTS" in text:
            self.value = rows
        else:
            self.value = None
    def fetchone(self): return self.value
    def fetchall(self): return list(self.value)
    def close(self): pass

class Connection:
    def __init__(self):
        self.autocommit = None
        self.cursor_obj = Cursor()
        self.commits = 0
        self.rollbacks = 0
    def cursor(self): return self.cursor_obj
    def commit(self): self.commits += 1
    def rollback(self): self.rollbacks += 1
    def close(self): pass

connection = Connection()
psycopg2 = types.ModuleType("psycopg2")
extras = types.ModuleType("psycopg2.extras")
class Json:
    def __init__(self, value): self.value = value
def execute_values(cursor, statement, values, template=None, page_size=None):
    assert len(values) == page_size == 478
    cursor.statements.append((statement, values))
    cursor.rowcount = len(values)
extras.Json = Json
extras.execute_values = execute_values
psycopg2.connect = lambda _dsn: connection
psycopg2.extras = extras
sys.modules["psycopg2"] = psycopg2
sys.modules["psycopg2.extras"] = extras

result = module._freeze_signal_ledger_baseline_20260715("unused", output_path)
inventory = json.loads(output_path.read_text())
assert inventory["row_count"] == 478 and inventory["portfolio_count"] == 76
assert result["inserted_rows"] == 478
assert result["ledger_rows_after"] - result["ledger_rows_before"] == 478
assert result["scope_rows"] == result["covered_rows"] == 341409
assert result["other_table_writes"] == result["recalculate_runs"] == 0
writes = [sql for sql, _ in connection.cursor_obj.statements if sql.lstrip().upper().startswith(("INSERT", "UPDATE", "DELETE"))]
assert len(writes) == 1 and "INSERT INTO signal_decision_ledger" in writes[0]
assert connection.commits == 1 and connection.rollbacks == 0
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

@test "production role probe launcher supplies trusted account HOME to dependency" {
  fixture="$BATS_TEST_TMPDIR/probe-launcher-repo"
  mkdir -p "$fixture/scripts/lib" "$fixture/scripts/oneshot" "$fixture/config" \
    "$fixture/outputs/analysis"
  cp "$LAUNCHER" "$fixture/scripts/db_capability_launcher.py"
  cp "$ROOT/scripts/lib/db_capability_tool.py" "$fixture/scripts/lib/db_capability_tool.py"
  cp "$ROOT/config/db_capabilities.json" "$fixture/config/db_capabilities.json"
  printf 'projects:\n  - id: dm-signal\n    path: %s\n' "$fixture" > "$fixture/config/projects.yaml"
  printf '%s\n' \
    'import os, pathlib, sys' \
    'pathlib.Path(sys.argv[sys.argv.index("--output") + 1]).write_text(os.environ["HOME"])' \
    > "$fixture/scripts/oneshot/cmd_3881_db_fence_verify.py"
  git -C "$fixture" init -q
  git -C "$fixture" config user.email fixture@example.invalid
  git -C "$fixture" config user.name fixture
  git -C "$fixture" add .
  git -C "$fixture" commit -qm fixture
  head="$(git -C "$fixture" rev-parse HEAD)"
  credentials="$BATS_TEST_TMPDIR/probe-launcher.env"
  printf 'DATABASE_URL=postgresql://user:secret@dpg-test-a.singapore-postgres.render.com/dm_signal\n' > "$credentials"
  chmod 600 "$credentials"
  artifact="$fixture/outputs/analysis/home.txt"

  run env HOME=/tmp/untrusted-home python3 "$fixture/scripts/db_capability_launcher.py" \
    --capability production_role_probe --mode production_role_probe \
    --confirm PRODUCTION_ROLE_PROBE_APPROVED --nonce "home-$RANDOM" \
    --credential-file "$credentials" --expected-commit "$head" \
    --execution-root "$fixture" -- run \
    --probe-role cmd3881_cap_probe_deadbeef --output "$artifact"
  [ "$status" -eq 0 ]
  expected_home="$(python3 -c 'import os,pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
  [ "$(cat "$artifact")" = "$expected_home" ]
}

@test "production role probe registry admits only the scoped nologin rehearsal arguments" {
  run python3 - "$LAUNCHER" "$ROOT/config/db_capabilities.json" <<'PY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("launcher", sys.argv[1])
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
contract = json.load(open(sys.argv[2]))["capabilities"]["production_role_probe"]
args = module._validate_child_args(contract, ["--", "nologin-rehearsal", "--app-role", "cmd3881_nologin_app_x", "--keeper-role", "cmd3881_nologin_keeper_x", "--output", "/tmp/a"])
assert args[0] == "nologin-rehearsal"
for bad in (["nologin-rehearsal", "--dsn", "secret"], ["unknown", "--output", "/tmp/a"]):
    try: module._validate_child_args(contract, bad)
    except SystemExit as exc: assert "BLOCK" in str(exc)
    else: raise AssertionError("unsafe rehearsal args allowed")
PY
  [ "$status" -eq 0 ]
}

@test "locked restore excludes writers and proves empty tables before COPY" {
  run python3 - "$ROOT/scripts/lib/db_capability_tool.py" "$BATS_TEST_TMPDIR" <<'PY'
import hashlib, importlib.util, pathlib, tempfile, types, sys

spec = importlib.util.spec_from_file_location("tool", sys.argv[1])
tool = importlib.util.module_from_spec(spec); spec.loader.exec_module(tool)
root = pathlib.Path(sys.argv[2])
artifact = root / "artifact"; artifact.mkdir()
output_tables = tuple(f"output_{index:02d}" for index in range(17))
guard_table = "signal_decision_ledger"
tables = (*output_tables, guard_table)
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
        elif "FROM pg_catalog.pg_locks" in text: self.result=(True,)
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
evidence=tool._restore_with_writer_lock(module, "unused", artifact, "deadbeef")
events=conn.cur.events
lock_index=next(i for i,e in enumerate(events) if e.startswith("LOCK TABLE"))
first_delete=next(i for i,e in enumerate(events) if e.startswith("DELETE FROM"))
first_copy=next(i for i,e in enumerate(events) if e.startswith("COPY "))
zero_checks=[i for i,e in enumerate(events) if e.startswith("SELECT count(*)") and i < first_copy]
assert lock_index < first_delete < first_copy
assert len(zero_checks) == len(output_tables)
assert not any('DELETE FROM "signal_decision_ledger"' in event for event in events)
assert not any('COPY "signal_decision_ledger"' in event for event in events)
assert "SHARE ROW EXCLUSIVE" in events[lock_index]
assert conn.committed and not conn.rolled_back and conn.closed
assert evidence == {
    "output_tables_restored": 17,
    "guard_tables_mutated": 0,
    "guard_sha256": manifest["tables"][guard_table]["sha256"],
    "transaction": "committed",
}

conn2=Connection()
guard_reads=0
def mutating_copy_out(cur, table, columns, order, destination):
    global guard_reads
    payload=(artifact / f"{table}.copy").read_bytes()
    if table == guard_table:
        guard_reads += 1
        if guard_reads == 2: payload=b"mutated-ledger"
    destination.write_bytes(payload); return 1
module.psycopg2=types.SimpleNamespace(connect=lambda _dsn: conn2)
module.copy_out=mutating_copy_out
try:
    tool._restore_with_writer_lock(module, "unused", artifact, "deadbeef")
except RuntimeError as exc:
    assert "immutable ledger guard changed" in str(exc)
else:
    raise AssertionError("G1 mutation did not fail closed")
assert conn2.rolled_back and not conn2.committed and conn2.closed
PY
  [ "$status" -eq 0 ]
}

@test "separate restore connection self-blocks while keeper owns advisory lock" {
  run python3 - "$ROOT/scripts/lib/db_capability_tool.py" "$BATS_TEST_TMPDIR" <<'PY'
import importlib.util, pathlib, types, sys
spec = importlib.util.spec_from_file_location("tool", sys.argv[1])
tool = importlib.util.module_from_spec(spec); spec.loader.exec_module(tool)

class Cursor:
    def execute(self, query, params=None): self.query = str(query)
    def fetchone(self): return (False,)
class Connection:
    def __init__(self): self.cur=Cursor(); self.rolled_back=False; self.closed=False
    def cursor(self): return self.cur
    def rollback(self): self.rolled_back=True
    def close(self): self.closed=True
conn=Connection()
module=types.SimpleNamespace(psycopg2=types.SimpleNamespace(connect=lambda _dsn: conn), LOCK_KEY=8675309)
try:
    tool._restore_with_writer_lock(module, "unused", pathlib.Path(sys.argv[2]), "deadbeef")
except RuntimeError as exc:
    assert "advisory lock is held" in str(exc)
else:
    raise AssertionError("separate connection bypassed keeper advisory lock")
assert conn.rolled_back and conn.closed
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

@test "bounded 20260714 signal restore writes exactly one fixed column after 161-row preflight" {
  run python3 - "$ROOT/scripts/lib/db_capability_tool.py" "$BATS_TEST_TMPDIR/backup.json" <<'PY'
import importlib.util
import json
import pathlib
import sys
import types

spec = importlib.util.spec_from_file_location("db_capability_tool", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

target = []
for pf_index in range(23):
    for day in range(1, 8):
        target.append((f"pf-{pf_index:02d}", f"2026-07-{day:02d}", "old", "new", "new"))
ledger = [(row[0], row[1], row[2], row[2]) for row in target]
updated = [(row[0], row[1]) for row in target]

class Cursor:
    def __init__(self):
        self.value = None
        self.statements = []
    def execute(self, statement, params=None):
        text = str(statement)
        self.statements.append((text, params))
        if text.startswith("SELECT current_user"):
            self.value = ("writer", "writer", "dm_signal", "127.0.0.1")
        elif "pg_try_advisory_lock" in text:
            self.value = (True,)
        elif "recalculation_status" in text:
            self.value = (False,)
        elif "c.new_holding_signal, s.holding_signal" in text:
            self.value = target
        elif "SELECT t.portfolio_id, t.date, t.old_holding_signal" in text:
            self.value = ledger
        elif "UPDATE signals s" in text:
            self.value = updated
        elif "COUNT(*) AS target_rows" in text:
            self.value = (161, 161, 161)
        else:
            self.value = None
    def fetchone(self):
        return self.value
    def fetchall(self):
        return list(self.value)
    def close(self):
        pass

class Connection:
    def __init__(self):
        self.autocommit = None
        self.cursor_obj = Cursor()
        self.commits = 0
        self.rollbacks = 0
    def cursor(self):
        return self.cursor_obj
    def commit(self):
        self.commits += 1
    def rollback(self):
        self.rollbacks += 1
    def close(self):
        pass

connection = Connection()
sys.modules["psycopg2"] = types.SimpleNamespace(connect=lambda dsn: connection)
result = module._restore_signal_window_20260714("postgresql://unused", pathlib.Path(sys.argv[2]))
updates = [sql for sql, _ in connection.cursor_obj.statements if "UPDATE signals s" in sql]
assert len(updates) == 1
assert "SET holding_signal = target.old_holding_signal" in updates[0]
assert "updated_at" not in updates[0]
assert connection.commits == 1 and connection.rollbacks == 0
assert result["updated_rows"] == result["restored_exact"] == result["ledger_exact"] == 161
backup = json.loads(pathlib.Path(sys.argv[2]).read_text())
assert backup["row_count"] == 161 and backup["portfolio_count"] == 23
PY
  [ "$status" -eq 0 ]
}

@test "project capability without dependency receives its registered project root" {
  fixture="$BATS_TEST_TMPDIR/project-root-repo"
  project="$fixture/project"
  mkdir -p "$fixture/scripts/lib" "$fixture/config" "$project/backend"
  cp "$LAUNCHER" "$fixture/scripts/db_capability_launcher.py"
  cat > "$fixture/scripts/lib/project_root_probe.py" <<'PY'
import os
print(os.environ["DB_CAPABILITY_PROJECT_ROOT"])
PY
  cat > "$fixture/config/db_capabilities.json" <<'JSON'
{"version":1,"capabilities":{"probe":{"tool":"scripts/lib/project_root_probe.py","project":"dm-signal","modes":["probe"],"confirm":"PROBE","required_credential_keys":["DATABASE_URL"],"requires_expected_commit":false}}}
JSON
  printf 'projects:\n  - id: dm-signal\n    path: %s\n' "$project" > "$fixture/config/projects.yaml"
  git -C "$fixture" init -q
  git -C "$fixture" config user.email fixture@example.invalid
  git -C "$fixture" config user.name fixture
  git -C "$fixture" add scripts config
  git -C "$fixture" commit -qm fixture
  run python3 "$fixture/scripts/db_capability_launcher.py" \
    --capability probe --mode probe --confirm PROBE --nonce "$BATS_TEST_NAME" \
    --credential-file "$CREDS"
  [ "$status" -eq 0 ]
  [ "$output" = "$project" ]
}
