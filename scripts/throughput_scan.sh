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
DRY_RUN=0

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

python3 - "$LOOP_LEDGER" "$FP_LEDGER" "$INSIGHTS_FILE" "$INSIGHT_SCRIPT" "$DRY_RUN" <<'PY'
import os
import re
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except Exception as exc:
    print(f"THROUGHPUT_SCAN_ERROR: PyYAML required: {exc}", file=sys.stderr)
    sys.exit(2)

loop_path, fp_path, insights_path, insight_script, dry_run_raw = sys.argv[1:6]
dry_run = dry_run_raw == "1"

FP_RATE_THRESHOLD = float(os.environ.get("THROUGHPUT_SCAN_FP_RATE_THRESHOLD", "50"))
FP_FIRES_THRESHOLD = int(os.environ.get("THROUGHPUT_SCAN_FP_FIRES_THRESHOLD", "2"))
OVERHEAD_WORSEN_THRESHOLD = float(os.environ.get("THROUGHPUT_SCAN_OVERHEAD_WORSEN_THRESHOLD", "5"))
E2E_WORSEN_THRESHOLD = float(os.environ.get("THROUGHPUT_SCAN_E2E_WORSEN_THRESHOLD", "60"))


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
    return (
        "stage_medians="
        f"deploy:{fmt_metric(curr_tp.get('deploy_median_sec'), 's')},"
        f"work:{fmt_metric(curr_tp.get('work_median_sec'), 's')},"
        f"finalize:{fmt_metric(curr_tp.get('finalize_median_sec'), 's')},"
        f"e2e:{fmt_metric(curr_tp.get('e2e_median_sec'), 's')},"
        f"overhead:{fmt_metric(curr_tp.get('overhead_rate_median_pct'), '%')}"
    )


def throughput_verify(kind):
    metric = "overhead_rate_median_pct" if kind == "throughput_overhead" else "e2e_median_sec"
    return (
        "python3 - <<'PY'\n"
        "import sys, yaml\n"
        "d=yaml.safe_load(open('logs/loop_ledger.yaml')) or {}\n"
        "s=(d.get('snapshots') or [{}])[-1]\n"
        "tp=((s.get('loops') or {}).get('throughput') or {})\n"
        f"v=tp.get('{metric}')\n"
        "sys.exit(0 if v not in (None, '', 'null') else 1)\n"
        "PY"
    )


def throughput_candidate(kind, priority, msg):
    return {
        "kind": kind,
        "target": "scripts/throughput_scan.sh",
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
                    "INSIGHT_FIX_KNOWN=1 target=scripts/throughput_scan.sh "
                    f"verify={verify!r} source=S1_loop_ledger"
                ),
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
                    "INSIGHT_FIX_KNOWN=1 target=scripts/throughput_scan.sh "
                    f"verify={verify!r} source=S1_loop_ledger"
                ),
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


pending_texts = pending_insight_texts(insights_path)
queued = 0
duplicates = 0
candidates = build_candidates()
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
