#!/usr/bin/env bash
# Connect existing observe/select/deploy/checkpoint/record/rerank CLIs.
set -euo pipefail

usage() {
  echo "usage: throughput_growth_loop.sh --event-id ID --ledger PATH --event PATH --observe CMD --select CMD --deploy CMD --checkpoint CMD --record CMD --rerank CMD [--idle yes|no] [--production yes|no]" >&2
  exit 2
}

event_id= ledger= event= observe= select= deploy= checkpoint= record= rerank=
idle=yes production=no
while (($#)); do
  case "$1" in
    --event-id) event_id=${2:-}; shift 2;; --ledger) ledger=${2:-}; shift 2;;
    --event) event=${2:-}; shift 2;; --observe) observe=${2:-}; shift 2;;
    --select) select=${2:-}; shift 2;; --deploy) deploy=${2:-}; shift 2;;
    --checkpoint) checkpoint=${2:-}; shift 2;; --record) record=${2:-}; shift 2;;
    --rerank) rerank=${2:-}; shift 2;; --idle) idle=${2:-}; shift 2;;
    --production) production=${2:-}; shift 2;; *) usage;;
  esac
done
for value in "$event_id" "$ledger" "$event" "$observe" "$select" "$deploy" "$checkpoint" "$record" "$rerank"; do
  [[ -n "$value" ]] || usage
done
[[ -f "$event" ]] || { echo "BLOCK event_missing" >&2; exit 3; }
for cmd in "$observe" "$select" "$deploy" "$checkpoint" "$record" "$rerank"; do
  [[ -x "$cmd" ]] || { echo "BLOCK phase_unconnected command=$cmd" >&2; exit 3; }
done
mkdir -p "${ledger%/*}"
exec 9>>"$ledger.lock"
flock -x 9

append() { printf '%s\n' "$1" >>"$ledger"; }
if grep -Fq '"event_id":"'"$event_id"'"' "$ledger" 2>/dev/null; then
  append '{"event_id":"'"$event_id"'","state":"BLOCK","reason":"duplicate"}'
  echo "BLOCK duplicate"; exit 0
fi
if [[ "$idle" != yes ]]; then
  append '{"event_id":"'"$event_id"'","state":"BLOCK","reason":"no_idle_worker"}'
  echo "BLOCK no_idle_worker"; exit 0
fi
if [[ "$production" != no ]]; then
  append '{"event_id":"'"$event_id"'","state":"BLOCK","reason":"production_or_irreversible"}'
  echo "BLOCK production_or_irreversible"; exit 0
fi

tmpdir=$(mktemp -d "${ledger%/*}/.throughput-loop.XXXXXX")
trap 'find "$tmpdir" -maxdepth 1 -type f -delete; rmdir "$tmpdir"' EXIT
"$observe" "$event" "$tmpdir/observed.json"
"$select" "$tmpdir/observed.json" "$tmpdir/selected.json"
python3 - "$tmpdir/selected.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
if not d.get("candidate_id") or float(d.get("blocked_agent_seconds", 0)) <= 0:
    raise SystemExit("BLOCK invalid_selection")
PY
"$deploy" "$tmpdir/selected.json" "$tmpdir/deployed.json"
if ! "$checkpoint" "$tmpdir/deployed.json" "$tmpdir/checkpoint.json"; then
  append '{"event_id":"'"$event_id"'","state":"BLOCK","reason":"checkpoint_fail"}'
  echo "BLOCK checkpoint_fail"; exit 0
fi
"$record" "$tmpdir/checkpoint.json" "$tmpdir/recorded.json"
"$rerank" "$tmpdir/recorded.json" "$tmpdir/reranked.json"
append '{"event_id":"'"$event_id"'","state":"COMPLETE","reason":"checkpoint_pass"}'
echo "COMPLETE event_id=$event_id"
