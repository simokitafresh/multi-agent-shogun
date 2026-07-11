#!/usr/bin/env bash
# Usage: review_approval.sh <cmd_id> <gunshi|karo> <LGTM|ACCEPT|RC> <report_path>
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/scripts/lib/review_approval.sh"
[ "$#" -eq 4 ] || { echo "Usage: $0 <cmd_id> <gunshi|karo> <LGTM|ACCEPT|RC> <report_path>" >&2; exit 2; }
cmd_id=$1; role=$2; result=$3; report=$4
case "$role:$result" in gunshi:LGTM|karo:ACCEPT|karo:RC) ;; *) echo "BLOCK: invalid role/result" >&2; exit 2;; esac
[[ "$report" = /* ]] || report="$ROOT/$report"
fingerprint=$(review_report_fingerprint "$report") || { echo "BLOCK: report not found: $report" >&2; exit 1; }
dir="$ROOT/queue/gates/$cmd_id/review_approvals"; mkdir -p "$dir"
lock="$dir/.lock"; exec 200>"$lock"; flock -w 5 200
tmp=$(mktemp "$dir/.${role}.XXXXXX")
trap 'rm -f "$tmp"' EXIT
printf 'timestamp: %s\nrole: %s\nresult: %s\nfingerprint: %s\nreport: %s\n' "$(date -Iseconds)" "$role" "$result" "$fingerprint" "${report#"$ROOT"/}" > "$tmp"
mv -f "$tmp" "$dir/$role.yaml"
if [ "$role" = karo ] && [ "$result" = RC ]; then rm -f "$dir/gunshi.yaml"; fi
echo "review approval recorded: $cmd_id $role $result fingerprint=$fingerprint"
