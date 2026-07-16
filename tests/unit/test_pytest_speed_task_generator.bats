#!/usr/bin/env bats
setup(){ TMP=$(mktemp -d); LEDGER="$TMP/ledger.tsv"; GEN="$BATS_TEST_DIRNAME/../../scripts/pytest_speed_task_generator.sh"; export PYTEST_SPEED_STATE_ROOT="$TMP/state"; mkdir -p "$PYTEST_SPEED_STATE_ROOT/queue/tasks" "$PYTEST_SPEED_STATE_ROOT/queue/reports"; }
teardown(){ rm -rf "$TMP"; }
header(){ printf 'timestamp\tnodeid\tduration_sec\toutcome\tfailures\tskips\tcommit\n' >"$LEDGER"; }
row(){ printf '%s\t%s\t%s\t%s\t%s\t%s\tx\n' "$@" >>"$LEDGER"; }
@test "filters fail skip stale malformed and stable sorts" { header; row 1 a::pass 3 passed 0 0; row 1 b::fail 9 failed 1 0; row 1 c::skip 8 passed 0 1; row 1 stale::x 7 passed 0 0; row 2 stale::x 7 failed 1 0; row 1 z::stable 5 passed 0 0; row 1 y::stable 5 passed 0 0; printf '1\tbad::duration\tnope\tpassed\t0\t0\tx\n' >>"$LEDGER"; run "$GEN" --ledger "$LEDGER" next; [ "$status" -eq 0 ]; [ "$output" = $'5\ty::stable\n5\tz::stable\n3\ta::pass' ]; }
@test "latest duplicate appears once" { header; row 1 a::x 2 passed 0 0; row 2 a::x 4 passed 0 0; run "$GEN" --ledger "$LEDGER" next; [ "$status" -eq 0 ]; [ "$output" = $'4\ta::x' ]; }
@test "active and completed nodeids are excluded" { header; row 1 active::x 4 passed 0 0; row 1 done::x 3 passed 0 0; row 1 free::x 2 passed 0 0; printf 'task:\n  status: in_progress\n  target_nodeid: active::x\n' >"$PYTEST_SPEED_STATE_ROOT/queue/tasks/a.yaml"; printf 'status: completed\ntarget_nodeid: done::x\n' >"$PYTEST_SPEED_STATE_ROOT/queue/reports/d.yaml"; run "$GEN" --ledger "$LEDGER" next; [ "$status" -eq 0 ]; [ "$output" = $'2\tfree::x' ]; }
@test "malformed header fails closed" { printf 'bad\theader\n' >"$LEDGER"; run "$GEN" --ledger "$LEDGER" next; [ "$status" -ne 0 ]; [[ "$output" == *malformed* ]]; }
@test "generate emits strict five minute contract" { header; row 1 backend/tests/test_slow.py::test_x 12.5 passed 0 0; run "$GEN" --ledger "$LEDGER" generate backend/tests/test_slow.py::test_x "$TMP/task.yaml"; [ "$status" -eq 0 ]; run python3 - "$TMP/task.yaml" <<'PY'
import sys,yaml
t=yaml.safe_load(open(sys.argv[1]))['task']; assert t['project']=='dm-signal' and t['estimated_minutes']==5; assert isinstance(t['target_path'],str); assert t['before_duration_sec']==12.5; assert t['quality_gate']=={'failures':0,'skips':0,'expectation_relaxation':'forbidden'}
PY
 [ "$status" -eq 0 ]; }
@test "deploy cleans temporary YAML after handoff" { header; row 1 backend/tests/test_slow.py::test_x 12.5 passed 0 0; mock="$TMP/deploy"; printf '#!/bin/sh\n[ -f "$3" ] || exit 9\nprintf "%%s" "$3" >"%s/seen"\n' "$TMP" >"$mock"; chmod +x "$mock"; run env DEPLOY_TASK="$mock" "$GEN" --ledger "$LEDGER" deploy sasuke backend/tests/test_slow.py::test_x; [ "$status" -eq 0 ]; path=$(cat "$TMP/seen"); [ ! -e "$path" ]; }
@test "default ledger resolves from projects config outside cwd" { run bash -c 'cd /tmp && "$1" next' _ "$GEN"; [ "$status" -eq 0 ] || [[ "$output" == *'cannot read ledger'* ]]; [[ "$output" != *'/mnt/c/Python_app/DM-signal'* ]]; }
