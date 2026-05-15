#!/usr/bin/env bash
# ============================================================
# cmd_save.sh
# 将軍がEdit toolでshogun_to_karo.yamlに書いたcmdブロックの保存前安全チェック
#
# Usage: bash scripts/cmd_save.sh <cmd_id>
#   cmd_id: 数字のみ（例: 1148）またはcmd_付き（例: cmd_1148）
#
# チェック内容:
#   1. cmdブロックがshogun_to_karo.yamlに存在するか
#   2. archive/cmds/配下の完了済みcmd_idとの重複チェック
#   3. quality_gateフィールド検査（q1_firefighting, q2_learning, q3_next_quality, q4_depth[WARNING]）
#   4. flock競合検出（家老との同時書き込み防止）
#   11.10. cmd-chronicle.md強制検索（title/purposeから類似過去cmdをINFO表示）
#   12. 内容重複チェック（キュー直近20件+archive直近20ファイルのtitle+purposeとの類似度比較）
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

QUEUE_FILE="${CMD_SAVE_QUEUE_FILE:-$PROJECT_DIR/queue/shogun_to_karo.yaml}"
ARCHIVE_CMD_DIR="${CMD_SAVE_ARCHIVE_CMD_DIR:-$PROJECT_DIR/queue/archive/cmds}"
QUALITY_LOG_FILE="${CMD_QUALITY_LOG_FILE:-$PROJECT_DIR/logs/cmd_design_quality.yaml}"
LOCK_FILE="${CMD_SAVE_LOCK_FILE:-/tmp/shogun_to_karo.lock}"
CMD_SAVE_LAST_CMD_FILE="${CMD_SAVE_LAST_CMD_FILE:-$PROJECT_DIR/logs/cmd_save_last_cmd.txt}"
CMD_SAVE_SHOGUN_LESSONS_FILE="${CMD_SAVE_SHOGUN_LESSONS_FILE:-$PROJECT_DIR/projects/infra/lessons_shogun.yaml}"
CMD_SAVE_SHOGUN_LESSON_ACK_FILE="${CMD_SAVE_SHOGUN_LESSON_ACK_FILE:-$PROJECT_DIR/queue/shogun_lesson_ack.yaml}"
PREFLIGHT_AUTOLEARN_FILE="${CMD_SAVE_PREFLIGHT_AUTOLEARN_FILE:-$PROJECT_DIR/logs/preflight_autolearn.txt}"
LORD_CONVERSATION_FILE="${CMD_SAVE_LORD_CONVERSATION_FILE:-$PROJECT_DIR/queue/lord_conversation.jsonl}"
CMD_CHRONICLE_FILE="${CMD_SAVE_CMD_CHRONICLE_FILE:-$PROJECT_DIR/context/cmd-chronicle.md}"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/firefighting_keywords.sh"

CMD_DIAGNOSIS=""
PRIOR_ATTEMPT_COUNT=0
CMD_SAVE_STDERR_LOG="$(mktemp)"
CMD_SAVE_ACCUMULATE_BLOCKS="${CMD_SAVE_ACCUMULATE_BLOCKS:-1}"
BLOCK_RETRY_NUDGE="止まるな、修正して再実行せよ"
BLOCK_RETRY_NUDGE_EMITTED=0
BLOCK_COUNT=0
CMD_BLOCK_LOADED=0
CMD_BLOCK_FOUND=0
CMD_BLOCK_CACHE_LOADED=0
declare -a BLOCK_REASONS=()
declare -a WARN_REASONS=()
declare -A CMD_BLOCK_CACHE=()
exec 3>&2
exec 2> >(tee -a "$CMD_SAVE_STDERR_LOG" >&3)

extract_cmd_diagnosis() {
    local block_text="${1:-}"
    echo "$block_text" | awk '
        /quality_gate:/ { in_qg=1; next }
        in_qg && /^[[:space:]]{6,}diagnosis:[[:space:]]*/ {
            sub(/^[[:space:]]*diagnosis:[[:space:]]*/, "")
            gsub(/^["'\'']|["'\'']$/, "")
            print
            exit
        }
        in_qg && /^[[:space:]]{4}[a-zA-Z_][a-zA-Z0-9_]*:/ { exit }
    '
}

trim_inline_yaml_scalar() {
    local value="${1:-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [[ "$value" == \"*\" && "$value" == *\" && ${#value} -ge 2 ]]; then
        value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' && ${#value} -ge 2 ]]; then
        value="${value:1:${#value}-2}"
        value="${value//\'\'/\'}"
    fi

    printf '%s' "$value"
}

update_bulletin_actioned_by_for_cmd() {
    local bulletin_file="${CMD_SAVE_BULLETIN_FILE:-$PROJECT_DIR/queue/bulletin_board.yaml}"
    [[ -f "$bulletin_file" ]] || return 0
    [[ -n "${CMD_ID:-}" ]] || return 0

    local lock_file="${bulletin_file}.lock"
    (
        flock -x 200
        CMD_BLOCK_TEXT="${CMD_BLOCK_NC:-${CMD_BLOCK:-}}" python3 - "$bulletin_file" "$CMD_ID" <<'PY'
import os
import re
import sys
import yaml

bulletin_file, cmd_id = sys.argv[1:3]
block_text = os.environ.get("CMD_BLOCK_TEXT", "")
referenced_ids = set(re.findall(r"\bblt_[0-9A-Za-z_]+\b", block_text))

if not referenced_ids:
    raise SystemExit(0)

with open(bulletin_file, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

entries = data.get("entries")
if not isinstance(entries, list):
    raise SystemExit(0)

updated = []
for entry in entries:
    if not isinstance(entry, dict):
        continue
    if str(entry.get("id", "")) not in referenced_ids:
        continue
    if str(entry.get("action_type", "info")) != "action_required":
        continue
    if str(entry.get("actioned_by", "")).strip():
        continue
    entry["actioned_by"] = cmd_id
    updated.append(str(entry.get("id", "")))

if not updated:
    raise SystemExit(0)

def sq(value):
    return str(value).replace("'", "''")

tmp_file = f"{bulletin_file}.tmp"
with open(tmp_file, "w", encoding="utf-8") as fh:
    fh.write("entries:\n")
    for entry in entries:
        fh.write(f"- id: '{sq(entry.get('id', ''))}'\n")
        fh.write("  content: |-\n")
        text = str(entry.get("content", ""))
        lines = text.splitlines() or [""]
        for line in lines:
            fh.write(f"    {line}\n")
        fh.write(f"  posted_by: '{sq(entry.get('posted_by', ''))}'\n")
        fh.write(f"  posted_at: '{sq(entry.get('posted_at', ''))}'\n")
        rc = entry.get("requires_confirmation")
        if isinstance(rc, list):
            fh.write("  requires_confirmation:\n")
            for agent_name in rc:
                fh.write(f"    - '{sq(agent_name)}'\n")
        elif rc:
            fh.write("  requires_confirmation: true\n")
        else:
            fh.write("  requires_confirmation: false\n")
        at = entry.get("action_type", "info")
        if at not in {"info", "action_required"}:
            at = "info"
        fh.write(f"  action_type: '{sq(at)}'\n")
        fh.write(f"  actioned_by: '{sq(entry.get('actioned_by', ''))}'\n")
        confirmed = entry.get("confirmed_by") or []
        if confirmed:
            fh.write("  confirmed_by:\n")
            for agent in confirmed:
                fh.write(f"    - '{sq(agent)}'\n")
        else:
            fh.write("  confirmed_by: []\n")
        fh.write(f"  status: '{sq(entry.get('status', 'open'))}'\n")

os.replace(tmp_file, bulletin_file)
print(",".join(updated))
PY
    ) 200>"$lock_file"
}

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

is_gate_or_hook_addition_cmd() {
    local block_text="${1:-${CMD_BLOCK_NC:-}}"
    # Treat underscores as identifier characters so gate_fire_log/gate_result
    # remain data names, not gate/hook addition keywords.
    local gate_hook_pattern='(^|[^A-Za-z0-9_])(gate|hook)([^A-Za-z0-9_]|$)|ゲート|フック'
    local q11_context=""
    local q11_value=""
    local scope_mode=""
    local scout_exempt=""

    [[ -n "$block_text" ]] || return 1

    scope_mode="$(cmd_block_get_field "scope_mode")"
    scout_exempt="$(cmd_block_get_field "scout_exempt")"
    [[ "${scope_mode:-}" == "SCOUT" || "${scout_exempt:-}" == "true" ]] && return 1

    q11_context=$(printf '%s\n' "$block_text" | awk '
        /^[[:space:]]*(title|purpose):/ { print; next }
        /^[[:space:]]*command:[[:space:]]*\|/ { in_command=1; next }
        /^[[:space:]]*command:[[:space:]]*[^|]/ {
            sub(/^[[:space:]]*command:[[:space:]]*/, "")
            print
            command_seen=1
            next
        }
        in_command && /^[[:space:]]{4}[A-Za-z_][A-Za-z0-9_]*:/ { in_command=0; next }
        in_command && /^[[:space:]]{4,}/ {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            if (line != "" && command_seen == 0) {
                print line
                command_seen=1
            }
            next
        }
    ')

    [[ -n "${q11_context:-}" ]] || return 1
    if printf '%s\n' "$q11_context" | grep -qiE '偽陽性|誤判定|精度改善|精度向上|改善|修正|緩和'; then
        if ! printf '%s\n' "$q11_context" | grep -qiE "(新規|新設).*(${gate_hook_pattern})|(${gate_hook_pattern}).*(新規|新設)"; then
            return 1
        fi
    fi

    q11_value="$(cmd_block_get_field "quality_gate.q11_not_already_done")"
    if q11_has_existing_alternative_verification "$q11_value" && \
       printf '%s\n' "$q11_value" | grep -qiE '既存道具|既存.*接続|既存.*統合|既存.*組込|既存.*組み込|既存.*改善|既存.*修正|既存.*精度|既存.*(gate|hook|チェック|ゲート|フック).*(条件追加|修正|改善|精度)|既存.*判定ロジック'; then
        return 1
    fi

    printf '%s\n' "$q11_context" | grep -qiE "$gate_hook_pattern" || return 1
    printf '%s\n' "$q11_context" | grep -qiE '追加|新設|導入|実装|作成|append|add|new|create|introduce' || return 1
    return 0
}

q11_has_existing_alternative_verification() {
    local q11_value="${1:-}"

    [[ -n "$q11_value" ]] || return 1
    printf '%s\n' "$q11_value" | grep -qiE 'grep|rg|sed|cat|read|確認|照合|現物|実測|docs/research|一次情報|verified|0件|該当なし' || return 1
    if printf '%s\n' "$q11_value" | grep -qiE '既存|代替|現行|既設'; then
        return 0
    fi
    if printf '%s\n' "$q11_value" | grep -qiE '0件|該当なし' && \
       printf '%s\n' "$q11_value" | grep -qiE '初回|偽陽性修正|精度改善|誤判定'; then
        return 0
    fi
    printf '%s\n' "$q11_value" | grep -qiE '(^|[^A-Za-z_])(existing|already|current)([^A-Za-z_]|$)' || return 1
    return 0
}

check_gate_hook_action_conversion() {
    local block_text="${1:-${CMD_BLOCK_NC:-}}"
    local action_text=""

    [[ -n "$block_text" ]] || return 0
    is_gate_or_hook_addition_cmd "$block_text" || return 0

    echo "INFO: gate/hook追加cmdです。既存強制フロー候補を先に検討してください:" >&2
    echo "  - cmd_save.sh: 将軍起票時の品質gateへ接続する" >&2
    echo "  - startup gate: 起動時チェックへ接続する" >&2
    echo "  - deploy_task.sh: 忍者配備時の注入/検査へ接続する" >&2
    echo "  - inbox_write.sh: 通信時の強制・遮断へ接続する" >&2
    echo "  - gate_report_format.sh: 報告提出時の構造検査へ接続する" >&2

    action_text="$(printf '%s\n' "$block_text" | awk '
        /^[[:space:]]{4}command:[[:space:]]*\|/ { in_command=1; print; next }
        /^[[:space:]]{4}command:[[:space:]]*[^|]/ {
            sub(/^[[:space:]]{4}command:[[:space:]]*/, "")
            print
            next
        }
        /^[[:space:]]{4}acceptance_criteria:[[:space:]]*$/ { in_ac=1; print; next }
        /^[[:space:]]{4}acceptance_criteria:[[:space:]]*\[/ {
            sub(/^[[:space:]]{4}acceptance_criteria:[[:space:]]*/, "")
            print
            next
        }
        (in_command || in_ac) && /^[[:space:]]{4}[A-Za-z_][A-Za-z0-9_]*:/ {
            in_command=0
            in_ac=0
            next
        }
        in_command && /^[[:space:]]{4,}/ { print; next }
        in_ac && /^[[:space:]]{6,}-/ { print; next }
    ')"

    [[ -n "${action_text:-}" ]] || return 0
    if printf '%s\n' "$action_text" | grep -qiE 'BLOCK|exit[[:space:]]+1|強制|自動実行|自動化'; then
        return 0
    fi

    echo "WARNING: gate/hook追加cmdに行動変換キーワードがありません。WARN止まりの新規gate/hookは運用を変えません" >&2
    echo "  推奨アクション: acceptance_criteria または command に BLOCK / exit 1 / 強制 / 自動実行 / 自動化 のいずれかを明記し、検知から行動変換まで設計せよ" >&2
    record_warn_reason "gate/hook追加cmdに行動変換キーワードなし" "check=gate_hook_action_conversion"
}

extract_acceptance_criteria_block() {
    [[ -n "${CMD_BLOCK_NC:-}" ]] || return 0

    printf '%s\n' "$CMD_BLOCK_NC" | awk '
        /^[[:space:]]*acceptance_criteria:/ {
            line = $0
            sub(/^[[:space:]]*acceptance_criteria:[[:space:]]*/, "", line)
            if (line != "") print line
            in_ac=1
            next
        }
        in_ac && /^[[:space:]]{4}[a-zA-Z_][a-zA-Z0-9_]*:/ && !/^[[:space:]]*- / { exit }
        in_ac { print }
    '
}

check_lord_instruction_ac_alignment_info() {
    local q8_value="${1:-}"
    local ac_block="${2:-}"
    local result status keywords quote

    [[ -n "${q8_value//[[:space:]]/}" ]] || return 0
    [[ -n "${ac_block//[[:space:]]/}" ]] || return 0
    printf '%s\n' "$q8_value" | grep -q '「' || return 0
    printf '%s\n' "$q8_value" | grep -q '」' || return 0

    result="$(
        Q8_VALUE="$q8_value" AC_BLOCK="$ac_block" python3 - <<'PY'
import os
import re

q8 = os.environ.get("Q8_VALUE", "")
ac = os.environ.get("AC_BLOCK", "")
quotes = [q.strip() for q in re.findall(r"「([^」]+)」", q8) if q.strip()]
if not quotes:
    print("SKIP\t\t")
    raise SystemExit

stopwords = set((
    "する", "して", "した", "いる", "ある", "こと", "これ", "それ", "ため",
    "なら", "では", "ない", "やれ", "探せ", "見ろ", "確認", "指示", "殿",
    "全部", "全て", "必ず", "まず", "から", "まで", "よう", "その", "この",
))
keywords = []
for quote in quotes:
    normalized = re.sub(r"([A-Za-z])([一-龥ぁ-んァ-ン])", r"\1 \2", quote)
    normalized = re.sub(r"([一-龥ぁ-んァ-ン])([A-Za-z])", r"\1 \2", normalized)
    for token in re.findall(r"[A-Za-z0-9_][A-Za-z0-9_.-]*|[一-龥ぁ-んァ-ン]{2,}", normalized):
        token = token.strip("._-")
        if not token or token in stopwords:
            continue
        if re.fullmatch(r"[A-Za-z0-9_.-]+", token) and len(token) < 2:
            continue
        if token not in keywords:
            keywords.append(token)

if not keywords:
    print("SKIP\t\t")
    raise SystemExit

matched = [kw for kw in keywords if kw.lower() in ac.lower()]
if matched:
    print("PASS\t" + ",".join(matched[:8]) + "\t" + quotes[0][:120])
else:
    print("INFO\t" + ",".join(keywords[:8]) + "\t" + quotes[0][:120])
PY
    )"

    IFS=$'\t' read -r status keywords quote <<< "$result"
    [[ "$status" == "INFO" ]] || return 0

    echo "INFO: q8_why_whatの殿指示引用とACキーワードの整合を確認してください" >&2
    echo "  指示引用: 「${quote}」" >&2
    echo "  抽出キーワード: ${keywords}" >&2
    echo "  AC内に引用キーワードが見当たりません。殿の指示範囲外の作業をAC化していないか確認せよ(LS-A08)" >&2
}

collect_assumption_claims_missing_dates() {
    local block_text="${1:-${CMD_BLOCK_NC:-}}"

    [[ -n "$block_text" ]] || return 0

    ASSUMPTION_BLOCK_TEXT="$block_text" python3 - <<'PY'
import os
import re

content = os.environ.get("ASSUMPTION_BLOCK_TEXT", "")
lines = content.splitlines()
in_assumptions = False
assumptions_indent = -1
current = {}
entries = []

for line in lines:
    m_aline = re.match(r'^(\s*)assumptions\s*:', line)
    if m_aline and not in_assumptions:
        in_assumptions = True
        assumptions_indent = len(m_aline.group(1))
        continue

    if in_assumptions:
        if line.strip():
            cur_indent = len(line) - len(line.lstrip())
            if cur_indent <= assumptions_indent:
                in_assumptions = False
                if current:
                    entries.append(dict(current))
                current = {}
                continue
        if re.match(r'\s*-\s', line):
            if current:
                entries.append(dict(current))
            current = {}
        m = re.match(r'^\s*-\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.+)', line)
        if m:
            current[m.group(1)] = m.group(2).strip().strip('"').strip("'")
            continue
        m = re.search(r'^\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.+)', line)
        if m:
            current[m.group(1)] = m.group(2).strip().strip('"').strip("'")

if current:
    entries.append(current)

date_pat = re.compile(r'(?:19|20)\d{2}-\d{2}-\d{2}')
temporal_markers = re.compile(
    r'(時点|現在|現時点|直近|最新|本日|今日|当時|初回|'
    r'確認済|完了|未実装|未達成|未実施|固定|稼働|利用可能|'
    r'存在|非空|空|実行可能|生成済|取得済)'
)

def claim_needs_date(entry):
    claim = entry.get("claim", "").strip()
    source = entry.get("source", "").strip()
    if not claim:
        return False
    if temporal_markers.search(claim):
        return True
    if re.search(r'(本番|Render|startup gate|gate出力|原票|ログ)', claim, re.I):
        return True
    if source and re.search(r'(tests/unit/|scripts/|docs/research/)', source):
        return False
    return False

for entry in entries:
    claim = entry.get("claim", "").strip()
    if claim and not date_pat.search(claim) and claim_needs_date(entry):
        print(claim)
PY
}

collect_negative_claims_missing_grep_evidence() {
    local block_text="${1:-${CMD_BLOCK_NC:-}}"

    [[ -n "$block_text" ]] || return 0

    ASSUMPTION_BLOCK_TEXT="$block_text" python3 - <<'PY'
import os
import re

content = os.environ.get("ASSUMPTION_BLOCK_TEXT", "")
lines = content.splitlines()

scan_lines = []
skip_q11 = False
q11_indent = -1
for line in lines:
    m_q11 = re.match(r'^(\s*)q11_not_already_done\s*:', line)
    if m_q11:
        skip_q11 = True
        q11_indent = len(m_q11.group(1))
        continue
    if skip_q11:
        if line.strip():
            cur_indent = len(line) - len(line.lstrip())
            if cur_indent <= q11_indent:
                skip_q11 = False
            else:
                continue
        else:
            continue
    scan_lines.append(line)
scan_content = "\n".join(scan_lines)

negative_pat = re.compile(r'(未実装|存在しない|仕組みがない|未対応)')
evidence_pat = re.compile(
    r'\b(?:grep|rg)\b[\s\S]*(?:[0-9]+\s*件|[0-9]+\s*hits?|0\s*matches?|no\s+matches?|ヒットなし|該当なし)',
    re.I,
)

in_assumptions = False
assumptions_indent = -1
current = {}
entries = []

for line in lines:
    m_aline = re.match(r'^(\s*)assumptions\s*:', line)
    if m_aline and not in_assumptions:
        in_assumptions = True
        assumptions_indent = len(m_aline.group(1))
        continue

    if in_assumptions:
        if line.strip():
            cur_indent = len(line) - len(line.lstrip())
            if cur_indent <= assumptions_indent:
                in_assumptions = False
                if current:
                    entries.append(dict(current))
                current = {}
                continue
        if re.match(r'\s*-\s', line):
            if current:
                entries.append(dict(current))
            current = {}
        m = re.match(r'^\s*-\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.+)', line)
        if m:
            current[m.group(1)] = m.group(2).strip().strip('"').strip("'")
            continue
        m = re.search(r'^\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.+)', line)
        if m:
            current[m.group(1)] = m.group(2).strip().strip('"').strip("'")
        continue

if current:
    entries.append(current)

if not negative_pat.search(scan_content):
    raise SystemExit(0)

for entry in entries:
    claim = entry.get("claim", "").strip()
    if claim and evidence_pat.search(claim):
        raise SystemExit(0)

for entry in entries:
    claim = entry.get("claim", "").strip()
    if claim:
        print(claim)
PY
}

collect_bulletin_count_claims_missing_grep_evidence() {
    local block_text="${1:-${CMD_BLOCK_NC:-}}"

    [[ -n "$block_text" ]] || return 0

    ASSUMPTION_BLOCK_TEXT="$block_text" python3 - <<'PY'
import os
import re

content = os.environ.get("ASSUMPTION_BLOCK_TEXT", "")
lines = content.splitlines()

in_assumptions = False
assumptions_indent = -1
current = {}
entries = []

for line in lines:
    m_aline = re.match(r'^(\s*)assumptions\s*:', line)
    if m_aline and not in_assumptions:
        in_assumptions = True
        assumptions_indent = len(m_aline.group(1))
        continue

    if in_assumptions:
        if line.strip():
            cur_indent = len(line) - len(line.lstrip())
            if cur_indent <= assumptions_indent:
                in_assumptions = False
                if current:
                    entries.append(dict(current))
                current = {}
                continue
        if re.match(r'\s*-\s', line):
            if current:
                entries.append(dict(current))
            current = {}
        m = re.match(r'^\s*-\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.+)', line)
        if m:
            current[m.group(1)] = m.group(2).strip().strip('"').strip("'")
            continue
        m = re.search(r'^\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.+)', line)
        if m:
            current[m.group(1)] = m.group(2).strip().strip('"').strip("'")
        continue

if current:
    entries.append(current)

bulletin_pat = re.compile(r'(掲示板|bulletin|blt_[0-9A-Za-z_]+)', re.I)
count_pat = re.compile(r'\d+\s*(?:件|entries?|items?|records?)', re.I)
grep_evidence_pat = re.compile(
    r'\b(?:grep|rg)\b[\s\S]*(?:[0-9]+\s*件|[0-9]+\s*hits?|0\s*matches?|no\s+matches?|ヒットなし|該当なし)',
    re.I,
)

for entry in entries:
    claim = entry.get("claim", "").strip()
    if not claim:
        continue
    if bulletin_pat.search(claim) and count_pat.search(claim) and not grep_evidence_pat.search(claim):
        print(claim)
PY
}

check_measurement_env_info() {
    [[ -n "${CMD_BLOCK_NC:-}" ]] || return 0

    if printf '%s\n' "$CMD_BLOCK_NC" | grep -qE '^[[:space:]]*measurement_env[[:space:]]*:'; then
        return 0
    fi

    local search_text first_hit
    search_text="$(
        printf '%s\n' "$CMD_BLOCK_NC" | awk '
            /^[[:space:]]*(quality_gate|assumptions|measurement_env):[[:space:]]*/ {
                skip=1
                skip_indent=match($0, /[^ ]/) - 1
                next
            }
            skip {
                if ($0 !~ /^[[:space:]]*$/) {
                    cur_indent=match($0, /[^ ]/) - 1
                    if (cur_indent <= skip_indent) {
                        skip=0
                    } else {
                        next
                    }
                } else {
                    next
                }
            }
            !skip { print }
        '
    )"

    first_hit="$(printf '%s\n' "$search_text" | grep -iE 'ローカル|local|本番|production|prod|Render|staging|環境差異|環境差|env差|DB差|database差' | head -1 || true)"
    [[ -n "${first_hit:-}" ]] || return 0

    echo "INFO: ローカル/本番などの環境差異キーワードを検出しました。measurement_envフィールドの記入を検討してください" >&2
    echo "  検出行: ${first_hit}" >&2
    echo "  例: measurement_env: \"local=WSL2 repo / production=Render+prod DB。差異の影響: なし（理由）\"" >&2
    record_warn_reason "measurement_env記入提案" "info" "check=measurement_env_info"
}

load_cmd_block() {
    if [[ "$CMD_BLOCK_LOADED" -eq 1 ]]; then
        [[ "$CMD_BLOCK_FOUND" -eq 1 ]]
        return $?
    fi

    CMD_BLOCK_LOADED=1
    CMD_BLOCK_FOUND=0
    CMD_BLOCK=""
    CMD_BLOCK_NC=""

    [[ -f "$QUEUE_FILE" ]] || return 1

    CMD_BLOCK=$(awk -v cmd_id="$CMD_ID" '
        $0 == "  " cmd_id ":" { found = 1; next }
        found && /^  cmd_[^:]+:/ { exit }
        found { print }
    ' "$QUEUE_FILE")

    [[ -n "$CMD_BLOCK" ]] || return 1

    CMD_BLOCK_NC=$(printf '%s\n' "$CMD_BLOCK" | awk '!/^[[:space:]]*#/')
    CMD_BLOCK_FOUND=1
    return 0
}

load_cmd_block_cache() {
    local line key value current_section="" _tcv

    if [[ "$CMD_BLOCK_CACHE_LOADED" -eq 1 ]]; then
        [[ "$CMD_BLOCK_FOUND" -eq 1 ]]
        return $?
    fi

    CMD_BLOCK_CACHE_LOADED=1
    [[ "$CMD_BLOCK_FOUND" -eq 1 ]] || return 1

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]{4}([A-Za-z_][A-Za-z0-9_]*):[[:space:]]*(.*)$ ]]; then
            current_section=""
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            if [[ -z "$value" ]]; then
                CMD_BLOCK_CACHE["$key"]=""
                current_section="$key"
            else
                # cmd_2077: trim_inline_yaml_scalarをインライン化してsubshell排除
                _tcv="$value"
                _tcv="${_tcv#"${_tcv%%[![:space:]]*}"}"
                _tcv="${_tcv%"${_tcv##*[![:space:]]}"}"
                if [[ "$_tcv" == \"*\" && "$_tcv" == *\" && ${#_tcv} -ge 2 ]]; then
                    _tcv="${_tcv:1:${#_tcv}-2}"
                elif [[ "$_tcv" == \'*\' && "$_tcv" == *\' && ${#_tcv} -ge 2 ]]; then
                    _tcv="${_tcv:1:${#_tcv}-2}"
                    _tcv="${_tcv//\'\'/\'}"
                fi
                CMD_BLOCK_CACHE["$key"]="$_tcv"
            fi
            continue
        fi

        if [[ -n "$current_section" && "$line" =~ ^[[:space:]]{6}([A-Za-z_][A-Za-z0-9_]*):[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            # cmd_2077: trim_inline_yaml_scalarをインライン化してsubshell排除
            _tcv="$value"
            _tcv="${_tcv#"${_tcv%%[![:space:]]*}"}"
            _tcv="${_tcv%"${_tcv##*[![:space:]]}"}"
            if [[ "$_tcv" == \"*\" && "$_tcv" == *\" && ${#_tcv} -ge 2 ]]; then
                _tcv="${_tcv:1:${#_tcv}-2}"
            elif [[ "$_tcv" == \'*\' && "$_tcv" == *\' && ${#_tcv} -ge 2 ]]; then
                _tcv="${_tcv:1:${#_tcv}-2}"
                _tcv="${_tcv//\'\'/\'}"
            fi
            CMD_BLOCK_CACHE["${current_section}.${key}"]="$_tcv"
        fi
    done <<< "$CMD_BLOCK_NC"

    return 0
}

cmd_block_has_field() {
    local field_name="$1"
    load_cmd_block_cache || return 1
    [[ -v "CMD_BLOCK_CACHE[$field_name]" ]]
}

cmd_block_get_field() {
    local field_name="$1"
    local default_value="${2:-}"

    load_cmd_block_cache || {
        printf '%s' "$default_value"
        return 0
    }

    if [[ -v "CMD_BLOCK_CACHE[$field_name]" ]]; then
        printf '%s' "${CMD_BLOCK_CACHE[$field_name]}"
    else
        printf '%s' "$default_value"
    fi
}

check_depends_on_field() {
    load_cmd_block || return 0
    load_cmd_block_cache || return 0

    local depends_on_value
    depends_on_value="$(cmd_block_get_field "depends_on")"

    if [[ -z "${depends_on_value:-}" ]]; then
        echo "WARNING: depends_on未記入。依存cmdがある場合は depends_on: cmd_XXXX、依存なしなら depends_on: none を記入せよ" >&2
        record_warn_reason "depends_on未記入" "check=depends_on_field"
        return 0
    fi

    if [[ "$depends_on_value" != "none" && ! "$depends_on_value" =~ ^cmd_[0-9]+$ ]]; then
        echo "WARNING: depends_on形式不正。depends_on: cmd_XXXX または depends_on: none のどちらかで記入せよ" >&2
        echo "  現在値: ${depends_on_value}" >&2
        record_warn_reason "depends_on形式不正" "check=depends_on_field"
    fi
}

collect_primary_cmd_targets() {
    [[ -n "${CMD_BLOCK_NC:-}" ]] || return 0

    normalize_bundle_path() {
        local path="${1:-}"
        local repo_root="${PROJECT_DIR:-${PROJECT_ROOT:-}}"
        path="${path%/}"

        if [[ -n "$repo_root" ]]; then
            path="${path#"$repo_root"/}"
            [[ "$path" == "$repo_root" ]] && path=""
        fi

        printf '%s\n' "$path"
    }

    detect_target_scope() {
        local raw_path="${1:-}"
        local repo_root="${PROJECT_DIR:-${PROJECT_ROOT:-}}"
        local normalized_path basename
        [[ -n "$raw_path" ]] || return 1

        normalized_path="$(normalize_bundle_path "$raw_path")"
        normalized_path="${normalized_path%/}"
        [[ -n "$normalized_path" ]] || return 1

        basename="${normalized_path##*/}"
        if [[ "$raw_path" == */ ]]; then
            printf '%s\n' "$normalized_path"
            return 0
        fi
        if [[ -n "$repo_root" && -d "$repo_root/$normalized_path" ]]; then
            printf '%s\n' "$normalized_path"
            return 0
        fi
        if [[ "$raw_path" = /* && -d "$raw_path" ]]; then
            printf '%s\n' "$normalized_path"
            return 0
        fi
        [[ "$basename" == *.* ]] && return 1
        return 1
    }

    local target_path_raw target_scope
    target_path_raw="$(
        printf '%s\n' "$CMD_BLOCK_NC" \
            | awk '
                /^[[:space:]]{4}target_path:[[:space:]]*/ {
                    sub(/^[[:space:]]{4}target_path:[[:space:]]*/, "")
                    if ($0 !~ /^[|>][-+]?$/) {
                        print
                    }
                    exit
                }
            '
    )"
    target_scope="$(detect_target_scope "$target_path_raw" || true)"

    printf '%s\n' "$CMD_BLOCK_NC" \
        | awk '
            function emit_inline(value) {
                if (value != "" && value !~ /^[|>][-+]?$/) {
                    print value
                }
            }

            /^[[:space:]]{4}[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*/ {
                if (in_block && $0 !~ /^[[:space:]]{6,}/) {
                    in_block=0
                }

                match($0, /^[[:space:]]{4}([A-Za-z_][A-Za-z0-9_]*):[[:space:]]*(.*)$/, m)
                key=m[1]
                value=m[2]

                if (key == "target_path") {
                    if (value ~ /^[|>][-+]?$/) {
                        in_block=1
                    } else {
                        in_block=0
                        emit_inline(value)
                    }
                } else {
                    in_block=0
                }
                next
            }

            in_block && /^[[:space:]]{6,}/ { print }
        ' \
        | sed 's/--[A-Za-z_-]*[[:space:]]*[^[:space:]]*//g' \
        | grep -oE '((scripts|docs|context|config|projects|queue|lib|memory|logs|instructions|tests)/[^[:space:]`"'\''(),]+|/mnt/[^[:space:]`"'\''(),]+)' 2>/dev/null \
        | sed 's/[.,:;]$//' \
        | while IFS= read -r path; do
            local normalized_path
            normalized_path="$(normalize_bundle_path "$path")"
            [[ -n "$normalized_path" ]] || continue
            if [[ -n "$target_scope" && ( "$normalized_path" == "$target_scope" || "$normalized_path" == "$target_scope/"* ) ]]; then
                printf '%s\n' "$target_scope"
            else
                printf '%s\n' "$normalized_path"
            fi
        done \
        | awk '
            !/^tests(\/|$)/ &&
            !/^docs\/research(\/|$)/ &&
            !/^queue\/reports(\/|$)/ &&
            !/^queue\/archive(\/|$)/ &&
            !/^outputs(\/|$)/ &&
            !/^context(\/|$)/ {
                print
            }
        ' \
        | sort -u
}

check_self_reread_red_flag() {
    local combined

    combined=$(printf '%s\n%s\n%s\n' \
        "$(cmd_block_get_field "title")" \
        "$(cmd_block_get_field "purpose")" \
        "$CMD_BLOCK_NC")

    if echo "$combined" | grep -qiE '(自己(再読|申告)|自分で(読み直|読み返)|読み直[しせす]|読み返[しせす]|目視確認.*(品質|判定)|セルフレビュー)'; then
        if echo "$combined" | grep -qiE '(曖昧|不明瞭|ambiguous|clarity|明瞭)'; then
            echo "WARNING: 自己再読パターンを検出。書き手自身の目視確認/自己申告は mizchi Red flag『自分で読み直せば同じ効果』になりうる。別役割の評価者へ分離せよ" >&2
            record_warn_reason "自己再読パターン" "check=check_self_reread_red_flag"
        fi
    fi
}

check_bundle_red_flag() {
    local targets target_count bundle_signal targets_inline

    targets="$(collect_primary_cmd_targets || true)"
    target_count=$(printf '%s\n' "$targets" | awk 'NF{c++} END{print c+0}')
    bundle_signal=0

    if printf '%s\n' "$CMD_BLOCK_NC" | grep -qiE '(^|[^A-Za-z])(bundle|バンドル)([^A-Za-z]|$)|\+|一気に|まとめて|同時に|複数|[0-9]+点|[0-9]+件|[0-9]+パターン|統合'; then
        bundle_signal=1
    fi

    if (( target_count >= 3 )) || { (( target_count >= 2 )) && (( bundle_signal == 1 )); }; then
        targets_inline=$(printf '%s\n' "$targets" | awk 'NF{printf "%s%s", sep, $0; sep=", "} END{print ""}')
        echo "WARNING: バンドルパターンを検出。1cmdで複数対象(${target_count}): ${targets_inline}。無関係な修正を一気に束ねていないか確認せよ" >&2
        record_warn_reason "バンドルパターン" "check=check_bundle_red_flag"
    fi
}

record_block_reason() {
    local reason="${1:-}"
    [[ -n "$reason" ]] || return 0

    if [[ "${BLOCK_RETRY_NUDGE_EMITTED:-0}" -eq 0 ]]; then
        echo "${BLOCK_RETRY_NUDGE:-止まるな、修正して再実行せよ}" >&2
        BLOCK_RETRY_NUDGE_EMITTED=1
    fi

    echo "BLOCK: $reason" >&2
    BLOCK_REASONS+=("$reason")
    BLOCK_COUNT=$((BLOCK_COUNT + 1))
}

build_warn_note() {
    local reason="${1:-}"
    shift || true

    local warn_type=""
    if [[ $# -gt 0 && "$1" != *=* ]]; then
        warn_type="$1"
        shift || true
    fi

    [[ -n "$warn_type" ]] || warn_type="${reason:-warn_unknown}"

    local note="$warn_type"
    local metadata
    for metadata in "$@"; do
        [[ -n "$metadata" ]] || continue
        note="${note}|${metadata}"
    done

    if [[ -n "$reason" && "$reason" != "$warn_type" ]]; then
        note="${note}|${reason}"
    fi

    printf '%s' "$note"
}

warn_note_key() {
    local note="${1:-}"
    printf '%s' "${note%%|*}"
}

warn_note_message() {
    local note="${1:-}"
    [[ -n "$note" ]] || return 0

    local segment display=""
    IFS='|' read -r -a _warn_segments <<< "$note"
    if [[ ${#_warn_segments[@]} -le 1 ]]; then
        printf '%s' "$note"
        return 0
    fi

    for segment in "${_warn_segments[@]:1}"; do
        [[ -n "$segment" && "$segment" != *=* ]] || continue
        display="$segment"
    done

    printf '%s' "${display:-${_warn_segments[0]}}"
}

record_warn_reason() {
    local reason="${1:-}"
    shift || true

    local warn_args=("$@")
    local has_check_metadata=0
    local warn_arg
    for warn_arg in "${warn_args[@]}"; do
        if [[ "$warn_arg" == check=* ]]; then
            has_check_metadata=1
            break
        fi
    done

    if [[ "$has_check_metadata" -eq 0 ]]; then
        local caller_fn=""
        local stack_fn
        for stack_fn in "${FUNCNAME[@]:1}"; do
            case "$stack_fn" in
                ""|record_warn_reason|main|source)
                    continue
                    ;;
            esac
            caller_fn="$stack_fn"
            break
        done
        [[ -n "$caller_fn" ]] && warn_args+=("check=${caller_fn}")
    fi

    local warn_note warn_key display_reason
    warn_note="$(build_warn_note "$reason" "${warn_args[@]}")"
    warn_key="$(warn_note_key "$warn_note")"
    display_reason="$(warn_note_message "$warn_note")"

    WARN_REASONS+=("$warn_note")
    WARN_COUNT=$((WARN_COUNT + 1))
    # 遡及学習: 過去の同一WARN件数を即表示（殿裁定2026-04-21）
    # 1回目で「過去N回出ている」と気づけば根本修正のROIが分かる
    local _prior_count
    _prior_count=$(count_same_warn_pattern "$warn_key" 2>/dev/null || echo 0)
    [[ "$_prior_count" =~ ^[0-9]+$ ]] || _prior_count=0
    if (( _prior_count > 0 )); then
        echo "  ★ このWARN(${display_reason})は過去${_prior_count}回出現。消火ではなく根本修正を検討せよ。" >&2

        local _note_segment _check_name="" _src_file _grep_output=""
        IFS='|' read -r -a _warn_segments <<< "$warn_note"
        for _note_segment in "${_warn_segments[@]:1}"; do
            [[ "$_note_segment" == check=* ]] || continue
            _check_name="${_note_segment#check=}"
            break
        done

        _src_file="${SRC_SAVE_SCRIPT:-${BASH_SOURCE[0]:-$0}}"
        if [[ ! -f "$_src_file" && -n "${SAVE_SCRIPT:-}" && -f "$SAVE_SCRIPT" ]]; then
            _src_file="$SAVE_SCRIPT"
        fi

        if [[ -f "$_src_file" ]]; then
            if [[ -n "$_check_name" ]]; then
                _grep_output="$(grep -nF -- "$_check_name" "$_src_file" | head -n 2 || true)"
            fi
            if [[ -z "$_grep_output" && -n "$warn_key" ]]; then
                _grep_output="$(grep -nF -- "$warn_key" "$_src_file" | head -n 2 || true)"
            fi
        fi

        if [[ -n "$_grep_output" ]]; then
            echo "  ★ Session State: 検出ロジック該当行" >&2
            while IFS= read -r _grep_line; do
                [[ -n "$_grep_line" ]] || continue
                echo "    ${_grep_line}" >&2
            done <<< "$_grep_output"
        fi
    fi
}

warn_note_check_name() {
    local note="${1:-}"
    local segment
    IFS='|' read -r -a _warn_check_segments <<< "$note"
    for segment in "${_warn_check_segments[@]:1}"; do
        [[ "$segment" == check=* ]] || continue
        printf '%s' "${segment#check=}"
        return 0
    done
    printf '%s' "$(warn_note_key "$note")"
}

log_preflight_autolearn() {
    local warn_note="${1:-}"
    local prior_count="${2:-}"
    [[ -n "$warn_note" && -n "$prior_count" ]] || return 0

    local check_name warn_key timestamp tmp_dir
    check_name="$(warn_note_check_name "$warn_note")"
    warn_key="$(warn_note_key "$warn_note")"
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    tmp_dir="$(dirname "$PREFLIGHT_AUTOLEARN_FILE")"
    mkdir -p "$tmp_dir" 2>/dev/null || return 0

    {
        flock -w 5 201 || exit 0
        printf '%s check=%s count=%s warn=%s cmd=%s\n' \
            "$timestamp" "$check_name" "$prior_count" "$warn_key" "$CMD_ID" >> "$PREFLIGHT_AUTOLEARN_FILE"
    } 201>"${PREFLIGHT_AUTOLEARN_FILE}.lock" || true
}

abort_if_block_immediate() {
    [[ "$CMD_SAVE_ACCUMULATE_BLOCKS" == "1" ]] && return 0
    return 1
}

show_prior_attempts() {
    [[ -f "$QUALITY_LOG_FILE" ]] || return 0

    local prior_output cache_file cache_tmp cache_sig cached_sig
    cache_file="/tmp/cmd_save_prior_attempts_${CMD_ID}.cache"
    cache_sig="$(stat -c '%Y:%s' "$QUALITY_LOG_FILE" 2>/dev/null || echo "")"

    if [[ -n "$cache_sig" && -f "$cache_file" ]]; then
        IFS= read -r cached_sig < "$cache_file" || cached_sig=""
        if [[ "$cached_sig" == "$cache_sig" ]]; then
            prior_output="$(tail -n +2 "$cache_file")"
        fi
    fi

    if [[ -z "${prior_output:-}" ]]; then
        prior_output=$(CMD_SAVE_CMD_ID="$CMD_ID" CMD_SAVE_QUALITY_LOG="$QUALITY_LOG_FILE" python3 - <<'PY'
import os
import yaml

cmd_id = os.environ.get("CMD_SAVE_CMD_ID", "")
log_path = os.environ.get("CMD_SAVE_QUALITY_LOG", "")

if not cmd_id or not log_path or not os.path.exists(log_path):
    print(0)
    raise SystemExit(0)

with open(log_path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

entries = (data.get("entries") or []) if isinstance(data, dict) else []
filtered = []
for entry in entries:
    if not isinstance(entry, dict):
        continue
    if entry.get("cmd_id") != cmd_id:
        continue
    if entry.get("gate_result") != "BLOCK":
        continue
    if entry.get("source") != "cmd_save":
        continue
    filtered.append(entry)

print(len(filtered))
for idx, entry in enumerate(filtered, start=1):
    reason = str(entry.get("notes", "") or "").split("|")[0].strip() or "unknown"
    diagnosis = str(entry.get("diagnosis", "") or "").strip()
    if diagnosis:
        print(f"Attempt {idx}: {reason} diagnosis: {diagnosis}")
    else:
        print(f"Attempt {idx}: {reason}")
PY
)
        if [[ -n "$cache_sig" ]]; then
            cache_tmp="$(mktemp)"
            {
                printf '%s\n' "$cache_sig"
                printf '%s\n' "$prior_output"
            } > "$cache_tmp"
            mv "$cache_tmp" "$cache_file"
        fi
    fi

    PRIOR_ATTEMPT_COUNT=$(echo "$prior_output" | head -n1 | tr -d '[:space:]')
    [[ "${PRIOR_ATTEMPT_COUNT:-0}" =~ ^[0-9]+$ ]] || PRIOR_ATTEMPT_COUNT=0
    (( PRIOR_ATTEMPT_COUNT > 0 )) || return 0

    echo "★ Prior attempts (同じcmd):" >&2
    echo "$prior_output" | tail -n +2 | while IFS= read -r line; do
        [[ -n "$line" ]] && echo "  $line" >&2
    done
    echo "  DO NOT repeat these — 別のアプローチを取れ" >&2
}

count_same_reason_prior_blocks() {
    local current_reason="${1:-}"
    [[ -n "$current_reason" && -f "$QUALITY_LOG_FILE" ]] || {
        echo 0
        return 0
    }

    CMD_SAVE_CMD_ID="$CMD_ID" \
    CMD_SAVE_QUALITY_LOG="$QUALITY_LOG_FILE" \
    CMD_SAVE_BLOCK_REASON="$current_reason" \
    python3 - <<'PY'
import os
import yaml

cmd_id = os.environ.get("CMD_SAVE_CMD_ID", "")
log_path = os.environ.get("CMD_SAVE_QUALITY_LOG", "")
current_reason = os.environ.get("CMD_SAVE_BLOCK_REASON", "").strip()

if not cmd_id or not current_reason or not log_path or not os.path.exists(log_path):
    print(0)
    raise SystemExit(0)

with open(log_path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

entries = (data.get("entries") or []) if isinstance(data, dict) else []
filtered = [
    entry for entry in entries
    if isinstance(entry, dict)
    and entry.get("cmd_id") == cmd_id
    and entry.get("gate_result") == "BLOCK"
    and entry.get("source") == "cmd_save"
]

count = 0
for entry in reversed(filtered[-5:]):
    reason = str(entry.get("notes", "") or "").split("|")[0].strip()
    if reason == current_reason:
        count += 1
    else:
        break

print(count)
PY
}

extract_last_block_reason() {
    python3 - "$CMD_SAVE_STDERR_LOG" <<'PY'
import re
import sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()
except FileNotFoundError:
    print("")
    raise SystemExit(0)

for line in reversed(lines):
    match = re.match(r"BLOCK:\s*(.+)", line.strip())
    if match:
        print(match.group(1).strip())
        break
else:
    print("")
PY
}

log_cmd_save_block() {
    local block_reason="${1:-}"
    [[ -n "$block_reason" && -f "$SCRIPT_DIR/cmd_quality_log.sh" ]] || return 0

    CMD_QUALITY_LOG_FILE="$QUALITY_LOG_FILE" \
    CMD_QUALITY_SOURCE="cmd_save" \
    CMD_QUALITY_DIAGNOSIS="$CMD_DIAGNOSIS" \
    CMD_QUALITY_FAST_METADATA=1 \
    bash "$SCRIPT_DIR/cmd_quality_log.sh" "$CMD_ID" "BLOCK" "no" "0" "$block_reason" >/dev/null 2>&1 || true
}

log_cmd_save_warns() {
    [[ ${#WARN_REASONS[@]} -gt 0 && -f "$SCRIPT_DIR/cmd_quality_log.sh" ]] || return 0
    local warn_note
    for warn_note in "${WARN_REASONS[@]}"; do
        CMD_QUALITY_LOG_FILE="$QUALITY_LOG_FILE" \
        CMD_QUALITY_SOURCE="cmd_save_warn" \
        CMD_QUALITY_DIAGNOSIS="" \
        CMD_QUALITY_FAST_METADATA=1 \
        bash "$SCRIPT_DIR/cmd_quality_log.sh" "$CMD_ID" "WARN" "no" "0" "$warn_note" >/dev/null 2>&1 || true
    done
}

log_cmd_save_pass() {
    local timestamp
    [[ -n "$CMD_ID" ]] || return 0
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    (
        flock -w 10 200 || exit 0

        if [[ ! -f "$QUALITY_LOG_FILE" ]] || [[ ! -s "$QUALITY_LOG_FILE" ]]; then
            printf 'entries:\n' > "$QUALITY_LOG_FILE"
        else
            local first_line
            IFS= read -r first_line < "$QUALITY_LOG_FILE" || first_line=""
            if [[ "$first_line" == "entries: []" ]]; then
                sed -i '1s/^entries: \[\]$/entries:/' "$QUALITY_LOG_FILE"
            fi
        fi

        local entry_indent field_indent
        entry_indent="$(awk '
            /^entries:[[:space:]]*$/ { in_entries=1; next }
            in_entries && /^[[:space:]]*-/ {
                match($0, /^[[:space:]]*/)
                print substr($0, RSTART, RLENGTH)
                exit
            }
        ' "$QUALITY_LOG_FILE")"
        field_indent="${entry_indent}  "

        cat >> "$QUALITY_LOG_FILE" <<EOF
${entry_indent}- cmd_id: "$CMD_ID"
${field_indent}ac_count: 0
${field_indent}gate_result: "PASS"
${field_indent}karo_rework: "no"
${field_indent}gunshi_verdict: "unknown"
${field_indent}ninja_blockers: 0
${field_indent}supplementary_cmds: 0
${field_indent}source: "cmd_save"
${field_indent}timestamp: "$timestamp"
EOF
    ) 200>/tmp/cmd_design_quality.lock
}

count_same_warn_pattern() {
    local warn_pattern="${1:-}"
    [[ -n "$warn_pattern" && -f "$QUALITY_LOG_FILE" ]] || {
        echo 0
        return 0
    }
    CMD_SAVE_CMD_ID="$CMD_ID" \
    CMD_SAVE_QUALITY_LOG="$QUALITY_LOG_FILE" \
    CMD_SAVE_WARN_PATTERN="$warn_pattern" \
    CMD_SAVE_SHOGUN_LESSONS_FILE="$CMD_SAVE_SHOGUN_LESSONS_FILE" \
    python3 - <<'PY'
import os
import re
import yaml

cmd_id = os.environ.get("CMD_SAVE_CMD_ID", "")
log_path = os.environ.get("CMD_SAVE_QUALITY_LOG", "")
warn_pattern = os.environ.get("CMD_SAVE_WARN_PATTERN", "").strip()
lessons_path = os.environ.get("CMD_SAVE_SHOGUN_LESSONS_FILE", "")

if not cmd_id or not warn_pattern or not log_path or not os.path.exists(log_path):
    print(0)
    raise SystemExit(0)

resolved_source_cmds = set()
if lessons_path and os.path.exists(lessons_path):
    with open(lessons_path, encoding="utf-8") as fh:
        for line in fh:
            match = re.match(r'^\s*source_cmd:\s*["\']?([^"\']+)["\']?\s*$', line)
            if match:
                resolved_source_cmds.add(match.group(1).strip())

with open(log_path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

entries = (data.get("entries") or []) if isinstance(data, dict) else []
count = sum(
    1
    for entry in entries
    if isinstance(entry, dict)
    and entry.get("source") == "cmd_save_warn"
    and entry.get("gate_result") == "WARN"
    and (
        lambda note: (
            (note.split("|", 1)[0].strip() == warn_pattern or warn_pattern in note)
            and "[resolved:" not in note
            and not entry.get("resolved_by")
            and not (
                note.split("|", 1)[0].strip() == "missing_prev_cmd_lesson"
                and any(
                    part.startswith("source_cmd=")
                    and part.split("=", 1)[1].strip() in resolved_source_cmds
                    for part in note.split("|")[1:]
                )
            )
        )
    )(str(entry.get("notes", "") or "").strip())
)
print(count)
PY
}

count_cmd_save_blocks_for_cmd() {
    local target_cmd_id="${1:-}"
    [[ -n "$target_cmd_id" && -f "$QUALITY_LOG_FILE" ]] || {
        echo 0
        return 0
    }

    CMD_SAVE_TARGET_CMD_ID="$target_cmd_id" \
    CMD_SAVE_QUALITY_LOG="$QUALITY_LOG_FILE" \
    python3 - <<'PY'
import os
import yaml

cmd_id = os.environ.get("CMD_SAVE_TARGET_CMD_ID", "")
log_path = os.environ.get("CMD_SAVE_QUALITY_LOG", "")

if not cmd_id or not log_path or not os.path.exists(log_path):
    print(0)
    raise SystemExit(0)

with open(log_path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

entries = (data.get("entries") or []) if isinstance(data, dict) else []
count = sum(
    1
    for entry in entries
    if isinstance(entry, dict)
    and entry.get("cmd_id") == cmd_id
    and entry.get("gate_result") == "BLOCK"
    and entry.get("source") == "cmd_save"
)
print(count)
PY
}

cmd_save_shogun_lesson_exists_for_cmd() {
    local source_cmd_id="${1:-}"
    [[ -n "$source_cmd_id" ]] || return 1

    if [[ -f "$CMD_SAVE_SHOGUN_LESSON_ACK_FILE" ]] && grep -qE "^[[:space:]]*-[[:space:]]+cmd_id:[[:space:]]*['\"]?${source_cmd_id}['\"]?" "$CMD_SAVE_SHOGUN_LESSON_ACK_FILE" 2>/dev/null; then
        return 0
    fi

    [[ -f "$CMD_SAVE_SHOGUN_LESSONS_FILE" ]] || return 1

    # v1形式: source_cmd: cmd_XXXX
    if grep -qE "^[[:space:]]+source_cmd:[[:space:]]*['\"]?${source_cmd_id}['\"]?" "$CMD_SAVE_SHOGUN_LESSONS_FILE" 2>/dev/null; then
        return 0
    fi
    # v2形式: source_cmdがなくても、detail/enforcement等でcmd_idに言及されていれば記録済みとみなす
    if grep -qF "${source_cmd_id}" "$CMD_SAVE_SHOGUN_LESSONS_FILE" 2>/dev/null; then
        return 0
    fi

    return 1
}

warn_missing_prev_cmd_lesson() {
    [[ -f "$CMD_SAVE_LAST_CMD_FILE" ]] || return 0

    local prev_cmd_id prev_block_count warn_msg
    prev_cmd_id="$(tr -d '[:space:]' < "$CMD_SAVE_LAST_CMD_FILE" 2>/dev/null || true)"
    [[ -n "$prev_cmd_id" && "$prev_cmd_id" != "$CMD_ID" ]] || return 0

    prev_block_count="$(count_cmd_save_blocks_for_cmd "$prev_cmd_id")"
    [[ "$prev_block_count" =~ ^[0-9]+$ ]] || prev_block_count=0
    (( prev_block_count > 0 )) || return 0

    cmd_save_shogun_lesson_exists_for_cmd "$prev_cmd_id" && return 0

    warn_msg="前${prev_cmd_id}で${prev_block_count}回BLOCKされたが教訓未記録。lesson_write_shogun.shで記録せよ。既知パターンなら: bash scripts/shogun_lesson_ack.sh ${prev_cmd_id} LS-A05"
    record_block_reason "$warn_msg"
}

remind_missing_current_cmd_lesson_after_clear() {
    local current_block_count remind_msg
    current_block_count="$(count_cmd_save_blocks_for_cmd "$CMD_ID")"
    [[ "$current_block_count" =~ ^[0-9]+$ ]] || current_block_count=0
    (( current_block_count > 0 )) || return 0

    cmd_save_shogun_lesson_exists_for_cmd "$CMD_ID" && return 0

    remind_msg="${CMD_ID}で${current_block_count}回BLOCKされたが教訓未記録。lesson_write_shogun.shで記録せよ。既知パターンなら: bash scripts/shogun_lesson_ack.sh ${CMD_ID} LS-A05"
    echo "REMIND: ${remind_msg}" >&2
    echo "REMIND: 環境埋込み判定: 同じBLOCKを既存hookテンプレート注入で防止可能か、gate修正が必要かを判定せよ。" >&2
}

handle_cmd_save_exit() {
    local status=$?
    trap - EXIT

    if [[ "$status" -ne 0 ]]; then
        local block_reason same_reason_count
        block_reason="$(extract_last_block_reason)"

        if [[ -n "$block_reason" ]]; then
            if [[ -n "$CMD_DIAGNOSIS" ]]; then
                echo "診断: $CMD_DIAGNOSIS" >&2
            fi

            echo "★ 診断せよ: なぜこのBLOCKが起きたか？根本原因を1行で書け。" >&2
            echo '★ 修正前に: quality_gateに diagnosis: "根本原因の1行記述" を追加してから再実行せよ。' >&2

            # --- resolution_hint: BLOCK理由に対応する解消手順を自動表示 ---
            # 軍師提案(A): 行動コストを下げて同じBLOCKの繰り返しを防ぐ
            case "$block_reason" in
                *"ファイルパスが存在しません"*|*"親ディレクトリも不在"*)
                    echo "★ 解消: ls でパスを確認。見つからなければ grep -rn 'ファイル名' で検索せよ。" >&2 ;;
                *"必須項目"*"未記入"*)
                    echo "★ 解消: quality_gate: に q1_firefighting/q2_learning/q3_next_quality を追加。各1行で理由を書け。" >&2 ;;
                *"q9_firefighting_root_cause"*)
                    echo "★ 解消: q9_firefighting_root_cause: \"真因: ... 再発防止: ...\" を追加せよ。" >&2 ;;
                *"q5="*"code_reading"*)
                    echo "★ 解消: q5を isolated_test/structure_verified/production_verified に昇格。確認した証拠を1行追記。" >&2 ;;
                *"未検証前提"*|*"trust:unverified"*)
                    echo "★ 解消: assumptions内のtrust:unverifiedをtrust:verifiedに変更。確認手段(コマンド/ファイル)を明記。" >&2 ;;
                *"既に委任済み"*)
                    echo "★ 解消: cmd_idが重複。新しいcmd_idで起票し直せ。" >&2 ;;
                *"WARN累計昇格"*)
                    echo "★ 解消: 繰り返しWARNの根因を修正せよ。偽陽性ならgateのチェック条件を修正。" >&2 ;;
            esac

            same_reason_count="$(count_same_reason_prior_blocks "$block_reason" | tr -d '[:space:]')"
            [[ "$same_reason_count" =~ ^[0-9]+$ ]] || same_reason_count=0
            if (( same_reason_count >= 1 )); then
                echo "★ DIVERGENT: 同じチェック($block_reason)で2回連続BLOCK。" >&2
                echo "  根本的に異なるアプローチを検討せよ。" >&2
            fi

            log_cmd_save_block "$block_reason"
        fi
    fi

    rm -f "$CMD_SAVE_STDERR_LOG"
    exit "$status"
}

trap 'handle_cmd_save_exit' EXIT

# --- Usage ---
if [[ $# -lt 1 ]]; then
    echo "Usage: bash scripts/cmd_save.sh <cmd_id>" >&2
    echo "  cmd_id: 数字のみ（例: 1148）またはcmd_付き（例: cmd_1148）" >&2
    exit 1
fi

# --- cmd_id正規化（cmd_プレフィックスを付与） ---
RAW_ID="$1"
if [[ "$RAW_ID" =~ ^cmd_ ]]; then
    CMD_ID="$RAW_ID"
else
    CMD_ID="cmd_${RAW_ID}"
fi

WARN_COUNT=0
CMD_BLOCK=""
CMD_BLOCK_NC=""

if [[ "${CMD_SAVE_PREV_LESSON_FAST:-0}" = "1" ]]; then
    if [[ ! -f "$QUEUE_FILE" ]]; then
        echo "WARN: $QUEUE_FILE が存在しません" >&2
        record_warn_reason "queue_file_missing" "check=session_state_queue_file_presence"
    elif load_cmd_block; then
        CMD_DIAGNOSIS="$(extract_cmd_diagnosis "$CMD_BLOCK_NC")"
        warn_missing_prev_cmd_lesson
    else
        echo "WARN: ${CMD_ID} のブロックが $QUEUE_FILE に見つかりません" >&2
        record_warn_reason "cmd_block_missing" "check=session_state_cmd_block_presence"
    fi

    if [[ "$BLOCK_COUNT" -eq 0 && "$WARN_COUNT" -eq 0 ]]; then
        echo "保存確認OK: ${CMD_ID}"
        echo "$CMD_ID" > "$CMD_SAVE_LAST_CMD_FILE"
        remind_missing_current_cmd_lesson_after_clear
        rm -f "$CMD_SAVE_STDERR_LOG"
        trap - EXIT
        exit 0
    fi

    if [[ "$BLOCK_COUNT" -gt 0 && ${#BLOCK_REASONS[@]} -gt 0 ]]; then
        log_cmd_save_block "${BLOCK_REASONS[-1]}"
    fi
    echo "保存確認NG: ${CMD_ID} (${BLOCK_COUNT}件のBLOCK, ${WARN_COUNT}件のWARN)" >&2
    rm -f "$CMD_SAVE_STDERR_LOG"
    trap - EXIT
    exit 1
fi

# --- Check 0.9: YAML構文検証 ---
if [[ -f "$QUEUE_FILE" ]] && ! python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$QUEUE_FILE" 2>/dev/null; then
    echo "BLOCK: $QUEUE_FILE にYAML構文エラーがあります。ダブルクォート内の特殊文字(|等)をエスケープするか、ブロックスカラー(|)を使用してください" >&2
    BLOCK_REASONS+=("yaml_syntax_error")
fi

# --- Check 1: cmdブロック存在確認 ---
if [[ ! -f "$QUEUE_FILE" ]]; then
    echo "WARN: $QUEUE_FILE が存在しません" >&2
    record_warn_reason "queue_file_missing" "check=session_state_queue_file_presence"
elif ! load_cmd_block; then
    echo "WARN: ${CMD_ID} のブロックが $QUEUE_FILE に見つかりません" >&2
    record_warn_reason "cmd_block_missing" "check=session_state_cmd_block_presence"
fi

# --- Check 1.5: 委任済みcmd再保存BLOCK ---
# cmd_1688事故: 将軍が委任済みcmdを3回上書き→忍者フリーズ→殿指摘
# delegated_at存在 = 既に家老に委任済み。再保存は設計変更を意味する。
# CLAUDE.mdルール: 途中修正の二択(別CMD or 神速停止→再CMD)。inbox_writeで途中修正するな
if load_cmd_block; then
    _DELEGATED_AT="$(cmd_block_get_field "delegated_at")"
    if [[ -n "$_DELEGATED_AT" ]]; then
        record_block_reason "${CMD_ID} は既に委任済みです。"
        echo "  delegated_at: $_DELEGATED_AT" >&2
        echo "  途中修正の二択: (1)別CMD_IDで発令 (2)忍者を神速停止→回復後に新CMD" >&2
        echo "  同一cmd_idの上書きは忍者のフリーズ・成果物無効化を引き起こします(cmd_1688実証済み)" >&2
        abort_if_block_immediate || exit 1
    fi
fi

# --- Check 1.6: 前回PASS済みcmd pending昇格チェック ---
# 原理: 将軍が一括起票すると前回cmdが家老に委任されないまま次のcmdを保存できてしまう
# 1cmd毎ゲート強制=呼出し方100億パターンに対応する原理的解決(cmd_2158)
if [[ -f "$CMD_SAVE_LAST_CMD_FILE" ]]; then
    _PREV_CMD_ID=$(cat "$CMD_SAVE_LAST_CMD_FILE" 2>/dev/null || true)
    if [[ -n "$_PREV_CMD_ID" && "$_PREV_CMD_ID" != "$CMD_ID" ]]; then
        _PREV_STATUS=$(awk -v cmd_id="$_PREV_CMD_ID" '
            $0 == "  " cmd_id ":" { found=1; next }
            found && /^  cmd_[^:]+:/ { exit }
            found && /^[[:space:]]+status:[[:space:]]/ {
                gsub(/^[[:space:]]+status:[[:space:]]*/, "")
                gsub(/"/, "")
                print; exit
            }
        ' "$QUEUE_FILE" 2>/dev/null || true)
        if [[ "$_PREV_STATUS" == "pending" ]]; then
            record_block_reason "前回PASS済み ${_PREV_CMD_ID} がまだ pending のまま。家老に委任(delegated昇格)されてから次のcmdを保存せよ"
            abort_if_block_immediate || exit 1
        fi
    fi
fi

# --- Check 2: 重複チェック（アーカイブ済みcmd_idとの衝突） ---
if [[ -d "$ARCHIVE_CMD_DIR" ]]; then
    # パターン: cmd_XXXX_completed_YYYYMMDD.yaml
    if ls "$ARCHIVE_CMD_DIR"/"${CMD_ID}"_completed_*.yaml 1>/dev/null 2>&1; then
        echo "WARN: ${CMD_ID} は既にアーカイブ済みです（重複の可能性）" >&2
        record_warn_reason "archive_duplicate" "check=check_archive_duplicate"
    fi
fi

# --- Check 2.5: 同時draft複数BLOCK（LS088: 1CMD1ゲート。一括起票禁止） ---
OTHER_DRAFTS=$(awk -v current="$CMD_ID" '
    /^  cmd_[^:]+:/ { id = $1; sub(/:$/, "", id); sub(/^  /, "", id); next }
    id && id != current && /status:.*draft/ { print id }
' "$QUEUE_FILE" 2>/dev/null)
if [[ -n "$OTHER_DRAFTS" ]]; then
    printf 'BLOCK\tother_draft_exists: %s もdraft状態。1本ずつゲートを通せ(LS088)\n' "$(echo "$OTHER_DRAFTS" | tr '\n' ',')" >&2
    record_block_reason "other_draft_exists"
fi

# --- Session State: 同一cmdの過去BLOCK履歴を表示 ---
if load_cmd_block; then
    CMD_DIAGNOSIS="$(extract_cmd_diagnosis "$CMD_BLOCK_NC")"
    show_prior_attempts
    warn_missing_prev_cmd_lesson
fi

# --- Check 3.5: diagnosis質検査（cmd_2159） ---
# 目的: diagnosisが記入されている場合、「BLOCK理由:」「対策:」の2部構成を強制
# 低品質diagnosisを再BLOCKすることで診断内容の質を担保する
if [[ -n "$CMD_DIAGNOSIS" ]]; then
    _DIAG_HAS_BLOCK_REASON=0
    _DIAG_HAS_TAISAKU=0
    if echo "$CMD_DIAGNOSIS" | grep -q "BLOCK理由:"; then _DIAG_HAS_BLOCK_REASON=1; fi
    if echo "$CMD_DIAGNOSIS" | grep -q "対策:"; then _DIAG_HAS_TAISAKU=1; fi
    if [[ "$_DIAG_HAS_BLOCK_REASON" -eq 0 || "$_DIAG_HAS_TAISAKU" -eq 0 ]]; then
        record_block_reason "diagnosisの形式不正。「BLOCK理由: ... 対策: ...」の2部構成で記載せよ"
        echo '  例: diagnosis: "BLOCK理由: q8にWHYが未記入 対策: q8に殿の指示引用を追加"' >&2
        abort_if_block_immediate || exit 1
    fi
fi

# --- Check 3.6: environment_change強制（cmd_2160, 殿指摘2026-04-20拡張） ---
# 目的: BLOCK/WARN後に「環境に何を埋め込んだか」を強制。免疫系の抗体生成フェーズ。
# 軍師原理(blt_20260420_021639): 「BLOCKの度に環境が1つ強くなるまで、次を許すな。」
# 殿指摘: WARNもスルーするな。WARNされたら次のCMDでBLOCKされないように成長せよ。
# 条件: PRIOR_ATTEMPT_COUNT > 0 = 過去にBLOCKされた実績がある
# ★ WARN_COUNT > 0 のケースは全チェック完了後(L2594付近)で処理(WARNは後段で蓄積されるため)
if (( PRIOR_ATTEMPT_COUNT > 0 )); then
    _ENV_STRUCTURED=""
    _ENV_TYPE=""
    _ENV_FILE=""
    _ENV_PATTERN=""
    _ENV_FILE_RESOLVED=""
    _ENV_CHANGE="$(echo "$CMD_BLOCK_NC" | awk '/environment_change:/{found=1; sub(/.*environment_change:[[:space:]]*"?/,""); sub(/"?[[:space:]]*$/,""); print; exit} END{if(!found) print ""}')"
    if [[ -z "$_ENV_CHANGE" ]]; then
        record_block_reason "environment_change未記入。BLOCKから何を環境に埋め込んだかを記載せよ(gate/lesson/hook/PI等)"
        echo '  例: environment_change: "gate_X追加(scripts/cmd_save.sh L576)+lesson_Y追加(lessons_karo.yaml)"' >&2
        abort_if_block_immediate || exit 1
    fi
    # 禁止値チェック: 意志依存の低品質回答をBLOCK（AC2: cmd_2160）
    _ENV_VAGUE_PATTERN="^(修正した|対策済み|対応済み|対策した|直した|変更した|更新した|改善した|実施した|対処した|完了|なし|none|N/A|初回起票|初回|該当なし|なし.*初回|対策:.*初回)$"
    if echo "$_ENV_CHANGE" | grep -qE "$_ENV_VAGUE_PATTERN"; then
        record_block_reason "environment_changeが低品質。環境変化の具体的diffを記載せよ(gate追加/lesson登録/hook変更等)"
        echo '  禁止値: 修正した/対策済み/対策した/直した/変更した/更新した/改善した/実施した/対処した/完了/なし' >&2
        abort_if_block_immediate || exit 1
    fi

    if _ENV_STRUCTURED="$(parse_structured_environment_change "$_ENV_CHANGE" 2>/dev/null)"; then
        IFS=$'\t' read -r _ENV_TYPE _ENV_FILE _ENV_PATTERN <<< "$_ENV_STRUCTURED"
        _ENV_FILE_RESOLVED="$_ENV_FILE"
        if [[ "$_ENV_FILE_RESOLVED" != /* ]]; then
            _ENV_FILE_RESOLVED="$PROJECT_DIR/$_ENV_FILE_RESOLVED"
        fi

        if ! grep -qE -- "$_ENV_PATTERN" "$_ENV_FILE_RESOLVED"; then
            record_block_reason "environment_change未実装。file=${_ENV_FILE} に pattern=${_ENV_PATTERN} が見つからない"
            echo "  structured environment_change: type=${_ENV_TYPE} file=${_ENV_FILE} pattern=${_ENV_PATTERN}" >&2
            echo "  実装してからcmd_save.shを再実行せよ" >&2
            abort_if_block_immediate || exit 1
        fi
    else
        # 非構造化テキスト = 実装検証不能 = 意志依存 = 成長しない(deepdive Phase 5)
        # 構造化形式を強制: type=xxx; file=xxx; pattern=xxx
        record_block_reason "environment_changeが非構造化。構造化形式で記載せよ: type=gate|lesson|hook; file=対象ファイルパス; pattern=grepで検証可能な文字列"
        echo '  例: environment_change: "type=gate; file=scripts/cmd_save.sh; pattern=WARN_COUNT"' >&2
        echo '  注意: YAML list形式(- type: ...)は非対応。必ず1行テキストで書け' >&2
        echo '  理由: 自由テキストは実装を検証できない。構造化形式なら自動grepで実在を証明する' >&2
        abort_if_block_immediate || exit 1
    fi
fi

# --- Check 3: quality_gateフィールド検査 ---
# cmdブロック内にquality_gate（q1_firefighting, q2_learning, q3_next_quality）があるか検査
if load_cmd_block; then
    load_cmd_block_cache || true

    if ! cmd_block_has_field "quality_gate"; then
        record_block_reason "quality_gate未記入。3問に答えてからcmd_save.shを実行せよ"
        cat >&2 <<'QG_TEMPLATE'
---
quality_gate:
  q1_firefighting: "no/yes — 理由"
  q2_learning: "奪わない/奪う — 学習機会への影響"
  q3_next_quality: "上がる/下がる — 品質への影響"
---
QG_TEMPLATE
        abort_if_block_immediate || exit 1
    fi

    # --- Preflight: 全必須項目の存在を一括チェック（逐次BLOCK防止） ---
    # 起源: cmd_1951で7回連続BLOCK。1項目ずつexit 1するため全項目埋めるのに7往復
    # 修正: 全必須項目を一括チェックし、全ての不足を1回で表示してexit 1
    MISSING_KEYS=()
    MISSING_HINTS=()

    for _QG_KEY in q1_firefighting q2_learning q3_next_quality; do
        if ! cmd_block_has_field "quality_gate.${_QG_KEY}"; then
            MISSING_KEYS+=("$_QG_KEY")
            case "$_QG_KEY" in
                q1_firefighting)  MISSING_HINTS+=('  q1_firefighting: "no/yes — 理由"') ;;
                q2_learning)      MISSING_HINTS+=('  q2_learning: "奪わない/奪う — 学習機会への影響"') ;;
                q3_next_quality)  MISSING_HINTS+=('  q3_next_quality: "上がる/下がる — 品質への影響"') ;;
            esac
        fi
    done

    if ! cmd_block_has_field "quality_gate.q5_verified_source"; then
        MISSING_KEYS+=("q5_verified_source")
        MISSING_HINTS+=('  q5_verified_source: "structure_verified — 確認方法と対象を記載"')
    fi

    if ! cmd_block_has_field "quality_gate.q8_why_what"; then
        MISSING_KEYS+=("q8_why_what")
        MISSING_HINTS+=('  q8_why_what: "WHY: 殿指示「...」 → WHAT: ...=正の複利(...)"')
    fi

    if ! cmd_block_has_field "quality_gate.q11_not_already_done"; then
        MISSING_KEYS+=("q11_not_already_done")
        MISSING_HINTS+=('  q11_not_already_done: "未達成。確認方法と結果を記載"')
    fi

    # q7: dm-signal impl のみBLOCK
    _PF_PROJECT="$(cmd_block_get_field "project")"
    _PF_TASK_TYPE="$(cmd_block_get_field "task_type")"
    if [[ "${_PF_PROJECT:-}" == "dm-signal" && "${_PF_TASK_TYPE:-}" == "impl" ]]; then
        if ! cmd_block_has_field "quality_gate.q7_definition_verified"; then
            MISSING_KEYS+=("q7_definition_verified")
            MISSING_HINTS+=('  q7_definition_verified: "yes — 定義を一次情報で照合した事実"')
        fi
    fi

    # assumptions: 全cmdで必須（cmd_2157: AC≥3→全cmdに拡大）
    if ! cmd_block_has_field "assumptions" && ! cmd_block_has_field "quality_gate.assumptions"; then
        MISSING_KEYS+=("assumptions")
        MISSING_HINTS+=('  assumptions: [{claim: "...", source: "...", trust: "verified"}]')
    fi

    if [[ ${#MISSING_KEYS[@]} -gt 0 ]]; then
        record_block_reason "必須項目 ${#MISSING_KEYS[@]}件 未記入。全て記入してからcmd_save.shを再実行せよ"
        echo "  未記入: ${MISSING_KEYS[*]}" >&2
        echo "  ---" >&2
        for _hint in "${MISSING_HINTS[@]}"; do
            echo "$_hint" >&2
        done
        echo "  ---" >&2
        abort_if_block_immediate || exit 1
    fi

    # depends_on: cmd間依存の暗黙化を入口で可視化（WARN導入 cmd_2627）
    check_depends_on_field

    # q4_depth: WARN_COUNTに加算（段階的導入→本格化 2026-04-21殿裁定）
    if ! cmd_block_has_field "quality_gate.q4_depth"; then
        echo "WARNING: q4_depth未記入。深堀り度を記入せよ: q4_depth: \"shallow/medium/deep — 理由\"" >&2
        record_warn_reason "q4_depth未記入" "check=quality_gate_q4_depth"
    else
        # q4_depth値チェック: deep/mediumは時間コスト大。概算表示で確認を促す（WARN_COUNTに加算しない）
        _Q4_VAL="$(cmd_block_get_field "quality_gate.q4_depth")"
        if echo "$_Q4_VAL" | grep -qiE '\b(deep|medium)\b'; then
            if echo "$_Q4_VAL" | grep -qiE '\bdeep\b'; then
                echo "WARNING: q4_depth=deep/medium — 時間コスト概算: 30-60分(全忍者投入)。時間は最も高価な資源。分割・並列化を検討せよ" >&2
            else
                echo "WARNING: q4_depth=deep/medium — 時間コスト概算: 15-30分(2-3忍者)。分割で時間短縮を検討せよ" >&2
            fi
        fi
    fi

    # LG022 gate: 研究cmdにbaseline無し→WARN
    _LG022_TYPE="$(cmd_block_get_field "type")"
    if echo "$_LG022_TYPE" | grep -qiE 'research|analysis|investigation'; then
        _LG022_TEXT="$(cmd_block_raw)"
        if ! echo "$_LG022_TEXT" | grep -qiE 'baseline|比較対象|before.*after|対照'; then
            echo "WARNING(LG022): type=research系cmdにbaseline/比較対象がありません。改善主張には比較対象が必須" >&2
            record_warn_reason "研究cmdにbaseline無し(LG022)" "check=research_baseline"
        fi
    fi

    # q5_verified_source: 存在チェックはpreflight済み。以下は内容検証のみ
    # q5検証レベル分類（cmd_1692: code_readingのみはBLOCK）
    # cmd_1481教訓: code_readingをproduction_verifiedに見せかけた。忍者に信頼度を正直に伝える(利他)
    # cmd_1692: code_readingのみでは前提未検証のためBLOCK。追加検証(isolated_test等)があれば通過
    # 除外条件: scope_mode=SCOUT OR scout_exempt=true（偵察cmdは実行前確認が目的のためcode_readingでも可）
    # infraの道具磨き(cmd_1891): q4_depth=shallow は軽微変更のためINFOに留める
    _q5_scope_mode="$(cmd_block_get_field "scope_mode")"
    _q5_scout_exempt="$(cmd_block_get_field "scout_exempt")"
    _q5_project="$(cmd_block_get_field "project")"
    _q5_depth="$(cmd_block_get_field "quality_gate.q4_depth")"
    q5_val="$(cmd_block_get_field "quality_gate.q5_verified_source")"
    if [[ -n "$q5_val" ]] && echo "$q5_val" | grep -qiE "code_reading|コード読み|読んだだけ"; then
        if [[ "${_q5_scope_mode:-}" == "SCOUT" || "${_q5_scout_exempt:-}" == "true" ]]; then
            echo "INFO: q5=code_reading。scope_mode=SCOUTまたはscout_exempt=trueのため除外。OK" >&2
        elif [[ "${_q5_project:-}" == "infra" && "${_q5_depth:-}" == "shallow" ]]; then
            echo "INFO: q5=code_reading。project=infra かつ q4_depth=shallow のためINFO扱い。OK" >&2
        elif ! echo "$q5_val" | grep -qiE "isolated_test|structure_verified|production_verified|pipeline_test|実行|execute|本番|production|API応答|DB確認|テスト実行"; then
            record_block_reason "q5=code_readingのみ。コード読みだけでは前提未検証。isolated_test/structure_verified/production_verifiedのいずれかで実確認せよ"
            echo '  例: q5_verified_source: "engine.py L107 code_reading + isolated_test(スクリプト実行確認)"' >&2
            abort_if_block_immediate || exit 1
        else
            echo "INFO: q5にcode_readingを含むが追加検証あり。OK" >&2
        fi
    elif [[ -n "$q5_val" ]] && ! echo "$q5_val" | grep -qiE "実行|execute|pipeline|本番|production|API応答|DB確認|テスト実行|structure_verified|isolated_test|production_verified|pipeline_test"; then
        echo "WARNING: q5に検証方法が不明確。レベル明記推奨: code_reading(コード読み) / isolated_test(単体実行) / pipeline_test(結合実行) / production_verified(本番確認)" >&2
    fi

    # q6_not_hiding: SG8自動消火チェック（WARN_COUNTに加算 2026-04-21殿裁定）
    # 目的: 表面的対処で根源的問題を隠し改革動機を殺すcmdを防止
    # 起源: cmd_1278事件 — lessons.yaml読込削除が7,552行の構造問題を隠蔽
    if ! cmd_block_has_field "quality_gate.q6_not_hiding"; then
        echo "WARNING: q6_not_hiding未記入。「この変更は根源的問題を隠さないか？表面的対処で改革動機を殺さないか？」" >&2
        echo '  例: q6_not_hiding: "no — Vercel化は構造改革であり表面的対処ではない"' >&2
        record_warn_reason "q6_not_hiding未記入" "check=quality_gate_q6_not_hiding"
    fi

    # q7_definition_verified: cmd内定義の一次情報照合明示
    # 起源: L542 — High/Low等の研究用語は実装とテストに同じ意味を固定しないと結論がずれる
    # 目的: cmd固有定義を一次情報に照合した事実をquality_gateに明示させる
    # dm-signal impl cmd → BLOCK昇格（cmd_1903）。infra/他PJ・scout/reconはWARNING維持
    _Q7_PROJECT="$(cmd_block_get_field "project")"
    _Q7_TASK_TYPE="$(cmd_block_get_field "task_type")"
    # q7: dm-signal impl BLOCKはpreflight済み。それ以外はWARNING
    if ! cmd_block_has_field "quality_gate.q7_definition_verified"; then
        if [[ "${_Q7_PROJECT:-}" != "dm-signal" || "${_Q7_TASK_TYPE:-}" != "impl" ]]; then
            echo "WARNING: q7_definition_verified未記入。High/Lowなどcmd固有定義を一次情報へ照合したか記載推奨" >&2
            echo '  例: q7_definition_verified: "yes — High=rolling max。trade-rule/テスト期待値に定義を固定"' >&2
            record_warn_reason "q7_definition_verified未記入" "check=quality_gate_q7_definition_verified"
        fi
    fi

    # q8_why_what: 存在チェックはpreflight済み。以下は内容検証のみ
    if cmd_block_has_field "quality_gate.q8_why_what"; then
        # WHAT部分の縮小表現検出（WARN — AC2）
        _Q8_WW_VAL="$(cmd_block_get_field "quality_gate.q8_why_what")"
        _Q8_WHAT_PART="${_Q8_WW_VAL#*WHAT:}"
        if echo "$_Q8_WHAT_PART" | grep -qE 'のみ|だけ|一部|代表'; then
            echo "WARN: q8_why_whatのWHATに縮小表現を検出。全量やることを確認せよ" >&2
            echo "  → のみ/だけ/一部/代表 は範囲縮小のシグナル(殿厳命 2026-04-04)" >&2
            record_warn_reason "q8_縮小表現" "check=quality_gate_q8_scope_expression"
        fi
        # COMPOUND(複利の問い)検査（WARN — 2026-04-15 殿指摘「将軍に因果をたどる仕組みを」）
        # 起源: 軍師のcausal_chain+複利の問いが因果思考を強制。将軍にはなかった
        # 方法: q8に「正の複利」or「負の複利」or「複利」が含まれるか検査
        if ! echo "$_Q8_WW_VAL" | grep -qE '複利|compound'; then
            echo "WARN: q8に複利の問いがありません。「この実装選択を10回繰り返したら正の複利か負の複利か」を追記せよ" >&2
            echo '  例: q8_why_what: "WHY: 殿指摘「浅い」 WHAT: lessons_shogun.yaml作成=正の複利(毎セッション具体化)"' >&2
            record_warn_reason "q8_複利の問い" "check=quality_gate_q8_compound_question"
        fi
        # WHY/WHATだけではループが回らない。WHEN(いつ発動)とHOW(どう機能)も明示させる。
        if ! echo "$_Q8_WW_VAL" | grep -qiE '(^|[^A-Za-z])WHEN[[:space:]]*[：:]' || ! echo "$_Q8_WW_VAL" | grep -qiE '(^|[^A-Za-z])HOW[[:space:]]*[：:]'; then
            echo "WARN: q8_why_whatにWHEN/HOWが不足しています。WHY/WHAT/WHEN/HOWを最低限そろえよ" >&2
            echo '  例: q8_why_what: "WHY: 殿原則「...」 → WHAT: ... → WHEN: ... → HOW: ...。複利: 正の複利"' >&2
            record_warn_reason "q8_WHEN/HOW不足" "check=quality_gate_q8_when_how"
        fi
        # 5W1H: WHERE(どこで)とWHO(誰が/誰に)も明示させる（殿指摘2026-05-10）
        if ! echo "$_Q8_WW_VAL" | grep -qiE '(^|[^A-Za-z])WHERE[[:space:]]*[：:]' || ! echo "$_Q8_WW_VAL" | grep -qiE '(^|[^A-Za-z])WHO[[:space:]]*[：:]'; then
            echo "WARN: q8_why_whatにWHERE/WHOが不足しています。5W1H(WHY/WHAT/WHEN/WHERE/WHO/HOW)をそろえよ" >&2
            echo '  例: q8_why_what: "WHY: ... WHAT: ... WHEN: ... WHERE: scripts/cmd_save.sh WHO: 将軍 HOW: ..."' >&2
            record_warn_reason "q8_WHERE/WHO不足" "check=quality_gate_q8_where_who"
        fi
        check_lord_instruction_ac_alignment_info "$_Q8_WW_VAL" "$(extract_acceptance_criteria_block)"
        # q8 WHY引用検査はcmd_2248で廃止。
        # 理由: WHYが明示されていても引用記号や特定語彙を持たないだけでWARNになる偽陽性が多かった。
    fi

    # q9_firefighting_root_cause: 消火cmdでは真因+再発防止を必須化（BLOCK — cmd_1801）
    # 起源: 消火禁止原則が理解止まりで、症状修正cmdが真因未記載のまま繰り返された
    # 対象: titleに消火キーワードが含まれるcmd（command本文は対象外 — cmd_1803）
    _Q9_SIGNAL_TEXT=$(echo "$CMD_BLOCK_NC" | awk '
        /^[[:space:]]*title:/ {
            sub(/^[[:space:]]*title:[[:space:]]*/, "")
            print
            next
        }
    ')
    # q1が「品質向上」なら消火ではない（gate修正/CoDD改善等はtitleに「修正」を含むがFP）
    _Q1_VAL="$(cmd_block_get_field "quality_gate.q1_firefighting")"
    if echo "$_Q9_SIGNAL_TEXT" | grep -qiE "$FIREFIGHTING_PATTERN" && ! echo "$_Q1_VAL" | grep -q "品質向上"; then
        if ! cmd_block_has_field "quality_gate.q9_firefighting_root_cause"; then
            record_block_reason "消火cmdなのにq9_firefighting_root_cause未記入。真因と再発防止を記載してからcmd_save.shを実行せよ"
            echo '  形式: q9_firefighting_root_cause: "root_cause: 真因1行 | prevention: 二度と起きない仕組み1行"' >&2
            abort_if_block_immediate || exit 1
        fi
        # q9の中身検証: root_cause: と prevention: の両方が含まれ非空であること（GP-176）
        # 存在チェックのみでは "q9: TBD" で通過する = 形式的コンプライアンス = 消火
        _Q9_VAL="$(cmd_block_get_field "quality_gate.q9_firefighting_root_cause")"
        if [[ -n "$_Q9_VAL" ]] && ! echo "$_Q9_VAL" | grep -q "root_cause:"; then
            record_block_reason "q9にroot_cause:が含まれていない。真因を具体的に記載せよ"
            echo '  形式: q9_firefighting_root_cause: "root_cause: 真因1行 | prevention: 二度と起きない仕組み1行"' >&2
            abort_if_block_immediate || exit 1
        fi
        if [[ -n "$_Q9_VAL" ]] && ! echo "$_Q9_VAL" | grep -q "prevention:"; then
            record_block_reason "q9にprevention:が含まれていない。二度と起きない仕組みを記載せよ"
            echo '  形式: q9_firefighting_root_cause: "root_cause: 真因1行 | prevention: 二度と起きない仕組み1行"' >&2
            abort_if_block_immediate || exit 1
        fi
        _Q9_ROOT=$(echo "$_Q9_VAL" | sed -E 's/.*root_cause:[[:space:]]*([^|]*).*/\1/' | sed 's/[[:space:]]*$//')
        _Q9_PREVENTION=$(echo "$_Q9_VAL" | sed -E 's/.*prevention:[[:space:]]*(.*)/\1/' | sed 's/[[:space:]]*$//')
        if [[ -n "$_Q9_VAL" && ${#_Q9_ROOT} -lt 10 ]]; then
            record_block_reason "q9のroot_causeが短すぎる。10文字以上で具体的に記載せよ"
            echo '  形式: q9_firefighting_root_cause: "root_cause: 真因1行 | prevention: 二度と起きない仕組み1行"' >&2
            abort_if_block_immediate || exit 1
        fi
        if [[ -n "$_Q9_VAL" && ${#_Q9_PREVENTION} -lt 10 ]]; then
            record_block_reason "q9のpreventionが短すぎる。10文字以上で具体的に記載せよ"
            echo '  形式: q9_firefighting_root_cause: "root_cause: 真因1行 | prevention: 二度と起きない仕組み1行"' >&2
            abort_if_block_immediate || exit 1
        fi
        if echo "$_Q9_PREVENTION" | grep -qiE '気をつけ|注意し|徹底|意識し|漏れないよう|覚えておく|次は.*ようにする'; then
            echo "WARNING: q9のpreventionが意志依存です。『気をつける/徹底する』ではなく、gate追加・自動化・チェック強制など仕組みに置き換えてください" >&2
        fi
    fi

    # (causal_chain各論パッチは削除。q5_verified_sourceに複利の問いを統合 — 2026-04-05)

    # (q8_tool_readiness各論パッチは削除。q5の複利の問いで十分 — cmd_1742 cancel 2026-04-05)

    # q10_knowledge_boundary: 検証済み空間の明示（WARN_COUNTに加算 2026-04-21殿裁定）
    # 起源: cmd_1903 — Phase 31-32の11過ちが全てgateを通過。「無知の知」がcmd起票に強制されていない
    # 目的: cmdの前提が「前Phase/前cmdの到達点(検証済み事実)」に基づいているかを明示させる
    if ! cmd_block_has_field "quality_gate.q10_knowledge_boundary"; then
        echo "WARNING: q10_knowledge_boundary未記入。cmdの前提は検証済み空間内か？前Phase/前cmdの到達点を使っているか？" >&2
        echo '  形式例: q10_knowledge_boundary: "空間内。根拠: Phase30 β調整確立 + cmd_1896結果確認済み"' >&2
        record_warn_reason "q10_knowledge_boundary未記入" "check=quality_gate_q10_knowledge_boundary"
    fi

    # q_ambiguity: 不明瞭自覚の自己申告（段階的導入 — WARNING）
    # 起源: cmd_2121 — 将軍がcmd設計時の曖昧な点を自己申告させることで定義確認を促す
    # 目的: cmdに曖昧な指示・未定義の前提がある場合、将軍に自覚と記録を促す
    if ! cmd_block_has_field "quality_gate.q_ambiguity"; then
        echo "WARNING: q_ambiguity未記入。このcmdに曖昧な指示・未定義の前提はないか？あれば明記し、なければ\"none\"と記入せよ" >&2
        echo '  形式例: q_ambiguity: "none — 全前提定義済み" or "あり: TOP-N の N が未定義 → 将軍が3と定義"' >&2
    fi

    # mizchi Red flag (1): 「自分で読み直せば同じ効果」
    # 自己申告/目視確認/自問で曖昧さや品質を担保しようとしていないかをWARNINGで可視化
    check_self_reread_red_flag

    # mizchi Red flag (4): 「複数の不明瞭点を一気に潰そう」
    # 1cmdに複数の主要対象を束ねた設計をWARNINGで可視化
    check_bundle_red_flag

    # q11_not_already_done: 存在チェックはpreflight済み。以下は自動検索のみ

    # q11自動検索: command内スクリプト名とdocs/researchの既存成果物を照合（INFO）
    # 起源: cmd_1916 — q11手動記入は嘘が書ける。自動露出で車輪の再発明を補助的に防ぐ
    _Q11_PROJECT_DIR="${PROJECT_DIR:-${PROJECT_ROOT:-.}}"
    _Q11_RESEARCH_DIR="${_Q11_PROJECT_DIR}/docs/research"
    if [[ -d "$_Q11_RESEARCH_DIR" ]]; then
        _Q11_COMMAND_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
            /^\s*command:\s*\|/ { found=1; next }
            /^\s*command:\s*[^|]/ { found=1; sub(/^\s*command:\s*/, ""); print; next }
            found && /^\s{4,}/ { print; next }
            found && /^\s*[a-zA-Z_][a-zA-Z0-9_]*:/ { exit }
        ')
        if [[ -n "${_Q11_COMMAND_SECTION:-}" ]]; then
            _Q11_TARGETS=$(
                printf '%s\n' "$_Q11_COMMAND_SECTION" \
                    | grep -oE 'scripts/[A-Za-z0-9_./-]+\.(sh|py)|[A-Za-z0-9_./-]+\.(sh|py)' \
                    | awk '
                        function basename_of(path, parts, n) {
                            n = split(path, parts, "/")
                            return parts[n]
                        }
                        {
                            item = $0
                            base = basename_of(item)
                            items[++count] = item
                            if (item ~ /\//) {
                                has_path[base] = 1
                            }
                        }
                        END {
                            for (i = 1; i <= count; i++) {
                                item = items[i]
                                base = basename_of(item)
                                if (item !~ /\// && has_path[base]) {
                                    continue
                                }
                                if (!seen[item]++) {
                                    print item
                                }
                            }
                        }
                    ' \
                    || true
            )
            if [[ -n "${_Q11_TARGETS:-}" ]]; then
                _Q11_CACHE_KEY="$(printf '%s\n%s\n' "$_Q11_RESEARCH_DIR" "$_Q11_TARGETS" | md5sum | cut -d' ' -f1)"
                _Q11_CACHE_FILE="/tmp/cmd_save_q11_${_Q11_CACHE_KEY}.cache"
                _Q11_RESEARCH_SIG="$(stat -c '%Y:%s' "$_Q11_RESEARCH_DIR" 2>/dev/null || echo '')"
                _Q11_CACHE_SIG=""
                _Q11_CACHE_BODY=""
                if [[ -f "$_Q11_CACHE_FILE" ]]; then
                    IFS= read -r _Q11_CACHE_SIG < "$_Q11_CACHE_FILE" || _Q11_CACHE_SIG=""
                    if [[ "$_Q11_CACHE_SIG" == "$_Q11_RESEARCH_SIG" ]]; then
                        _Q11_CACHE_BODY="$(tail -n +2 "$_Q11_CACHE_FILE")"
                    fi
                fi

                if [[ -n "$_Q11_CACHE_BODY" ]]; then
                    [[ -n "${_Q11_CACHE_BODY//[[:space:]]/}" ]] && {
                        echo "INFO: 関連する既存成果物を検出:" >&2
                        printf '%s\n' "$_Q11_CACHE_BODY" >&2
                    }
                else
                    _Q11_CANDIDATE_DOCS=""
                    if command -v rg >/dev/null 2>&1; then
                        _Q11_PATTERN_ARGS=()
                        while IFS= read -r _q11_target; do
                            [[ -z "$_q11_target" ]] && continue
                            _Q11_PATTERN_ARGS+=(-e "$_q11_target")
                            _q11_base="${_q11_target##*/}"
                            if [[ "$_q11_base" != "$_q11_target" ]]; then
                                _Q11_PATTERN_ARGS+=(-e "$_q11_base")
                            fi
                        done <<< "$_Q11_TARGETS"
                        _Q11_CANDIDATE_DOCS=$(rg -l -F "${_Q11_PATTERN_ARGS[@]}" "$_Q11_RESEARCH_DIR" 2>/dev/null || true)
                    else
                        _Q11_PATTERN_ARGS=()
                        while IFS= read -r _q11_target; do
                            [[ -z "$_q11_target" ]] && continue
                            _Q11_PATTERN_ARGS+=(-e "$_q11_target")
                            _q11_base="${_q11_target##*/}"
                            if [[ "$_q11_base" != "$_q11_target" ]]; then
                                _Q11_PATTERN_ARGS+=(-e "$_q11_base")
                            fi
                        done <<< "$_Q11_TARGETS"
                        _Q11_CANDIDATE_DOCS=$(grep -rl -F "${_Q11_PATTERN_ARGS[@]}" "$_Q11_RESEARCH_DIR" 2>/dev/null || true)
                    fi

                    _Q11_ANY_MATCH=false
                    _Q11_CACHE_BODY=""
                    while IFS= read -r _q11_target; do
                        [[ -z "$_q11_target" ]] && continue
                        _q11_base="${_q11_target##*/}"
                        _Q11_MATCHES=""
                        while IFS= read -r _q11_doc; do
                            [[ -z "$_q11_doc" ]] && continue
                            if [[ "$_q11_base" == "$_q11_target" ]]; then
                                grep -Fq -- "$_q11_target" "$_q11_doc" 2>/dev/null || continue
                            else
                                grep -Fq -- "$_q11_target" "$_q11_doc" 2>/dev/null \
                                    || grep -Fq -- "$_q11_base" "$_q11_doc" 2>/dev/null \
                                    || continue
                            fi
                            _Q11_MATCHES+="${_q11_doc}"$'\n'
                        done <<< "$_Q11_CANDIDATE_DOCS"
                        [[ -z "${_Q11_MATCHES:-}" ]] && continue
                        if [[ "$_Q11_ANY_MATCH" == false ]]; then
                            echo "INFO: 関連する既存成果物を検出:" >&2
                            _Q11_ANY_MATCH=true
                        fi
                        while IFS= read -r _q11_doc; do
                            [[ -z "$_q11_doc" ]] && continue
                            _q11_rel="${_q11_doc#"${_Q11_PROJECT_DIR}"/}"
                            echo "  ${_q11_target} → ${_q11_rel}" >&2
                            _Q11_CACHE_BODY+="  ${_q11_target} → ${_q11_rel}"$'\n'
                        done <<< "$_Q11_MATCHES"
                    done <<< "$_Q11_TARGETS"

                    {
                        printf '%s\n' "$_Q11_RESEARCH_SIG"
                        printf '%s' "$_Q11_CACHE_BODY"
                    } > "$_Q11_CACHE_FILE"
                fi
            fi
        fi
    fi

    _Q11_VAL="$(cmd_block_get_field "quality_gate.q11_not_already_done")"
    if is_gate_or_hook_addition_cmd "$CMD_BLOCK_NC" && ! q11_has_existing_alternative_verification "$_Q11_VAL"; then
        echo "BLOCK: q11_existing_alternative_verification — gate/hook追加cmdです。q11_not_already_done に既存代替の現物確認を記載してください" >&2
        echo "  推奨アクション: 既存/代替の仕組みを grep/rg 等で確認し、その確認方法と差分理由を q11_not_already_done に書け" >&2
        record_block_reason "q11に既存代替の現物確認なし"
    fi
    check_gate_hook_action_conversion "$CMD_BLOCK_NC"

    # q8_branch_coverage: 条件分岐変更cmdの本番データ分岐確認AC提案（段階的導入 — WARNING）
    # 起源: cmd_1443事例 — 本番未使用コードパスへの無駄修正
    # 目的: type=impl + 条件分岐キーワード検出時に、本番での分岐実行頻度確認ACの追加を提案
    _Q8_TASK_TYPE="$(cmd_block_get_field "task_type")"
    if [[ "${_Q8_TASK_TYPE:-}" == "impl" ]]; then
        _Q8_FIELDS=$(echo "$CMD_BLOCK_NC" | grep -E '^\s*(purpose|title):' || true)
        if echo "$_Q8_FIELDS" | grep -qiE '\bif\b|\bcase\b|条件|分岐|フラグ|\bflag\b|\belif\b|\bswitch\b'; then
            echo "WARNING: q8_branch_coverage — 条件分岐変更を含むimpl cmdです。本番データでの分岐実行頻度確認ACの追加を検討してください" >&2
            echo "  推奨アクション: 本番DBで該当条件がtrue/falseになるレコード数を確認せよ" >&2
            echo "  (cmd_1443教訓: 本番未使用コードパスへの修正は無駄コスト+リスク)" >&2
        fi
    fi

    # --- Check 3.7: チェックリスト制約転写確認（WARNING） ---
    # cmd_1397事故: チェックリストStep7(再計算禁止)がcmdに転写されず忍者が再計算実行
    # cmdにチェックリスト参照がある場合、隣接Step制約の転写を促す
    if echo "$CMD_BLOCK_NC" | grep -qiE 'チェックリスト|checklist-'; then
        echo "WARNING: チェックリスト参照cmdです。隣接Stepの🛑制約(禁止事項)をACまたは制約欄に転写しましたか？" >&2
        echo "  (cmd_1397教訓: Step7再計算禁止がcmd未記載→忍者が再計算実行)" >&2
    fi
fi

# --- Check 4: flock競合検出 ---
# flock -n: ノンブロッキング。取得成功=競合なし、取得失敗=家老が書き込み中
if ! (flock -n 200) 200>"$LOCK_FILE" 2>/dev/null; then
    echo "WARN: $LOCK_FILE がロック中です（家老が書き込み中の可能性）" >&2
    record_warn_reason "flock_lock_contention" "check=check_lock_contention"
fi

show_recent_completed_ninjas() {
    local snapshot_file="$PROJECT_DIR/queue/karo_snapshot.txt"
    [[ -f "$snapshot_file" ]] || return 0

    local completed_ninjas
    completed_ninjas=$(
        awk -F'|' '
            NR == FNR {
                if ($1 == "report" && ($4 == "completed" || $4 == "done")) {
                    report_done[$2] = 1
                    if (!seen[$2]++) {
                        names[++count] = $2
                    }
                }
                next
            }
            $1 == "ninja" && ($4 == "completed" || $4 == "done") {
                if (!report_done[$2] && !seen[$2]++) {
                    names[++count] = $2
                }
            }
            END {
                for (i = 1; i <= count; i++) {
                    printf "%s%s", names[i], (i < count ? ", " : "")
                }
            }
        ' "$snapshot_file" "$snapshot_file" 2>/dev/null || true
    )

    [[ -n "$completed_ninjas" ]] || return 0
    echo "  直近完了忍者一覧: $completed_ninjas" >&2
}

show_uncommitted_changes_warning() {
    local uncommitted="${1:-}"
    [[ -n "$uncommitted" ]] || return 0

    echo "WARN: 未コミット変更を検出（コミット忘れ注意）:" >&2
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        echo "  $line" >&2
    done <<< "$uncommitted"

    show_recent_completed_ninjas
}

# --- Check 5: uncommitted changes検出 ---
# WSL2 NTFS最適化: git status --porcelain=v2 --no-optional-locks はgit自身のmtime cacheを活用し
# diff-files(全tracked filesをstat()比較)より高速。cmd_2077で最適化
UNCOMMITTED=$(git -C "$PROJECT_DIR" status --porcelain=v2 --no-optional-locks \
    -- scripts/ CLAUDE.md instructions/ config/ 2>/dev/null \
    | awk '!/^[?!#]/{sub(/.*[[:space:]]/,""); print}' || true)
show_uncommitted_changes_warning "$UNCOMMITTED"

# --- Check 6: パイプラインGP重複チェック（非BLOCK — WARN_COUNTに加算しない） ---
# 新cmdのcommandフィールドからGP-XXXパターンを抽出し、
# 直近20件のdelegated/in_progress cmdと照合。一致時WARN（非BLOCK）
if [[ -f "$QUEUE_FILE" ]] && grep -q "  ${CMD_ID}:" "$QUEUE_FILE"; then
    NEW_CMD_LINE=$(awk "/^  ${CMD_ID}:/{found=1; next} found && /^  cmd_/{exit} found && /command:/{print; exit}" "$QUEUE_FILE")
    NEW_GP=$(echo "$NEW_CMD_LINE" | grep -oE 'GP-[0-9]+' | sort -u || true)

    if [[ -n "$NEW_GP" ]]; then
        RECENT_CMDS=$(grep -oE "^  cmd_[^:]+:" "$QUEUE_FILE" | sed 's/: *$//; s/^ *//' | tail -20 | grep -v "^${CMD_ID}$" || true)

        if [[ -n "$RECENT_CMDS" ]]; then
            while IFS= read -r OTHER_CMD; do
                [[ -z "$OTHER_CMD" ]] && continue
                OTHER_BLOCK=$(awk "/^  ${OTHER_CMD}:/{found=1; next} found && /^  cmd_/{exit} found{print}" "$QUEUE_FILE")
                OTHER_STATUS=$(echo "$OTHER_BLOCK" | awk '/status:/{gsub(/.*status: */, ""); gsub(/"/, ""); print; exit}')

                if [[ "$OTHER_STATUS" == "delegated" || "$OTHER_STATUS" == "in_progress" ]]; then
                    OTHER_CMD_LINE=$(echo "$OTHER_BLOCK" | grep -m1 "command:" || true)
                    while IFS= read -r gp; do
                        [[ -z "$gp" ]] && continue
                        if echo "$OTHER_CMD_LINE" | grep -qF "$gp"; then
                            echo "WARN: ${CMD_ID} のGP番号 ${gp} が ${OTHER_CMD}(status:${OTHER_STATUS}) と重複" >&2
                        fi
                    done <<< "$NEW_GP"
                fi
            done <<< "$RECENT_CMDS"
        fi
    fi
fi

# --- Check 7: 軍師既存分析チェック（偵察cmd重複防止） ---
# 起源: cmd_1451事件 — 軍師OPT-6分析完了済みなのに偵察cmd重複起票
# 目的: recon/scout cmdの起票前に軍師の関連分析有無を確認させる
check_gunshi_analysis_overlap() {
    [[ ! -f "$QUEUE_FILE" ]] && return 0
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # task_typeがrecon/scoutの場合のみチェック（impl等は対象外）
    local TASK_TYPE
    TASK_TYPE="$(cmd_block_get_field "task_type")"
    if [[ "$TASK_TYPE" != "recon" && "$TASK_TYPE" != "scout" ]]; then
        return 0
    fi

    # context/gunshi-*.md の存在チェック
    local GUNSHI_FILES
    GUNSHI_FILES=$(find "$PROJECT_DIR/context" -name "gunshi-*.md" -type f 2>/dev/null)
    [[ -z "$GUNSHI_FILES" ]] && return 0

    # 軍師分析ファイルの見出しを表示
    local HIT=false
    while IFS= read -r gfile; do
        [[ -z "$gfile" || ! -f "$gfile" ]] && continue
        local title mtime_hr
        title=$(head -5 "$gfile" | grep -m1 '^#' | sed 's/^# *//')
        mtime_hr=$(date -r "$gfile" '+%m-%d %H:%M' 2>/dev/null || echo "unknown")
        if [[ "$HIT" == false ]]; then
            echo "WARNING: 偵察cmd起票前に軍師の既存分析を確認したか？" >&2
            HIT=true
        fi
        echo "  $(basename "$gfile") [$mtime_hr] — $title" >&2
    done <<< "$GUNSHI_FILES"

    if [[ "$HIT" == true ]]; then
        echo "  → 重複起票防止(cmd_1451教訓): 軍師が先行分析済みの可能性あり" >&2
    fi
}

check_gunshi_analysis_overlap

# --- Check 8: PI番号衝突チェック（Production Invariant重複防止） ---
# 起源: cmd_1453事件 — PI-015を起票したが既存PI-015と衝突。hayateがPI-016に修正
# 目的: cmdにPI-0XXが含まれる場合、既存PIと衝突しないか自動チェック
check_pi_number_collision() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # cmdブロックからPI-0XX番号を抽出
    local PI_NUMS
    PI_NUMS=$(echo "$CMD_BLOCK_NC" | grep -oE 'PI-[0-9]{3}' | sort -u || true)
    [[ -z "$PI_NUMS" ]] && return 0

    # 全projects/*.yamlから既存PI番号を収集
    local EXISTING_PIS
    EXISTING_PIS=$(grep -ohE 'PI-[0-9]{3}' "$PROJECT_DIR"/projects/*.yaml 2>/dev/null | sort -u || true)
    [[ -z "$EXISTING_PIS" ]] && return 0

    # 衝突検出
    local HIT=false
    while IFS= read -r pi; do
        [[ -z "$pi" ]] && continue
        if echo "$EXISTING_PIS" | grep -qx "$pi"; then
            if [[ "$HIT" == false ]]; then
                echo "WARNING: PI番号衝突検出（cmd_1453教訓）" >&2
                HIT=true
            fi
            echo "  $pi は既に projects/*.yaml に登録済み" >&2
        fi
    done <<< "$PI_NUMS"

    if [[ "$HIT" == true ]]; then
        # 次の空き番号を表示
        local MAX_PI
        MAX_PI=$(echo "$EXISTING_PIS" | grep -oE '[0-9]+' | sort -n | tail -1)
        local NEXT_PI
        NEXT_PI=$(printf "PI-%03d" $((10#$MAX_PI + 1)))
        echo "  → 次の空き番号: $NEXT_PI" >&2
    fi
}

check_pi_number_collision

# --- Check 9: 未消化insightsサーフェス（知識循環デッドエンド防止） ---
# 起源: insights 18件死蔵発見(2026-03-28) — 書込み専用で消費者不在
# 目的: cmd起票時にpending insightsを表示し、将軍がinsightsを消費する動線を作る
show_pending_insights() {
    local INSIGHTS_FILE="$PROJECT_DIR/queue/insights.yaml"
    [[ ! -f "$INSIGHTS_FILE" ]] && return 0

    local insight_summary PENDING_COUNT
    insight_summary=$(awk '
        /^- / {
            if (in_item && status == "pending") {
                pending++
                if (shown < 3 && insight != "") {
                    text = insight
                    gsub(/\r/, "", text)
                    gsub(/\n/, " ", text)
                    if (length(text) > 70) {
                        text = substr(text, 1, 70)
                    }
                    shown++
                    lines = lines "  → " text "\n"
                }
            }
            in_item = 1
            status = ""
            insight = ""
            next
        }
        in_item && /^[[:space:]]*status:[[:space:]]*/ {
            status = $0
            sub(/^[[:space:]]*status:[[:space:]]*/, "", status)
            gsub(/["'"'"']/, "", status)
            next
        }
        in_item && /^[[:space:]]*insight:[[:space:]]*/ {
            insight = $0
            sub(/^[[:space:]]*insight:[[:space:]]*/, "", insight)
            gsub(/^["'"'"']|["'"'"']$/, "", insight)
            next
        }
        END {
            if (in_item && status == "pending") {
                pending++
                if (shown < 3 && insight != "") {
                    text = insight
                    gsub(/\r/, "", text)
                    gsub(/\n/, " ", text)
                    if (length(text) > 70) {
                        text = substr(text, 1, 70)
                    }
                    lines = lines "  → " text "\n"
                }
            }
            printf "%d\n%s", pending + 0, lines
        }
    ' "$INSIGHTS_FILE" 2>/dev/null)
    PENDING_COUNT=$(printf '%s\n' "$insight_summary" | head -n1)
    PENDING_COUNT=$(( ${PENDING_COUNT:-0} + 0 ))
    [[ "$PENDING_COUNT" -eq 0 ]] && return 0

    echo "INFO: 未消化insights ${PENDING_COUNT}件 — 起票前に確認推奨:" >&2
    printf '%s\n' "$insight_summary" | tail -n +2 >&2
    if [[ "$PENDING_COUNT" -gt 3 ]]; then
        echo "  ... 他 $((PENDING_COUNT - 3))件 (queue/insights.yaml)" >&2
    fi
}

show_pending_insights

# --- Check 10: AC内ファイルパス存在チェック（親ディレクトリありはINFO、親も不在はBLOCK） ---
# 起源: cmd_1464事故 + cmd_1896/1899で3回連続パス誤り(2026-04-14なぜなぜ7回)
# 目的: AC内のファイルパス参照が実在するか検証。未作成でも親ディレクトリがあれば作成対象として許容する
# 真因: WARNを無視する習慣が定着し、パス誤りcmdが家老・忍者に到達する
check_ac_file_paths() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # AC内からファイルパス(拡張子付き)を抽出（ACセクションのみ。command/quality_gate内の説明文は対象外）
    # awkでacceptance_criteria:ブロックを抽出。終了条件: ACブロック後の同レベルキー(quality_gate/command等)
    local AC_BLOCK PATHS
    AC_BLOCK=$(echo "$CMD_BLOCK_NC" | awk '
        /^[[:space:]]*acceptance_criteria:/ { in_ac=1; print; next }
        in_ac && /^[[:space:]]*[a-z_]+:/ && !/^[[:space:]]*- / && !/^[[:space:]]*description:/ && !/^[[:space:]]*id:/ { exit }
        in_ac { print }
    ' || true)
    PATHS=$(echo "$AC_BLOCK" | grep -oE '[A-Za-z0-9_-]+(/[A-Za-z0-9_.+-]+)+\.(py|ts|tsx|js|jsx|sh|bash|yaml|yml|json|sql|html|css|toml|cfg|env)' | sort -u || true)
    [[ -z "$PATHS" ]] && return 0

    # プロジェクトWDを取得: cmdブロックのproject → current_project → fallback
    # 単体抽出テストでも動くよう、helper未ロード時はブロック本文から直接拾う。
    local PROJECT_ID PROJECT_WD
    if declare -F cmd_block_get_field >/dev/null 2>&1; then
        PROJECT_ID="$(cmd_block_get_field "project")"
    else
        PROJECT_ID=$(printf '%s\n' "${CMD_BLOCK_NC:-$CMD_BLOCK}" | awk '
            /^[[:space:]]*project:[[:space:]]*/ {
                sub(/^[[:space:]]*project:[[:space:]]*/, "")
                gsub(/^["'\''"]|["'\''"]$/, "")
                print
                exit
            }
        ')
    fi
    [[ -z "$PROJECT_ID" ]] && PROJECT_ID=$(awk '/^current_project:/{print $2}' "$PROJECT_DIR/config/projects.yaml" 2>/dev/null)

    if [[ -n "${PROJECT_ID:-}" ]]; then
        PROJECT_WD=$(awk -v id="$PROJECT_ID" '
            /^  - id:/ { current_id = $3; gsub(/"/, "", current_id) }
            /^    path:/ && current_id == id { gsub(/.*path: *"?/, ""); gsub(/"$/, ""); print; exit }
        ' "$PROJECT_DIR/config/projects.yaml" 2>/dev/null)
    fi

    [[ -z "${PROJECT_WD:-}" ]] && return 0

    # 各パスの存在チェック
    local HAS_MISSING=false
    local HAS_CREATABLE=false
    while IFS= read -r fpath; do
        [[ -z "$fpath" ]] && continue
        if [[ ! -e "$PROJECT_WD/$fpath" ]] && [[ ! -e "$PROJECT_DIR/$fpath" ]]; then
            local parent_dir
            parent_dir=$(dirname "$fpath")

            if [[ -d "$PROJECT_WD/$parent_dir" ]] || [[ -d "$PROJECT_DIR/$parent_dir" ]]; then
                if [[ "$HAS_CREATABLE" == false ]]; then
                    echo "INFO: AC内の未作成ファイルは親ディレクトリが存在するため作成対象として扱います:" >&2
                    HAS_CREATABLE=true
                fi
                echo "  • $fpath (parent: $PROJECT_WD/$parent_dir)" >&2
            else
                if [[ "$HAS_MISSING" == false ]]; then
                    echo "WARNING: AC内のファイルパスが存在せず、親ディレクトリも不在です（cmd_1464教訓）:" >&2
                    HAS_MISSING=true
                fi
                echo "  ✗ $fpath (missing parent: $PROJECT_WD/$parent_dir)" >&2
            fi
        fi
    done <<< "$PATHS"

    if [[ "$HAS_MISSING" == true ]]; then
        echo "  BLOCK: 親ディレクトリも不在のパスはcmd品質低下の根因。現物確認してからcmd_save.shを再実行せよ" >&2
        record_warn_reason "ac_missing_parent_path" "check=check_ac_file_paths"
    fi
}

check_ac_file_paths

# --- Check 10.5: cmd text pipe danger warning ---
# Purpose: shell/YAML-special pipe characters in command/purpose can be lost or
# interpreted by downstream task deployment if a batch write path regresses.
check_cmd_text_pipe_danger() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    local CMD_TEXT
    CMD_TEXT=$(printf '%s\n' "$CMD_BLOCK_NC" | awk '
        /^[[:space:]]*purpose:[[:space:]]*/ {
            line = $0
            sub(/^[[:space:]]*purpose:[[:space:]]*/, "", line)
            print line
            next
        }
        /^[[:space:]]*command:[[:space:]]*[|>][+-]?([[:space:]]*#.*)?$/ {
            in_command = 1
            next
        }
        /^[[:space:]]*command:[[:space:]]*/ {
            line = $0
            sub(/^[[:space:]]*command:[[:space:]]*/, "", line)
            print line
            next
        }
        in_command && /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]*/ {
            in_command = 0
            next
        }
        in_command { print }
    ' || true)

    [[ -n "${CMD_TEXT:-}" ]] || return 0
    if [[ "$CMD_TEXT" == *"|"* ]]; then
        echo "WARNING: cmdテキスト内にパイプ文字(|)を検出。deploy_task.sh/yaml_field_set_batch経路で切り詰め・シェル解釈されないよう、必要なら引用または別表現へ修正せよ" >&2
        record_warn_reason "cmd_text_pipe_danger" "check=check_cmd_text_pipe_danger"
    fi
}

check_cmd_text_pipe_danger

# --- Check 11: impl cmd post-deploy verification AC検出（informational — WARN_COUNTに加算しない） ---
# 目的: project=dm-signal + type=impl のcmdのacceptance_criteria内にデプロイ後検証ACがない場合に警告
# 起源: cmd_1491でpush漏れ→cmd_1492で後追い発生
check_impl_push_ac() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # project取得
    local PROJECT_ID
    PROJECT_ID="$(cmd_block_get_field "project")"
    [[ "$PROJECT_ID" != "dm-signal" ]] && return 0

    # task_type取得
    local TASK_TYPE
    TASK_TYPE="$(cmd_block_get_field "task_type")"
    [[ "$TASK_TYPE" != "impl" ]] && return 0

    # acceptance_criteria セクションを抽出
    local AC_SECTION
    AC_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
        /^[[:space:]]*acceptance_criteria:/ { found=1; next }
        found && /^[[:space:]]*[a-z_]+:/ && !/^[[:space:]]*- / && !/^[[:space:]]*description:/ && !/^[[:space:]]*id:/ { exit }
        found { print }
    ')

    # acceptance_criteriaがない場合はCMD_BLOCK_NC全体にフォールバック
    if [[ -z "$AC_SECTION" ]]; then
        AC_SECTION="$CMD_BLOCK_NC"
    fi

    # AC内にpush/deploy/verify/本番確認関連キーワードがあるか
    if ! echo "$AC_SECTION" | grep -qiE 'push|deploy|デプロイ|verify|本番確認|本番反映|本番動作|Render'; then
        echo "WARNING: project=dm-signal + type=impl のACにデプロイ後の本番動作確認が含まれていません" >&2
        echo "  デプロイ後の本番動作確認ACを追加せよ。例:" >&2
        echo '  - "ACN: git push後、Render自動デプロイ完了を確認。本番エンドポイントで変更反映を目視確認"' >&2
        echo "  (cmd_1491教訓: push漏れ→cmd_1492で後追い発生)" >&2
    fi
}

check_impl_push_ac

# --- Check 11.1: dm-signal raw layer notation warning ---
# 目的: dm-signal cmdで文脈なし生L0-L4を使うと、PF階層と計算階層が混線するためcanonical名を促す
check_dm_signal_bare_layer_reference() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    local PROJECT_ID
    if declare -F cmd_block_get_field >/dev/null 2>&1; then
        PROJECT_ID="$(cmd_block_get_field "project")"
    else
        PROJECT_ID=$(printf '%s\n' "${CMD_BLOCK_NC:-$CMD_BLOCK}" | awk '
            /^[[:space:]]*project:[[:space:]]*/ {
                sub(/^[[:space:]]*project:[[:space:]]*/, "")
                gsub(/^["'\''"]|["'\''"]$/, "")
                print
                exit
            }
        ')
    fi
    [[ "$PROJECT_ID" != "dm-signal" ]] && return 0

    local raw_hits=""
    local line trimmed
    while IFS= read -r line; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$trimmed" ]] && continue

        # Exclusions: code spans, file paths, canonical names, and mathematical contexts.
        [[ "$trimmed" == *'`'* ]] && continue
        [[ "$trimmed" =~ (/|[[:alnum:]_-]+\.(md|py|sh|yaml|yml|csv|json|txt|db|sqlite)) ]] && continue
        [[ "$trimmed" =~ (pf_L[0-4]|calc_L[0-4]|ctx_L[0-4]|doc_L[0-4]|sg_L[0-4]) ]] && continue
        [[ "$trimmed" =~ (正則化|ノルム|norm|regularization|regression|loss|lambda|λ|距離|行列|ベクトル|vector|matrix) ]] && continue

        if [[ "$trimmed" =~ (^|[^A-Za-z0-9_])L[0-4]([^A-Za-z0-9_]|$) ]]; then
            raw_hits+="${trimmed}"$'\n'
        fi
    done <<< "${CMD_BLOCK_NC:-$CMD_BLOCK}"

    [[ -z "$raw_hits" ]] && return 0

    echo "WARNING: dm-signal cmdに文脈なし生L0-L4表記を検出。pf_L0/pf_L1/pf_L2 または calc_L1/calc_L2/calc_L3 などcanonical名で曖昧性を潰せ" >&2
    echo "  該当行: $(printf '%s' "$raw_hits" | head -3 | tr '\n' ' ')" >&2
    echo "  除外: バッククォート/ファイルパス/canonical名接頭辞/数学キーワード同一行" >&2
    record_warn_reason "dm-signal文脈なし生L0-L4表記" "check=check_dm_signal_bare_layer_reference"
}

check_dm_signal_bare_layer_reference

# --- Check 11.3: AC推奨/必須混在検出（informational — WARN_COUNTに加算しない） ---
# 起源: GP-173。verdict_override 2件(cmd_karo_fix_flock_silent)。ACに推奨事項混入→忍者正FAIL→家老override
# 目的: ACテキストに推奨キーワードが含まれる場合にWARNし、notesへの分離を促す
check_ac_must_should_mix() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    local AC_SECTION
    AC_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
        /^[[:space:]]*acceptance_criteria:/ { found=1; next }
        found && /^[[:space:]]*[a-z_]+:/ && !/^[[:space:]]*- / && !/^[[:space:]]*description:/ && !/^[[:space:]]*id:/ { exit }
        found { print }
    ')
    [[ -z "$AC_SECTION" ]] && return 0

    local RECOMMEND_LINES
    RECOMMEND_LINES=$(echo "$AC_SECTION" | grep -inE '推奨|optional|nice.to.have|できれば|望ましい' || true)
    if [[ -n "$RECOMMEND_LINES" ]]; then
        record_block_reason "ACに推奨事項が混在しています。推奨はnotesに分離し、ACは必須(MUST)のみにせよ"
        echo "  AC定義: 忍者が二値(yes/no)で判定する必須完了基準。推奨/optional/nice-to-haveはnotes欄に" >&2
        echo "  該当行: $(echo "$RECOMMEND_LINES" | head -3 | tr '\n' ' ')" >&2
        echo "  根拠: verdict_override WA 2件(cmd_karo_fix_flock_silent)。推奨にno→FAIL→家老override。WARN→BLOCK昇格(GP-175)" >&2
        abort_if_block_immediate || return 1
    fi
}

check_ac_must_should_mix

# --- Check 11.5: 研究cmdの道具成長AC検出（informational — WARN_COUNTに加算しない） ---
# 起源: 軍師SG10 — 研究cmdで新規関数を増やしてもresearch_engine.py統合ACがないと意志依存で分岐する
# 目的: research系キーワードを含むimpl cmdで、ACにengine統合/追加/移設の明示がない場合にWARNING
check_research_tool_growth_ac() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    local PROJECT_ID TASK_TYPE
    if declare -F cmd_block_get_field >/dev/null 2>&1; then
        PROJECT_ID="$(cmd_block_get_field "project")"
        TASK_TYPE="$(cmd_block_get_field "task_type")"
    else
        PROJECT_ID=$(printf '%s\n' "${CMD_BLOCK_NC:-$CMD_BLOCK}" | awk '
            /^[[:space:]]*project:[[:space:]]*/ {
                sub(/^[[:space:]]*project:[[:space:]]*/, "")
                gsub(/^["'\''"]|["'\''"]$/, "")
                print
                exit
            }
        ')
        TASK_TYPE=$(printf '%s\n' "${CMD_BLOCK_NC:-$CMD_BLOCK}" | awk '
            /^[[:space:]]*task_type:[[:space:]]*/ {
                sub(/^[[:space:]]*task_type:[[:space:]]*/, "")
                gsub(/^["'\''"]|["'\''"]$/, "")
                print
                exit
            }
        ')
    fi

    [[ "$PROJECT_ID" != "dm-signal" ]] && return 0
    [[ "$TASK_TYPE" != "impl" ]] && return 0

    local COMMAND_SECTION
    COMMAND_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
        /command:/ { found=1; print; next }
        found && /^    [a-zA-Z_][a-zA-Z0-9_]*:/ { exit }
        found { print }
    ')
    [[ -z "$COMMAND_SECTION" ]] && return 0

    if ! echo "$COMMAND_SECTION" | grep -qiE 'research_engine|simulate|analysis|研究'; then
        return 0
    fi

    local AC_SECTION
    AC_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
        /^[[:space:]]*acceptance_criteria:/ { found=1; next }
        found && /^[[:space:]]*[a-z_]+:/ && !/^[[:space:]]*- / && !/^[[:space:]]*description:/ && !/^[[:space:]]*id:/ { exit }
        found { print }
    ')
    [[ -z "$AC_SECTION" ]] && AC_SECTION="$CMD_BLOCK_NC"

    if echo "$AC_SECTION" | grep -qiE 'research_engine(\.py)?|engine[^[:cntrl:]]*(統合|追加|移設)|(統合|追加|移設)[^[:cntrl:]]*(research_engine|engine)'; then
        return 0
    fi

    echo "WARNING: 研究cmdで新規関数を定義する場合、research_engine.pyへの統合ACを検討せよ" >&2
    echo '  例: "ACN: 新規関数をresearch_engine.pyへ統合し、呼び出し側を移設"' >&2
    echo "  (軍師SG10: engine未統合の研究ロジックは再利用が意志依存になる)" >&2
}

check_research_tool_growth_ac

# --- Check 11.9: 殿発言強制検索（informational — WARN_COUNTに加算しない） ---
# 目的: cmdのtitle/purposeから過去の殿裁定・方針・指摘を自動検索し、
#       起票時に関連発言を見落とさない入口を作る。
show_lord_conversation_matches() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0
    [[ ! -f "$LORD_CONVERSATION_FILE" ]] && {
        echo "INFO: [LORD] 殿発言検索: lord_conversation.jsonl不在のため0件" >&2
        return 0
    }

    CMD_BLOCK_FOR_LORD="$CMD_BLOCK_NC" python3 - "$LORD_CONVERSATION_FILE" >&2 <<'PY'
import json
import os
import re
import sys

conversation_path = sys.argv[1]

def tokenize(text):
    if not text:
        return set()
    tokens = set()
    for token in re.findall(r'[a-zA-Z][a-zA-Z0-9_.-]*[a-zA-Z0-9]|[a-zA-Z0-9]{2,}', text.lower()):
        tokens.add(token)
    jp_chars = re.sub(r'[\x00-\x7f\s]', '', text)
    for i in range(len(jp_chars) - 1):
        tokens.add(jp_chars[i:i + 2])
    return tokens

def similarity(left, right):
    if not left or not right:
        return 0.0
    union = left | right
    return len(left & right) / len(union) * 100 if union else 0.0

def strip_scalar(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1]
    return value

cmd_text = os.environ.get("CMD_BLOCK_FOR_LORD", "")
fields = {"title": "", "purpose": ""}
current = None
block_indent = 0
for raw_line in cmd_text.splitlines():
    line = raw_line.rstrip("\n")
    if current is not None:
        indent = len(line) - len(line.lstrip(" "))
        if not line.strip():
            fields[current] += "\n"
            continue
        if indent > block_indent:
            fields[current] += line[block_indent:].rstrip() + "\n"
            continue
        current = None

    match = re.match(r'^\s*(title|purpose):\s*(.*)$', line)
    if not match:
        continue
    key, value = match.group(1), match.group(2)
    if value in {"|", ">"} or value == "":
        fields[key] = ""
        current = key
        block_indent = 6
    else:
        fields[key] = strip_scalar(value)

query = " ".join(value.strip() for value in fields.values() if value.strip())
query_words = tokenize(query)
if not query_words:
    print("INFO: [LORD] 殿発言検索: title/purpose空のため0件")
    raise SystemExit(0)

entries = []
total_inbound = 0
try:
    with open(conversation_path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if entry.get("direction") != "inbound":
                continue
            total_inbound += 1
            text = " ".join(
                str(entry.get(key, "") or "")
                for key in ("summary", "detail")
            )
            words = tokenize(text)
            score = similarity(query_words, words)
            if score <= 0:
                continue
            overlap = sorted(query_words & words)
            entries.append((score, entry.get("ts", ""), str(entry.get("summary", "") or "")[:120], overlap[:5]))
except OSError:
    print("INFO: [LORD] 殿発言検索: lord_conversation.jsonl読込失敗のため0件")
    raise SystemExit(0)

entries.sort(key=lambda item: (-item[0], item[1]))
hits = entries[:3]
print(f"INFO: [LORD] 殿発言検索: inbound {total_inbound}件から関連{len(entries)}件")
for score, ts, summary, overlap in hits:
    terms = ",".join(overlap)
    print(f"  - {ts} 類似度{score:.0f}% terms={terms}: {summary}")
PY
}

show_lord_conversation_matches

# --- Check 11.10: cmd-chronicle.md強制検索（informational — WARN_COUNTに加算しない） ---
# 目的: cmdのtitle/purposeから完了済みcmd履歴を自動検索し、
#       類似過去cmdの見落としを起票時に減らす。
show_cmd_chronicle_matches() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0
    [[ ! -f "$CMD_CHRONICLE_FILE" ]] && {
        echo "INFO: [CHRONICLE] cmd履歴検索: cmd-chronicle.md不在のため0件" >&2
        return 0
    }

    CMD_BLOCK_FOR_CHRONICLE="$CMD_BLOCK_NC" python3 - "$CMD_CHRONICLE_FILE" >&2 <<'PY'
import os
import re
import sys

chronicle_path = sys.argv[1]

def tokenize(text):
    if not text:
        return set()
    tokens = set()
    for token in re.findall(r'[a-zA-Z][a-zA-Z0-9_.-]*[a-zA-Z0-9]|[a-zA-Z0-9]{2,}', text.lower()):
        tokens.add(token)
    jp_chars = re.sub(r'[\x00-\x7f\s]', '', text)
    for i in range(len(jp_chars) - 1):
        tokens.add(jp_chars[i:i + 2])
    return tokens

def similarity(left, right):
    if not left or not right:
        return 0.0
    union = left | right
    return len(left & right) / len(union) * 100 if union else 0.0

def strip_scalar(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1]
    return value

def extract_title_purpose(cmd_text):
    fields = {"title": "", "purpose": ""}
    current = None
    block_indent = 0
    for raw_line in cmd_text.splitlines():
        line = raw_line.rstrip("\n")
        if current is not None:
            indent = len(line) - len(line.lstrip(" "))
            if not line.strip():
                fields[current] += "\n"
                continue
            if indent > block_indent:
                fields[current] += line[block_indent:].rstrip() + "\n"
                continue
            current = None

        match = re.match(r'^\s*(title|purpose):\s*(.*)$', line)
        if not match:
            continue
        key, value = match.group(1), match.group(2)
        if value in {"|", ">"} or value == "":
            fields[key] = ""
            current = key
            block_indent = 6
        else:
            fields[key] = strip_scalar(value)
    return " ".join(value.strip() for value in fields.values() if value.strip())

query = extract_title_purpose(os.environ.get("CMD_BLOCK_FOR_CHRONICLE", ""))
query_words = tokenize(query)
if not query_words:
    print("INFO: [CHRONICLE] cmd履歴検索: title/purpose空のため0件")
    raise SystemExit(0)

entries = []
total_cmds = 0
try:
    with open(chronicle_path, encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if not line.startswith("| cmd_"):
                continue
            parts = [part.strip() for part in line.strip("|").split("|")]
            if len(parts) < 2:
                continue
            cmd_id = parts[0]
            title = parts[1]
            rest = " ".join(parts[2:])
            total_cmds += 1
            words = tokenize(f"{title} {rest}")
            score = similarity(query_words, words)
            if score <= 0:
                continue
            overlap = sorted(query_words & words)
            entries.append((score, cmd_id, title[:100], overlap[:5]))
except OSError:
    print("INFO: [CHRONICLE] cmd履歴検索: cmd-chronicle.md読込失敗のため0件")
    raise SystemExit(0)

entries.sort(key=lambda item: (-item[0], item[1]))
hits = entries[:5]
print(f"INFO: [CHRONICLE] cmd履歴検索: completed {total_cmds}件から関連{len(entries)}件")
for score, cmd_id, title, overlap in hits:
    terms = ",".join(overlap)
    print(f"  - {cmd_id} 類似度{score:.0f}% terms={terms}: {title}")
PY
}

show_cmd_chronicle_matches

# --- Check 12: 内容重複チェック（informational — WARN_COUNTに加算しない） ---
# 起源: 重複cmd起票の構造的防止
# 目的: 新cmdのtitle+purposeと直近20件(キュー+archive)の類似度を比較しWARN（50%以上）
check_content_duplicate() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0
    [[ ! -f "$QUEUE_FILE" ]] && return 0

    python3 - "$QUEUE_FILE" "$CMD_ID" "${ARCHIVE_CMD_DIR:-}" >&2 <<'PY'
import sys, re, os, json

def tokenize(text):
    """title+purposeをトークン集合に変換。ASCII単語+日本語2gramで混合テキスト対応"""
    if not text:
        return set()
    tokens = set()
    for t in re.findall(r'[a-zA-Z][a-zA-Z0-9_.]*[a-zA-Z0-9]|[a-zA-Z0-9]{2,}', text.lower()):
        tokens.add(t)
    jp_chars = re.sub(r'[\x00-\x7f\s]', '', text)
    for i in range(len(jp_chars) - 1):
        tokens.add(jp_chars[i:i+2])
    return tokens

def similarity(s1, s2):
    """共通単語数/全単語数(Jaccard)"""
    if not s1 or not s2:
        return 0.0
    union = s1 | s2
    return len(s1 & s2) / len(union) * 100 if union else 0.0

def strip_scalar(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1]
    return value

def parse_title_purpose(path):
    commands = {}
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.readlines()
    except Exception:
        return commands

    current_cmd = None
    current_field = None
    block_indent = None

    def ensure_entry(cmd_id):
        return commands.setdefault(cmd_id, {"title": "", "purpose": ""})

    def finalize_block():
        nonlocal current_field, block_indent
        current_field = None
        block_indent = None

    for raw_line in lines:
        line = raw_line.rstrip("\n")

        cmd_match = re.match(r"^  (cmd_\d+):\s*$", line)
        if cmd_match:
            current_cmd = cmd_match.group(1)
            ensure_entry(current_cmd)
            finalize_block()
            continue

        if current_cmd is None:
            continue

        next_cmd_match = re.match(r"^  cmd_\d+:\s*$", line)
        if next_cmd_match:
            current_cmd = None
            finalize_block()
            continue

        if current_field is not None:
            indent = len(line) - len(line.lstrip(" "))
            if not line.strip():
                commands[current_cmd][current_field] += "\n"
                continue
            if indent <= block_indent:
                finalize_block()
            else:
                commands[current_cmd][current_field] += line[block_indent:].rstrip() + "\n"
                continue

        field_match = re.match(r"^    (title|purpose):\s*(.*)$", line)
        if not field_match:
            continue

        field = field_match.group(1)
        value = field_match.group(2)
        if value in {"|", ">"} or value == "":
            commands[current_cmd][field] = ""
            current_field = field
            block_indent = 6
        else:
            commands[current_cmd][field] = strip_scalar(value)
            finalize_block()

    for entry in commands.values():
        for key in ("title", "purpose"):
            entry[key] = entry[key].strip()
    return commands

queue_file, current_cmd_id, archive_dir = sys.argv[1], sys.argv[2], sys.argv[3]
cmds = parse_title_purpose(queue_file)
current = cmds.get(current_cmd_id)
if not isinstance(current, dict):
    sys.exit(0)

new_title = str(current.get("title", "") or "")
new_purpose = str(current.get("purpose", "") or "")
new_words = tokenize(new_title) | tokenize(new_purpose)
if not new_words:
    sys.exit(0)

# Phase 1: キュー内の直近20件と比較
cmd_ids = sorted(cmds.keys())
cmd_ids = [c for c in cmd_ids if c != current_cmd_id][-20:]

hits = []
for cid in cmd_ids:
    entry = cmds[cid]
    if not isinstance(entry, dict):
        continue
    t = str(entry.get("title", "") or "")
    p = str(entry.get("purpose", "") or "")
    other_words = tokenize(t) | tokenize(p)
    sim = similarity(new_words, other_words)
    if sim >= 50:
        hits.append((cid, t[:50], sim))

if hits:
    hits.sort(key=lambda x: -x[2])
    print("WARNING: 内容重複の可能性を検出（類似度50%以上）", file=sys.stderr)
    for cid, title, sim in hits:
        print(f"  {cid}: {title} — 類似度{sim:.0f}%", file=sys.stderr)
    print("  → 重複起票でないか確認してください（BLOCKではありません）", file=sys.stderr)

# Phase 2: archive/cmds/の直近20ファイルと比較
# os.scandir()でstat情報を一括取得（glob+getmtimeのsyscall×n削減）
if os.path.isdir(archive_dir):
    cache_path = "/tmp/cmd_save_content_dup_cache.json"
    try:
        with open(cache_path, encoding="utf-8") as fh:
            cache = json.load(fh)
        if not isinstance(cache, dict):
            cache = {}
    except Exception:
        cache = {}

    cache_dirty = False
    try:
        archive_dir_stat = os.stat(archive_dir)
    except OSError:
        archive_dir_stat = None

    recent_index = cache.get("_archive_recent_files", {})
    if (
        archive_dir_stat is not None
        and isinstance(recent_index, dict)
        and recent_index.get("archive_dir") == os.path.abspath(archive_dir)
        and recent_index.get("dir_mtime_ns") == archive_dir_stat.st_mtime_ns
        and isinstance(recent_index.get("files"), list)
    ):
        archive_files = recent_index["files"]
    else:
        scanned_files = []
        for entry in os.scandir(archive_dir):
            if not entry.name.endswith(".yaml"):
                continue
            st = entry.stat()
            scanned_files.append(
                {
                    "path": entry.path,
                    "mtime_ns": st.st_mtime_ns,
                    "size": st.st_size,
                }
            )
        scanned_files.sort(key=lambda item: item["mtime_ns"], reverse=True)
        archive_files = scanned_files[:20]
        if archive_dir_stat is not None:
            cache["_archive_recent_files"] = {
                "archive_dir": os.path.abspath(archive_dir),
                "dir_mtime_ns": archive_dir_stat.st_mtime_ns,
                "files": archive_files,
            }
            cache_dirty = True

    archive_hits = []
    for archive_file in archive_files:
        af = archive_file.get("path") if isinstance(archive_file, dict) else str(archive_file)
        if not af:
            continue
        try:
            st_mtime_ns = archive_file.get("mtime_ns") if isinstance(archive_file, dict) else None
            st_size = archive_file.get("size") if isinstance(archive_file, dict) else None
            if st_mtime_ns is None or st_size is None:
                st = os.stat(af)
                st_mtime_ns = st.st_mtime_ns
                st_size = st.st_size
        except OSError:
            continue
        cache_key = os.path.abspath(af)
        cache_entry = cache.get(cache_key, {})
        if (
            isinstance(cache_entry, dict)
            and cache_entry.get("mtime_ns") == st_mtime_ns
            and cache_entry.get("size") == st_size
            and isinstance(cache_entry.get("commands"), dict)
        ):
            acmds = cache_entry["commands"]
        else:
            acmds = parse_title_purpose(af)
            cache[cache_key] = {
                "mtime_ns": st_mtime_ns,
                "size": st_size,
                "commands": acmds,
            }
            cache_dirty = True
        for acid, aentry in acmds.items():
            if not isinstance(aentry, dict):
                continue
            t = str(aentry.get("title", "") or "")
            p = str(aentry.get("purpose", "") or "")
            other_words = tokenize(t) | tokenize(p)
            sim = similarity(new_words, other_words)
            if sim >= 50:
                archive_hits.append((acid, t[:50], sim))

    if archive_hits:
        archive_hits.sort(key=lambda x: -x[2])
        print("WARNING: archive内に類似cmdを検出（類似度50%以上）(archive)", file=sys.stderr)
        for cid, title, sim in archive_hits:
            print(f"  (archive) {cid}: {title} — 類似度{sim:.0f}%", file=sys.stderr)
        print("  → 過去の完了cmdとの重複でないか確認してください（BLOCKではありません）", file=sys.stderr)

    if cache_dirty:
        try:
            tmp_path = f"{cache_path}.tmp"
            with open(tmp_path, "w", encoding="utf-8") as fh:
                json.dump(cache, fh, ensure_ascii=False)
            os.replace(tmp_path, cache_path)
        except Exception:
            pass
PY
}

check_content_duplicate

# --- Check 13: ACパラメータ充足度チェック（WARN — WARN_COUNTに加算） ---
# 起源: cmd_1681事故 — ACに「前処理4条件」とだけ書き具体値未記載→忍者が独自判断でKalman_auto使用→条件不一致
# 目的: ACに「N条件」「N項目」等の数量指定があり具体値列挙がない場合にWARN
emit_ac_param_candidate_hints() {
    local ac_line="${1:-}"
    [[ -n "$ac_line" ]] || return 0

    CMD_SAVE_AC_LINE="$ac_line" \
    CMD_SAVE_CMD_BLOCK="${CMD_BLOCK_NC:-}" \
    CMD_SAVE_PROJECT_DIR="$PROJECT_DIR" \
    CMD_SAVE_PROJECT_ID="$(cmd_block_get_field "project" "")" \
    python3 - <<'PY' >&2 || true
import os
import re
from pathlib import Path

root = Path(os.environ.get("CMD_SAVE_PROJECT_DIR", ".")).resolve()
cmd_block = os.environ.get("CMD_SAVE_CMD_BLOCK", "")
ac_line = os.environ.get("CMD_SAVE_AC_LINE", "")
project_id = os.environ.get("CMD_SAVE_PROJECT_ID", "").strip()

paths: list[Path] = []

def add_path(raw: str) -> None:
    raw = raw.strip().strip("`'\"")
    if not raw:
        return
    path = Path(raw)
    if not path.is_absolute():
        path = root / path
    try:
        path = path.resolve()
    except OSError:
        return
    if path.is_file() and path not in paths:
        paths.append(path)

for match in re.findall(r'(?:(?:/[^\s`"\']+/)?(?:context|projects)/[^\s`"\':,()]+?\.(?:md|ya?ml))', cmd_block):
    add_path(match)

if project_id:
    add_path(f"projects/{project_id}.yaml")
    add_path(f"context/{project_id}.md")
    if project_id == "infra":
        add_path("context/infrastructure.md")

for extra in os.environ.get("CMD_SAVE_AC_HINT_EXTRA_FILES", "").split(":"):
    add_path(extra)

generic = {
    "AC", "以下", "満たす", "こと", "これ", "それ", "ため", "する", "される",
    "条件", "項目", "手法", "種類", "パラメータ", "要件", "ステップ", "設定", "フィールド",
}
quantity_match = re.search(r'([0-9]+)(条件|項目|手法|種類|パラメータ|要件|ステップ|設定|フィールド|種)', ac_line)
quantity_word = quantity_match.group(2) if quantity_match else ""
tokens = [
    t for t in re.findall(r'[A-Za-z0-9_./-]{3,}|[一-龥ぁ-んァ-ン]{2,}', ac_line)
    if t not in generic and not re.fullmatch(r'AC[0-9]+|[0-9]+', t)
]

hits: list[tuple[int, str, int, str]] = []
for path in paths[:12]:
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        continue
    for idx, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped or len(stripped) > 220:
            continue
        score = 0
        if quantity_word and quantity_word in stripped:
            score += 3
        for token in tokens:
            if token and token in stripped:
                score += 2
        if re.search(r'(^[-*]|\||:|: |：|/|・|,)', stripped):
            score += 1
        if score >= 3:
            rel = str(path)
            try:
                rel = str(path.relative_to(root))
            except ValueError:
                pass
            hits.append((score, rel, idx, stripped))

print("  候補値ヒント（関連context/projectsから自動抽出）:")
if not hits:
    searched = ", ".join(
        str(p.relative_to(root)) if str(p).startswith(str(root)) else str(p)
        for p in paths[:6]
    )
    if not searched:
        searched = "関連ファイル未検出"
    print(f"    - 候補なし: {searched}")
else:
    seen: set[tuple[str, str]] = set()
    count = 0
    for _score, rel, idx, text in sorted(hits, key=lambda item: (-item[0], item[1], item[2])):
        key = (rel, text)
        if key in seen:
            continue
        seen.add(key)
        print(f"    - {rel}:{idx}: {text[:160]}")
        count += 1
        if count >= 5:
            break
PY
}

check_ac_param_sufficiency() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # acceptance_criteria セクションを抽出。キー自体がない旧形式のみCMD全文へフォールバック。
    local AC_SECTION
    AC_SECTION="$(extract_acceptance_criteria_block)"
    if [[ -z "${AC_SECTION//[[:space:]]/}" ]]; then
        printf '%s\n' "$CMD_BLOCK_NC" | grep -qE '^[[:space:]]*acceptance_criteria[[:space:]]*:' && return 0
        AC_SECTION="$CMD_BLOCK_NC"
    fi

    # 数量指定パターン検出: 「N条件」「N項目」「N手法」「N種類」「N種」「Nパラメータ」等
    local QUANT_LINES
    QUANT_LINES=$(echo "$AC_SECTION" | grep -E '[0-9]+(条件|項目|手法|種類|パラメータ|要件|ステップ|設定|フィールド|種)' || true)
    [[ -z "$QUANT_LINES" ]] && return 0

    local HIT=false
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # 具体値列挙チェック: 括弧内にスラッシュ区切り or カンマ区切り or 中点区切りの項目
        if ! echo "$line" | grep -qE '\([^)]*[/,・][^)]*\)'; then
            if [[ "$HIT" == false ]]; then
                echo "WARN: ACに数量指定があるが具体値が列挙されていません（cmd_1681教訓）" >&2
                HIT=true
            fi
            echo "  → $(echo "$line" | sed 's/^[[:space:]]*//' | cut -c1-80)" >&2
            emit_ac_param_candidate_hints "$line"
        fi
    done <<< "$QUANT_LINES"

    if [[ "$HIT" == true ]]; then
        echo "  具体値を列挙せよ。例: 「4条件」→「4条件(EMA/SMA/Kalman/Bandpass)」" >&2
        echo "  理由: 忍者は独自判断で条件を補完する（cmd_1681実証済み）" >&2
        record_warn_reason "ac_param_sufficiency" "check=check_ac_param_sufficiency"
    fi
}

check_ac_param_sufficiency

# --- Check 14: 前段results.yamlとのパラメータ空間縮小検出（BLOCK） ---
# 起源: 2026-04-04 将軍4回連続で範囲縮小(top_n=5/lookback=6/PBO=5/MaxDD=1)
# 目的: 後段cmdが前段cmdを参照している場合、前段results.yamlのconfig空間を削っていないか構造的に検査
check_param_space_against_results() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    local CMD_SECTION
    CMD_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
        /^[[:space:]]*command:[[:space:]]*\|/ { found=1; next }
        found && /^      / { sub(/^      /, ""); print; next }
        found { exit }
    ')
    if [[ -z "$CMD_SECTION" ]]; then
        CMD_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
            /^[[:space:]]*command:[[:space:]]*/ {
                sub(/^[[:space:]]*command:[[:space:]]*/, "")
                gsub(/^"/, "")
                gsub(/"$/, "")
                print
                exit
            }
        ')
    fi
    [[ -z "$CMD_SECTION" ]] && return 0

    local PROJECT_ID PROJECT_ROOT_FOR_CMD PROJECT_FILE
    PROJECT_ID=$(echo "$CMD_BLOCK_NC" | awk '
        /^[[:space:]]*project:/ {
            sub(/^[[:space:]]*project:[[:space:]]*/, "")
            gsub(/["'\''[:space:]]/, "")
            print
            exit
        }
    ')
    if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "infra" ]]; then
        # infra projectはGS結果YAMLなし → python3不要 (cmd_2077最適化)
        return 0
    else
        PROJECT_FILE="$PROJECT_DIR/projects/${PROJECT_ID}.yaml"
        [[ ! -f "$PROJECT_FILE" ]] && return 0
        PROJECT_ROOT_FOR_CMD=$(awk '
            /^project:/ { in_project=1; next }
            in_project && /^[^[:space:]]/ { exit }
            in_project && /^  path:/ {
                sub(/^  path:[[:space:]]*/, "")
                gsub(/["'\''[:space:]]/, "")
                print
                exit
            }
        ' "$PROJECT_FILE")
        [[ -z "$PROJECT_ROOT_FOR_CMD" ]] && return 0
    fi
    # results YAML候補が存在しなければpython3不要 (cmd_2077最適化)
    if ! find "$PROJECT_ROOT_FOR_CMD/outputs/analysis" -name "*.yaml" \
            -maxdepth 3 2>/dev/null | grep -q .; then
        return 0
    fi

    CMD_SECTION="$CMD_SECTION" \
    CURRENT_CMD_ID="$CMD_ID" \
    PROJECT_ROOT_FOR_CMD="$PROJECT_ROOT_FOR_CMD" \
    python3 - <<'PY'
import glob
import os
import re
import sys

cmd_section = os.environ.get("CMD_SECTION", "")
current_cmd_id = os.environ.get("CURRENT_CMD_ID", "")
project_root = os.environ.get("PROJECT_ROOT_FOR_CMD", "")

if not cmd_section or not project_root:
    sys.exit(0)


def unique(values):
    seen = set()
    out = []
    for value in values:
        marker = repr(value)
        if marker in seen:
            continue
        seen.add(marker)
        out.append(value)
    return out


def normalize_scalar(raw):
    raw = raw.strip()
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in {"'", '"'}:
        raw = raw[1:-1]
    if re.fullmatch(r"-?\d+", raw):
        return int(raw)
    return raw


def parse_config_lists(path):
    config = {}
    in_config = False
    current_key = None
    with open(path, encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.rstrip("\n")
            if not in_config:
                if line.strip() == "config:":
                    in_config = True
                continue

            if re.match(r"^\S", line):
                break

            match = re.match(r"^  ([A-Za-z0-9_]+):\s*$", line)
            if match:
                current_key = match.group(1)
                config.setdefault(current_key, [])
                continue

            match = re.match(r"^  ([A-Za-z0-9_]+):\s+.+$", line)
            if match:
                current_key = None
                continue

            match = re.match(r"^  -\s*(.+)$", line)
            if match and current_key:
                config.setdefault(current_key, []).append(normalize_scalar(match.group(1)))
                continue

            if line.strip():
                current_key = None

    return {key: unique(values) for key, values in config.items() if values}


def parse_value_expr(expr):
    expr = expr.strip()
    if expr.startswith("["):
        end = expr.find("]")
        if end == -1:
            return None
        content = expr[1:end]
        parts = [part.strip() for part in content.split(",") if part.strip()]
        return [normalize_scalar(part) for part in parts]

    range_match = re.match(r"^(\d+)\s*-\s*(\d+)\b", expr)
    if range_match:
        start = int(range_match.group(1))
        end = int(range_match.group(2))
        step = 1 if end >= start else -1
        return list(range(start, end + step, step))

    csv_match = re.match(r"^(\d+(?:\s*,\s*\d+)+)\b", expr)
    if csv_match:
        return [int(part.strip()) for part in csv_match.group(1).split(",")]

    return None


ALIASES = {
    "lookbacks": ["lookbacks", "lookback"],
    "top_ns": ["top_ns", "top_n"],
    "rolling_windows": ["rolling_windows", "rolling_window"],
}


def extract_cmd_values(text, config_key):
    aliases = ALIASES.get(config_key, [config_key])
    found = []
    for alias in aliases:
        patterns = [
            rf"\b{re.escape(alias)}\b\s*[:=]\s*(\[[^\]]+\])",
            rf"\b{re.escape(alias)}\b\s*[:=]\s*([0-9]+\s*-\s*[0-9]+)",
            rf"\b{re.escape(alias)}\b\s*[:=]\s*([0-9]+(?:\s*,\s*[0-9]+)+)",
        ]
        for pattern in patterns:
            for match in re.finditer(pattern, text, flags=re.IGNORECASE):
                values = parse_value_expr(match.group(1))
                if values:
                    found.extend(values)
    return unique(found)


blocked = []
ref_cmds = unique(re.findall(r"(?<![A-Za-z0-9_])cmd_\d+(?![A-Za-z0-9_])", cmd_section))
for ref_cmd in ref_cmds:
    if ref_cmd == current_cmd_id:
        continue

    matches = glob.glob(os.path.join(project_root, "outputs", "analysis", "*", f"{ref_cmd}_results.yaml"))
    if not matches:
        continue

    result_path = matches[0]
    config_lists = parse_config_lists(result_path)
    if not config_lists:
        continue

    for config_key, previous_values in config_lists.items():
        current_values = extract_cmd_values(cmd_section, config_key)
        if not current_values:
            continue
        if set(current_values).issubset(set(previous_values)) and set(current_values) != set(previous_values):
            blocked.append((ref_cmd, config_key, previous_values, current_values, result_path))

if blocked:
    ref_cmd, config_key, previous_values, current_values, result_path = blocked[0]
    print(
        f"BLOCK: 前段cmdのパラメータ空間を縮小しています "
        f"({ref_cmd} {config_key}: current={current_values} previous={previous_values})",
        file=sys.stderr,
    )
    print(f"  参照results: {result_path}", file=sys.stderr)
    print("  後段cmdは前段と同一または拡張のみ許可。部分列挙での縮小は不可。", file=sys.stderr)
    sys.exit(1)
PY
}

check_param_space_against_results

# --- Check 15: パラメータ空間縮小検出（WARN） ---
# 起源: 2026-04-04 将軍4回連続で範囲縮小(top_n=5/lookback=6/PBO=5/MaxDD=1)
# 目的: commandに「計算量を言い訳に範囲を狭めた」記述があればWARN
check_param_space_shrink() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    local CMD_SECTION
    CMD_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
        /^[[:space:]]*command:/ { found=1; next }
        found && /^[[:space:]]{4,}/ { print; next }
        found && /^[[:space:]]*[a-z]/ { exit }
    ')
    [[ -z "$CMD_SECTION" ]] && return 0

    local SHRINK_PATTERNS="代表[0-9]+組|代表[0-9]+点|主要な[0-9]+パターン|計算量を考慮し|重いため[0-9]|に絞って検証|に絞って実行|非現実的なので|コスト的に[0-9]"
    local HITS
    HITS=$(echo "$CMD_SECTION" | grep -Ec "$SHRINK_PATTERNS" || true)

    if [[ "$HITS" -gt 0 ]]; then
        echo "WARN: パラメータ空間を縮小していないか？(${HITS}箇所で縮小表現を検出)" >&2
        echo "  → 計算量が多いなら: (1)道具を磨け (2)並列にせよ (3)チャンクに分けよ" >&2
        echo "  → 範囲を狭めることは殿の時間を奪う最大の無駄(2026-04-04殿厳命)" >&2
        record_warn_reason "param_space_shrink_expression" "check=check_param_space_shrink_expression"
    fi
}

check_param_space_shrink

# --- Check 17: 軍師設計書参照cmdの数値緩和検出（WARN — WARN_COUNTに加算しない） ---
# 起源: cmd_1781事故 — 軍師設計書の数値→cmdで緩和して起票(cmd_1783教訓)
# 目的: gunshi設計書参照cmdでq8_why_what数値とAC数値を突合し、緩和をWARN
check_gunshi_design_num_relax() {
    [[ -z "${CMD_BLOCK_NC:-}" ]] && return 0

    local scope_mode scout_exempt
    scope_mode="$(cmd_block_get_field "scope_mode")"
    scout_exempt="$(cmd_block_get_field "scout_exempt")"
    if [[ "${scope_mode:-}" == "SCOUT" || "${scout_exempt:-}" == "true" ]]; then
        return 0
    fi

    # 軍師設計書参照検出: q5_verified_sourceに設計書パスが含まれる場合（gunshi補足 2026-04-07）
    # 理由: q5は検証ソースの一次情報→設計書参照の信頼性が最も高い判定基準
    local Q5_VAL
    Q5_VAL="$(cmd_block_get_field "quality_gate.q5_verified_source")"
    if ! echo "$Q5_VAL" | grep -qiE 'gunshi[-_]|設計書|context/gunshi'; then
        return 0
    fi

    # カタログ参照除外: q5にカタログ|catalog|takeaway-catalogが含まれる場合スキップ（LS-A22 cmd_2279）
    # 理由: カタログ由来の閾値は設計書数値でなく分類基準→緩和と誤検出される
    if echo "$Q5_VAL" | grep -qiE 'カタログ|catalog|takeaway-catalog'; then
        return 0
    fi

    # q8_why_whatの存在確認（なければ上のBLOCKで終了済み）
    local Q8_LINE
    Q8_LINE="$(cmd_block_get_field "quality_gate.q8_why_what")"
    [[ -z "$Q8_LINE" ]] && return 0

    # WHAT部分から数値を抽出
    local WHAT_PART Q8_NUMS Q8_MAX
    WHAT_PART="${Q8_LINE#*WHAT:}"
    # FP修正(2026-04-27): 複利の問い「10回繰り返したら」の10は設計パラメータではない
    WHAT_PART="${WHAT_PART%%複利:*}"
    Q8_NUMS=$(echo "$WHAT_PART" | grep -oE '[0-9]+(\.[0-9]+)?' | sort -n || true)
    [[ -z "$Q8_NUMS" ]] && return 0
    Q8_MAX=$(echo "$Q8_NUMS" | tail -1)

    # acceptance_criteriaから数値を抽出
    local AC_SECTION AC_NUMS AC_MAX
    AC_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
        /acceptance_criteria:/ { found=1; next }
        found && /^    - / { print; next }
        found && /^      / { print; next }
        found { exit }
    ')
    [[ -z "$AC_SECTION" ]] && AC_SECTION="$CMD_BLOCK_NC"
    AC_NUMS=$(echo "$AC_SECTION" | sed 's|AC[0-9]\{1,\}||g; s|[A-Za-z_]*_[0-9]\{1,\}[A-Za-z0-9_.-]*||g; s|[A-Za-z_/]\{1,\}/[^ ]*||g; s|[αβγδ][0-9]\{1,\}||g; s|§[0-9.]\{1,\}||g' | grep -oE '[0-9]+(\.[0-9]+)?' | sort -n || true)

    if [[ -z "$AC_NUMS" ]]; then
        echo "WARN: 軍師設計書参照cmdでAC数値不一致を検出（cmd_1783教訓）" >&2
        echo "  q8のWHAT数値: ${Q8_MAX} → ACに数値なし（緩和/抜落ちの可能性）" >&2
        echo "  設計書の数値をACに明記せよ" >&2
        return 0
    fi

    AC_MAX=$(echo "$AC_NUMS" | tail -1)

    # AC最大値 > q8最大値 = 緩和の可能性（大きいtimeout/少ない対象数の逆）
    if python3 -c "import sys; sys.exit(0 if float('$AC_MAX') > float('$Q8_MAX') else 1)" 2>/dev/null; then
        echo "WARN: 軍師設計書参照cmdで数値緩和を検出（cmd_1783教訓）" >&2
        echo "  q8のWHAT最大値: ${Q8_MAX} → AC最大値: ${AC_MAX}（ACがq8より大きい=緩和の可能性）" >&2
        echo "  設計書の数値をACで緩和するな。元の設計書数値を維持せよ" >&2
        record_warn_reason "設計書数値緩和" "check=check_gunshi_reference_numeric_relaxation"
    fi
}

check_gunshi_design_num_relax

# --- Check 16: 行動→即確認原則（全cmd対象 — PI-023汎用化） ---
# 真因: 全ての問題の根源は「行動した後に結果を確認しない」。
# 本番変更かどうかのキーワード判定は各論。全cmdの全ACに確認を問う。
# reason: リアルワールドに事前通告はない(2026-04-07殿指摘)
check_action_immediate_verification() {
    local ac_block verify_ac_count
    ac_block="$(extract_acceptance_criteria_block || true)"
    [[ -n "${ac_block//[[:space:]]/}" ]] || return 0

    verify_ac_count=$(printf '%s\n' "$ac_block" | grep -ciE "確認|verify|パリティ|parity|検証|validate|assert|比較|突合|PASS" 2>/dev/null || true)
    verify_ac_count=$(( ${verify_ac_count:-0} + 0 ))
    if [ "$verify_ac_count" -eq 0 ]; then
        echo "WARNING: 全ACが行動のみで確認を含みません。行動→即確認(PI-023)。" >&2
        echo "  各ACに「やった後どう確認するか」を含めよ。確認なき行動は想像と同じ" >&2
    fi
}

check_action_immediate_verification

show_semantic_index_matches() {
    local SEARCH_TEXT="$1"
    local INDEX_PATH="${SEMANTIC_INDEX_PATH:-$PROJECT_DIR/docs/semantic-index/index.md}"
    [[ -z "$SEARCH_TEXT" || ! -f "$INDEX_PATH" ]] && return 0

    local _semantic_rows _semantic_label _semantic_aliases _semantic_files
    local _semantic_alias _semantic_alias_re
    _semantic_rows=$(awk -F'|' '
        function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
        function flush() {
            if (label != "" && aliases != "") print label "\t" aliases "\t" files
            label=""; aliases=""; files=""
        }
        /^## / { flush(); next }
        trim($2) == "label" {
            label=trim($3)
            next
        }
        trim($2) == "aliases" {
            aliases=trim($3)
            next
        }
        trim($2) == "file" {
            line=trim($3)
            if (files == "") files=line; else files=files ", " line
            next
        }
        END { flush() }
    ' "$INDEX_PATH" 2>/dev/null || true)
    [[ -z "$_semantic_rows" ]] && return 0

    while IFS=$'\t' read -r _semantic_label _semantic_aliases _semantic_files; do
        [[ -z "$_semantic_label" || -z "$_semantic_aliases" ]] && continue
        IFS=',' read -r -a _semantic_alias_array <<< "$_semantic_aliases"
        for _semantic_alias in "${_semantic_alias_array[@]}"; do
            _semantic_alias="$(printf '%s' "$_semantic_alias" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
            [[ -z "$_semantic_alias" ]] && continue
            _semantic_alias_re="$(printf '%s' "$_semantic_alias" | sed -E 's/[][(){}.^$*+?|\\/]/\\&/g')"
            if printf '%s' "$_semantic_alias" | LC_ALL=C grep -qE '^[A-Za-z0-9_ -]+$'; then
                _semantic_match_cmd=(grep -Eqi "(^|[^[:alnum:]_])${_semantic_alias_re}([^[:alnum:]_]|$)")
            else
                _semantic_match_cmd=(grep -Fqi -- "$_semantic_alias")
            fi
            if printf '%s\n' "$SEARCH_TEXT" | "${_semantic_match_cmd[@]}"; then
                echo "INFO: [SEMANTIC] ${_semantic_label} matched alias '${_semantic_alias}'" >&2
                if [[ -n "$_semantic_files" ]]; then
                    echo "  主要ファイル: ${_semantic_files}" >&2
                fi
                break
            fi
        done
    done <<< "$_semantic_rows"
}

# --- Check 18: 研究cmd道具明示チェック（dm-signal研究cmd対象 — WARNING） ---
# 起源: cmd_1822事故 — 将軍がACに研究エンジンのCLI引数を書かず忍者がhang
# 目的: dm-signal研究cmdでAC内にスクリプトパスが未記載の場合WARNING表示（WARN_COUNTに加算しない）
# カタログ: context/dm-signal-ops.md §18 参照
check_research_tool_explicit() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # project=dm-signalのみ対象
    local PROJECT_ID
    PROJECT_ID="$(cmd_block_get_field "project")"
    [[ "$PROJECT_ID" != "dm-signal" ]] && return 0

    # title + command本文から研究ツールキーワード検出
    local FULL_CMD TITLE_LINE SEARCH_TEXT WF_SEARCH_TEXT
    FULL_CMD=$(echo "$CMD_BLOCK_NC" | awk '
        /^\s*command:\s*\|/ { found=1; next }
        /^\s*command:\s*[^|]/ { found=1; sub(/^\s*command:\s*/, ""); print; next }
        found && /^\s{4,}/ { print; next }
        found && /^\s*[a-zA-Z_][a-zA-Z0-9_]*:/ { exit }
    ')
    TITLE_LINE=$(echo "$CMD_BLOCK_NC" | grep '^\s*title:' | head -1)
    SEARCH_TEXT="${TITLE_LINE}
${FULL_CMD}"

    show_semantic_index_matches "$SEARCH_TEXT"

    local HIT_GS=false HIT_WF=false
    local GS_PATH_CANDIDATE WF_PATH_CANDIDATE
    GS_PATH_CANDIDATE=$(printf '%s\n' "$SEARCH_TEXT" | grep -oE 'scripts/analysis/grid_search/run_077_[A-Za-z0-9_]+\.py' | head -1 || true)
    WF_PATH_CANDIDATE=$(printf '%s\n' "$SEARCH_TEXT" | grep -oE 'outputs/scripts/l1_alm_wf_engine\.py|[^[:space:]"]+wf_engine[^[:space:]"]*\.py' | head -1 || true)
    # cmd_2172: WF四神/WF選別はWF engine実行ではなく分類ラベル。説明文だけでの誤検出を避ける。
    WF_SEARCH_TEXT=$(printf '%s\n' "$SEARCH_TEXT" | sed -E 's/WF(四神|選別)//g')

    # GS検出: bare grid_search は outputs/grid_search/*.csv を誤検出するため、
    # 研究スクリプト参照または明示的なGS文言に限定する。
    # "GS CSV" = データファイル参照であり研究スクリプト実行ではないため除外(cmd_2227 FP修正)
    local GS_SEARCH_TEXT
    GS_SEARCH_TEXT=$(printf '%s\n' "$SEARCH_TEXT" | grep -v 'outputs/grid_search' | sed -E 's/GS[[:space:]]*CSV//g' || true)
    if echo "$GS_SEARCH_TEXT" | grep -qE 'run_077|scripts/analysis/grid[_-]search|grid[_-]search/run|グリッドサーチ|[[:space:]]GS[[:space:]　]|[[:space:]]GS新規|忍法GS|GS[[:space:]を]|GS[[:space:]の]'; then
        HIT_GS=true
    fi
    if [[ "$HIT_GS" == true ]] && [[ -z "$GS_PATH_CANDIDATE" ]] \
        && printf '%s\n' "$SEARCH_TEXT" | grep -q 'outputs/grid_search' \
        && printf '%s\n' "$SEARCH_TEXT" | grep -q '偵察'; then
        HIT_GS=false
    fi

    # WF検出: l1_alm_wf_engine / walk.forward / WF(大文字) / ウォークフォワード
    if echo "$WF_SEARCH_TEXT" | grep -qE 'l1_alm_wf_engine|wf_engine|walk[_-]forward|ウォークフォワード|[[:space:]]WF[[:space:]　]|窓WF|WF[[:space:]を]|WFで'; then
        HIT_WF=true
    fi

    # どちらも検出されなければ対象外
    [[ "$HIT_GS" == false && "$HIT_WF" == false ]] && return 0

    # ACセクションを抽出
    local AC_SECTION
    AC_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
        /acceptance_criteria:/ { found=1; next }
        found && /^    - / { print; next }
        found && /^      / { print; next }
        found { exit }
    ')
    [[ -z "$AC_SECTION" ]] && AC_SECTION="$CMD_BLOCK_NC"

    local HIT=false

    # GS検出 → ACにrun_077が含まれるか確認
    if [[ "$HIT_GS" == true ]]; then
        if ! echo "$AC_SECTION" | grep -qE 'run_077|grid_search/run|shin_shijin_l1_gs'; then
            if [[ "$HIT" == false ]]; then
                echo "WARNING: 研究cmd道具明示チェック(Check 18)。ACに研究スクリプトパスが未記載(cmd_1822教訓)" >&2
                HIT=true
            fi
            echo "  GS道具: scripts/analysis/grid_search/run_077_{忍法}.py をACに明記せよ" >&2
            if [[ -n "$GS_PATH_CANDIDATE" ]]; then
                echo "  ACパス候補: ${GS_PATH_CANDIDATE}" >&2
            fi
            echo '  例: "run_077_oikaze.py --universe config/portfolio_universes/XXX.yaml を実行"' >&2
        fi
    fi

    # WF検出 → ACにl1_alm_wf_engineが含まれるか確認
    if [[ "$HIT_WF" == true ]]; then
        if ! echo "$AC_SECTION" | grep -qE 'l1_alm_wf_engine|wf_engine'; then
            if [[ "$HIT" == false ]]; then
                echo "WARNING: 研究cmd道具明示チェック(Check 18)。ACに研究スクリプトパスが未記載(cmd_1822教訓)" >&2
                HIT=true
            fi
            echo "  WF道具: outputs/scripts/l1_alm_wf_engine.py をACに明記せよ" >&2
            if [[ -n "$WF_PATH_CANDIDATE" ]]; then
                echo "  ACパス候補: ${WF_PATH_CANDIDATE}" >&2
            fi
            echo '  例: "l1_alm_wf_engine.py --batch-csvs <paths> --multi-is --cmd-id XXX を実行"' >&2
        fi
    fi

    if [[ "$HIT" == true ]]; then
        echo "  道具カタログ: context/dm-signal-ops.md §18 参照" >&2
        record_warn_reason "研究cmd道具未記載" "check=check_research_tool_explicit"
    fi
}

check_research_tool_explicit

# --- Quality Summary (品質パターン表示) ---
show_quality_summary() {
    local QUALITY_LOG="$QUALITY_LOG_FILE"

    # AC3: ファイル不存在・空→スキップ（エラーなし）
    if [[ ! -f "$QUALITY_LOG" ]] || [[ ! -s "$QUALITY_LOG" ]]; then
        return 0
    fi

    # Single awk pass: parse entries, output AC1 summary + AC2 warnings
    awk '
    /^ *- cmd_id:/ { n++ }
    /karo_rework:/ {
        val = $2; gsub(/[" ]/, "", val)
        if (val == "yes") rw[n] = 1
    }
    /ninja_blockers:/ {
        val = $2 + 0
        if (val > 0) bl[n] = 1
    }
    /supplementary_cmds:/ {
        val = $2 + 0
        if (val > 0) sp[n] = 1
    }
    END {
        if (n == 0) exit

        # AC1: 直近10件サマリー（10件未満ならあるだけ）
        s10 = (n > 10) ? n - 9 : 1
        c10 = n - s10 + 1
        rw10 = 0; bl10 = 0; sp10 = 0
        for (i = s10; i <= n; i++) {
            rw10 += rw[i]; bl10 += bl[i]; sp10 += sp[i]
        }
        printf "品質: %dcmd中 rework=%d blocker=%d supplementary=%d\n", c10, rw10, bl10, sp10

        # AC2: 直近5件でパターン警告
        s5 = (n > 5) ? n - 4 : 1
        c5 = n - s5 + 1
        if (c5 < 2) exit
        r5 = 0; b5 = 0; p5 = 0
        for (i = s5; i <= n; i++) {
            r5 += rw[i]; b5 += bl[i]; p5 += sp[i]
        }
        rr = (r5 / c5) * 100
        br = (b5 / c5) * 100
        sr = (p5 / c5) * 100
        if (rr > 20) printf "WARNING: rework率%.0f%%。AC設計の精度を確認せよ\n", rr
        if (br > 10) printf "WARNING: blocker率%.0f%%。前提条件の確認を強化せよ\n", br
        if (sr > 30) printf "WARNING: 補足cmd率%.0f%%。スコープ漏れの傾向\n", sr
    }
    ' "$QUALITY_LOG" || true
}

show_quality_summary

# --- Gunshi直近指摘表示（informational — WARN_COUNTに加算しない） ---
show_gunshi_recent_issues() {
    local GUNSHI_LOG="$PROJECT_DIR/logs/gunshi_review_log.yaml"

    # AC3: ファイル不存在/空→スキップ
    if [[ ! -f "$GUNSHI_LOG" ]] || [[ ! -s "$GUNSHI_LOG" ]]; then
        return 0
    fi

    # AC1+AC2: 直近REQ_CHANGES/FAILを最大3件表示
    awk '
    /^- cmd_id:/ {
        n++
        cmd[n] = $3
    }
    /^  verdict:/ {
        v = $2
        gsub(/#.*/, "", v)
        gsub(/[" ]/, "", v)
        verdict[n] = v
    }
    /^  findings_summary:/ {
        s = $0
        sub(/^  findings_summary: *"?/, "", s)
        sub(/"$/, "", s)
        summary[n] = substr(s, 1, 60)
    }
    END {
        m = 0
        for (i = 1; i <= n; i++) {
            if (verdict[i] == "REQUEST_CHANGES" || verdict[i] == "FAIL") {
                issues[++m] = i
            }
        }
        if (m == 0) exit
        start = (m > 3) ? m - 2 : 1
        for (j = start; j <= m; j++) {
            k = issues[j]
            printf "軍師直近指摘: %s %s — %s\n", cmd[k], verdict[k], summary[k]
        }
    }
    ' "$GUNSHI_LOG" 2>/dev/null || true
}

show_gunshi_recent_issues

# --- 軍師ペイン活動状況表示（informational — WARN_COUNTに加算しない） ---
show_gunshi_pane_status() {
    local PANE_TARGET="shogun:2.2"

    # ペイン存在確認（tmux未起動 or ペインなし → スキップ）
    if ! tmux capture-pane -t "$PANE_TARGET" -p >/dev/null 2>&1; then
        return 0
    fi

    # 最終3行をキャプチャ（空行を除去してから末尾3行）
    local PANE_CONTENT
    PANE_CONTENT=$(tmux capture-pane -t "$PANE_TARGET" -p 2>/dev/null | sed '/^$/d' | tail -n 3) || return 0

    if [[ -n "$PANE_CONTENT" ]]; then
        echo "軍師ペイン(最終3行):"
        while IFS= read -r line; do
            echo "  $line"
        done <<< "$PANE_CONTENT"
    fi
}

show_gunshi_pane_status

# AC_TEXT: acceptance_criteriaセクション全行を結合（Check 19/20で使用）
# description:形式とAC1:"..."形式の両方をカバー
AC_TEXT=$(echo "$CMD_BLOCK" | awk '
  /acceptance_criteria:/ { found=1; next }
  found && /^[[:space:]]{0,4}[a-z_]+:/ && !/^[[:space:]]*AC[0-9]/ && !/^[[:space:]]*description:/ { exit }
  found { print }
' || true)

# --- Check 19: パリティcmdのP1-P6全基準チェック（WARN） ---
# 本番DB操作cmd（パリティ/登録/recalculate含む）のACにP1-P6が網羅されているか
# トリガー対象はtitle+purpose+AC_TEXTのみ（not_in_scopeの否定文による誤検知防止）
# FP修正(2026-04-27): descriptionにPARITY_PATH等の変数名があると偽陽性。title+purposeのみでトリガー
# FP修正(2026-04-29): 過去形コンテキスト(修正後/修正版/修正済み/完了)の行を除外して分析cmdの誤検出を防ぐ
_CHECK19_TRIGGER=$(echo "$CMD_BLOCK" | grep -E 'title:|purpose:' | grep -viE '修正後|修正版|修正済み|完了' || true)
# scope_mode=SCOUT/VERIFYはDB変更なし→パリティP3-P5不要
_CHECK19_SCOPE="$(cmd_block_get_field "scope_mode")"
if [[ "${_CHECK19_SCOPE}" != "SCOUT" && "${_CHECK19_SCOPE}" != "VERIFY" ]] && echo "$_CHECK19_TRIGGER" | grep -qiE 'パリティ|parity|登録.*本番|本番.*登録|recalculate.*sync'; then
    PARITY_MISSING=()
    # P1: holding_signal
    if ! echo "$AC_TEXT" | grep -qi 'holding_signal'; then
        PARITY_MISSING+=("P1:holding_signal完全一致")
    fi
    # P2: monthly_return
    if ! echo "$AC_TEXT" | grep -qi 'monthly_return.*1e-6\|monthly_return.*差\|return.*一致'; then
        PARITY_MISSING+=("P2:monthly_return完全一致(1e-6)")
    fi
    # P3: 既存PF不変
    if ! echo "$AC_TEXT" | grep -qi 'ゴールデン\|golden\|既存.*不変\|不変.*確認'; then
        PARITY_MISSING+=("P3:既存PF不変(ゴールデンデータ)")
    fi
    # P4: FE UI
    if ! echo "$AC_TEXT" | grep -qi 'FE\|UI\|frontend\|Dashboard\|ページ'; then
        PARITY_MISSING+=("P4:FE UI全ページ整合")
    fi
    # P5: hide-first
    if ! echo "$AC_TEXT" | grep -qi 'hide\|is_visible\|非表示'; then
        PARITY_MISSING+=("P5:hide-first原則")
    fi
    if [[ ${#PARITY_MISSING[@]} -gt 0 ]]; then
        echo "WARNING: パリティcmdのAC基準欠落を検出(dm-signal-ops.md §6-7 チェックリスト参照)"
        for m in "${PARITY_MISSING[@]}"; do
            echo "  ✗ $m"
        done
        # Level5: 不足ACテンプレートを自動提案(コピペで追加可能)
        echo "  ─── 追加AC候補(コピペ用) ───"
        for m in "${PARITY_MISSING[@]}"; do
            case "$m" in
                P1*) echo "  - \"holding_signal全PF完全一致を実API diffで検証\"" ;;
                P2*) echo "  - \"monthly_returns全PF全期間の差分が1e-6以内をAPI diffで検証\"" ;;
                P3*) echo "  - \"既存PFのゴールデンデータ不変を確認(変更対象外PFに影響なし)\"" ;;
                P4*) echo "  - \"FE Dashboard/各ページで表示が正常であることをCDP確認\"" ;;
                P5*) echo "  - \"hide-first原則: 新PFはis_visible=falseで登録し確認後に公開\"" ;;
            esac
        done
        echo "  ─────────────────────────"
        record_warn_reason "parity_ac_missing" "check=check_parity_ac_requirements"
    fi
fi

# --- Check 20: assumptionsフィールド検査（BLOCK昇格 cmd_1906） ---
# 起源: cmd_1905 — 暗黙前提を構造的に可視化し、未検証前提がcmdに混入するのを防ぐ
# 目的: 全cmdにassumptionsがない/未検証前提があるcmdをBLOCKし、暗黙前提の混入を防ぐ（cmd_2157: AC≥3→全cmd）
# cmd_1906: trust:unverified→BLOCK昇格。trust:verified+sourceにファイルパスがある場合実在確認
if true; then
    # assumptions存在チェックはpreflight(Check 3)済み。以下は内容検証のみ
    if echo "$CMD_BLOCK_NC" | grep -q "assumptions:"; then
        # AC1: trust: unverified が含まれる場合BLOCK(exit 1)
        if echo "$CMD_BLOCK_NC" | grep -A5 "assumptions:" | grep -q "trust:.*unverified\|trust: unverified"; then
            record_block_reason "未検証前提あり。現物確認してtrust:verifiedに変更せよ"
            abort_if_block_immediate || exit 1
        fi
        # AC2: trust:verified + sourceにファイルパスがある場合、プロジェクトWD内の実在確認
        _ASSUMP_PROJECT_ID="$(cmd_block_get_field "project")"
        [[ -z "${_ASSUMP_PROJECT_ID:-}" ]] && _ASSUMP_PROJECT_ID=$(awk '/^current_project:/{print $2}' "$PROJECT_DIR/config/projects.yaml" 2>/dev/null || true)
        if [[ -n "${_ASSUMP_PROJECT_ID:-}" ]]; then
            _ASSUMP_PROJECT_WD=$(awk -v id="$_ASSUMP_PROJECT_ID" '
                /^  - id:/ { current_id = $3; gsub(/"/, "", current_id) }
                /^    path:/ && current_id == id { gsub(/.*path: *"?/, ""); gsub(/"$/, ""); print; exit }
            ' "$PROJECT_DIR/config/projects.yaml" 2>/dev/null || true)
        fi
        if [[ -n "${_ASSUMP_PROJECT_WD:-}" ]]; then
            _ASSUMP_VERIFIED_PATHS=$(echo "$CMD_BLOCK_NC" | python3 -c "
import sys, re
content = sys.stdin.buffer.read().decode('utf-8', errors='replace')
lines = content.split('\n')
in_assumptions = False
assumptions_indent = -1
current = {}
entries = []
for line in lines:
    m_aline = re.match(r'^(\s*)assumptions\s*:', line)
    if m_aline and not in_assumptions:
        in_assumptions = True
        assumptions_indent = len(m_aline.group(1))
        continue
    if in_assumptions:
        # Exit if line is non-empty and at same/lower indentation as assumptions: (peer/parent key)
        if line.strip():
            cur_indent = len(line) - len(line.lstrip())
            if cur_indent <= assumptions_indent:
                in_assumptions = False
                if current: entries.append(dict(current))
                current = {}
                continue
        if re.match(r'\s*-\s', line):
            if current:
                entries.append(dict(current))
            current = {}
        # GP-216: source/trust以外の任意フィールド(tool_verified/csv_paths等)もキャプチャ
        m = re.search(r'^\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.+)', line)
        if m:
            current[m.group(1)] = m.group(2).strip().strip('\"').strip(\"'\")
if current: entries.append(current)
pat = re.compile(r'[A-Za-z0-9_/-]+\.(py|ts|tsx|js|jsx|sh|bash|yaml|yml|json|sql|html|css|toml|cfg|env)')
for e in entries:
    trust = e.get('trust', '')
    if 'verified' in trust and 'unverified' not in trust:
        # GP-216: source/tool_verified/csv_paths等の明示的パスフィールドからパス抽出
        # claim はフリーテキストのため除外（LS033: ファイル名パターン誤検出防止）
        skip_keys = {'trust', 'claim'}
        for key, val in e.items():
            if key in skip_keys:
                continue
            for m in pat.finditer(val):
                print(m.group(0))
" 2>/dev/null || true)
            if [[ -n "${_ASSUMP_VERIFIED_PATHS:-}" ]]; then
                _ASSUMP_HAS_MISSING=false
                while IFS= read -r fpath; do
                    [[ -z "$fpath" ]] && continue
                    if [[ ! -e "$_ASSUMP_PROJECT_WD/$fpath" ]]; then
                        if [[ "$_ASSUMP_HAS_MISSING" == false ]]; then
                            record_block_reason "assumptions sourceのファイルパスが存在しません:"
                            _ASSUMP_HAS_MISSING=true
                        fi
                        echo "  ✗ $fpath (in $_ASSUMP_PROJECT_WD)" >&2
                    fi
                done <<< "$_ASSUMP_VERIFIED_PATHS"
                if [[ "$_ASSUMP_HAS_MISSING" == true ]]; then
                    echo "  現物確認してからcmd_save.shを再実行せよ" >&2
                    abort_if_block_immediate || exit 1
                fi
            fi
        fi
        _ASSUMP_CLAIMS_MISSING_DATES="$(collect_assumption_claims_missing_dates "$CMD_BLOCK_NC")"
        if [[ -n "${_ASSUMP_CLAIMS_MISSING_DATES//[[:space:]]/}" ]]; then
            echo "WARNING: assumptions claimに日付がありません。claimへ YYYY-MM-DD を含めて時系列を固定してください" >&2
            while IFS= read -r _assump_claim; do
                [[ -z "$_assump_claim" ]] && continue
                echo "  - $_assump_claim" >&2
            done <<< "$_ASSUMP_CLAIMS_MISSING_DATES"
            record_warn_reason "assumptions claimに日付なし" "check=assumptions_claim_date"
        fi
        _ASSUMP_NEGATIVE_CLAIMS_MISSING_GREP="$(collect_negative_claims_missing_grep_evidence "$CMD_BLOCK_NC")"
        if [[ -n "${_ASSUMP_NEGATIVE_CLAIMS_MISSING_GREP//[[:space:]]/}" ]]; then
            echo "WARNING: 否定的前提キーワードを検出しました。assumptions claimにgrep/rg反証結果を記載してください" >&2
            echo "  対象キーワード: 未実装 / 存在しない / 仕組みがない / 未対応" >&2
            echo "  例: claim: \"2026-05-10時点で grep -rn 'pattern' scripts/ → 0件\"" >&2
            while IFS= read -r _assump_claim; do
                [[ -z "$_assump_claim" ]] && continue
                echo "  - $_assump_claim" >&2
            done <<< "$_ASSUMP_NEGATIVE_CLAIMS_MISSING_GREP"
            record_warn_reason "否定的前提claimにgrep反証結果なし" "check=assumptions_negative_claim_grep_evidence"
        fi
        _ASSUMP_BULLETIN_COUNT_CLAIMS_MISSING_GREP="$(collect_bulletin_count_claims_missing_grep_evidence "$CMD_BLOCK_NC")"
        if [[ -n "${_ASSUMP_BULLETIN_COUNT_CLAIMS_MISSING_GREP//[[:space:]]/}" ]]; then
            echo "WARNING: bulletin由来の件数claimを検出しました。assumptions claimにgrep/rg検証結果を記載してください" >&2
            echo "  例: claim: \"2026-05-15時点で grep -n 'blt_...' queue/bulletin_board.yaml → 1件\"" >&2
            while IFS= read -r _assump_claim; do
                [[ -z "$_assump_claim" ]] && continue
                echo "  - $_assump_claim" >&2
            done <<< "$_ASSUMP_BULLETIN_COUNT_CLAIMS_MISSING_GREP"
            record_warn_reason "bulletin由来件数claimにgrep検証結果なし" "check=assumptions_bulletin_count_grep_evidence"
        fi
        check_measurement_env_info
    fi
fi

# --- Check 20.5: 計測/研究cmdのタイムボックス欄要求（WARN） ---
# 起源: LG019 — 研究/計測cmdの実行時間見積がなく、CTX圧迫やOOMを入口で防げない
# 目的: 時間コスト関連cmdに timeout_minutes を明示させ、無制限の計測・探索を防ぐ
check_timebox_minutes_required() {
    [[ -n "${CMD_BLOCK_NC:-}" ]] || return 0

    local SEARCH_TEXT COMMAND_TEXT TIMEOUT_MINUTES FIRST_HIT
    COMMAND_TEXT=$(printf '%s\n' "$CMD_BLOCK_NC" | awk '
        /^[[:space:]]*command:[[:space:]]*\|?[[:space:]]*$/ { in_command=1; next }
        in_command && /^[[:space:]]{4}[a-zA-Z_][a-zA-Z0-9_]*:/ && !/^[[:space:]]*- / { exit }
        in_command { print }
        /^[[:space:]]*command:[[:space:]]*[^|]/ {
            line=$0
            sub(/^[[:space:]]*command:[[:space:]]*/, "", line)
            print line
        }
    ')
    SEARCH_TEXT="$(cmd_block_get_field "purpose")
${COMMAND_TEXT}
${AC_TEXT:-}"

    FIRST_HIT=$(printf '%s\n' "$SEARCH_TEXT" | grep -iE 'benchmark|計測|研究|grid[_-]?search|探索|見積|見込み|profil' | head -1 || true)
    [[ -n "${FIRST_HIT:-}" ]] || return 0

    TIMEOUT_MINUTES="$(cmd_block_get_field "timeout_minutes")"
    if [[ -z "${TIMEOUT_MINUTES//[[:space:]]/}" ]]; then
        TIMEOUT_MINUTES="$(printf '%s\n' "$CMD_BLOCK_NC" | awk '
            /^[[:space:]]*timeout_minutes:[[:space:]]*/ {
                line=$0
                sub(/^[[:space:]]*timeout_minutes:[[:space:]]*/, "", line)
                print line
                exit
            }
        ')"
    fi
    local TIMEOUT_MINUTES_CLEAN
    TIMEOUT_MINUTES_CLEAN="${TIMEOUT_MINUTES//[[:space:]\"]/}"
    TIMEOUT_MINUTES_CLEAN="${TIMEOUT_MINUTES_CLEAN//\'/}"
    if [[ -n "$TIMEOUT_MINUTES_CLEAN" ]]; then
        return 0
    fi

    echo "WARNING: 計測/研究/見積cmdにtimeout_minutes未記入(LG019)" >&2
    echo "  → timeout_minutes: <想定実行時間上限(分)> をcmdに記入してください" >&2
    echo "  → 検出行: $(printf '%s' "$FIRST_HIT" | sed -E 's/^[[:space:]-]*(description|check|purpose|command):[[:space:]]*//; s/^\"//; s/\"$//' | cut -c1-100)" >&2
    echo "  check=check_timebox_minutes_required" >&2
    record_warn_reason "計測研究cmd timeout_minutes未記入" "check=check_timebox_minutes_required"
}

check_timebox_minutes_required

# --- Check 21: ACの数値絶対値WARN検出（informational — WARN_COUNTに加算しない） ---
# 起源: cmd_1910事故 — ACに「テスト数=118」のような固定値を記載し、並行cmdで即陳腐化
# 目的: AC description内の絶対値パターンを検出し、相対条件への書換えを促す
check_ac_absolute_literals() {
    [[ -z "${AC_TEXT:-}" ]] && return 0

    local ABSOLUTE_HITS
    ABSOLUTE_HITS=$(echo "$AC_TEXT" | grep -iE \
        '=[[:space:]]*[0-9]+|テスト数[[:space:]]*[=:：]?[[:space:]]*[0-9]+|[0-9]+(件|個|本|行|回|分|秒|時間|箇所|テスト)([[:space:]]*(PASS|成功|通過))?|ゼロ' \
        || true)
    [[ -z "$ABSOLUTE_HITS" ]] && return 0

    echo "WARN: ACに数値絶対値パターンを検出。並行配備時に陳腐化リスクあり(cmd_1910教訓)" >&2
    echo "  → 相対条件(例: 減少しないこと)への書換えを検討せよ。Check 21はinformationalのみ" >&2
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "  → $(echo "$line" | sed -E 's/^[[:space:]-]*description:[[:space:]]*//; s/^\"//; s/\"$//' | cut -c1-100)" >&2
    done <<< "$ABSOLUTE_HITS"
}

extract_command_text_block() {
    [[ -n "${CMD_BLOCK_NC:-}" ]] || return 0

    printf '%s\n' "$CMD_BLOCK_NC" | awk '
        /^[[:space:]]*command:[[:space:]]*\|?[[:space:]]*$/ { in_command=1; next }
        in_command && /^[[:space:]]{4}[a-zA-Z_][a-zA-Z0-9_]*:/ && !/^[[:space:]]*- / { exit }
        in_command { print }
        /^[[:space:]]*command:[[:space:]]*[^|]/ {
            line=$0
            sub(/^[[:space:]]*command:[[:space:]]*/, "", line)
            print line
        }
    '
}

collect_numeric_derivation_source_evidence() {
    [[ -n "${CMD_BLOCK_NC:-}" ]] || return 0

    printf '%s\n' "$CMD_BLOCK_NC" | awk '
        /^[[:space:]]*quality_gate:/ { in_qg=1; next }
        in_qg && /^[[:space:]]+q5_verified_source:/ {
            if ($0 ~ /^[[:space:]]*q5_verified_source:/) print
        }
        /^[[:space:]]*assumptions:/ {
            in_assumptions=1
            match($0, /^[ ]*/)
            assumptions_indent=RLENGTH
            next
        }
        in_assumptions {
            match($0, /^[ ]*/)
            cur_indent=RLENGTH
            if ($0 !~ /^[[:space:]]*$/ && cur_indent <= assumptions_indent) {
                in_assumptions=0
            } else {
                print
            }
        }
    '
}

numeric_derivation_source_evidence_exists() {
    local evidence_text
    evidence_text="$(collect_numeric_derivation_source_evidence)"
    [[ -n "${evidence_text//[[:space:]]/}" ]] || return 1

    if ! printf '%s\n' "$evidence_text" | grep -qiE 'grep|rg|wc|awk|sed|find|python|bash|計測|測定|実測|benchmark|ベンチ'; then
        return 1
    fi
    printf '%s\n' "$evidence_text" | grep -qE '→|->|=>|[0-9]+[[:space:]]*(件|行|個|本|箇所|matches?|lines?)|0件|0[[:space:]]+lines?'
}

check_numeric_literal_derivation_source_info() {
    local search_text numeric_hits first_hit
    search_text="$(extract_acceptance_criteria_block; extract_command_text_block)"
    [[ -n "${search_text//[[:space:]]/}" ]] || return 0

    numeric_hits="$(printf '%s\n' "$search_text" | grep -E '(^|[^[:alnum:]_])([0-9]{3,}|L[0-9]+)([^[:alnum:]_]|$)' || true)"
    [[ -n "$numeric_hits" ]] || return 0
    numeric_derivation_source_evidence_exists && return 0

    first_hit="$(printf '%s\n' "$numeric_hits" | head -n 1 | sed -E 's/^[[:space:]-]*(description|check|id|command):[[:space:]]*//; s/^"//; s/"$//' | cut -c1-100)"
    echo "INFO: AC/command内に数値リテラルを検出。算出元コマンド+結果の記載を推奨(LG020)" >&2
    echo "  → assumptions claim または q5_verified_source に grep/rg/wc等の算出元と結果を記載してください" >&2
    echo "  → ${first_hit}" >&2
}

count_acceptance_criteria_items() {
    local ac_block
    ac_block="$(extract_acceptance_criteria_block)"
    [[ -n "$ac_block" ]] || {
        printf '0'
        return 0
    }

    printf '%s\n' "$ac_block" | awk '
        /^[[:space:]]*-[[:space:]]/ { c++; next }
        /^[[:space:]]*(AC|ac)?[0-9]+:/ { c++; next }
        END { print c+0 }
    '
}

check_ac_phase_mixing() {
    local ac_block
    ac_block="$(extract_acceptance_criteria_block)"
    [[ -n "${ac_block//[[:space:]]/}" ]] || return 0

    # AC単位の文脈判定: 同一AC内にimpl+measure/deliveryが共起する場合のみWARN
    # 異なるAC間にまたがる場合は正当(実装ACとテストACの共存)
    local mixing_found
    mixing_found="$(printf '%s\n' "$ac_block" | awk '
    function check_buf(text,    lt) {
        if (text == "") return
        lt = tolower(text)
        if (lt !~ /実装|追加|修正|改修|変更|作成|導入|implement|implementation|add|fix|modify|change|create|introduce/) return
        if (lt ~ /cdp|計測|測定|実測|measure|measurement|benchmark|ベンチ/ ||
            lt ~ /commit|push|deploy|コミット|デプロイ/) { print "FOUND" }
    }
    BEGIN { min_indent = -1; buf = "" }
    {
        if (min_indent == -1 && /^[[:space:]]*- /) {
            s = $0; gsub(/[^ ].*/, "", s); min_indent = length(s)
        }
        s = $0; gsub(/[^ ].*/, "", s)
        if (min_indent >= 0 && length(s) == min_indent && substr($0, min_indent+1, 2) == "- ") {
            check_buf(buf); buf = $0 "\n"
        } else {
            buf = buf $0 "\n"
        }
    }
    END { check_buf(buf) }
    ')"

    [[ -n "$mixing_found" ]] || return 0

    local impl_hits measure_hits delivery_hits
    impl_hits="$(printf '%s\n' "$ac_block" | grep -inE '実装|追加|修正|改修|変更|作成|導入|implement|implementation|add|fix|modify|change|create|introduce' || true)"
    measure_hits="$(printf '%s\n' "$ac_block" | grep -inE 'CDP|計測|測定|実測|measure|measurement|benchmark|ベンチ' || true)"
    delivery_hits="$(printf '%s\n' "$ac_block" | grep -inE 'commit|push|deploy|コミット|デプロイ' || true)"

    echo "WARN: ACフェーズ混在を検出。同一AC内に実装と計測/commit/deployが共起しています" >&2
    echo "  実装ACと後続フェーズACはcmdを分割せよ(cmd_2300教訓)" >&2
    echo "  実装側: $(printf '%s\n' "$impl_hits" | head -n 2 | tr '\n' ' ')" >&2
    if [[ -n "$measure_hits" ]]; then
        echo "  計測側: $(printf '%s\n' "$measure_hits" | head -n 2 | tr '\n' ' ')" >&2
    fi
    if [[ -n "$delivery_hits" ]]; then
        echo "  commit/deploy側: $(printf '%s\n' "$delivery_hits" | head -n 2 | tr '\n' ' ')" >&2
    fi
    # Level5: フェーズ分割テンプレート提案
    echo "  ─── 分割案(コピペ用) ───" >&2
    echo "  AC-impl: 「{実装内容}。batsテストPASS。commit」" >&2
    echo "  AC-verify: 「{計測/CDP確認/deploy}。結果を報告」" >&2
    echo "  ─────────────────────────" >&2
    record_warn_reason "ac_phase_mixing" "check=check_ac_phase_mixing"
}

check_ac_test_scope() {
    local ac_block scope_hits

    ac_block="$(extract_acceptance_criteria_block)"
    [[ -n "${ac_block//[[:space:]]/}" ]] || return 0

    # スコープ未指定のテスト全件条件を検出
    # FP除外: 変更対象/関連テスト/ファイル名/.bats/pre-existing/限定テスト群を含む行はスコープ済みとみなし除外
    scope_hits="$(printf '%s\n' "$ac_block" | \
        grep -v -iE '(変更対象|対象の関連|関連テスト|pre[_\-]?existing|\.bats|scripts/|DB依存テスト|CI固有テスト|退行確認)' | \
        grep -inE \
        '全[[:space:]]*(テスト|test)[[:space:]]*(PASS|通過|成功|pass|green)|テスト[[:space:]]*全[[:space:]]*(PASS|通過|成功|pass|green)|0[[:space:]]*(failures?|errors?|skips?|失敗|エラー|スキップ)|all[[:space:]]*(tests?|テスト)[[:space:]]*(pass|green|通過)|no[[:space:]]*(failures?|errors?|skips?)' \
        || true)"
    [[ -n "$scope_hits" ]] || return 0

    echo "WARN: ACにスコープ未指定のテスト全件条件を検出。変更対象の関連テストのみに限定すべき" >&2
    printf '%s\n' "$scope_hits" | head -n 5 | while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "  → $(echo "$line" | sed -E 's/^[[:space:]-]*(description|check|id):[[:space:]]*//; s/^\"//; s/\"$//' | cut -c1-100)" >&2
    done
    echo "  修正例: 「全テストPASS」→「変更対象(scripts/cmd_save.sh)の関連テストPASS」" >&2
    echo "  修正例: 「0 failures」→「変更ファイルに対応するテスト(test_cmd_save*.bats等)0 failures」" >&2
    echo "  理由: スコープ未指定のAC=pre-existing failureを全て抱え込み、AC達成不能になりうる(cmd_2342教訓)" >&2
    record_warn_reason "ac_test_scope_too_broad" "check=check_ac_test_scope"
}

check_ac_absolute_literals

# --- Check 21.1: AC/command数値リテラルの算出元記載提案（INFO） ---
# 起源: LG020 — 数値の算出元未確認により、grep結果の対象を誤認した
# 目的: 3桁以上整数またはL行番号参照を検出し、算出元コマンド+結果の明記を促す
check_numeric_literal_derivation_source_info

# --- Check 21.5: ACフェーズ混在検出（WARN） ---
# 起源: cmd_2300事故 — 実装ACとCDP計測ACが1cmdに同居し、実装完了後に計測不能でFAIL
# 目的: 実装フェーズと計測/commit/deployフェーズの同居を検出し、cmd分割を促す
check_ac_phase_mixing

# --- Check 21.6: ACテストスコープ検証（WARN） ---
# 起源: cmd_2342 — ACに「全テストPASS」「0 failures」等のスコープ未指定条件を記載すると
#         pre-existing failureを全て抱え込みAC達成不能になる
# 目的: スコープ未指定のテスト全件条件を検出し、変更対象の関連テストのみへの限定を促す
check_ac_test_scope

# --- Check 22: command欄ステップ数 vs AC数の不整合検出（WARN） ---
# 起源: cmd_1953-1958でcommand欄に(1)(2)(3)(4)の4ステップを書いたがAC2個→忍者がspec/設計書をスキップ
# 原理: command欄の番号付きステップ数 > AC数 = 中間成果物がACに分解されていない可能性
# CoDD固有でなく全cmdに適用。手順が増えれば自動検出(100億パターン対応)
if [[ -n "${CMD_BLOCK_NC:-}" ]]; then
    _CMD_SECTION=$(echo "$CMD_BLOCK_NC" | awk '
        /^[[:space:]]*command:[[:space:]]*\|/ { found=1; next }
        /^[[:space:]]*command:[[:space:]]*[^|]/ { found=1; sub(/^[[:space:]]*command:[[:space:]]*/, ""); print; next }
        found && /^[[:space:]]{4}[a-zA-Z_][a-zA-Z0-9_]*:/ { exit }
        found && /^[[:space:]]{4,}/ { print; next }
    ')
    _STEP_COUNT=$(printf '%s\n' "$_CMD_SECTION" | awk '
        function indent_len(s,    t) { t=s; sub(/[^ ].*$/, "", t); return length(t) }
        /^\s*\([0-9]+\)/ || /^\s*[0-9]+[\.\)]\s/ {
            ind = indent_len($0)
            if (min == "" || ind < min) min = ind
            lines[++n] = $0
            indents[n] = ind
        }
        END {
            for (i = 1; i <= n; i++) if (indents[i] == min) c++
            print c+0
        }
    ')
    _AC_COUNT="$(count_acceptance_criteria_items)"
    if (( _STEP_COUNT > 0 && _STEP_COUNT > _AC_COUNT )); then
        echo "WARN: command欄に${_STEP_COUNT}ステップあるがACは${_AC_COUNT}個。中間成果物がACに分解されていない可能性" >&2
        echo "  忍者はACにないことは実行しない。各ステップの成果物をACに対応させよ" >&2
        # Level5: commandステップからAC候補を自動生成
        echo "  ─── AC候補(commandステップから自動生成) ───" >&2
        printf '%s\n' "$_CMD_SECTION" | awk '
            function indent_len(s,    t) { t=s; sub(/[^ ].*$/, "", t); return length(t) }
            /^\s*\([0-9]+\)/ || /^\s*[0-9]+[\.\)]\s/ {
                ind = indent_len($0)
                if (min == "" || ind < min) min = ind
                lines[++n] = $0
                indents[n] = ind
            }
            END {
                for (i = 1; i <= n; i++) {
                    if (indents[i] != min) continue
                    line = lines[i]
                    sub(/^\s*\(?[0-9]+[\.\)]\s*/, "", line)
                    printf "  - \"%s。binary_check: yes/no\"\n", line
                }
            }
        ' >&2
        echo "  ─────────────────────────" >&2
        record_warn_reason "command_steps_over_ac" "check=check_command_steps_vs_ac"
    fi
fi

# --- Check 22: ACにpush要求があればWARN（忍者はpush禁止） ---
# 根因: 将軍がACに「commit+push」を習慣的に記載→忍者はpush不可→gate BLOCK→家老WA
# cmd_2225/cmd_2226で実証(2026-04-22殿指摘)
if load_cmd_block; then
    _AC_BLOCK="$(extract_acceptance_criteria_block)"
    if printf '%s\n' "$_AC_BLOCK" | grep -qiE '\bpush\b'; then
        echo "WARN: ACに'push'が含まれている。忍者はpush禁止(CLAUDE.md)。'commit'のみに変更せよ" >&2
        echo "  pushは家老が行う。ACに含めると忍者がbinary_checks no→gate BLOCK→毎回WA" >&2
        record_warn_reason "ac_contains_push" "check=check_ac_contains_push"
    fi
fi

# --- Check 23: new_file/new_structure request warning ---
# 目的: ACやcommandに新規ファイル/新規構造作成が含まれるときWARNし、既存活用を促す。
check_new_file_structure_warning() {
    local ac_block command_block search_text hits

    ac_block="$(extract_acceptance_criteria_block)"
    command_block="$(echo "$CMD_BLOCK_NC" | awk '
        /^[[:space:]]*command:[[:space:]]*\|/ { found=1; next }
        /^[[:space:]]*command:[[:space:]]*[^|]/ {
            found=1
            sub(/^[[:space:]]*command:[[:space:]]*/, "")
            print
            next
        }
        found && /^[[:space:]]{4,}/ {
            line=$0
            sub(/^[[:space:]]+/, "", line)
            print line
            next
        }
        found && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*:/ { exit }
    ')"
    search_text="${ac_block}"$'\n'"${command_block}"
    [[ -n "${search_text//[[:space:]]/}" ]] || return 0

    # Filter out quality_gate/diagnosis/assumptions content that may leak into search scope
    # (defensive: extract functions should exclude these, but edge cases exist)
    hits="$(printf '%s\n' "$search_text" | grep -v -E '^\s*(diagnosis|quality_gate|q[0-9]_|assumptions|trust|claim|environment_change|delegated_at):' | grep -inE 'new_file|new_structure|新規ファイル|新規構造|新規作成|新設|新規に.*(作成|追加)|新しい.*(ファイル|構造)' || true)"
    [[ -n "$hits" ]] || return 0

    echo "WARN: new_file/new_structure要求を検出。既存活用できるファイル・構造がないか確認せよ" >&2
    echo "$hits" | head -n 5 >&2
    echo "  既存活用を優先し、新規作成が必要なら理由と既存代替の現物確認をcmdに明記せよ" >&2
    # Level5: 新規ファイル名から既存類似ファイルを自動検索して提案
    local _new_names
    _new_names=$(printf '%s\n' "$hits" | grep -oE '[a-zA-Z_][a-zA-Z0-9_-]*\.(sh|py|yaml|md|tsx?)' | sort -u | head -3)
    if [[ -n "$_new_names" ]]; then
        echo "  ─── 既存類似ファイル候補 ───" >&2
        while IFS= read -r _nf; do
            local _stem="${_nf%.*}" _ext="${_nf##*.}"
            _stem=$(echo "$_stem" | tr '_-' '*')
            local _found
            _found=$(find "$SCRIPT_DIR" -maxdepth 3 -name "*${_stem}*" -o -name "*${_ext}" 2>/dev/null | head -3)
            [[ -n "$_found" ]] && printf '  %s → 類似: %s\n' "$_nf" "$(echo "$_found" | xargs -I{} basename {} | tr '\n' ', ')" >&2
        done <<< "$_new_names"
        echo "  ─────────────────────────" >&2
    fi
    record_warn_reason "new_file_or_structure_requested" "check=check_new_file_structure_warning"
}

if load_cmd_block; then
    check_new_file_structure_warning
fi

# --- Check 3.6b: WARN時environment_change強制（殿指摘2026-04-20） ---
# 目的: WARNが出た=問題がある。次のcmdで同じWARNが出ないように環境に埋め込め。
# Check 3.6(PRIOR_ATTEMPT_COUNT>0)は過去BLOCK後の再PASS用。こちらはWARN初回用。
# 全チェック完了後に配置(WARNは後段のCheckで蓄積されるため)
if (( WARN_COUNT > 0 )) && (( PRIOR_ATTEMPT_COUNT == 0 )); then
    if load_cmd_block; then
        _ENV_CHANGE_WARN="$(echo "$CMD_BLOCK_NC" | awk '/environment_change:/{found=1; sub(/.*environment_change:[[:space:]]*"?/,""); sub(/"?[[:space:]]*$/,""); print; exit} END{if(!found) print ""}')"
        if [[ -z "$_ENV_CHANGE_WARN" ]]; then
            record_block_reason "WARNが${WARN_COUNT}件検出。environment_changeを記載せよ。次のcmdで同じWARNが出ないように環境に何を埋め込むか書け"
            echo '  形式: environment_change: "type=gate|lesson|hook; file=対象パス; pattern=grep検証文字列"' >&2
        else
            # 構造化形式チェック(Check 3.6と同一ロジック)
            if _ENV_WARN_STRUCTURED="$(parse_structured_environment_change "$_ENV_CHANGE_WARN" 2>/dev/null)"; then
                IFS=$'\t' read -r _EW_TYPE _EW_FILE _EW_PATTERN <<< "$_ENV_WARN_STRUCTURED"
                _EW_FILE_RESOLVED="$_EW_FILE"
                [[ "$_EW_FILE_RESOLVED" == /* ]] || _EW_FILE_RESOLVED="$PROJECT_DIR/$_EW_FILE_RESOLVED"
                if ! grep -qE -- "$_EW_PATTERN" "$_EW_FILE_RESOLVED" 2>/dev/null; then
                    record_block_reason "environment_change未実装(WARN対応)。file=${_EW_FILE} に pattern=${_EW_PATTERN} が見つからない"
                fi
            else
                record_block_reason "environment_changeが非構造化(WARN対応)。type=xxx; file=xxx; pattern=xxx の形式で記載せよ"
            fi
        fi
    fi
fi

# --- WARN累計昇格: 同一WARNパターンが繰り返しでBLOCK昇格（cmd_2159） ---
# 目的: WARNを無視し続けるとBLOCKに昇格。WARNを解消しない運用を防ぐ
# 穴2対処(殿指摘2026-04-20): environment_changeを書いたのに同じWARNが再発
#   = 前回の環境変化が無効だった証拠。通常のWARN累計昇格メッセージに加え、
#   「前回のenvironment_changeが効いていない」を明示的にフィードバック。
_WARN_ESCALATE_THRESHOLD=1
if [[ ${#WARN_REASONS[@]} -gt 0 ]]; then
    # カウントを先に(log書込み前)。書込み後だと自分自身をカウントする(閾値1で即BLOCK)
    for _warn_r in "${WARN_REASONS[@]}"; do
        _warn_prior_count=$(count_same_warn_pattern "$_warn_r" 2>/dev/null || echo 0)
        [[ "$_warn_prior_count" =~ ^[0-9]+$ ]] || _warn_prior_count=0
        if (( _warn_prior_count >= _WARN_ESCALATE_THRESHOLD )); then
            log_preflight_autolearn "$_warn_r" "$_warn_prior_count"
            record_block_reason "WARN累計昇格: 「${_warn_r}」が${_warn_prior_count}回繰り返されています。WARNを解消してからcmd_save.shを実行せよ"
            echo "  ★ 前回このWARNに対してenvironment_changeを書いたはず。効いていない。" >&2
            echo "  ★ 前回の環境変化の質が低い(根に到達していない)。なぜなぜ7回で深く掘り直せ。" >&2
        fi
    done
    log_cmd_save_warns
fi

# --- 結果出力 ---
if [[ "$BLOCK_COUNT" -eq 0 && "$WARN_COUNT" -eq 0 ]]; then
    echo "保存確認OK: ${CMD_ID}"
    log_cmd_save_pass
    _BULLETIN_ACTIONED_UPDATED="$(update_bulletin_actioned_by_for_cmd 2>/dev/null || true)"
    if [[ -n "$_BULLETIN_ACTIONED_UPDATED" ]]; then
        echo "  bulletin actioned_by更新: ${_BULLETIN_ACTIONED_UPDATED} → ${CMD_ID}"
    fi
    # status: pending 自動注入（未設定時のみ。cmdライフサイクル追跡の起点）
    _EXISTING_STATUS=$(echo "$CMD_BLOCK" | awk '/status:/{gsub(/.*status: */, ""); gsub(/"/, ""); print; exit}')
    if [[ -z "$_EXISTING_STATUS" ]]; then
        if bash "$SCRIPT_DIR/lib/yaml_field_set.sh" "$QUEUE_FILE" "$CMD_ID" status pending 2>/dev/null; then
            echo "  status: pending — 自動設定"
        fi
    fi
    # 前回cmd_id記録（次回呼出し時のpending昇格チェック用 — Check 1.6）
    echo "$CMD_ID" > "$CMD_SAVE_LAST_CMD_FILE"
    remind_missing_current_cmd_lesson_after_clear
else
    if [[ "$BLOCK_COUNT" -gt 0 ]]; then
        echo "保存確認NG: ${CMD_ID} (${BLOCK_COUNT}件のBLOCK, ${WARN_COUNT}件のWARN)" >&2
    else
        echo "保存確認NG: ${CMD_ID} (${WARN_COUNT}件のWARN)" >&2
    fi
    exit 1
fi
