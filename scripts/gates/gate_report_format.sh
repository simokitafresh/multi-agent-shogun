#!/bin/bash
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

# --- PASS cache: skip redundant re-checks on unmodified files (GP-073) ---
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS_CACHE="${GATE_PASS_CACHE_FILE:-$REPO_ROOT/logs/.gate_pass_cache}"
# perf: cache keyはshellで組み立て、realpath起動を避ける。
if [[ "$REPORT_PATH" = /* ]]; then
    _CANON="$REPORT_PATH"
else
    _CANON="$PWD/${REPORT_PATH#./}"
fi
{ read -r _MTIME; read -r _GATE_MTIME; } < <(stat -c '%Y' "$REPORT_PATH" "${BASH_SOURCE[0]}" 2>/dev/null || printf '\n\n')
if [ -n "$_MTIME" ] && [ -n "$_GATE_MTIME" ] && [ -f "$PASS_CACHE" ] && grep -qF "${_CANON} ${_MTIME} ${_GATE_MTIME}" "$PASS_CACHE" 2>/dev/null; then
    echo "PASS"
    exit 0
fi

# cmd_2063: autofix + format validation を単一 python3 プロセスで実行
# 旧: bash gate_report_autofix.sh (→python3) + python3 gate_report_format_main.py = 2プロセス
# 新: python3 gate_report_format_combined.py (autofix+validation を1プロセス統合) = 1プロセス
_GATE_DIR="${BASH_SOURCE[0]%/*}"
RESULT=$(python3 "$_GATE_DIR/gate_report_format_combined.py" "$REPORT_PATH" 2>&1) || true

echo "$RESULT"

RESULT_IS_PASS=0
if printf '%s\n' "$RESULT" | grep -qxE 'PASS|PASS_NO_IMPROVEMENT'; then
    RESULT_IS_PASS=1
fi

# --- GATE_NO_LOG guard: skip fire_log writing ---
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
    (
        flock -w 5 200 2>/dev/null
        printf -- '- ts: "%s", file: "%s", gate: "gate_report_format", result: PASS\n' "$TS" "$REPORT_PATH" >> "$LOG_FILE"
    ) 200>"$LOG_FILE.lock" 2>/dev/null || true
    # Update PASS cache (GP-073) — flock for concurrent gate runs
    if [ -n "$_MTIME" ]; then
        (
            flock -w 5 201 2>/dev/null
            sed -i "\|^${_CANON} |d" "$PASS_CACHE" 2>/dev/null || true
            echo "${_CANON} ${_MTIME} ${_GATE_MTIME}" >> "$PASS_CACHE"
        ) 201>"$PASS_CACHE.lock" 2>/dev/null || true
    fi
    exit 0
else
    REASONS="$RESULT"
    REASONS="${REASONS#FAIL: }"
    REASONS="${REASONS%%$'\n'*}"
    REASONS="${REASONS//\"/\\\"}"
    (
        flock -w 5 200 2>/dev/null
        printf -- '- ts: "%s", file: "%s", gate: "gate_report_format", result: FAIL, reasons: "%s"\n' "$TS" "$REPORT_PATH" "$REASONS" >> "$LOG_FILE"
    ) 200>"$LOG_FILE.lock" 2>/dev/null || true
    _DIAGNOSE_GATE="$(dirname "${BASH_SOURCE[0]}")/gate_diagnose_check.sh"
    if [ -f "$_DIAGNOSE_GATE" ]; then
        bash "$_DIAGNOSE_GATE" "$REPORT_PATH" "$REASONS" || true
    fi
    # --- GP-198: session_state recording on gate FAIL ---
    _SS_REPORT_BASE=$(basename "$REPORT_PATH")
    _SS_NINJA="${_SS_REPORT_BASE%%_report_*}"
    _SS_TASK_DIR="${GATE_SESSION_STATE_TASK_DIR:-$REPO_ROOT/queue/tasks}"
    _SS_TASK_YAML="$_SS_TASK_DIR/${_SS_NINJA}.yaml"
    _SS_VALID=false
    for _nn in kagemaru hanzo hayate tobisaru saizo kotaro sasuke kirimaru; do
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

pat = re.compile(r'^  session_state:.*?(?=\n  [a-zA-Z_]|\Z)', re.MULTILINE | re.DOTALL)
m = pat.search(raw)
if m:
    raw = raw[:m.start()] + indented + raw[m.end():]
else:
    raw = raw.rstrip('\n') + '\n' + indented + '\n'

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
