#!/bin/bash
# clear_prep_check.sh — /shogun-clear-prep 用の軽量事前確認
# Usage: bash scripts/clear_prep_check.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PD_FILE="$ROOT_DIR/queue/pending_decisions.yaml"
CMD_FILE="$ROOT_DIR/queue/shogun_to_karo.yaml"
DASHBOARD_FILE="$ROOT_DIR/dashboard.md"
SNAPSHOT_FILE="$ROOT_DIR/queue/karo_snapshot.txt"

pd_count=0
pd_ids="なし"
if [ -f "$PD_FILE" ]; then
  pd_result="$(awk '
    /^[[:space:]]*id:[[:space:]]*/ {
      id=$2
      gsub(/"/, "", id)
      gsub(/\047/, "", id)
    }
    /^[[:space:]]*status:[[:space:]]*/ {
      status=$2
      gsub(/"/, "", status)
      gsub(/\047/, "", status)
      if (id != "" && status != "resolved" && status != "deferred") {
        ids[++count] = id
      }
      id = ""
    }
    END {
      if (count == 0) {
        printf "0|なし"
      } else {
        printf "%d|", count
        for (i = 1; i <= count; i++) {
          printf "%s", ids[i]
          if (i < count) {
            printf ", "
          }
        }
      }
    }
  ' "$PD_FILE")"
  pd_count="${pd_result%%|*}"
  pd_ids="${pd_result#*|}"
fi

cmd_count=0
cmd_ids="なし"
if [ -f "$CMD_FILE" ]; then
  cmd_result="$(awk '
    /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/ {
      id=$3
      gsub(/"/, "", id)
      gsub(/\047/, "", id)
    }
    /^[[:space:]]*status:[[:space:]]*/ {
      status=$2
      gsub(/"/, "", status)
      gsub(/\047/, "", status)
      if (id != "" && status == "pending") {
        ids[++count] = id
      }
      id = ""
    }
    END {
      if (count == 0) {
        printf "0|なし"
      } else {
        printf "%d|", count
        for (i = 1; i <= count; i++) {
          printf "%s", ids[i]
          if (i < count) {
            printf ", "
          }
        }
      }
    }
  ' "$CMD_FILE")"
  cmd_count="${cmd_result%%|*}"
  cmd_ids="${cmd_result#*|}"
fi

alert_count=0
alert_lines=()
if [ -f "$DASHBOARD_FILE" ]; then
  mapfile -t alert_lines < <(awk '
    /^## .*🚨 要対応/ { in_section=1; next }
    in_section && /^## / { in_section=0 }
    in_section && /^[[:space:]]*[0-9]+\./ {
      line=$0
      sub(/^[[:space:]]*[0-9]+\.[[:space:]]*/, "", line)
      print line
    }
  ' "$DASHBOARD_FILE")
  alert_count="${#alert_lines[@]}"
fi

ninja_active=0
ninja_idle=0
ninja_blocked=0
if [ -f "$SNAPSHOT_FILE" ]; then
  ninja_result="$(awk -F'|' '
    /^ninja\|/ {
      status=$4
      if (status == "assigned" || status == "acknowledged" || status == "in_progress") {
        active++
      } else if (status == "blocked") {
        blocked++
      }
    }
    /^idle\|/ {
      split($2, names, ",")
      for (i in names) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", names[i])
        if (names[i] != "" && names[i] != "none") {
          idle++
        }
      }
    }
    END {
      printf "%d|%d|%d", active+0, idle+0, blocked+0
    }
  ' "$SNAPSHOT_FILE")"
  ninja_active="${ninja_result%%|*}"
  rest="${ninja_result#*|}"
  ninja_idle="${rest%%|*}"
  ninja_blocked="${rest#*|}"
fi

echo "=== clear_prep_check $(date '+%Y-%m-%dT%H:%M:%S%z') ==="
echo "[PD未決] ${pd_count}件: ${pd_ids}"
echo "[cmd pending] ${cmd_count}件: ${cmd_ids}"
echo "[🚨要対応] ${alert_count}件"
if [ "$alert_count" -gt 0 ]; then
  for line in "${alert_lines[@]}"; do
    echo "  - ${line}"
  done
else
  echo "  - なし"
fi
echo "[忍者] 稼働${ninja_active} / idle${ninja_idle} / blocked${ninja_blocked}"

# ALERT/OK判定
issues=0
issue_reasons=()
if [ "$pd_count" -gt 0 ]; then
  issues=$((issues + pd_count))
  issue_reasons+=("PD未決${pd_count}")
fi
if [ "$cmd_count" -gt 0 ]; then
  issues=$((issues + cmd_count))
  issue_reasons+=("cmd_pending${cmd_count}")
fi
if [ "$alert_count" -gt 0 ]; then
  issues=$((issues + alert_count))
  issue_reasons+=("要対応${alert_count}")
fi
if [ "$ninja_blocked" -gt 0 ]; then
  issues=$((issues + ninja_blocked))
  issue_reasons+=("blocked${ninja_blocked}")
fi

if [ "$issues" -gt 0 ]; then
  reason_str=$(IFS=','; echo "${issue_reasons[*]}")
  echo "[STATUS] ALERT (${reason_str})"
else
  echo "[STATUS] OK"
fi
echo "========================"

exit "$( [ "$issues" -gt 0 ] && echo 1 || echo 0 )"
