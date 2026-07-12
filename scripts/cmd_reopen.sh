#!/usr/bin/env bash
# Reopen an archived/false-CLEAR cmd without deleting evidence.
set -euo pipefail
ROOT=${CMD_REOPEN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
DRY_RUN=0
[ "${1:-}" = --dry-run ] && { DRY_RUN=1; shift; }
[ "$#" -eq 1 ] || { echo "Usage: $0 [--dry-run] cmd_id" >&2; exit 2; }
cmd_id=$1
[[ "$cmd_id" =~ ^cmd_[0-9]+$ ]] || { echo "BLOCK: numbered cmd_id required" >&2; exit 2; }
mapfile -t archives < <(find "$ROOT/queue/archive/cmds" -maxdepth 1 -type f -name "${cmd_id}_*.yaml" -print | sort)
[ "${#archives[@]}" -gt 0 ] || { echo "BLOCK: archived parent SSOT missing" >&2; exit 1; }
mapfile -t tasks < <(grep -l "parent_cmd: ${cmd_id}" "$ROOT"/queue/tasks/*.yaml 2>/dev/null | sort || true)
[ "${#tasks[@]}" -gt 0 ] || { echo "BLOCK: matching task missing" >&2; exit 1; }
echo "reopen plan: cmd=$cmd_id archives=${#archives[@]} tasks=${#tasks[@]} dry_run=$DRY_RUN"
[ "$DRY_RUN" -eq 1 ] && exit 0
stamp=$(date +%Y%m%dT%H%M%S)
state="$ROOT/queue/reopen/$cmd_id/$stamp"; mkdir -p "$state"
cp -a "${archives[0]}" "$state/parent.before.yaml"
cp -a "$ROOT/queue/gates/$cmd_id" "$state/gates.before" 2>/dev/null || true
# Restore an active SSOT without rewriting the shared multi-command queue.
mkdir -p "$ROOT/queue/reopened_cmds"
cp -a "${archives[0]}" "$ROOT/queue/reopened_cmds/$cmd_id.yaml.tmp"
mv -f "$ROOT/queue/reopened_cmds/$cmd_id.yaml.tmp" "$ROOT/queue/reopened_cmds/$cmd_id.yaml"
bash "$ROOT/scripts/lib/yaml_field_set.sh" "$ROOT/queue/reopened_cmds/$cmd_id.yaml" "$cmd_id" status in_progress
for task in "${tasks[@]}"; do
  worker=$(basename "$task" .yaml)
  bash "$ROOT/scripts/lib/yaml_field_set.sh" "$task" task status assigned
  bash "$ROOT/scripts/lib/yaml_field_set.sh" "$task" task completed_at ""
  bash "$ROOT/scripts/lib/yaml_field_set.sh" "$task" task done_at ""
  report=$(find "$ROOT/queue/reports" "$ROOT/queue/archive/reports" -maxdepth 1 -type f -name "${worker}_report_${cmd_id}.yaml" -print | head -1)
  [ -z "$report" ] || bash "$ROOT/scripts/report_field_set.sh" "$report" status revision_requested
done
mkdir -p "$ROOT/queue/gates/$cmd_id"
for marker in archive.done lesson.done review_gate.done completion_notified.done; do
  [ ! -e "$ROOT/queue/gates/$cmd_id/$marker" ] || mv "$ROOT/queue/gates/$cmd_id/$marker" "$state/$marker.invalidated"
done
[ ! -d "$ROOT/queue/gates/$cmd_id/review_approvals" ] || mv "$ROOT/queue/gates/$cmd_id/review_approvals" "$state/review_approvals.invalidated"
find "$ROOT/queue/gates/$cmd_id" -maxdepth 1 -name '.gate_triggered.*' -exec mv {} "$state/" \;
printf '%s\t%s\tREOPEN\tparent_contract_invalidated\n' "$(date -Iseconds)" "$cmd_id" >> "$ROOT/logs/gate_metrics.log"
printf 'timestamp: %s\ncmd_id: %s\nreason: parent_contract_invalidated\n' "$(date -Iseconds)" "$cmd_id" > "$state/manifest.yaml"
echo "reopened: state=$state"
