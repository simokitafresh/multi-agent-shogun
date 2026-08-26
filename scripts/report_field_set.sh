#!/usr/bin/env bash
# semantic-links: [[YAML安全書込み]], [[gate迂回防止]], [[忍者報告品質プロトコル]]
# report_field_set.sh — 報告YAMLのフィールドをflock排他制御で安全に更新
# 共通ライブラリ(lib/yaml_field_set.sh)の関数を使用
#
# Usage: bash scripts/report_field_set.sh <report_path> <dot.notation.key> <value>
#        echo "multi-line value" | bash scripts/report_field_set.sh <report_path> <dot.notation.key> -
#
# - flock付き排他制御（inbox_write.sh同等パターン）
# - ドット記法でネストフィールドに対応（例: results.AC1.status）
# - 値が "-" ならstdinから読む
# - 存在しないキーは自動作成（中間dictも — Pythonフォールバック経由）
# - 平文フィールド: yaml_field_set.sh (awk) で高速処理
# - 構造体/複数行/新規ブロック: Pythonフォールバック

set -e

# Batch lane: one process, one flock and one atomic replace for a complete report
# transition. Input is a YAML mapping of dot-notation field names to values.
# This is intentionally a separate, fail-closed lane: partial writes are never
# committed when validation fails.
if [ "${1:-}" = "--batch" ]; then
    [ "$#" -eq 2 ] || { echo "Usage: report_field_set.sh --batch <report_path> < fields.yaml" >&2; exit 1; }
    _rfs_batch_report="$2"
    _rfs_batch_payload="$(cat)"
    _rfs_batch_self="${BASH_SOURCE[0]:-$0}"
    [[ "$_rfs_batch_self" != /* ]] && _rfs_batch_self="$PWD/$_rfs_batch_self"
    _rfs_batch_root="${_rfs_batch_self%/scripts/report_field_set.sh}"
    [[ "$_rfs_batch_report" = /* ]] || _rfs_batch_report="$PWD/$_rfs_batch_report"
    _rfs_batch_task_root="${REPORT_FIELD_SET_TASK_ROOT:-}"
    if [ -z "$_rfs_batch_task_root" ]; then
        case "$_rfs_batch_report" in
            */queue/reports/*)
                _rfs_batch_task_root="${_rfs_batch_report%%/queue/reports/*}"
                ;;
        esac
    fi
    _rfs_batch_lock="${_rfs_batch_report}.lock"
    _rfs_receipt_dir="${RFS_RECEIPT_DIR:-/dev/shm}"
    [ -d "$_rfs_receipt_dir" ] || _rfs_receipt_dir="${TMPDIR:-/tmp}"
    _rfs_phase_receipt="${RFS_PHASE_RECEIPT:-${_rfs_receipt_dir}/rfs-terminal-receipt.$$.tsv}"
    : >"$_rfs_phase_receipt"
    _rfs_current_fp=missing
    _rfs_mono_ms() {
        local _up _whole _frac
        read -r _up _ </proc/uptime
        _whole="${_up%%.*}"
        _frac="${_up#*.}000"
        _frac="${_frac:0:3}"
        printf '%s\n' "$((10#${_whole} * 1000 + 10#${_frac}))"
    }
    _rfs_phase() {
        local _phase="$1" _started="$2" _now _fp
        _now="$(_rfs_mono_ms)"
        _fp="$_rfs_current_fp"
        printf '%s\twall_ms=%s\tcaller=%s\towner_pid=%s\tfingerprint=%s\n' \
            "$_phase" "$((_now - _started))" "${RFS_CALLER:-report_field_set}" "$$" "${_fp:-missing}" >>"$_rfs_phase_receipt"
    }
    _rfs_wait_started="$(_rfs_mono_ms)"
    # Only terminal transitions participate in the gate single-flight.  A
    # successful nonterminal batch still has its own report lock below; making
    # it wait behind a terminal gate produced multi-second publish_total tails
    # without protecting any terminal lifecycle edge.
    _rfs_terminal_transition=0
    if grep -Eq '^[[:space:]]*status:[[:space:]]*["'\'']?(completed|done|failed|revision_requested)(["'\'']?[[:space:]]*(#.*)?$)' \
        <<<"$_rfs_batch_payload"; then
        _rfs_terminal_transition=1
        exec 199>"${_rfs_batch_report}.gate.lock"
        flock -w "${RFS_SINGLEFLIGHT_TIMEOUT:-30}" 199 || { echo "BLOCK: terminal gate single-flight timeout" >&2; exit 1; }
    else
        exec 199>/dev/null
    fi
    _rfs_phase singleflight_wait "$_rfs_wait_started"
    mkdir -p "${_rfs_batch_report%/*}"
    exec 200>"$_rfs_batch_lock"
    flock -w 5 200 || { echo "BLOCK: batch report lock timeout" >&2; exit 1; }
    _rfs_atomic_started="$(_rfs_mono_ms)"
    # 公開直後のterminal識別子を受け取るside-channel(stdout契約は不変)。
    # RFS_BATCH_META_DISABLE=1 はside-channelを無効化し、従来の再読込fallbackを
    # そのまま実行させる(fallbackが生きていることを外から検証可能にするため)。
    if [ "${RFS_BATCH_META_DISABLE:-0}" = "1" ]; then
        _rfs_batch_meta_file=""
    else
        _rfs_batch_meta_file="$(mktemp "${_rfs_batch_report}.meta.XXXXXX")" || _rfs_batch_meta_file=""
    fi
    _rfs_batch_output=$(RFS_BATCH_META_FILE="$_rfs_batch_meta_file" \
        RFS_PHASE_RECEIPT="$_rfs_phase_receipt" \
        RFS_BATCH_PAYLOAD="$_rfs_batch_payload" \
        python3 - "$_rfs_batch_report" "$_rfs_batch_root" "$_rfs_batch_task_root" <<'PY'
import datetime, hashlib, os, pathlib, re, subprocess, sys, tempfile, time, yaml
from typing import Any
sys.path.insert(0, sys.argv[2])
from scripts.lib.yaml_atomic import yaml_text

path = pathlib.Path(sys.argv[1])
phase_receipt = os.environ.get("RFS_PHASE_RECEIPT")

def record_phase(name, started_ns):
    if not phase_receipt:
        return
    wall_ms = max(0, (time.monotonic_ns() - started_ns) // 1_000_000)
    with open(phase_receipt, "a", encoding="utf-8") as receipt:
        receipt.write(f"{name}\twall_ms={wall_ms}\tcaller=report_field_set"
                      f"\towner_pid={os.getppid()}\tfingerprint=missing\n")

parse_validate_serialize_started = time.monotonic_ns()
updates = yaml.safe_load(os.environ.get("RFS_BATCH_PAYLOAD", ""))
if not isinstance(updates, dict) or not updates:
    raise SystemExit("BLOCK: batch input must be a non-empty YAML mapping")
data = yaml.safe_load(path.read_text(encoding="utf-8")) if path.exists() else {}
if not isinstance(data, dict):
    raise SystemExit("BLOCK: report must be a YAML mapping")
# Level 5 report scaffold: legacy/alternate publication paths may hand the
# authoring lane a report created before operational_simulation became
# mandatory.  Repair structure only; empty values deliberately remain invalid
# so gate_report_format.sh still requires the ninja's measured evidence.
opsim = data.get("operational_simulation")
if not isinstance(opsim, dict):
    opsim = {}
    data["operational_simulation"] = opsim
for field in ("command", "expected", "actual", "result"):
    opsim.setdefault(field, "")
old_status = str(data.get("status", "")).strip()
if old_status in {"completed", "done"} and updates.get("status") != "revision_requested":
    raise SystemExit("BLOCK: completed report is immutable; batch must first transition to revision_requested")

def set_dot(root, dotted, value):
    keys = dotted.replace("[", ".").replace("]", "").split(".")
    cur = root
    for key in keys[:-1]:
        if key.isdigit():
            idx = int(key)
            if not isinstance(cur, list) or idx >= len(cur):
                raise ValueError(f"invalid list path: {dotted}")
            cur = cur[idx]
        else:
            if not isinstance(cur, dict):
                raise ValueError(f"invalid mapping path: {dotted}")
            cur = cur.setdefault(key, {})
    last = keys[-1]
    if last.isdigit():
        idx = int(last)
        if not isinstance(cur, list) or idx >= len(cur):
            raise ValueError(f"invalid list path: {dotted}")
        cur[idx] = value
    else:
        if not isinstance(cur, dict):
            raise ValueError(f"invalid mapping path: {dotted}")
        cur[last] = value

# review_bundle.py's _HOOK_POST_RESULTS enforces exactly these three
# lowercase snake_case tokens; ninjas keep writing the PASS/UPPER_SNAKE form
# tool output shows them, which round-trips through gunshi APPROVE rejection.
# Canonicalize only the exact path (not the direct-sibling
# hook_failures.post_verification_result) so an unknown value still falls
# through to review_bundle.py's existing BLOCK unchanged.
_HOOK_POST_RESULT_CANON = {
    "PASS": "all_pass", "all_pass": "all_pass",
    "NO_NEW_FAILURE": "no_new_failure", "no_new_failure": "no_new_failure",
    "REGRESSION_DETECTED": "regression_detected", "regression_detected": "regression_detected",
}

def canonicalize_hook_result(key, value):
    target = None
    if key == "hook_failures" and isinstance(value, dict):
        details = value.get("details")
        if isinstance(details, dict):
            target = details
    elif key == "hook_failures.details" and isinstance(value, dict):
        target = value
    if target is not None:
        current = target.get("post_verification_result")
        if isinstance(current, str):
            target["post_verification_result"] = _HOOK_POST_RESULT_CANON.get(current, current)
    elif key == "hook_failures.details.post_verification_result" and isinstance(value, str):
        value = _HOOK_POST_RESULT_CANON.get(value, value)
    return value

try:
    for key, value in updates.items():
        if not isinstance(key, str) or not key.strip():
            raise ValueError("batch field names must be non-empty strings")
        if key.startswith("binary_checks.") and key.endswith(".result") and isinstance(value, bool):
            value = "yes" if value else "no"
        # LG048 D0根治(2026-08-09): batch経路でもsemantic_validation.resultをPASS/FAILに制限
        if key == "semantic_validation.result" and isinstance(value, str) and value.strip() not in ("PASS", "FAIL"):
            raise ValueError(f"semantic_validation.result must be PASS or FAIL, got: {value!r}")
        value = canonicalize_hook_result(key, value)
        set_dot(data, key, value)
except ValueError as exc:
    raise SystemExit(f"BLOCK: {exc}")

bc = data.get("binary_checks")
results = []
files = data.get("files_modified")
lessons = data.get("lessons_useful")
if not isinstance(files, list) or any(not isinstance(item, dict) for item in files):
    raise SystemExit("BLOCK: files_modified must be a YAML list of mappings; scalar input is not auto-fixed")
if not isinstance(lessons, list) or any(not isinstance(item, dict) for item in lessons):
    raise SystemExit("BLOCK: lessons_useful must be a YAML list of mappings; scalar input is not auto-fixed")
if not isinstance(bc, dict):
    raise SystemExit("BLOCK: binary_checks must be a YAML mapping of check lists; scalar input is not auto-fixed")
for ac_key, checks in bc.items():
    if not isinstance(checks, list) or any(not isinstance(item, dict) for item in checks):
        raise SystemExit(f"BLOCK: binary_checks.{ac_key} must be a YAML list of mappings; scalar input is not auto-fixed")
    results.extend(str(item.get("result", "")).strip().lower() for item in checks)
bad = [value for value in results if value not in {"yes", "no"}]
if bad:
    raise SystemExit("BLOCK: binary_checks results must all be yes/no")
if results:
    data["verdict"] = "PASS" if all(value == "yes" for value in results) else "FAIL"
    if any(value == "no" for value in results):
        data["status"] = "failed"
    elif old_status in {"completed", "done"} and updates.get("status") == "revision_requested":
        # A completed report revision is an explicit, single-transaction lane:
        # unlock, apply every field, derive the verdict, then republish terminal.
        # The intermediate revision_requested state must never reach readers.
        data["status"] = "completed"

terminal = str(data.get("status", "")).strip() in {"completed", "done", "failed"}
# The authoring timestamp is created at deployment and can predate terminal
# publication by multiple review rounds. Record the real terminal edge in the
# same atomic replace as the report status so downstream gap telemetry uses the
# completion event rather than deployment time.
if terminal:
    data["completed_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
root = pathlib.Path(sys.argv[2]).resolve()
task_root_arg = str(sys.argv[3]).strip()
task_root = pathlib.Path(task_root_arg).resolve() if task_root_arg else None

def lesson_feedback_task_path(report: dict[str, Any]) -> pathlib.Path | None:
    explicit = str(os.environ.get("RFS_TASK_FILE_PATH", "")).strip()
    if explicit:
        return pathlib.Path(explicit).resolve()
    worker = str(report.get("worker_id") or "").strip()
    if not worker or task_root is None:
        return None
    return task_root / "queue" / "tasks" / f"{worker}.yaml"

def validate_lesson_feedback_set(report: dict[str, Any]) -> None:
    task_path = lesson_feedback_task_path(report)
    if task_path is None or not task_path.is_file():
        return
    try:
        task_doc = yaml.safe_load(task_path.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError) as exc:
        raise SystemExit(f"BLOCK: lesson_feedback_set task read failed: {exc}")
    task = task_doc.get("task", task_doc) if isinstance(task_doc, dict) else {}
    # Older reports without an explicit lesson-set declaration retain their
    # compatibility path.  An explicit empty list remains a contract and is
    # checked by the shared SSOT (including the empty/empty PASS boundary).
    if not isinstance(task, dict) or not (
        "assigned_lesson_ids" in task or "related_lessons" in task
    ):
        return
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent,
        prefix=f".{path.name}.lesson-feedback.", delete=False,
    ) as staged:
        staged.write(yaml_text(report, allow_unicode=True, sort_keys=False))
        staged_report = pathlib.Path(staged.name)
    try:
        result = subprocess.run(
            [
                sys.executable,
                str(root / "scripts" / "lib" / "report_gate_contract.py"),
                "lesson-feedback-set",
                str(task_path),
                str(staged_report),
            ],
            text=True,
            capture_output=True,
            check=False,
        )
    except OSError as exc:
        raise SystemExit(f"BLOCK: lesson_feedback_set invocation failed: {exc}")
    finally:
        staged_report.unlink(missing_ok=True)
    if result.returncode != 0:
        detail = (result.stdout.strip() or result.stderr.strip() or "unknown mismatch")
        raise SystemExit(f"BLOCK: lesson_feedback_set: {detail}")

def task_allows_empty_lessons(report, root):
    if root is None:
        return False
    worker = str(report.get("worker_id") or "").strip()
    if not worker:
        return False
    task_path = root / "queue" / "tasks" / f"{worker}.yaml"
    try:
        task_doc = yaml.safe_load(task_path.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError):
        return False
    task = task_doc.get("task", task_doc) if isinstance(task_doc, dict) else {}
    return isinstance(task, dict) and task.get("related_lessons") == []

def expected_failed_commit_absence(report):
    """Permit only the truthful terminal FAIL lane to omit a required commit."""
    contract = report.get("commit_contract")
    checks = (report.get("binary_checks") or {}).get("commit")
    return (
        str(report.get("status") or "").strip().lower() == "failed"
        and str(report.get("verdict") or "").strip().upper() == "FAIL"
        and isinstance(contract, dict)
        and contract.get("required") is True
        and isinstance(checks, list)
        and bool(checks)
        and all(
            isinstance(item, dict)
            and str(item.get("result") or "").strip().lower() == "no"
            for item in checks
        )
    )

# operational_simulation is the author-entered test evidence SSOT.  Keep the
# legacy test_results consumer compatible without a second hand-written copy.
opsim = data.get("operational_simulation")
if isinstance(opsim, dict) and all(str(opsim.get(key) or "").strip() for key in ("command", "expected", "actual", "result")):
    data["test_results"] = dict(opsim)
if terminal:
    validate_lesson_feedback_set(data)
    required = ("worker_id", "parent_cmd", "ac_version_read", "binary_checks", "files_modified", "lessons_useful", "lesson_candidate")
    missing = [key for key in required if data.get(key) in (None, "", [], {})
               and not (key == "lessons_useful" and data.get(key) == []
                        and task_allows_empty_lessons(data, task_root))]
    if missing:
        raise SystemExit("BLOCK: terminal readiness missing: " + ",".join(missing))
    commit = str(data.get("commit_hash", "")).strip()
    # Third and final terminal-readiness entrance uses the same structural
    # no-code identity contract as review_approval and cmd_complete_gate.
    # This does not trust commit_contract.required alone: evidence, an explicit
    # no-commit assertion, and operational-only paths must all be true.
    if not re.fullmatch(r"[0-9a-f]{40}", commit) and not expected_failed_commit_absence(data):
        # The normal implementation lane always carries a full commit hash.
        # Loading report_commit_identity also imports pathlib/subprocess and
        # taxed every terminal publish despite being needed only by the
        # explicit no-code fallback.
        from scripts.lib.report_commit_identity import permits_no_code_identity
        if not permits_no_code_identity(data, root):
            raise SystemExit("BLOCK: terminal readiness requires a 40-hex commit or shared no-code identity contract")

text = yaml_text(data, allow_unicode=True, sort_keys=False)
record_phase("atomic_parse_validate_serialize", parse_validate_serialize_started)
fd, tmp = tempfile.mkstemp(prefix=path.name + ".batch.", dir=path.parent)
try:
    flush_fsync_started = time.monotonic_ns()
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(text); handle.flush(); os.fsync(handle.fileno())
    record_phase("atomic_flush_file_fsync", flush_fsync_started)
    replace_started = time.monotonic_ns()
    os.replace(tmp, path)
    record_phase("atomic_replace_syscall", replace_started)
finally:
    if os.path.exists(tmp): os.unlink(tmp)

# cmd_karo_impl_report_publish_latency_20260725: publish経路はこの直後に
# status/worker_id/parent_cmd を得るため report を3回 python3+yaml.safe_load で
# 読み直していた(実測 avg 548ms = publish総時間の52.5%)。ここでは同じ値が
# 既にメモリ上にあり、公開済みバイト列と同一である。検査を1つも省かずに
# 再読込3プロセスだけを消すため、値をside-channelファイルへ書き出す
# (stdoutは既存の 'fingerprint=' パース契約があるため変更しない)。
meta_path = os.environ.get("RFS_BATCH_META_FILE")
if meta_path:
    with open(meta_path, "w", encoding="utf-8") as meta_handle:
        meta_handle.write("\t".join([
            str(data.get("status", "")),
            str(data.get("worker_id", "")),
            str(data.get("parent_cmd", "")),
            str(data.get("report_id", "")),
        ]) + "\n")
print("BATCH_OK fields={} fingerprint={}".format(len(updates), hashlib.sha256(text.encode()).hexdigest()))
PY
)
    _rfs_batch_rc=$?
    printf '%s\n' "$_rfs_batch_output"
    if [ "$_rfs_batch_rc" -eq 0 ]; then
        _rfs_current_fp="${_rfs_batch_output##*fingerprint=}"
    fi
    _rfs_phase atomic_replace "$_rfs_atomic_started"
    if [ "$_rfs_batch_rc" -eq 0 ]; then
        # 公開済みバイト列の識別子(status/worker_id/parent_cmd)は、書込みを行った
        # python processが既に保持している。side-channelから受け取り、同じ値を得る
        # ための3回のpython3+yaml.safe_load再読込を消す(実測 548ms/1043ms = 52.5%)。
        # side-channelが無い/壊れた場合は従来の再読込へfallbackする(fail-closed)。
        _rfs_meta_started="$(_rfs_mono_ms)"
        _rfs_batch_status=""
        _rfs_batch_worker=""
        _rfs_batch_parent=""
        _rfs_batch_report_id=""
        if [ -s "$_rfs_batch_meta_file" ]; then
            IFS=$'\t' read -r _rfs_batch_status _rfs_batch_worker _rfs_batch_parent _rfs_batch_report_id \
                < "$_rfs_batch_meta_file" || true
        fi
        if [ -z "$_rfs_batch_status" ]; then
            _rfs_batch_status=$(python3 - "$_rfs_batch_report" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
print(str(data.get("status", "")))
PY
)
        fi
        _rfs_phase terminal_meta "$_rfs_meta_started"
        if [ "$_rfs_batch_status" = "completed" ] || [ "$_rfs_batch_status" = "done" ] || [ "$_rfs_batch_status" = "failed" ]; then
            _rfs_validated_fp="$_rfs_current_fp"
            if [ -z "$_rfs_batch_worker" ]; then
                _rfs_batch_worker=$(python3 - "$_rfs_batch_report" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
print(str(data.get("worker_id", "")))
PY
)
            fi
            if [ -z "$_rfs_batch_parent" ]; then
                _rfs_batch_parent=$(python3 - "$_rfs_batch_report" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
print(str(data.get("parent_cmd", "")))
PY
)
            fi
            [ -n "$_rfs_batch_worker" ] && [ -n "$_rfs_batch_parent" ] || {
                echo "BLOCK: terminal report lacks worker_id/parent_cmd for durable publish" >&2
                exit 1
            }
            # The terminal report is the durable outbox. Publishing here binds
            # the canonical parent and review child to the exact persisted bytes;
            # inbox_write owns fingerprint dedupe and the atomic task-done edge.
            _rfs_inbox_write="${RFS_INBOX_WRITE_PATH:-$_rfs_batch_root/scripts/inbox_write.sh}"
            _rfs_event_type="report_received"
            _rfs_event_label="報告完了"
            if [ "$_rfs_batch_status" = "failed" ]; then
                _rfs_event_type="task_failed"
                _rfs_event_label="未達報告"
                _rfs_task_file="${RFS_TASK_FILE_PATH:-}"
                if [ -z "$_rfs_task_file" ] && [ -n "$_rfs_batch_task_root" ]; then
                    _rfs_task_file="$_rfs_batch_task_root/queue/tasks/${_rfs_batch_worker}.yaml"
                fi
                [ -f "$_rfs_task_file" ] || { echo "BLOCK: failed report lacks worker task YAML" >&2; exit 1; }
                bash "$_rfs_batch_root/scripts/lib/yaml_field_set.sh" "$_rfs_task_file" task status failed
            fi
            if [ "${RFS_DISABLE_FAST_RECONCILER:-0}" != "1" ]; then
                # Detached bounded reconciler closes the process/pane-death
                # window without waiting for ninja_monitor's 20s cycle. The
                # synchronous publisher below remains the success boundary;
                # both converge through inbox_write's fingerprint transaction.
                # DELAY must exceed the synchronous publisher+gate path: at 0.2s
                # the reconciler's inbox_write→gate_report_format grabbed the
                # report lock while this process still held it (circular
                # lock contention, 3 ninjas stalled 2026-07-27).
                # Close both locks in the parent before spawning. Closing only
                # on the final bash redirection leaves a race where nohup or
                # setsid -f can transiently inherit them before its exec.
                flock -u 200
                exec 200>&-
                [ "$_rfs_terminal_transition" -eq 0 ] || flock -u 199
                exec 199>&-
                RFS_RECONCILE_INBOX="$_rfs_inbox_write" \
                RFS_RECONCILE_REPORT="$_rfs_batch_report" \
                RFS_RECONCILE_WORKER="$_rfs_batch_worker" \
                RFS_RECONCILE_PARENT="$_rfs_batch_parent" \
                RFS_RECONCILE_EVENT="$_rfs_event_type" \
                RFS_RECONCILE_LABEL="$_rfs_event_label" \
                RFS_RECONCILE_DELAY="${RFS_RECONCILE_DELAY:-30}" \
                    nohup setsid -f bash -c '
                        sleep "$RFS_RECONCILE_DELAY"
                        bash "$RFS_RECONCILE_INBOX" karo \
                          "$RFS_RECONCILE_WORKER${RFS_RECONCILE_LABEL}。report=${RFS_RECONCILE_REPORT##*/} parent_cmd=$RFS_RECONCILE_PARENT" \
                          "$RFS_RECONCILE_EVENT" "$RFS_RECONCILE_WORKER" notify_karo
                    ' 199>&- 200>&- </dev/null >/dev/null 2>&1 &
            fi
            if [ "${RFS_FAIL_AFTER_ATOMIC_REPLACE:-0}" = "1" ]; then
                echo "FAILPOINT: terminal bytes persisted before lifecycle publish" >&2
                exit 86
            fi
            _rfs_inbox_started="$(_rfs_mono_ms)"
            GATE_SINGLEFLIGHT_OWNER=1 GATE_OWNER_PID="$$" GATE_PHASE_RECEIPT="$_rfs_phase_receipt" \
            bash "$_rfs_inbox_write" karo \
                "${_rfs_batch_worker}${_rfs_event_label}。report=$(basename "$_rfs_batch_report") parent_cmd=${_rfs_batch_parent}" \
                "$_rfs_event_type" "$_rfs_batch_worker" notify_karo
            _rfs_phase inbox_write "$_rfs_inbox_started"
            _rfs_publish_started="$(_rfs_mono_ms)"
            _rfs_phase publish "$_rfs_publish_started"
            _rfs_total_ms=$(( $(_rfs_mono_ms) - _rfs_wait_started ))
            if [ "$_rfs_total_ms" -gt 1000 ]; then
                printf 'infra_bug_suspected\twall_ms=%s\tcaller=%s\towner_pid=%s\tfingerprint=%s\n' \
                    "$_rfs_total_ms" "${RFS_CALLER:-report_field_set}" "$$" \
                    "$(sha256sum "$_rfs_batch_report" | awk '{print $1}')" >>"$_rfs_phase_receipt"
            fi
        fi
    fi
    [ -n "$_rfs_batch_meta_file" ] && rm -f "$_rfs_batch_meta_file"
    # Async telemetry must not inherit either report lock.  The lifecycle edge
    # above is complete; retaining these fds in its child can make the next
    # batch wait until timeout even after this publisher returns.
    flock -u 200 2>/dev/null || true
    exec 200>&-
    if [ "$_rfs_terminal_transition" -eq 1 ]; then
        flock -u 199 2>/dev/null || true
    fi
    exec 199>&-
    # cmd_karo_impl_report_publish_latency_20260725: publish経路の相別所要時間を
    # 既存台帳 logs/defense_overhead.jsonl へ流す(新台帳を作らない)。
    # /dev/shmのTSV receiptはプロセス毎に消えるため前後比較の母数にできなかった。
    if [ "${RFS_PUBLISH_TELEMETRY:-1}" = "1" ] \
        && [ -f "$_rfs_batch_root/scripts/lib/defense_overhead_writer.sh" ]; then
        # Telemetry is observational and already writes asynchronously.  Keep
        # its setup on that same child lane too: sourcing the writer, scanning
        # the phase receipt and building the argument array on the publisher
        # used to tax every successful terminal call after both durable locks
        # had already been released.
        (
            # shellcheck source=/dev/null
            source "$_rfs_batch_root/scripts/lib/defense_overhead_writer.sh"
            # report_publish belongs to the same formal generation consumed by
            # review_approval/cmd_complete.  report_id is a delivery identity,
            # not a review generation; use the shared canonical fingerprint
            # implementation so every downstream phase joins on one 64hex key.
            # Non-terminal or identity-incomplete reports remain explicitly
            # unobservable instead of fabricating a generation.
            # shellcheck source=/dev/null
            source "$_rfs_batch_root/scripts/lib/review_approval.sh"
            _rfs_publish_total_ms=$(( $(_rfs_mono_ms) - _rfs_wait_started ))
            _rfs_publish_verdict=PASS
            [ "$_rfs_batch_rc" -eq 0 ] || _rfs_publish_verdict=BLOCK
            _rfs_publish_generation=unknown
            case "$_rfs_batch_status" in
                completed|done)
                    _rfs_publish_generation="$(review_report_fingerprint "$_rfs_batch_report" 2>/dev/null || true)"
                    case "$_rfs_publish_generation" in
                        (*[!0-9a-f]*|'') _rfs_publish_generation=unknown ;;
                        (????????????????????????????????????????????????????????????????) ;;
                        (*) _rfs_publish_generation=unknown ;;
                    esac
                    ;;
            esac
            if [ "$_rfs_publish_generation" = unknown ]; then
                _rfs_publish_verdict=BLOCK
            fi
            _rfs_publish_cmd_id="${_rfs_batch_parent:-unknown}"
            _rfs_publish_metadata="{\"cmd_id\":\"${_rfs_publish_cmd_id}\",\"generation\":\"${_rfs_publish_generation}\"}"
            _rfs_telemetry_args=()
            while IFS=$'\t' read -r _rfs_tp _rfs_tw _; do
                case "$_rfs_tp" in
                    singleflight_wait|atomic_replace|atomic_parse_validate_serialize|atomic_flush_file_fsync|atomic_replace_syscall|terminal_meta|inbox_write|publish) ;;
                    *) continue ;;
                esac
                _rfs_telemetry_args+=(report_publish "$_rfs_tp" "${_rfs_tw#wall_ms=}" "$_rfs_publish_verdict" \
                    "report_publish:${_rfs_tp}:$$:${_rfs_wait_started}" "$_rfs_publish_metadata")
            done < "$_rfs_phase_receipt"
            _rfs_telemetry_args+=(report_publish publish_total "$_rfs_publish_total_ms" "$_rfs_publish_verdict" \
                "report_publish:total:$$:${_rfs_wait_started}" "$_rfs_publish_metadata")
            while [ "${#_rfs_telemetry_args[@]}" -ge 6 ]; do
                defense_overhead_write "${_rfs_telemetry_args[@]:0:6}" || true
                _rfs_telemetry_args=("${_rfs_telemetry_args[@]:6}")
            done
        ) >/dev/null 2>&1 &
    fi
    exit "$_rfs_batch_rc"
fi

if [ "$#" -lt 2 ]; then
    echo "Usage: bash scripts/report_field_set.sh <report_path> <dot.notation.key> <value>" >&2
    echo "  value が '-' ならstdinから読む。空文字列は ''(YAML空文字)として書込み。" >&2
    echo "Examples:" >&2
    echo "  bash scripts/report_field_set.sh queue/reports/hanzo_report_cmd_100.yaml results.AC1.status PASS" >&2
    echo "  echo 'long text' | bash scripts/report_field_set.sh queue/reports/hanzo_report_cmd_100.yaml results.AC1.notes -" >&2
    exit 1
fi

# SCRIPT_DIR: string ops instead of $(cd) subshells (~1.2ms savings on WSL2)
_rfs_self="${BASH_SOURCE[0]:-$0}"
[[ "$_rfs_self" != /* ]] && _rfs_self="$PWD/$_rfs_self"
SCRIPT_DIR="${_rfs_self%/scripts/report_field_set.sh}"
YAML_FIELD_SET_LOADED=0

ensure_yaml_field_set_loaded() {
    if [ "$YAML_FIELD_SET_LOADED" -eq 1 ]; then
        return 0
    fi
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
    YAML_FIELD_SET_LOADED=1
}

REPORT_PATH="$1"
DOT_KEY="$2"
VALUE="$3"

# cmd_karo_impl_report_field_set_telemetry_20260726: 単一キー経路の計装。
# 記録するのは2つだけ — 所要時間(wall_ms)と結果(PASS=書込み成功 / BLOCK=非0終了)。
# 記録しないもの: 値の中身・報告本文・BLOCKメッセージ本文(報告内容を台帳へ漏らさない)。
# 出力は既存台帳 logs/defense_overhead.jsonl (source=report_field_set)。新台帳は作らない。
if [ "${RFS_SINGLE_KEY_TELEMETRY:-1}" = "1" ] \
    && [ "${DEFENSE_OVERHEAD_ENABLED:-1}" = "1" ]; then
    _rfs_sk_mono_ms() {
        local _up _whole _frac
        read -r _up _ </proc/uptime
        _whole="${_up%%.*}"
        _frac="${_up#*.}000"
        _frac="${_frac:0:3}"
        printf '%s\n' "$((10#${_whole} * 1000 + 10#${_frac}))"
    }
    _rfs_sk_started="$(_rfs_sk_mono_ms)"
    _rfs_sk_emit() {
        local _rc="$?" _ms _key _verdict _ledger _ts
        # check_id は writer の許容文字集合へ丸める(値は含めない)。
        _key="${DOT_KEY//[^A-Za-z0-9_.:-]/_}"
        [ -n "$_key" ] || _key=unknown
        _ms=$(( $(_rfs_sk_mono_ms) - _rfs_sk_started ))
        if [ "$_rc" -eq 0 ]; then _verdict=PASS; else _verdict=BLOCK; fi
        # 追記は既存台帳 logs/defense_overhead.jsonl へ同一schemaで行う(新台帳は作らない)。
        # writer関数(defense_overhead_write)はイベント毎に python3 起動 + 台帳全走査の
        # 重複grepを伴い、この経路の実測で +50〜90ms/回だった。単一キー計装は event_id が
        # pid+開始時刻+key で構造的に一意なので重複検査は不要。ただし排他は既存writerと
        # 同じ ${ledger}.lock を取る(独自ロックだと共存中の writer と行が混ざる)。
        # 親は fork 1回(実測 ~1ms)だけ払い、flock待ちと書込みは子側で行う。
        _ledger="${DEFENSE_OVERHEAD_LEDGER:-$SCRIPT_DIR/logs/defense_overhead.jsonl}"
        [ -d "${_ledger%/*}" ] || return "$_rc"
        (
            # report/task identifiers make repeated commit_hash writes from one
            # report flow distinguishable without changing existing fields.
            # Read root scalars with shell builtins so telemetry remains off the
            # caller's measured critical path and does not add a YAML parse.
            _report_id=""
            _task_id=""
            while IFS= read -r _line; do
                case "$_line" in
                    report_id:*) _report_id="${_line#report_id:}" ;;
                    task_id:*) _task_id="${_line#task_id:}" ;;
                esac
                [ -n "$_report_id" ] && [ -n "$_task_id" ] && break
            done < "$REPORT_PATH"
            _report_id="${_report_id#"${_report_id%%[![:space:]]*}"}"
            _task_id="${_task_id#"${_task_id%%[![:space:]]*}"}"
            _report_id="${_report_id//[^A-Za-z0-9_.:-]/_}"
            _task_id="${_task_id//[^A-Za-z0-9_.:-]/_}"
            [ -n "$_report_id" ] || _report_id=unknown
            [ -n "$_task_id" ] || _task_id=unknown
            export TZ=UTC
            printf -v _ts '%(%Y-%m-%dT%H:%M:%S)T' -1
            exec 8>>"${_ledger}.lock" || exit 0
            flock -w "${DEFENSE_OVERHEAD_LOCK_TIMEOUT:-2}" 8 || exit 0
            printf '{"timestamp":"%s+00:00","source":"report_field_set","check_id":"%s","wall_ms":%s,"verdict":"%s","event_id":"report_field_set:%s:%s:%s:%s:%s","report_id":"%s","task_id":"%s"}\n' \
                "$_ts" "$_key" "$_ms" "$_verdict" "$$" "$_rfs_sk_started" "$_key" \
                "$_report_id" "$_task_id" "$_report_id" "$_task_id" >&9
        ) 9>>"$_ledger" </dev/null >/dev/null 2>&1 &
        disown 2>/dev/null || true
        return "$_rc"
    }
    trap '_rfs_sk_emit' EXIT
fi

# Historical skill guidance accidentally used:
#   report_field_set.sh <report> assumption_invalidation found false
# Keep the compatibility shim scoped to this field so the extra positional
# argument cannot silently affect unrelated writes.
if [ "$DOT_KEY" = "assumption_invalidation" ] && [ "${3:-}" = "found" ] && [ -n "${4:-}" ]; then
    DOT_KEY="assumption_invalidation.found"
    VALUE="$4"
fi

# Pattern1 fix: 空文字値を許可。$3未指定/空→YAML空文字列('')として書込み
if [ -z "$VALUE" ]; then
    VALUE="''"
fi

# Resolve to absolute path if relative
if [[ "$REPORT_PATH" != /* ]]; then
    REPORT_PATH="$SCRIPT_DIR/$REPORT_PATH"
fi

# A completed report is moved from queue/reports to archive/reports.  A stale
# caller that still holds the old active path must not recreate a partial YAML
# file via the legacy create-on-write behavior below.  Keep that legacy
# behavior for every other missing path: deploy_task normally creates report
# templates first, but older callers and isolated tests intentionally use this
# helper to create reports outside the canonical active directory.
if [ ! -e "$REPORT_PATH" ] && [[ "$REPORT_PATH" == "$SCRIPT_DIR/queue/reports/"* ]]; then
    _rfs_active_rel="${REPORT_PATH#"$SCRIPT_DIR/queue/reports/"}"
    if [[ "$_rfs_active_rel" != */* ]]; then
        _rfs_archive_candidates=()
        while IFS= read -r -d '' _rfs_candidate; do
            _rfs_archive_candidates+=("$_rfs_candidate")
        done < <(find "$SCRIPT_DIR/archive/reports" -type f -name "$_rfs_active_rel" -print0 2>/dev/null || true)
        if [ "${#_rfs_archive_candidates[@]}" -gt 0 ]; then
            echo "BLOCK: active report is missing but an archived report with the same basename exists; refusing to create a residual YAML." >&2
            echo "  requested active path: $REPORT_PATH" >&2
            for _rfs_candidate in "${_rfs_archive_candidates[@]}"; do
                echo "  candidate archive path: $_rfs_candidate" >&2
            done
            echo "  To update the canonical archived report, pass its archive path explicitly." >&2
            exit 1
        fi
    fi
fi

# Resolve the current task/cmd origin for the shorthand command when operators
# intentionally omit the value: `report_field_set.sh <report> origin`.
_report_field_set_resolve_cmd_origin() {
    python3 - "$REPORT_PATH" "$SCRIPT_DIR" <<'PY'
import glob
import os
import sys
import yaml

report_path = sys.argv[1]
repo_root = sys.argv[2]

def load_yaml(path):
    try:
        with open(path, encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return {}

def origin_from_entry(entry):
    if isinstance(entry, dict):
        origin = str(entry.get("origin", "") or "").strip()
        if origin:
            return origin
    return ""

def find_origin_in_doc(doc, cmd_id):
    if not cmd_id:
        return ""
    if isinstance(doc, dict):
        commands = doc.get("commands")
        if isinstance(commands, dict):
            found = origin_from_entry(commands.get(cmd_id))
            if found:
                return found
        found = origin_from_entry(doc.get(cmd_id))
        if found:
            return found
        cmd = doc.get("cmd")
        if isinstance(cmd, dict) and str(cmd.get("id", "") or "").strip() == cmd_id:
            found = origin_from_entry(cmd)
            if found:
                return found
        if str(doc.get("id", "") or "").strip() == cmd_id:
            return origin_from_entry(doc)
        for value in doc.values():
            if isinstance(value, dict) and str(value.get("id", "") or "").strip() == cmd_id:
                found = origin_from_entry(value)
                if found:
                    return found
    elif isinstance(doc, list):
        for item in doc:
            if isinstance(item, dict) and str(item.get("id", "") or "").strip() == cmd_id:
                found = origin_from_entry(item)
                if found:
                    return found
    return ""

def unquote_scalar(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        value = value[1:-1]
        if value and value[0] == "'":
            value = value.replace("''", "'")
    return value.strip()

def find_origin_in_text(path, cmd_id):
    if not cmd_id:
        return ""
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.readlines()
    except Exception:
        return ""
    cmd_re = f"{cmd_id}:"
    in_block = False
    block_indent = 0
    for line in lines:
        stripped = line.strip()
        if not in_block:
            if stripped == cmd_re or stripped.startswith(f"id: {cmd_id}"):
                in_block = True
                block_indent = len(line) - len(line.lstrip(" "))
            continue
        indent = len(line) - len(line.lstrip(" "))
        if stripped and not stripped.startswith("#") and indent <= block_indent and not stripped.startswith("origin:"):
            break
        if stripped.startswith("origin:"):
            return unquote_scalar(stripped.split(":", 1)[1])
    return ""

report = load_yaml(report_path)
worker = str(report.get("worker_id", "") or "").strip() if isinstance(report, dict) else ""
if not worker:
    base = os.path.basename(report_path)
    if "_report_" in base:
        worker = base.split("_report_", 1)[0]

task = {}
if worker:
    task_doc = load_yaml(os.path.join(repo_root, "queue", "tasks", f"{worker}.yaml"))
    task = task_doc.get("task", task_doc) if isinstance(task_doc, dict) else {}

candidate_ids = []
for candidate in (
    task.get("cmd_id") if isinstance(task, dict) else "",
    task.get("parent_cmd") if isinstance(task, dict) else "",
    report.get("parent_cmd") if isinstance(report, dict) else "",
):
    candidate = str(candidate or "").strip()
    if candidate and candidate not in candidate_ids:
        candidate_ids.append(candidate)

queue_doc = load_yaml(os.path.join(repo_root, "queue", "shogun_to_karo.yaml"))
queue_path = os.path.join(repo_root, "queue", "shogun_to_karo.yaml")
for cmd_id in candidate_ids:
    found = find_origin_in_doc(queue_doc, cmd_id)
    if not found:
        found = find_origin_in_text(queue_path, cmd_id)
    if found:
        print(found)
        sys.exit(0)
    for path in sorted(glob.glob(os.path.join(repo_root, "queue", "archive", "cmds", f"{cmd_id}*.yaml")), reverse=True):
        found = find_origin_in_doc(load_yaml(path), cmd_id)
        if not found:
            found = find_origin_in_text(path, cmd_id)
        if found:
            print(found)
            sys.exit(0)
PY
}

# Convenience command for causal-network reports.  Report templates store the
# backlink with lesson_candidate, but operators should not need to remember the
# nested path for the common write.  If the shorthand value is omitted, inherit
# the cmd origin from the worker task/report context when available.
if [ "$DOT_KEY" = "origin" ]; then
    if [ -z "$VALUE" ] || [ "$VALUE" = "''" ] || [ "$VALUE" = '""' ] || [ "$VALUE" = "null" ] || [ "$VALUE" = "None" ]; then
        _auto_origin="$(_report_field_set_resolve_cmd_origin 2>/dev/null || true)"
        if [ -n "$_auto_origin" ]; then
            VALUE="$_auto_origin"
        fi
    fi
    DOT_KEY="lesson_candidate.origin"
fi

LOCKFILE="${REPORT_PATH}.lock"

# Read stdin if value is "-"
STDIN_VALUE=""
USE_PYTHON=0
if [ "$VALUE" = "-" ]; then
    STDIN_VALUE="$(cat)"
    # Detect YAML structure (list/dict) → Python fallback for faithful preservation
    # bash fast-path: first non-whitespace char is [ { or - → list/dict
    _sv_fc=$(printf '%s' "$STDIN_VALUE" | tr -d ' \t\n' | cut -c1)
    if [[ "$_sv_fc" == "[" || "$_sv_fc" == "{" || "$_sv_fc" == "-" ]]; then
        VALUE="$STDIN_VALUE"
        USE_PYTHON=1
    elif [[ "$STDIN_VALUE" == *$'\n'* ]]; then
        # Multi-line text: awk cannot handle, use Python
        VALUE="$STDIN_VALUE"
        USE_PYTHON=1
    else
        VALUE="$STDIN_VALUE"
    fi
fi

# Direct argument multiline detection (non-stdin path)
if [[ "$VALUE" == *$'\n'* ]] && [ "$USE_PYTHON" -eq 0 ]; then
    USE_PYTHON=1
    STDIN_VALUE="$VALUE"
fi

# --- binary_checks共通バリデーション (DRY: full/per-AC統合) ---
# mode="full": binary_checks全体(dict of lists) / mode="per_ac": 単一AC(list of dicts)
_validate_binary_checks() {
    local mode="$1"
    local val="$2"
    python3 -c "
import yaml, sys
err = '''ERROR: binary_checks must be YAML list of dicts with result: yes/no.
  Correct: - {check: 'テスト全PASS', result: yes}
  Wrong:   'AC1: YES, AC2: NO'
  Wrong:   result: true (use 'yes' not true)
  Wrong:   result: PASS (use 'yes' not 'PASS')'''
mode = sys.argv[1]
try:
    data = yaml.load(sys.stdin.read(), Loader=yaml.BaseLoader)
except yaml.YAMLError:
    print(err, file=sys.stderr)
    sys.exit(1)
if isinstance(data, str):
    print(err, file=sys.stderr)
    sys.exit(1)
def check_items(items):
    if not isinstance(items, list):
        print(err, file=sys.stderr)
        sys.exit(1)
    for j, item in enumerate(items):
        if not isinstance(item, dict):
            continue
        r = str(item.get('result', '')).strip()
        if r and r.lower() not in ('yes', 'no', ''):
            print(err, file=sys.stderr)
            sys.exit(1)
if mode == 'full':
    if not isinstance(data, dict):
        print(err, file=sys.stderr)
        sys.exit(1)
    for ac_key, ac_val in data.items():
        check_items(ac_val)
else:
    check_items(data)
" "$mode" <<< "$val" || return 1
}

# A report may only become terminal after the task-requested variation matrix
# is filled.  SG-PRE33 already checked this during Gunshi review, but the two
# authoritative report entry points (verdict auto-complete and direct
# status=completed) previously ignored it, allowing an invalid completed
# report to exist until review time.
_validate_variation_completion_contract() {
    REPORT_PATH="$REPORT_PATH" python3 - <<'PY'
import os
import sys

import yaml

report_path = os.environ.get("REPORT_PATH", "")
if not report_path or not os.path.exists(report_path):
    raise SystemExit(0)

with open(report_path, encoding="utf-8") as report_file:
    report = yaml.safe_load(report_file) or {}
if not isinstance(report, dict):
    raise SystemExit(0)

worker_id = str(report.get("worker_id") or "").strip()
parent_cmd = str(report.get("parent_cmd") or "").strip()
task_path = os.path.join(os.path.dirname(os.path.dirname(report_path)), "tasks", f"{worker_id}.yaml")
if not worker_id or not parent_cmd or not os.path.exists(task_path):
    raise SystemExit(0)

with open(task_path, encoding="utf-8") as task_file:
    raw_task = yaml.safe_load(task_file) or {}
task = raw_task.get("task", raw_task) if isinstance(raw_task, dict) else {}
if not isinstance(task, dict) or str(task.get("parent_cmd") or "").strip() != parent_cmd:
    raise SystemExit(0)

required_raw = task.get("variation_checks_required", False)
required = required_raw is True or str(required_raw).strip().lower() in {"1", "true", "yes", "on"}
if not required:
    raise SystemExit(0)

required_names = (
    "normal_pass",
    "quoted_or_heredoc",
    "linked_worktree",
    "parallel_or_respawn",
    "abnormal_exit",
)
checks = report.get("variation_checks")
missing = []
invalid = []
for name in required_names:
    item = checks.get(name) if isinstance(checks, dict) else None
    if not isinstance(item, dict):
        missing.append(name)
        continue
    raw_result = item.get("result", "")
    if isinstance(raw_result, bool):
        normalized = "yes" if raw_result else "no"
    else:
        normalized = str(raw_result or "").strip().strip("\"'").lower()
    if not normalized:
        missing.append(name)
    elif normalized not in {"yes", "no"}:
        invalid.append(name)

if missing or invalid:
    details = []
    if missing:
        details.append("未記入=" + ",".join(missing))
    if invalid:
        details.append("yes/no以外=" + ",".join(invalid))
    print(
        "BLOCK: variation_checks_required=true の完了前提未達 (" + "; ".join(details) + ")",
        file=sys.stderr,
    )
    print(
        "  先に report_field_set.sh <report> variation_checks.<name>.result yes|no を全5項目へ記入せよ",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY
}

# The lesson ID set is owned by report_gate_contract.py and is shared with
# cmd_complete_gate.sh and the Gunshi precheck. Apply that same contract at
# every direct terminal entry point before status bytes become visible.
_validate_lesson_feedback_completion_contract() {
    local task_file="${RFS_TASK_FILE_PATH:-}"
    if [ -z "$task_file" ]; then
        local worker_id task_root
        worker_id="$(REPORT_PATH="$REPORT_PATH" python3 - <<'PY'
import os, yaml
path = os.environ.get("REPORT_PATH", "")
try:
    data = yaml.safe_load(open(path, encoding="utf-8")) or {}
except (OSError, yaml.YAMLError):
    print("")
else:
    print(str(data.get("worker_id") or "").strip())
PY
)"
        task_root="${REPORT_FIELD_SET_TASK_ROOT:-}"
        if [ -z "$task_root" ]; then
            case "$REPORT_PATH" in
                */queue/reports/*)
                    task_root="${REPORT_PATH%%/queue/reports/*}"
                    ;;
                *)
                    # Reports outside queue/reports have no implicit task
                    # contract; never couple an isolated fixture to live state.
                    return 0
                    ;;
            esac
        fi
        [ -n "$worker_id" ] || return 0
        task_file="$task_root/queue/tasks/${worker_id}.yaml"
    fi
    [ -f "$task_file" ] || return 0
    [ -f "$REPORT_PATH" ] || return 0

    local lesson_contract_state=0
    python3 - "$task_file" <<'PY' || lesson_contract_state=$?
import sys, yaml
try:
    raw = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
except (OSError, yaml.YAMLError):
    raise SystemExit(2)
task = raw.get("task", raw) if isinstance(raw, dict) else {}
if not isinstance(task, dict):
    raise SystemExit(2)
raise SystemExit(0 if "assigned_lesson_ids" in task or "related_lessons" in task else 1)
PY
    case "$lesson_contract_state" in
        0) ;;
        1) return 0 ;;
        *)
            echo "BLOCK: lesson_feedback_set task declaration could not be read: $task_file" >&2
            return 1
            ;;
    esac

    python3 "$SCRIPT_DIR/scripts/lib/report_gate_contract.py" \
        lesson-feedback-set "$task_file" "$REPORT_PATH"
}

# --- GP-072: Pre-write field value validation (Level 4 BLOCK) ---
# 書込み前にフィールド値の妥当性を検証。不正値はBLOCKして忍者に即フィードバック。
# GP-072c2: per-item writes, dict→list conversion, verdict pre-conditions
# GP-072c3: lessons_useful id UNKNOWN/null BLOCK, template mandatory fields
# GP-072c4: binary_checks all-result-empty verdict BLOCK
_validate_field_value() {
    local dot_key="$1"
    local val="$2"
    local field="${dot_key%%.*}"

    case "$field" in
        result)
            if [[ "$dot_key" == "result.summary" ]]; then
                local clean_summary
                clean_summary="$(printf '%s' "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                if [[ -z "$clean_summary" || "$clean_summary" == "''" || "$clean_summary" == '\"\"' || "$clean_summary" == *FILL_THIS* ]]; then
                    echo "BLOCK: result.summary は実値必須。空文字/FILL_THIS残存は禁止（有効値の自動補完もしない）。" >&2
                    echo "  正: bash scripts/report_field_set.sh <report> result.summary \"実施内容と検証結果の1行要約\"" >&2
                    return 1
                fi
            fi
            ;;
        files_modified)
            if [[ "$dot_key" == "files_modified" ]]; then
                # files_modified is normalized and path-validated together in
                # _autofix_field_value.  Keeping a second yaml.safe_load here
                # charged every write another Python process without adding a
                # distinct check.
                return 0
            fi
            ;;
        lessons_useful)
            # Full field write: must be YAML list, not dict/string/empty
            if [[ "$dot_key" == "lessons_useful" ]]; then
                python3 -c "
import yaml, sys
data = yaml.safe_load(sys.stdin.read())
if not isinstance(data, list):
    print('ERROR: lessons_useful must be YAML list format.', file=sys.stderr)
    print(\"  Correct: - {id: L001, useful: true, reason: '理由'}\", file=sys.stderr)
    print(\"  Wrong:   {0: {id: L001}, 1: {id: L002}}\", file=sys.stderr)
    print(\"  Wrong:   'L001をreviewで使用した'\", file=sys.stderr)
    sys.exit(1)
for i, item in enumerate(data):
    if not isinstance(item, dict):
        print(f'BLOCK: lessons_useful[{i}] はdict必須。受信: {type(item).__name__}', file=sys.stderr)
        sys.exit(1)
    if 'id' not in item or not str(item['id']).strip():
        print(f'BLOCK: lessons_useful[{i}].id が空。テンプレート注入済みIDを使え', file=sys.stderr)
        sys.exit(1)
    id_val = str(item['id']).strip()
    if id_val in ('UNKNOWN', 'unknown', 'null', 'FILL_THIS'):
        print(f'BLOCK: lessons_useful[{i}].id=\"{id_val}\" は不正。L074等の実IDを使え', file=sys.stderr)
        sys.exit(1)
    if 'useful' in item and not isinstance(item['useful'], bool):
        print(f'BLOCK: lessons_useful[{i}].useful はbool必須。受信: {item[\"useful\"]}', file=sys.stderr)
        sys.exit(1)
" <<< "$val" || return 1
                # D0: フルフィールド書込み時に既存件数より少なければBLOCK(上書き消去防止)
                local _existing_count _new_count
                # shellcheck disable=SC2154  # $file is set in outer scope
                _existing_count=$(python3 -c "
import yaml, sys
try:
    with open(sys.argv[1]) as f: d = yaml.safe_load(f) or {}
    lu = d.get('lessons_useful', [])
    print(len(lu) if isinstance(lu, list) else 0)
except: print(0)
" "$file" 2>/dev/null || echo 0)
                _new_count=$(python3 -c "
import yaml, sys
d = yaml.safe_load(sys.stdin.read())
print(len(d) if isinstance(d, list) else 0)
" <<< "$val" 2>/dev/null || echo 0)
                if (( _existing_count > 0 && _new_count < _existing_count )); then
                    echo "BLOCK: lessons_useful全体上書きで${_existing_count}件→${_new_count}件に削減。テンプレート注入済み教訓が消える。個別書き込み(lessons_useful.0.useful等)を使え" >&2
                    return 1
                fi
            # GP-072c3: Per-item id write (e.g., lessons_useful.0.id)
            elif [[ "$dot_key" =~ ^lessons_useful\.[0-9]+\.id$ ]]; then
                local id_val
                id_val=$(echo "$val" | xargs)
                id_val="${id_val//\"/}"
                if [[ -z "$id_val" ]] || [[ "$id_val" == "UNKNOWN" ]] || [[ "$id_val" == "unknown" ]] || [[ "$id_val" == "null" ]]; then
                    echo "BLOCK: lessons_useful id=\"$val\" は不正。テンプレートに注入済みのID(L074等)を使え。UNKNOWNは禁止。" >&2
                    return 1
                fi
            # P5 fix: lessons_useful.{non-numeric}.field → IDベースアクセスをBLOCK+正しい方法を案内
            elif [[ "$dot_key" =~ ^lessons_useful\.[^0-9] ]]; then
                local bad_key="${dot_key#lessons_useful.}"
                echo "BLOCK: lessons_useful.${bad_key} は不正。lessons_usefulはYAML listのためindex指定が必要。" >&2
                echo "  正: lessons_useful.0.reason / lessons_useful.1.useful" >&2
                echo "  誤: lessons_useful.L636.reason (IDベースアクセスは不可)" >&2
                return 1
            fi
            ;;
        memory_references)
            if [[ "$dot_key" == "memory_references" ]]; then
                python3 -c "
import yaml, sys
data = yaml.safe_load(sys.stdin.read())
if not isinstance(data, list):
    print('ERROR: memory_references must be YAML list format.', file=sys.stderr)
    print(\"  Correct: - {id: MEM001, source: semantic_search, query: '...', used: false, useful: false, reason: '...'}\", file=sys.stderr)
    sys.exit(1)
for i, item in enumerate(data):
    if not isinstance(item, dict):
        print(f'BLOCK: memory_references[{i}] はdict必須。受信: {type(item).__name__}', file=sys.stderr)
        sys.exit(1)
    for key in ('id', 'source', 'query', 'used', 'useful', 'reason'):
        if key not in item:
            print(f'BLOCK: memory_references[{i}].{key} が欠落', file=sys.stderr)
            sys.exit(1)
    for key in ('id', 'source', 'query'):
        if not str(item.get(key, '')).strip() or str(item.get(key, '')).strip() == 'FILL_THIS':
            print(f'BLOCK: memory_references[{i}].{key} が空またはplaceholder', file=sys.stderr)
            sys.exit(1)
    if not isinstance(item.get('used'), bool) or not isinstance(item.get('useful'), bool):
        print(f'BLOCK: memory_references[{i}].used/useful はbool必須', file=sys.stderr)
        sys.exit(1)
" <<< "$val" || return 1
            elif [[ "$dot_key" =~ ^memory_references\.[0-9]+\.(used|useful)$ ]]; then
                local mr_bool
                mr_bool="$(echo "$val" | xargs)"
                if [[ "$mr_bool" != "true" && "$mr_bool" != "false" ]]; then
                    echo "BLOCK: ${dot_key} は true/false のみ。受信: $val" >&2
                    return 1
                fi
            elif [[ "$dot_key" =~ ^memory_references\.[0-9]+\.reason$ ]]; then
                if [[ "$(echo "$val" | xargs)" == "FILL_THIS" ]]; then
                    echo "BLOCK: ${dot_key} に FILL_THIS は不可。参照した/しなかった理由を記入せよ" >&2
                    return 1
                fi
            elif [[ "$dot_key" =~ ^memory_references\.[^0-9] ]]; then
                local bad_key="${dot_key#memory_references.}"
                echo "BLOCK: memory_references.${bad_key} は不正。memory_referencesはYAML listのためindex指定が必要。" >&2
                echo "  正: memory_references.0.used / memory_references.0.reason" >&2
                return 1
            fi
            ;;
        verified_existing_dependency)
            if [[ "$dot_key" == "verified_existing_dependency" ]]; then
                python3 -c "
import yaml, sys
data = yaml.safe_load(sys.stdin.read())
if not isinstance(data, list):
    print('ERROR: verified_existing_dependency must be YAML list format.', file=sys.stderr)
    print(\"  Correct: - {path: scripts/foo.sh, reason: '既存依存として参照のみ', checked_not_modified: true}\", file=sys.stderr)
    sys.exit(1)
for i, item in enumerate(data):
    if not isinstance(item, dict):
        print(f'BLOCK: verified_existing_dependency[{i}] はdict必須。受信: {type(item).__name__}', file=sys.stderr)
        sys.exit(1)
    path = str(item.get('path', '') or '').strip()
    reason = str(item.get('reason', '') or '').strip()
    if not path or path == 'FILL_THIS':
        print(f'BLOCK: verified_existing_dependency[{i}].path が空またはplaceholder', file=sys.stderr)
        sys.exit(1)
    if '/' not in path:
        print(f'BLOCK: verified_existing_dependency[{i}].path はrepo相対パス形式必須。受信: {path}', file=sys.stderr)
        sys.exit(1)
    if not reason or reason == 'FILL_THIS':
        print(f'BLOCK: verified_existing_dependency[{i}].reason が空またはplaceholder', file=sys.stderr)
        sys.exit(1)
    if item.get('checked_not_modified') is not True:
        print(f'BLOCK: verified_existing_dependency[{i}].checked_not_modified は true 必須', file=sys.stderr)
        sys.exit(1)
" <<< "$val" || return 1
            elif [[ "$dot_key" =~ ^verified_existing_dependency\.[0-9]+\.checked_not_modified$ ]]; then
                local ved_bool
                ved_bool="$(echo "$val" | xargs)"
                if [[ "$ved_bool" != "true" ]]; then
                    echo "BLOCK: ${dot_key} は true のみ。既存依存は変更なし確認済みの場合だけ宣言せよ。受信: $val" >&2
                    return 1
                fi
            elif [[ "$dot_key" =~ ^verified_existing_dependency\.[0-9]+\.(path|reason)$ ]]; then
                if [[ "$(echo "$val" | xargs)" == "FILL_THIS" || -z "$(echo "$val" | xargs)" ]]; then
                    echo "BLOCK: ${dot_key} に空値/FILL_THIS は不可" >&2
                    return 1
                fi
            elif [[ "$dot_key" =~ ^verified_existing_dependency\.[^0-9] ]]; then
                local bad_key="${dot_key#verified_existing_dependency.}"
                echo "BLOCK: verified_existing_dependency.${bad_key} は不正。verified_existing_dependencyはYAML listのためindex指定が必要。" >&2
                echo "  正: verified_existing_dependency.0.path / verified_existing_dependency.0.reason / verified_existing_dependency.0.checked_not_modified" >&2
                return 1
            fi
            ;;
        binary_checks)
            # Full-field write validation (GP-072 binary_checks型バリデーション)
            # BaseLoader使用: yes/noを文字列として保持し true/falseと区別する
            if [[ "$dot_key" == "binary_checks" ]]; then
                _validate_binary_checks "full" "$val" || return 1
            # GP-072c2: Per-AC write (e.g., binary_checks.AC1) — only 2-level depth
            elif [[ "$dot_key" == binary_checks.AC* ]] && [[ "$dot_key" != *.*.* ]]; then
                _validate_binary_checks "per_ac" "$val" || return 1
            elif [[ "$dot_key" =~ ^binary_checks\.[^.]+\.[0-9]+\.result$ ]]; then
                local bc_result
                bc_result="${val%\"}"
                bc_result="${bc_result#\"}"
                bc_result="${bc_result%\'}"
                bc_result="${bc_result#\'}"
                bc_result="$(echo "$bc_result" | xargs)"
                if [[ -n "$bc_result" && "$bc_result" != "yes" && "$bc_result" != "no" ]]; then
                    echo "BLOCK: binary_checks result は yes/no のみ。受信: $val" >&2
                    return 1
                fi
            fi
            ;;
        self_gate_check)
            if [[ "$dot_key" == "self_gate_check" ]]; then
                echo "BLOCK: self_gate_check へのトップレベル書込みは禁止。dict構造を維持するため dot notation を使え。" >&2
                echo "  dict形式で再入力せよ。必須: lesson_ref / lesson_candidate / status_valid / purpose_fit" >&2
                echo "  正: self_gate_check.lesson_ref PASS" >&2
                echo "  誤: self_gate_check PASS" >&2
                return 1
            fi
            if [[ ! "$dot_key" =~ ^self_gate_check\.(lesson_ref|lesson_candidate|status_valid|purpose_fit)$ ]]; then
                echo "BLOCK: self_gate_check の未知キーは禁止。必須キーのみ使え: lesson_ref / lesson_candidate / status_valid / purpose_fit" >&2
                echo "  受信: $dot_key" >&2
                return 1
            fi
            if [[ "$val" != "PASS" ]] && [[ "$val" != "FAIL" ]]; then
                echo "BLOCK: self_gate_check は PASS/FAIL のみ。受信: $val" >&2
                return 1
            fi
            ;;
        semantic_validation)
            # LG048 D0根治(2026-08-09): semantic_validation.resultに散文を書く忍者パターンが
            # 4cmd(gist_reorder/cmd_4239/cmd_4240/cmd_4241)で繰り返し発生。
            # report_field_set.sh経由の書込み時にPASS/FAILリテラルを強制し、散文をBLOCKする。
            if [[ "$dot_key" == "semantic_validation.result" ]]; then
                local sv_result
                sv_result="$(echo "$val" | xargs)"
                if [[ "$sv_result" != "PASS" && "$sv_result" != "FAIL" ]]; then
                    echo "BLOCK: semantic_validation.result は PASS/FAIL のみ。散文は不可(LG048)。受信: $val" >&2
                    return 1
                fi
            fi
            ;;
        lesson_candidate)
            if [[ "$dot_key" == "lesson_candidate" ]]; then
                python3 -c "
import yaml, sys
data = yaml.safe_load(sys.stdin.read())
if not isinstance(data, dict):
    print(f'BLOCK: lesson_candidate はdict形式必須。受信: {type(data).__name__}', file=sys.stderr)
    sys.exit(1)
found = data.get('found')
found_s = str(found).strip().lower()
if found_s == 'true':
    missing = [field for field in ('title', 'detail', 'project') if not str(data.get(field, '')).strip()]
    if missing:
        print(f'BLOCK: lesson_candidate.found=true だが必須フィールド欠落: {\", \".join(missing)}', file=sys.stderr)
        print(\"  Correct: {found: true, title: '...', detail: '...', project: infra}\", file=sys.stderr)
        sys.exit(1)
elif found_s == 'false':
    reason = str(data.get('no_lesson_reason', '')).strip()
    if not reason or reason == 'FILL_THIS':
        print('BLOCK: lesson_candidate.found=false だが no_lesson_reason が空またはplaceholder', file=sys.stderr)
        print(\"  Correct: {found: false, no_lesson_reason: '既知教訓で被覆済み'}\", file=sys.stderr)
        sys.exit(1)
" <<< "$val" || return 1
                # found=true時にno_lesson_reasonが残っていれば自動消去（意味矛盾の正規化）
                if [[ "$val" == *"found: true"* ]] && [[ "$val" == *"no_lesson_reason:"* ]]; then
                    local _nlr
                    _nlr=$(echo "$val" | grep -oP 'no_lesson_reason:\s*\K.+' || true)
                    if [[ -n "$_nlr" && "$_nlr" != "''" && "$_nlr" != '""' ]]; then
                        echo "INFO: found=true のため no_lesson_reason を自動消去" >&2
                        bash "$SCRIPT_DIR/lib/yaml_field_set.sh" "$report" "$block_id" "lesson_candidate.no_lesson_reason" "" 2>/dev/null || true
                    fi
                fi
            fi
            ;;
        assumption_invalidation)
            if [[ "$dot_key" == "assumption_invalidation" ]]; then
                python3 -c "
import yaml, sys
data = yaml.safe_load(sys.stdin.read())
if not isinstance(data, dict):
    print(f'BLOCK: assumption_invalidation はdict形式必須。受信: {type(data).__name__}', file=sys.stderr)
    sys.exit(1)
for field in ('found', 'affected_cmds', 'detail'):
    if field not in data:
        print(f'BLOCK: assumption_invalidation.{field} が欠落', file=sys.stderr)
        sys.exit(1)
found_s = str(data.get('found', '')).strip().lower()
if found_s == 'true':
    detail = str(data.get('detail', '') or '').strip()
    affected_cmds = data.get('affected_cmds', [])
    if not detail:
        print('BLOCK: assumption_invalidation.found=true だが detail が空', file=sys.stderr)
        sys.exit(1)
    if not isinstance(affected_cmds, list) or len(affected_cmds) == 0:
        print('BLOCK: assumption_invalidation.found=true だが affected_cmds が空', file=sys.stderr)
        sys.exit(1)
" <<< "$val" || return 1
            elif [[ "$dot_key" == "assumption_invalidation.found" ]] && [[ "$val" =~ ^([Tt][Rr][Uu][Ee]|true|TRUE|yes|YES)$ ]]; then
                REPORT_PATH="$REPORT_PATH" python3 -c "
import json, os, sys, yaml
rp = os.environ.get('REPORT_PATH', '')
if not rp or not os.path.exists(rp):
    print('BLOCK: assumption_invalidation.found=true は detail/affected_cmds 記入後に実行せよ', file=sys.stderr)
    sys.exit(1)
with open(rp) as f:
    data = yaml.safe_load(f) or {}
ai = data.get('assumption_invalidation', {})
if not isinstance(ai, dict):
    print('BLOCK: assumption_invalidation.found=true は既存dictが必要', file=sys.stderr)
    sys.exit(1)
detail = str(ai.get('detail', '') or '').strip()
affected_cmds = ai.get('affected_cmds', [])
if not detail:
    print('BLOCK: assumption_invalidation.found=true だが detail が空。先に assumption_invalidation.detail を記入せよ', file=sys.stderr)
    sys.exit(1)
if not isinstance(affected_cmds, list) or len(affected_cmds) == 0:
    print('BLOCK: assumption_invalidation.found=true だが affected_cmds が空。先に assumption_invalidation.affected_cmds を記入せよ', file=sys.stderr)
    sys.exit(1)
" || return 1
            fi
            ;;
        knowledge_candidate)
            # GP-126: knowledge_candidate validation (事実データ循環)
            if [[ "$dot_key" == "knowledge_candidate" ]]; then
                python3 -c "
import yaml, sys
data = yaml.safe_load(sys.stdin.read())
if not isinstance(data, dict):
    print(f'BLOCK: knowledge_candidate はdict形式必須。受信: {type(data).__name__}', file=sys.stderr)
    sys.exit(1)
found = data.get('found', False)
if found is True:
    items = data.get('items', [])
    if not isinstance(items, list) or len(items) == 0:
        print('BLOCK: knowledge_candidate.found=true だがitemsが空。発見した事実を記入せよ', file=sys.stderr)
        print('  items:', file=sys.stderr)
        print(\"    - fact: '発見した事実を1文で'\", file=sys.stderr)
        print(\"      source: '確認元ファイル/行'\", file=sys.stderr)
        sys.exit(1)
    for i, item in enumerate(items):
        if not isinstance(item, dict):
            print(f'BLOCK: knowledge_candidate.items[{i}] はdict必須', file=sys.stderr)
            sys.exit(1)
        if not str(item.get('fact', '')).strip():
            print(f'BLOCK: knowledge_candidate.items[{i}].fact が空', file=sys.stderr)
            sys.exit(1)
" <<< "$val" || return 1
            fi
            ;;
        status)
            # Commit check is a completion precondition.  Blocking at write-time
            # prevents the common bad loop: status=completed -> report gate FAIL
            # -> operator fixes the report after already declaring completion.
            if [[ "$dot_key" == "status" ]]; then
                local status_val
                status_val="${val%\"}"
                status_val="${status_val#\"}"
                status_val="${status_val%\'}"
                status_val="${status_val#\'}"
                status_val="$(echo "$status_val" | xargs)"
                if [[ "$status_val" == "completed" || "$status_val" == "done" || "$status_val" == "failed" ]]; then
                    _validate_lesson_feedback_completion_contract || return 1
                    _validate_variation_completion_contract || return 1
                    REPORT_PATH="$REPORT_PATH" python3 -c "
import os
import sys
import yaml

rp = os.environ.get('REPORT_PATH', '')
if not rp or not os.path.exists(rp):
    sys.exit(0)
with open(rp, encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
bc = data.get('binary_checks', {})
commit_checks = bc.get('commit') if isinstance(bc, dict) else None
if not commit_checks:
    sys.exit(0)
if not isinstance(commit_checks, list):
    print('BLOCK: binary_checks.commit がlistではない。report templateを修復せよ', file=sys.stderr)
    sys.exit(1)
missing = []
for i, item in enumerate(commit_checks):
    if not isinstance(item, dict):
        missing.append(str(i))
        continue
    raw_result = item.get('result', '')
    if raw_result is True:
        result = 'yes'
    elif raw_result is False:
        result = 'no'
    else:
        result = str(raw_result or '').strip().strip('\"\\'').lower()
    if result != 'yes':
        missing.append(str(i))
if missing:
    print('BLOCK: commit check未完了のまま status=completed は禁止。先にgit commitし binary_checks.commit.*.result を yes にせよ', file=sys.stderr)
    print('  例: bash scripts/report_field_set.sh <report> binary_checks.commit.0.result yes', file=sys.stderr)
    sys.exit(1)
" || return 1
                fi
            fi
            ;;
        commit_hash)
            # GP-258: commit_hash 40文字フルhex検証 (Level 4 BLOCK)
            # 根因: 忍者手動記入で短縮hash→gate_report_format FAIL 10件/324回(3.1%)
            if [[ "$dot_key" == "commit_hash" ]]; then
                local clean_val
                clean_val="$(echo "$val" | xargs)"
                if [[ ! "$clean_val" =~ ^[0-9a-f]{40}$ ]] && ! REPORT_PATH="$REPORT_PATH" PROJECT_ROOT="$SCRIPT_DIR" COMMIT_IDENTITY="$clean_val" python3 - <<'PY'
import os, pathlib, sys, yaml
sys.path.insert(0, str(pathlib.Path(os.environ['PROJECT_ROOT']) / 'scripts' / 'lib'))
from report_commit_identity import valid_commit_identity
report = yaml.safe_load(open(os.environ['REPORT_PATH'], encoding='utf-8')) or {}
sys.exit(0 if valid_commit_identity(os.environ['COMMIT_IDENTITY'], report, pathlib.Path(os.environ['PROJECT_ROOT'])) else 1)
PY
                then
                    echo "BLOCK: commit_hash は40文字フルhex、または明示no-commitかつqueue/logsのみのno-code-change必須。受信: '$clean_val'" >&2
                    echo "  正: git rev-parse HEAD で取得した40文字 (例: a1b2c3d4...)" >&2
                    echo "  誤: 短縮hash(8文字等)、根拠なしno-code-change、source/config/docs混在" >&2
                    return 1
                fi
            fi
            ;;
        verdict)
            # GP-072c2+c3+c4: verdict書込み時に前提条件チェック
            if [[ "$dot_key" == "verdict" ]] && [[ "$val" == "PASS" || "$val" == "FAIL" || "$val" == "PASS_NO_IMPROVEMENT" ]]; then
                _validate_variation_completion_contract || return 1
                local _normalized_verdict
                if ! _normalized_verdict=$(REPORT_PATH="$REPORT_PATH" FIELD_VAL="$val" python3 -c "
import yaml, sys, os
rp = os.environ.get('REPORT_PATH', '')
if not rp or not os.path.exists(rp):
    print(os.environ.get('FIELD_VAL', ''), end='')
    sys.exit(0)
with open(rp) as f:
    data = yaml.safe_load(f) or {}
issues = []
# GP-072c3: Template mandatory fields
for mf in ('worker_id', 'parent_cmd', 'ac_version_read'):
    v = data.get(mf)
    if not v or str(v).strip() in ('', 'null', 'None'):
        issues.append(f'{mf} が空。テンプレートの値を保持せよ')
# P8 fix: report filename と parent_cmd の整合性チェック
_pcmd = str(data.get('parent_cmd', '')).strip()
if _pcmd and rp:
    import os as _os
    _basename = _os.path.basename(rp)  # e.g. hayate_report_cmd_2073.yaml
    if _pcmd and _pcmd not in _basename:
        issues.append(f'parent_cmd={_pcmd} がreportファイル名 {_basename} に含まれない。テンプレート再利用時のparent_cmd更新漏れの可能性')
# GP-072c2: result.summary not empty
result = data.get('result', {})
if isinstance(result, dict):
    s = str(result.get('summary', '')).strip()
    if not s:
        issues.append('result.summary が空。作業内容を記述せよ')
# GP-072c2: lesson_candidate.found=false requires no_lesson_reason
lc = data.get('lesson_candidate', {})
if isinstance(lc, dict) and str(lc.get('found', '')).lower() == 'false':
    nlr = str(lc.get('no_lesson_reason', '')).strip()
    if not nlr:
        issues.append('lesson_candidate.found=false だが no_lesson_reason が空')
# P7 fix: assumption_invalidation必須フィールドガード
ai = data.get('assumption_invalidation', {})
if isinstance(ai, dict):
    ai_found = str(ai.get('found', '')).lower()
    if ai_found == 'true':
        ai_detail = str(ai.get('detail', '')).strip()
        ai_cmds = ai.get('affected_cmds', [])
        if not ai_detail:
            issues.append('assumption_invalidation.found=true だが detail が空')
        if not ai_cmds or (isinstance(ai_cmds, list) and len(ai_cmds) == 0):
            issues.append('assumption_invalidation.found=true だが affected_cmds が空')
# GP-072c2: lessons_useful items must have non-empty reason
lu = data.get('lessons_useful', [])
if isinstance(lu, list):
    for i, item in enumerate(lu):
        if isinstance(item, dict):
            r = str(item.get('reason', '')).strip()
            if not r:
                issues.append(f'lessons_useful[{i}].reason が空')
# GP-072c5: binary_checks に 'no' があるのに verdict=PASS は矛盾 → 自動FAIL化
# 真因: フィールド間整合性制約がなく矛盾状態を作れた(なぜなぜ7回 2026-04-21)
# 原理: 間違える余地がない構造。gateで止めるのではなく書込み時に矛盾を不可能にする
bc = data.get('binary_checks', {})
verdict_val = os.environ.get('FIELD_VAL', '')
has_no = False
if isinstance(bc, dict) and bc and verdict_val in ('PASS', 'PASS_NO_IMPROVEMENT'):
    for ac_key, ac_val in bc.items():
        if isinstance(ac_val, list):
            for item in ac_val:
                if isinstance(item, dict) and str(item.get('result', '')).strip().lower() == 'no':
                    has_no = True
                    break
        if has_no:
            break
# GP-072c4: binary_checks results must not be all empty
# P4 fix: assigned_acs がある場合、担当外ACの空resultは除外
import glob
_assigned_acs = set()
_task_files = glob.glob(os.path.join(os.path.dirname(rp), '..', 'tasks', '*.yaml'))
for _tf in _task_files:
    try:
        with open(_tf) as _tfh:
            _td = yaml.safe_load(_tfh) or {}
        _task = _td.get('task', _td)
        _aa = str(_task.get('assigned_acs', '') or '').strip()
        _pcmd = str(_task.get('parent_cmd', '') or '').strip()
        _rpcmd = str(data.get('parent_cmd', '') or '').strip()
        if _aa and _pcmd == _rpcmd:
            _assigned_acs = {a.strip() for a in _aa.replace(',', ' ').split()}
            break
    except Exception:
        pass
if isinstance(bc, dict) and bc:
    total_checks = 0
    empty_results = 0
    for ac_key, ac_val in bc.items():
        if _assigned_acs and ac_key != 'commit' and ac_key not in _assigned_acs:
            continue  # P4: 担当外ACはスキップ
        if isinstance(ac_val, list):
            for item in ac_val:
                if isinstance(item, dict) and 'check' in item:
                    total_checks += 1
                    r = str(item.get('result', '')).strip()
                    if not r or r == '\"\"':
                        empty_results += 1
    if total_checks > 0 and empty_results == total_checks:
        issues.append(f'binary_checks {total_checks}件全てのresultが空。yes/noを記入してからverdictを書け')
    elif total_checks > 0 and empty_results > 0:
        issues.append(f'binary_checks {empty_results}/{total_checks}件のresultが未記入。全件yes/noを記入してからverdictを書け')
if issues:
    for iss in issues:
        print(f'BLOCK: {iss}', file=sys.stderr)
    sys.exit(1)
print('FAIL' if has_no else verdict_val, end='')
"); then
                    return 1
                fi
                if [[ "$_normalized_verdict" != "$val" ]]; then
                    echo "★ verdict自動修正: PASS→FAIL(bc:noあり。矛盾状態を作れない構造)" >&2
                    _val_input="$_normalized_verdict"
                    VALUE="$_normalized_verdict"
                    if [ -n "$STDIN_VALUE" ]; then STDIN_VALUE="$_normalized_verdict"; fi
                fi
            fi
            ;;
    esac
    return 0
}

# --- Completed report immutability guard (cmd_karo_hotfix_report_completed_immutability) ---
# fingerprint = 報告ファイル全体のsha256 (scripts/lib/review_approval.sh
# review_report_fingerprint)。status completed/done後にどのフィールドを
# 書き換えても、軍師LGTM/家老ACCEPTが束縛したfingerprintと無言で乖離する。
# 個別フィールドのallowlistではなく、書込み入口そのものをfail-closedで塞ぐ。
# 抜け道は2つのみ:
#   (1) status → revision_requested への明示遷移
#       (scripts/review_approval.sh のRCパスが使う既存の正規ルート)
#   (2) 既存値と完全一致する冪等write
#       (verdict→completed自動遷移の再入・重複呼び出しを壊さないため)
_report_field_set_completed_guard() {
    local dot_key="$1"
    local val="$2"

    [ -f "$REPORT_PATH" ] || return 0

    # fingerprint/review approval (scripts/lib/review_approval.sh review_validate_report)
    # only ever binds to reports living under queue/reports/ — archived reports
    # (moved to archive/reports/ after GATE CLEAR) have no live approval to
    # invalidate, and existing tooling legitimately rewrites them post-archive
    # (see test_report_field_set_archive_guard.bats). Scope the guard to the
    # canonical active directory so archived-report edits stay unaffected.
    case "$REPORT_PATH" in
        "$SCRIPT_DIR/queue/reports/"*) ;;
        *) return 0 ;;
    esac

    # commit_hash速度最適化(cmd_karo_hotfix_hot_script_report_commit_hash_20260728):
    # このguardはstatusがcompleted/doneでない限りsys.exit(0)で即抜けるだけ(下のPython参照)。
    # そのためだけに毎回yaml.safe_loadで全量再parseするのは恒常課税(commit_hash 1回=最低1回の
    # 全量再parse)。statusは常にroot直下のscalarなので `^status:` grepで同じ早期終了を安価に
    # 判定できる。completed/doneの時だけ本来のPython経路(fingerprint不変性チェック)へ進む。
    local _guard_status
    _guard_status="$(grep -m1 '^status:' "$REPORT_PATH" 2>/dev/null | sed 's/^status:[[:space:]]*//' | tr -d '\r"'"'"'')"
    case "$_guard_status" in
        completed|done) ;;
        *) return 0 ;;
    esac

    REPORT_PATH="$REPORT_PATH" DOT_KEY="$dot_key" NEW_VALUE="$val" python3 -c "
import os, re, sys, yaml

rp = os.environ.get('REPORT_PATH', '')
dot_key = os.environ.get('DOT_KEY', '')
new_raw = os.environ.get('NEW_VALUE', '')

try:
    with open(rp, encoding='utf-8') as f:
        data = yaml.safe_load(f) or {}
except Exception:
    sys.exit(0)  # unreadable/corrupt report: not this guard's concern

if not isinstance(data, dict):
    sys.exit(0)

cur_status = str(data.get('status', '') or '').strip()
if cur_status not in ('completed', 'done'):
    sys.exit(0)  # guard only applies once a report has reached a terminal state

try:
    new_parsed = yaml.safe_load(new_raw)
except yaml.YAMLError:
    new_parsed = new_raw

# (1) explicit unlock: status -> revision_requested is always allowed
if dot_key == 'status' and new_parsed == 'revision_requested':
    sys.exit(0)

# (2) idempotent same-value write (any field) must not be blocked
def split_path(key):
    parts = []
    for seg in key.split('.'):
        m = re.match(r'^(.+)\[(\d+)\]\$', seg)
        if m:
            parts.append(m.group(1))
            parts.append(m.group(2))
        else:
            parts.append(seg)
    return parts

def get_nested(d, keys):
    cur = d
    for k in keys:
        if isinstance(cur, dict):
            if k not in cur:
                return None, False
            cur = cur[k]
        elif isinstance(cur, list):
            try:
                idx = int(k)
            except ValueError:
                return None, False
            if not (0 <= idx < len(cur)):
                return None, False
            cur = cur[idx]
        else:
            return None, False
    return cur, True

existing, found = get_nested(data, split_path(dot_key))
if found and existing == new_parsed:
    sys.exit(0)

print(f'BLOCK: report status={cur_status} は内容変更禁止(fingerprint不変性。review_report_fingerprintを参照)。', file=sys.stderr)
print(f'  対象キー: {dot_key}', file=sys.stderr)
print('  修正するには先に revision_requested へ明示遷移せよ:', file=sys.stderr)
print(f'  bash scripts/report_field_set.sh {rp} status revision_requested', file=sys.stderr)
sys.exit(1)
"
}

# --- Pre-validation autofix: 機械的フォーマットエラーを自動正規化 ---
# Phase 4原理: 忍者は/clearで記憶を失う。BLOCKでCTX浪費するより構文正規化で通す。
# 意味的エラー(空フィールド等)はBLOCK維持。構文エラー(true→yes, list→dict)のみautofix。
_autofix_field_value() {
    local dot_key="$1"
    local val="$2"
    local field="${dot_key%%.*}"

    case "$field" in
        files_modified)
            # string/string-list → dict-list (忍者がパス文字列だけを書く頻出パターン)
            if [[ "$dot_key" == "files_modified" ]]; then
                # The dominant caller supplies one plain repo-relative path.
                # Its normalized value is fixed and needs neither PyYAML parsing
                # nor serialization.  Keep punctuation, whitespace, non-ASCII,
                # reference_only, and list/dict inputs on the general parser.
                if [[ "$val" == */* ]] \
                    && [[ "$val" =~ ^[A-Za-z0-9_./@+-]+$ ]]; then
                    printf '%s\n' \
                        "- path: $val" \
                        '  change: modified'
                    return 0
                fi
                local fixed
                fixed=$(PYTHONPATH="$SCRIPT_DIR" python3 -c "
import yaml, sys, re
from scripts.lib.yaml_atomic import yaml_text
raw = sys.stdin.read()
def sanitize_path(p):
    return re.sub(r'^[^\x00-\x7f]+[:：]\s*', '', p).strip()
def reference_only(item):
    if isinstance(item, dict):
        if item.get('reference_only') is True:
            return True
        return str(item.get('change', '') or '').strip().lower() in ('reference_only', 'reference-only')
    return str(item or '').strip().lower() in ('reference_only', 'reference-only')
def validate(items):
    bad = []
    for idx, item in enumerate(items):
        path = str(item.get('path', '') or '').strip() if isinstance(item, dict) else str(item or '').strip()
        if not path or path == 'FILL_THIS':
            bad.append(f'{idx}: empty/path placeholder')
        elif not reference_only(item) and not path.startswith('偵察') and '/' not in path:
            bad.append(f'{idx}: {path}')
    if bad:
        print('BLOCK: files_modified はファイルパス形式のみ記入可。説明文・非パス値は禁止。', file=sys.stderr)
        print('  正: scripts/report_field_set.sh / context/foo.md', file=sys.stderr)
        print('  偵察のみの場合は \"偵察のみ\"、参照のみの場合は reference_only を使え', file=sys.stderr)
        print('  不正値: ' + '; '.join(bad), file=sys.stderr)
        sys.exit(1)
try:
    data = yaml.safe_load(raw)
except yaml.YAMLError as e:
    print(f'BLOCK: files_modified YAML parse error: {e}', file=sys.stderr)
    sys.exit(1)
if isinstance(data, str) and data.strip():
    # スペース区切り複数パス検出(拡張子付き2+トークン)
    tokens = [t for t in data.strip().split() if '.' in t or '/' in t]
    if len(tokens) > 1:
        print('[autofix] files_modified string→dict変換(複数ファイル スペース区切り)', file=sys.stderr)
        items = [{'path': sanitize_path(t.rstrip(',')), 'change': 'modified'} for t in tokens]
    else:
        print('[autofix] files_modified string→dict変換(単一ファイル)', file=sys.stderr)
        items = [{'path': sanitize_path(data.strip()), 'change': 'modified'}]
elif isinstance(data, list) and all(isinstance(x, str) for x in data):
    items = [{'path': sanitize_path(x.strip()), 'change': 'modified'} for x in data if x.strip()]
    if items:
        print('[autofix] files_modified string list→dict list変換', file=sys.stderr)
elif isinstance(data, list) and all(isinstance(x, dict) for x in data):
    items = data
    changed = False
    for item in items:
        if 'path' in item:
            clean = sanitize_path(item['path'])
            if clean != item['path']:
                item['path'] = clean
                changed = True
    if changed:
        print('[autofix] files_modified path日本語プレフィックス除去', file=sys.stderr)
else:
    items = data if isinstance(data, list) else [data]
validate(items)
print(yaml_text(items), end='')
" <<< "$val") || return 1
                echo "$fixed"
                return 0
            fi
            ;;
        lessons_useful)
            # dict → list of 1 dict (忍者がlistでなくdictで書く頻出パターン)
            if [[ "$dot_key" == "lessons_useful" ]]; then
                local fixed
                fixed=$(PYTHONPATH="$SCRIPT_DIR" python3 -c "
import yaml, sys
from scripts.lib.yaml_atomic import yaml_text
raw = sys.stdin.read()
try:
    data = yaml.safe_load(raw)
except yaml.YAMLError:
    print(raw, end='')
    sys.exit(0)
if isinstance(data, dict) and ('id' in data or 'useful' in data or 'reason' in data):
    print('[autofix] lessons_useful dict→list変換(単体dictをlistに包む)', file=sys.stderr)
    print(yaml_text([data]), end='')
elif isinstance(data, dict) and all(str(k).isdigit() for k in data.keys()) and all(isinstance(v, dict) for v in data.values()):
    # {0: {id:..}, 1: {id:..}} 形式 → list化 (数値キーのみ。ID-keyed dictはlist契約違反としてfall-through)
    items = [v for k, v in sorted(data.items(), key=lambda x: str(x[0]))]
    print('[autofix] lessons_useful 数値キーdict→list変換', file=sys.stderr)
    print(yaml_text(items), end='')
else:
    print(raw, end='')
" <<< "$val")
                echo "$fixed"
                return 0
            fi
            ;;
        lesson_candidate)
            # list of 1 dict → dict (忍者がdictをlistで包む頻出パターン)
            if [[ "$dot_key" == "lesson_candidate" ]]; then
                local fixed
                fixed=$(PYTHONPATH="$SCRIPT_DIR" python3 -c "
import yaml, sys
from scripts.lib.yaml_atomic import yaml_text
raw = sys.stdin.read()
try:
    data = yaml.safe_load(raw)
except yaml.YAMLError:
    print(raw, end='')
    sys.exit(0)
if isinstance(data, list) and len(data) == 1 and isinstance(data[0], dict):
    print('[autofix] lesson_candidate list→dict変換(要素1のlistからdict抽出)', file=sys.stderr)
    print(yaml_text(data[0]), end='')
elif isinstance(data, list) and len(data) >= 1:
    # 複数要素listの場合: 全要素をキー統合してdictに
    merged = {}
    for item in data:
        if isinstance(item, dict):
            merged.update(item)
    if merged:
        print('[autofix] lesson_candidate list→dict変換(複数要素を統合)', file=sys.stderr)
        print(yaml_text(merged), end='')
    else:
        print(raw, end='')
else:
    print(raw, end='')
" <<< "$val")
                echo "$fixed"
                return 0
            fi
            ;;
        assumption_invalidation)
            if [[ "$dot_key" == "assumption_invalidation" ]]; then
                local fixed
                fixed=$(PYTHONPATH="$SCRIPT_DIR" python3 -c "
import yaml, sys
from scripts.lib.yaml_atomic import yaml_text
raw = sys.stdin.read().strip()
lower = raw.lower().strip('\"\\'')
try:
    data = yaml.safe_load(raw)
except yaml.YAMLError:
    data = raw

if isinstance(data, dict):
    data.setdefault('found', False)
    data.setdefault('affected_cmds', [])
    data.setdefault('detail', '')
elif isinstance(data, bool):
    data = {'found': data, 'affected_cmds': [], 'detail': ''}
elif data is None or lower in ('', \"''\", '\"\"', 'none', 'null', 'false', 'no'):
    data = {'found': False, 'affected_cmds': [], 'detail': ''}
elif lower in ('true', 'yes'):
    data = {'found': True, 'affected_cmds': [], 'detail': ''}
else:
    data = {'found': True, 'affected_cmds': [], 'detail': raw}

print('[autofix] assumption_invalidation scalar→dict変換', file=sys.stderr)
print(yaml_text(data, sort_keys=False), end='')
" <<< "$val")
                echo "$fixed"
                return 0
            fi
            ;;
        hook_failures)
            # Canonicalize the leaf whether it is written directly or inside
            # either accepted parent mapping.
            # review_bundle.py enforces {all_pass,no_new_failure,regression_detected}
            # (lowercase snake_case); ninjas keep writing the uppercase/PASS form
            # they see in tool output, which round-trips through gunshi APPROVE
            # rejection. Canonicalize known spellings here; leave anything else
            # untouched so the existing downstream BLOCK still catches real
            # unknown values (no silent-fix of genuine mistakes).
            if [[ "$dot_key" == "hook_failures" ||
                  "$dot_key" == "hook_failures.details" ||
                  "$dot_key" == "hook_failures.details.post_verification_result" ]]; then
                local fixed
                fixed=$(PYTHONPATH="$SCRIPT_DIR" DOT_KEY="$dot_key" python3 -c '
import json, os, sys, yaml

canon = {
    "PASS": "all_pass", "all_pass": "all_pass",
    "NO_NEW_FAILURE": "no_new_failure", "no_new_failure": "no_new_failure",
    "REGRESSION_DETECTED": "regression_detected",
    "regression_detected": "regression_detected",
}
key = os.environ["DOT_KEY"]
raw = sys.stdin.read().strip()
try:
    value = yaml.safe_load(raw)
except yaml.YAMLError:
    value = raw

target = None
if key == "hook_failures" and isinstance(value, dict):
    details = value.get("details")
    if isinstance(details, dict):
        target = details
elif key == "hook_failures.details" and isinstance(value, dict):
    target = value

if target is not None:
    current = target.get("post_verification_result")
    if isinstance(current, str):
        target["post_verification_result"] = canon.get(current, current)
elif key == "hook_failures.details.post_verification_result" and isinstance(value, str):
    value = canon.get(value, value)

if isinstance(value, (dict, list)):
    # Flow style keeps even a one-key parent mapping structurally explicit
    # after command substitution strips the trailing newline.
    print(json.dumps(value, ensure_ascii=False), end="")
else:
    print(value, end="")
' <<< "$val")
                echo "$fixed"
                return 0
            fi
            ;;
    esac
    echo "$val"
    return 0
}

# Execute pre-write autofix + validation
_val_input="$VALUE"
if [ -n "$STDIN_VALUE" ]; then
    _val_input="$STDIN_VALUE"
fi
# Autofix: 機械的正規化
_fixed_input=$(_autofix_field_value "$DOT_KEY" "$_val_input")
if [ "$_fixed_input" != "$_val_input" ]; then
    # Autofixed — update the value for downstream processing
    if [ -n "$STDIN_VALUE" ]; then
        STDIN_VALUE="$_fixed_input"
    fi
    VALUE="$_fixed_input"
    _val_input="$_fixed_input"
    # Autofix may have converted scalar→structure (e.g., string→YAML list)
    # Re-check if Python fallback is needed
    if [ "$USE_PYTHON" -eq 0 ]; then
        if [[ "$VALUE" == *$'\n'* ]] || [[ "$VALUE" == '['* ]] || [[ "$VALUE" == '{'* ]]; then
            USE_PYTHON=1
            STDIN_VALUE="$VALUE"
        fi
    fi
fi
# Completed report immutability guard: status completed/done後の内容変更をfail-closed BLOCK
if ! _report_field_set_completed_guard "$DOT_KEY" "$_val_input"; then
    echo "[report_field_set] BLOCKED: completed/done報告は不変。上記メッセージに従い revision_requested へ遷移せよ。" >&2
    exit 1
fi
# Validate: 意味的エラーはBLOCK
if ! _validate_field_value "$DOT_KEY" "$_val_input"; then
    echo "[report_field_set] BLOCKED: 値フォーマット不正。上記メッセージに従い修正せよ。" >&2
    exit 1
fi

# Parse dot notation
IFS='.' read -ra KEYS <<< "$DOT_KEY"
NUM_KEYS=${#KEYS[@]}
RFS_BINARY_CHECK_RESULT_WRITE=0
RFS_BC_AC_KEY=""
RFS_BC_ITEM_IDX=""
# Two report-write call conventions reach the same leaf: dot-numeric
# ("binary_checks.AC1.0.result", legacy) and bracket-index
# ("binary_checks.AC1[0].result", the documented skills/report-write form).
# Detect both so the hot-path writer below and the downstream semantic-check
# skip (GP-053) cover the call pattern operators actually use.
if [[ "$DOT_KEY" =~ ^binary_checks\.([A-Za-z0-9_]+)\.([0-9]+)\.result$ ]]; then
    RFS_BINARY_CHECK_RESULT_WRITE=1
    RFS_BC_AC_KEY="${BASH_REMATCH[1]}"
    RFS_BC_ITEM_IDX="${BASH_REMATCH[2]}"
elif [[ "$DOT_KEY" =~ ^binary_checks\.([A-Za-z0-9_]+)\[([0-9]+)\]\.result$ ]]; then
    RFS_BINARY_CHECK_RESULT_WRITE=1
    RFS_BC_AC_KEY="${BASH_REMATCH[1]}"
    RFS_BC_ITEM_IDX="${BASH_REMATCH[2]}"
fi
# lessons_useful.<idx>.reason: second most frequent write (~4/report, one per
# injected lesson). Same shape of waste as binary_checks had: falls through to
# the Python leaf-write AND unconditionally re-parses the whole file in the
# GP-072c2 dict->list post-write step even though the list is already a list.
RFS_LU_REASON_WRITE=0
RFS_LU_ITEM_IDX=""
if [[ "$DOT_KEY" =~ ^lessons_useful\.([0-9]+)\.reason$ ]]; then
    RFS_LU_REASON_WRITE=1
    RFS_LU_ITEM_IDX="${BASH_REMATCH[1]}"
fi
AUTO_COMPLETE_STATUS=0
if [[ "$DOT_KEY" == "verdict" ]] && [[ "$VALUE" == "PASS" || "$VALUE" == "FAIL" || "$VALUE" == "PASS_NO_IMPROVEMENT" ]]; then
    AUTO_COMPLETE_STATUS=1
    # A report that claims commit=yes must remain writable until its immutable
    # commit fingerprint has been recorded.  Otherwise verdict auto-completion
    # makes the immediately-following commit_hash write impossible.
    if [ -f "$REPORT_PATH" ] && ! REPORT_PATH="$REPORT_PATH" PROJECT_ROOT="$SCRIPT_DIR" python3 - <<'PY'
import os, pathlib, sys, yaml
sys.path.insert(0, str(pathlib.Path(os.environ['PROJECT_ROOT']) / 'scripts' / 'lib'))
from report_commit_identity import valid_commit_identity
data = yaml.safe_load(open(os.environ['REPORT_PATH'], encoding='utf-8')) or {}
checks = (data.get('binary_checks') or {}).get('commit')
if not checks:
    sys.exit(0)
def is_yes(value):
    return value is True or (isinstance(value, str) and value.strip().lower() == 'yes')
all_yes = isinstance(checks, list) and all(
    isinstance(item, dict) and is_yes(item.get('result')) for item in checks
)
commit_hash = str(data.get('commit_hash', '')).strip()
def terminal_ready(d):
    summary = str((d.get('result') or {}).get('summary', '')).strip()
    files = d.get('files_modified')
    lessons = d.get('lessons_useful')
    memories = d.get('memory_references') or []
    return (
        summary not in ('', 'FILL_THIS')
        and isinstance(d.get('purpose_validation'), dict)
        and isinstance(files, list) and bool(files)
        and isinstance(d.get('lesson_candidate'), (dict, list))
        and isinstance(lessons, list) and bool(lessons)
        and all(isinstance(x, dict) and str(x.get('reason', '')).strip() not in ('', 'FILL_THIS', '未参照') for x in lessons)
        and all(isinstance(x, dict) and str(x.get('reason', '')).strip() for x in memories)
    )
sys.exit(0 if (not all_yes or (valid_commit_identity(commit_hash, data, pathlib.Path(os.environ['PROJECT_ROOT'])) and terminal_ready(data))) else 1)
PY
    then
        AUTO_COMPLETE_STATUS=0
    fi
elif [[ "$DOT_KEY" == "commit_hash" ]] && { [[ "$VALUE" =~ ^[0-9a-f]{40}$ ]] || [[ "$VALUE" == "no-code-change" ]]; } && [ -f "$REPORT_PATH" ]; then
    # commit_hash速度最適化(cmd_karo_hotfix_hot_script_report_commit_hash_20260728):
    # 下のPythonは最終条件で `verdict in ('PASS','FAIL','PASS_NO_IMPROVEMENT')` を要求する
    # ため、verdictがまだ未設定/他値ならall_yes/terminal_readyの判定結果に関わらず必ずexit 1
    # (AUTO_COMPLETE_STATUS=0のまま)になる。commit_hashは通常verdict確定より前に書かれるため、
    # 恒常的にこの全量再parseだけが空振りする。^verdict: grepで先に判定できる場合はpython3を
    # 起動せず同じ結果(スキップ=exit 1相当)に到達する。
    _rfs_ch_verdict="$(grep -m1 '^verdict:' "$REPORT_PATH" 2>/dev/null | sed 's/^verdict:[[:space:]]*//' | tr -d '\r"'"'"'')"
    case "$_rfs_ch_verdict" in
        PASS|FAIL|PASS_NO_IMPROVEMENT) ;;
        *) _rfs_ch_verdict="" ;;
    esac
    if [ -n "$_rfs_ch_verdict" ] && REPORT_PATH="$REPORT_PATH" python3 - <<'PY'
import json, os, sys, yaml
data = yaml.safe_load(open(os.environ['REPORT_PATH'], encoding='utf-8')) or {}
checks = (data.get('binary_checks') or {}).get('commit')
def is_yes(value):
    return value is True or (isinstance(value, str) and value.strip().lower() == 'yes')
all_yes = isinstance(checks, list) and bool(checks) and all(
    isinstance(item, dict) and is_yes(item.get('result')) for item in checks
)
verdict = str(data.get('verdict', '')).strip()
status = str(data.get('status', '')).strip()
summary = str((data.get('result') or {}).get('summary', '')).strip()
files = data.get('files_modified')
lessons = data.get('lessons_useful')
memories = data.get('memory_references') or []
terminal_ready = (
    summary not in ('', 'FILL_THIS')
    and isinstance(data.get('purpose_validation'), dict)
    and isinstance(files, list) and bool(files)
    and isinstance(data.get('lesson_candidate'), (dict, list))
    and isinstance(lessons, list) and bool(lessons)
    and all(isinstance(x, dict) and str(x.get('reason', '')).strip() not in ('', 'FILL_THIS', '未参照') for x in lessons)
    and all(isinstance(x, dict) and str(x.get('reason', '')).strip() for x in memories)
)
sys.exit(0 if all_yes and terminal_ready and verdict in ('PASS', 'FAIL', 'PASS_NO_IMPROVEMENT') and status not in ('completed', 'done') else 1)
PY
    then
        AUTO_COMPLETE_STATUS=1
    fi
fi

if [ "$AUTO_COMPLETE_STATUS" -eq 1 ]; then
    _validate_lesson_feedback_completion_contract || exit 1
fi

# Create file if not exists
[ -f "$REPORT_PATH" ] || touch "$REPORT_PATH"

# --- Fast path: scalar root / 2-level nested writes without sourcing yaml_field_set.sh ---
# Common report updates (status/result.summary/etc.) dominate call volume. Keep the
# Python/list paths unchanged, and only short-circuit the simple scalar mapping case.
_report_field_set_fast_scalar() {
    local report_path="$1"
    local tmp_file="$2"
    local dot_key="$3"
    local value="$4"
    local num_keys="$5"
    shift 5
    local keys=("$@")

    if [ "$num_keys" -gt 2 ]; then
        return 2
    fi
    if [[ "$dot_key" == *'['* ]] || [[ "$value" == '['* ]] || [[ "$value" == '{'* ]] || [[ "$value" == *$'\n'* ]]; then
        return 2
    fi

    if [ "$num_keys" -eq 1 ]; then
        awk \
            -v field="${keys[0]}" \
            -v new_value="$value" '
function regex_escape(str,    out,i,c) {
    out = ""
    for (i = 1; i <= length(str); i++) {
        c = substr(str, i, 1)
        if (c ~ /[][\\.^$*+?(){}|]/) out = out "\\" c
        else out = out c
    }
    return out
}
function yaml_safe(v,    out,i,c,needs_quote) {
    needs_quote = 0
    if (index(v, ":") > 0) needs_quote = 1
    if (index(v, "#") > 0) needs_quote = 1
    if (index(v, "[") > 0) needs_quote = 1
    if (index(v, "]") > 0) needs_quote = 1
    if (index(v, "{") > 0) needs_quote = 1
    if (index(v, "}") > 0) needs_quote = 1
    if (needs_quote) {
        out = ""
        for (i = 1; i <= length(v); i++) {
            c = substr(v, i, 1)
            if (c == "\"") out = out "\\" c
            else out = out c
        }
        return "\"" out "\""
    }
    return v
}
BEGIN { replaced = 0; has_fields = 0; skip_continuation = 0 }
{
    field_re = "^" regex_escape(field) ":[[:space:]]*"
    if (!replaced && $0 ~ field_re) {
        print field ": " yaml_safe(new_value)
        replaced = 1
        has_fields = 1
        skip_continuation = 1
        next
    }
    # GP-234: block scalar continuation行スキップ
    if (skip_continuation) {
        if ($0 ~ /^[[:space:]]/ || $0 ~ /^$/) { next }
        skip_continuation = 0
    }
    if ($0 ~ /^[A-Za-z0-9_.-]+:[[:space:]]/) has_fields = 1
    print
}
END {
    if (!has_fields) exit 2
    if (!replaced) print field ": " yaml_safe(new_value)
}
' "$report_path" > "$tmp_file"
        return $?
    fi

    awk \
        -v block_id="${keys[0]}" \
        -v field="${keys[1]}" \
        -v new_value="$value" '
function trim(s) { sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
function leading_spaces(line,    i,cnt,c) {
    cnt = 0
    for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (c == " ") cnt++
        else break
    }
    return cnt
}
function make_indent(n,    s,i) {
    s = ""
    for (i = 0; i < n; i++) s = s " "
    return s
}
function regex_escape(str,    out,i,c) {
    out = ""
    for (i = 1; i <= length(str); i++) {
        c = substr(str, i, 1)
        if (c ~ /[][\\.^$*+?(){}|]/) out = out "\\" c
        else out = out c
    }
    return out
}
function yaml_safe(v,    out,i,c,needs_quote) {
    needs_quote = 0
    if (index(v, ":") > 0) needs_quote = 1
    if (index(v, "#") > 0) needs_quote = 1
    if (index(v, "[") > 0) needs_quote = 1
    if (index(v, "]") > 0) needs_quote = 1
    if (index(v, "{") > 0) needs_quote = 1
    if (index(v, "}") > 0) needs_quote = 1
    if (needs_quote) {
        out = ""
        for (i = 1; i <= length(v); i++) {
            c = substr(v, i, 1)
            if (c == "\"") out = out "\\" c
            else out = out c
        }
        return "\"" out "\""
    }
    return v
}
BEGIN {
    block_found = 0
    in_block = 0
    replaced = 0
    block_indent = -1
    field_indent = -1
}
{
    if (!in_block) {
        block_re = "^" regex_escape(block_id) ":[[:space:]]*$"
        if ($0 ~ block_re) {
            in_block = 1
            block_found = 1
            block_indent = leading_spaces($0)
            field_indent = block_indent + 2
        }
        print
        next
    }

    trimmed = trim($0)
    indent = leading_spaces($0)
    if (trimmed != "" && trimmed !~ /^#/ && indent <= block_indent) {
        if (!replaced) {
            print make_indent(field_indent) field ": " yaml_safe(new_value)
            replaced = 1
        }
        in_block = 0
        print
        next
    }

    field_re = "^" make_indent(field_indent) regex_escape(field) ":[[:space:]]*"
    if (!replaced && $0 ~ field_re) {
        print make_indent(field_indent) field ": " yaml_safe(new_value)
        replaced = 1
        skip_continuation = 1
        next
    }

    # GP-234: block scalar continuation行スキップ（旧マルチライン値の残骸除去）
    if (skip_continuation) {
        if (trimmed == "" || indent > field_indent) {
            next  # continuation行をスキップ
        }
        skip_continuation = 0  # 同レベル以上のフィールドに到達→スキップ終了
    }

    print
}
END {
    if (!block_found) exit 2
    if (in_block && !replaced) print make_indent(field_indent) field ": " yaml_safe(new_value)
}
' "$report_path" > "$tmp_file"
}

# Replace a top-level block sequence with an already-canonical YAML block.
# This is intentionally narrower than the Python fallback: callers must prove
# the complete replacement text and the existing top-level key shape.
_report_field_set_fast_root_block() {
    local report_path="$1"
    local tmp_file="$2"
    local root_key="$3"
    local replacement="$4"

    awk -v root_key="$root_key" -v replacement="$replacement" '
function leading_spaces(line,    i,cnt,c) {
    cnt = 0
    for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (c == " ") cnt++
        else break
    }
    return cnt
}
BEGIN { found = 0; skipping = 0 }
{
    if (!found && $0 ~ ("^" root_key ":[[:space:]]*")) {
        print root_key ":"
        print replacement
        found = 1
        skipping = 1
        next
    }
    if (skipping) {
        if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*#/) next
        if (leading_spaces($0) > 0 || $0 ~ /^-[[:space:]]/) next
        skipping = 0
    }
    print
}
END { if (!found) exit 2 }
' "$report_path" > "$tmp_file"
}

_report_field_set_extract_binary_result() {
    awk '
function trim(s) { sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
function unquote(s) {
    s = trim(s)
    if ((substr(s, 1, 1) == "\"" && substr(s, length(s), 1) == "\"") ||
        (substr(s, 1, 1) == "'"'"'" && substr(s, length(s), 1) == "'"'"'")) {
        s = substr(s, 2, length(s) - 2)
    }
    return s
}
/^[[:space:]]*result:[[:space:]]*/ {
    v = $0
    sub(/^[[:space:]]*result:[[:space:]]*/, "", v)
    v = unquote(v)
    if (v == "yes" || v == "no" || v == "") {
        print v
        found = 1
        exit 0
    }
}
END { if (!found) exit 2 }
' <<< "$1"
}

_report_field_set_fast_binary_ac_result() {
    local report_path="$1"
    local tmp_file="$2"
    local ac_key="$3"
    local result_value="$4"

    if [[ "$result_value" != "yes" && "$result_value" != "no" && "$result_value" != "" ]]; then
        return 2
    fi

    awk \
        -v ac_key="$ac_key" \
        -v result_value="$result_value" '
function trim(s) { sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
function leading_spaces(line,    i,cnt,c) {
    cnt = 0
    for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (c == " ") cnt++
        else break
    }
    return cnt
}
function make_indent(n,    s,i) { s = ""; for (i = 0; i < n; i++) s = s " "; return s }
function yaml_quote(v,    out,i,c) {
    out = ""
    for (i = 1; i <= length(v); i++) {
        c = substr(v, i, 1)
        if (c == "'\''") out = out "'\'''\''"
        else out = out c
    }
    return "'\''" out "'\''"
}
BEGIN {
    in_bc = 0
    in_ac = 0
    bc_indent = -1
    ac_indent = -1
    replaced = 0
}
{
    line = $0
    trimmed = trim(line)
    indent = leading_spaces(line)

    if (!in_bc && line ~ /^binary_checks:[[:space:]]*$/) {
        in_bc = 1
        bc_indent = indent
        print line
        next
    }

    if (in_bc && trimmed != "" && trimmed !~ /^#/ && indent <= bc_indent && line !~ /^binary_checks:[[:space:]]*$/) {
        if (in_ac && !replaced) {
            print make_indent(ac_indent + 2) "result: " yaml_quote(result_value)
            replaced = 1
        }
        in_bc = 0
        in_ac = 0
        print line
        next
    }

    if (in_bc && !in_ac) {
        ac_re = "^" make_indent(bc_indent + 2) ac_key ":[[:space:]]*$"
        if (line ~ ac_re) {
            in_ac = 1
            ac_indent = indent
        }
        print line
        next
    }

    if (in_ac) {
        if (trimmed != "" && trimmed !~ /^#/ && indent <= ac_indent && trimmed !~ /^-/ && line !~ ("^" make_indent(ac_indent) ac_key ":[[:space:]]*$")) {
            if (!replaced) {
                print make_indent(ac_indent + 2) "result: " yaml_quote(result_value)
                replaced = 1
            }
            in_ac = 0
            print line
            next
        }
        if (!replaced && indent > ac_indent && trimmed ~ /^result:[[:space:]]*/) {
            print make_indent(indent) "result: " yaml_quote(result_value)
            replaced = 1
            next
        }
    }

    print line
}
END {
    if (in_ac && !replaced) {
        print make_indent(ac_indent + 2) "result: " yaml_quote(result_value)
        replaced = 1
    }
    if (!replaced) exit 2
}
' "$report_path" > "$tmp_file"
}

# Indexed leaf write for "binary_checks.<AC>.<idx>.result" / "binary_checks.<AC>[<idx>].result".
# This is the single most frequent report write (one call per AC check item, ~15-20/report)
# and previously always fell through to the ~110ms Python fallback because
# _report_field_set_fast_scalar only handles <=2 dot-levels and the bracket-notation
# form was caught by the unconditional "contains '[' -> Python" guard. Restricted to
# result_value in {yes,no}: anything else (rare) still falls through to Python unchanged.
_report_field_set_fast_indexed_binary_result() {
    local report_path="$1"
    local tmp_file="$2"
    local ac_key="$3"
    local target_idx="$4"
    local result_value="$5"

    if [[ "$result_value" != "yes" && "$result_value" != "no" ]]; then
        return 2
    fi

    awk \
        -v ac_key="$ac_key" \
        -v target_idx="$target_idx" \
        -v result_value="$result_value" '
function trim(s) { sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
function leading_spaces(line,    i,cnt,c) {
    cnt = 0
    for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (c == " ") cnt++
        else break
    }
    return cnt
}
function make_indent(n,    s,i) { s = ""; for (i = 0; i < n; i++) s = s " "; return s }
function yaml_quote(v,    out,i,c) {
    out = ""
    for (i = 1; i <= length(v); i++) {
        c = substr(v, i, 1)
        if (c == "'\''") out = out "'\'''\''"
        else out = out c
    }
    return "'\''" out "'\''"
}
BEGIN {
    in_bc = 0
    in_ac = 0
    bc_indent = -1
    ac_indent = -1
    item_no = -1
    replaced = 0
}
{
    line = $0
    trimmed = trim(line)
    indent = leading_spaces(line)

    if (!in_bc && line ~ /^binary_checks:[[:space:]]*$/) {
        in_bc = 1
        bc_indent = indent
        print line
        next
    }

    if (in_bc && trimmed != "" && trimmed !~ /^#/ && indent <= bc_indent && line !~ /^binary_checks:[[:space:]]*$/) {
        in_bc = 0
        in_ac = 0
        print line
        next
    }

    if (in_bc && !in_ac) {
        ac_re = "^" make_indent(bc_indent + 2) ac_key ":[[:space:]]*$"
        if (line ~ ac_re) {
            in_ac = 1
            ac_indent = indent
            item_no = -1
        }
        print line
        next
    }

    if (in_ac) {
        # AC block ends at a line back to (or above) ac_indent that is not a list item.
        if (trimmed != "" && trimmed !~ /^#/ && indent <= ac_indent && trimmed !~ /^-/) {
            in_ac = 0
            print line
            next
        }
        # Each list item starts with "-" at ac_indent (compact YAML block-sequence style).
        if (indent == ac_indent && trimmed ~ /^-/) {
            item_no++
        }
        if (!replaced && item_no == target_idx && indent > ac_indent && trimmed ~ /^result:[[:space:]]*/) {
            print make_indent(indent) "result: " yaml_quote(result_value)
            replaced = 1
            next
        }
    }

    print line
}
END {
    if (!replaced) exit 2
}
' "$report_path" > "$tmp_file"
}

# Indexed leaf write for "lessons_useful.<idx>.reason" — the second most frequent
# report write. Restricted to single-line values (caller already routes
# multi-line values to USE_PYTHON before reaching here) and to the top-level
# list-of-dicts shape the template always injects, so a failed match (e.g. the
# item doesn't exist yet) safely falls through to the Python fallback below.
_report_field_set_fast_indexed_list_reason() {
    local report_path="$1"
    local tmp_file="$2"
    local list_key="$3"
    local target_idx="$4"
    local new_value="$5"

    awk \
        -v list_key="$list_key" \
        -v target_idx="$target_idx" \
        -v new_value="$new_value" '
function leading_spaces(line,    i,cnt,c) {
    cnt = 0
    for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (c == " ") cnt++
        else break
    }
    return cnt
}
function trim(s) { sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
function make_indent(n,    s,i) { s = ""; for (i = 0; i < n; i++) s = s " "; return s }
function yaml_safe(v,    out,i,c,needs_quote) {
    needs_quote = 0
    if (index(v, ":") > 0) needs_quote = 1
    if (index(v, "#") > 0) needs_quote = 1
    if (index(v, "[") > 0) needs_quote = 1
    if (index(v, "]") > 0) needs_quote = 1
    if (index(v, "{") > 0) needs_quote = 1
    if (index(v, "}") > 0) needs_quote = 1
    if (needs_quote) {
        out = ""
        for (i = 1; i <= length(v); i++) {
            c = substr(v, i, 1)
            if (c == "\"") out = out "\\" c
            else out = out c
        }
        return "\"" out "\""
    }
    return v
}
BEGIN {
    in_list = 0
    in_item = 0
    list_indent = -1
    item_indent = -1
    item_no = -1
    replaced = 0
    skip_continuation = 0
}
{
    line = $0
    trimmed = trim(line)
    indent = leading_spaces(line)

    if (!in_list && line ~ ("^" list_key ":")) {
        in_list = 1
        list_indent = indent
        print line
        next
    }

    if (in_list && trimmed != "" && trimmed !~ /^#/ && indent <= list_indent) {
        in_list = 0
        in_item = 0
        print line
        next
    }

    if (in_list) {
        # Each item is a standard (non-compact) block-sequence entry: "- " at
        # list_indent+2, fields one level deeper at list_indent+4.
        if (indent == list_indent + 2 && trimmed ~ /^-/) {
            item_no++
            in_item = (item_no == target_idx)
            item_indent = indent
            skip_continuation = 0
        }

        if (in_item) {
            field_re = "^" make_indent(item_indent + 2) "reason:[[:space:]]*"
            if (!replaced && line ~ field_re) {
                print make_indent(item_indent + 2) "reason: " yaml_safe(new_value)
                replaced = 1
                skip_continuation = 1
                next
            }
            if (skip_continuation) {
                if (trimmed == "" || indent > item_indent + 2) { next }
                skip_continuation = 0
            }
        }
    }

    print line
}
END {
    if (!replaced) exit 2
}
' "$report_path" > "$tmp_file"
}

# --- Python fallback (multi-line text, new block creation) ---
_report_field_set_python() {
    local rp="$1" dk="$2" val="$3" sv="$4"
    PYTHONPATH="$SCRIPT_DIR" python3 -c "
import sys, os, yaml, re
from scripts.lib.yaml_atomic import atomic_yaml_write

report_path = sys.argv[1]
dot_key = sys.argv[2]
value = sys.argv[3]
stdin_value = sys.argv[4] if len(sys.argv) > 4 else ''

if value == '-' and stdin_value:
    value = stdin_value
    try:
        # binary_checks: BaseLoaderでyes/noを文字列として保持(safe_loadはboolに変換してしまう)
        loader = yaml.BaseLoader if dot_key.startswith('binary_checks') else yaml.SafeLoader
        parsed = yaml.load(value, Loader=loader)
        if isinstance(parsed, (list, dict)):
            value = parsed
    except yaml.YAMLError:
        pass

if isinstance(value, str):
    if value.lower() == 'true':
        value = True
    elif value.lower() == 'false':
        value = False
    elif value.lower() in ('null', 'none'):
        value = None
    else:
        try:
            value = int(value)
        except (ValueError, TypeError):
            try:
                value = float(value)
            except (ValueError, TypeError):
                pass

if os.path.exists(report_path) and os.path.getsize(report_path) > 0:
    with open(report_path, 'r') as f:
        data = yaml.safe_load(f) or {}
else:
    data = {}

keys = dot_key.split('.')
current = data
for key in keys[:-1]:
    m = re.match(r'^(.+)\[(\d+)\]$', key)
    if m:
        arr_key, idx = m.group(1), int(m.group(2))
        if arr_key not in current or not isinstance(current.get(arr_key), list):
            current[arr_key] = []
        arr = current[arr_key]
        while len(arr) <= idx:
            arr.append(None)
        if arr[idx] is None or not isinstance(arr[idx], dict):
            arr[idx] = {}
        current = arr[idx]
    else:
        # GP-072c2: If current is a list and key is numeric, use list index
        if isinstance(current, list) and key.isdigit():
            idx = int(key)
            while len(current) <= idx:
                current.append({})
            if not isinstance(current[idx], dict):
                current[idx] = {}
            current = current[idx]
        elif isinstance(current, dict):
            existing = current.get(key)
            if isinstance(existing, (dict, list)):
                # GP-072c2: preserve list for next iteration's numeric index handling
                current = existing
            else:
                current[key] = {}
                current = current[key]
        else:
            current = {}

last_key = keys[-1]
m_last = re.match(r'^(.+)\[(\d+)\]$', last_key)
if m_last:
    arr_key, idx = m_last.group(1), int(m_last.group(2))
    if arr_key not in current or not isinstance(current.get(arr_key), list):
        current[arr_key] = []
    arr = current[arr_key]
    while len(arr) <= idx:
        arr.append(None)
    arr[idx] = value
else:
    # --- GP-053 cycle 3: binary_checks check項目保護 ---
    # テンプレートで事前展開されたcheck項目を忍者の上書きから保護。
    # 忍者はresultのみ更新可能。check項目はテンプレートのまま維持。
    # ★ただしFILLプレースホルダは保護対象外（忍者の具体的check文で上書き可能）
    if keys[0] == 'binary_checks' and len(keys) == 2 and isinstance(value, list):
        existing = current.get(last_key, [])
        if isinstance(existing, list) and existing:
            protected = 0
            for i, ex_item in enumerate(existing):
                if i < len(value) and isinstance(ex_item, dict) and isinstance(value[i], dict):
                    ex_check = ex_item.get('check', '')
                    if ex_check and isinstance(ex_check, str) and len(ex_check.strip()) > 5:
                        # FILLプレースホルダは保護しない（忍者が具体的check文で上書きすべき）
                        if ex_check.strip().startswith('FILL'):
                            continue
                        value[i]['check'] = ex_check
                        protected += 1
            if protected > 0:
                print(f'[report_field_set] binary_checks保護: {protected}個のcheck項目をテンプレートから維持', file=sys.stderr)
    current[last_key] = value

    # cmd_2841: any assumption_invalidation.* write must leave the gate-required
    # shape intact.  When the block is missing, dot-notation writes create only
    # the requested leaf; add the template defaults instead of producing a report
    # that gate_report_format_main.py rejects.
    if keys[0] == 'assumption_invalidation':
        ai = data.get('assumption_invalidation')
        if not isinstance(ai, dict):
            ai = {}
            data['assumption_invalidation'] = ai
        ai.setdefault('found', False)
        ai.setdefault('affected_cmds', [])
        ai.setdefault('detail', '')

try:
    atomic_yaml_write(report_path, data, sort_keys=False)
except Exception as e:
    print(f'[report_field_set] YAML_DUMP_CORRUPTION: {e}. Original file preserved.', file=sys.stderr)
    sys.exit(1)

print(f'[report_field_set] {dot_key} = {value}')
" "$rp" "$dk" "$val" "$sv"
}

_report_field_set_prepare_backup() {
    if [ -e "$REPORT_PATH" ]; then
        cp "$REPORT_PATH" "${REPORT_PATH}.bak"
    else
        : > "${REPORT_PATH}.bak"
    fi
}

_report_field_set_validate_or_restore() {
    local parse_output
    if parse_output=$(python3 -c "import yaml, sys; yaml.safe_load(open(sys.argv[1], encoding='utf-8'))" "$REPORT_PATH" 2>&1); then
        return 0
    fi

    echo "YAML parse error after field set — reverting" >&2
    if [ -n "$parse_output" ]; then
        echo "$parse_output" >&2
    fi
    if [ -f "${REPORT_PATH}.bak" ]; then
        cp "${REPORT_PATH}.bak" "$REPORT_PATH"
    fi
    return 1
}

# --- Main write logic with flock + retries ---
MAX_RETRIES=3
for ((attempt = 1; attempt <= MAX_RETRIES; attempt++)); do
    (
        flock -w 5 200 || { echo "[report_field_set] flock failed (attempt $attempt)" >&2; exit 1; }
        # Backup (.bak) is only ever read by _report_field_set_validate_or_restore,
        # which is reachable from the Python-fallback/fast_scalar paths further
        # below — never from the three fast paths in this block (they atomically
        # mv a freshly-built tmp_file and exit 0 without touching .bak). Creating
        # it unconditionally here cost every single call a full-file cp for no
        # reason on the hot path. Deferred to just before the paths that can
        # actually use it (see below), so it's still in place before any code
        # that might need it, just skipped when nothing downstream will read it.

        # binary_checks.AC*: common report path is a single result update.  The
        # Python fallback preserves arbitrary structures, but this hot path can
        # safely keep template check text and replace only the result scalar.
        if [[ "$DOT_KEY" == binary_checks.AC* ]] && [[ "$DOT_KEY" != *.*.* ]] && [ -n "$STDIN_VALUE" ]; then
            _bc_result="$(_report_field_set_extract_binary_result "$STDIN_VALUE" 2>/dev/null || true)"
            # Flow-style fallback: extract result from {check: ..., result: yes} (single-item only)
            # Pure bash string ops to avoid subprocess overhead (grep/sed → ~10ms savings on WSL2)
            if [ -z "$_bc_result" ]; then
                case "$STDIN_VALUE" in
                    *result:*result:*) ;; # Multiple result fields: multi-item, skip fast path
                    *result:*)
                        _rfs_after="${STDIN_VALUE#*result:}"
                        _rfs_after="${_rfs_after# }"
                        case "$_rfs_after" in
                            \"*) _rfs_after="${_rfs_after#\"}" ;;
                        esac
                        _rfs_after="${_rfs_after#\'}"
                        # Extract value before first delimiter (comma, brace, quote, space)
                        _rfs_val="${_rfs_after%%[, \}\"]*}"
                        _rfs_val="${_rfs_val%%\'*}"
                        case "$_rfs_val" in
                            yes) _bc_result="yes" ;;
                            no) _bc_result="no" ;;
                        esac
                        ;;
                esac
            fi
            if [ -n "$_bc_result" ]; then
                tmp_file="${REPORT_PATH}.tmp.$$.$attempt"
                rm -f "$tmp_file"
                if _report_field_set_fast_binary_ac_result "$REPORT_PATH" "$tmp_file" "${KEYS[1]}" "$_bc_result"; then
                    if ! mv "$tmp_file" "$REPORT_PATH"; then
                        rm -f "$tmp_file"
                        echo "FATAL: report_field_set: atomic replace failed" >&2
                        exit 1
                    fi
                    echo "[report_field_set] binary_checks保護: check項目をテンプレートから維持" >&2
                    echo "[report_field_set] $DOT_KEY.result = ${_bc_result:0:80}"
                    exit 0
                fi
                rm -f "$tmp_file"
            fi
        fi

        # Indexed binary_checks result write ("AC1.0.result" or "AC1[0].result" form):
        # single most frequent report write. Only fires for result_value in {yes,no}
        # (see _report_field_set_fast_indexed_binary_result); anything else falls
        # through unchanged to the existing Python-fallback paths below.
        if [ -n "$RFS_BC_AC_KEY" ] && [ "$USE_PYTHON" -eq 0 ]; then
            tmp_file="${REPORT_PATH}.tmp.$$.$attempt"
            rm -f "$tmp_file"
            if _report_field_set_fast_indexed_binary_result "$REPORT_PATH" "$tmp_file" "$RFS_BC_AC_KEY" "$RFS_BC_ITEM_IDX" "$VALUE"; then
                if ! mv "$tmp_file" "$REPORT_PATH"; then
                    rm -f "$tmp_file"
                    echo "FATAL: report_field_set: atomic replace failed" >&2
                    exit 1
                fi
                echo "[report_field_set] $DOT_KEY = ${VALUE:0:80}"
                exit 0
            fi
            rm -f "$tmp_file"
        fi

        # Indexed lessons_useful.<idx>.reason write: second most frequent report
        # write. USE_PYTHON=0 here already means the value is single-line.
        # Backslash-containing values are excluded (fall through to Python):
        # the awk yaml_safe() quoting here (like the pre-existing fast_scalar
        # path) escapes '"' but not '\', so a literal backslash inside a
        # double-quoted scalar can be read back as a YAML escape sequence
        # (e.g. "\f" -> form-feed) and corrupt the file. Confirmed via
        # reproduction during this optimization; Python's yaml.dump handles
        # backslashes correctly, so falling through there is safe.
        if [ "$RFS_LU_REASON_WRITE" -eq 1 ] && [ "$USE_PYTHON" -eq 0 ] && [[ "$VALUE" != *'\'* ]]; then
            tmp_file="${REPORT_PATH}.tmp.$$.$attempt"
            rm -f "$tmp_file"
            if _report_field_set_fast_indexed_list_reason "$REPORT_PATH" "$tmp_file" "lessons_useful" "$RFS_LU_ITEM_IDX" "$VALUE"; then
                if ! mv "$tmp_file" "$REPORT_PATH"; then
                    rm -f "$tmp_file"
                    echo "FATAL: report_field_set: atomic replace failed" >&2
                    exit 1
                fi
                echo "[report_field_set] $DOT_KEY = ${VALUE:0:80}"
                exit 0
            fi
            rm -f "$tmp_file"
        fi

        # Non-terminal status writes are root-scalar atomic replacements.  The
        # generic lane below prepares a full-file backup solely for fallback
        # restoration, then performs this same fast-scalar write.  No fallback
        # or normalize path can consume that backup for non-terminal values, so
        # keep them on the same backup-free atomic lane as the indexed fast
        # paths above. completed/done deliberately remain below: their terminal
        # normalization and completion checks are part of the quality contract.
        if [ "$DOT_KEY" = "status" ] && [[ "$VALUE" != "completed" && "$VALUE" != "done" ]]; then
            tmp_file="${REPORT_PATH}.tmp.$$.$attempt"
            rm -f "$tmp_file"
            if _report_field_set_fast_scalar "$REPORT_PATH" "$tmp_file" "status" "$VALUE" 1 "status"; then
                if ! mv "$tmp_file" "$REPORT_PATH"; then
                    rm -f "$tmp_file"
                    echo "FATAL: report_field_set: atomic replace failed" >&2
                    exit 1
                fi
                echo "[report_field_set] status = ${VALUE:0:80}"
                exit 0
            fi
            rm -f "$tmp_file"
        fi

        # A valid commit_hash is also a root scalar.  In the common ordering it
        # is recorded before verdict/terminal readiness, so AUTO_COMPLETE_STATUS
        # remains 0 and neither the generic full-file backup nor the later
        # terminal status normalization can be consumed.  Keep the exceptional
        # ready-to-complete case on the existing lane below; only the proven
        # non-terminal 40-hex shape takes this backup-free atomic replacement.
        if [ "$DOT_KEY" = "commit_hash" ] \
            && [[ "$VALUE" =~ ^[0-9a-f]{40}$ ]] \
            && [ "$AUTO_COMPLETE_STATUS" -eq 0 ]; then
            tmp_file="${REPORT_PATH}.tmp.$$.$attempt"
            rm -f "$tmp_file"
            if _report_field_set_fast_scalar "$REPORT_PATH" "$tmp_file" \
                "commit_hash" "$VALUE" 1 "commit_hash"; then
                if ! mv "$tmp_file" "$REPORT_PATH"; then
                    rm -f "$tmp_file"
                    echo "FATAL: report_field_set: atomic replace failed" >&2
                    exit 1
                fi
                echo "[report_field_set] commit_hash = ${VALUE:0:80}"
                exit 0
            fi
            rm -f "$tmp_file"
        fi

        # A single plain repo-relative files_modified path was canonicalized by
        # _autofix_field_value to exactly this three-line block.  The completed
        # report guard has already compared the semantic value above.  Replace
        # the top-level sequence atomically without a second full YAML load/dump.
        if [ "$DOT_KEY" = "files_modified" ] \
            && [[ "$VALUE" == -\ path:\ *$'\n'\ \ change:\ modified ]] \
            && [ "$AUTO_COMPLETE_STATUS" -eq 0 ]; then
            tmp_file="${REPORT_PATH}.tmp.$$.$attempt"
            rm -f "$tmp_file"
            if _report_field_set_fast_root_block \
                "$REPORT_PATH" "$tmp_file" "files_modified" "$VALUE"; then
                if ! mv "$tmp_file" "$REPORT_PATH"; then
                    rm -f "$tmp_file"
                    echo "FATAL: report_field_set: atomic replace failed" >&2
                    exit 1
                fi
                echo "[report_field_set] files_modified = ${VALUE:0:80}"
                exit 0
            fi
            rm -f "$tmp_file"
        fi

        # parent_ac_coverage / parent_contract_fingerprint are deployment-time
        # root scalars written together (same inject_parent_contract call site,
        # scripts/deploy_task.sh) to every report template.  The generic scalar
        # lane below performs the same awk replacement, but first copies a full
        # backup and afterwards re-reads status for terminal normalization.
        # Neither operation can be consumed by this non-terminal metadata write.
        # parent_contract_fingerprint is either a 16-char sha256 hex digest, or
        # '' (empty) when inject_parent_contract's parent-cmd lookup exits early
        # — e.g. a direct/karo_direct hotfix task with no parent_cmd contract to
        # bind (scripts/deploy_task.sh inject_parent_contract).  $VALUE=="" is
        # normalized to the literal two-char "''" before this block runs (see
        # the empty-value handling above), which is itself a single-line scalar
        # with no backslash/bracket/newline — same shape class as the hex case,
        # confirmed byte-identical against the pre-existing generic-lane output.
        # Keep structure, multiline and backslash values on the existing
        # Python/fallback lane; only the exact scalar shape takes this
        # backup-free atomic path.
        if [[ "$DOT_KEY" == "parent_ac_coverage" || "$DOT_KEY" == "parent_contract_fingerprint" ]] \
            && [ "$USE_PYTHON" -eq 0 ] \
            && [[ "$VALUE" != *'\'* ]]; then
            tmp_file="${REPORT_PATH}.tmp.$$.$attempt"
            rm -f "$tmp_file"
            if _report_field_set_fast_scalar \
                "$REPORT_PATH" "$tmp_file" "$DOT_KEY" "$VALUE" "$NUM_KEYS" "${KEYS[@]}"; then
                if ! mv "$tmp_file" "$REPORT_PATH"; then
                    rm -f "$tmp_file"
                    echo "FATAL: report_field_set: atomic replace failed" >&2
                    exit 1
                fi
                echo "[report_field_set] $DOT_KEY = ${VALUE:0:80}"
                exit 0
            fi
            rm -f "$tmp_file"
        fi

        # None of the fast paths above applied (or none matched this write) —
        # from here on, paths can fall back to Python or hit the backslash
        # validate-or-restore check, both of which read .bak. Create it now.
        _report_field_set_prepare_backup

        # Multi-line stdin text → Python fallback
        # Python path validates round-trip internally (yaml.safe_load reload)
        if [ "$USE_PYTHON" -eq 1 ]; then
            _report_field_set_python "$REPORT_PATH" "$DOT_KEY" "-" "$STDIN_VALUE"
            exit $?
        fi

        # Array index key (e.g., files_modified[0]) → Python fallback
        # awk経路はリテラルキーとして扱うため配列インデックスを正しく処理できない
        if [[ "$DOT_KEY" == *'['* ]]; then
            _report_field_set_python "$REPORT_PATH" "$DOT_KEY" "$VALUE" "$STDIN_VALUE"
            exit $?
        fi

        # YAML list item dot-notation (memory_references.0.used etc.) must be
        # handled by the Python path. The generic awk nested writer treats the
        # numeric segment as a mapping key and can produce dicts instead of
        # lists, which later fails gate_report_format.
        if [[ "$DOT_KEY" =~ ^(memory_references|verified_existing_dependency)\.[0-9]+\. ]]; then
            _report_field_set_python "$REPORT_PATH" "$DOT_KEY" "$VALUE" "$STDIN_VALUE"
            exit $?
        fi

        # JSON/YAML structure value (starts with [ or {) → Python fallback (GP-038)
        # awk経路は構造体をリテラル文字列として書くためYAML破壊の原因になる
        if [[ "$VALUE" == '['* ]] || [[ "$VALUE" == '{'* ]]; then
            _report_field_set_python "$REPORT_PATH" "$DOT_KEY" "-" "$VALUE"
            exit $?
        fi

        # A literal backslash is data, not a reason to reject the write.  The
        # awk scalar writer uses YAML double quotes when the value contains
        # punctuation such as ':', but cannot faithfully escape every YAML
        # backslash sequence (for example regex text '\.' or '\q').  Route all
        # such scalars through the atomic Python writer, which preserves the
        # literal value and emits valid YAML.
        if [[ "$VALUE" == *'\'* ]]; then
            _report_field_set_python "$REPORT_PATH" "$DOT_KEY" "$VALUE" "$STDIN_VALUE"
            exit $?
        fi

        tmp_file="${REPORT_PATH}.tmp.$$.$attempt"
        rm -f "$tmp_file"
        rc=0

        _report_field_set_fast_scalar "$REPORT_PATH" "$tmp_file" "$DOT_KEY" "$VALUE" "$NUM_KEYS" "${KEYS[@]}" || rc=$?
        if [ "$rc" -eq 0 ]; then
            :
        else
            ensure_yaml_field_set_loaded
        fi

        if [ "$rc" -eq 0 ]; then
            :
        elif [ "$NUM_KEYS" -eq 1 ]; then
            # Root-level field (e.g., "status")
            _yaml_field_set_apply_root "$REPORT_PATH" "$tmp_file" "${KEYS[0]}" "$VALUE" || rc=$?
            if [ "$rc" -eq 2 ]; then
                # No root-level fields found: append to file content
                if [ -s "$REPORT_PATH" ]; then
                    cat "$REPORT_PATH" > "$tmp_file"
                    if [[ "$VALUE" == *:* ]]; then
                        _escaped_val="${VALUE//\"/\\\"}"
                        echo "${KEYS[0]}: \"${_escaped_val}\"" >> "$tmp_file"
                    else
                        echo "${KEYS[0]}: $VALUE" >> "$tmp_file"
                    fi
                else
                    if [[ "$VALUE" == *:* ]]; then
                        _escaped_val="${VALUE//\"/\\\"}"
                        echo "${KEYS[0]}: \"${_escaped_val}\"" > "$tmp_file"
                    else
                        echo "${KEYS[0]}: $VALUE" > "$tmp_file"
                    fi
                fi
                rc=0
            fi
        elif [ "$rc" -eq 2 ]; then
            # Nested field: block_id = second-to-last segment, field = last segment
            BLOCK_ID="${KEYS[$((NUM_KEYS-2))]}"
            FIELD="${KEYS[$((NUM_KEYS-1))]}"
            _yaml_field_set_apply "$REPORT_PATH" "$tmp_file" "$BLOCK_ID" "$FIELD" "$VALUE" || rc=$?
            if [ "$rc" -eq 2 ]; then
                # Block not found → Python fallback for new structure creation
                rm -f "$tmp_file"
                _report_field_set_python "$REPORT_PATH" "$DOT_KEY" "$VALUE" ""
                exit $?
            fi
        fi

        if [ "$rc" -ne 0 ]; then
            rm -f "$tmp_file"
            echo "FATAL: report_field_set: failed to write $DOT_KEY in $REPORT_PATH" >&2
            exit 1
        fi

        # cmd_2543: verdict確定とstatus完了を同じflock内・同じatomic replaceで反映する。
        # 旧実装はverdict書込み後に別プロセスでstatusを書き、短時間だけ中間状態が見え得た。
        if [ "$AUTO_COMPLETE_STATUS" -eq 1 ]; then
            status_tmp="${REPORT_PATH}.tmp.$$.$attempt.status"
            rm -f "$status_tmp"
            _rfs_terminal_status="completed"
            # A fresh FAIL is a failed lifecycle terminal.  An explicitly
            # reopened completed report keeps the established RC round-trip:
            # revision_requested -> verdict rewrite -> completed.  The latter
            # is a review generation transition, not a new task failure.
            _rfs_prewrite_status="$(grep -m1 '^status:' "$REPORT_PATH" 2>/dev/null | sed 's/^status:[[:space:]]*//' | tr -d '\r"'"'"'')"
            if [ "$VALUE" = "FAIL" ] && [ "$_rfs_prewrite_status" != "revision_requested" ]; then
                _rfs_terminal_status="failed"
            fi
            if ! _report_field_set_fast_scalar "$tmp_file" "$status_tmp" "status" "$_rfs_terminal_status" 1 "status"; then
                rm -f "$tmp_file" "$status_tmp"
                echo "FATAL: report_field_set: failed to auto-complete status for $REPORT_PATH" >&2
                exit 1
            fi
            mv "$status_tmp" "$tmp_file"
        fi

        # cmd_karo_hotfix_report_completed_immutability RC: normalize a report
        # INSIDE the same atomic write that transitions it to completed/done —
        # i.e. before it is ever visible for review approval, and therefore
        # before any fingerprint (scripts/lib/review_approval.sh
        # review_report_fingerprint = sha256 of the whole file) is ever
        # computed on it. scripts/lib/normalize_report.sh previously only ran
        # post-approval (cmd_complete_gate.sh B層), where finding something to
        # fix silently invalidated an already-captured 軍師LGTM/家老ACCEPT
        # fingerprint (review_fingerprint_changed_after_normalize GATE BLOCK).
        # Normalizing here means that stall path can no longer fire: by the
        # time B層 runs post-approval, the report is already normalized and
        # normalize_report.sh is a byte-identical no-op (idempotent by design).
        # Non-terminal direct status writes cannot trigger normalization. Skip
        # the three-process status reread; terminal writes retain the original
        # inspection and fail-closed normalization path below.
        _rfs_skip_status_inspection=0
        if [ "$DOT_KEY" = "status" ]; then
            case "$VALUE" in
                completed|done) ;;
                *) _rfs_skip_status_inspection=1 ;;
            esac
        fi
        if [ "$_rfs_skip_status_inspection" -eq 0 ]; then
        _rfs_tmp_status="$(grep -m1 '^status:' "$tmp_file" 2>/dev/null | sed 's/^status:[[:space:]]*//' | tr -d '\r"'"'"'')"
        case "$_rfs_tmp_status" in
            completed|done)
                if [ -f "$SCRIPT_DIR/scripts/lib/normalize_report.sh" ]; then
                    # normalize_report.sh contract: 0=modified, 1=no-op (already
                    # normalized) — both are safe to publish. Any other exit
                    # (2=usage/parse/not-a-dict error, crash, etc.) means we do
                    # NOT know the true state of $tmp_file and must not publish
                    # it as completed. Discard the attempt and leave the
                    # original REPORT_PATH byte-unchanged (fail-closed) instead
                    # of silently completing a possibly-unnormalized report,
                    # which would reopen the exact fingerprint stall path this
                    # hook exists to close.
                    _rfs_normalize_rc=0
                    bash "$SCRIPT_DIR/scripts/lib/normalize_report.sh" "$tmp_file" >/dev/null 2>&1 || _rfs_normalize_rc=$?
                    if [ "$_rfs_normalize_rc" -gt 1 ]; then
                        rm -f "$tmp_file"
                        echo "FATAL: report_field_set: normalize_report.sh failed (rc=$_rfs_normalize_rc) while completing $REPORT_PATH; original report left untouched" >&2
                        exit 1
                    fi
                fi
                ;;
        esac
        fi

        if ! mv "$tmp_file" "$REPORT_PATH"; then
            rm -f "$tmp_file"
            echo "FATAL: report_field_set: atomic replace failed" >&2
            exit 1
        fi

        if [ "$rc" -ne 0 ]; then
            ensure_yaml_field_set_loaded
            actual=""
            if [ "$NUM_KEYS" -eq 1 ]; then
                actual="$(_yaml_field_get_root "$REPORT_PATH" "${KEYS[0]}")" || true
            else
                actual="$(_yaml_field_get_in_block "$REPORT_PATH" "$BLOCK_ID" "$FIELD")" || true
            fi

            normalized_actual="$(_yaml_field_set_normalize "$actual")"
            normalized_expected="$(_yaml_field_set_normalize "$VALUE")"
            if [ "$normalized_actual" != "$normalized_expected" ]; then
                echo "FATAL: report_field_set: post-write verification mismatch for $DOT_KEY (expected='$normalized_expected', actual='$normalized_actual')" >&2
                exit 1
            fi
        fi

        echo "[report_field_set] $DOT_KEY = ${VALUE:0:80}"
        if [ "$AUTO_COMPLETE_STATUS" -eq 1 ]; then
            if [ "${_rfs_terminal_status:-completed}" = "failed" ]; then
                echo "[report_field_set] status = failed (auto after verdict)"
            else
                echo "[report_field_set] status = completed (auto after verdict)"
            fi
        fi
        # Awk fast path: only validate YAML when value contains backslash.
        # awk yaml_safe escapes '"' but not '\', so values with '\' can produce
        # invalid YAML escape sequences (e.g. \q). Values without '\' are always safe.
        # Python fallback paths validate unconditionally (yaml.dump round-trip risk).
        if [[ "$VALUE" == *\\* ]]; then
            _report_field_set_validate_or_restore
        fi

    ) 200>"$LOCKFILE" && break

    if [ "$attempt" -eq "$MAX_RETRIES" ]; then
        echo "[report_field_set] All $MAX_RETRIES attempts failed" >&2
        exit 1
    fi
    sleep 0.5
done

# --- GP-072c2: Post-write dict→list auto-conversion ---
# per-item書込み(lessons_useful.0.id等)後に数値キーdictをリストに変換
# binary_checks.*.*.result / lessons_useful.*.reason は既存list内の値だけを
# 置換するhot pathなので変換不要(常にlistのまま。dict化する余地がない)。
if { [[ "$DOT_KEY" == lessons_useful.* ]] && [ "$RFS_LU_REASON_WRITE" -ne 1 ]; } || { [[ "$DOT_KEY" == binary_checks.*.* ]] && [ "$RFS_BINARY_CHECK_RESULT_WRITE" -ne 1 ]; } || [[ "$DOT_KEY" == memory_references.* ]] || [[ "$DOT_KEY" == verified_existing_dependency.* ]]; then
    PYTHONPATH="$SCRIPT_DIR" python3 -c "
import yaml, sys, os
from scripts.lib.yaml_atomic import atomic_yaml_write
rp = sys.argv[1]
dk = sys.argv[2]
if not os.path.exists(rp):
    sys.exit(0)
with open(rp) as f:
    data = yaml.safe_load(f) or {}
if not isinstance(data, dict):
    sys.exit(0)
changed = False
# Convert numeric-keyed dicts to lists
for field in ('lessons_useful', 'memory_references', 'verified_existing_dependency'):
    val = data.get(field)
    if isinstance(val, dict) and all(str(k).isdigit() for k in val.keys()):
        max_idx = max(int(k) for k in val.keys())
        new_list = [val.get(i, val.get(str(i))) for i in range(max_idx + 1)]
        data[field] = new_list
        changed = True
# binary_checks per-AC: convert numeric-keyed dicts within each AC
bc = data.get('binary_checks')
if isinstance(bc, dict):
    for ac_key, ac_val in bc.items():
        if isinstance(ac_val, dict) and all(str(k).isdigit() for k in ac_val.keys()):
            max_idx = max(int(k) for k in ac_val.keys())
            new_list = [ac_val.get(i, ac_val.get(str(i))) for i in range(max_idx + 1)]
            bc[ac_key] = new_list
            changed = True
if changed:
    atomic_yaml_write(rp, data, sort_keys=False)
    print(f'[report_field_set] dict→list auto-conversion applied for {dk}', file=sys.stderr)
" "$REPORT_PATH" "$DOT_KEY" 2>&1 || true
    _report_field_set_validate_or_restore
fi

# --- GP-053: binary_checks書込み直後のsemantic check ---
# 忍者がcheck="PASS"やresult=自由記述を書いた瞬間にフィードバック。
# gateは事後(cmd完了時)。ここは即時検出。品質の起点を早くする。
if [[ "$DOT_KEY" == binary_checks* ]]; then
    # Per-AC result-only writes: awk auto-verdict (avoid Python startup ~80ms)
    # Template check values are preserved by awk fast path; result is validated (yes/no only)
    if { [[ "$DOT_KEY" == binary_checks.AC* ]] && [[ "$DOT_KEY" != *.*.* ]]; } || [ "$RFS_BINARY_CHECK_RESULT_WRITE" -eq 1 ]; then
        _cur_verdict=$(awk '
BEGIN { total=0; yes_c=0; no_c=0; empty_c=0; in_bc=0; cv="" }
/^verdict:[[:space:]]/ { v=$0; sub(/^verdict:[[:space:]]*/, "", v); gsub(/["'"'"'[:space:]]/, "", v); cv=v }
/^binary_checks:[[:space:]]*$/ { in_bc=1; next }
in_bc && /^[^[:space:]]/ { in_bc=0 }
in_bc && /[[:space:]]result:[[:space:]]/ {
    v=$0; sub(/.*result:[[:space:]]*/, "", v); gsub(/["'"'"'[:space:]]/, "", v)
    total++
    if (v=="" || v=="null" || v=="None") empty_c++
    else if (v=="yes") yes_c++
    else if (v=="no") no_c++
}
END {
    if (total==0) exit
    if ((cv=="PASS" || cv=="PASS_NO_IMPROVEMENT") && no_c>0) print "INCONSISTENT"
    else if ((cv=="" || cv=="null" || cv=="None") && empty_c==0 && no_c==0) print "AUTO_PASS"
    else if ((cv=="" || cv=="null" || cv=="None") && no_c>0 && empty_c==0) print "AUTO_FAIL"
}' "$REPORT_PATH")
    else
        # Full binary_checks write or per-item: full Python semantic check
        _bc_post=$(REPORT_PATH="$REPORT_PATH" python3 -c "
import yaml, os, sys
rp = os.environ['REPORT_PATH']
action = ''
issues = []
try:
    with open(rp) as f:
        data = yaml.safe_load(f) or {}
except Exception:
    print('ACTION:')
    sys.exit(0)
if isinstance(data, dict):
    bc = data.get('binary_checks')
    if isinstance(bc, dict):
        verdict_words = {'PASS','FAIL','OK','NG','yes','no','YES','NO','true','false','True','False','pass','fail','ok','ng'}
        has_no = False
        has_empty = False
        for ac_key, ac_val in bc.items():
            if not isinstance(ac_val, list):
                continue
            for j, ci in enumerate(ac_val):
                if not isinstance(ci, dict):
                    continue
                ck = str(ci.get('check','')).strip()
                rs = str(ci.get('result','')).strip()
                if ck in verdict_words:
                    issues.append(f'{ac_key}[{j}].check=\"{ck}\" — 確認項目ではなく判定値。何を確認したかを書け')
                if rs and rs.lower() not in ('yes','no','true','false',''):
                    issues.append(f'{ac_key}[{j}].result=\"{rs[:30]}\" — yes/noのみ。自由記述はdetailに書け')
                r = rs.lower()
                if r == 'no':
                    has_no = True
                elif r not in ('yes',):
                    has_empty = True
        verdict = str(data.get('verdict', '')).strip()
        if verdict in ('PASS', 'PASS_NO_IMPROVEMENT') and has_no:
            action = 'INCONSISTENT'
        elif verdict in ('', 'null', 'None') and not has_empty and not has_no:
            action = 'AUTO_PASS'
        elif verdict in ('', 'null', 'None') and has_no and not has_empty:
            action = 'AUTO_FAIL'
print(f'ACTION:{action}')
for issue in issues:
    print(issue)
" 2>/dev/null) || true
        _cur_verdict="${_bc_post%%$'\n'*}"
        _cur_verdict="${_cur_verdict#ACTION:}"
        if [[ "$_bc_post" == *$'\n'* ]]; then
            _bc_check="${_bc_post#*$'\n'}"
        else
            _bc_check=""
        fi
        if [ -n "$_bc_check" ]; then
            echo "" >&2
            echo "⚠ binary_checks品質問題検出 ⚠" >&2
            echo "$_bc_check" >&2
            echo "FIX: check=「確認した内容」 result=\"yes\" or \"no\"" >&2
            echo "例: bash scripts/report_field_set.sh $REPORT_PATH binary_checks.AC1 '[{check: \"変数が除去されたか\", result: \"yes\"}]'" >&2
        fi
    fi
    # ★穴B/C対策: bc書込み後にverdictを自動再導出(矛盾状態を時間軸でも作れない)
    if [[ "$_cur_verdict" == "INCONSISTENT" ]]; then
        # verdict:PASSだがbc:noあり → FAILに自動修正
        bash "$0" "$REPORT_PATH" verdict FAIL 2>/dev/null || true
        echo "★ verdict自動再導出: bc:no追加によりPASS→FAIL強制(時間軸矛盾排除)" >&2
    elif [[ "$_cur_verdict" == "AUTO_PASS" ]]; then
        # verdict空+bc全yes → PASS自動設定
        bash "$0" "$REPORT_PATH" verdict PASS 2>/dev/null || true
        echo "★ verdict自動導出: bc全yes+verdict空→PASS自動設定" >&2
    elif [[ "$_cur_verdict" == "AUTO_FAIL" ]]; then
        # verdict空+bc:noあり → FAIL自動設定
        bash "$0" "$REPORT_PATH" verdict FAIL 2>/dev/null || true
        echo "★ verdict自動導出: bc:no検出+verdict空→FAIL自動設定" >&2
    fi
fi

# --- 記憶DB: report event INSERT (非破壊的) ---
# フィールド書込み成功後にeventsテーブルへevent_type=reportでINSERT。
# INSERT失敗時も報告YAML書込みは成功扱い(AC2: 非破壊的追加)
_MEMORY_DB_INSERT_SCRIPT="$SCRIPT_DIR/scripts/memory_db_live_insert_async.py"
if [ -f "$_MEMORY_DB_INSERT_SCRIPT" ] && [ -f "$REPORT_PATH" ]; then
    printf -v _rfs_ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1
    # Extract agent/parent_cmd from filename via bash string ops (avoids awk subprocess).
    # Standard report filename: {agent}_report_{parent_cmd}.yaml
    _rfs_basename="${REPORT_PATH##*/}"
    if [[ "$_rfs_basename" == *"_report_"* ]]; then
        _rfs_agent="${_rfs_basename%%_report_*}"
        _rfs_parent_cmd_tmp="${_rfs_basename#*_report_}"
        _rfs_parent_cmd="${_rfs_parent_cmd_tmp%.yaml}"
    else
        _rfs_agent=""
        _rfs_parent_cmd=""
    fi
    # Verdict is known only when we just wrote it; otherwise empty (DB stores partial record).
    if [[ "$DOT_KEY" == "verdict" ]]; then
        _rfs_verdict="$VALUE"
    else
        _rfs_verdict=""
    fi
    python3 "$_MEMORY_DB_INSERT_SCRIPT" report \
        --report-path "$REPORT_PATH" \
        --ts "$_rfs_ts" \
        --agent "${_rfs_agent:-unknown}" \
        --parent-cmd "${_rfs_parent_cmd:-}" \
        --verdict "${_rfs_verdict:-}" \
        --dot-key "$DOT_KEY" \
        --source-file "$REPORT_PATH" \
        >/dev/null 2>&1 &
    disown 2>/dev/null || true
fi
