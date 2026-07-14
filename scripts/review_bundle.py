#!/usr/bin/env python3
"""Generate and validate the SG7 completion bundle used by Gunshi and Karo."""
from __future__ import annotations
import argparse, fcntl, glob, hashlib, json, os, subprocess, sys
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

def find_command(root, cmd_id):
    paths = [root / "queue/shogun_to_karo.yaml", root / f"queue/reopened_cmds/{cmd_id}.yaml"]
    paths += [Path(p) for p in sorted(glob.glob(str(root / f"queue/archive/cmds/{cmd_id}_*.yaml")), reverse=True)]
    for path in paths:
        if path.is_file():
            item = command_from(load(path), cmd_id)
            if item is not None: return item, path
    raise ValueError(f"cmd spec not found: {cmd_id}")

def summary(command):
    ac = command.get("acceptance_criteria")
    if not isinstance(ac, (list, dict)) or not ac: raise ValueError("cmd spec acceptance_criteria is missing")
    scope = command.get("not_in_scope")
    if scope in (None, "", [], {}): scope = command.get("command")
    if scope in (None, "", [], {}): raise ValueError("cmd spec scope is missing")
    project = str(command.get("project") or "").strip()
    if not project: raise ValueError("cmd spec project is missing")
    return {"acceptance_criteria_count": len(ac), "scope": scope, "project": project}

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
    return review

def generate(args):
    root = Path(args.root).resolve(); report = Path(args.report)
    if not report.is_absolute(): report = root / report
    report = report.resolve(); reports = (root / "queue/reports").resolve()
    if report.parent != reports or not report.is_file(): raise ValueError("report must be an existing direct child of queue/reports")
    if str(load(report).get("parent_cmd") or "") != args.cmd: raise ValueError("report parent_cmd contradicts requested cmd")
    command, source = find_command(root, args.cmd); verdict = args.verdict.upper()
    review = {"cmd_id": args.cmd, "verdict": verdict, "reviewer": "gunshi", "reviewed_at": datetime.now().astimezone().isoformat(timespec="seconds"), "report": str(report.relative_to(root)), "report_fingerprint": hashlib.sha256(report.read_bytes()).hexdigest(), "cmd_spec_source": str(source.relative_to(root)), "cmd_spec_summary": summary(command)}
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

def build_parser():
    p = argparse.ArgumentParser(); p.add_argument("--root", default=str(Path(__file__).resolve().parents[1])); subs = p.add_subparsers(dest="action", required=True)
    g = subs.add_parser("generate"); g.add_argument("--cmd", required=True); g.add_argument("--verdict", required=True, choices=("APPROVE", "FAIL")); g.add_argument("--report", required=True); g.add_argument("--fail-reason"); g.set_defaults(func=generate)
    n = subs.add_parser("notify"); n.add_argument("--cmd", required=True); n.add_argument("--bundle", required=True); n.set_defaults(func=notify)
    c = subs.add_parser("consume"); c.add_argument("--cmd", required=True); c.add_argument("--bundle", required=True); c.add_argument("--expect-verdict", choices=("APPROVE", "FAIL")); c.set_defaults(func=consume); return p

def main():
    args = build_parser().parse_args()
    try: return args.func(args)
    except (OSError, ValueError, subprocess.CalledProcessError, yaml.YAMLError) as exc:
        print(f"BLOCK: review bundle: {exc}", file=sys.stderr); return 2

if __name__ == "__main__": raise SystemExit(main())
