#!/usr/bin/env bash
# throughput_scan.sh — S1/S2 throughput ledgers -> fix_known insight queue
# Usage: bash scripts/throughput_scan.sh [--dry-run]

set -euo pipefail

self="${BASH_SOURCE[0]}"
[[ "$self" != /* ]] && self="$PWD/$self"
ROOT="${THROUGHPUT_SCAN_ROOT:-${self%/scripts/throughput_scan.sh}}"

LOOP_LEDGER="${THROUGHPUT_SCAN_LOOP_LEDGER:-$ROOT/logs/loop_ledger.yaml}"
FP_LEDGER="${THROUGHPUT_SCAN_FP_LEDGER:-$ROOT/logs/detector_fp_rate.yaml}"
INSIGHTS_FILE="${THROUGHPUT_SCAN_INSIGHTS_FILE:-$ROOT/queue/insights.yaml}"
INSIGHT_SCRIPT="${THROUGHPUT_SCAN_INSIGHT_SCRIPT:-$ROOT/scripts/insight_write.sh}"
GATE_METRICS="${THROUGHPUT_SCAN_GATE_METRICS:-$ROOT/logs/gate_metrics.log}"
TRAVERSAL_LEDGER="${THROUGHPUT_SCAN_TRAVERSAL_LEDGER:-$ROOT/logs/obsidian_traversal.yaml}"
DRY_RUN=0

if [[ "${1:-}" == "--record-traversal" ]]; then
    [[ $# -eq 9 ]] || { echo "Usage: $0 --record-traversal route event_id landing adjacent finding action origin existing_links_csv" >&2; exit 2; }
    python3 - "$TRAVERSAL_LEDGER" "${@:2}" <<'PY'
import fcntl, os, sys, yaml
from scripts.lib.yaml_atomic import atomic_yaml_write
p,route,eid,a,b,finding,action,origin,links=sys.argv[1:]
links=[x for x in links.split(',') if x]
expected=f"[[{a}]] -> [[{b}]] -> [[{action}]]"
if route not in {'preflight','semantic_search','causal_backlinks'} or origin != expected or not all(x in links for x in (a,b,action)):
    raise SystemExit('TRAVERSAL_REJECT: invalid route/origin/link')
os.makedirs(os.path.dirname(p) or '.',exist_ok=True)
lock=p+'.lock'
with open(lock,'a+') as lf:
 fcntl.flock(lf,fcntl.LOCK_EX)
 data=yaml.safe_load(open(p)) if os.path.exists(p) else {}; data=data or {}; events=data.setdefault('events',[])
 if any(str(e.get('event_id'))==eid for e in events): print('TRAVERSAL_DUPLICATE'); raise SystemExit(0)
 events.append({'event_id':eid,'route':route,'landing_node':a,'adjacent_node':b,'finding':finding,'connected_action':action,'hop_count':1,'origin':origin,'existing_links':links})
 atomic_yaml_write(p,data)
print('TRAVERSAL_RECORDED')
PY
    exit $?
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --loop-ledger)
            LOOP_LEDGER="${2:?--loop-ledger requires path}"
            shift 2
            ;;
        --fp-ledger)
            FP_LEDGER="${2:?--fp-ledger requires path}"
            shift 2
            ;;
        --insights)
            INSIGHTS_FILE="${2:?--insights requires path}"
            shift 2
            ;;
        --insight-script)
            INSIGHT_SCRIPT="${2:?--insight-script requires path}"
            shift 2
            ;;
        --gate-metrics)
            GATE_METRICS="${2:?--gate-metrics requires path}"
            shift 2
            ;;
        --traversal-ledger)
            TRAVERSAL_LEDGER="${2:?--traversal-ledger requires path}"
            shift 2
            ;;
        *)
            echo "Usage: bash scripts/throughput_scan.sh [--dry-run] [--loop-ledger path] [--fp-ledger path] [--insights path] [--insight-script path]" >&2
            exit 2
            ;;
    esac
done

if [[ "$DRY_RUN" != "1" && ! -x "$INSIGHT_SCRIPT" ]]; then
    echo "THROUGHPUT_SCAN_SKIP: insight_write.sh not executable: $INSIGHT_SCRIPT"
    exit 0
fi

python3 - "$LOOP_LEDGER" "$FP_LEDGER" "$INSIGHTS_FILE" "$INSIGHT_SCRIPT" "$DRY_RUN" "$GATE_METRICS" "$TRAVERSAL_LEDGER" <<'PY'
import os
import re
import statistics
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except Exception as exc:
    print(f"THROUGHPUT_SCAN_ERROR: PyYAML required: {exc}", file=sys.stderr)
    sys.exit(2)

loop_path, fp_path, insights_path, insight_script, dry_run_raw, gate_metrics_path, traversal_path = sys.argv[1:8]
dry_run = dry_run_raw == "1"

FP_RATE_THRESHOLD = float(os.environ.get("THROUGHPUT_SCAN_FP_RATE_THRESHOLD", "50"))
FP_FIRES_THRESHOLD = int(os.environ.get("THROUGHPUT_SCAN_FP_FIRES_THRESHOLD", "2"))
OVERHEAD_WORSEN_THRESHOLD = float(os.environ.get("THROUGHPUT_SCAN_OVERHEAD_WORSEN_THRESHOLD", "5"))
E2E_WORSEN_THRESHOLD = float(os.environ.get("THROUGHPUT_SCAN_E2E_WORSEN_THRESHOLD", "60"))

STAGE_TARGETS = {
    "deploy": "scripts/deploy_task.sh",
    "finalize": "scripts/cmd_complete_gate.sh",
}
MEASUREMENT_TARGET = "scripts/loop_ledger_update.sh"
BASELINE_GENERATED_AT = "2026-07-16T14:32:11Z"
BASELINE_E2E_SEC = 3213.5
RATCHET_TARGET_SEC = BASELINE_E2E_SEC / 2.0
RATCHET_MIN_SAMPLES = 5
POST_TELEMETRY_START = "2026-07-17T01:46:58"


def load_yaml(path):
    p = Path(path)
    if not p.is_file():
        return {}
    try:
        return yaml.safe_load(p.read_text(encoding="utf-8", errors="replace")) or {}
    except Exception as exc:
        print(f"THROUGHPUT_SCAN_WARN: failed to parse {path}: {exc}", file=sys.stderr)
        return {}


def as_float(value):
    try:
        if value in (None, ""):
            return None
        return float(value)
    except Exception:
        return None


def as_int(value):
    try:
        if value in (None, ""):
            return 0
        return int(value)
    except Exception:
        return 0


def sanitize_source(text):
    return re.sub(r"[^A-Za-z0-9_.:-]+", "_", text).strip("_")[:120] or "unknown"


def pending_insight_texts(path):
    data = load_yaml(path)
    result = []
    for entry in data.get("insights") or []:
        if isinstance(entry, dict) and str(entry.get("status") or "") == "pending":
            result.append(str(entry.get("insight") or ""))
    return result


def target_from_detector(detector):
    if detector.startswith("cmd_save:"):
        return "scripts/cmd_save.sh"
    if detector.startswith("escalation:"):
        return "scripts/gate_improvement_trigger.sh"
    return "scripts"


def verify_from_detector(detector):
    if detector.startswith("cmd_save:"):
        return "test -f logs/detector_fp_rate.yaml && test -f scripts/cmd_save.sh"
    if detector.startswith("escalation:"):
        return "test -f logs/detector_fp_rate.yaml && test -f scripts/gate_improvement_trigger.sh"
    return "test -f logs/detector_fp_rate.yaml"


def fmt_metric(value, suffix=""):
    num = as_float(value)
    if num is None:
        return "na"
    return f"{num:.1f}{suffix}"


def throughput_stage_summary(curr_tp):
    deploy = as_float(curr_tp.get('deploy_median_sec'))
    work = as_float(curr_tp.get('work_median_sec'))
    finalize = as_float(curr_tp.get('finalize_median_sec'))
    e2e = as_float(curr_tp.get('e2e_median_sec'))
    measured = None if None in (deploy, work, finalize) else deploy + work + finalize
    unmeasured = None if e2e is None or measured is None else max(0.0, e2e - measured)
    return (
        "stage_medians="
        f"deploy:{fmt_metric(curr_tp.get('deploy_median_sec'), 's')},"
        f"work:{fmt_metric(curr_tp.get('work_median_sec'), 's')},"
        f"finalize:{fmt_metric(curr_tp.get('finalize_median_sec'), 's')},"
        f"e2e:{fmt_metric(curr_tp.get('e2e_median_sec'), 's')},"
        f"overhead:{fmt_metric(curr_tp.get('overhead_rate_median_pct'), '%')}"
        f",measured:{fmt_metric(measured, 's')}"
        f",unmeasured_wait:{fmt_metric(unmeasured, 's')}"
    )


def throughput_stage_attribution(curr_tp):
    values = {
        "deploy": as_float(curr_tp.get("deploy_median_sec")),
        "work": as_float(curr_tp.get("work_median_sec")),
        "finalize": as_float(curr_tp.get("finalize_median_sec")),
    }
    e2e = as_float(curr_tp.get("e2e_median_sec"))
    missing = [f"{stage}_median_sec" for stage, value in values.items() if value is None]
    if e2e is None:
        missing.append("e2e_median_sec")
    if missing:
        return {
            "stage": "unmeasured",
            "target": MEASUREMENT_TARGET,
            "measurement_target": "missing:" + ",".join(missing),
        }

    measured = sum(values.values())
    values["unmeasured_wait"] = max(0.0, e2e - measured)
    largest = max(values.values())
    winners = [stage for stage, value in values.items() if value == largest]

    # A tie cannot support causal attribution. Keep the candidate actionable by
    # targeting the measurement producer and naming the ambiguous boundaries.
    if len(winners) != 1:
        return {
            "stage": "ambiguous",
            "target": MEASUREMENT_TARGET,
            "measurement_target": "tie:" + ",".join(winners),
        }

    stage = winners[0]
    if stage in STAGE_TARGETS:
        return {
            "stage": stage,
            "target": STAGE_TARGETS[stage],
            "measurement_target": f"{stage}_median_sec",
        }

    # Work duration belongs to the task/agent, not a single infrastructure
    # script. An E2E gap has no measured owner at all. Neither may be blamed on
    # finalize; route both to the measurement producer for finer instrumentation.
    metric = "work_median_sec" if stage == "work" else "unmeasured_wait"
    return {
        "stage": stage,
        "target": MEASUREMENT_TARGET,
        "measurement_target": metric,
    }


def throughput_attribution_summary(attribution):
    return (
        f"largest_stage={attribution['stage']} "
        f"target={attribution['target']} "
        f"measurement_target={attribution['measurement_target']}"
    )


def throughput_verify(kind):
    metric = "overhead_rate_median_pct" if kind == "throughput_overhead" else "e2e_median_sec"
    return (
        "python3 - <<'PY'\n"
        "import sys, yaml\n"
        # verify_commandは任意cwdで実行されるため台帳パスは絶対パスで埋め込む(INS-c929: 相対パスでFileNotFoundError)
        f"d=yaml.safe_load(open('{os.path.abspath(loop_path)}')) or {{}}\n"
        "s=(d.get('snapshots') or [{}])[-1]\n"
        "tp=((s.get('loops') or {}).get('throughput') or {})\n"
        f"v=tp.get('{metric}')\n"
        "sys.exit(0 if v not in (None, '', 'null') else 1)\n"
        "PY"
    )


def throughput_candidate(kind, priority, msg, attribution):
    return {
        "kind": kind,
        "target": attribution["target"],
        "verify": throughput_verify(kind),
        "priority": priority,
        "msg": msg,
    }


def latest_snapshot(data):
    snapshots = data.get("snapshots") if isinstance(data, dict) else None
    if isinstance(snapshots, list) and snapshots:
        last = snapshots[-1]
        if isinstance(last, dict):
            return last
    return data if isinstance(data, dict) else {}


def metric_pairs(cols):
    result = {}
    for field in cols[8:]:
        for token in field.split():
            if "=" in token:
                key, value = token.split("=", 1)
                result[key] = value
    return result


def throughput_ratchet(loop_data):
    snapshots = loop_data.get("snapshots") if isinstance(loop_data, dict) else []
    baseline = next((s for s in snapshots or [] if isinstance(s, dict) and s.get("generated_at") == BASELINE_GENERATED_AT), None)
    baseline_value = as_float((((baseline or {}).get("loops") or {}).get("throughput") or {}).get("e2e_median_sec"))
    baseline_ok = baseline_value == BASELINE_E2E_SEC
    excluded = {"na": 0, "negative": 0, "estimated_backfill": 0, "old_schema": 0, "duplicate_old_revision": 0}
    rows = []
    p = Path(gate_metrics_path)
    if p.is_file():
        for revision, raw in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines()):
            cols = raw.split("\t")
            if len(cols) < 3 or cols[2].strip().upper() != "CLEAR" or not cols[1].strip():
                continue
            rows.append((cols[1].strip(), cols[0].strip(), revision, metric_pairs(cols)))

    latest = {}
    for row in rows:
        cmd_id, ts, revision, _ = row
        previous = latest.get(cmd_id)
        if previous is not None:
            excluded["duplicate_old_revision"] += 1
        if previous is None or (ts, revision) > (previous[1], previous[2]):
            latest[cmd_id] = row

    valid = []
    stages = {"deploy": [], "work": [], "finalize": []}
    for _, ts, _, metrics in latest.values():
        # The timestamp-SSOT producer became canonical at this boundary. Older
        # CLEAR rows can contain numerics derived from the legacy schema.
        if ts < POST_TELEMETRY_START or "missing" not in metrics:
            excluded["old_schema"] += 1
            continue
        if metrics.get("estimated_backfill", "false").lower() in {"1", "true", "yes"}:
            excluded["estimated_backfill"] += 1
            continue
        values = {key: as_float(metrics.get(f"{key}_sec")) for key in ("deploy", "work", "finalize", "e2e")}
        if metrics.get("missing") != "none" or any(value is None for value in values.values()):
            excluded["na"] += 1
            continue
        if any(value < 0 for value in values.values()):
            excluded["negative"] += 1
            continue
        if values["e2e"] < max(values["deploy"], values["work"], values["finalize"]):
            excluded["negative"] += 1
            continue
        # build_clear_throughput_metric emits deploy=0 only when its resolved
        # issued_at and deployed_at events are identical; missing=none proves
        # both source events existed rather than being imputed.
        valid.append(values["e2e"])
        for key in stages:
            stages[key].append(values[key])

    median_e2e = statistics.median(valid) if valid else None
    ratio = BASELINE_E2E_SEC / median_e2e if median_e2e and median_e2e > 0 else None
    if not baseline_ok or len(valid) < RATCHET_MIN_SAMPLES:
        status = "WARMUP"
    elif median_e2e <= RATCHET_TARGET_SEC and ratio >= 2.0:
        status = "PASS"
    else:
        status = "FAIL"
    largest_stage = "na"
    if status == "FAIL":
        stage_medians = {key: statistics.median(values) for key, values in stages.items()}
        largest_stage = max(stage_medians, key=stage_medians.get)
    excluded_text = ",".join(f"{key}:{value}" for key, value in excluded.items())
    return (
        "THROUGHPUT_2X_RATCHET: "
        f"status={status} baseline_source=loop_ledger:{BASELINE_GENERATED_AT} "
        f"baseline_e2e_sec={BASELINE_E2E_SEC} target_e2e_sec={RATCHET_TARGET_SEC} "
        f"valid_samples={len(valid)} median_e2e_sec={median_e2e if median_e2e is not None else 'na'} "
        f"improvement_ratio={ratio if ratio is not None else 'na'} largest_stage={largest_stage} "
        f"excluded={excluded_text}"
    )


def build_candidates():
    candidates = []
    loop_data = load_yaml(loop_path)
    snapshots = loop_data.get("snapshots") if isinstance(loop_data, dict) else None
    current = latest_snapshot(loop_data)
    previous = snapshots[-2] if isinstance(snapshots, list) and len(snapshots) >= 2 and isinstance(snapshots[-2], dict) else None
    curr_tp = ((current.get("loops") or {}).get("throughput") or {}) if isinstance(current, dict) else {}
    prev_tp = ((previous.get("loops") or {}).get("throughput") or {}) if isinstance(previous, dict) else {}

    curr_overhead = as_float(curr_tp.get("overhead_rate_median_pct"))
    prev_overhead = as_float(prev_tp.get("overhead_rate_median_pct"))
    curr_e2e = as_float(curr_tp.get("e2e_median_sec"))
    prev_e2e = as_float(prev_tp.get("e2e_median_sec"))
    attribution = throughput_stage_attribution(curr_tp)
    attribution_summary = throughput_attribution_summary(attribution)
    if prev_overhead is not None and curr_overhead is not None:
        delta = round(curr_overhead - prev_overhead, 1)
        if delta >= OVERHEAD_WORSEN_THRESHOLD:
            stage_summary = throughput_stage_summary(curr_tp)
            verify = throughput_verify("throughput_overhead")
            candidates.append(throughput_candidate(
                "throughput_overhead",
                "high",
                (
                    "THROUGHPUT_FIX_KNOWN throughput_overhead: throughput overhead median worsened "
                    f"prev={prev_overhead}% curr={curr_overhead}% delta={delta}pp. "
                    f"{stage_summary}. "
                    f"{attribution_summary}. "
                    f"INSIGHT_FIX_KNOWN=1 target={attribution['target']} "
                    f"verify={verify!r} source=S1_loop_ledger"
                ),
                attribution,
            ))
    if prev_e2e is not None and curr_e2e is not None:
        delta = round(curr_e2e - prev_e2e, 1)
        if delta >= E2E_WORSEN_THRESHOLD:
            stage_summary = throughput_stage_summary(curr_tp)
            verify = throughput_verify("throughput_e2e")
            candidates.append(throughput_candidate(
                "throughput_e2e",
                "high",
                (
                    "THROUGHPUT_FIX_KNOWN throughput_e2e: throughput e2e median worsened "
                    f"prev={prev_e2e}s curr={curr_e2e}s delta={delta}s. "
                    f"{stage_summary}. "
                    f"{attribution_summary}. "
                    f"INSIGHT_FIX_KNOWN=1 target={attribution['target']} "
                    f"verify={verify!r} source=S1_loop_ledger"
                ),
                attribution,
            ))

    fp_data = load_yaml(fp_path)
    for item in fp_data.get("detectors") or []:
        if not isinstance(item, dict):
            continue
        detector = str(item.get("detector") or "")
        fp_rate = as_float(item.get("fp_rate"))
        fires = as_int(item.get("fires"))
        false_positive = as_int(item.get("false_positive"))
        if not detector or fp_rate is None:
            continue
        if fires < FP_FIRES_THRESHOLD or fp_rate < FP_RATE_THRESHOLD:
            continue
        target = target_from_detector(detector)
        verify = verify_from_detector(detector)
        candidates.append({
            "kind": "fp_rate",
            "target": target,
            "verify": verify,
            "priority": "high" if fp_rate >= 80 else "medium",
            "msg": (
                f"THROUGHPUT_FIX_KNOWN detector={detector}: FP rate over threshold "
                f"fp_rate={fp_rate}% false_positive={false_positive}/{fires}. "
                f"INSIGHT_FIX_KNOWN=1 target={target} verify='{verify}' source=S2_detector_fp_rate"
            ),
        })
    return candidates


def traversal_candidates():
    data = load_yaml(traversal_path)
    events = data.get("events") or []
    accepted, rejected, seen, zero_hop = [], 0, set(), []
    required_routes = {"preflight", "semantic_search", "causal_backlinks"}
    for event in events:
        if not isinstance(event, dict): rejected += 1; continue
        event_id = str(event.get("event_id") or "")
        route = str(event.get("route") or "")
        landing = str(event.get("landing_node") or "")
        adjacent = str(event.get("adjacent_node") or "")
        action = str(event.get("connected_action") or "")
        finding = str(event.get("finding") or "")
        origin = str(event.get("origin") or "")
        links = {str(x) for x in event.get("existing_links") or []}
        expected = f"[[{landing}]] -> [[{adjacent}]] -> [[{action}]]"
        valid = (event_id and event_id not in seen and route in required_routes and landing
                 and finding and origin == expected and adjacent and action
                 and landing in links and adjacent in links and action in links)
        if not valid: rejected += 1; continue
        seen.add(event_id); accepted.append(event)
        if int(event.get("hop_count") or 0) < 1: zero_hop.append(event)
    traversed = sum(int(e.get("hop_count") or 0) >= 1 for e in accepted)
    discovered = sum(bool(str(e.get("finding") or "").strip()) for e in accepted)
    connected = sum(bool(str(e.get("connected_action") or "").strip()) for e in accepted)
    total = len(accepted)
    print(f"TRAVERSAL_METRICS: accepted={total} rejected={rejected} duplicate={len(events)-len(seen)-rejected} traversal={traversed}/{total} discovery={discovered}/{total} action={connected}/{total}")
    if zero_hop:
        first = zero_hop[0]
        return [{"kind":"obsidian_zero_hop", "target":"scripts/throughput_scan.sh",
                 "verify":f"test -f {os.path.abspath(traversal_path)}", "priority":"high",
                 "msg":("THROUGHPUT_FIX_KNOWN obsidian_zero_hop: traversal入口止まり "
                        f"route={first['route']} landing={first['landing_node']} event_id={first['event_id']}. "
                        "INSIGHT_FIX_KNOWN=1 target=scripts/throughput_scan.sh source=obsidian_traversal") }]
    return []


loop_data_for_ratchet = load_yaml(loop_path)
print(throughput_ratchet(loop_data_for_ratchet))
pending_texts = pending_insight_texts(insights_path)
queued = 0
duplicates = 0
candidates = build_candidates() + traversal_candidates()
for candidate in candidates:
    msg = candidate["msg"]
    dedup_key = msg[:120]
    if any(dedup_key in existing or existing[:120] == dedup_key for existing in pending_texts):
        duplicates += 1
        print(f"THROUGHPUT_SCAN_DUPLICATE: {dedup_key}")
        continue
    if dry_run:
        queued += 1
        print(f"THROUGHPUT_SCAN_DRY_RUN: {msg}")
        continue
    env = os.environ.copy()
    env.update({
        "INSIGHT_FIX_KNOWN": "1",
        "INSIGHT_TARGET_FILE": candidate["target"],
        "INSIGHT_VERIFY_COMMAND": candidate["verify"],
        "INSIGHTS_FILE": insights_path,
    })
    proc = subprocess.run(
        ["bash", insight_script, msg, candidate["priority"], f"throughput_scan:{sanitize_source(candidate['kind'])}:{sanitize_source(candidate['target'])}"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=env,
        check=False,
    )
    output = proc.stdout.strip()
    if proc.returncode != 0:
        print(f"THROUGHPUT_SCAN_WARN: insight_write failed rc={proc.returncode} output={output}", file=sys.stderr)
        continue
    if output.startswith("SKIP:"):
        duplicates += 1
        print(f"THROUGHPUT_SCAN_DUPLICATE: {output}")
    else:
        queued += 1
        pending_texts.append(msg)
        print(f"THROUGHPUT_SCAN_QUEUED: {output} {msg[:160]}")

if not candidates:
    print("THROUGHPUT_SCAN_NONE: no throughput or FP degradation")
else:
    print(f"THROUGHPUT_SCAN_SUMMARY: candidates={len(candidates)} queued={queued} duplicates={duplicates}")
PY
