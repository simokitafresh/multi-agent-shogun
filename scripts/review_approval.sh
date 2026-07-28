#!/usr/bin/env bash
# Usage: review_approval.sh <cmd_id> <gunshi|karo> <LGTM|ACCEPT|RC> <report_path> [auto|implementation|report]
#    or: review_approval.sh <cmd_id> karo RC_REVOKE <report_path> <reason>
set -euo pipefail
ROOT=${REVIEW_APPROVAL_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
source "$ROOT/scripts/lib/review_approval.sh"
source "$ROOT/scripts/lib/yaml_field_set.sh"
defense_writer="$ROOT/scripts/lib/defense_overhead_writer.sh"
[ -f "$defense_writer" ] || defense_writer="$(cd "$(dirname "$0")" && pwd)/lib/defense_overhead_writer.sh"
DEFENSE_OVERHEAD_REPO_ROOT="${DEFENSE_OVERHEAD_REPO_ROOT:-$ROOT}"
source "$defense_writer"
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
failed_rc=0
if [ "$report_status" = "failed" ] && [ "$role:$result" = "karo:RC" ] && [ "$report_verdict" = "FAIL" ]; then
  failed_rc=1
fi
[ "$report_status" = "completed" ] || [ "$fail_close" = 1 ] || [ "$failed_rc" = 1 ] || [ "$role:$result" = "karo:RC_REVOKE" ] || {
  echo "BLOCK: formal review requires status=completed (actual=${report_status:-missing}): $report" >&2
  exit 1
}
base="$ROOT/queue/gates/$cmd_id/review_approvals"
mkdir -p "$base"
exec 200>"$base/.lock"; flock -w 10 200
fingerprint=$(REVIEW_FAIL_CLOSE_IDENTITY_EXEMPT="$fail_close" review_report_fingerprint "$report") || { echo "BLOCK: report missing or commit_hash absent: $report" >&2; exit 1; }
report_rel=${report#"$ROOT"/}; report_key=$(review_report_key "$report_rel")
dir="$base/reports/$report_key"; mkdir -p "$dir"
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
current_commit=$(REVIEW_FAIL_CLOSE_IDENTITY_EXEMPT="$fail_close" review_report_commit_identity "$report" 2>/dev/null || true)
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

  pre_report_status=$(cat "$snapshot_dir/report_status" 2>/dev/null || true)
  [ -n "$pre_report_status" ] || { echo "BLOCK: RC snapshot missing report_status: $snapshot_dir" >&2; exit 1; }
  bash "$ROOT/scripts/report_field_set.sh" "$report" status "$pre_report_status"

  # cmd_karo_hotfix_rc_task_status_reset_20260727: one atomic batch write
  # instead of N separate yaml_field_set.sh invocations (N separate
  # flock-acquire/release cycles). Between two individual calls the lock is
  # released, leaving a window where an independent writer (e.g. ninja_monitor
  # AUTO-DONE) can interleave and observe/leave a half-restored task state.
  restore_pairs=()
  while IFS='=' read -r field value; do
    [ -n "$field" ] || continue
    restore_pairs+=("${field}=${value}")
  done < "$snapshot_dir/task_fields"
  [ "${#restore_pairs[@]}" -eq 0 ] || yaml_field_set_batch "$task_file" task "${restore_pairs[@]}"

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

if [ ! "$role:$result" = "karo:RC" ] && [ "$correction_scope" = implementation ] \
  && [ -f "$rejected_commit_file" ] && [ "$current_commit" != "no-code-change" ]; then
  rejected_commit=$(head -n 1 "$rejected_commit_file" 2>/dev/null || true)
  if [ -n "$rejected_commit" ] && [ "$rejected_commit" = "$current_commit" ]; then
    echo "BLOCK: implementation commit unchanged since Karo RC: $current_commit" >&2
    exit 1
  fi
fi
if [ ! "$role:$result" = "karo:RC" ] && [ "$correction_scope" = report ]; then
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
if [ "$role" = gunshi ] && [ "$result" = LGTM ] && [ -f "$ROOT/scripts/review_bundle.py" ]; then
  python3 "$ROOT/scripts/review_bundle.py" generate \
    --cmd "$cmd_id" --verdict APPROVE --report "$report_rel" >/dev/null || {
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
    echo "  先に軍師のレビュー記録を台帳へ追記せよ: bash scripts/gunshi_log_append.sh < <entry.yaml>" >&2
    echo "  (sg7 bundle は本実行で生成済みのため lgtm_bundle_guard は通る。追記後に本コマンドを再実行せよ)" >&2
    echo "  台帳: ${ledger_file#"$ROOT"/}" >&2
    exit 2
  fi
fi
tmp=$(mktemp "$dir/.${role}.XXXXXX")
trap 'rm -f "$tmp" "${REVIEW_FP_CACHE_DIR:?}"/*; rmdir "${REVIEW_FP_CACHE_DIR:?}" 2>/dev/null || true' EXIT
printf 'timestamp: %s\nrole: %s\nresult: %s\nfingerprint: %s\nreport: %s\ncorrection_scope: %s\n' "$(date -Iseconds)" "$role" "$result" "$fingerprint" "$report_rel" "$correction_scope" > "$tmp"
mv -f "$tmp" "$dir/$role.yaml"
# T1a throughput instrumentation: the approval file above is the existing
# durable decision boundary.  Reuse the shared append-only timing ledger and
# bind the id to the report attempt (fingerprint) plus report identity (key).
# Duplicate invocations intentionally keep the original boundary timestamp.
case "$role:$result" in
  gunshi:LGTM)
    defense_overhead_write review_approval gunshi_lgtm 0 PASS \
      "review-approval-gunshi-lgtm-${cmd_id}-${report_key}-${fingerprint}" || true
    ;;
  karo:ACCEPT)
    defense_overhead_write review_approval karo_accept 0 PASS \
      "review-approval-karo-accept-${cmd_id}-${report_key}-${fingerprint}" || true
    ;;
esac
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
  # cmd_karo_impl_rc_revoke_command_20260727: snapshot pre-RC state under the
  # same deploy lock so a mistaken RC can be revoked later (incident
  # 2026-07-27 12:47: a correct report was RC'd by mistake with no formal
  # undo path; karo had to hand-retreat the ledger). Captured before any of
  # this block's mutations below.
  snapshot_dir="$dir/.pre_rc_snapshot.$(date +%Y%m%d%H%M%S)_$$"
  mkdir -p "$snapshot_dir"
  printf '%s\n' "$report_status" > "$snapshot_dir/report_status"
  : > "$snapshot_dir/task_fields"
  for field in deployed_at retry_deployed_at status reviewed review_result acknowledged_at completed_at done_at; do
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
  [ -f "$dir/gunshi.yaml" ] && cp -f "$dir/gunshi.yaml" "$snapshot_dir/gunshi.yaml"
  [ -f "$dir/gunshi_notice.sent" ] && cp -f "$dir/gunshi_notice.sent" "$snapshot_dir/gunshi_notice.sent"
  [ -f "$ROOT/queue/gates/$cmd_id/review_gate.done" ] && cp -f "$ROOT/queue/gates/$cmd_id/review_gate.done" "$snapshot_dir/review_gate.done"
  [ -f "$ROOT/queue/gates/$cmd_id/gunshi_report_review_notify_${worker_id}.done" ] && cp -f "$ROOT/queue/gates/$cmd_id/gunshi_report_review_notify_${worker_id}.done" "$snapshot_dir/gunshi_notify.done"
  [ -f "$rc_scope_file" ] && cp -f "$rc_scope_file" "$snapshot_dir/last_rc_scope"
  [ -f "$rejected_commit_file" ] && cp -f "$rejected_commit_file" "$snapshot_dir/last_rc_commit"
  [ -f "$rejected_payload_file" ] && cp -f "$rejected_payload_file" "$snapshot_dir/last_rc_report_payload"
  [ -f "$base/karo_rework.seen" ] && cp -f "$base/karo_rework.seen" "$snapshot_dir/karo_rework.seen"
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
  mapfile -t current_reports < <(find "$ROOT/queue/reports" -maxdepth 1 -type f -name "*_report_${cmd_id}.yaml" -print | LC_ALL=C sort)
  current_manifest=$(PROJECT_ROOT="$ROOT" review_manifest_fingerprint "${current_reports[@]}" 2>/dev/null || true)
  # RC starts a fresh report-review lifecycle.  Clear both the formal approval
  # markers and inbox_write's completion-notify marker; otherwise a revised
  # report can be resubmitted successfully while Gunshi receives no new review
  # request because the previous completion is still treated as notified.
  rm -f "$dir/gunshi.yaml" \
    "$dir/gunshi_notice.sent" \
    "$ROOT/queue/gates/$cmd_id/review_gate.done" \
    "$ROOT/queue/gates/$cmd_id/gunshi_report_review_notify_${worker_id}.done"
  [ -z "$current_manifest" ] || rm -f "$base/.gate_triggered.$current_manifest"
  # A completed report makes ninja_monitor auto-promote the task back to done.
  # Move the report out of the terminal set before reopening the task so RC
  # cannot race with AUTO-DONE and silently stop the worker again.
  bash "$ROOT/scripts/report_field_set.sh" "$report" status revision_requested
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
  yaml_field_set_batch "$task_file" task \
    "deployed_at=$rc_deployed_at" \
    "retry_deployed_at=$rc_deployed_at" \
    "status=assigned" \
    "review_correction_scope=$correction_scope" \
    "reviewed=false" \
    "review_result=" \
    "acknowledged_at=" \
    "completed_at=" \
    "done_at="
  if [ "$correction_scope" = report ]; then
    rc_task_message="前報告の実測・成果物は有効。現task YAMLを正本として再読し、RCで指摘された報告項目だけを是正せよ。再計算・再実装は禁止。"
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
if [ "$role" = gunshi ] && [ "$result" = LGTM ] && [ "${REVIEW_APPROVAL_NO_NOTIFY:-0}" != 1 ]; then
  notice_marker="$dir/gunshi_notice.sent"
  if [ ! -f "$notice_marker" ]; then
    review_notice="$cmd_id 完了レビュー LGTM — report=$report_rel。家老ACCEPT/GATE判定待ち。"
    # BULLETIN_AUTOGEN=1: 本文はスクリプトが自動生成する定型文であり人が3点セットを
    # 書き込めない。指揮官発信本文検査を免除しないと構造的に必ずBLOCKする(家老D0止血 2026-07-27)。
    BULLETIN_AUTOGEN=1 BULLETIN_NOTIFY=karo bash "$ROOT/scripts/bulletin_write.sh" gunshi "$review_notice" false info || {
      echo "BLOCK: LGTM recorded but Karo notification persistence failed: cmd=$cmd_id report=$report_rel" >&2
      exit 1
    }
    notice_tmp=$(mktemp "$dir/.gunshi_notice.XXXXXX")
    printf '%s\n' "$fingerprint" > "$notice_tmp"
    mv -f "$notice_tmp" "$notice_marker"
  else
    echo "gunshi LGTM notice: SKIP (already notified for report lifecycle)"
  fi
fi
echo "review approval recorded: $cmd_id $role $result fingerprint=$fingerprint"

mapfile -t reports < <(find "$ROOT/queue/reports" -maxdepth 1 -type f -name "*_report_${cmd_id}.yaml" -print | LC_ALL=C sort)
if [ -n "${REVIEW_APPROVAL_TEST_READY_FILE:-}" ]; then
  : > "$REVIEW_APPROVAL_TEST_READY_FILE"
  while [ ! -e "${REVIEW_APPROVAL_TEST_RELEASE_FILE:?}" ]; do sleep 0.01; done
fi
if [ "$fail_close" = 1 ]; then
  # B28: FAIL close は「家老が正式にFAILとして終端させた」証跡だけを残す。
  # review_gate.done(=CLEAR marker)を書かず GATE も起動しないため、品質記録には
  # FAILのまま残る(instructions/karo.md §verdict=FAIL のcmdを閉じる・L1318)。
  echo "fail-close review recorded (no CLEAR marker, no gate trigger): $cmd_id"
elif review_all_reports_ready "$cmd_id" "${reports[@]}"; then
  if [[ "$cmd_id" =~ ^cmd_[0-9]+$ ]] && ! python3 "$ROOT/scripts/lib/parent_cmd_contract.py" "$cmd_id" --root "$ROOT"; then
    echo "BLOCK: parent cmd SSOT/purpose/AC contract incomplete; formalization withheld" >&2
    exit 1
  fi
  manifest=$(PROJECT_ROOT="$ROOT" review_manifest_fingerprint "${reports[@]}")
  marker="$ROOT/queue/gates/$cmd_id/review_gate.done"
  marker_tmp=$(mktemp "$ROOT/queue/gates/$cmd_id/.review_gate.XXXXXX")
  printf 'timestamp: %s\nsource: two_phase_review\nresult: LGTM\nreports: %s\nmanifest: %s\n' "$(date -Iseconds)" "${#reports[@]}" "$manifest" > "$marker_tmp"
  mv -f "$marker_tmp" "$marker"
  if (set -o noclobber; : > "$base/.gate_triggered.$manifest") 2>/dev/null; then
    if [ "${REVIEW_APPROVAL_NO_TRIGGER:-0}" != 1 ]; then
      trigger_log="$ROOT/queue/gates/$cmd_id/cmd_complete_gate.trigger.log"
      : > "$trigger_log" 2>/dev/null || true
      # setsidで呼び出し元(caller shell)とは別のセッション/プロセスグループに切り離す。
      # nohup単体はSIGHUPしか無視せず、呼び出し元プロセスグループへのkill(短命CLI/tool
      # 呼出し終了後にharnessが行うグループ単位のクリーンアップ等)には巻き込まれて死ぬ。
      setsid nohup bash "$ROOT/scripts/cmd_complete_gate.sh" "$cmd_id" >>"$trigger_log" 2>&1 </dev/null &
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
      echo "review gate formalized and cmd_complete_gate triggered: $cmd_id"
    fi
  fi
fi
