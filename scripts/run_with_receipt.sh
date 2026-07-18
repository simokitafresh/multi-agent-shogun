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

receipt="" artifact="" max_bytes=1048576 declared="" verify=""
while (($#)); do
    case "$1" in
        --receipt) receipt="${2:-}"; shift 2 ;;
        --artifact) artifact="${2:-}"; shift 2 ;;
        --max-bytes) max_bytes="${2:-}"; shift 2 ;;
        --declared-test-count) declared="${2:-}"; shift 2 ;;
        --verify-receipt) verify="${2:-}"; shift 2 ;;
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
signal_name=""

write_receipt() {
    local rc="$1" complete="$2" signal_value="$3"
    local ended_ms duration observed skips plan result sha receipt_tmp
    ended_ms="$(date +%s%3N)"
    duration=$((ended_ms - started_ms))
    observed="$(grep -Ec '^(ok|not ok)([[:space:]]|$)' "$artifact_tmp" 2>/dev/null || true)"
    skips="$(grep -Eic '^ok .*#[[:space:]]*skip([[:space:]]|$)' "$artifact_tmp" 2>/dev/null || true)"
    plan="$(sed -nE 's/^1\.\.([0-9]+)([[:space:]].*)?$/\1/p' "$artifact_tmp" | tail -n 1)"
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
    [[ -z "$child_pid" ]] || kill -TERM "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
    head -c "$max_bytes" "$raw" > "$artifact_tmp"
    write_receipt 128 false "$signal_name" "$@"
    rm -f "$raw"
    exit 128
}
trap 'on_signal TERM "$@"' TERM
trap 'on_signal INT "$@"' INT
trap 'rm -f "$raw" "$artifact_tmp"' EXIT

"$@" > "$raw" 2>&1 &
child_pid=$!
wait "$child_pid"
rc=$?
child_pid=""
head -c "$max_bytes" "$raw" > "$artifact_tmp"
cat "$artifact_tmp"
complete=true
write_receipt "$rc" "$complete" "" "$@"
rm -f "$raw"
trap - EXIT
[[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"])' "$receipt")" == PASS ]]
