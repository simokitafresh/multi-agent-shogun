#!/usr/bin/env bash
# Usage: review_approval.sh <cmd_id> <gunshi|karo> <LGTM|ACCEPT|RC> <report_path>
set -euo pipefail
ROOT=${REVIEW_APPROVAL_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
source "$ROOT/scripts/lib/review_approval.sh"
[ "$#" -eq 4 ] || { echo "Usage: $0 <cmd_id> <gunshi|karo> <LGTM|ACCEPT|RC> <report_path>" >&2; exit 2; }
cmd_id=$1; role=$2; result=$3; report=$4
case "$role:$result" in gunshi:LGTM|karo:ACCEPT|karo:RC) ;; *) echo "BLOCK: invalid role/result" >&2; exit 2;; esac
[[ "$report" = /* ]] || report="$ROOT/$report"
PROJECT_ROOT="$ROOT" review_validate_report "$cmd_id" "$report" || { echo "BLOCK: invalid cmd/report boundary or parent_cmd mismatch" >&2; exit 2; }
report=$(realpath "$report")
# A formal decision is valid only for a submitted report.  Karo RC moves the
# report to revision_requested before waking the worker; without this guard a
# delayed Gunshi review can bind LGTM to that post-RC document and recreate a
# stale approval after RC invalidation.
report_status=$(python3 - "$report" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
print(str(data.get("status") or "").strip())
PY
) || { echo "BLOCK: report status unreadable: $report" >&2; exit 1; }
[ "$report_status" = "completed" ] || {
  echo "BLOCK: formal review requires status=completed (actual=${report_status:-missing}): $report" >&2
  exit 1
}
base="$ROOT/queue/gates/$cmd_id/review_approvals"
mkdir -p "$base"
exec 200>"$base/.lock"; flock -w 10 200
fingerprint=$(review_report_fingerprint "$report") || { echo "BLOCK: report missing or commit_hash absent: $report" >&2; exit 1; }
report_rel=${report#"$ROOT"/}; report_key=$(review_report_key "$report_rel")
dir="$base/reports/$report_key"; mkdir -p "$dir"
tmp=$(mktemp "$dir/.${role}.XXXXXX")
trap 'rm -f "$tmp"' EXIT
printf 'timestamp: %s\nrole: %s\nresult: %s\nfingerprint: %s\nreport: %s\n' "$(date -Iseconds)" "$role" "$result" "$fingerprint" "$report_rel" > "$tmp"
mv -f "$tmp" "$dir/$role.yaml"
if [ "$role" = karo ] && [ "$result" = RC ]; then
  # Preserve RC as monotonic command history.  The per-report karo.yaml is
  # intentionally overwritten by the later ACCEPT, so it cannot tell the
  # completion-quality logger that rework occurred.
  rework_tmp=$(mktemp "$base/.karo_rework.XXXXXX")
  printf 'timestamp: %s\nsource: formal_karo_rc\n' "$(date -Iseconds)" > "$rework_tmp"
  mv -f "$rework_tmp" "$base/karo_rework.seen"
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
  task_parent=$(python3 - "$task_file" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
print(str((data.get("task") or {}).get("parent_cmd") or ""))
PY
  ) || { echo "BLOCK: RC worker task unreadable: $worker_id" >&2; exit 1; }
  [ "$task_parent" = "$cmd_id" ] || {
    echo "BLOCK: RC worker task parent_cmd mismatch: worker=$worker_id expected=$cmd_id actual=${task_parent:-missing}" >&2
    exit 1
  }

  mapfile -t current_reports < <(find "$ROOT/queue/reports" -maxdepth 1 -type f -name "*_report_${cmd_id}.yaml" -print | LC_ALL=C sort)
  current_manifest=$(PROJECT_ROOT="$ROOT" review_manifest_fingerprint "${current_reports[@]}" 2>/dev/null || true)
  rm -f "$dir/gunshi.yaml" "$dir/gunshi_notice.sent" "$ROOT/queue/gates/$cmd_id/review_gate.done"
  [ -z "$current_manifest" ] || rm -f "$base/.gate_triggered.$current_manifest"
  # A completed report makes ninja_monitor auto-promote the task back to done.
  # Move the report out of the terminal set before reopening the task so RC
  # cannot race with AUTO-DONE and silently stop the worker again.
  bash "$ROOT/scripts/report_field_set.sh" "$report" status revision_requested
  # RC is a real redeployment. Refresh the deployment clock before reopening;
  # otherwise ninja_monitor's Stage-1 timeout measures from the original
  # deployment and can immediately reset the revived task to idle.
  bash "$ROOT/scripts/lib/yaml_field_set.sh" "$task_file" task deployed_at "$(date -Iseconds)"
  bash "$ROOT/scripts/lib/yaml_field_set.sh" "$task_file" task status assigned
  bash "$ROOT/scripts/lib/yaml_field_set.sh" "$task_file" task acknowledged_at ""
  bash "$ROOT/scripts/lib/yaml_field_set.sh" "$task_file" task completed_at ""
  bash "$ROOT/scripts/lib/yaml_field_set.sh" "$task_file" task done_at ""
  bash "$ROOT/scripts/inbox_write.sh" "$worker_id" \
    "前taskの情報は無効。タスクYAMLを最初から読み直して作業開始せよ。 — タスクYAML: $task_file を読んで作業開始せよ" \
    task_assigned karo task_start || {
      echo "BLOCK: RC task reopened but task_start notification persistence failed: worker=$worker_id" >&2
      exit 1
    }
  echo "review approval recorded: $cmd_id $role $result fingerprint=$fingerprint"
  exit 0
fi

# A formal report LGTM is operationally relevant to Shogun even before Karo's
# ACCEPT/GATE result. Persist it at the approval boundary instead of relying on
# a second manual send. bulletin_write.sh is fail-closed for inbox persistence;
# A regenerated report can change its fingerprint without representing a new
# review lifecycle.  Keep a durable marker per report path and make the
# bulletin body fingerprint-independent, so retries remain exactly-once.
if [ "$role" = gunshi ] && [ "$result" = LGTM ] && [ "${REVIEW_APPROVAL_NO_NOTIFY:-0}" != 1 ]; then
  notice_marker="$dir/gunshi_notice.sent"
  if [ ! -f "$notice_marker" ]; then
    review_notice="$cmd_id 完了レビュー LGTM — report=$report_rel。家老ACCEPT/GATE判定待ち。"
    BULLETIN_NOTIFY=shogun bash "$ROOT/scripts/bulletin_write.sh" gunshi "$review_notice" false info || {
      echo "BLOCK: LGTM recorded but Shogun notification persistence failed: cmd=$cmd_id report=$report_rel" >&2
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
if review_all_reports_ready "$cmd_id" "${reports[@]}"; then
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
        state=$(awk '{print $3}' "$stat_file" 2>/dev/null)
        pgrp=$(awk '{print $5}' "$stat_file" 2>/dev/null)
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
