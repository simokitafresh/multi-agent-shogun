#!/usr/bin/env bats
# test_necessity: Atomic PASS receipt with SHA256 hash and verify-receipt detects corruption/tampering fail-closed; violation is BLOCK.

setup() {
    RUNNER="$BATS_TEST_DIRNAME/../../scripts/run_with_receipt.sh"
    RECEIPT="$BATS_TEST_TMPDIR/receipt.json"
}

field() {
    python3 - "$RECEIPT" "$1" <<'PY'
import json, sys
with open(sys.argv[1]) as fh: value=json.load(fh)[sys.argv[2]]
print(str(value).lower() if isinstance(value, bool) else value)
PY
}

@test "rc0 TAP writes complete atomic PASS receipt with counts and hash" {
    run bash "$RUNNER" --receipt "$RECEIPT" --declared-test-count 2 -- bash -c "printf '1..2\nok 1 alpha\nok 2 beta\n'"
    [ "$status" -eq 0 ]
    [ "$(field complete)" = true ]
    [ "$(field result)" = PASS ]
    [ "$(field observed_test_count)" -eq 2 ]
    [ "$(field skip_count)" -eq 0 ]
    [ "$(field output_sha256)" = "$(sha256sum "${RECEIPT%.json}.output" | awk '{print $1}')" ]
}

@test "nonzero command writes durable FAIL receipt" {
    run bash "$RUNNER" --receipt "$RECEIPT" -- bash -c "echo broken; exit 7"
    [ "$status" -ne 0 ]
    [ "$(field complete)" = true ]
    [ "$(field result)" = FAIL ]
    [ "$(field rc)" -eq 7 ]
}

@test "TAP skip is counted and classified FAIL without false positive" {
    run bash "$RUNNER" --receipt "$RECEIPT" --declared-test-count 2 -- bash -c "printf '1..2\nok 1 cannot skip words\nok 2 real # SKIP reason\n'"
    [ "$(field observed_test_count)" -eq 2 ]
    [ "$(field skip_count)" -eq 1 ]
    [ "$(field result)" = FAIL ]
}

@test "partial TAP plan is incomplete even when command rc is zero" {
    run bash "$RUNNER" --receipt "$RECEIPT" -- bash -c "printf '1..3\nok 1 only\nok 2 partial\n'"
    [ "$status" -ne 0 ]
    [ "$(field declared_test_count)" -eq 3 ]
    [ "$(field observed_test_count)" -eq 2 ]
    [ "$(field complete)" = false ]
    [ "$(field result)" = FAIL ]
}

@test "bounded artifact truncates output and receipt remains parseable" {
    run bash "$RUNNER" --receipt "$RECEIPT" --max-bytes 16 -- bash -c "printf '12345678901234567890'"
    [ "$status" -eq 0 ]
    [ "$(wc -c < "${RECEIPT%.json}.output")" -eq 16 ]
    [ "$(field complete)" = true ]
}

@test "TERM during command atomically publishes incomplete receipt" {
    command_pgid_file="$BATS_TEST_TMPDIR/command.pgid"
    bash "$RUNNER" --receipt "$RECEIPT" -- bash -c \
        "echo \"\$BASHPID\" > '$command_pgid_file'; echo started; sleep 10" \
        > "$BATS_TEST_TMPDIR/term.out" 2>&1 &
    pid=$!
    for _ in {1..50}; do [[ -s "$BATS_TEST_TMPDIR/term.out" ]] && break; sleep 0.02; done
    kill -TERM "$pid"
    wait "$pid" || true
    [ -f "$RECEIPT" ]
    [ "$(field complete)" = false ]
    [ "$(field result)" = FAIL ]
    [ "$(field signal)" = TERM ]
    # The command shell and its sleep descendant run in a dedicated process
    # group.  Publishing the receipt must leave that group with zero live work.
    command_pgid="$(cat "$command_pgid_file")"
    ! ps -e -o pgid=,stat= | awk -v pgid="$command_pgid" '$1 == pgid && $2 !~ /^Z/ { found=1 } END { exit !found }'
}

# test_necessity: a command that returns before its background descendant must
# still leave zero live members in the receipt runner's dedicated session.
@test "normal command exit reaps detached descendants before publishing receipt" {
    child_pid_file="$BATS_TEST_TMPDIR/normal-child.pid"
    run bash "$RUNNER" --receipt "$RECEIPT" -- bash -c \
        "sleep 30 & echo \$! > '$child_pid_file'; exit 0"
    [ "$status" -eq 0 ]
    child_pid="$(cat "$child_pid_file")"
    ! ps -p "$child_pid" -o stat= | awk '$1 !~ /^Z/ { found=1 } END { exit found ? 0 : 1 }'
    [ "$(field result)" = PASS ]
}

@test "help embeds receipt usage and required fields" {
    run bash "$RUNNER" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--receipt PATH"* ]]
    [[ "$output" == *"output_sha256"* ]]
    [[ "$output" == *"observed_test_count"* ]]
}

@test "verify-receipt detects JSON corruption and artifact tampering fail-closed" {
    bash "$RUNNER" --receipt "$RECEIPT" -- bash -c 'echo durable'
    run bash "$RUNNER" --verify-receipt "$RECEIPT"
    [ "$status" -eq 0 ]
    printf '{broken\n' > "$RECEIPT"
    run bash "$RUNNER" --verify-receipt "$RECEIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"RECEIPT_FAIL"* ]]

    bash "$RUNNER" --receipt "$RECEIPT" -- bash -c 'echo durable'
    printf 'tamper\n' >> "${RECEIPT%.json}.output"
    run bash "$RUNNER" --verify-receipt "$RECEIPT"
    [ "$status" -ne 0 ]
}

@test "long TAP complete and truncated-terminal fixtures are decided once from receipts" {
    good="$BATS_TEST_TMPDIR/long-good.json"
    bad="$BATS_TEST_TMPDIR/long-bad.json"
    run bash "$RUNNER" --receipt "$good" --declared-test-count 200 -- bash -c \
        'echo 1..200; for i in $(seq 1 200); do echo "ok $i case"; done'
    [ "$status" -eq 0 ]
    [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["observed_test_count"])' "$good")" -eq 200 ]
    run bash "$RUNNER" --verify-receipt "$good"
    [ "$status" -eq 0 ]

    run bash "$RUNNER" --receipt "$bad" --declared-test-count 200 -- bash -c \
        'echo 1..200; for i in $(seq 1 199); do echo "ok $i case"; done'
    [ "$status" -ne 0 ]
    [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["observed_test_count"])' "$bad")" -eq 199 ]
    run bash "$RUNNER" --verify-receipt "$bad"
    [ "$status" -ne 0 ]
}

@test "live progress publishes atomic partial evidence and streams file boundaries" {
  receipt="$BATS_TEST_TMPDIR/live.json"
  stderr_log="$BATS_TEST_TMPDIR/live.stderr"
  bash "$RUNNER" --summary-only --live-progress --receipt "$receipt" -- \
    bash -c 'echo "START: first.bats pid=1 weight=1 timeout=10s"; sleep 2; echo "DONE: first.bats rc=0"; echo "1..1"; echo "ok 1 live"' \
    >"$BATS_TEST_TMPDIR/live.stdout" 2>"$stderr_log" &
  runner_pid=$!

  progress_seen=0
  for _ in 1 2 3 4 5; do
    if [[ -f "${receipt%.json}.progress.json" ]]; then
      python3 - "${receipt%.json}.progress.json" <<'PY'
import json, sys
d=json.load(open(sys.argv[1], encoding="utf-8"))
assert d["complete"] is False
assert d["files_started"] >= 1
PY
      progress_seen=1
      break
    fi
    sleep 1
  done
  wait "$runner_pid"

  [ "$progress_seen" -eq 1 ]
  [ ! -e "${receipt%.json}.progress.json" ]
  grep -Fq 'START: first.bats' "$stderr_log"
  grep -Fq 'DONE: first.bats rc=0' "$stderr_log"
}
