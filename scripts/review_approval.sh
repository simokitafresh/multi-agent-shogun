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
  mapfile -t current_reports < <(find "$ROOT/queue/reports" -maxdepth 1 -type f -name "*_report_${cmd_id}.yaml" -print | LC_ALL=C sort)
  current_manifest=$(PROJECT_ROOT="$ROOT" review_manifest_fingerprint "${current_reports[@]}" 2>/dev/null || true)
  rm -f "$dir/gunshi.yaml" "$ROOT/queue/gates/$cmd_id/review_gate.done"
  [ -z "$current_manifest" ] || rm -f "$base/.gate_triggered.$current_manifest"
  echo "review approval recorded: $cmd_id $role $result fingerprint=$fingerprint"
  exit 0
fi
echo "review approval recorded: $cmd_id $role $result fingerprint=$fingerprint"

mapfile -t reports < <(find "$ROOT/queue/reports" -maxdepth 1 -type f -name "*_report_${cmd_id}.yaml" -print | LC_ALL=C sort)
if [ -n "${REVIEW_APPROVAL_TEST_READY_FILE:-}" ]; then
  : > "$REVIEW_APPROVAL_TEST_READY_FILE"
  while [ ! -e "${REVIEW_APPROVAL_TEST_RELEASE_FILE:?}" ]; do sleep 0.01; done
fi
if review_all_reports_ready "$cmd_id" "${reports[@]}"; then
  manifest=$(PROJECT_ROOT="$ROOT" review_manifest_fingerprint "${reports[@]}")
  marker="$ROOT/queue/gates/$cmd_id/review_gate.done"
  marker_tmp=$(mktemp "$ROOT/queue/gates/$cmd_id/.review_gate.XXXXXX")
  printf 'timestamp: %s\nsource: two_phase_review\nresult: LGTM\nreports: %s\nmanifest: %s\n' "$(date -Iseconds)" "${#reports[@]}" "$manifest" > "$marker_tmp"
  mv -f "$marker_tmp" "$marker"
  if (set -o noclobber; : > "$base/.gate_triggered.$manifest") 2>/dev/null; then
    if [ "${REVIEW_APPROVAL_NO_TRIGGER:-0}" != 1 ]; then
      trigger_log="$ROOT/queue/gates/$cmd_id/cmd_complete_gate.trigger.log"
      : > "$trigger_log" 2>/dev/null || true
      nohup bash "$ROOT/scripts/cmd_complete_gate.sh" "$cmd_id" >>"$trigger_log" 2>&1 &
      trigger_pid=$!
      # 起動直後の即死(exec失敗/構文エラー・未捕捉例外等)だけを検知する短時間ポーリング。
      # フルGATE実行の完了は待たない(非同期起動の意図を維持)。
      # kill -0 はreap前のzombieにも成功してしまうため使わず、/proc/<pid>/statの
      # 状態文字(Z=zombie以外なら稼働中)で実行中かどうかを判定する。
      trigger_proc_running() {
        local stat_file="/proc/$1/stat" state
        [ -r "$stat_file" ] || return 1
        state=$(awk '{print $3}' "$stat_file" 2>/dev/null)
        [ -n "$state" ] && [ "$state" != "Z" ]
      }
      trigger_alive=0
      for _ in 1 2 3 4 5; do
        sleep 0.03
        if trigger_proc_running "$trigger_pid"; then
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
