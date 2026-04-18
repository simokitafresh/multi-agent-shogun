#!/bin/bash
# gate_report_autofix.sh — 報告YAMLの機械的フォーマット自動修正
# 原則: 品質に影響しない純粋な構造変換のみ。内容欠落はBLOCKして家老/軍師に回す。
# 局所免疫: 忍者のペインで走る。家老のCTXを消費しない。
# Usage: bash scripts/gates/gate_report_autofix.sh <report_yaml_path>
# Exit: 0=修正完了(or修正不要), 1=auto-fix不可(要エージェント判断)
# Stdout: AUTO-FIXED: ... / NO-FIX-NEEDED / UNFIXABLE: ...
#
# === GP-107: 消火検出4問ゲート ===
# 新Fixを追加する前に4問で判定。1つでもNOなら消火構造 → BLOCKに切替えよ。
#   Q1: 内容不変か？ (構造変換: YES / 値の推定・補完: NO)
#   Q2: 忍者の判断を代行していないか？ (機械的変換: YES / 思考の代替: NO)
#   Q3: BLOCKで代替可能か？ (可能ならBLOCKを選べ)
#   Q4: 撤去しても忍者の学習ループは回るか？ (YES: 合法 / NO: 消火)
# 撤去実績: GP-091,093,094,103,104,106 (全て上記Q1-Q4でNO判定→BLOCK化)

set -e

REPORT_PATH="$1"

if [ -z "$REPORT_PATH" ] || [ ! -f "$REPORT_PATH" ]; then
    echo "UNFIXABLE: report file not found: ${REPORT_PATH:-<empty>}" >&2
    exit 1
fi

fast_no_fix_needed() {
    local report_path="$1"
    awk '
        BEGIN {
            need_python = 0
            section = ""
            saw_worker = 0
            saw_parent = 0
            saw_lessons_useful = 0
        }

        /^[^[:space:]][^:]*:/ {
            key = substr($0, 1, index($0, ":") - 1)
            section = key

            if (key == "report") {
                need_python = 1
            } else if (key == "worker_id") {
                saw_worker = 1
                if ($0 ~ /^worker_id:[[:space:]]*$/) need_python = 1
            } else if (key == "parent_cmd") {
                saw_parent = 1
                if ($0 ~ /^parent_cmd:[[:space:]]*$/) need_python = 1
            } else if (key == "lessons_useful") {
                saw_lessons_useful = 1
                if ($0 ~ /^lessons_useful:[[:space:]]*(null|~)[[:space:]]*$/) {
                    need_python = 1
                } else if ($0 !~ /^lessons_useful:[[:space:]]*$/ && $0 !~ /^lessons_useful:[[:space:]]*\[[[:space:]]*\][[:space:]]*$/) {
                    need_python = 1
                }
            } else if (key == "files_modified") {
                if ($0 !~ /^files_modified:[[:space:]]*$/ && $0 !~ /^files_modified:[[:space:]]*\[[[:space:]]*\][[:space:]]*$/) {
                    need_python = 1
                }
            } else if (key == "binary_checks") {
                if ($0 !~ /^binary_checks:[[:space:]]*$/) need_python = 1
            } else if (key == "lesson_candidate") {
                if ($0 ~ /^lesson_candidate:[[:space:]]*\[/) need_python = 1
            } else if (key == "verdict") {
                if ($0 !~ /^verdict:[[:space:]]*(PASS|FAIL|PASS_NO_IMPROVEMENT)[[:space:]]*$/ && $0 !~ /^verdict:[[:space:]]*$/) {
                    need_python = 1
                }
            }

            if (need_python) exit 1
            next
        }

        section == "files_modified" {
            if ($0 ~ /^[[:space:]]{2}-[[:space:]]/ && $0 !~ /^[[:space:]]{2}-[[:space:]]path:/) need_python = 1
        }

        section == "lessons_useful" {
            if ($0 ~ /^[[:space:]]{2}[0-9A-Za-z_-]+:/) need_python = 1
            if ($0 ~ /^[[:space:]]{2}-[[:space:]]/ && $0 !~ /^[[:space:]]{2}-[[:space:]]id:/) need_python = 1
            if ($0 ~ /UNKNOWN_[0-9]+/) need_python = 1
            if ($0 ~ /id:[[:space:]]*(UNKNOWN|None|null)/) need_python = 1
        }

        section == "binary_checks" {
            if ($0 ~ /^[[:space:]]{2}[^-[:space:]][^:]*:[[:space:]]+[^[:space:]]/) need_python = 1
            if ($0 ~ /^[[:space:]]{4}check:/) need_python = 1
            if ($0 ~ /^[[:space:]]{4}-[[:space:]]/ && $0 !~ /^[[:space:]]{4}-[[:space:]]check:/) need_python = 1
            if ($0 ~ /^[[:space:]]{4}result:/ && $0 !~ /^[[:space:]]{4}result:[[:space:]]*"?(yes|no)"?[[:space:]]*$/) need_python = 1
            if ($0 ~ /^[[:space:]]{6}result:/ && $0 !~ /^[[:space:]]{6}result:[[:space:]]*"?(yes|no)"?[[:space:]]*$/) need_python = 1
        }

        section == "self_gate_check" {
            if ($0 ~ /^[[:space:]]{2}[^:]+:[[:space:]]*(ok|yes|true|pass|o|○|ng|no|false|fail|x|×)[[:space:]]*$/) need_python = 1
        }

        {
            if (need_python) exit 1
        }

        END {
            if (!need_python && saw_worker && saw_parent && saw_lessons_useful) exit 0
            exit 1
        }
    ' "$report_path"
}

if fast_no_fix_needed "$REPORT_PATH"; then
    echo "NO-FIX-NEEDED"
    exit 0
fi

_self="${BASH_SOURCE[0]}"
SCRIPT_DIR="${_self%/*}"
[[ "$SCRIPT_DIR" != /* ]] && SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)"
REPO_ROOT="${SCRIPT_DIR%/scripts/gates}"
PY_HELPER="$SCRIPT_DIR/gate_report_autofix_main.py"
RESULT=$(python3 "$PY_HELPER" "$REPORT_PATH" 2>&1) || true

echo "$RESULT"

case "$RESULT" in
    AUTO-FIXED:*)
        LOG_FILE="$REPO_ROOT/logs/gate_fire_log.yaml"
        TS=$(date -Is)
        FIXED_ITEMS=${RESULT#AUTO-FIXED: }
        FIXED_ITEMS=${FIXED_ITEMS//\"/\\\"}
        (
            flock -w 5 200 2>/dev/null
            printf -- '- ts: "%s", file: "%s", gate: "gate_report_autofix", result: AUTO-FIXED, fixes: "%s"\n' "$TS" "$REPORT_PATH" "$FIXED_ITEMS" >> "$LOG_FILE"
        ) 200>"$LOG_FILE.lock" 2>/dev/null || true
        exit 0
        ;;
    NO-FIX-NEEDED*)
        exit 0
        ;;
    *)
        LOG_FILE="$REPO_ROOT/logs/gate_fire_log.yaml"
        TS=$(date -Is)
        REASON=${RESULT//\"/\\\"}
        (
            flock -w 5 200 2>/dev/null
            printf -- '- ts: "%s", file: "%s", gate: "gate_report_autofix", result: UNFIXABLE, reason: "%s"\n' "$TS" "$REPORT_PATH" "$REASON" >> "$LOG_FILE"
        ) 200>"$LOG_FILE.lock" 2>/dev/null || true
        exit 1
        ;;
esac
