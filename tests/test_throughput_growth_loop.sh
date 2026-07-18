#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
tmp=$(mktemp -d); trap 'find "$tmp" -maxdepth 1 -type f -delete; rmdir "$tmp"' EXIT
mkcmd() { local name=$1 body=$2; printf '#!/usr/bin/env bash\nset -euo pipefail\n%s\n' "$body" >"$tmp/$name"; chmod +x "$tmp/$name"; }
mkcmd observe 'cp "$1" "$2"'
mkcmd select 'printf "{\"candidate_id\":\"slowest\",\"blocked_agent_seconds\":99}\\n" >"$2"'
mkcmd deploy 'printf "{\"deployed\":true}\\n" >"$2"'
mkcmd checkpoint 'printf "{\"quality\":\"pass\"}\\n" >"$2"'
mkcmd record 'cp "$1" "$2"'
mkcmd rerank 'printf "{\"next\":\"second\"}\\n" >"$2"'
printf '{"events":1}\n' >"$tmp/event.json"
run() { bash "$ROOT/scripts/throughput_growth_loop.sh" --event-id "$1" --ledger "$tmp/ledger.jsonl" --event "$tmp/event.json" --observe "$tmp/observe" --select "$tmp/select" --deploy "$tmp/deploy" --checkpoint "$tmp/checkpoint" --record "$tmp/record" --rerank "$tmp/rerank" "${@:2}"; }
[[ $(run e1) == COMPLETE* ]]
[[ $(run e1) == 'BLOCK duplicate' ]]
[[ $(run e2 --idle no) == 'BLOCK no_idle_worker' ]]
[[ $(run e3 --production yes) == 'BLOCK production_or_irreversible' ]]
mkcmd checkpoint_fail 'exit 1'
out=$(bash "$ROOT/scripts/throughput_growth_loop.sh" --event-id e4 --ledger "$tmp/ledger.jsonl" --event "$tmp/event.json" --observe "$tmp/observe" --select "$tmp/select" --deploy "$tmp/deploy" --checkpoint "$tmp/checkpoint_fail" --record "$tmp/record" --rerank "$tmp/rerank")
[[ "$out" == 'BLOCK checkpoint_fail' ]]
[[ $(grep -c '"event_id":"e1"' "$tmp/ledger.jsonl") -eq 2 ]]
[[ $(grep -c '"state":"COMPLETE"' "$tmp/ledger.jsonl") -eq 1 ]]
echo 'PASS 5 FAIL 0 SKIP 0 duplicate_deploy 0 lost 0'
