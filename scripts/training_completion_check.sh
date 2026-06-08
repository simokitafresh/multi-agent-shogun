#!/usr/bin/env bash
# semantic-links: [[修行サイクル]] [[Skill設計ルール]]
# training_completion_check.sh — 修行完了判定(FP率計算) + SKILL.md防止ステップ自動更新
#
# Usage:
#   bash scripts/training_completion_check.sh --cmd-id <training_cmd_id> [--skill <name>] [--pass-count <N>]
#
# Called by ninja_monitor.sh when a training task completes (done/completed).
# 1. Extracts training group pattern from cmd_id
# 2. Scans gate_fire_log for matching training report entries
# 3. Calculates first-pass PASS rate per unique report (per L671)
# 4. If pass_count (default 3) or more first-pass PASS → TRAINING_COMPLETE
# 5. Calls skill_auto_improve.sh --apply to update SKILL.md prevention steps

set -euo pipefail

REPO_ROOT="${SHOGUN_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
GATE_FIRE_LOG="${TRAINING_COMPLETION_GATE_LOG:-$REPO_ROOT/logs/gate_fire_log.yaml}"
SKILL_AUTO_IMPROVE="${TRAINING_COMPLETION_IMPROVE_SCRIPT:-$REPO_ROOT/scripts/skill_auto_improve.sh}"
pass_count="${TRAINING_COMPLETION_PASS_COUNT:-3}"

cmd_id=""
skill=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --cmd-id) cmd_id="${2:-}"; shift 2 ;;
        --skill) skill="${2:-}"; shift 2 ;;
        --pass-count) pass_count="${2:-}"; shift 2 ;;
        --gate-log) GATE_FIRE_LOG="${2:-}"; shift 2 ;;
        --improve-script) SKILL_AUTO_IMPROVE="${2:-}"; shift 2 ;;
        --repo-root) REPO_ROOT="${2:-}"; shift 2 ;;
        -h|--help) sed -n '1,15p' "$0" >&2; exit 0 ;;
        *) echo "ERROR: Unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$cmd_id" ]; then
    echo "ERROR: --cmd-id is required" >&2
    exit 2
fi

[[ "$pass_count" =~ ^[0-9]+$ ]] || { echo "ERROR: --pass-count must be integer" >&2; exit 2; }

# --- Extract training group grep pattern from cmd_id ---
# Training cmd patterns vary:
#   cmd_training_L4_auto_202606041638_hayate
#   cmd_training_speed_topic_202606071500_normal
# Strip ninja/mode suffix, then use date prefix (YYYYMMDDHH) for grouping
# to handle minute-level timestamp differences between ninjas.

# Extract YYYYMMDDHH date prefix
date_prefix=""
if [[ "$cmd_id" =~ ([0-9]{10}) ]]; then
    date_prefix="${BASH_REMATCH[1]}"
fi

# Determine training type from cmd_id
training_type=""
if [[ "$cmd_id" =~ training_L([0-9]+) ]]; then
    training_type="training_L${BASH_REMATCH[1]}"
elif [[ "$cmd_id" =~ training_speed ]]; then
    training_type="training_speed"
else
    training_type="training"
fi

# Build grep pattern: match training reports with same type and date prefix
if [ -n "$date_prefix" ]; then
    grep_pattern="_report_cmd_${training_type}.*${date_prefix}"
else
    # Fallback: strip known suffixes to get group base
    group_base="$cmd_id"
    for ninja in hayate kagemaru hanzo saizo kotaro tobisaru sasuke kirimaru; do
        group_base="${group_base%_${ninja}}"
    done
    group_base="${group_base%_normal}"
    grep_pattern="_report_${group_base}"
fi

# --- Auto-detect skill name if not given ---
if [ -z "$skill" ]; then
    # Pattern: training_L{N}_{skill}_{timestamp}
    if [[ "$cmd_id" =~ training_L[0-9]+_([a-z][a-z0-9_-]+)_[0-9] ]]; then
        candidate="${BASH_REMATCH[1]}"
        # Skip "auto" (part of auto-deploy pattern, not skill name)
        [ "$candidate" != "auto" ] && skill="$candidate"
    fi
fi

# --- Scan gate_fire_log ---
if [ ! -f "$GATE_FIRE_LOG" ]; then
    echo "TRAINING_COMPLETION_SKIP: gate_fire_log not found: $GATE_FIRE_LOG"
    exit 0
fi

# Parse gate_fire_log: for each unique report file matching the pattern,
# determine if the FIRST gate_report_format execution was PASS (一発PASS).
# gate_fire_log is chronologically ordered (oldest first).
# Per L671: use unique report YAML as unit, not raw gate line count.
read -r first_pass_count total_reports <<< "$(awk -v pattern="$grep_pattern" '
    $0 ~ pattern && /gate:.*gate_report_format/ {
        # Extract file path
        file = $0
        sub(/^.*file:[[:space:]]*"?/, "", file)
        sub(/"?[,[:space:]].*$/, "", file)
        if (file == "") next

        # Normalize to basename for dedup (paths may be relative or absolute)
        n = split(file, parts, "/")
        basename = parts[n]
        if (basename == "") next

        # Record FIRST result only per report (chronological order)
        if (!(basename in first_result)) {
            first_result[basename] = ($0 ~ /result:[[:space:]]*PASS/) ? "PASS" : "FAIL"
        }
    }
    END {
        total = 0; pass = 0
        for (f in first_result) {
            total++
            if (first_result[f] == "PASS") pass++
        }
        printf "%d %d\n", pass, total
    }
' "$GATE_FIRE_LOG")"

first_pass_count=${first_pass_count:-0}
total_reports=${total_reports:-0}

# Calculate first-pass rate
if [ "$total_reports" -gt 0 ]; then
    fp_rate=$(( (first_pass_count * 100) / total_reports ))
else
    fp_rate=0
fi

echo "TRAINING_COMPLETION_CHECK: cmd_group=${training_type} date=${date_prefix:-unknown} first_pass=${first_pass_count}/${total_reports} fp_rate=${fp_rate}% pass_threshold=${pass_count}"

# --- Completion judgment ---
if [ "$first_pass_count" -lt "$pass_count" ]; then
    echo "TRAINING_INCOMPLETE: ${first_pass_count} < ${pass_count} first-pass PASS required"
    exit 0
fi

echo "TRAINING_COMPLETE: ${first_pass_count} >= ${pass_count} first-pass PASS achieved"

# --- Call skill_auto_improve.sh to update SKILL.md prevention steps ---
if [ ! -f "$SKILL_AUTO_IMPROVE" ]; then
    echo "TRAINING_COMPLETION_WARN: skill_auto_improve.sh not found: $SKILL_AUTO_IMPROVE"
    exit 0
fi

skill_args=("--apply")
if [ -n "$skill" ]; then
    skill_args+=("--skill" "$skill")
fi

echo "TRAINING_COMPLETION_APPLY: running skill_auto_improve.sh ${skill_args[*]}"
bash "$SKILL_AUTO_IMPROVE" "${skill_args[@]}" 2>&1 || {
    echo "TRAINING_COMPLETION_WARN: skill_auto_improve.sh exited with $?"
}

echo "TRAINING_COMPLETION_DONE: skill=${skill:-all}"
