#!/usr/bin/env python3
"""Generate and validate the SG7 completion bundle used by Gunshi and Karo."""
from __future__ import annotations
import argparse, fcntl, glob, hashlib, json, os, re, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path
import yaml

def load(path):
    with Path(path).open(encoding="utf-8") as handle: return yaml.safe_load(handle) or {}

def command_from(data, cmd_id):
    commands = data.get("commands", data)
    if isinstance(commands, dict):
        value = commands.get(cmd_id); return value if isinstance(value, dict) else None
    if isinstance(commands, list):
        return next((x for x in commands if isinstance(x, dict) and str(x.get("id")) == cmd_id), None)

def find_command(root, cmd_id, report=None, report_path=None):
    paths = [root / "queue/shogun_to_karo.yaml", root / f"queue/reopened_cmds/{cmd_id}.yaml"]
    paths += [Path(p) for p in sorted(glob.glob(str(root / f"queue/archive/cmds/{cmd_id}_*.yaml")), reverse=True)]
    for path in paths:
        if path.is_file():
            item = command_from(load(path), cmd_id)
            if item is not None: return item, path
    # Karo-direct commands intentionally have no Shogun command record.  Their
    # assigned task is the contract; never infer that contract from report
    # output or from another worker's task.
    if cmd_id.startswith("cmd_karo_") and isinstance(report, dict) and report_path is not None:
        if str(report.get("status") or "") != "completed" or str(report.get("verdict") or "").upper() != "PASS":
            raise ValueError("karo-direct fallback requires completed/PASS report")
        worker = str(report.get("worker_id") or "").strip()
        if not re.fullmatch(r"[a-z][a-z0-9_-]*", worker):
            raise ValueError("karo-direct report worker_id is missing or invalid")
        task_path = root / f"queue/tasks/{worker}.yaml"
        if not task_path.is_file():
            raise ValueError(f"karo-direct worker task is missing: {worker}")
        task_doc = load(task_path)
        task = task_doc.get("task", task_doc) if isinstance(task_doc, dict) else None
        if not isinstance(task, dict) or str(task.get("parent_cmd") or "") != cmd_id:
            raise ValueError(f"karo-direct worker task parent_cmd mismatch: {worker}")
        purpose = str(task.get("purpose") or "").strip()
        criteria = task.get("acceptance_criteria")
        project = str(task.get("project") or "").strip()
        if not purpose or not isinstance(criteria, (list, dict)) or not criteria or not project:
            raise ValueError(f"karo-direct worker task contract is incomplete: {worker}")
        return {
            "acceptance_criteria": criteria,
            "command": purpose,
            "project": project,
        }, task_path
    raise ValueError(f"cmd spec not found: {cmd_id}")

def summary(command):
    ac = command.get("acceptance_criteria")
    if not isinstance(ac, (list, dict)) or not ac: raise ValueError("cmd spec acceptance_criteria is missing")
    scope = command.get("not_in_scope")
    if scope in (None, "", [], {}): scope = command.get("scope")
    # Current numbered commands use target_path as their executable scope
    # boundary.  Requiring the optional not_in_scope prose here made valid
    # commands fail only after implementation, at SG7 generation time.
    if scope in (None, "", [], {}): scope = command.get("target_path")
    if scope in (None, "", [], {}): scope = command.get("command")
    if scope in (None, "", [], {}): raise ValueError("cmd spec scope is missing")
    project = str(command.get("project") or "").strip()
    if not project: raise ValueError("cmd spec project is missing")
    return {"acceptance_criteria_count": len(ac), "scope": scope, "project": project}

def dashboard_line(report, cmd_id):
    result = report.get("result") if isinstance(report.get("result"), dict) else {}
    text = str(result.get("summary") or report.get("summary") or "").strip()
    if not text: raise ValueError("report result.summary is missing for dashboard_line")
    return f"- **{cmd_id}**: 完了。{text}"

def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True); lock_path = path.with_suffix(path.suffix + ".lock")
    with lock_path.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX); temp = path.with_name(f".{path.name}.tmp.{os.getpid()}")
        try:
            temp.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            os.replace(temp, path)
        finally:
            if temp.exists(): temp.unlink()

def validate(bundle, expected_cmd=None, expected_verdict=None):
    if not isinstance(bundle, dict) or not isinstance(bundle.get("review"), dict): raise ValueError("review bundle root/review is missing")
    review = bundle["review"]; cmd_id = str(review.get("cmd_id") or ""); verdict = str(review.get("verdict") or "").upper()
    if expected_cmd and cmd_id != expected_cmd: raise ValueError(f"bundle cmd mismatch: expected={expected_cmd} actual={cmd_id}")
    if verdict not in {"APPROVE", "FAIL"}: raise ValueError(f"invalid bundle verdict: {verdict}")
    if expected_verdict and verdict != expected_verdict.upper(): raise ValueError(f"bundle verdict mismatch: expected={expected_verdict} actual={verdict}")
    spec = review.get("cmd_spec_summary")
    if not isinstance(spec, dict): raise ValueError("cmd_spec_summary is missing")
    count = spec.get("acceptance_criteria_count")
    if not isinstance(count, int) or isinstance(count, bool) or count < 1: raise ValueError("cmd_spec_summary.acceptance_criteria_count must be a positive integer")
    if spec.get("scope") in (None, "", [], {}): raise ValueError("cmd_spec_summary.scope is missing")
    if not str(spec.get("project") or "").strip(): raise ValueError("cmd_spec_summary.project is missing")
    if verdict == "APPROVE" and "karo_attention" in review: raise ValueError("APPROVE bundle must omit karo_attention")
    if verdict == "FAIL" and not str(review.get("karo_attention") or "").strip(): raise ValueError("FAIL bundle requires karo_attention")
    line = str(review.get("dashboard_line") or "").strip()
    if not line: raise ValueError("dashboard_line is missing")
    if not line.startswith(f"- **{cmd_id}**:"): raise ValueError("dashboard_line contradicts cmd_id")
    return review

def generate(args):
    root = Path(args.root).resolve(); report_arg = Path(args.report)
    if not report_arg.is_absolute(): report_arg = root / report_arg
    report_arg = Path(os.path.abspath(report_arg)); report = report_arg.resolve()
    reports = (root / "queue/reports").resolve(); archived = (root / "queue/archive/reports").resolve()
    current_direct = report_arg.parent == reports and report.parent == reports
    archived_direct = args.allow_archived and report.parent == archived
    if not (current_direct or archived_direct) or not report.is_file():
        raise ValueError("report must be a current direct report (or archived with --allow-archived)")
    report_data = load(report)
    if str(report_data.get("parent_cmd") or "") != args.cmd: raise ValueError("report parent_cmd contradicts requested cmd")
    report_ref = report_arg if report_arg.is_relative_to(root) else report
    command, source = find_command(root, args.cmd, report_data, report_ref); verdict = args.verdict.upper()
    review = {"cmd_id": args.cmd, "verdict": verdict, "reviewer": "gunshi", "reviewed_at": datetime.now().astimezone().isoformat(timespec="seconds"), "report": str(report_ref.relative_to(root)), "report_fingerprint": hashlib.sha256(report.read_bytes()).hexdigest(), "cmd_spec_source": str(source.relative_to(root)), "cmd_spec_summary": summary(command), "dashboard_line": dashboard_line(report_data, args.cmd)}
    if verdict == "FAIL":
        if not args.fail_reason: raise ValueError("FAIL requires --fail-reason")
        review["karo_attention"] = args.fail_reason
    bundle = {"review": review}; validate(bundle, args.cmd, verdict)
    path = root / f"queue/gates/{args.cmd}/sg7_bundle.json"; atomic_json(path, bundle); relative = str(path.relative_to(root)); spec = review["cmd_spec_summary"]
    print(relative); print(json.dumps(spec, ensure_ascii=False, sort_keys=True)); return 0

def notify(args):
    root = Path(args.root).resolve(); path = Path(args.bundle)
    if not path.is_absolute(): path = root / path
    path = path.resolve(); gates = (root / "queue/gates").resolve()
    if gates not in path.parents or path.name != "sg7_bundle.json": raise ValueError("bundle must be queue/gates/<cmd>/sg7_bundle.json")
    review = validate(load(path), args.cmd, "APPROVE")
    report = (root / review["report"]).resolve(); reports = (root / "queue/reports").resolve()
    if report.parent != reports or not report.is_file(): raise ValueError("bundle report is missing or outside queue/reports")
    if hashlib.sha256(report.read_bytes()).hexdigest() != review.get("report_fingerprint"): raise ValueError("bundle report fingerprint is stale")
    # Step 1.5 observations and Step 2 review_log happen before the skill calls
    # formal review_approval.  This final boundary merely verifies that exact
    # marker; it never creates approvals itself.
    approval_check = f'''source "{root / 'scripts/lib/review_approval.sh'}"
PROJECT_ROOT="{root}" review_two_phase_ready_gunshi "{args.cmd}" "{report}"
'''
    subprocess.run(["bash", "-c", approval_check], cwd=root, check=True)
    spec = review["cmd_spec_summary"]; relative = str(path.relative_to(root))
    message = f"{args.cmd} SG7 bundle. verdict: LGTM. report: {review['report']} bundle: {relative} cmd_spec_summary: acceptance_criteria_count={spec['acceptance_criteria_count']}, scope={json.dumps(spec['scope'], ensure_ascii=False, separators=(',', ':'))}, project={spec['project']}"
    subprocess.run(["bash", str(root / "scripts/inbox_write.sh"), "karo", message, "report_review_result", "gunshi"], cwd=root, check=True)
    print(message); return 0

def consume(args):
    root = Path(args.root).resolve(); path = Path(args.bundle)
    if not path.is_absolute(): path = root / path
    path = path.resolve(); gates = (root / "queue/gates").resolve()
    if gates not in path.parents or path.name != "sg7_bundle.json": raise ValueError("bundle must be queue/gates/<cmd>/sg7_bundle.json")
    review = validate(load(path), args.cmd, args.expect_verdict); print(json.dumps(review["cmd_spec_summary"], ensure_ascii=False, sort_keys=True)); return 0

def _batch_precheck(root, item):
    started = time.monotonic()
    na = item.get("precheck_na")
    if na is not None:
        if not isinstance(na, dict) or not str(na.get("reason") or "").strip() or not str(na.get("evidence") or "").strip():
            raise ValueError("precheck_na requires non-empty reason and evidence")
        return {"status": "N/A", "reason": str(na["reason"]), "evidence": str(na["evidence"]), "duration_ms": round((time.monotonic() - started) * 1000)}
    report = str(item["report"])
    proc = subprocess.run(
        ["bash", str(root / "scripts/gates/gate_gunshi_report_precheck.sh"), report],
        cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    evidence = proc.stdout.strip()
    if proc.returncode != 0:
        raise ValueError(f"precheck failed cmd={item['cmd']}: {evidence[-500:]}")
    return {"status": "PASS", "reason": "all checks passed", "evidence": evidence, "duration_ms": round((time.monotonic() - started) * 1000)}

def _batch_generate(root, item, precheck):
    argv = argparse.Namespace(root=str(root), cmd=str(item["cmd"]), verdict=str(item["verdict"]).upper(),
                              report=str(item["report"]), fail_reason=item.get("fail_reason"), allow_archived=False)
    generate(argv)
    path = root / f"queue/gates/{item['cmd']}/sg7_bundle.json"
    bundle = load(path); bundle["review"]["precheck"] = precheck; atomic_json(path, bundle)
    return path

def batch(args):
    root = Path(args.root).resolve(); manifest = load(args.manifest)
    items = manifest.get("reviews") if isinstance(manifest, dict) else manifest
    if not isinstance(items, list) or not items or len(items) > args.max_workers:
        raise ValueError(f"manifest reviews must contain 1..{args.max_workers} items")
    required = {"cmd", "report", "verdict", "review_entry"}
    for item in items:
        if not isinstance(item, dict) or not required.issubset(item): raise ValueError("each review requires cmd/report/verdict/review_entry")
        if str(item["verdict"]).upper() not in {"APPROVE", "FAIL"}: raise ValueError("batch verdict must be APPROVE or FAIL")
        if not isinstance(item["review_entry"], dict): raise ValueError("review_entry must be a mapping")
    cmds = [str(x["cmd"]) for x in items]; reports = [str(x["report"]) for x in items]
    if len(set(cmds)) != len(cmds) or len(set(reports)) != len(reports): raise ValueError("batch cmd/report values must be unique")

    wall_started = time.monotonic()
    with ThreadPoolExecutor(max_workers=min(args.max_workers, len(items))) as pool:
        prechecks = list(pool.map(lambda x: _batch_precheck(root, x), items))
    # No durable review/log/inbox mutation occurs until every precheck passes.
    with ThreadPoolExecutor(max_workers=min(args.max_workers, len(items))) as pool:
        paths = list(pool.map(lambda pair: _batch_generate(root, pair[0], pair[1]), zip(items, prechecks)))
    entries = yaml.safe_dump([x["review_entry"] for x in items], allow_unicode=True, sort_keys=False)
    subprocess.run(["bash", str(root / "scripts/gunshi_log_append.sh"), "--batch"], cwd=root, input=entries, text=True, check=True)

    def finish(pair):
        item, path = pair; verdict = str(item["verdict"]).upper()
        if verdict == "APPROVE":
            subprocess.run(["bash", str(root / "scripts/review_approval.sh"), str(item["cmd"]), "gunshi", "LGTM", str(item["report"])], cwd=root, check=True)
            notify(argparse.Namespace(root=str(root), cmd=str(item["cmd"]), bundle=str(path)))
        else:
            message = f"{item['cmd']} review FAIL. report: {item['report']} reason: {item.get('fail_reason') or 'quality evidence mismatch'}"
            subprocess.run(["bash", str(root / "scripts/inbox_write.sh"), "karo", message, "report_review_result", "gunshi"], cwd=root, check=True)
    with ThreadPoolExecutor(max_workers=min(args.max_workers, len(items))) as pool:
        list(pool.map(finish, zip(items, paths)))
    durations = [x["duration_ms"] for x in prechecks]
    result = {"total": len(items), "fail": 0, "skip": 0, "wall_ms": round((time.monotonic() - wall_started) * 1000), "p95_report_ms": max(durations)}
    print(json.dumps(result, ensure_ascii=False, sort_keys=True)); return 0

def build_parser():
    p = argparse.ArgumentParser(); p.add_argument("--root", default=str(Path(__file__).resolve().parents[1])); subs = p.add_subparsers(dest="action", required=True)
    g = subs.add_parser("generate"); g.add_argument("--cmd", required=True); g.add_argument("--verdict", required=True, choices=("APPROVE", "FAIL")); g.add_argument("--report", required=True); g.add_argument("--fail-reason"); g.add_argument("--allow-archived", action="store_true"); g.set_defaults(func=generate)
    n = subs.add_parser("notify"); n.add_argument("--cmd", required=True); n.add_argument("--bundle", required=True); n.set_defaults(func=notify)
    c = subs.add_parser("consume"); c.add_argument("--cmd", required=True); c.add_argument("--bundle", required=True); c.add_argument("--expect-verdict", choices=("APPROVE", "FAIL")); c.set_defaults(func=consume)
    b = subs.add_parser("batch"); b.add_argument("--manifest", required=True); b.add_argument("--max-workers", type=int, default=5); b.set_defaults(func=batch)
    return p

def main():
    args = build_parser().parse_args()
    try: return args.func(args)
    except (OSError, ValueError, subprocess.CalledProcessError, yaml.YAMLError) as exc:
        print(f"BLOCK: review bundle: {exc}", file=sys.stderr); return 2

if __name__ == "__main__": raise SystemExit(main())
