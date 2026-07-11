#!/usr/bin/env bash
# Usage: review_approval.sh <cmd_id> <gunshi|karo> <LGTM|ACCEPT|RC> <report_path>
set -euo pipefail
ROOT=${REVIEW_APPROVAL_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
source "$ROOT/scripts/lib/review_approval.sh"
[ "$#" -eq 4 ] || { echo "Usage: $0 <cmd_id> <gunshi|karo> <LGTM|ACCEPT|RC> <report_path>" >&2; exit 2; }
cmd_id=$1; role=$2; result=$3; report=$4
case "$role:$result" in gunshi:LGTM|karo:ACCEPT|karo:RC) ;; *) echo "BLOCK: invalid role/result" >&2; exit 2;; esac
[[ "$report" = /* ]] || report="$ROOT/$report"
fingerprint=$(review_report_fingerprint "$report") || { echo "BLOCK: report missing or commit_hash absent: $report" >&2; exit 1; }
report_rel=${report#"$ROOT"/}; report_key=$(review_report_key "$report_rel")
base="$ROOT/queue/gates/$cmd_id/review_approvals"
dir="$base/reports/$report_key"; mkdir -p "$dir"
lock="$dir/.lock"; exec 200>"$lock"; flock -w 5 200
tmp=$(mktemp "$dir/.${role}.XXXXXX")
trap 'rm -f "$tmp"' EXIT
printf 'timestamp: %s\nrole: %s\nresult: %s\nfingerprint: %s\nreport: %s\n' "$(date -Iseconds)" "$role" "$result" "$fingerprint" "$report_rel" > "$tmp"
mv -f "$tmp" "$dir/$role.yaml"
if [ "$role" = karo ] && [ "$result" = RC ]; then
  rm -f "$dir/gunshi.yaml" "$base/.gate_triggered" "$ROOT/queue/gates/$cmd_id/review_gate.done"
  echo "review approval recorded: $cmd_id $role $result fingerprint=$fingerprint"
  exit 0
fi
echo "review approval recorded: $cmd_id $role $result fingerprint=$fingerprint"

mapfile -t reports < <(find "$ROOT/queue/reports" -maxdepth 1 -type f -name "*_report_${cmd_id}.yaml" -print | LC_ALL=C sort)
if review_all_reports_ready "$cmd_id" "${reports[@]}"; then
  marker="$ROOT/queue/gates/$cmd_id/review_gate.done"
  marker_tmp=$(mktemp "$ROOT/queue/gates/$cmd_id/.review_gate.XXXXXX")
  printf 'timestamp: %s\nsource: two_phase_review\nresult: LGTM\nreports: %s\n' "$(date -Iseconds)" "${#reports[@]}" > "$marker_tmp"
  mv -f "$marker_tmp" "$marker"
  if (set -o noclobber; : > "$base/.gate_triggered") 2>/dev/null; then
    if [ "${REVIEW_APPROVAL_NO_TRIGGER:-0}" != 1 ]; then
      nohup bash "$ROOT/scripts/cmd_complete_gate.sh" "$cmd_id" >/dev/null 2>&1 &
    fi
    echo "review gate formalized and cmd_complete_gate triggered: $cmd_id"
  fi
fi
