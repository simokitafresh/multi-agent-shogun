#!/usr/bin/env python3
"""Generate and validate the SG7 completion bundle used by Gunshi and Karo."""
from __future__ import annotations
import argparse, fcntl, glob, hashlib, json, os, subprocess, sys, time
import re
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime
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

def _report_identity(report, snapshot):
    """Read the immutable report-generation identity, if the deployer supplied it."""
    nested = snapshot.get("report_identity") if isinstance(snapshot.get("report_identity"), dict) else {}
    root = report.get("report_identity") if isinstance(report.get("report_identity"), dict) else {}
    def value(source, *names):
        for name in names:
            if str(source.get(name) or "").strip():
                return str(source[name]).strip()
        return ""
    return {
        "report_id": (value(snapshot, "report_id") or value(nested, "report_id"), value(report, "report_id") or value(root, "report_id")),
        "version": (value(snapshot, "report_identity_version", "identity_version") or value(nested, "report_identity_version", "identity_version"), value(report, "report_identity_version", "identity_version") or value(root, "report_identity_version", "identity_version")),
        "fingerprint": (value(snapshot, "report_fingerprint", "report_generation_fingerprint", "identity_fingerprint", "fingerprint") or value(nested, "report_fingerprint", "report_generation_fingerprint", "identity_fingerprint", "fingerprint"), value(report, "report_fingerprint", "report_generation_fingerprint", "identity_fingerprint", "fingerprint") or value(root, "report_fingerprint", "report_generation_fingerprint", "identity_fingerprint", "fingerprint")),
    }


def _receipt_generation_matches(root, report_path, report):
    """Verify a redeployed worker's report against its durable inbox receipt."""
    report_path = Path(report_path).resolve()
    try:
        report_ref = str(report_path.relative_to(Path(root).resolve()))
    except ValueError:
        return False
    report_id = str(report.get("report_id") or "").strip()
    version = str(report.get("report_identity_version") or "").strip()
    if not report_id or not version or not report_path.is_file():
        return False
    fingerprint = hashlib.sha256(report_path.read_bytes()).hexdigest()
    candidates = [Path(root) / "queue/inbox/karo.yaml"]
    timestamp = str(report.get("timestamp") or "")
    day = re.sub(r"[^0-9]", "", timestamp[:10])
    if len(day) == 8:
        candidates.append(Path(root) / f"archive/inbox/karo_{day}.yaml")
    # 2026-08-26: 報告timestampがUTC('...Z')だと日付が1日ずれ、JST日付で命名される
    # archive/inbox/karo_YYYYMMDD.yaml と一致せず receipt を見失う(batch6r saizo実証:
    # ts=2026-08-25T16:43:53Z → karo_20260825 を探すが receipt は karo_20260826 にあった)。
    # 受領証は archive 全日付から探す(新しい順)。fingerprint/report_id/path の完全一致が要るので緩和ではない。
    for archived in sorted((Path(root) / "archive/inbox").glob("karo_*.yaml"), reverse=True):
        if archived not in candidates:
            candidates.append(archived)
    for receipt_path in candidates:
        if not receipt_path.is_file():
            continue
        payload = load(receipt_path)
        messages = payload.get("messages", payload) if isinstance(payload, dict) else payload
        if not isinstance(messages, list):
            continue
        for message in messages:
            if not isinstance(message, dict):
                continue
            if (
                str(message.get("report_id") or "") == report_id
                and str(message.get("report_identity_version") or "") == version
                and str(message.get("report_fingerprint") or "") == fingerprint
                and str(message.get("report_path") or "") == report_ref
                and str(message.get("parent_cmd") or "") == str(report.get("parent_cmd") or "")
                and str(message.get("task_id") or "") == str(report.get("task_id") or "")
            ):
                return True
    return False


def _snapshot_command(root, report, cmd_id, report_path=None):
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
    # A terminal-idle worker may already carry a later assignment.  The old
    # report remains valid only when its deploy-time report identity is
    # self-consistent; a same-generation mismatch remains fail-closed.
    core_matches = (
        report_task == str(task.get("task_id") or "")
        and cmd_id == str(task.get("parent_cmd") or "")
        and str(report.get("ac_version_read") or "") == str(task.get("ac_version") or "")
    )
    if core_matches:
        for key, (expected_value, actual_value) in identities.items():
            if not expected_value or str(actual_value or "") != expected_value:
                raise ValueError(f"immutable task/report identity mismatch: {key}")
    else:
        identity = _report_identity(report, snapshot)
        embedded_identity_matches = all(
            expected and actual and expected == actual for expected, actual in identity.values()
        )
        receipt_identity_matches = bool(
            report_path is not None and _receipt_generation_matches(root, report_path, report)
        )
        if not (embedded_identity_matches or receipt_identity_matches):
            raise ValueError("immutable report-generation identity missing or mismatched")
    return {"acceptance_criteria": criteria, "command": purpose, "project": project}, task_path

# Commands the system generates for itself never pass through cmd_save, so they
# have no Shogun spec by construction.  Their deploy-time immutable
# task_contract_snapshot is the contract instead.  This is an allowlist, not a
# relaxation: any other spec-less cmd_id (notably a hand-written one that
# bypassed cmd_save) still fails closed below.
#   cmd_karo_*            karo-direct deployment
#   cmd_reflux_promotion_ ninja_monitor's promotion reflux auto-deployment
SPEC_LESS_AUTOGEN_PREFIXES = ("cmd_karo_", "cmd_reflux_", "cmd_shogun_")
_APPROVE_REPORT_STATES = {("completed", "PASS"), ("completed", "PASS_NO_IMPROVEMENT")}


def _saved_command(root, cmd_id):
    paths = [root / "queue/shogun_to_karo.yaml", root / f"queue/reopened_cmds/{cmd_id}.yaml"]
    paths += [Path(p) for p in sorted(glob.glob(str(root / f"queue/archive/cmds/{cmd_id}_*.yaml")), reverse=True)]
    for path in paths:
        if path.is_file():
            item = command_from(load(path), cmd_id)
            if item is not None:
                return item, path
    return None


def _split_command(root, report, cmd_id, report_path):
    """Resolve a generated split child only through its longest saved ancestor."""
    snapshot = report.get("task_contract_snapshot") if isinstance(report, dict) else None
    if not isinstance(snapshot, dict) or str(snapshot.get("issued_cmd_id") or "") != cmd_id:
        return None
    # A worker can be leased to a later task before Karo reviews its immutable
    # report.  In that case the durable receipt is the generation boundary: it
    # binds report_id, identity version, fingerprint, logical report path,
    # parent_cmd, and task_id to the report that was actually received.  Do not
    # re-apply the live worker's issued_cmd_id/report_filename/subtask_id checks
    # after that proof; those fields necessarily describe the later lease.
    receipt_match = _receipt_generation_matches(root, report_path, report)
    _, task_path = _snapshot_command(root, report, cmd_id, report_path)
    task = load(task_path).get("task")
    if not receipt_match:
        split_identities = {
            "issued_cmd_id": (cmd_id, task.get("issued_cmd_id")),
            "report_filename": (Path(report_path).name, task.get("report_filename")),
        }
        for key, (expected, actual) in split_identities.items():
            if not expected or str(actual or "") != str(expected):
                raise ValueError(f"immutable task/report identity mismatch: {key}")
        if not str(task.get("subtask_id") or "").strip():
            raise ValueError("split task subtask_id is missing")
    ancestor = None
    for cut in range(len(cmd_id), 3, -1):
        if cut < len(cmd_id) and cmd_id[cut] != "_":
            continue
        candidate = cmd_id[:cut]
        found = _saved_command(root, candidate)
        if found:
            ancestor = (candidate, *found)
            break
    if ancestor is None:
        return None
    _, command, source = ancestor
    criteria = command.get("acceptance_criteria")
    ancestor_ids = set(criteria) if isinstance(criteria, dict) else {
        str(item.get("id")) for item in criteria or [] if isinstance(item, dict) and item.get("id")
    }
    assigned = task.get("assigned_acs")
    # assigned_acs=None means the split task covers all ancestor ACs (common for
    # recon/scout splits that explore the full scope).  Only validate subset when
    # an explicit list is provided.
    if isinstance(assigned, list) and assigned:
        if not set(map(str, assigned)).issubset(ancestor_ids):
            raise ValueError("split task assigned_acs are not a subset of ancestor acceptance criteria")
    return command, source


def find_command(root, cmd_id, report=None, report_path=None, requested_verdict=None):
    saved = _saved_command(root, cmd_id)
    if saved:
        return saved
    # Auto-generated commands intentionally have no Shogun command record.
    # Their immutable deploy-generation snapshot is the contract; the live
    # worker task may already belong to a later assignment.
    if cmd_id.startswith(SPEC_LESS_AUTOGEN_PREFIXES) and isinstance(report, dict) and report_path is not None:
        state = (str(report.get("status") or ""), str(report.get("verdict") or "").upper())
        # The review verdict and the reporter's verdict are separate axes.  A
        # reviewer may legitimately reject a completed/PASS report; requiring
        # the reporter to rewrite it as failed/FAIL destroys the evidence that
        # was reviewed.  APPROVE accepts either completed success state, while
        # FAIL accepts either a rejected success claim or an already self-reported failure.
        allowed = ({("completed", "PASS"), ("failed", "FAIL")} if requested_verdict == "FAIL"
                   else _APPROVE_REPORT_STATES)
        if state not in allowed:
            expected = " or ".join(f"{status}/{verdict}" for status, verdict in sorted(allowed))
            raise ValueError(f"autogen spec fallback requires {expected} report")
        return _snapshot_command(root, report, cmd_id, report_path)
    if isinstance(report, dict) and report_path is not None:
        split = _split_command(root, report, cmd_id, report_path)
        if split:
            return split
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

def _json_default(value):
    # PyYAML parses unquoted ISO timestamps in review ledgers as datetime
    # objects.  The single-review manifest is JSON, so normalize that YAML
    # scalar at the boundary while still rejecting unrelated unsupported
    # objects instead of silently stringifying them.
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True); lock_path = path.with_suffix(path.suffix + ".lock")
    with lock_path.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX); temp = path.with_name(f".{path.name}.tmp.{os.getpid()}")
        try:
            temp.write_text(json.dumps(value, default=_json_default, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            os.replace(temp, path)
        finally:
            if temp.exists(): temp.unlink()

def _review_registry(root, cmd_id):
    """Return the canonical (realpath, logical path) identities from the shell SSOT."""
    library = Path(__file__).resolve().parent / "lib/review_approval.sh"
    script = f'''source "{library}"
review_resolve_reports "$1" | while IFS= read -r report; do
    logical=$(review_report_logical_path "$report") || exit 1
    printf '%s\\t%s\\n' "$(realpath "$report")" "$logical"
done
'''
    result = subprocess.run(
        ["bash", "-c", script, "review-registry", cmd_id], cwd=root,
        env={**os.environ, "PROJECT_ROOT": str(root)}, text=True,
        capture_output=True, check=True,
    )
    return {tuple(line.split("\t", 1)) for line in result.stdout.splitlines() if "\t" in line}


def _resolve_report(root, report_ref, cmd_id, *, allow_archived=False):
    """Resolve only an identity selected by the shared canonical report registry."""
    report_arg = Path(report_ref)
    if not report_arg.is_absolute(): report_arg = root / report_arg
    lexical = str(report_arg)
    if os.path.normpath(lexical) != lexical:
        raise ValueError("report identity is not a canonical lexical path")
    report_arg = Path(os.path.abspath(report_arg)); report = report_arg.resolve()
    logical = f"queue/reports/{report_arg.name}"
    identity = (str(report), logical)
    registry = _review_registry(root, cmd_id)
    archived = (root / "queue/archive/reports").resolve()
    # When called with an archive path (e.g. from review_approval.sh report_rel),
    # report_arg.name carries the archive date suffix, so the logical path won't
    # match. Fall back to registry lookup by realpath to recover the canonical
    # logical identity.
    if identity not in registry:
        realpath_str = str(report)
        for reg_real, reg_logical in registry:
            if reg_real == realpath_str:
                identity = (realpath_str, reg_logical)
                break
    if (report.parent == archived and not allow_archived) or identity not in registry or not report.is_file():
        raise ValueError("report identity is not in the canonical report registry")
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
    report_arg, report = _resolve_report(root, args.report, args.cmd, allow_archived=args.allow_archived)
    report_data = load(report)
    if str(report_data.get("parent_cmd") or "") != args.cmd: raise ValueError("report parent_cmd contradicts requested cmd")
    report_ref = report_arg if report_arg.is_relative_to(root) else report
    verdict = args.verdict.upper()
    command, source = find_command(root, args.cmd, report_data, report_ref, verdict)
    if verdict == "APPROVE":
        report_state = (str(report_data.get("status") or ""), str(report_data.get("verdict") or "").upper())
        if report_state not in _APPROVE_REPORT_STATES:
            raise ValueError("APPROVE requires completed/PASS or completed/PASS_NO_IMPROVEMENT report")
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
    print(relative); print(json.dumps(spec, ensure_ascii=False, sort_keys=True))
    # 2026-08-26: `generate` を単独CLIで叩いただけでは承認(gunshi LGTM)にならない。
    # batch4/5r/6r/7r/8r で軍師が generate のみ実行→承認欠落→家老gate 5件BLOCKした実証。
    # 直接CLI呼出し(single/batch経由でない)でAPPROVE時、LGTM承認が未記録なら fail-closed(rc=3)で
    # 次に叩くべきコマンドを名指しする。bundle自体は書いてよい(承認の前提物であり、上書き冪等)。
    if getattr(args, "direct_cli", False) and verdict == "APPROVE":
        approval_check = f'''source "{root / 'scripts/lib/review_approval.sh'}"
PROJECT_ROOT="{root}" review_two_phase_ready_gunshi "{args.cmd}" "{report}"
'''
        ready = subprocess.run(["bash", "-c", approval_check], cwd=root).returncode == 0
        if not ready:
            print(f"BLOCK: gunshi LGTM approval not recorded for {args.cmd} — bundle alone is not an approval. "
                  f"NEXT: python3 scripts/review_bundle.py single --cmd {args.cmd} --verdict APPROVE --report {review['report']} "
                  f"--review-entry <review_log entry yaml>  (the /review-bundle skill Step 1; direct review_approval.sh gunshi LGTM is rejected)", file=sys.stderr)
            return 3
    return 0

def notify(args):
    started = time.monotonic()
    root = Path(args.root).resolve(); path = Path(args.bundle)
    if not path.is_absolute(): path = root / path
    path = path.resolve(); gates = (root / "queue/gates").resolve()
    if gates not in path.parents or path.name != "sg7_bundle.json": raise ValueError("bundle must be queue/gates/<cmd>/sg7_bundle.json")
    review = validate(load(path), args.cmd, "APPROVE")
    report_ref = str(review["report"])
    allow_archived = Path(report_ref).parent == Path("queue/archive/reports")
    _, report = _resolve_report(root, report_ref, args.cmd, allow_archived=allow_archived)
    if hashlib.sha256(report.read_bytes()).hexdigest() != review.get("report_fingerprint"): raise ValueError("bundle report fingerprint is stale")
    # The canonical approval entry publishes immediately, while the legacy
    # batch caller may still invoke notify after approval returns.  Serialize
    # both callers and bind the durable marker to the report generation so a
    # retry is exactly-once without suppressing a genuinely revised review.
    marker = root / f"queue/gates/{args.cmd}/sg7_notify.done"
    lock_path = marker.with_suffix(marker.suffix + ".lock")
    marker.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        fingerprint = str(review.get("report_fingerprint") or "")
        if marker.is_file() and marker.read_text(encoding="utf-8").strip() == fingerprint:
            print(f"{args.cmd} SG7 notification: SKIP (already published for report generation)")
            return 0
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
        marker_tmp = marker.with_name(f".{marker.name}.tmp.{os.getpid()}")
        try:
            marker_tmp.write_text(fingerprint + "\n", encoding="utf-8")
            os.replace(marker_tmp, marker)
        finally:
            if marker_tmp.exists(): marker_tmp.unlink()
    _emit_self_retro(root, "gunshi_review_bundle", args.cmd, round((time.monotonic()-started)*1000), "review_notify")
    print(message); return 0

def _emit_self_retro(root, endpoint, cmd_id, wall_ms, cause_class):
    writer = root / "scripts/lib/defense_overhead_writer.sh"
    prompt = root / "scripts/lib/retro_pane_prompt.sh"
    # These are post-delivery telemetry/reminder side effects.  Detach one
    # process after the SG7 inbox boundary so their startup cannot extend the
    # measured review-notify phase; each helper retains its own durable
    # exactly-once guard.
    payload = f'''source "{writer}"
self_retro_write_async {endpoint} {cmd_id} {wall_ms} '{{"review_bundle":{wall_ms}}}' {cause_class} "review bundle generated and delivered" "reduce dominant review phase while preserving SG7 validation" "delivery succeeds and duplicate event count is 0" "[[review_bundle]] -> [[review_delivery]] -> [[fix_known]]"
source "{prompt}"
retro_pane_prompt_async "{root}" gunshi "review_bundle:{cmd_id}" review_bundle
'''
    subprocess.Popen(
        ["bash", "-c", payload],
        cwd=root,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        close_fds=True,
        start_new_session=True,
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
        # FAIL verdict accepts precheck BLOCK (e.g. bc:no on failed reports).
        # The precheck observation is recorded but does not prevent bundle generation.
        if str(item.get("verdict", "")).upper() == "FAIL":
            return {"status": "BLOCK_ACCEPTED", "reason": f"precheck BLOCK accepted for FAIL verdict (rc={proc.returncode})", "evidence": evidence, "duration_ms": round((time.monotonic() - started) * 1000)}
        # A precheck can exit non-zero after emitting only advisory warnings.
        # The shell gate's authoritative result is its final ERRORS count, not
        # the process status alone.  Treat only the explicit zero-error case as
        # a warning; missing or positive ERRORS remains fail-closed so a real
        # report defect cannot be hidden by the review-bundle entry point.
        match = re.search(r"(?:総合|総計|TOTAL)\s*:\s*ERRORS\s*=\s*(\d+)", evidence, re.IGNORECASE)
        if match and int(match.group(1)) == 0:
            return {"status": "WARN", "reason": f"precheck exited rc={proc.returncode} with ERRORS=0; advisory warning retained", "evidence": evidence, "duration_ms": round((time.monotonic() - started) * 1000)}
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
            approval_env = os.environ.copy(); approval_env["REVIEW_APPROVAL_CANONICAL_ENTRY"] = "review_bundle"
            subprocess.run(["bash", str(root / "scripts/review_approval.sh"), str(item["cmd"]), "gunshi", "LGTM", str(item["report"])], cwd=root, env=approval_env, check=True)
            notify(argparse.Namespace(root=str(root), cmd=str(item["cmd"]), bundle=str(path)))
        else:
            message = f"{item['cmd']} review FAIL. report: {item['report']} reason: {item.get('fail_reason') or 'quality evidence mismatch'}"
            subprocess.run(["bash", str(root / "scripts/inbox_write.sh"), "karo", message, "report_review_result", "gunshi"], cwd=root, check=True)
    with ThreadPoolExecutor(max_workers=min(args.max_workers, len(items))) as pool:
        list(pool.map(finish, zip(items, paths)))
    durations = [x["duration_ms"] for x in prechecks]
    result = {"total": len(items), "fail": 0, "skip": 0, "wall_ms": round((time.monotonic() - wall_started) * 1000), "p95_report_ms": max(durations)}
    print(json.dumps(result, ensure_ascii=False, sort_keys=True)); return 0

def _singleflight_token(root, args, entry):
    """Bind one review notification to one report/contract generation."""
    report_path = Path(args.report)
    if not report_path.is_absolute():
        report_path = root / report_path
    report_path = report_path.resolve()
    report = load(report_path) if report_path.is_file() else {}
    worker = str(report.get("worker_id") or "").strip()
    task = {}
    if worker:
        task_path = root / "queue" / "tasks" / f"{worker}.yaml"
        if task_path.is_file():
            task_doc = load(task_path)
            task = task_doc.get("task", task_doc) if isinstance(task_doc, dict) else {}
    contract = {
        "parent_cmd": str(report.get("parent_cmd") or args.cmd),
        "task_id": str(report.get("task_id") or task.get("task_id") or ""),
        "ac_version": str(report.get("ac_version_read") or task.get("ac_version") or ""),
        "report_id": str(report.get("report_id") or ""),
        "report_identity_version": str(
            report.get("report_identity_version") or task.get("report_identity_version") or ""
        ),
    }
    logical_report = f"queue/reports/{report_path.name}"
    approval_key = hashlib.sha256(logical_report.encode("utf-8")).hexdigest()
    approval_dir = root / "queue" / "gates" / str(args.cmd) / "review_approvals" / "reports" / approval_key
    approval_state = {}
    for relative in (
        "gunshi.yaml", "karo.yaml", "last_rc_commit", "last_rc_scope",
        "last_rc_report_payload", "last_rc_snapshot_dir", "karo_rework.seen",
    ):
        state_path = approval_dir / relative
        approval_state[relative] = state_path.read_text(encoding="utf-8") if state_path.is_file() else None
    gate_marker = root / "queue" / "gates" / str(args.cmd) / "review_gate.done"
    approval_state["review_gate.done"] = (
        gate_marker.read_text(encoding="utf-8") if gate_marker.is_file() else None
    )
    payload = {
        "cmd": str(args.cmd),
        "report": str(report_path),
        "report_sha256": hashlib.sha256(report_path.read_bytes()).hexdigest() if report_path.is_file() else "missing",
        "contract": contract,
        "approval_state": approval_state,
        "review_entry": entry,
    }
    encoded = json.dumps(payload, default=_json_default, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def single(args):
    """Run one review notification as a durable single-flight transaction."""
    entry = load(args.review_entry)
    if isinstance(entry, list):
        matches = [item for item in entry if isinstance(item, dict) and str(item.get("cmd_id") or "") == args.cmd]
        if len(matches) != 1:
            raise ValueError(f"single review_entry sequence requires exactly one cmd_id={args.cmd} mapping (found {len(matches)})")
        entry = matches[0]
    if not isinstance(entry, dict) or not entry:
        raise ValueError("single review_entry must be a non-empty YAML mapping")
    item = {"cmd": args.cmd, "report": args.report, "verdict": args.verdict,
            "review_entry": entry}
    precheck_na = entry.get("precheck_na")
    if precheck_na is not None:
        if not isinstance(precheck_na, dict):
            raise ValueError("single review_entry precheck_na must be a mapping")
        item["precheck_na"] = precheck_na
    if args.fail_reason:
        item["fail_reason"] = args.fail_reason
    root = Path(args.root).resolve()
    gate_dir = root / "queue" / "gates" / args.cmd
    gate_dir.mkdir(parents=True, exist_ok=True)
    token = _singleflight_token(root, args, entry)
    terminal = gate_dir / "single_review_terminal.json"
    lock_path = gate_dir / "single_review_singleflight.lock"
    with lock_path.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        if terminal.is_file():
            previous = load(terminal)
            if str(previous.get("token") or "") == token:
                if previous.get("status") == "success":
                    print(f"{args.cmd} review singleflight: SKIP (durable terminal)")
                    return 0
                raise ValueError(
                    "singleflight terminal failure: "
                    + str(previous.get("error") or "unknown review failure")
                )
        manifest = gate_dir / "single_review_manifest.json"
        atomic_json(manifest, {"reviews": [item]})
        try:
            result = batch(argparse.Namespace(root=str(root), manifest=str(manifest), max_workers=1))
        except Exception as exc:
            atomic_json(terminal, {
                "version": 1, "token": token, "status": "failure",
                "error": str(exc),
            })
            raise
        atomic_json(terminal, {"version": 1, "token": token, "status": "success"})
        return result

def build_parser():
    p = argparse.ArgumentParser(); p.add_argument("--root", default=str(Path(__file__).resolve().parents[1])); subs = p.add_subparsers(dest="action", required=True)
    g = subs.add_parser("generate"); g.add_argument("--cmd", required=True); g.add_argument("--verdict", required=True, choices=("APPROVE", "FAIL")); g.add_argument("--report", required=True); g.add_argument("--fail-reason"); g.add_argument("--allow-archived", action="store_true"); g.set_defaults(func=generate, direct_cli=True)
    n = subs.add_parser("notify"); n.add_argument("--cmd", required=True); n.add_argument("--bundle", required=True); n.set_defaults(func=notify)
    c = subs.add_parser("consume"); c.add_argument("--cmd", required=True); c.add_argument("--bundle", required=True); c.add_argument("--expect-verdict", choices=("APPROVE", "FAIL")); c.set_defaults(func=consume)
    b = subs.add_parser("batch"); b.add_argument("--manifest", required=True); b.add_argument("--max-workers", type=int, default=5); b.set_defaults(func=batch)
    s = subs.add_parser("single"); s.add_argument("--cmd", required=True); s.add_argument("--report", required=True); s.add_argument("--verdict", required=True, choices=("APPROVE", "FAIL")); s.add_argument("--review-entry", required=True); s.add_argument("--fail-reason"); s.set_defaults(func=single)
    return p

def main():
    args = build_parser().parse_args()
    try: return args.func(args)
    except (OSError, ValueError, subprocess.CalledProcessError, yaml.YAMLError) as exc:
        print(f"BLOCK: review bundle: {exc}", file=sys.stderr); return 2

if __name__ == "__main__": raise SystemExit(main())
