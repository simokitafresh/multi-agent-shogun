#!/usr/bin/env python3
"""Generate and validate the SG7 completion bundle used by Gunshi and Karo."""
from __future__ import annotations
import argparse, fcntl, glob, hashlib, json, os, subprocess, sys, time
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

def _snapshot_command(root, report, cmd_id):
    snapshot = report.get("task_contract_snapshot") if isinstance(report, dict) else None
    if not isinstance(snapshot, dict):
        raise ValueError("immutable task contract snapshot is missing")
    report_task = str(report.get("task_id") or "")
    expected = {
        "parent_cmd": cmd_id,
        "task_id": report_task,
        "ac_fingerprint": str(report.get("ac_version_read") or ""),
    }
    for key, value in expected.items():
        if not value or str(snapshot.get(key) or "") != value:
            raise ValueError(f"immutable task contract identity mismatch: {key}")
    issued = str(snapshot.get("issued_cmd_id") or "")
    if issued and issued != cmd_id:
        raise ValueError("immutable task contract identity mismatch: issued_cmd_id")
    purpose = str(snapshot.get("purpose") or "").strip()
    criteria = snapshot.get("acceptance_criteria")
    project = str(snapshot.get("project") or "").strip()
    if not purpose or not isinstance(criteria, (list, dict)) or not criteria or not project:
        raise ValueError("immutable task contract snapshot is incomplete")
    worker = str(report.get("worker_id") or "").strip()
    if not worker or "/" in worker or worker in {".", ".."}:
        raise ValueError("immutable task contract identity mismatch: worker_id")
    task_path = root / f"queue/tasks/{worker}.yaml"
    task = load(task_path).get("task") if task_path.is_file() else None
    if not isinstance(task, dict):
        raise ValueError("immutable task contract task snapshot is missing")
    identities = {
        "task_id": (report_task, task.get("task_id")),
        "parent_cmd": (cmd_id, task.get("parent_cmd")),
        "ac_version": (str(report.get("ac_version_read") or ""), task.get("ac_version")),
        "report_id": (str(report.get("report_id") or ""), task.get("report_id")),
    }
    for key, (expected_value, actual_value) in identities.items():
        if not expected_value or str(actual_value or "") != expected_value:
            raise ValueError(f"immutable task/report identity mismatch: {key}")
    return {"acceptance_criteria": criteria, "command": purpose, "project": project}, task_path

# Commands the system generates for itself never pass through cmd_save, so they
# have no Shogun spec by construction.  Their deploy-time immutable
# task_contract_snapshot is the contract instead.  This is an allowlist, not a
# relaxation: any other spec-less cmd_id (notably a hand-written one that
# bypassed cmd_save) still fails closed below.
#   cmd_karo_*            karo-direct deployment
#   cmd_reflux_promotion_ ninja_monitor's promotion reflux auto-deployment
SPEC_LESS_AUTOGEN_PREFIXES = ("cmd_karo_", "cmd_reflux_")


def find_command(root, cmd_id, report=None, report_path=None):
    paths = [root / "queue/shogun_to_karo.yaml", root / f"queue/reopened_cmds/{cmd_id}.yaml"]
    paths += [Path(p) for p in sorted(glob.glob(str(root / f"queue/archive/cmds/{cmd_id}_*.yaml")), reverse=True)]
    for path in paths:
        if path.is_file():
            item = command_from(load(path), cmd_id)
            if item is not None: return item, path
    # Auto-generated commands intentionally have no Shogun command record.
    # Their immutable deploy-generation snapshot is the contract; the live
    # worker task may already belong to a later assignment.
    if cmd_id.startswith(SPEC_LESS_AUTOGEN_PREFIXES) and isinstance(report, dict) and report_path is not None:
        if str(report.get("status") or "") != "completed" or str(report.get("verdict") or "").upper() != "PASS":
            raise ValueError("autogen spec fallback requires completed/PASS report")
        return _snapshot_command(root, report, cmd_id)
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

def _resolve_report(root, report_ref, *, allow_archived=False):
    """Resolve a direct report while preserving the live/archive boundary."""
    report_arg = Path(report_ref)
    if not report_arg.is_absolute():
        report_arg = root / report_arg
    report_arg = Path(os.path.abspath(report_arg))
    report = report_arg.resolve()
    reports = (root / "queue/reports").resolve()
    archived = (root / "queue/archive/reports").resolve()
    current_direct = report_arg.parent == reports and report.parent == reports
    archived_direct = allow_archived and report_arg.parent == archived and report.parent == archived
    if not (current_direct or archived_direct) or not report.is_file():
        raise ValueError("report must be a current direct report (or archived with --allow-archived)")
    return report_arg, report

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

# hook_failures.count records how many times a hook fired; it says nothing about
# whether those failures are still open.  Judging on the count alone kept fully
# resolved work (kagemaru B27, hayate divergent-detector) from ever reaching
# APPROVE.  The judgement axis is therefore the *state* of the failures, proven
# by the four-step evidence those workers already produced voluntarily:
# cause / independent verification / bypass record / post-commit verification.
# The evidence lives inside the existing `details` field (no new report field,
# LG032): a plain string keeps the legacy "unresolved" meaning and stays blocked.
_HOOK_RESOLUTION_STEPS = ("cause", "independent_verification", "bypass_record", "post_verification")
# (d) is not "everything passes" but "nothing got worse": a full re-run PASS
# (kagemaru: 66/66) and an identical-failure-set proof (hayate: no new FAIL) are
# both valid, and nothing else is.
# hanzo's B28 supplies the third and decisive case: (d) can legitimately *fail*.
# He measured after the merged commit, found two new regressions, and reported
# "the bypass does not hold" instead of hiding it; the cause was fixed by its
# owner and his re-measurement on the new HEAD then held.  So `regression_detected`
# is a first-class declarable state — it blocks APPROVE while naming the way out,
# because a state that cannot be declared honestly has no exit and simply stalls.
_HOOK_POST_RESULTS = ("all_pass", "no_new_failure", "regression_detected")
_HOOK_POST_BLOCKING = {"regression_detected"}
# (d) re-measurement answers "what is true now", not "does the old number repeat"
# — hanzo's 02:04 count of 3 would have been wrong by the time he reported.  The
# measured HEAD pins the answer to a revision.
_HOOK_HEAD_KEY = "post_verification_head"

def _require_hook_failures_resolved(hook_failures):
    details = hook_failures.get("details")
    if not isinstance(details, dict):
        raise ValueError(
            "APPROVE forbidden while hook failures remain: hook_failures.details must be a mapping with "
            + "/".join(_HOOK_RESOLUTION_STEPS) + " plus post_verification_result"
        )
    missing = [step for step in _HOOK_RESOLUTION_STEPS if not str(details.get(step) or "").strip()]
    if missing:
        raise ValueError(f"APPROVE forbidden while hook failures remain: resolution evidence missing: {','.join(missing)}")
    outcome = str(details.get("post_verification_result") or "").strip()
    if outcome not in _HOOK_POST_RESULTS:
        raise ValueError(
            "APPROVE forbidden while hook failures remain: post_verification_result must be one of "
            + "/".join(_HOOK_POST_RESULTS)
        )
    if outcome in _HOOK_POST_BLOCKING:
        raise ValueError(
            "APPROVE forbidden while hook failures remain: post_verification_result=regression_detected. "
            "Fix the cause, re-measure on the new HEAD, then update post_verification/"
            + _HOOK_HEAD_KEY + " and re-request review"
        )
    head = str(details.get(_HOOK_HEAD_KEY) or "").strip()
    if len(head) < 7 or len(head) > 40 or any(c not in "0123456789abcdefABCDEF" for c in head):
        raise ValueError(
            "APPROVE forbidden while hook failures remain: " + _HOOK_HEAD_KEY
            + " must be the 7-40 char commit hash the post verification was measured on"
        )

def generate(args):
    root = Path(args.root).resolve()
    report_arg, report = _resolve_report(root, args.report, allow_archived=args.allow_archived)
    report_data = load(report)
    if str(report_data.get("parent_cmd") or "") != args.cmd: raise ValueError("report parent_cmd contradicts requested cmd")
    report_ref = report_arg if report_arg.is_relative_to(root) else report
    command, source = find_command(root, args.cmd, report_data, report_ref); verdict = args.verdict.upper()
    if verdict == "APPROVE":
        if str(report_data.get("status") or "") != "completed" or str(report_data.get("verdict") or "").upper() != "PASS":
            raise ValueError("APPROVE requires completed/PASS report")
        hook_failures = report_data.get("hook_failures")
        if isinstance(hook_failures, dict) and int(hook_failures.get("count") or 0) != 0:
            _require_hook_failures_resolved(hook_failures)
        checks = report_data.get("binary_checks")
        # yaml.safe_load coerces bare yes/no to booleans; treat them as equivalent
        results = [("yes" if item.get("result") is True else "no" if item.get("result") is False else str(item.get("result") or "").lower()) for group in (checks or {}).values() if isinstance(group, list) for item in group if isinstance(item, dict)] if isinstance(checks, dict) else []
        if not results or any(result != "yes" for result in results):
            raise ValueError("APPROVE requires all binary checks resolved yes")
    review = {"cmd_id": args.cmd, "verdict": verdict, "reviewer": "gunshi", "reviewed_at": datetime.now().astimezone().isoformat(timespec="seconds"), "report": str(report_ref.relative_to(root)), "report_fingerprint": hashlib.sha256(report.read_bytes()).hexdigest(), "cmd_spec_source": str(source.relative_to(root)), "cmd_spec_summary": summary(command), "dashboard_line": dashboard_line(report_data, args.cmd)}
    if verdict == "FAIL":
        if not args.fail_reason: raise ValueError("FAIL requires --fail-reason")
        review["karo_attention"] = args.fail_reason
    bundle = {"review": review}; validate(bundle, args.cmd, verdict)
    path = root / f"queue/gates/{args.cmd}/sg7_bundle.json"; atomic_json(path, bundle); relative = str(path.relative_to(root)); spec = review["cmd_spec_summary"]
    print(relative); print(json.dumps(spec, ensure_ascii=False, sort_keys=True)); return 0

def notify(args):
    started = time.monotonic()
    root = Path(args.root).resolve(); path = Path(args.bundle)
    if not path.is_absolute(): path = root / path
    path = path.resolve(); gates = (root / "queue/gates").resolve()
    if gates not in path.parents or path.name != "sg7_bundle.json": raise ValueError("bundle must be queue/gates/<cmd>/sg7_bundle.json")
    review = validate(load(path), args.cmd, "APPROVE")
    report_ref = str(review["report"])
    allow_archived = Path(report_ref).parent == Path("queue/archive/reports")
    _, report = _resolve_report(root, report_ref, allow_archived=allow_archived)
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
    _emit_self_retro(root, "gunshi_review_bundle", args.cmd, round((time.monotonic()-started)*1000), "review_notify")
    print(message); return 0

def _emit_self_retro(root, endpoint, cmd_id, wall_ms, cause_class):
    script = root / "scripts/lib/defense_overhead_writer.sh"
    payload = f'''source "{script}"
self_retro_write_async {endpoint} {cmd_id} {wall_ms} '{{"review_bundle":{wall_ms}}}' {cause_class} "review bundle generated and delivered" "reduce dominant review phase while preserving SG7 validation" "delivery succeeds and duplicate event count is 0" "[[review_bundle]] -> [[review_delivery]] -> [[fix_known]]"
'''
    subprocess.run(["bash", "-c", payload], cwd=root, check=False)
    subprocess.Popen(
        ["bash", "-c", f'''source "{root / 'scripts/lib/retro_pane_prompt.sh'}"
retro_pane_prompt_async "{root}" gunshi "review_bundle:{cmd_id}" review_bundle
wait
'''], cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )

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
