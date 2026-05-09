#!/usr/bin/env bash
# karo_workaround_log.sh — 家老ワークアラウンド記録スクリプト
# Usage:
#   bash scripts/karo_workaround_log.sh <cmd_id> <ninja_name> "<issue>" "<fix>" [category] [missed_sg]
#   bash scripts/karo_workaround_log.sh --wa <cmd_id> <ninja_name> "<issue>" "<fix>" [category] [missed_sg] [environment_change]
#
# AC1(cmd_1211): カテゴリ別件数カウント。2件目WARN、3件目以上ALERT(ntfy+insight_write)
# AC2(cmd_1211): classify_category改善(report_yaml_format/file_disappearance/uncategorized)
# AC3(cmd_1211): resolved_by_cmdフィールド追加。resolved済みはALERTカウント除外

set -euo pipefail

SCRIPT_DIR="$(cd "${0%/*}" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$REPO_ROOT/logs/karo_workarounds.yaml"
LOCK_FILE="/tmp/karo_workarounds.lock"

# --- Reclassify mode: update category of existing entries ---
if [[ "${1:-}" == "--reclassify" ]]; then
    shift
    if [[ $# -lt 2 ]]; then
        echo "Usage: bash scripts/karo_workaround_log.sh --reclassify <cmd_id_pattern> <new_category>" >&2
        exit 1
    fi
    PATTERN="$1"
    NEW_CAT="$2"
    (
        flock -w 10 200 || { echo "[reclassify] Error: lock" >&2; exit 1; }
        TMPFILE=$(mktemp)
        awk -v pat="$PATTERN" -v newcat="$NEW_CAT" '
        function trim_scalar(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            if (value ~ /^'\''.*'\''$/ || value ~ /^".*"$/) {
                value = substr(value, 2, length(value) - 2)
            }
            return value
        }
        function reset_entry() {
            delete entry_lines
            entry_len = 0
            entry_cmd = ""
        }
        function flush_entry(    idx, line, matches, replaced) {
            if (entry_len == 0) return
            matches = (entry_cmd != "" && entry_cmd ~ pat)
            replaced = 0
            for (idx = 1; idx <= entry_len; idx++) {
                line = entry_lines[idx]
                if (matches && !replaced && line ~ /^- category:[[:space:]]*/) {
                    print "- category: " newcat
                    replaced = 1
                    continue
                }
                if (matches && !replaced && line ~ /^  category:[[:space:]]*/) {
                    print "  category: " newcat
                    replaced = 1
                    continue
                }
                print line
            }
            reset_entry()
        }
        /^- [A-Za-z0-9_]+:[[:space:]]*/ {
            flush_entry()
        }
        {
            entry_lines[++entry_len] = $0
            if ($0 ~ /^(-|  )cmd(_id)?:[[:space:]]*/) {
                value = $0
                sub(/^(-|  )cmd(_id)?:[[:space:]]*/, "", value)
                entry_cmd = trim_scalar(value)
            }
        }
        END { flush_entry() }
        ' "$LOG_FILE" > "$TMPFILE"
        mv "$TMPFILE" "$LOG_FILE"
        echo "[reclassify] Updated entries matching '$PATTERN' → category: $NEW_CAT"
    ) 200>"$LOCK_FILE"
    exit 0
fi

# --- Normalize mode: fix cmd → cmd_id key ---
if [[ "${1:-}" == "--normalize" ]]; then
    (
        flock -w 10 200 || { echo "[normalize] Error: lock" >&2; exit 1; }
        BEFORE=$(awk 'BEGIN { count = 0 } /^- cmd: / { count++ } END { print count + 0 }' "$LOG_FILE" 2>/dev/null)
        if [[ "$BEFORE" -gt 0 ]]; then
            TMPFILE=$(mktemp)
            sed "s/^- cmd: /- cmd_id: /" "$LOG_FILE" > "$TMPFILE"
            mv "$TMPFILE" "$LOG_FILE"
        fi
        echo "[normalize] Fixed $BEFORE entries: cmd → cmd_id"
    ) 200>"$LOCK_FILE"
    exit 0
fi

# --- Argument validation ---
CLEAN_MODE=false
WA_MODE=false
EXPLICIT_CATEGORY=""
MISSED_SG=""
ENVIRONMENT_CHANGE=""
if [[ "${1:-}" = "--clean" ]]; then
    CLEAN_MODE=true
    shift
    if [[ $# -lt 2 ]]; then
        echo "[karo_workaround_log] Usage: bash scripts/karo_workaround_log.sh --clean <cmd_id> <ninja_name>" >&2
        exit 1
    fi
    CMD_ID="$1"
    NINJA_NAME="$2"
    ISSUE=""
    FIX=""
    if [[ -z "$CMD_ID" || -z "$NINJA_NAME" ]]; then
        echo "[karo_workaround_log] Error: cmd_id and ninja_name must be non-empty" >&2
        exit 1
    fi
elif [[ "${1:-}" = "--wa" ]]; then
    WA_MODE=true
    shift
    if [[ $# -lt 4 || $# -gt 7 ]]; then
        echo "[karo_workaround_log] Usage: bash scripts/karo_workaround_log.sh --wa <cmd_id> <ninja_name> \"<issue>\" \"<fix>\" [category] [missed_sg] [environment_change]" >&2
        echo "  structured environment_change: type=gate|lesson|hook; file=path; pattern=grep_pattern" >&2
        exit 1
    fi
    CMD_ID="$1"
    NINJA_NAME="$2"
    ISSUE="$3"
    FIX="$4"
    EXPLICIT_CATEGORY="${5:-}"
    MISSED_SG="${6:-}"
    ENVIRONMENT_CHANGE="${7:-}"
    if [[ -z "$CMD_ID" || -z "$NINJA_NAME" || -z "$ISSUE" ]]; then
        echo "[karo_workaround_log] Error: cmd_id, ninja_name, issue must be non-empty" >&2
        exit 1
    fi
else
    if [[ $# -lt 4 || $# -gt 6 ]]; then
        echo "[karo_workaround_log] Usage: bash scripts/karo_workaround_log.sh <cmd_id> <ninja_name> \"<issue>\" \"<fix>\" [category] [missed_sg]" >&2
        echo "  --wa mode: bash scripts/karo_workaround_log.sh --wa <cmd_id> <ninja_name> \"<issue>\" \"<fix>\" [category] [missed_sg] [environment_change]" >&2
        echo "  --clean mode: bash scripts/karo_workaround_log.sh --clean <cmd_id> <ninja_name>" >&2
        exit 1
    fi
    CMD_ID="$1"
    NINJA_NAME="$2"
    ISSUE="$3"
    FIX="$4"
    EXPLICIT_CATEGORY="${5:-}"  # optional 5th arg for category
    MISSED_SG="${6:-}"          # optional 6th arg for missed SG checklist id
    if [[ -z "$CMD_ID" || -z "$NINJA_NAME" || -z "$ISSUE" ]]; then
        echo "[karo_workaround_log] Error: cmd_id, ninja_name, issue must be non-empty" >&2
        exit 1
    fi
fi

# --- Structured environment_change parsing (cmd_karo_env_change_gate) ---
parse_structured_environment_change() {
    local env_change="${1:-}"
    [[ -n "$env_change" ]] || return 1

    ENV_CHANGE_TEXT="$env_change" python3 - <<'PY'
import os
import re
import sys

text = os.environ.get("ENV_CHANGE_TEXT", "")
if not text:
    raise SystemExit(1)

def extract(key: str) -> str:
    pattern = rf'(?:^|;)\s*{key}\s*=\s*([^;]+)'
    match = re.search(pattern, text)
    if not match:
        return ""
    value = match.group(1).strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1]
    return value.strip()

etype = extract("type")
efile = extract("file")
epattern = extract("pattern")

if not (etype and efile and epattern):
    raise SystemExit(1)

print(f"{etype}\t{efile}\t{epattern}")
PY
}

verify_environment_change() {
    local env_change="${1:-}"
    local env_structured="" env_type="" env_file="" env_pattern="" env_file_resolved=""

    if [[ -z "$env_change" ]]; then
        echo "[karo_workaround_log] BLOCK: environment_change未記入。--wa時は何を環境に埋め込んだか記録せよ" >&2
        echo '  形式: type=gate|lesson|hook; file=対象ファイルパス; pattern=grepで検証可能な文字列' >&2
        return 1
    fi

    if env_structured="$(parse_structured_environment_change "$env_change" 2>/dev/null)"; then
        IFS=$'\t' read -r env_type env_file env_pattern <<< "$env_structured"
        env_file_resolved="$env_file"
        [[ "$env_file_resolved" == /* ]] || env_file_resolved="$REPO_ROOT/$env_file_resolved"
        if grep -qE -- "$env_pattern" "$env_file_resolved" 2>/dev/null; then
            echo "[karo_workaround_log] INFO: environment_change検証OK: type=${env_type} file=${env_file} pattern=${env_pattern}" >&2
        else
            echo "[karo_workaround_log] BLOCK: environment_change未実装。file=${env_file} に pattern=${env_pattern} が見つからない" >&2
            echo "  実装してからkaro_workaround_log.sh --waを再実行せよ" >&2
            return 1
        fi
    else
        echo "[karo_workaround_log] BLOCK: environment_changeが非構造化。構造化形式で記録せよ" >&2
        echo '  形式: type=gate|lesson|hook; file=対象ファイルパス; pattern=grepで検証可能な文字列' >&2
        echo '  例: type=gate; file=scripts/karo_workaround_log.sh; pattern=verify_environment_change' >&2
        return 1
    fi
}

# --- AC1(cmd_1542): ninja_id validation ---
# cmd_1967高速化: task dirループ(basename subprocess×10=45ms)廃止。
# settings.yamlが全エージェントの権威リスト。task filesはephemeral state。
validate_ninja_id() {
    local ninja_id="$1"
    local settings_file="$REPO_ROOT/config/settings.yaml"
    # karo (caller agent) は常に有効
    [[ "$ninja_id" == "karo" ]] && return 0
    # settings.yaml agents のみで検証(早期exit付き)
    awk -v id="$ninja_id" '
        /^  agents:/ { in_agents=1; next }
        in_agents && /^    [a-z][a-z0-9_]*:$/ {
            name=$0; gsub(/^ +|:$/, "", name)
            if (name == id) { found=1; exit }
        }
        in_agents && /^[^ ]/ { exit }
        in_agents && /^  [a-z]/ { exit }
        END { exit !found }
    ' "$settings_file"
}

if ! validate_ninja_id "$NINJA_NAME"; then
    echo "[karo_workaround_log] WARN: ninja_id '$NINJA_NAME' は有効なエージェント名ではない。config/settings.yaml・queue/tasks/を確認せよ" >&2
fi

# --- Argument order auto-swap (cmd_id/ninja reversal detection) ---
# 家老がcmd_idとninja_nameを逆順で渡すバグを自動検出+修正(4件データ汚染で発見 2026-04-28)
if [[ ! "$CMD_ID" =~ ^cmd_ && "$NINJA_NAME" =~ ^cmd_ ]]; then
    echo "[karo_workaround_log] WARN: cmd_id='$CMD_ID' がcmd_パターンに不一致、ninja='$NINJA_NAME'がcmd_パターン。引数が逆順。自動スワップ実行" >&2
    SWAP_TMP="$CMD_ID"
    CMD_ID="$NINJA_NAME"
    NINJA_NAME="$SWAP_TMP"
fi

# --- YAML single-quote escaping (cmd_cycle_L4_026: injection防止) ---
yaml_escape_sq() {
    # YAML single-quoted strings: ' → '' でエスケープ
    printf '%s' "${1//\'/\'\'}"
}

# --- Category auto-classification (AC2: cmd_1211) ---
classify_category() {
    local issue="$1"
    local pattern_report="lessons_useful|binary_checks|lesson_candidate|report_field_set|verdict|ac_version|report.*フォーマット|フォーマット|(dict|list|string).*(→|変換|形式)"
    local pattern_disappear="消失|missing|not found|消失|不在"
    local pattern_commit="commit|コミット|git commit|untracked|modified"
    local pattern_stale="stale|古い|残骸|旧cmd|残存"
    local pattern_double="二重|double|重複配備|二重配備"
    local pattern_redeploy="再配備|redeploy|task_redeploy"
    local pattern_report_missing="報告.*未作成|report.*未作成|報告YAML.*未|report_yaml_missing"
    if [[ "$issue" =~ $pattern_report ]]; then
        echo "report_yaml_format"
    elif [[ "$issue" =~ $pattern_report_missing ]]; then
        echo "report_missing"
    elif [[ "$issue" =~ $pattern_disappear ]]; then
        echo "file_disappearance"
    elif [[ "$issue" =~ $pattern_commit ]]; then
        echo "commit_missing"
    elif [[ "$issue" =~ $pattern_stale ]]; then
        echo "stale_report"
    elif [[ "$issue" =~ $pattern_double ]]; then
        echo "double_deploy"
    elif [[ "$issue" =~ $pattern_redeploy ]]; then
        echo "task_redeploy"
    else
        echo "uncategorized"
    fi
}

if [[ "$CLEAN_MODE" = true ]]; then
    CATEGORY="clean"
elif [[ -n "$EXPLICIT_CATEGORY" ]]; then
    CATEGORY="$EXPLICIT_CATEGORY"
else
    CATEGORY=$(classify_category "$ISSUE")
fi
TZ=UTC printf -v TIMESTAMP '%(%Y-%m-%dT%H:%M:%SZ)T' -1

# AC1(cmd_1538): WARN when category is uncategorized
if [[ "$CLEAN_MODE" != true && "$CATEGORY" == "uncategorized" ]]; then
    echo "[karo_workaround_log] WARN: categoryが未分類(uncategorized)。5番目の引数で明示的にcategoryを指定せよ: $CMD_ID/$NINJA_NAME" >&2
fi

# GP-220: WARN when category=clean but not --clean mode (data quality: workaround=true+clean矛盾防止)
if [[ "$CLEAN_MODE" != true && "$CATEGORY" == "clean" ]]; then
    echo "[karo_workaround_log] WARN: category=cleanだが--cleanモードでない。workaround=trueで記録される。--cleanモードを使え: $CMD_ID/$NINJA_NAME" >&2
fi

# AC2(cmd_1538+cmd_1542): root_cause validation (empty/null/short)
if [[ "$CLEAN_MODE" != true ]]; then
    if [[ -z "$FIX" || "$FIX" == "null" || "$FIX" == "None" || "$FIX" == "NULL" || "$FIX" == "none" ]]; then
        echo "[karo_workaround_log] WARN: root_causeが無効値('$FIX')。意味のある修正説明を記録せよ: $CMD_ID/$NINJA_NAME" >&2
    elif [[ ${#FIX} -lt 3 ]]; then
        echo "[karo_workaround_log] WARN: root_causeが短すぎる(${#FIX}文字, 最小3文字)。意味のある修正説明を記録せよ: $CMD_ID/$NINJA_NAME" >&2
    fi
fi

if [[ "$WA_MODE" = true ]]; then
    verify_environment_change "$ENVIRONMENT_CHANGE"
fi

# --- Count category entries excluding resolved (AC1+AC3: cmd_1211, GP-084: Python→awk) ---
count_category_entries() {
    local category="$1"
    if [[ ! -f "$LOG_FILE" ]]; then
        echo 0
        return
    fi
    awk -v target="$category" '
    function trim_scalar(value) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        if (value ~ /^'\''.*'\''$/ || value ~ /^".*"$/) {
            value = substr(value, 2, length(value) - 2)
        }
        return value
    }
    function flush_entry() {
        if (entry_started && cat == target && is_wa && !resolved) count++
        cat = ""
        resolved = 0
        is_wa = 0
        entry_started = 0
    }
    function apply_field(key, value) {
        value = trim_scalar(value)
        if (key == "workaround" && value == "true") is_wa = 1
        else if (key == "category") cat = value
        else if (key == "resolved_by_cmd" && value != "") resolved = 1
    }
    match($0, /^- ([A-Za-z0-9_]+):[[:space:]]*(.*)$/, m) {
        flush_entry()
        entry_started = 1
        apply_field(m[1], m[2])
        next
    }
    match($0, /^  ([A-Za-z0-9_]+):[[:space:]]*(.*)$/, m) {
        if (entry_started) apply_field(m[1], m[2])
        next
    }
    END {
        flush_entry()
        print count+0
    }
    ' "$LOG_FILE"
}

# --- Append entry with flock ---
(
    flock -w 10 200 || { echo "[karo_workaround_log] Error: Failed to acquire lock" >&2; exit 1; }

    # Initialize file if it doesn't exist
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
    fi

    if [[ "$CLEAN_MODE" = true ]]; then
        # --clean mode: workaround: false, category: clean を記録
        cat >> "$LOG_FILE" <<EOF
- cmd_id: $CMD_ID
  timestamp: '$TIMESTAMP'
  ninja: $NINJA_NAME
  workaround: false
  category: clean
  detail: ''
  root_cause: ''
  resolved_by_cmd: ''
EOF
        echo "[karo_workaround_log] Clean: $CMD_ID/$NINJA_NAME [clean]"
    else
        CAT_COUNT=$(count_category_entries "$CATEGORY")
        OCCURRENCE=$((CAT_COUNT + 1))

        # GP-086: Append entry in standard flat-list format (matches manual karo entries)
        # Old format used nested "entries:" + 2-space indent → YAML structure conflict with manual entries
        SAFE_ISSUE=$(yaml_escape_sq "$ISSUE")
        SAFE_FIX=$(yaml_escape_sq "$FIX")
        SAFE_MISSED_SG=$(yaml_escape_sq "$MISSED_SG")
        SAFE_ENVIRONMENT_CHANGE=$(yaml_escape_sq "$ENVIRONMENT_CHANGE")
        {
            cat <<EOF
- cmd_id: $CMD_ID
  timestamp: '$TIMESTAMP'
  ninja: $NINJA_NAME
  workaround: true
  category: $CATEGORY
  detail: '$SAFE_ISSUE'
  root_cause: '$SAFE_FIX'
EOF
            if [[ -n "$MISSED_SG" ]]; then
                echo "  missed_sg: '$SAFE_MISSED_SG'"
            fi
            if [[ "$WA_MODE" = true && -n "$ENVIRONMENT_CHANGE" ]]; then
                echo "  environment_change: '$SAFE_ENVIRONMENT_CHANGE'"
            fi
            cat <<EOF
  resolved_by_cmd: ''
EOF
        } >> "$LOG_FILE"

        # --- Alert mechanism (AC1: cmd_1211) ---
        if [[ "$CATEGORY" != "clean" && $OCCURRENCE -ge 3 ]]; then
            echo "[karo_workaround_log] ALERT: カテゴリ「${CATEGORY}」が${OCCURRENCE}件。構造対策cmdを起票せよ"
            bash "$SCRIPT_DIR/ntfy.sh" "【家老ALERT】workaround同一カテゴリ「${CATEGORY}」が${OCCURRENCE}件。構造対策cmd起票を強制" 2>/dev/null || true
            bash "$SCRIPT_DIR/insight_write.sh" "workaround同一カテゴリ「${CATEGORY}」が${OCCURRENCE}件蓄積。構造対策cmdの起票が必要" "high" "karo_workaround_log" 2>/dev/null || true
            # なぜなぜ7回到達: ALERTを行動に接続（表示→PD自動起票→将軍startup gate検知）
            bash "$SCRIPT_DIR/pending_decision_write.sh" create "workaround同一カテゴリ「${CATEGORY}」が${OCCURRENCE}件蓄積。構造対策cmdの起票・裁定が必要" "${CMD_ID}" escalation karo 2>/dev/null || true
        elif [[ "$CATEGORY" != "clean" && $OCCURRENCE -eq 2 ]]; then
            echo "[karo_workaround_log] WARN: 同一カテゴリ「${CATEGORY}」が2件。構造対策cmdの起票を検討せよ"
        else
            echo "[karo_workaround_log] Logged: $CMD_ID/$NINJA_NAME [$CATEGORY]"
        fi
    fi

) 200>"$LOCK_FILE"
