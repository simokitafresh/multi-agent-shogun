#!/usr/bin/env bash
# insight_resolve.sh — emit an immutable insight resolution operation.
set -euo pipefail
SELF="${BASH_SOURCE[0]}"; [[ "$SELF" = /* ]] || SELF="$PWD/$SELF"
SCRIPT_DIR="${SELF%/scripts/insight_resolve.sh}"
[[ $# -eq 3 ]] || { echo 'Usage: insight_resolve.sh <insight_id> <reason> <action_artifact>' >&2; exit 1; }
INSIGHT_ID="$1"; REASON="$2"; ACTION_ARTIFACT="$3"
INSIGHTS_FILE="${INSIGHTS_FILE:-${SCRIPT_DIR%/scripts}/queue/insights.yaml}"
[[ -f "$INSIGHTS_FILE" ]] || { echo "ERROR: insights file not found: $INSIGHTS_FILE" >&2; exit 1; }
if [[ "${INSIGHT_ALLOW_RESOLVE_WITH_CORRUPT:-0}" != 1 ]] && compgen -G "${INSIGHTS_FILE}.corrupt.*" >/dev/null; then
    echo "ERROR: unresolved corrupt insight quarantine remains in queue root" >&2
    exit 1
fi
[[ -n "${REASON//[[:space:]]/}" && -n "${ACTION_ARTIFACT//[[:space:]]/}" ]] || { echo 'ERROR: resolution evidence must be non-empty' >&2; exit 1; }
IFS=$'\t' read -r current_status current_reason current_artifact < <(python3 - "$INSIGHTS_FILE" "$INSIGHT_ID" <<'PY'
import sys
path, ident = sys.argv[1:]
lines = open(path, encoding='utf-8').read().splitlines()
start = next((i for i,line in enumerate(lines) if line.strip() == f'- id: {ident}'), None)
if start is None: raise SystemExit(f'ERROR: insight not found: {ident}')
end = next((i for i in range(start+1,len(lines)) if lines[i].startswith('- id: ')), len(lines))
values = {}
for line in lines[start:end]:
    if ':' in line:
        key, value = line.strip().split(':',1)
        values[key] = value.strip().strip('"\'')
print(values.get('status',''), values.get('resolved_reason',''), values.get('action_artifact',''), sep='\t')
PY
)
if [[ "$current_status" == resolved && "$current_reason" == "$REASON" && "$current_artifact" == "$ACTION_ARTIFACT" ]]; then
    echo "IDEMPOTENT: $INSIGHT_ID already resolved with identical evidence"
    exit 0
fi
LEDGER_WRITER="$SCRIPT_DIR/scripts/ledger_writer.sh"
PUBLISHER_SINGLE_HELPER="$SCRIPT_DIR/scripts/lib/publisher_single_flag.sh"
publisher_single_insights_enabled() {
    [[ -x "$LEDGER_WRITER" ]] || return 1
    [[ "$INSIGHTS_FILE" == "$SCRIPT_DIR/queue/insights.yaml" ]] || return 1
    [[ -f "$PUBLISHER_SINGLE_HELPER" ]] || return 1
    # shellcheck source=lib/publisher_single_flag.sh
    source "$PUBLISHER_SINGLE_HELPER"
    publisher_single_enabled "$SCRIPT_DIR"
}
if ! publisher_single_insights_enabled; then
    INSIGHTS_FILE_ENV="$INSIGHTS_FILE" INSIGHT_ID_ENV="$INSIGHT_ID" REASON_ENV="$REASON" ACTION_ENV="$ACTION_ARTIFACT" python3 - <<'PY'
import json, os, tempfile
path=os.environ['INSIGHTS_FILE_ENV']; ident=os.environ['INSIGHT_ID_ENV']
lines=open(path,encoding='utf-8').read().splitlines(keepends=True)
start=next(i for i,line in enumerate(lines) if line.strip()==f'- id: {ident}')
end=next((i for i in range(start+1,len(lines)) if lines[i].startswith('- id: ')),len(lines))
values={'status':'resolved','resolved_reason':os.environ['REASON_ENV'],'action_artifact':os.environ['ACTION_ENV'],'resolved_at':__import__('datetime').datetime.now().isoformat()}
block=lines[start:end]
for key,value in values.items():
    replacement=f'  {key}: {json.dumps(value,ensure_ascii=False)}\n'
    pos=next((i for i,line in enumerate(block) if line.startswith(f'  {key}:')),None)
    if pos is None: block.append(replacement)
    else: block[pos]=replacement
lines[start:end]=block
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(path),prefix='.insight-resolve.')
with os.fdopen(fd,'w',encoding='utf-8') as stream: stream.writelines(lines)
delay=float(os.environ.get('INSIGHT_TEST_SLEEP_BEFORE_REPLACE','0') or '0')
if delay > 0: __import__('time').sleep(delay)
os.replace(tmp,path)
PY
    echo "OK: $INSIGHT_ID → resolved"
    exit 0
fi
ledger_op_path="$(LEDGER_SOURCE_FILE="$INSIGHTS_FILE" bash "$LEDGER_WRITER" resolve insights "$INSIGHT_ID" \
    --expect "status=${current_status}" --resolved-reason "$REASON" --action-artifact "$ACTION_ARTIFACT")"
printf '%s\n' "$ledger_op_path"
echo "OK: $INSIGHT_ID → resolved"
