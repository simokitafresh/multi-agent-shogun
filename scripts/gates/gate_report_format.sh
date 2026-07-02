#!/bin/bash
# semantic-links: [[gate迂回防止]], [[忍者報告品質プロトコル]]
# gate_report_format.sh — 忍者報告YAMLのフォーマット検証
# 目的: 家老の手動フォーマット修正作業を根絶（karo_workarounds 5件連続同一問題）
# 知性の外部化原則: 正しいフォーマットを忍者の記憶に依存させず、自動検証で強制
# Usage: bash scripts/gates/gate_report_format.sh <report_yaml_path>
# Exit: 0=PASS, 1=FAIL(修正必要)

set -e

REPORT_PATH="$1"

if [ -z "$REPORT_PATH" ] || [ ! -f "$REPORT_PATH" ]; then
    echo "FAIL: report file not found: ${REPORT_PATH:-<empty>}" >&2
    exit 1
fi

# executor帰属: 報告YAMLのworker_idを読取り(CLI非依存)
_REPORT_EXECUTOR="${AGENT_ID:-}"
if [ -z "$_REPORT_EXECUTOR" ]; then
    while IFS= read -r _line; do
        case "$_line" in
            worker_id:*)
                _REPORT_EXECUTOR="${_line#worker_id:}"
                _REPORT_EXECUTOR="${_REPORT_EXECUTOR#"${_REPORT_EXECUTOR%%[![:space:]]*}"}"
                _REPORT_EXECUTOR="${_REPORT_EXECUTOR%%#*}"
                _REPORT_EXECUTOR="${_REPORT_EXECUTOR%"${_REPORT_EXECUTOR##*[![:space:]]}"}"
                _REPORT_EXECUTOR="${_REPORT_EXECUTOR%\'}"
                _REPORT_EXECUTOR="${_REPORT_EXECUTOR#\'}"
                _REPORT_EXECUTOR="${_REPORT_EXECUTOR%\"}"
                _REPORT_EXECUTOR="${_REPORT_EXECUTOR#\"}"
                break
                ;;
        esac
    done < "$REPORT_PATH"
fi
_REPORT_EXECUTOR="${_REPORT_EXECUTOR:-unknown}"

# --- PASS cache: skip redundant re-checks on unmodified files (GP-073) ---
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS_CACHE="${GATE_PASS_CACHE_FILE:-$REPO_ROOT/logs/.gate_pass_cache}"
LEARNING_FILE="${GATE_REPORT_FORMAT_LEARNING_FILE:-$REPO_ROOT/logs/gate_report_format_learning.yaml}"
PREFILL_THRESHOLD="${GATE_REPORT_FORMAT_PREFILL_THRESHOLD:-10}"
# perf: cache keyはshellで組み立て、realpath起動を避ける。
if [[ "$REPORT_PATH" = /* ]]; then
    _CANON="$REPORT_PATH"
else
    _CANON="$PWD/${REPORT_PATH#./}"
fi
_MTIME=""
_GATE_MTIME=""
if [[ "${GATE_NO_LOG:-}" != "1" ]] || [ -f "$PASS_CACHE" ]; then
    { read -r _MTIME; read -r _GATE_MTIME; } < <(stat -c '%Y' "$REPORT_PATH" "${BASH_SOURCE[0]}" 2>/dev/null || printf '\n\n')
    if [ -n "$_MTIME" ] && [ -n "$_GATE_MTIME" ] && [ -f "$PASS_CACHE" ] && grep -qF "${_CANON} ${_MTIME} ${_GATE_MTIME}" "$PASS_CACHE" 2>/dev/null; then
        echo "PASS"
        exit 0
    fi
fi

# cmd_2063: autofix + format validation を単一 python3 プロセスで実行
# 旧: bash gate_report_autofix.sh (→python3) + python3 gate_report_format_main.py = 2プロセス
# 新: python3 gate_report_format_combined.py (autofix+validation を1プロセス統合) = 1プロセス
_GATE_DIR="${BASH_SOURCE[0]%/*}"
RESULT=$(python3 "$_GATE_DIR/gate_report_format_combined.py" "$REPORT_PATH" 2>&1) || true

echo "$RESULT"

# --- cmd_3264: auto-commit contamination check (AC2/AC3) ---
# bc:commit=yes時にtarget_path配下の未commit変更・auto-commit巻込みを検出
CONTAMINATION_BLOCK=0
if [[ "$REPORT_PATH" != /tmp/* ]] && [[ "$REPORT_PATH" != *"/tmp/"* ]]; then
    _CC_WORKER="$_REPORT_EXECUTOR"
    _CC_TASK_FILE="$REPO_ROOT/queue/tasks/${_CC_WORKER}.yaml"
    if [ -f "$_CC_TASK_FILE" ]; then
        _CC_CHECK=$(python3 -c "
import os
import yaml, sys
try:
    rdata = yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}
    bc = rdata.get('binary_checks') or {}
    commit = bc.get('commit') or []
    if not (isinstance(commit, list) and commit):
        sys.exit(0)
    if str(commit[0].get('result', '') or '').strip().lower() not in ('yes', 'true'):
        sys.exit(0)
    tdata = yaml.safe_load(open(sys.argv[2], encoding='utf-8')) or {}
    task = tdata.get('task') or tdata
    repo_root = os.path.realpath(sys.argv[3])

    def add_path(paths, value):
        s = str(value or '').strip().lstrip('- ').strip()
        s = s.strip(chr(96)).strip('\"').strip(\"'\")
        if s and s not in ('', 'none', 'null', 'FILL_THIS'):
            paths.append(s)

    report_paths = []
    fm = rdata.get('files_modified') or []
    if isinstance(fm, list):
        for item in fm:
            if isinstance(item, dict):
                add_path(report_paths, item.get('path') or item.get('file') or item.get('name'))
            else:
                add_path(report_paths, item)
    elif isinstance(fm, str):
        add_path(report_paths, fm)

    tp = task.get('target_path') or ''
    paths = []
    if isinstance(tp, list):
        for p in tp:
            add_path(paths, p)
    elif tp:
        add_path(paths, tp)

    # Repo-root target_path is common for infra tasks. Checking the whole repo
    # picks up unrelated parallel-agent work and false-BLOCKs completed reports.
    # In that case, limit AC2 to the files the report claims it modified.
    if report_paths and any(os.path.realpath(os.path.join(repo_root, p)) == repo_root for p in paths):
        paths = report_paths

    for p in paths:
        print(p)
except Exception:
    pass
" "$REPORT_PATH" "$_CC_TASK_FILE" "$REPO_ROOT" 2>/dev/null || true)
        if [ -n "${_CC_CHECK//[[:space:]]/}" ]; then
            # AC2: git status check for uncommitted target_path changes
            _CC_UNCOMMITTED=$(cd "$REPO_ROOT" && git status --porcelain -- $_CC_CHECK 2>/dev/null || true)
            if [ -n "${_CC_UNCOMMITTED//[[:space:]]/}" ]; then
                echo ""
                echo "★ BLOCK(cmd_3264-AC2): ${_CC_WORKER} target_path配下に未commit変更あり:"
                # 注: [ -n ]&&形式はループ末尾空行でset -e死亡する同型バグ族(2026-06-11 precheck 2件と同根)。防御的if/fi化
                while IFS= read -r _ccl; do if [ -n "$_ccl" ]; then echo "  $_ccl"; fi; done <<< "$_CC_UNCOMMITTED"
                # WARN→BLOCK昇格(2026-06-26): commit_missing workaround 3件再発。WARNでは止まらない
                CONTAMINATION_BLOCK=1
                RESULT="${RESULT}"$'\n'"FAIL: cmd_3264-AC2 target_path配下に未commit変更あり"
            fi
            # AC3: auto-commit contamination detection
            # perf: git log --grep --name-only は7800+コミット履歴走査でNTFS上~500ms(cmd_training実測)。
            # 結果はHEAD不変なら同一のため、HEAD SHAキーでmemo化(GP-073 PASS cacheと同型パターン)。
            _CC_AC_CACHE="${GATE_AUTOCOMMIT_CACHE_FILE:-$REPO_ROOT/logs/.gate_autocommit_files_cache}"
            _CC_CUR_HEAD=$(cd "$REPO_ROOT" && git rev-parse HEAD 2>/dev/null) || _CC_CUR_HEAD=""
            _CC_AUTO_FILES=""
            _CC_AC_HIT=0
            if [ -n "$_CC_CUR_HEAD" ] && [ -f "$_CC_AC_CACHE" ]; then
                _CC_AC_CACHED_HEAD=$(head -n 1 "$_CC_AC_CACHE" 2>/dev/null)
                if [ "$_CC_AC_CACHED_HEAD" = "$_CC_CUR_HEAD" ]; then
                    _CC_AUTO_FILES=$(tail -n +2 "$_CC_AC_CACHE" 2>/dev/null)
                    _CC_AC_HIT=1
                fi
            fi
            if [ "$_CC_AC_HIT" -eq 0 ]; then
                _CC_AUTO_FILES=$(cd "$REPO_ROOT" && git log --grep="auto-commit" -10 --format="" --name-only 2>/dev/null | sort -u || true)
                if [ -n "$_CC_CUR_HEAD" ]; then
                    _CC_AC_TMP=$(mktemp "${_CC_AC_CACHE}.XXXXXX" 2>/dev/null) || _CC_AC_TMP=""
                    if [ -n "$_CC_AC_TMP" ]; then
                        { printf '%s\n' "$_CC_CUR_HEAD"; printf '%s\n' "$_CC_AUTO_FILES"; } > "$_CC_AC_TMP" 2>/dev/null \
                            && mv -f "$_CC_AC_TMP" "$_CC_AC_CACHE" 2>/dev/null \
                            || rm -f "$_CC_AC_TMP" 2>/dev/null
                    fi
                fi
            fi
            if [ -n "$_CC_AUTO_FILES" ]; then
                _CC_HITS=""
                while IFS= read -r _tp; do
                    [ -n "$_tp" ] || continue
                    _CC_M=$(printf '%s\n' "$_CC_AUTO_FILES" | grep -E "^${_tp}(/|$)" || true)
                    [ -n "$_CC_M" ] && _CC_HITS="${_CC_HITS}${_CC_M}"$'\n'
                done <<< "$_CC_CHECK"
                _CC_HITS="${_CC_HITS%$'\n'}"
                if [ -n "${_CC_HITS//[[:space:]]/}" ]; then
                    echo ""
                    echo "★ WARN(cmd_3264-AC3): ${_CC_WORKER} target_path配下ファイルがauto-commitに巻き込まれた可能性:"
                    printf '%s\n' "$_CC_HITS" | sort -u | while IFS= read -r _ccl; do
                        [ -n "$_ccl" ] && echo "  $_ccl"
                    done
                fi
            fi
        fi
    fi
fi

# cmd_2130: task_clarity_score WARN (non-blocking)
# perf: moved into gate_report_format_combined.py (Phase 3) to eliminate 2nd python3 subprocess

RESULT_IS_PASS=0
while IFS= read -r _result_line; do
    case "$_result_line" in
        PASS|PASS_NO_IMPROVEMENT)
            RESULT_IS_PASS=1
            break
            ;;
    esac
done <<< "$RESULT"
if [ "$CONTAMINATION_BLOCK" -eq 1 ]; then
    RESULT_IS_PASS=0
fi

# Test/unit fast path: callers that only need stdout + exit code can bypass cache/log/session-state work.
if [[ "${GATE_FAST_EXIT:-0}" = "1" ]]; then
    [ "$RESULT_IS_PASS" -eq 1 ] && exit 0 || exit 1
fi

# --- GATE_NO_LOG guard: skip fire_log writing ---
# cmd_complete_gate.sh等gate呼び出し元スクリプトをベンチマーク/速度計測で反復実行する時はこれを1にせよ。
# 判定(PASS/FAIL)自体は変わらない。付けないと未完成レポートの空欄FAILがgate_fire_log/insightを汚染する
# (cmd_karo_hotfix_bc_result_empty_high_freq_insight_202607020526で確認: kagemaru 3連続実行×6項目=18件)。
if [[ "${GATE_NO_LOG:-}" = "1" ]]; then
    [ "$RESULT_IS_PASS" -eq 1 ] && exit 0 || exit 1
fi

# --- Test report guard: /tmp/ reports are test artifacts, not production signal ---
if [[ "$REPORT_PATH" == /tmp/* ]] || [[ "$REPORT_PATH" == *"/tmp/"* ]]; then
    [ "$RESULT_IS_PASS" -eq 1 ] && exit 0 || exit 1
fi

# --- Gate fire logging (cmd_1279) ---
LOG_FILE="${GATE_FIRE_LOG_FILE:-$REPO_ROOT/logs/gate_fire_log.yaml}"
TS=$(date -Is)

if [ "$RESULT_IS_PASS" -eq 1 ]; then
    # WSL2最適化: gate_fire_log書込みをバックグラウンド化（ログは判定に影響しない）
    (
        flock -w 5 200 2>/dev/null
        printf -- '- ts: "%s", file: "%s", gate: "gate_report_format", result: PASS\n' "$TS" "$REPORT_PATH" >> "$LOG_FILE"
    ) 200>"$LOG_FILE.lock" 2>/dev/null &
    # DB INSERT: eventsテーブルへゲート記録（非ブロック）
    _GRF_CMD_ID="$(basename "${REPORT_PATH%.yaml}" | grep -oE 'cmd_[0-9a-zA-Z_]+' | head -1 || true)"
    # WSL2最適化: memory_db_live_insert を非同期化（DB書込みは判定に影響しない）
    python3 "$REPO_ROOT/scripts/memory_db_live_insert_async.py" gate \
        --gate-name "gate_report_format" --result "PASS" \
        --cmd-id "${_GRF_CMD_ID:-}" --ts "$TS" --detail "" \
        --source-file "$REPORT_PATH" >/dev/null 2>&1 &
    disown 2>/dev/null || true
    _SKILL_LOG="$REPO_ROOT/scripts/skill_execution_log.sh"
    _REPORT_WRITE_SKILL="$REPO_ROOT/skills/report-write/SKILL.md"
    if [ "${SKILL_EXECUTION_PASS_LOG_DISABLE:-0}" != "1" ] && [ -x "$_SKILL_LOG" ]; then
        # WSL2最適化: skill_execution_log.sh を非同期化。
        # SKILL_LOG_SYNC=1 でテスト時は同期実行(CI並列でポーリング競合を回避)。
        if [ "${SKILL_LOG_SYNC:-0}" = "1" ]; then
            bash "$_SKILL_LOG" \
                "report-write" \
                "$_REPORT_EXECUTOR" \
                "PASS" \
                "gate_report_format PASS" \
                "gate_report_format" \
                "$REPORT_PATH" \
                "$_REPORT_WRITE_SKILL" >/dev/null 2>&1 || true
            bash "$_SKILL_LOG" \
                "verdict-check" \
                "$_REPORT_EXECUTOR" \
                "PASS" \
                "gate_report_format verdict/binary_checks PASS" \
                "gate_report_format" \
                "$REPORT_PATH" \
                "$REPO_ROOT/skills/verdict-check/SKILL.md" >/dev/null 2>&1 || true
        else
            bash "$_SKILL_LOG" \
                "report-write" \
                "$_REPORT_EXECUTOR" \
                "PASS" \
                "gate_report_format PASS" \
                "gate_report_format" \
                "$REPORT_PATH" \
                "$_REPORT_WRITE_SKILL" >/dev/null 2>&1 &
            bash "$_SKILL_LOG" \
                "verdict-check" \
                "$_REPORT_EXECUTOR" \
                "PASS" \
                "gate_report_format verdict/binary_checks PASS" \
                "gate_report_format" \
                "$REPORT_PATH" \
                "$REPO_ROOT/skills/verdict-check/SKILL.md" >/dev/null 2>&1 &
        fi
    fi
    # Update PASS cache (GP-073) — WSL2最適化: sed dedup削除、直接append
    # 旧エントリは次回grep時にmtime不一致で自然失効。correctnessに影響なし。
    if [ -n "$_MTIME" ]; then
        echo "${_CANON} ${_MTIME} ${_GATE_MTIME}" >> "$PASS_CACHE" 2>/dev/null || true
    fi
    exit 0
else
    REASONS="$(printf '%s\n' "$RESULT" | awk '/^FAIL: /{sub(/^FAIL: /,""); print; exit}')"
    if [ -z "$REASONS" ]; then
        REASONS="$RESULT"
        REASONS="${REASONS#FAIL: }"
        REASONS="${REASONS%%$'\n'*}"
    fi
    # Traceback: append the actual error line (last non-empty line) for diagnosis
    if [[ "$REASONS" == "Traceback (most recent call last):"* ]]; then
        _LAST_ERR="$(printf '%s\n' "$RESULT" | awk 'NF{line=$0} END{print line}')"
        REASONS="Traceback: ${_LAST_ERR}"
    fi
    REASONS="${REASONS//\"/\\\"}"
    # 中間状態チェック: verdict空/None + binary_checks AC欄0件 → FAILログ記録スキップ
    # 忍者の自己修正後に再度gateが走りPASS記録される（偽陽性FAIL根絶）
    _GATE_FIRE_LOG_SKIP=0
    if python3 -c "
import sys, yaml
try:
    data = yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}
    v = str(data.get('verdict', '') or '').strip().lower()
    bc = data.get('binary_checks') or {}
    ac_count = sum(1 for k in (bc if isinstance(bc, dict) else {}) if str(k).upper().startswith('AC'))
    sys.exit(0 if (v in ('', 'none') and ac_count == 0) else 1)
except Exception:
    sys.exit(1)
" "$REPORT_PATH" 2>/dev/null; then
        _GATE_FIRE_LOG_SKIP=1
        echo "WARN: 中間状態(verdict未設定+AC欄なし) — gate_fire_logへのFAIL記録スキップ" >&2
    fi
    if [ "${GATE_SESSION_STATE_TEST:-0}" != "1" ] && [ "$_GATE_FIRE_LOG_SKIP" = "0" ]; then
        (
            flock -w 5 200 2>/dev/null
            printf -- '- ts: "%s", file: "%s", gate: "gate_report_format", result: FAIL, reasons: "%s"\n' "$TS" "$REPORT_PATH" "$REASONS" >> "$LOG_FILE"
        ) 200>"$LOG_FILE.lock" 2>/dev/null || true
        # DB INSERT: eventsテーブルへゲート記録（非ブロック）
        _GRF_CMD_ID="$(basename "${REPORT_PATH%.yaml}" | grep -oE 'cmd_[0-9a-zA-Z_]+' | head -1 || true)"
        python3 "$REPO_ROOT/scripts/memory_db_live_insert_async.py" gate \
            --gate-name "gate_report_format" --result "FAIL" \
            --cmd-id "${_GRF_CMD_ID:-}" --ts "$TS" --detail "$REASONS" \
            --source-file "$REPORT_PATH" >/dev/null 2>&1 &
        disown 2>/dev/null || true
    fi
    # cmd_2459: Gate FAIL → relevant skill feedback loop.
    # Best-effort only: report gate must remain responsible for the FAIL exit.
    _SKILL_FEEDBACK="$REPO_ROOT/scripts/skill_gate_feedback.sh"
    if [ "${SKILL_GATE_FEEDBACK_DISABLE:-0}" != "1" ] && [ -x "$_SKILL_FEEDBACK" ]; then
        _target_skill=""
        case "$REASONS" in
            *lesson_candidate*|*lessons_useful*|*result.summary*|*files_modified*|*status:\ \"pending\"*|*assumption_invalidation*|*purpose_validation*)
                _target_skill="report-write" ;;
            *binary_checks*|*verdict*)
                _target_skill="verdict-check" ;;
            *commit*)
                _target_skill="ninja-commit" ;;
        esac
        _skill_args=()
        [ -n "$_target_skill" ] && _skill_args=(--skill "$_target_skill")
        bash "$_SKILL_FEEDBACK" \
            --gate "gate_report_format" \
            --result "FAIL" \
            --reason "$REASONS" \
            --executor "$_REPORT_EXECUTOR" \
            --source "$REPORT_PATH" \
            "${_skill_args[@]}" >/dev/null 2>&1 || true
    fi
    if [ "${GATE_SESSION_STATE_TEST:-0}" != "1" ]; then
        GATE_REASONS="$REASONS" \
        GATE_REPORT_PATH="$REPORT_PATH" \
        GATE_LEARNING_FILE="$LEARNING_FILE" \
        GATE_PREFILL_THRESHOLD="$PREFILL_THRESHOLD" \
        python3 - <<'LEARNING_PY' 2>/dev/null || true
import os
import json
import tempfile
from datetime import datetime, timezone

import yaml


PATTERN_DEFS = [
    {
        "name": "lu_reason_empty",
        "prefill_field": "lessons_useful.reason",
        "match": lambda reason: reason.startswith("lessons_useful[") and "reason is empty" in reason,
    },
    {
        "name": "bc_result_empty",
        "prefill_field": "binary_checks.result",
        "match": lambda reason: reason.startswith("binary_checks.") and (".result: 空文字" in reason or '.result: ""' in reason),
    },
    {
        "name": "ac_version_read_missing",
        "match": lambda reason: reason.startswith("ac_version_read: MISSING"),
    },
    {
        "name": "result_summary_empty",
        "prefill_field": "result.summary",
        "match": lambda reason: reason == "result.summary: MISSING or empty",
    },
    {
        "name": "files_modified_missing",
        "prefill_field": "files_modified",
        "match": lambda reason: reason.startswith("files_modified: MISSING"),
    },
]


def extract_patterns(reason_text: str) -> list[dict[str, str]]:
    patterns = {}
    for reason in [r.strip() for r in reason_text.split(";") if r.strip()]:
        for pattern_def in PATTERN_DEFS:
            if pattern_def["match"](reason):
                entry = {"name": pattern_def["name"]}
                prefill_field = pattern_def.get("prefill_field")
                if prefill_field:
                    entry["prefill_field"] = prefill_field
                patterns[pattern_def["name"]] = entry
                break
    return [patterns[name] for name in sorted(patterns)]


reason_text = os.environ.get("GATE_REASONS", "")
patterns = extract_patterns(reason_text)
if not patterns:
    raise SystemExit(0)

learning_file = os.environ["GATE_LEARNING_FILE"]
threshold = int(os.environ.get("GATE_PREFILL_THRESHOLD", "10") or "10")
report_path = os.environ.get("GATE_REPORT_PATH", "")

try:
    with open(learning_file, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except FileNotFoundError:
    data = {}
except Exception:
    data = {}

if not isinstance(data, dict):
    data = {}

pattern_map = data.get("patterns")
if not isinstance(pattern_map, dict):
    pattern_map = {}
data["patterns"] = pattern_map
data["threshold"] = threshold
data["updated_at"] = datetime.now(timezone.utc).isoformat()

report_name = os.path.basename(report_path) if report_path else ""
for pattern_meta in patterns:
    pattern = pattern_meta["name"]
    entry = pattern_map.get(pattern)
    if not isinstance(entry, dict):
        entry = {}
    try:
        count = int(entry.get("count", 0) or 0)
    except Exception:
        count = 0
    count += 1
    entry["count"] = count
    entry["prefill_active"] = count >= threshold
    if pattern_meta.get("prefill_field"):
        entry["prefill_field"] = pattern_meta["prefill_field"]
    entry["last_report"] = report_name
    entry["last_seen"] = data["updated_at"]
    pattern_map[pattern] = entry

os.makedirs(os.path.dirname(learning_file), exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(learning_file), suffix=".learning.tmp")
os.close(fd)
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=False)
    f.write("\n")
os.replace(tmp, learning_file)
LEARNING_PY
        _DIAGNOSE_GATE="$(dirname "${BASH_SOURCE[0]}")/gate_diagnose_check.sh"
        if [ -f "$_DIAGNOSE_GATE" ]; then
            bash "$_DIAGNOSE_GATE" "$REPORT_PATH" "$REASONS" || true
        fi
    fi
    # --- GP-198: session_state recording on gate FAIL ---
    _SS_REPORT_BASE=$(basename "$REPORT_PATH")
    _SS_NINJA="${_SS_REPORT_BASE%%_report_*}"
    _SS_TASK_DIR="${GATE_SESSION_STATE_TASK_DIR:-$REPO_ROOT/queue/tasks}"
    if [ "${GATE_SESSION_STATE_DISABLE:-0}" = "1" ]; then
        [ "$RESULT_IS_PASS" -eq 1 ] && exit 0 || exit 1
    fi
    _SS_TASK_YAML="$_SS_TASK_DIR/${_SS_NINJA}.yaml"
    _SS_VALID=false
    source "$REPO_ROOT/scripts/lib/agent_config.sh" 2>/dev/null || true
    for _nn in $(get_ninja_names 2>/dev/null); do
        [ "$_nn" = "$_SS_NINJA" ] && { _SS_VALID=true; break; }
    done
    if [ "$_SS_VALID" = "true" ] && [ -f "$_SS_TASK_YAML" ]; then
        python3 - "$_SS_TASK_YAML" "$REPORT_PATH" "$REASONS" <<'SESSION_STATE_PY' 2>/dev/null || true
import yaml, sys, re, os, tempfile

task_yaml = sys.argv[1]
report_yaml = sys.argv[2]
block_reason = sys.argv[3]

with open(task_yaml, encoding='utf-8') as f:
    raw = f.read()

report_data = {}
try:
    with open(report_yaml, encoding='utf-8') as f:
        report_data = yaml.safe_load(f) or {}
except Exception:
    report_data = {}

diagnose_reason = ""
approach_summary = ""
if isinstance(report_data, dict):
    diagnose_reason = str(report_data.get('diagnose_reason', '') or '').strip()
    result_node = report_data.get('result') or {}
    if isinstance(result_node, dict):
        approach_summary = str(result_node.get('summary', '') or '').strip()

try:
    data = yaml.safe_load(raw) or {}
    task_node = data.get('task') or data
    ss = task_node.get('session_state') or {}
    attempt = int(ss.get('attempt', 0)) + 1
    tried = list(ss.get('tried_approaches', []))
    prior_attempts = list(ss.get('prior_attempts', []))
except Exception:
    attempt = 1
    tried = []
    prior_attempts = []

if block_reason and block_reason not in tried:
    tried.append(block_reason)

new_attempt = {
    'attempt': attempt,
    'block_reason': block_reason,
}
if diagnose_reason:
    new_attempt['diagnose_reason'] = diagnose_reason
if approach_summary:
    new_attempt['approach_summary'] = approach_summary

prior_attempts = [p for p in prior_attempts if isinstance(p, dict)]
prior_attempts.append(new_attempt)
prior_attempts = prior_attempts[-3:]

def _sq(s):
    return "'" + str(s).replace("'", "''") + "'"

frag_lines = ['session_state:',
              f'  attempt: {attempt}',
              f'  last_block_reason: {_sq(block_reason)}',
              '  tried_approaches:']
for t in tried:
    frag_lines.append(f'  - {_sq(t)}')
if diagnose_reason:
    frag_lines.append(f'  diagnose_reason: {_sq(diagnose_reason)}')
if approach_summary:
    frag_lines.append(f'  approach_summary: {_sq(approach_summary)}')
frag_lines.append('  prior_attempts:')
for item in prior_attempts:
    frag_lines.append(f"  - attempt: {int(item.get('attempt', 0) or 0)}")
    frag_lines.append(f"    block_reason: {_sq(item.get('block_reason', ''))}")
    if item.get('diagnose_reason'):
        frag_lines.append(f"    diagnose_reason: {_sq(item.get('diagnose_reason', ''))}")
    if item.get('approach_summary'):
        frag_lines.append(f"    approach_summary: {_sq(item.get('approach_summary', ''))}")
frag = '\n'.join(frag_lines)
indented = '\n'.join('  ' + l for l in frag.split('\n'))

# 行ベースのブロック置換（正規表現はマルチライン値で誤マッチする）
_lines = raw.split('\n')
_result = []
_skip = False
_inserted = False
for _l in _lines:
    _s = _l.lstrip(' ')
    _i = len(_l) - len(_s)
    if _skip:
        if _s == '' or _i > 2 or (_i == 2 and _s.startswith('- ')):
            continue
        _skip = False
    if _i == 2 and _s.startswith('session_state:'):
        _skip = True
        _result.append(indented)
        _inserted = True
        continue
    _result.append(_l)
if not _inserted:
    _result.append(indented)
raw = '\n'.join(_result)

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(task_yaml), suffix='.ss_tmp')
os.close(fd)
with open(tmp, 'w', encoding='utf-8') as f:
    f.write(raw)
os.replace(tmp, task_yaml)
print(f'[SESSION_STATE] attempt={attempt} block_reason={block_reason[:50]!r} prior_attempts={len(prior_attempts)}', file=sys.stderr)
SESSION_STATE_PY
    fi
    exit 1
fi
