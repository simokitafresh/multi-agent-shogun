#!/usr/bin/env bash
# run_with_receipt.sh — command output and terminal state as a durable atomic receipt

set -uo pipefail

usage() {
    cat <<'EOF'
Usage: run_with_receipt.sh --receipt PATH [--artifact PATH] [--max-bytes N]
                           [--declared-test-count N] -- COMMAND [ARG...]

Runs COMMAND once, stores bounded combined stdout/stderr, and atomically writes a
JSON receipt containing complete, result, rc, duration_ms, output_sha256,
declared_test_count, observed_test_count, and skip_count. TAP with a declared
count is complete only when the observed ok/not-ok count matches it.

       run_with_receipt.sh --verify-receipt PATH
Validates schema, artifact hash, rc, completeness, TAP counts, and SKIP=0.
EOF
}

receipt="" artifact="" max_bytes=1048576 declared="" verify="" summary_only=false live_progress=false
while (($#)); do
    case "$1" in
        --receipt) receipt="${2:-}"; shift 2 ;;
        --artifact) artifact="${2:-}"; shift 2 ;;
        --max-bytes) max_bytes="${2:-}"; shift 2 ;;
        --declared-test-count) declared="${2:-}"; shift 2 ;;
        --verify-receipt) verify="${2:-}"; shift 2 ;;
        --summary-only) summary_only=true; shift ;;
        --live-progress) live_progress=true; shift ;;
        --help|-h) usage; exit 0 ;;
        --) shift; break ;;
        *) printf 'ERROR: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ -n "$verify" ]]; then
    python3 - "$verify" <<'PY'
import hashlib, json, os, sys
path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as fh: data = json.load(fh)
    required = {"version", "complete", "result", "rc", "duration_ms", "output_sha256",
                "declared_test_count", "observed_test_count", "skip_count", "artifact",
                "signal", "command"}
    if set(data) != required or data["version"] != 1: raise ValueError("schema")
    with open(data["artifact"], "rb") as fh: actual = hashlib.sha256(fh.read()).hexdigest()
    valid = (actual == data["output_sha256"] and data["complete"] is True and
             data["result"] == "PASS" and data["rc"] == 0 and data["skip_count"] == 0 and
             (data["declared_test_count"] == 0 or
              data["observed_test_count"] == data["declared_test_count"]))
    if not valid: raise ValueError("terminal contract")
except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError) as exc:
    print(f"RECEIPT_FAIL {exc}", file=sys.stderr)
    raise SystemExit(1)
print("RECEIPT_PASS")
PY
    exit $?
fi

[[ -n "$receipt" && $# -gt 0 ]] || { usage >&2; exit 2; }
[[ "$max_bytes" =~ ^[1-9][0-9]*$ ]] || { printf 'ERROR: --max-bytes must be positive\n' >&2; exit 2; }
[[ -z "$declared" || "$declared" =~ ^[0-9]+$ ]] || { printf 'ERROR: --declared-test-count must be nonnegative\n' >&2; exit 2; }

receipt_dir="$(dirname "$receipt")"
mkdir -p "$receipt_dir"
artifact="${artifact:-${receipt%.json}.output}"
artifact_dir="$(dirname "$artifact")"
mkdir -p "$artifact_dir"
raw="$(mktemp "$receipt_dir/.run_receipt.raw.XXXXXX")"
artifact_tmp="$(mktemp "$artifact_dir/.run_receipt.artifact.XXXXXX")"
started_ms="$(date +%s%3N)"
child_pid=""
command_pgid=""
signal_name=""
progress="${receipt%.json}.progress.json"

write_progress() {
    local line_count started done last_file progress_tmp
    line_count="$(wc -l <"$raw" 2>/dev/null || printf 0)"
    started="$(grep -c '^START: ' "$raw" 2>/dev/null || true)"
    done="$(grep -c '^DONE: ' "$raw" 2>/dev/null || true)"
    last_file="$(sed -nE 's/^(START|DONE): ([^ ]+).*/\2/p' "$raw" | tail -1)"
    progress_tmp="$(mktemp "$receipt_dir/.run_receipt.progress.XXXXXX")"
    python3 - "$progress_tmp" "$started_ms" "$line_count" "$started" "$done" "$last_file" "$@" <<'PY'
import json, os, sys, time
path, started_ms, lines, started, done, last_file, *command = sys.argv[1:]
data = {
    "version": 1,
    "complete": False,
    "started_ms": int(started_ms),
    "updated_ms": int(time.time() * 1000),
    "output_lines": int(lines),
    "files_started": int(started),
    "files_done": int(done),
    "last_file": last_file or None,
    "command": command,
}
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, sort_keys=True); fh.write("\n"); fh.flush(); os.fsync(fh.fileno())
PY
    mv -f "$progress_tmp" "$progress"
}

write_receipt() {
    local rc="$1" complete="$2" signal_value="$3"
    shift 3
    local ended_ms duration observed skips plan result sha receipt_tmp
    ended_ms="$(date +%s%3N)"
    duration=$((ended_ms - started_ms))
    observed="$(grep -Ec '^(ok|not ok)([[:space:]]|$)' "$artifact_tmp" 2>/dev/null || true)"
    skips="$(grep -Eic '^ok .*#[[:space:]]*skip([[:space:]]|$)' "$artifact_tmp" 2>/dev/null || true)"
    plan="$(sed -nE 's/^1\.\.([0-9]+)([[:space:]].*)?$/\1/p' "$artifact_tmp" | awk '{s+=$1} END{print s+0}')"
    [[ -n "$declared" ]] || declared="${plan:-0}"
    if [[ "$complete" == true && "$declared" -gt 0 && "$observed" -ne "$declared" ]]; then complete=false; fi
    if [[ "$complete" == true && "$rc" -eq 0 && "$skips" -eq 0 ]]; then result=PASS; else result=FAIL; fi
    sha="$(sha256sum "$artifact_tmp" | awk '{print $1}')"
    receipt_tmp="$(mktemp "$receipt_dir/.run_receipt.json.XXXXXX")"
    python3 - "$receipt_tmp" "$complete" "$result" "$rc" "$duration" "$sha" "$declared" "$observed" "$skips" "$artifact" "$signal_value" "$@" <<'PY'
import json, os, sys
path, complete, result, rc, duration, sha, declared, observed, skips, artifact, signal, *command = sys.argv[1:]
data = {
    "version": 1, "complete": complete == "true", "result": result,
    "rc": int(rc), "duration_ms": int(duration), "output_sha256": sha,
    "declared_test_count": int(declared), "observed_test_count": int(observed),
    "skip_count": int(skips), "artifact": artifact, "signal": signal or None,
    "command": command,
}
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, sort_keys=True); fh.write("\n"); fh.flush(); os.fsync(fh.fileno())
PY
    mv -f "$artifact_tmp" "$artifact"
    mv -f "$receipt_tmp" "$receipt"
}

on_signal() {
    signal_name="$1"
    shift
    # COMMAND owns a dedicated session/process group (see launch below), so a
    # signal cannot leave grandchildren doing work after the receipt runner
    # has published its terminal state.  Scope TERM to that command group;
    # never signal the caller's/heavy admission's process group.
    if [[ -n "$child_pid" ]]; then
        command_pgid="$child_pid"
        kill -TERM -- "-$child_pid" 2>/dev/null || true
        wait "$child_pid" 2>/dev/null || true
        child_pid=""
    fi
    cleanup_command_group "$command_pgid"
    head -c "$max_bytes" "$raw" > "$artifact_tmp"
    write_receipt 128 false "$signal_name" "$@"
    rm -f "$raw"
    exit 128
}
trap 'on_signal TERM "$@"' TERM
trap 'on_signal INT "$@"' INT
trap 'rm -f "$raw" "$artifact_tmp"' EXIT

cleanup_command_group() {
    local pgid="$1" member_pid member_pgid member_stat snapshot
    [[ "$pgid" =~ ^[1-9][0-9]*$ ]] || return 0
    # COMMAND owns a dedicated session. A command can return while a
    # background descendant still has that session's PGID, so normal exit
    # needs the same bounded drain as signal exit.
    snapshot="$(ps -e -o pid=,pgid=,stat= 2>/dev/null || true)"
    while read -r member_pid member_pgid member_stat; do
        [[ "$member_pgid" == "$pgid" && "$member_stat" != Z* ]] || continue
        kill -TERM "$member_pid" 2>/dev/null || true
    done <<< "$snapshot"
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        snapshot="$(ps -e -o pid=,pgid=,stat= 2>/dev/null || true)"
        if ! awk -v pgid="$pgid" '$2 == pgid && $3 !~ /^Z/ { found=1 } END { exit found ? 0 : 1 }' <<< "$snapshot"; then
            return 0
        fi
        sleep 0.05
    done
    # TERM is cooperative; a stubborn descendant must not survive the
    # receipt boundary. Scope escalation to the same dedicated session.
    snapshot="$(ps -e -o pid=,pgid=,stat= 2>/dev/null || true)"
    while read -r member_pid member_pgid member_stat; do
        [[ "$member_pgid" == "$pgid" && "$member_stat" != Z* ]] || continue
        kill -KILL "$member_pid" 2>/dev/null || true
    done <<< "$snapshot"
}

# Keep COMMAND and all of its descendants in a group owned by this invocation.
# This makes signal cleanup complete without broadening the signal boundary to
# the receipt runner, its caller, or an enclosing heavy-job admission group.
setsid -- "$@" > "$raw" 2>&1 &
child_pid=$!
if [[ "$live_progress" == true ]]; then
    published_lines=0
    while state="$(ps -o stat= -p "$child_pid" 2>/dev/null)" \
        && [[ -n "$state" && "$state" != Z* ]]; do
        sleep 1
        current_lines="$(wc -l <"$raw" 2>/dev/null || printf 0)"
        if ((current_lines > published_lines)); then
            sed -n "$((published_lines + 1)),${current_lines}p" "$raw" >&2
            published_lines="$current_lines"
        fi
        write_progress "$@"
    done
fi
wait "$child_pid"
rc=$?
command_pgid="$child_pid"
child_pid=""
if [[ "$live_progress" == true ]]; then
    current_lines="$(wc -l <"$raw" 2>/dev/null || printf 0)"
    if ((current_lines > published_lines)); then
        sed -n "$((published_lines + 1)),${current_lines}p" "$raw" >&2
    fi
    write_progress "$@"
fi
cleanup_command_group "$command_pgid"
head -c "$max_bytes" "$raw" > "$artifact_tmp"
if [[ "$summary_only" == true ]]; then
    printf 'RECEIPT_WRITTEN %s artifact=%s\n' "$receipt" "$artifact" >&2
else
    cat "$artifact_tmp"
fi
complete=true
write_receipt "$rc" "$complete" "" "$@"
rm -f "$raw"
rm -f "$progress"
trap - EXIT
[[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"])' "$receipt")" == PASS ]]
