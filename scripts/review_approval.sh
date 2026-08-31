#!/usr/bin/env bash
# Usage: review_approval.sh <cmd_id> <gunshi|karo> <LGTM|ACCEPT|RC> <report_path> [auto|implementation|report]
#    or: review_approval.sh <cmd_id> karo RC_REVOKE <report_path> <reason>
set -euo pipefail
ROOT=${REVIEW_APPROVAL_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
source "$ROOT/scripts/lib/review_approval.sh"
source "$ROOT/scripts/lib/yaml_field_set.sh"
if [ -f "$ROOT/scripts/lib/lock_path.sh" ]; then
  source "$ROOT/scripts/lib/lock_path.sh"
else
  # Unit fixtures may copy only the approval entrypoint. Preserve the shared
  # report-unit lock contract without requiring the helper in the fixture.
  lock_path() { printf '%s.lock\n' "$1"; }
fi
defense_writer="$ROOT/scripts/lib/defense_overhead_writer.sh"
[ -f "$defense_writer" ] || defense_writer="$(cd "$(dirname "$0")" && pwd)/lib/defense_overhead_writer.sh"
DEFENSE_OVERHEAD_REPO_ROOT="${DEFENSE_OVERHEAD_REPO_ROOT:-$ROOT}"
source "$defense_writer"
REVIEW_APPROVAL_TOTAL_T0_US="${EPOCHREALTIME/./}"
REVIEW_APPROVAL_TOTAL_T0_US="${REVIEW_APPROVAL_TOTAL_T0_US:0:16}"
REVIEW_APPROVAL_TOTAL_RECORDED=0
review_approval_record_total() {
  local rc="${1:-0}" now_us wall_ms verdict
  [ "${REVIEW_APPROVAL_TOTAL_RECORDED:-0}" -eq 0 ] || return 0
  REVIEW_APPROVAL_TOTAL_RECORDED=1
  now_us="${EPOCHREALTIME/./}"
  now_us="${now_us:0:16}"
  wall_ms=$(( (now_us - REVIEW_APPROVAL_TOTAL_T0_US + 999) / 1000 ))
  verdict=PASS
  [ "$rc" -eq 0 ] || verdict=FAIL
  defense_overhead_write_async review_approval review_approval_total "$wall_ms" "$verdict" \
    "review-approval-${BASHPID}-${REVIEW_APPROVAL_TOTAL_T0_US}" || true
}
review_approval_total_on_exit() { local rc=$?; review_approval_record_total "$rc"; return "$rc"; }
trap review_approval_total_on_exit EXIT
if [ "$#" -lt 4 ] || [ "$#" -gt 5 ]; then
  echo "Usage: $0 <cmd_id> <gunshi|karo> <LGTM|ACCEPT|RC> <report_path> [auto|implementation|report]" >&2
  echo "   or: $0 <cmd_id> karo RC_REVOKE <report_path> <reason>" >&2
  exit 2
fi
cmd_id=$1; role=$2; result=$3; report=$4
# "-" (not ":-") so an explicitly empty 5th arg is distinguishable from an
# omitted one; RC_REVOKE's reason validation depends on seeing the real "".
requested_scope=${5-auto}
case "$role:$result" in gunshi:LGTM|karo:ACCEPT|karo:RC|karo:RC_REVOKE) ;; *) echo "BLOCK: invalid role/result" >&2; exit 2;; esac
if [ "$role:$result" = "gunshi:LGTM" ] \
  && [ "${REVIEW_APPROVAL_CANONICAL_ENTRY:-}" != review_bundle ] \
  && [ "${REVIEW_APPROVAL_SKIP_LEDGER_CHECK:-0}" != 1 ]; then
  echo "BLOCK: direct Gunshi LGTM is not a normal entry point." >&2
  echo "  正規入口: python3 scripts/review_bundle.py single --cmd '$cmd_id' --verdict APPROVE --report '$report' --review-entry <review-entry.yaml>" >&2
  echo "  正規入口がbundle生成→ledger追記→approval→notifyを一試行で実行する。" >&2
  exit 2
fi
if [ "$role:$result" = "karo:RC_REVOKE" ]; then
  # RC_REVOKE の第5引数は scope 語ではなく撤回理由(必須・自由文でよい。表示型の
  # 作文強要はしない=殿裁定07-20。空文字のみ機械的に拒否する)。
  revoke_reason=$requested_scope
  [ -n "$(printf '%s' "$revoke_reason" | tr -d '[:space:]')" ] || {
    echo "BLOCK: RC_REVOKE requires a non-empty reason as the 5th argument" >&2
    exit 2
  }
  requested_scope=auto
else
  case "$requested_scope" in auto|implementation|report) ;; *) echo "BLOCK: invalid correction scope: $requested_scope" >&2; exit 2;; esac
fi
[ "$result" = RC ] || [ "$requested_scope" != implementation ] || {
  echo "BLOCK: implementation scope is only valid when recording Karo RC" >&2
  exit 2
}
[ "$role" = gunshi ] || [ "$requested_scope" != report ] || [ "$result" = RC ] || {
  echo "BLOCK: only Gunshi LGTM may attest a legacy report-only correction" >&2
  exit 2
}
[[ "$report" = /* ]] || report="$ROOT/$report"
PROJECT_ROOT="$ROOT" review_validate_report "$cmd_id" "$report" || { echo "BLOCK: invalid cmd/report boundary or parent_cmd mismatch" >&2; exit 2; }
report=$(realpath "$report")
report_logical=$(PROJECT_ROOT="$ROOT" review_report_logical_path "$report") || {
  echo "BLOCK: report logical path resolution failed: $report" >&2
  exit 2
}
rc_restore_snapshot_common() {
  local snap="$1" task_path="$2" report_path="$3" approval_dir="$4" approval_base="$5" restore_worker="$6"
  local scope_path="$7" commit_path="$8" payload_path="$9" expected_task_sha="${10}" expected_report_sha="${11}"
  local actual_task_sha actual_report_sha tmp i src dest restore_ok=1 manifest
  [ -f "$snap/task.yaml" ] && [ -f "$snap/report.yaml" ] || return 1
  python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1],encoding="utf-8")); yaml.safe_load(open(sys.argv[2],encoding="utf-8"))' \
    "$snap/task.yaml" "$snap/report.yaml" >/dev/null 2>&1 || return 1
  actual_task_sha=$(sha256sum "$snap/task.yaml" | awk '{print $1}')
  actual_report_sha=$(sha256sum "$snap/report.yaml" | awk '{print $1}')
  [ "$actual_task_sha" = "$expected_task_sha" ] && [ "$actual_report_sha" = "$expected_report_sha" ] || return 1
  [[ "$expected_task_sha" =~ ^[0-9a-f]{64}$ ]] && [[ "$expected_report_sha" =~ ^[0-9a-f]{64}$ ]] || return 1
  local -a srcs=(task.yaml report.yaml karo.yaml gunshi.yaml gunshi_notice.sent review_gate.done gunshi_notify.done last_rc_scope last_rc_commit last_rc_report_payload karo_rework.seen last_rc_snapshot_pointer)
  local -a dests=("$task_path" "$report_path" "$approval_dir/karo.yaml" "$approval_dir/gunshi.yaml" "$approval_dir/gunshi_notice.sent" "$ROOT/queue/gates/$cmd_id/review_gate.done" "$ROOT/queue/gates/$cmd_id/gunshi_report_review_notify_${restore_worker}.done" "$scope_path" "$commit_path" "$payload_path" "$approval_base/karo_rework.seen" "$approval_dir/last_rc_snapshot_dir")
  # Validate every source before the first operational file is replaced.
  for ((i=0; i<${#srcs[@]}; i++)); do
    src="$snap/${srcs[$i]}"
    [ ! -e "$src" ] || { [ -f "$src" ] && [ ! -L "$src" ]; } || return 1
  done
  if [ -e "$snap/gate_triggered.manifest" ] || [ -e "$snap/gate_triggered.marker" ]; then
    [ -f "$snap/gate_triggered.manifest" ] && [ ! -L "$snap/gate_triggered.manifest" ] \
      && [ -f "$snap/gate_triggered.marker" ] && [ ! -L "$snap/gate_triggered.marker" ] || return 1
    manifest=$(head -n 1 "$snap/gate_triggered.manifest")
    [[ "$manifest" =~ ^[0-9a-f]{64}$ ]] || return 1
    [ "$(wc -l < "$snap/gate_triggered.manifest")" -eq 1 ] || return 1
  fi
  for ((i=0; i<${#srcs[@]}; i++)); do
    src="$snap/${srcs[$i]}"; dest="${dests[$i]}"
    if [ -f "$src" ]; then
      mkdir -p "${dest%/*}"; tmp=$(mktemp "${dest}.rc-restore.XXXXXX") || return 1
      cp -f "$src" "$tmp" && mv -f "$tmp" "$dest" || { rm -f "$tmp"; restore_ok=0; break; }
      cmp -s "$src" "$dest" || { restore_ok=0; break; }
    else
      rm -f "$dest"; [ ! -e "$dest" ] || { restore_ok=0; break; }
    fi
  done
  [ "$restore_ok" -eq 1 ] || return 1
  if [ -f "$snap/gate_triggered.manifest" ]; then
    dest="$approval_base/.gate_triggered.$manifest"; tmp=$(mktemp "${dest}.rc-restore.XXXXXX") || return 1
    cp -f "$snap/gate_triggered.marker" "$tmp" && mv -f "$tmp" "$dest" || return 1
    cmp -s "$snap/gate_triggered.marker" "$dest" || return 1
  fi
  cmp -s "$snap/task.yaml" "$task_path" && cmp -s "$snap/report.yaml" "$report_path"
}
# Recover an interrupted formal-RC transaction before lifecycle validation:
# the orphaned report may intentionally be revision_requested+PASS, which is
# invalid as a submitted report but is valid evidence of the interrupted write.
early_base="$ROOT/queue/gates/$cmd_id/review_approvals"
early_fence="$early_base/.rc_identity_transaction"
if [ "$role:$result" = karo:RC ] && [ -f "$early_fence" ]; then
  mkdir -p "$early_base"
  exec 200>"$early_base/.lock"; flock -w 10 200
  early_journal=$(python3 - "$early_fence" <<'PY'
import re, sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
required = ("cmd_id", "worker_id", "report", "snapshot_dir", "task_sha256", "report_sha256")
if any(not isinstance(d.get(k), str) or not d[k] for k in required): raise SystemExit(1)
if not re.fullmatch(r"[a-z][a-z0-9_-]*", d["worker_id"]): raise SystemExit(1)
if not re.fullmatch(r"[0-9a-f]{64}", d["task_sha256"]): raise SystemExit(1)
if not re.fullmatch(r"[0-9a-f]{64}", d["report_sha256"]): raise SystemExit(1)
for k in required: print(d[k])
PY
) || { echo "BLOCK: orphan RC journal invalid" >&2; exit 1; }
  early_journal_cmd=$(printf '%s\n' "$early_journal" | sed -n 1p)
  early_worker=$(printf '%s\n' "$early_journal" | sed -n 2p)
  early_journal_report=$(printf '%s\n' "$early_journal" | sed -n 3p)
  early_snapshot=$(printf '%s\n' "$early_journal" | sed -n 4p)
  early_task_sha=$(printf '%s\n' "$early_journal" | sed -n 5p)
  early_report_sha=$(printf '%s\n' "$early_journal" | sed -n 6p)
  [ "$early_journal_cmd" = "$cmd_id" ] && [ "$early_journal_report" = "$report_logical" ] || {
    echo "BLOCK: orphan RC journal identity mismatch" >&2; exit 1;
  }
  early_report_worker=$(python3 - "$report" <<'PY'
import sys,yaml
print(str((yaml.safe_load(open(sys.argv[1],encoding="utf-8")) or {}).get("worker_id") or ""))
PY
) || exit 1
  [ "$early_report_worker" = "$early_worker" ] || { echo "BLOCK: orphan RC worker mismatch" >&2; exit 1; }
  early_task="$ROOT/queue/tasks/$early_worker.yaml"
  early_key=$(review_report_key "$report_logical")
  early_dir="$early_base/reports/$early_key"
  mkdir -p "$ROOT/queue/locks"
  exec 201>"$ROOT/queue/locks/deploy_ninja_${early_worker}.lock"; flock -w 10 201
  early_live="$ROOT/$report_logical"
  exec 202>"$(lock_path "${early_live}.report-unit")"; flock -w 10 202
  early_snapshot=$(realpath -m "$early_snapshot" 2>/dev/null || true)
  [[ "$early_snapshot" == "$early_dir"/.pre_rc_snapshot.* ]] \
    && [ -f "$early_snapshot/task.yaml" ] && [ -f "$early_snapshot/report.yaml" ] || {
      echo "BLOCK: orphan RC identity fence has invalid snapshot: $early_fence" >&2; exit 1;
    }
  early_rejected_commit="$early_dir/last_rc_commit"
  early_rejected_payload="$early_dir/last_rc_report_payload"
  early_scope="$early_dir/last_rc_scope"
  rc_restore_snapshot_common "$early_snapshot" "$early_task" "$early_live" "$early_dir" "$early_base" "$early_worker" \
    "$early_scope" "$early_rejected_commit" "$early_rejected_payload" "$early_task_sha" "$early_report_sha" || {
    echo "BLOCK: orphan RC exact restore verification failed" >&2; exit 1;
  }
  rm -f "$early_fence"; [ ! -e "$early_fence" ] || { echo "BLOCK: orphan fence removal failed" >&2; exit 1; }
  early_test_fault="${REVIEW_APPROVAL_TEST_RC_FAULT:-}"
  if [ "$early_test_fault" = orphan_restored_stop ] \
    && [ -n "${BATS_TEST_TMPDIR:-}" ] && [[ "$ROOT" == "$BATS_TEST_TMPDIR"/* ]]; then
    flock -u 202; flock -u 201; flock -u 200
    exit 98
  fi
  flock -u 202; flock -u 201; flock -u 200
  bash "$0" "$cmd_id" "$role" "$result" "$early_live" "$requested_scope"
  exit $?
fi
# A formal decision is valid only for a submitted report.  Karo RC moves the
# report to revision_requested before waking the worker; without this guard a
# delayed Gunshi review can bind LGTM to that post-RC document and recreate a
# stale approval after RC invalidation.
report_lifecycle=$(python3 - "$report" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
print(str(data.get("status") or "").strip())
print(str(data.get("verdict") or "").strip().upper())
PY
) || { echo "BLOCK: report status unreadable: $report" >&2; exit 1; }
report_status=$(printf '%s\n' "$report_lifecycle" | sed -n 1p)
report_verdict=$(printf '%s\n' "$report_lifecycle" | sed -n 2p)
# cmd_karo_impl_b28_failed_report_close_20260726 (B28):
# verdict=FAIL は report_field_set が status=failed へ落とすため、B21のFAIL_CLOSE経路が
# 要求する証跡(review_approvals/reports/*/karo.yaml)を作る手段が存在しなかった
# (この guard が status=completed のみを通すため)。failed も家老へ提出済みの終端報告で
# あることに変わりはないので、家老のACCEPTに限り受け付ける。CLEARは捏造しない
# (下流の review_gate.done 生成と GATE trigger は fail_close=1 で明示的にスキップする)。
fail_close=0
if [ "$report_status" = "failed" ] && [ "$role:$result" = "karo:ACCEPT" ] && [ "$report_verdict" = "FAIL" ]; then
  fail_close=1
fi
# A truthful failed report can be approved as a report attestation by Gunshi.
# This records review quality without turning the failed implementation into a
# successful completion; the later review_all_reports_ready path still excludes
# it from CLEAR until Karo performs the explicit fail-close.
honest_fail=0
if [ "$report_status" = "failed" ] && [ "$report_verdict" = "FAIL" ] \
  && [ "$role:$result" = "gunshi:LGTM" ] && [ "$requested_scope" = report ]; then
  honest_fail=1
fi
failed_rc=0
if [ "$report_status" = "failed" ] && [ "$role:$result" = "karo:RC" ] && [ "$report_verdict" = "FAIL" ]; then
  failed_rc=1
fi
[ "$report_status" = "completed" ] || [ "$fail_close" = 1 ] || [ "$honest_fail" = 1 ] || [ "$failed_rc" = 1 ] || [ "$role:$result" = "karo:RC_REVOKE" ] || {
  if [ "$report_verdict" = "PASS" ]; then
    echo "BLOCK: nonterminal report cannot carry verdict=PASS (status=${report_status:-missing}); normalize atomically: bash scripts/report_field_set.sh '$report' status completed" >&2
    exit 1
  fi
  echo "BLOCK: formal review requires status=completed (actual=${report_status:-missing}): $report" >&2
  exit 1
}

# A failed RC can truthfully have no implementation commit.  Admit that narrow
# exception only after binding the report to the worker's current task.  This
# precheck deliberately precedes the fingerprint commit-identity gate; normal
# completed reports and failed reports for another task never receive it.
identity_exempt="$fail_close"
[ "$honest_fail" = 1 ] && identity_exempt=1
if [ "$failed_rc" = 1 ]; then
  failed_rc_boundary=$(python3 - "$ROOT" "$report" "$cmd_id" <<'PY'
import pathlib, sys, yaml
root = pathlib.Path(sys.argv[1])
report = yaml.safe_load(open(sys.argv[2], encoding="utf-8")) or {}
cmd_id = sys.argv[3]
worker = str(report.get("worker_id") or "")
if not worker or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789_-" for c in worker):
    raise SystemExit(1)
task_path = root / "queue" / "tasks" / f"{worker}.yaml"
task_doc = yaml.safe_load(task_path.read_text(encoding="utf-8")) or {}
task = task_doc.get("task") or {}
task_id = str(task.get("task_id") or task.get("_ac_task_id") or "")
report_task_id = str(report.get("task_id") or "")
task_parent = str(task.get("parent_cmd") or "")
issued_cmd_id = str(task.get("issued_cmd_id") or "")
normal = not cmd_id.startswith("cmd_karo_") and task_parent == cmd_id
karo_direct = cmd_id.startswith("cmd_karo_") and (task_parent == cmd_id or issued_cmd_id == cmd_id)
if not ((normal or karo_direct) and task_id and report_task_id == task_id):
    raise SystemExit(1)
print(task_path)
PY
  ) || { echo "BLOCK: failed RC report/task identity mismatch: $report" >&2; exit 1; }
  identity_exempt=1
fi
base="$ROOT/queue/gates/$cmd_id/review_approvals"
mkdir -p "$base"
exec 200>"$base/.lock"; flock -w 10 200
fingerprint=$(REVIEW_FAIL_CLOSE_IDENTITY_EXEMPT="$identity_exempt" review_report_fingerprint "$report") || { echo "BLOCK: report missing or commit_hash absent: $report" >&2; exit 1; }
# Finalize telemetry joins against SG7 review.report_fingerprint, whose contract
# is the SHA-256 of the report's exact bytes.  The approval fingerprint above is
# intentionally normalized for review stability and therefore is not the same
# lifecycle generation.
canonical_generation=$(sha256sum "$report" | awk '{print $1}')
[[ "$canonical_generation" =~ ^[0-9a-f]{64}$ ]] || { echo "BLOCK: canonical report generation unavailable: $report" >&2; exit 1; }
report_rel=${report#"$ROOT"/}; report_key=$(review_report_key "$report_logical")
dir="$base/reports/$report_key"; mkdir -p "$dir"
# A Karo ACCEPT is terminal only when the canonical Gunshi LGTM for this exact
# report generation already exists.  Previously the normal ACCEPT path relied
# on review_all_reports_ready() later in the asynchronous completion flow; that
# let Karo publish an ACCEPT first, after which a delayed LGTM created a
# reversed_lgtm_to_karo_accept interval.  Fail before any Karo marker is
# written, and keep the failed-report close exception below intact.
if [ "$role:$result" = karo:ACCEPT ] && [ "$fail_close" != 1 ]; then
  gunshi_result=$(review_approval_value "$dir/gunshi.yaml" result 2>/dev/null || true)
  gunshi_fp=$(review_approval_value "$dir/gunshi.yaml" fingerprint 2>/dev/null || true)
  gunshi_report=$(review_approval_value "$dir/gunshi.yaml" report 2>/dev/null || true)
  if [ "$gunshi_result" != LGTM ] || [ "$gunshi_fp" != "$fingerprint" ] \
    || { [ -n "$gunshi_report" ] && [ "$gunshi_report" != "$report_rel" ]; }; then
    echo "BLOCK: Karo ACCEPT requires current Gunshi LGTM before ACCEPT: $report_rel" >&2
    exit 1
  fi
fi
# An RC means the reviewed implementation was not acceptable.  Re-submitting
# the same implementation commit merely by toggling report lifecycle fields
# recreates the handoff without changing the artifact.  Persist the rejected
# commit identity and fail closed until a new implementation commit exists.
# No-code reviews are content-bound instead and therefore excluded here.
rejected_commit_file="$dir/last_rc_commit"
rejected_payload_file="$dir/last_rc_report_payload"
rc_scope_file="$dir/last_rc_scope"
# The fingerprint is the normalized content hash alone (3718e7245 / cmd_4156);
# ${fingerprint##*:} returned the whole hash, so the no-code test below was
# always false.  Read the gate's decided commit identity instead.
current_commit=$(REVIEW_FAIL_CLOSE_IDENTITY_EXEMPT="$identity_exempt" review_report_commit_identity "$report" 2>/dev/null || true)
stored_scope=$(head -n 1 "$rc_scope_file" 2>/dev/null || true)
case "$stored_scope" in implementation|report) ;; *) stored_scope="" ;; esac
if [ "$result" = RC ]; then
  if [ "$requested_scope" = auto ]; then
    [ "$current_commit" = "no-code-change" ] && correction_scope=report || correction_scope=implementation
  else
    correction_scope=$requested_scope
  fi
elif [ "$requested_scope" = report ]; then
  # Legacy RC records predate last_rc_scope.  A fresh Gunshi review may
  # explicitly attest that only the report payload required correction.
  correction_scope=report
else
  correction_scope=${stored_scope:-implementation}
fi

# Validate the RC redeployment target before writing any durable review or
# rework state.  A stale report can outlive the worker's task pointer; recording
# karo.yaml/last_rc_* first would leave a false RC history even though no task
# was reopened.
if [ "$role:$result" = "karo:RC" ]; then
  worker_id=$(python3 - "$report" <<'PY'
import re, sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
worker = str(data.get("worker_id") or "")
if not re.fullmatch(r"[a-z][a-z0-9_-]*", worker):
    raise SystemExit(1)
print(worker)
PY
  ) || { echo "BLOCK: RC report worker_id missing or invalid: $report_rel" >&2; exit 1; }
  task_file="$ROOT/queue/tasks/$worker_id.yaml"
  [ -f "$task_file" ] || { echo "BLOCK: RC worker task not found: $worker_id" >&2; exit 1; }
  task_boundary=$(python3 - "$task_file" "$report" "$cmd_id" <<'PY'
import sys, yaml
task_doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
report = yaml.safe_load(open(sys.argv[2], encoding="utf-8")) or {}
task = task_doc.get("task") or {}
cmd_id = sys.argv[3]
task_parent = str(task.get("parent_cmd") or "")
task_id = str(task.get("task_id") or task.get("_ac_task_id") or "")
report_task_id = str(report.get("task_id") or "")
issued_cmd_id = str(task.get("issued_cmd_id") or "")

# Normal Shogun commands remain bound by parent_cmd.  Karo-direct deployment
# has a separate worker task identity; its canonical command edge is the
# deploy-time issued_cmd_id, and both sides must name the exact same task.
normal = not cmd_id.startswith("cmd_karo_") and task_parent == cmd_id
karo_direct = (
    cmd_id.startswith("cmd_karo_")
    and (task_parent == cmd_id or issued_cmd_id == cmd_id)
    and task_id != ""
    and report_task_id == task_id
)
if not (normal or karo_direct):
    raise SystemExit(1)
print(f"parent={task_parent or 'missing'} task_id={task_id or 'missing'} issued_cmd_id={issued_cmd_id or 'missing'}")
PY
  ) || {
    echo "BLOCK: RC worker task boundary mismatch: worker=$worker_id expected_cmd=$cmd_id" >&2
    exit 1
  }
fi

# cmd_karo_impl_rc_revoke_command_20260727: revoke a mistaken Karo RC by
# restoring the pre-RC snapshot and retreating (not deleting) the erroneous
# formal record. Must run before the implementation/report "unchanged since RC"
# guards below, which would otherwise fire on the very commit/payload the RC
# rejected and re-block the revoke itself.
if [ "$role:$result" = "karo:RC_REVOKE" ]; then
  worker_id=$(python3 - "$report" <<'PY'
import re, sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
worker = str(data.get("worker_id") or "")
if not re.fullmatch(r"[a-z][a-z0-9_-]*", worker):
    raise SystemExit(1)
print(worker)
PY
  ) || { echo "BLOCK: RC_REVOKE report worker_id missing or invalid: $report_rel" >&2; exit 1; }
  task_file="$ROOT/queue/tasks/$worker_id.yaml"
  [ -f "$task_file" ] || { echo "BLOCK: RC_REVOKE worker task not found: $worker_id" >&2; exit 1; }
  snapshot_pointer="$dir/last_rc_snapshot_dir"
  [ -f "$snapshot_pointer" ] || { echo "BLOCK: no recorded Karo RC to revoke for report: $report_rel" >&2; exit 1; }
  snapshot_dir=$(head -n 1 "$snapshot_pointer")
  [ -d "$snapshot_dir" ] || { echo "BLOCK: RC snapshot directory missing: $snapshot_dir" >&2; exit 1; }

  # A worker may publish a newer completed report generation before Karo
  # revokes the earlier RC.  The pre-RC snapshot is authoritative only for
  # the report generation that created it; restoring it over a newer report
  # would silently roll back valid work and can trip the immutable terminal
  # gate.  Older snapshots predate this sidecar, so retain their historical
  # restore behavior until a new RC records the generation boundary.
  snapshot_fingerprint=$(cat "$snapshot_dir/report_fingerprint" 2>/dev/null || true)
  if [ -z "$snapshot_fingerprint" ]; then
    # Legacy RC snapshots predate the report_fingerprint sidecar.  Recover the
    # rejected generation from the live Karo RC marker, but authenticate the
    # marker's report identity before using its fingerprint as a fallback.
    marker_report=$(review_approval_value "$dir/karo.yaml" report 2>/dev/null || true)
    marker_role=$(review_approval_value "$dir/karo.yaml" role 2>/dev/null || true)
    marker_result=$(review_approval_value "$dir/karo.yaml" result 2>/dev/null || true)
    marker_fingerprint=$(review_approval_value "$dir/karo.yaml" fingerprint 2>/dev/null || true)
    [ "$marker_report" = "$report_rel" ] || {
      echo "BLOCK: legacy RC marker report identity mismatch: expected=$report_rel actual=${marker_report:-missing}" >&2
      exit 1
    }
    [ "$marker_role" = karo ] && [ "$marker_result" = RC ] || {
      echo "BLOCK: legacy RC marker decision identity mismatch: role=${marker_role:-missing} result=${marker_result:-missing}" >&2
      exit 1
    }
    [[ "$marker_fingerprint" =~ ^[0-9a-f]{64}$ ]] || {
      echo "BLOCK: legacy RC marker fingerprint missing or invalid: $report_rel" >&2
      exit 1
    }
    snapshot_fingerprint="$marker_fingerprint"
  fi
  [[ "$snapshot_fingerprint" =~ ^[0-9a-f]{64}$ ]] || {
    echo "BLOCK: RC snapshot fingerprint missing or invalid: $snapshot_dir" >&2
    exit 1
  }
  if [ -n "$snapshot_fingerprint" ] && [ "$snapshot_fingerprint" != "$fingerprint" ]; then
    archive_dir="$ROOT/queue/archive/rc_erroneous/${cmd_id}_$(date +%Y%m%d%H%M%S)_${worker_id}"
    mkdir -p "$archive_dir"
    [ -f "$dir/karo.yaml" ] && mv -f "$dir/karo.yaml" "$archive_dir/karo.yaml"
    for rc_marker in last_rc_scope last_rc_commit last_rc_report_payload karo_rework.seen; do
      marker_path="$dir/$rc_marker"
      [ -f "$marker_path" ] && mv -f "$marker_path" "$archive_dir/$rc_marker"
    done
    printf 'reason: %s\ncmd_id: %s\nreport: %s\nworker_id: %s\nrevoked_at: %s\n' \
      "$revoke_reason" "$cmd_id" "$report_rel" "$worker_id" "$(date -Iseconds)" > "$archive_dir/reason.yaml"
    mv -f "$snapshot_dir" "$archive_dir/pre_rc_snapshot"
    rm -f "$snapshot_pointer"
    echo "review approval revoked without restoring newer report generation: $cmd_id $role $result report=$report_rel archive=${archive_dir#"$ROOT"/}"
    exit 0
  fi

  pre_report_status=$(cat "$snapshot_dir/report_status" 2>/dev/null || true)
  [ -n "$pre_report_status" ] || { echo "BLOCK: RC snapshot missing report_status: $snapshot_dir" >&2; exit 1; }
  pre_report_id=$(cat "$snapshot_dir/report_id" 2>/dev/null || true)
  if [ -f "$snapshot_dir/report.yaml" ]; then
    report_restore_lock=$(lock_path "$report")
    report_restore_tmp=$(mktemp "${report}.rc-revoke.XXXXXX") || exit 1
    cp -f "$snapshot_dir/report.yaml" "$report_restore_tmp"
    python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1], encoding="utf-8"))' \
      "$report_restore_tmp" >/dev/null
    exec 204>"$report_restore_lock"
    flock -w 10 204 || { rm -f "$report_restore_tmp"; exit 1; }
    mv -f "$report_restore_tmp" "$report"
  elif [ -f "$snapshot_dir/report_id" ]; then
    bash "$ROOT/scripts/report_field_set.sh" "$report" report_id "$pre_report_id"
    bash "$ROOT/scripts/report_field_set.sh" "$report" status "$pre_report_status"
  else
    # Legacy snapshots predate formal-RC identity rotation.
    bash "$ROOT/scripts/report_field_set.sh" "$report" status "$pre_report_status"
  fi

  # cmd_karo_hotfix_rc_task_status_reset_20260727: one atomic batch write
  # instead of N separate yaml_field_set.sh invocations (N separate
  # flock-acquire/release cycles). Between two individual calls the lock is
  # released, leaving a window where an independent writer (e.g. ninja_monitor
  # AUTO-DONE) can interleave and observe/leave a half-restored task state.
  if [ -f "$snapshot_dir/task.yaml" ]; then
    task_restore_lock=$(lock_path "$task_file")
    task_restore_tmp=$(mktemp "${task_file}.rc-revoke.XXXXXX") || exit 1
    cp -f "$snapshot_dir/task.yaml" "$task_restore_tmp"
    python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1], encoding="utf-8"))' \
      "$task_restore_tmp" >/dev/null
    exec 203>"$task_restore_lock"
    flock -w 10 203 || { rm -f "$task_restore_tmp"; exit 1; }
    mv -f "$task_restore_tmp" "$task_file"
  else
    restore_pairs=()
    while IFS='=' read -r field value; do
      [ -n "$field" ] || continue
      restore_pairs+=("${field}=${value}")
    done < "$snapshot_dir/task_fields"
    [ "${#restore_pairs[@]}" -eq 0 ] || yaml_field_set_batch "$task_file" task "${restore_pairs[@]}"
  fi

  for marker in gunshi.yaml gunshi_notice.sent; do
    if [ -f "$snapshot_dir/$marker" ]; then
      cp -f "$snapshot_dir/$marker" "$dir/$marker"
    else
      rm -f "$dir/$marker"
    fi
  done
  if [ -f "$snapshot_dir/review_gate.done" ]; then
    mkdir -p "$ROOT/queue/gates/$cmd_id"
    cp -f "$snapshot_dir/review_gate.done" "$ROOT/queue/gates/$cmd_id/review_gate.done"
  else
    rm -f "$ROOT/queue/gates/$cmd_id/review_gate.done"
  fi
  notify_marker="$ROOT/queue/gates/$cmd_id/gunshi_report_review_notify_${worker_id}.done"
  if [ -f "$snapshot_dir/gunshi_notify.done" ]; then
    cp -f "$snapshot_dir/gunshi_notify.done" "$notify_marker"
  else
    rm -f "$notify_marker"
  fi

  if [ -f "$snapshot_dir/last_rc_scope" ]; then cp -f "$snapshot_dir/last_rc_scope" "$rc_scope_file"; else rm -f "$rc_scope_file"; fi
  if [ -f "$snapshot_dir/last_rc_commit" ]; then cp -f "$snapshot_dir/last_rc_commit" "$rejected_commit_file"; else rm -f "$rejected_commit_file"; fi
  if [ -f "$snapshot_dir/last_rc_report_payload" ]; then cp -f "$snapshot_dir/last_rc_report_payload" "$rejected_payload_file"; else rm -f "$rejected_payload_file"; fi
  if [ -f "$snapshot_dir/karo_rework.seen" ]; then cp -f "$snapshot_dir/karo_rework.seen" "$base/karo_rework.seen"; else rm -f "$base/karo_rework.seen"; fi

  # Retreat (not delete) the erroneous RC's own formal record and its snapshot
  # into an audit trail, with the mandatory reason (AC2/AC3: 撤回は退避+理由記録).
  archive_dir="$ROOT/queue/archive/rc_erroneous/${cmd_id}_$(date +%Y%m%d%H%M%S)_${worker_id}"
  mkdir -p "$archive_dir"
  [ -f "$dir/karo.yaml" ] && mv -f "$dir/karo.yaml" "$archive_dir/karo.yaml"
  printf 'reason: %s\ncmd_id: %s\nreport: %s\nworker_id: %s\nrevoked_at: %s\n' \
    "$revoke_reason" "$cmd_id" "$report_rel" "$worker_id" "$(date -Iseconds)" > "$archive_dir/reason.yaml"
  mv -f "$snapshot_dir" "$archive_dir/pre_rc_snapshot"
  rm -f "$snapshot_pointer"

  echo "review approval revoked: $cmd_id $role $result report=$report_rel archive=${archive_dir#"$ROOT"/}"
  exit 0
fi

if [ ! "$role:$result" = "karo:RC" ] && [ "$fail_close" != 1 ] && [ "$correction_scope" = implementation ] \
  && [ -f "$rejected_commit_file" ] && [ "$current_commit" != "no-code-change" ]; then
  rejected_commit=$(head -n 1 "$rejected_commit_file" 2>/dev/null || true)
  if [ -n "$rejected_commit" ] && [ "$rejected_commit" = "$current_commit" ]; then
    # If a precheck CLEAR prediction exists for this cmd, the shared execution
    # plane already passes all gate checks despite the commit being unchanged.
    # This happens when a separate fix (e.g. SG-PRE9c) resolved the prior RC
    # cause without touching the original implementation commit.  Downgrade to
    # WARN so the approval can proceed.
    precheck_clear=0
    _bundle_path="$ROOT/queue/gates/${cmd_id}/sg7_bundle.json"
    if [ -f "$_bundle_path" ]; then
      precheck_clear=1
    fi
    if [ "$precheck_clear" = 1 ]; then
      echo "WARN: implementation commit unchanged since Karo RC ($current_commit) but precheck CLEAR — proceeding" >&2
    else
      echo "BLOCK: implementation commit unchanged since Karo RC: $current_commit" >&2
      exit 1
    fi
  fi
fi
if [ ! "$role:$result" = "karo:RC" ] && [ "$fail_close" != 1 ] && [ "$correction_scope" = report ]; then
  if [ "$role" = gunshi ]; then
    if [ -f "$rejected_payload_file" ]; then
      rejected_payload=$(head -n 1 "$rejected_payload_file" 2>/dev/null || true)
      current_payload=$(review_report_payload_hash "$report" 2>/dev/null || true)
      if [ -z "$current_payload" ] || [ "$current_payload" = "$rejected_payload" ]; then
        echo "BLOCK: report-only payload unchanged since Karo RC" >&2
        exit 1
      fi
    elif [ "$requested_scope" != report ]; then
      echo "BLOCK: legacy RC lacks report payload; Gunshi must attest correction scope=report" >&2
      exit 1
    fi
  else
    gunshi_fp=$(review_approval_value "$dir/gunshi.yaml" fingerprint 2>/dev/null || true)
    gunshi_result=$(review_approval_value "$dir/gunshi.yaml" result 2>/dev/null || true)
    if [ "$gunshi_result" != LGTM ] || [ "$gunshi_fp" != "$fingerprint" ]; then
      echo "BLOCK: report-only correction requires current Gunshi LGTM before Karo ACCEPT" >&2
      exit 1
    fi
  fi
fi
# SG7 used to exist only as a skill instruction: review_bundle.py generate had
# no production caller, so GATE could archive the report before Karo consumed
# the bundle.  Bind generation to the existing formal Gunshi-LGTM boundary.
if [ "$role" = gunshi ] && [ "$result" = LGTM ] \
  && [ "${REVIEW_APPROVAL_CANONICAL_ENTRY:-}" != review_bundle ] \
  && [ -f "$ROOT/scripts/review_bundle.py" ]; then
  sg7_archive_args=()
  [[ "$report_rel" = queue/archive/reports/* ]] && sg7_archive_args+=(--allow-archived)
  [ "$honest_fail" = 1 ] && sg7_archive_args+=(--allow-honest-fail)
  python3 "$ROOT/scripts/review_bundle.py" generate \
    --cmd "$cmd_id" --verdict APPROVE --report "$report_rel" "${sg7_archive_args[@]}" >/dev/null || {
      echo "BLOCK: SG7 bundle generation failed: $cmd_id $report_rel" >&2
      exit 1
    }
fi
# cmd_karo_impl_approval_log_atomic_20260726: 承認発行と台帳記録の不可分化。
# 軍師は本日3回「承認は発行したが logs/gunshi_review_log.yaml を書かなかった」を起こし、
# accuracy が対象を数えない値になった(gate_gunshi_startup.sh:521 が review_type in (draft, report)
# だけを母集団とするため、記録されない承認は「測れない承認」になる)。
# ★向き(2026-07-26 家老訂正): 「承認が記録を書く」ではなく「記録が無ければ承認できない」。
#   台帳エントリの中身(observations / brainwash_check / verified_files / operational_simulation)は
#   軍師が書くものであり、このスクリプトが機械生成できるものは1つも無い。自動生成すれば
#   中身の無いエントリを毎回作り、accuracy から静かに落ちる行を増やすだけである。
# ★前例と同じ形(AC1): commit 0e489017a の lgtm_bundle_guard も「無ければ作る」ではなく
#   「無ければ exit 2 で止める」である。fail-closed に寄せる。
# ★順序: sg7 bundle 生成(上の block)の後に置く。bundle は gunshi_log_append の
#   lgtm_bundle_guard が実在を要求するため、先に生成しておけば
#   「approval(bundle生成) → 軍師が台帳記録 → approval再実行(承認成立)」で循環しない。
# ★karo ACCEPT には課さない(AC4): 台帳は軍師のレビュー記録であり、家老の承認を書くのも
#   前提として課すのも、軍師の accuracy 母集団に家老の判断を持ち込むことになる。
if [ "$role" = gunshi ] && [ "$result" = LGTM ] && [ "${REVIEW_APPROVAL_SKIP_LEDGER_CHECK:-0}" != 1 ]; then
  ledger_file="$ROOT/logs/gunshi_review_log.yaml"
  if ! grep -Eq "^[[:space:]]*-?[[:space:]]*cmd_id:[[:space:]]*[\"']?${cmd_id}[\"']?[[:space:]]*$" "$ledger_file" 2>/dev/null; then
    echo "BLOCK: review ledger entry missing for $cmd_id — approval withheld." >&2
    echo "  正規入口: python3 scripts/review_bundle.py single --cmd '$cmd_id' --verdict APPROVE --report '$report_rel' --review-entry <review-entry.yaml>" >&2
    echo "  この入口がbundle生成→review ledger追記→正式approval→家老通知を一試行で順序保証する。" >&2
    echo "  台帳: ${ledger_file#"$ROOT"/}" >&2
    exit 2
  fi
fi
tmp=$(mktemp "$dir/.${role}.XXXXXX")
pre_rc_karo_marker=""
if [ "$role:$result" = karo:RC ] && [ -f "$dir/karo.yaml" ]; then
  pre_rc_karo_marker=$(mktemp "$dir/.pre_rc_karo.XXXXXX")
  cp -f "$dir/karo.yaml" "$pre_rc_karo_marker"
fi
review_approval_cleanup_on_exit() {
  local rc=$?
  if [ "${RC_IDENTITY_TRANSACTION_ACTIVE:-0}" -eq 1 ] && declare -F rc_identity_rollback >/dev/null; then
    rc_identity_rollback || rc=1
  fi
  rm -f "$tmp" "${pre_rc_karo_marker:-}" "${REVIEW_FP_CACHE_DIR:?}"/*
  rmdir "${REVIEW_FP_CACHE_DIR:?}" 2>/dev/null || true
  review_approval_record_total "$rc"
  return "$rc"
}
trap review_approval_cleanup_on_exit EXIT
# Gunshi approval writes are idempotent per report/fingerprint.  A retry of the
# same LGTM must retain the first durable boundary timestamp; otherwise a
# delayed Gunshi retry moves the measured LGTM edge and can recreate the
# reversed interval this task fixes.  Karo ACCEPT deliberately receives a new
# timestamp on each valid retry so a previously invalid Karo-first record can
# be recovered after the matching LGTM exists.  A changed fingerprint
# (including an RC generation) naturally receives a fresh timestamp.
approval_timestamp="$(date -Iseconds)"
existing_result=$(review_approval_value "$dir/$role.yaml" result 2>/dev/null || true)
existing_fp=$(review_approval_value "$dir/$role.yaml" fingerprint 2>/dev/null || true)
existing_report=$(review_approval_value "$dir/$role.yaml" report 2>/dev/null || true)
existing_timestamp=$(review_approval_value "$dir/$role.yaml" timestamp 2>/dev/null || true)
if [ "$role" = gunshi ] && [ "$existing_result" = "$result" ] && [ "$existing_fp" = "$fingerprint" ] \
  && [ -n "$existing_timestamp" ] \
  && { [ -z "$existing_report" ] || [ "$existing_report" = "$report_rel" ]; }; then
  approval_timestamp="$existing_timestamp"
fi
printf 'timestamp: %s\nrole: %s\nresult: %s\nfingerprint: %s\ngeneration: %s\nreport: %s\ncorrection_scope: %s\n' "$approval_timestamp" "$role" "$result" "$fingerprint" "$canonical_generation" "$report_rel" "$correction_scope" > "$tmp"
mv -f "$tmp" "$dir/$role.yaml"
# The durable approval record is complete.  Do not keep the report approval
# lock across SG7 publication or any completion work: canonical LGTM used to
# invoke review_bundle.notify while fd 200 was still held, and notify then ran
# cmd_complete_gate synchronously.  Karo ACCEPT consequently waited on the
# same lock until rc=1 while the predecessor remained in pipe_read.
flock -u 200 2>/dev/null || true
exec 200>&- || true
# T1a throughput instrumentation: the approval file above is the existing
# durable decision boundary.  Reuse the shared append-only timing ledger and
# bind the id to the report attempt (fingerprint) plus report identity (key).
# Duplicate invocations intentionally keep the original boundary timestamp.
case "$role:$result" in
  gunshi:LGTM)
    defense_overhead_write review_approval gunshi_lgtm 0 PASS \
      "review-approval-gunshi-lgtm-${cmd_id}-${report_key}-${fingerprint}" \
      "{\"cmd_id\":\"${cmd_id}\",\"generation\":\"${canonical_generation}\"}" || true
    ;;
  karo:ACCEPT)
    defense_overhead_write review_approval karo_accept 0 PASS \
      "review-approval-karo-accept-${cmd_id}-${report_key}-${fingerprint}" \
      "{\"cmd_id\":\"${cmd_id}\",\"generation\":\"${canonical_generation}\"}" || true
    ;;
esac
# The canonical APPROVE entry owns SG7 publication.  Publish immediately after
# the durable Gunshi approval record above.  The remaining report resolution,
# manifest, and completion work can exceed the caller's timeout; none of that
# work may be required for Karo to receive the LGTM notification.
if [ "$role" = gunshi ] && [ "$result" = LGTM ] \
  && [ "${REVIEW_APPROVAL_CANONICAL_ENTRY:-}" = review_bundle ]; then
  sg7_bundle="$ROOT/queue/gates/$cmd_id/sg7_bundle.json"
  [ -f "$sg7_bundle" ] || {
    echo "BLOCK: canonical SG7 bundle missing before publication: $cmd_id" >&2
    exit 1
  }
  python3 "$ROOT/scripts/review_bundle.py" notify \
    --cmd "$cmd_id" --bundle "$sg7_bundle" >/dev/null || {
      echo "BLOCK: canonical SG7 publication failed: $cmd_id $report_rel" >&2
      exit 1
    }
fi
if [ "$role" = karo ] && [ "$result" = RC ]; then
  # RC reopening is one lifecycle transaction and the canonical formal entry.
  # ninja_monitor uses this same
  # per-worker lock for AUTO-DONE, so it cannot observe the old completed
  # report between task/report resets or emit report_notification_missing
  # before the fresh task_start notification is durable.
  rc_deploy_lock="$ROOT/queue/locks/deploy_ninja_${worker_id}.lock"
  mkdir -p "${rc_deploy_lock%/*}"
  exec 201>"$rc_deploy_lock"
  flock -w 10 201 || { echo "BLOCK: RC deploy lock timeout: worker=$worker_id" >&2; exit 1; }
  # The live report path is the lifecycle slot even when archive_completed
  # left a compatibility symlink there.  Serialize RC status transition and
  # live-path materialization against archive mv+symlink and deploy template
  # publication with the same report-unit lock.
  rc_report_path="$ROOT/$report_logical"
  rc_report_lock_file="$(lock_path "${rc_report_path}.report-unit")"
  exec 202>"$rc_report_lock_file"
  flock -w 10 202 || { echo "BLOCK: RC report lock timeout: $rc_report_path" >&2; exit 1; }
  if [ -L "$rc_report_path" ]; then
    rc_report_source="$report"
    rc_report_tmp=$(mktemp "${rc_report_path}.rc.XXXXXX")
    cp -- "$rc_report_source" "$rc_report_tmp"
    mv -f -- "$rc_report_tmp" "$rc_report_path"
    echo "formal RC: detached archived compatibility symlink into live report slot: $report_rel"
  fi
  # All subsequent RC mutations must address the logical live slot, never the
  # archived target resolved by realpath().  This preserves the archive hash.
  report="$rc_report_path"
  rc_identity_fence="$base/.rc_identity_transaction"
  # cmd_karo_impl_rc_revoke_command_20260727: snapshot pre-RC state under the
  # same deploy lock so a mistaken RC can be revoked later (incident
  # 2026-07-27 12:47: a correct report was RC'd by mistake with no formal
  # undo path; karo had to hand-retreat the ledger). Captured before any of
  # this block's mutations below.
  snapshot_dir="$dir/.pre_rc_snapshot.$(date +%Y%m%d%H%M%S)_$$"
  mkdir -p "$snapshot_dir"
  printf '%s\n' "$report_status" > "$snapshot_dir/report_status"
  printf '%s\n' "$fingerprint" > "$snapshot_dir/report_fingerprint"
  printf '%s\n' "$canonical_generation" > "$snapshot_dir/report_generation"
  cp -f "$task_file" "$snapshot_dir/task.yaml"
  cp -f "$report" "$snapshot_dir/report.yaml"
  snapshot_task_sha=$(sha256sum "$snapshot_dir/task.yaml" | awk '{print $1}')
  snapshot_report_sha=$(sha256sum "$snapshot_dir/report.yaml" | awk '{print $1}')
  printf '%s\n' "$snapshot_task_sha" > "$snapshot_dir/task.sha256"
  printf '%s\n' "$snapshot_report_sha" > "$snapshot_dir/report.sha256"
  : > "$snapshot_dir/task_fields"
  for field in report_id deployed_at retry_deployed_at status reviewed review_result acknowledged_at completed_at done_at; do
    field_value=$(python3 - "$task_file" "$field" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
task = data.get("task") or {}
value = task.get(sys.argv[2])
if value is None:
    print("")
elif isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
)
    printf '%s=%s\n' "$field" "$field_value" >> "$snapshot_dir/task_fields"
  done
  pre_rc_report_id=$(python3 - "$report" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
print(str(data.get("report_id") or ""))
PY
)
  printf '%s\n' "$pre_rc_report_id" > "$snapshot_dir/report_id"
  [ -f "$dir/gunshi.yaml" ] && cp -f "$dir/gunshi.yaml" "$snapshot_dir/gunshi.yaml"
  [ -f "$dir/gunshi_notice.sent" ] && cp -f "$dir/gunshi_notice.sent" "$snapshot_dir/gunshi_notice.sent"
  if [ -n "$pre_rc_karo_marker" ] && [ -f "$pre_rc_karo_marker" ]; then
    cp -f "$pre_rc_karo_marker" "$snapshot_dir/karo.yaml"
  else
    : > "$snapshot_dir/karo.absent"
  fi
  [ -f "$ROOT/queue/gates/$cmd_id/review_gate.done" ] && cp -f "$ROOT/queue/gates/$cmd_id/review_gate.done" "$snapshot_dir/review_gate.done"
  [ -f "$ROOT/queue/gates/$cmd_id/gunshi_report_review_notify_${worker_id}.done" ] && cp -f "$ROOT/queue/gates/$cmd_id/gunshi_report_review_notify_${worker_id}.done" "$snapshot_dir/gunshi_notify.done"
  [ -f "$rc_scope_file" ] && cp -f "$rc_scope_file" "$snapshot_dir/last_rc_scope"
  [ -f "$rejected_commit_file" ] && cp -f "$rejected_commit_file" "$snapshot_dir/last_rc_commit"
  [ -f "$rejected_payload_file" ] && cp -f "$rejected_payload_file" "$snapshot_dir/last_rc_report_payload"
  [ -f "$base/karo_rework.seen" ] && cp -f "$base/karo_rework.seen" "$snapshot_dir/karo_rework.seen"
  [ -f "$dir/last_rc_snapshot_dir" ] && cp -f "$dir/last_rc_snapshot_dir" "$snapshot_dir/last_rc_snapshot_pointer"
  printf '%s\n' "$snapshot_dir" > "$dir/last_rc_snapshot_dir"
  # Preserve RC as monotonic command history.  The per-report karo.yaml is
  # intentionally overwritten by the later ACCEPT, so it cannot tell the
  # completion-quality logger that rework occurred.
  rework_tmp=$(mktemp "$base/.karo_rework.XXXXXX")
  printf 'timestamp: %s\nsource: formal_karo_rc\n' "$(date -Iseconds)" > "$rework_tmp"
  mv -f "$rework_tmp" "$base/karo_rework.seen"
  scope_tmp=$(mktemp "$dir/.last_rc_scope.XXXXXX")
  printf '%s\n' "$correction_scope" > "$scope_tmp"
  mv -f "$scope_tmp" "$rc_scope_file"
  if [ "$correction_scope" = implementation ]; then
    rejected_tmp=$(mktemp "$dir/.last_rc_commit.XXXXXX")
    printf '%s\n' "$current_commit" > "$rejected_tmp"
    mv -f "$rejected_tmp" "$rejected_commit_file"
    rm -f "$rejected_payload_file"
  else
    rejected_payload=$(review_report_payload_hash "$report") || {
      echo "BLOCK: report-only RC payload hash failed: $report_rel" >&2
      exit 1
    }
    rejected_tmp=$(mktemp "$dir/.last_rc_report_payload.XXXXXX")
    printf '%s\n' "$rejected_payload" > "$rejected_tmp"
    mv -f "$rejected_tmp" "$rejected_payload_file"
    rm -f "$rejected_commit_file"
  fi
  mapfile -t current_reports < <(PROJECT_ROOT="$ROOT" review_resolve_reports "$cmd_id")
  current_manifest=$(PROJECT_ROOT="$ROOT" review_manifest_fingerprint "${current_reports[@]}" 2>/dev/null || true)
  if [ -n "$current_manifest" ] && [ -f "$base/.gate_triggered.$current_manifest" ]; then
    cp -f "$base/.gate_triggered.$current_manifest" "$snapshot_dir/gate_triggered.marker"
    printf '%s\n' "$current_manifest" > "$snapshot_dir/gate_triggered.manifest"
  fi
  rc_identity_fence="$base/.rc_identity_transaction"
  rc_identity_fence_tmp=$(mktemp "$base/.rc_identity_transaction.XXXXXX") || {
    echo "BLOCK: formal RC identity fence allocation failed: $cmd_id" >&2
    exit 1
  }
  printf 'cmd_id: %s\nworker_id: %s\nreport: %s\nold_report_id: %s\nsnapshot_dir: %s\ntask_sha256: %s\nreport_sha256: %s\nstarted_at: %s\n' \
    "$cmd_id" "$worker_id" "$report_logical" "$pre_rc_report_id" "$snapshot_dir" \
    "$snapshot_task_sha" "$snapshot_report_sha" "$(date -Iseconds)" \
    > "$rc_identity_fence_tmp"
  mv -f "$rc_identity_fence_tmp" "$rc_identity_fence"

  rc_identity_rollback() {
    if rc_restore_snapshot_common "$snapshot_dir" "$task_file" "$report" "$dir" "$base" "$worker_id" \
      "$rc_scope_file" "$rejected_commit_file" "$rejected_payload_file" \
      "$snapshot_task_sha" "$snapshot_report_sha"; then
      rm -f "$rc_identity_fence"
      [ ! -e "$rc_identity_fence" ] || return 1
      RC_IDENTITY_TRANSACTION_ACTIVE=0
      return 0
    fi
    echo "BLOCK: formal RC rollback incomplete; identity fence retained: $rc_identity_fence" >&2
    return 1
  }
  RC_IDENTITY_TRANSACTION_ACTIVE=1
  rc_test_fault="${REVIEW_APPROVAL_TEST_RC_FAULT:-}"
  if [ -n "$rc_test_fault" ] \
    && { [ -z "${BATS_TEST_TMPDIR:-}" ] || [[ "$ROOT" != "$BATS_TEST_TMPDIR"/* ]]; }; then
    rc_test_fault=""
  fi
  # RC starts a fresh report-review lifecycle.  Clear both the formal approval
  # markers and inbox_write's completion-notify marker; otherwise a revised
  # report can be resubmitted successfully while Gunshi receives no new review
  # request because the previous completion is still treated as notified.
  rm -f "$dir/gunshi.yaml" \
    "$dir/gunshi_notice.sent" \
    "$ROOT/queue/gates/$cmd_id/review_gate.done" \
    "$ROOT/queue/gates/$cmd_id/gunshi_report_review_notify_${worker_id}.done"
  [ -z "$current_manifest" ] || rm -f "$base/.gate_triggered.$current_manifest"
  # A formal RC starts a new logical report generation. Generate the identity
  # exactly once, then publish report+task while the shared resolver fence is
  # present. Lock-free readers fail closed until success or verified rollback.
  if [ "$rc_test_fault" = id_generation ]; then
    rc_report_id=""
  else
    rc_report_id=$(python3 "$ROOT/scripts/lib/report_unique_identity.py" new \
      --path "$report" --root "$ROOT") || rc_report_id=""
  fi
  if [ -z "$rc_report_id" ]; then
    echo "BLOCK: formal RC report_id generation failed: $report_rel" >&2
    exit 1
  fi
  [[ "$rc_report_id" =~ ^rpt-[0-9a-fA-F-]{36}$ ]] || {
    echo "BLOCK: formal RC generated invalid report_id: $rc_report_id" >&2
    exit 1
  }
  if [ "$rc_test_fault" = report_status ] || ! bash "$ROOT/scripts/report_field_set.sh" "$report" status revision_requested; then
      echo "BLOCK: formal RC report identity publication failed: $report_rel" >&2
      exit 1
  fi
  if [ "$rc_test_fault" = report_id ] || ! bash "$ROOT/scripts/report_field_set.sh" "$report" report_id "$rc_report_id"; then
    echo "BLOCK: formal RC report identity publication rolled back: $report_rel" >&2
    exit 1
  fi
  if [ "$rc_test_fault" = orphan_exit ]; then
    # Test-only abrupt termination simulation: deliberately skip EXIT cleanup.
    trap - EXIT
    exit 97
  fi
  # RC is a real redeployment. Refresh the deployment clock before reopening;
  # otherwise ninja_monitor's Stage-1 timeout measures from the original
  # deployment and can immediately reset the revived task to idle.
  rc_deployed_at=$(date -Iseconds)
  # cmd_karo_hotfix_rc_task_status_reset_20260727: single atomic batch write
  # (1 flock, 1 read-modify-write) instead of 8 separate yaml_field_set.sh
  # invocations. Each individual call previously released and reacquired the
  # lock, leaving 7 windows where an independent writer sharing no lock with
  # this sequence (e.g. a worker session reacting to the just-sent task_start
  # notification, or a monitor process reading a half-updated task file)
  # could observe or leave a state where "status" and the other reset fields
  # disagree — reproducing the 2026-07-27 13:39 incident where kotaro's task
  # kept status=done after a formal RC (bulletin 13:48 manual fix).
  if [ "$rc_test_fault" = task_batch ] || ! yaml_field_set_batch "$task_file" task \
    "report_id=$rc_report_id" \
    "deployed_at=$rc_deployed_at" \
    "retry_deployed_at=$rc_deployed_at" \
    "status=assigned" \
    "review_correction_scope=$correction_scope" \
    "reviewed=false" \
    "review_result=" \
    "acknowledged_at=" \
    "completed_at=" \
    "done_at="; then
    echo "BLOCK: formal RC task/report identity transaction rolled back: worker=$worker_id" >&2
    exit 1
  fi
  # RC_REVOKE compares against the generation produced by this RC, not the
  # pre-RC bytes. Status is normalized by review_report_fingerprint; report_id
  # is not, so pin the post-rotation fingerprint after both writes succeed.
  if [ "$rc_test_fault" = rotated_fingerprint ]; then
    rc_rotated_fingerprint=""
  else
    rc_rotated_fingerprint=$(REVIEW_FAIL_CLOSE_IDENTITY_EXEMPT="$identity_exempt" \
      review_report_fingerprint "$report") || rc_rotated_fingerprint=""
  fi
  if [ -z "$rc_rotated_fingerprint" ]; then
      echo "BLOCK: formal RC rotated report fingerprint unavailable: $report_rel" >&2
      exit 1
  fi
  printf '%s\n' "$rc_rotated_fingerprint" > "$snapshot_dir/report_fingerprint"
  if [ "$rc_test_fault" = fence_remove ] || ! rm -f "$rc_identity_fence" || [ -e "$rc_identity_fence" ]; then
    echo "BLOCK: formal RC identity fence removal failed: $rc_identity_fence" >&2
    exit 1
  fi
  RC_IDENTITY_TRANSACTION_ACTIVE=0
  if [ "$correction_scope" = report ]; then
    rc_task_message="現task YAMLとRC指摘を正本として再読し、RCで指摘された報告項目だけを是正せよ。再計算・再実装の要否はレビュー指示に従え。"
  else
    rc_task_message="現task YAMLを正本として再読し、RCで否認された実装範囲と依存する検証だけを是正せよ。独立な既存成果は再利用し、全作業をやり直すな。"
  fi
  bash "$ROOT/scripts/inbox_write.sh" "$worker_id" \
    "$rc_task_message — タスクYAML: $task_file を読んで作業開始せよ" \
    task_assigned karo task_start || {
      echo "BLOCK: RC task reopened but task_start notification persistence failed: worker=$worker_id" >&2
      exit 1
    }
  echo "review approval recorded: $cmd_id $role $result fingerprint=$fingerprint"
  exit 0
fi

# Upgrade a legacy implementation-bound RC only after Gunshi explicitly
# attests report-only scope and the approval has been durably written.
if [ "$role:$result" = gunshi:LGTM ] && [ "$requested_scope" = report ]; then
  scope_tmp=$(mktemp "$dir/.last_rc_scope.XXXXXX")
  printf 'report\n' > "$scope_tmp"
  mv -f "$scope_tmp" "$rc_scope_file"
  rm -f "$rejected_commit_file"
fi

# A formal report LGTM is operationally relevant to Karo, who owns the
# ACCEPT/GATE transition. Persist it at the approval boundary instead of relying
# on a second manual send. bulletin_write.sh is fail-closed for inbox persistence;
# A regenerated report can change its fingerprint without representing a new
# review lifecycle.  Keep a durable marker per report path and make the
# bulletin body fingerprint-independent, so retries remain exactly-once.
if [ "$role" = gunshi ] && [ "$result" = LGTM ] \
  && [ "${REVIEW_APPROVAL_CANONICAL_ENTRY:-}" != review_bundle ] \
  && [ "${REVIEW_APPROVAL_NO_NOTIFY:-0}" != 1 ]; then
  notice_marker="$dir/gunshi_notice.sent"
  notice_stale=0
  if [ -f "$notice_marker" ]; then
    prev_fp=$(head -n 1 "$notice_marker" 2>/dev/null || true)
    [ "$prev_fp" != "$fingerprint" ] && notice_stale=1
  fi
  if [ ! -f "$notice_marker" ] || [ "$notice_stale" = 1 ]; then
    review_notice="$cmd_id 完了レビュー LGTM — report=$report_rel。家老ACCEPT/GATE判定待ち。"
    # BULLETIN_AUTOGEN=1: 本文はスクリプトが自動生成する定型文であり人が3点セットを
    # 書き込めない。指揮官発信本文検査を免除しないと構造的に必ずBLOCKする(家老D0止血 2026-07-27)。
    BULLETIN_AUTOGEN=1 BULLETIN_NOTIFY=karo bash "$ROOT/scripts/bulletin_write.sh" gunshi "$review_notice" false info || {
      echo "BLOCK: LGTM recorded but Karo notification persistence failed: cmd=$cmd_id report=$report_rel" >&2
      exit 1
    }
    # D0 bugfix: bulletin_notify型はwatcherが自動既読化し家老に起床nudgeが届かない(殿裁定2026-08-04)。
    # report_review_result型のinbox_writeを追加し、家老を確実に起床させる。
    bash "$ROOT/scripts/inbox_write.sh" karo "$review_notice" report_review_result gunshi notify_karo 2>/dev/null || true
    notice_tmp=$(mktemp "$dir/.gunshi_notice.XXXXXX")
    printf '%s\n' "$fingerprint" > "$notice_tmp"
    mv -f "$notice_tmp" "$notice_marker"
  else
    echo "gunshi LGTM notice: SKIP (already notified for report lifecycle)"
  fi
fi
echo "review approval recorded: $cmd_id $role $result fingerprint=$fingerprint"

mapfile -t reports < <(PROJECT_ROOT="$ROOT" review_resolve_reports "$cmd_id")
mapfile -t reports < <(PROJECT_ROOT="$ROOT" review_resolve_gate_reports "$cmd_id" "${reports[@]}")
if [ -n "${REVIEW_APPROVAL_TEST_READY_FILE:-}" ]; then
  : > "$REVIEW_APPROVAL_TEST_READY_FILE"
  while [ ! -e "${REVIEW_APPROVAL_TEST_RELEASE_FILE:?}" ]; do sleep 0.01; done
fi
if [ "$fail_close" = 1 ]; then
  # B28: FAIL close は「家老が正式にFAILとして終端させた」証跡だけを残す。
  # review_gate.done(=CLEAR marker)を書かず GATE も起動しないため、品質記録には
  # FAILのまま残る(instructions/karo.md §verdict=FAIL のcmdを閉じる・L1318)。
  echo "fail-close review recorded (no CLEAR marker, no gate trigger): $cmd_id"
  # 正式closeを書いた同じ行動でworkerの会話状態も白紙化する。monitorの次巡回を
  # 待つと、failed taskが数分間prompt待ちのまま残る。agent_respawn.sh側はfailedを
  # 保持するため、白紙化直後にauto-deployへ再選択されない。
  live_root=$(cd "$(dirname "$0")/.." && pwd)
  if [ "$ROOT" = "$live_root" ]; then
    report_base=$(basename "$report_logical")
    fail_close_agent=${report_base%%_report_*}
    fail_close_task="$ROOT/queue/tasks/${fail_close_agent}.yaml"
    fail_close_status=$(grep -m1 -E '^\s*status:\s*' "$fail_close_task" 2>/dev/null \
      | sed 's/.*status:[[:space:]]*//' | tr -d "\"'[:space:]" || true)
    if [ "$fail_close_status" = "failed" ]; then
      if bash "$ROOT/scripts/agent_respawn.sh" "$fail_close_agent" formal_fail_close; then
        echo "fail-close auto-clear completed: agent=$fail_close_agent"
      else
        echo "WARN: fail-close auto-clear failed; ninja_monitor will retry: agent=$fail_close_agent" >&2
      fi
    fi
  fi
elif review_all_reports_ready "$cmd_id" "${reports[@]}"; then
  if [[ "$cmd_id" =~ ^cmd_[0-9]+$ ]] && ! python3 "$ROOT/scripts/lib/parent_cmd_contract.py" "$cmd_id" --root "$ROOT"; then
    echo "BLOCK: parent cmd SSOT/purpose/AC contract incomplete; formalization withheld" >&2
    exit 1
  fi
  manifest=$(PROJECT_ROOT="$ROOT" review_manifest_fingerprint "${reports[@]}")
  terminal_manifest_sha=$(PROJECT_ROOT="$ROOT" review_terminal_snapshot_write "$cmd_id" "${reports[@]}") || {
    echo "BLOCK: terminal review manifest publication failed" >&2
    exit 1
  }
  marker="$ROOT/queue/gates/$cmd_id/review_gate.done"
  marker_tmp=$(mktemp "$ROOT/queue/gates/$cmd_id/.review_gate.XXXXXX")
  printf 'timestamp: %s\nsource: two_phase_review\nresult: LGTM\nreports: %s\nmanifest: %s\nterminal_manifest: queue/gates/%s/terminal_review_manifest.json\nterminal_manifest_sha: %s\n' \
    "$(date -Iseconds)" "${#reports[@]}" "$manifest" "$cmd_id" "$terminal_manifest_sha" > "$marker_tmp"
  mv -f "$marker_tmp" "$marker"
  # Claim the manifest while the detached worker is running, but publish the
  # gate_triggered marker only after cmd_complete_gate has returned a terminal
  # result.  exit 75 means that the decision is still unknown (normally a
  # transient CMD_ID lock collision) and must not suppress the next attempt.
  if [ ! -e "$base/.gate_triggered.$manifest" ] \
    && (set -o noclobber; : > "$base/.gate_triggering.$manifest") 2>/dev/null; then
    if [ "${REVIEW_APPROVAL_NO_TRIGGER:-0}" != 1 ]; then
      trigger_log="$ROOT/queue/gates/$cmd_id/cmd_complete_gate.trigger.log"
      : > "$trigger_log" 2>/dev/null || true
      # setsidで呼び出し元(caller shell)とは別のセッション/プロセスグループに切り離す。
      # nohup単体はSIGHUPしか無視せず、呼び出し元プロセスグループへのkill(短命CLI/tool
      # 呼出し終了後にharnessが行うグループ単位のクリーンアップ等)には巻き込まれて死ぬ。
      # fd 200 owns the synchronous approval transaction only.  A background
      # completion gate inheriting it keeps the report lock after this process
      # exits (including throughout slow Git history scans), making the other
      # approver time out despite all approval writes already being durable.
      setsid nohup bash -c '
        set -u
        root=$1
        cmd_id=$2
        base=$3
        manifest=$4
        trigger_log=$5
        triggering="$base/.gate_triggering.$manifest"
        triggered="$base/.gate_triggered.$manifest"
        attempt=1
        delay=2
        terminal_rc=75
        while [ "$attempt" -le 10 ]; do
          attempt_started=$(date -Iseconds)
          rc=0
          bash "$root/scripts/cmd_complete_gate.sh" "$cmd_id" >>"$trigger_log" 2>&1 || rc=$?
          printf "attempt=%s rc=%s timestamp=%s\\n" "$attempt" "$rc" "$attempt_started" >>"$trigger_log"
          if [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; then
            marker_tmp="$base/.gate_triggered.$manifest.tmp.$$"
            printf "timestamp: %s\\n" "$(date -Iseconds)" >"$marker_tmp"
            printf "result: %s\\n" "$rc" >>"$marker_tmp"
            printf "attempts: %s\\n" "$attempt" >>"$marker_tmp"
            printf "manifest: %s\\n" "$manifest" >>"$marker_tmp"
            mv -f "$marker_tmp" "$triggered"
            terminal_rc=$rc
            break
          fi
          if [ "$rc" -ne 75 ] || [ "$attempt" -eq 10 ]; then
            terminal_rc=$rc
            break
          fi
          sleep "$delay"
          if [ "$delay" -lt 60 ]; then
            delay=$((delay * 2))
            [ "$delay" -le 60 ] || delay=60
          fi
          attempt=$((attempt + 1))
        done
        rm -f "$triggering"
        exit "$terminal_rc"
      ' _ "$ROOT" "$cmd_id" "$base" "$manifest" "$trigger_log" >>"$trigger_log" 2>&1 </dev/null 200>&- &
      trigger_pid=$!
      # 起動直後の即死(exec失敗/構文エラー・未捕捉例外等)だけを検知する短時間ポーリング。
      # フルGATE実行の完了は待たない(非同期起動の意図を維持)。
      # kill -0 はreap前のzombieにも成功してしまうため使わず、/proc/<pid>/statの
      # 状態文字(Z=zombie以外なら稼働中)で実行中かどうかを判定する。
      # 単なる生存確認だけでは不十分: setsidでの新セッション分離前に呼び出し元
      # (CLI/tool呼出しの短命shell)が終了すると、そのプロセスグループごと
      # 刈り取られてtrigger_pidも巻き添えで消える(cmd_karo_hotfix_review_trigger_durable_cli_202607111336実測)。
      # pgrp(/proc/<pid>/statの第5field)が自身のpidと一致していることまで確認し、
      # 呼び出し元のプロセスグループから分離済み(durable dispatch受付)であることを検証する。
      trigger_proc_dispatched() {
        local stat_file="/proc/$1/stat" state pgrp
        [ -r "$stat_file" ] || return 1
        read -r state pgrp < <(awk '{print $3, $5}' "$stat_file" 2>/dev/null)
        [ -n "$state" ] && [ "$state" != "Z" ] && [ -n "$pgrp" ] && [ "$pgrp" = "$1" ]
      }
      trigger_alive=0
      for _ in 1 2 3 4 5; do
        sleep 0.03
        if trigger_proc_dispatched "$trigger_pid"; then
          trigger_alive=1
          break
        fi
      done
      if [ "$trigger_alive" = 1 ]; then
        echo "review gate formalized and cmd_complete_gate triggered: $cmd_id (pid=$trigger_pid log=${trigger_log#"$ROOT"/})"
      else
        trigger_rc=0
        wait "$trigger_pid" 2>/dev/null || trigger_rc=$?
        if [ "$trigger_rc" -eq 0 ]; then
          echo "review gate formalized and cmd_complete_gate triggered: $cmd_id (pid=$trigger_pid rc=0 completed immediately, log=${trigger_log#"$ROOT"/})"
        else
          echo "review gate formalized but cmd_complete_gate exited immediately (rc=$trigger_rc); see ${trigger_log#"$ROOT"/}" >&2
          echo "review gate formalized; cmd_complete_gate trigger FAILED (rc=$trigger_rc): $cmd_id"
        fi
      fi
    else
      rm -f "$base/.gate_triggering.$manifest"
      echo "review gate formalized and cmd_complete_gate triggered: $cmd_id"
    fi
  fi
fi
