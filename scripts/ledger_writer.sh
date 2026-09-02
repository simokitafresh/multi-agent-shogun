#!/usr/bin/env bash
# ledger_writer.sh — immutable ledger operations for the U6 single-publisher boundary.
# Operation files are JSON, which is valid YAML and avoids yaml.dump data loss.
set -euo pipefail

SELF="${BASH_SOURCE[0]}"
[[ "$SELF" = /* ]] || SELF="$PWD/$SELF"
SCRIPT_DIR="${SELF%/*}"
REPO_ROOT="${SCRIPT_DIR%/*}"
die() { printf 'ledger_writer: %s\n' "$*" >&2; exit 2; }

resolve_state_dir() {
    local configured="${SHOGUN_STATE_DIR:-${HOME:-}/.local/share/multi-agent-shogun}"
    [[ "$configured" = /* && -n "$configured" ]] || die "STATE_DIR must be absolute"
    mkdir -p -- "$configured"
    STATE_DIR="$(cd -- "$configured" && pwd -P)"
    local root
    root="$(cd -- "$REPO_ROOT" && pwd -P)"
    # Explicit fixture directories may be ephemeral; only the implicit
    # default is required to be a persistent location.
    if [[ -z "${SHOGUN_STATE_DIR+x}" && "$STATE_DIR" == /tmp/* ]]; then
        die "implicit STATE_DIR under /tmp is not persistent: $STATE_DIR"
    fi
    case "$STATE_DIR" in "$root"|"$root"/*) die "STATE_DIR must not be inside repository: $STATE_DIR";; esac
}
ledger_dir() {
    case "$1" in
        insights|lessons|bulletin|workarounds) printf '%s/ledger_inbox/%s\n' "$STATE_DIR" "$1";;
        *) die "unknown ledger: $1";;
    esac
}
ledger_file() {
    local ledger="$1" value
    case "$ledger" in
        insights) value="${LEDGER_INSIGHTS_FILE:-${INSIGHTS_FILE:-$REPO_ROOT/queue/insights.yaml}}";;
        bulletin) value="${LEDGER_BULLETIN_FILE:-${BULLETIN_FILE:-$REPO_ROOT/queue/bulletin_board.yaml}}";;
        workarounds) value="${LEDGER_WORKAROUNDS_FILE:-${KARO_WORKAROUND_LOG_FILE:-$REPO_ROOT/logs/karo_workarounds.yaml}}";;
        lessons) value="${LEDGER_LESSONS_FILE:-${LESSONS_FILE:-}}";;
        *) die "unknown ledger: $ledger";;
    esac
    [[ -n "$value" ]] || die "lessons ledger requires LEDGER_LESSONS_FILE or LESSONS_FILE"
    printf '%s\n' "$value"
}
next_seq() {
    local dir="$1" n
    mkdir -p -- "$dir"
    exec 9>"$dir/.lock"
    flock -x 9
    n="$(cat "$dir/.seq" 2>/dev/null || printf '0')"
    [[ "$n" =~ ^[0-9]+$ ]] || n=0
    n=$((n + 1))
    printf '%s\n' "$n" >"$dir/.seq"
    flock -u 9
    exec 9>&-
    printf '%012d\n' "$n"
}
write_op() {
    local ledger="$1" body="$2" dir seq name tmp
    dir="$(ledger_dir "$ledger")"
    seq="$(next_seq "$dir")"
    name="$(date -u +%Y%m%dT%H%M%S%NZ)_${seq}.yaml"
    tmp="$dir/.$name.$$"
    printf '%s\n' "$body" >"$tmp"
    mv -- "$tmp" "$dir/$name"
    printf '%s\n' "$dir/$name"
}
entry_id() {
    python3 - "$1" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
for pattern in (r"^\s*-\s+(?:id|cmd_id):\s*['\"]?([^'\"\s]+)", r"^###\s+(L[0-9]+):"):
    match = re.search(pattern, text, re.MULTILINE)
    if match:
        print(match.group(1)); raise SystemExit(0)
raise SystemExit("entry must contain id, cmd_id, or a markdown lesson heading")
PY
}
append_op() {
    [[ $# -eq 2 ]] || die "usage: append <ledger> <entry.yaml>"
    local ledger="$1" entry="$2" source hash body id
    [[ -f "$entry" ]] || die "entry file not found: $entry"
    source="${LEDGER_SOURCE_FILE:-$(ledger_file "$ledger")}"
    hash="$(sha256sum "$entry" | awk '{print $1}')"
    id="$(entry_id "$entry")"
    body="$(LEDGER_ENV_LEDGER="$ledger" LEDGER_ENV_SOURCE="$source" LEDGER_ENV_ENTRY="$entry" LEDGER_ENV_HASH="$hash" LEDGER_ENV_ID="$id" python3 - <<'PY'
import json, os
from datetime import datetime, timezone
print(json.dumps({"op":"append","ledger":os.environ["LEDGER_ENV_LEDGER"],"id":os.environ["LEDGER_ENV_ID"],"entry_hash":os.environ["LEDGER_ENV_HASH"],"issued_at":datetime.now(timezone.utc).isoformat(),"source_file":os.environ["LEDGER_ENV_SOURCE"],"entry_text":open(os.environ["LEDGER_ENV_ENTRY"],encoding="utf-8").read()},ensure_ascii=False,sort_keys=True))
PY
    )"
    write_op "$ledger" "$body"
}
assignment_parts() {
    [[ "$1" == *=* ]] || die "field assignment must be field=value"
    printf '%s\t%s\n' "${1%%=*}" "${1#*=}"
}
update_op() {
    [[ $# -ge 4 ]] || die "usage: update <ledger> <id> <field=value> --expect <field=old>"
    local ledger="$1" id="$2" expect_field="" expect_value="" source hash fields expected body
    shift 2
    local -a assignments=()
    while [[ $# -gt 0 ]]; do
        if [[ "$1" = --expect ]]; then
            [[ $# -ge 2 ]] || die "--expect requires field=value"
            IFS=$'\t' read -r expect_field expect_value < <(assignment_parts "$2")
            shift 2
        else
            [[ "$1" != --* ]] || die "unknown option: $1"
            assignments+=("$1"); shift
        fi
    done
    [[ -n "$expect_field" ]] || die "--expect is required"
    for assignment in "${assignments[@]}"; do
        field_name="${assignment%%=*}"
        case "$ledger:$field_name" in
            insights:status|insights:resolved_reason|insights:action_artifact|insights:resolved_at|insights:fix_known|lessons:status|lessons:retired_at|lessons:retire_reason|bulletin:status|bulletin:actioned_by|bulletin:confirmed_by|workarounds:status) ;;
            *) printf 'ledger_writer: field outside %s allowlist: %s\n' "$ledger" "$field_name" >&2; return 12 ;;
        esac
    done
    source="${LEDGER_SOURCE_FILE:-$(ledger_file "$ledger")}" 
    [[ -f "$source" ]] || die "ledger file not found: $source"
    IFS=$'\t' read -r hash fields expected < <(
        LEDGER_ENV_FILE="$source" LEDGER_ENV_ID="$id" LEDGER_ENV_EXPECT_FIELD="$expect_field" LEDGER_ENV_EXPECT_VALUE="$expect_value" LEDGER_ENV_ASSIGNMENTS="$(printf '%s\n' "${assignments[@]}")" python3 - <<'PY'
import hashlib, json, os, re
path, ident = os.environ["LEDGER_ENV_FILE"], os.environ["LEDGER_ENV_ID"]
text=open(path,encoding="utf-8").read(); lines=text.splitlines(keepends=True)
if re.fullmatch(r"L[0-9]+",ident):
    starts=[i for i,l in enumerate(lines) if re.match(r"^###\s+"+re.escape(ident)+r":",l)]
else:
    starts=[i for i,l in enumerate(lines) if re.search(r"^\s*-\s+(?:id|cmd_id):\s*['\"]?"+re.escape(ident)+r"(?:['\"]|\s|$)",l)]
if len(starts)!=1: raise SystemExit(f"target id must be unique: {ident} ({len(starts)})")
start=starts[0]; base=len(lines[start])-len(lines[start].lstrip()); end=len(lines)
for i in range(start+1,len(lines)):
    if re.match(r"^###\s+L[0-9]+:",lines[i]) or (re.match(r"^\s*-\s+(?:id|cmd_id):",lines[i]) and len(lines[i])-len(lines[i].lstrip())<=base): end=i; break
def scalar(v):
    v=v.strip()
    return v[1:-1] if len(v)>=2 and v[0]==v[-1] and v[0] in "'\"" else v
values={}
for line in lines[start:end]:
    m=re.match(r"^\s*(?:-\s*)?(?:\*\*)?([A-Za-z_][A-Za-z0-9_]*)\*?:\s*(.*)$",line.rstrip("\n"))
    if m: values[m.group(1)]=scalar(m.group(2))
field,value=os.environ["LEDGER_ENV_EXPECT_FIELD"],os.environ["LEDGER_ENV_EXPECT_VALUE"]
if field not in values and value != "": raise SystemExit(f"expected field not found: {field}")
assignments={}
for item in os.environ["LEDGER_ENV_ASSIGNMENTS"].splitlines():
    if item: k,v=item.split("=",1); assignments[k]=v
print(hashlib.sha256("".join(lines[start:end]).encode()).hexdigest(),end="\t")
print(json.dumps(assignments,ensure_ascii=False),end="\t")
print(json.dumps({field:value},ensure_ascii=False))
PY
    )
    body="$(LEDGER_ENV_LEDGER="$ledger" LEDGER_ENV_ID="$id" LEDGER_ENV_SOURCE="$source" LEDGER_ENV_HASH="$hash" LEDGER_ENV_FIELDS="$fields" LEDGER_ENV_EXPECTED="$expected" python3 - <<'PY'
import json, os
from datetime import datetime, timezone
print(json.dumps({"op":"update","ledger":os.environ["LEDGER_ENV_LEDGER"],"id":os.environ["LEDGER_ENV_ID"],"entry_hash":os.environ["LEDGER_ENV_HASH"],"issued_at":datetime.now(timezone.utc).isoformat(),"source_file":os.environ["LEDGER_ENV_SOURCE"],"fields":json.loads(os.environ["LEDGER_ENV_FIELDS"]),"expected":json.loads(os.environ["LEDGER_ENV_EXPECTED"])},ensure_ascii=False,sort_keys=True))
PY
    )"
    write_op "$ledger" "$body"
}
resolve_op() {
    [[ $# -ge 4 ]] || die "usage: resolve <ledger> <id> --expect status=<old>"
    local ledger="$1" id="$2" expected=""; shift 2
    local -a fields=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --expect) expected="$2"; shift 2;;
            --resolved-reason) fields+=("resolved_reason=$2"); shift 2;;
            --action-artifact) fields+=("action_artifact=$2"); shift 2;;
            *) die "unknown option: $1";;
        esac
    done
    [[ "$expected" == status=* ]] || die "resolve requires --expect status=<old>"
    update_op "$ledger" "$id" status=resolved "${fields[@]}" --expect "$expected"
}
reject_op() {
    local op="$1" reason="$2" dest
    dest="$(dirname "$op")/rejected/$(basename "$op")"
    mkdir -p -- "$(dirname "$dest")"; [[ ! -e "$dest" ]] || dest="$dest.$$"
    mv -- "$op" "$dest"
    if [[ "${LEDGER_WRITER_NOTIFY:-1}" = 1 && -x "$SCRIPT_DIR/inbox_write.sh" ]]; then
        bash "$SCRIPT_DIR/inbox_write.sh" karo "ledger CAS rejected ledger=$(basename "$(dirname "$op")") op=$(basename "$op") reason=$reason" report_received ledger_writer notify_karo >/dev/null 2>&1 || true
    fi
    printf 'REJECTED %s\n' "$dest"
}
apply_op() {
    [[ $# -eq 1 ]] || die "usage: apply <op.yaml>"
    local op="$1"
    [[ -f "$op" ]] || die "operation file not found: $op"
    LEDGER_ENV_OP="$op" LEDGER_ENV_SCRIPT="$SCRIPT_DIR" python3 - <<'PY'
import hashlib,json,os,re,shutil,subprocess,sys,tempfile
from pathlib import Path
operation=Path(os.environ["LEDGER_ENV_OP"]); data=json.loads(operation.read_text(encoding="utf-8"))
ledger=data.get("ledger"); source=os.environ.get("LEDGER_SOURCE_FILE") or data.get("source_file")
if not source: raise SystemExit("apply requires source_file in operation or LEDGER_SOURCE_FILE")
path=Path(source)
if not path.exists(): raise SystemExit(f"ledger file not found: {path}")
text=path.read_text(encoding="utf-8"); lines=text.splitlines(keepends=True); ident=str(data.get("id","")); is_lesson=ledger=="lessons" or bool(re.fullmatch(r"L[0-9]+",ident))
def found():
    if is_lesson: return [i for i,l in enumerate(lines) if re.match(r"^###\s+"+re.escape(ident)+r":",l)]
    return [i for i,l in enumerate(lines) if re.search(r"^\s*-\s+(?:id|cmd_id):\s*['\"]?"+re.escape(ident)+r"(?:['\"]|\s|$)",l)]
def end(start):
    base=len(lines[start])-len(lines[start].lstrip())
    for i in range(start+1,len(lines)):
        if re.match(r"^###\s+L[0-9]+:",lines[i]) or (re.match(r"^\s*-\s+(?:id|cmd_id):",lines[i]) and len(lines[i])-len(lines[i].lstrip())<=base): return i
    return len(lines)
def reject(reason):
    dest=operation.parent/"rejected"/operation.name; dest.parent.mkdir(parents=True,exist_ok=True)
    if dest.exists(): dest=dest.with_name(dest.name+"."+str(os.getpid()))
    shutil.move(str(operation),str(dest))
    helper=Path(os.environ["LEDGER_ENV_SCRIPT"])/"inbox_write.sh"
    if os.environ.get("LEDGER_WRITER_NOTIFY", "1") == "1" and helper.exists(): subprocess.run(["bash",str(helper),"karo",f"ledger CAS rejected ledger={ledger} id={ident} op={operation.name} reason={reason}","report_received","ledger_writer","notify_karo"],check=False,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    print(f"REJECTED {dest}"); raise SystemExit(11)
matches=found()
if data.get("op")=="append":
    if matches: reject("duplicate_id")
    entry=str(data.get("entry_text",""))
    if hashlib.sha256(entry.encode()).hexdigest()!=data.get("entry_hash"): raise SystemExit("entry_hash mismatch")
    if ledger=="lessons": new=text.rstrip("\n")+"\n\n"+entry.rstrip("\n")+"\n"
    else:
        header={"insights":"insights:","bulletin":"entries:","workarounds":""}[ledger]
        if not text.strip(): text=header+"\n" if header else ""
        if header and not text.startswith(header+"\n"): raise SystemExit(f"{ledger} ledger has unexpected root shape")
        new=text.rstrip("\n")+"\n"+entry.lstrip("\n"); new += "" if new.endswith("\n") else "\n"
elif data.get("op") in ("update","resolve"):
    if len(matches)!=1: reject("target_not_unique")
    start,stop=matches[0],end(matches[0]); block=lines[start:stop]
    def scalar(v):
        v=v.strip(); return v[1:-1] if len(v)>=2 and v[0]==v[-1] and v[0] in "'\"" else v
    values={}
    for line in block:
        m=re.match(r"^\s*(?:-\s*)?(?:\*\*)?([A-Za-z_][A-Za-z0-9_]*)\*?:\s*(.*)$",line.rstrip("\n"))
        if m: values[m.group(1)]=scalar(m.group(2))
    for field,expected in (data.get("expected") or {}).items():
        if values.get(field, "")!=str(expected): reject("expected_"+field+"_mismatch")
    allowed={"insights":{"status","resolved_reason","action_artifact","resolved_at","fix_known"},"lessons":{"status","retired_at","retire_reason"},"bulletin":{"status","actioned_by","confirmed_by"},"workarounds":{"status"}}[ledger]
    fields=data.get("fields") or {}
    if any(field not in allowed for field in fields): raise SystemExit("field outside allowlist")
    for field,value in fields.items():
        pattern=r"^\s*(?:-\s*)?(?:\*\*)?"+re.escape(field)+r"\*?:\s*"; changed=False
        for i,line in enumerate(block):
            if re.match(pattern,line):
                block[i]=line.split(":",1)[0]+": "+json.dumps(str(value),ensure_ascii=False)+"\n"; changed=True; break
        if not changed: block.append(("- **"+field+"**: " if is_lesson else "  "+field+": ")+json.dumps(str(value),ensure_ascii=False)+"\n")
    lines[start:stop]=block; new="".join(lines)
else: raise SystemExit("unsupported op")
fd,tmp=tempfile.mkstemp(prefix="."+path.name+".ledger.",dir=str(path.parent))
try:
    with os.fdopen(fd,"w",encoding="utf-8") as stream: stream.write(new); stream.flush(); os.fsync(stream.fileno())
    os.replace(tmp,path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
applied=operation.parent/"applied"; applied.mkdir(parents=True,exist_ok=True)
dest=applied/operation.name
if dest.exists(): dest=dest.with_name(dest.name+"."+str(os.getpid()))
shutil.move(str(operation),str(dest)); print(f"APPLIED {dest}")
PY
}
resolve_state_dir
case "${1:-}" in
    append) shift; append_op "$@";;
    update) shift; update_op "$@";;
    resolve) shift; resolve_op "$@";;
    apply) shift; apply_op "$@";;
    *) die "usage: append|update|resolve|apply ...";;
esac
