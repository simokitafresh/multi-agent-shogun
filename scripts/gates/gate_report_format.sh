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

# --- Pre-step: 機械的修正を自動実行（autofix未実行による無駄FAILを防止）---
_AUTOFIX_GATE="$(dirname "${BASH_SOURCE[0]}")/gate_report_autofix.sh"
if [ -f "$_AUTOFIX_GATE" ]; then
    _AUTOFIX_OUT=$(bash "$_AUTOFIX_GATE" "$REPORT_PATH" 2>&1) || {
        echo "  [WARN] autofix pre-step failed (exit $?). Output:" >&2
        echo "$_AUTOFIX_OUT" | head -5 >&2
    }
fi

# Python validation — checks all known failure patterns from karo_workarounds
RESULT=$(python3 "$(dirname "${BASH_SOURCE[0]}")/gate_report_format_main.py" "$REPORT_PATH" 2>&1) || true

echo "$RESULT"

RESULT_IS_PASS=0
case "$RESULT" in
    PASS|PASS$'\n'*)
        RESULT_IS_PASS=1
        ;;
esac

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
        python3 - "$_SS_TASK_YAML" "$REASONS" <<'SESSION_STATE_PY' 2>/dev/null || true
import yaml, sys, re, os, tempfile

task_yaml = sys.argv[1]
block_reason = sys.argv[2]

with open(task_yaml, encoding='utf-8') as f:
    raw = f.read()

try:
    data = yaml.safe_load(raw) or {}
    task_node = data.get('task') or data
    ss = task_node.get('session_state') or {}
    attempt = int(ss.get('attempt', 0)) + 1
    tried = list(ss.get('tried_approaches', []))
except Exception:
    attempt = 1
    tried = []

if block_reason and block_reason not in tried:
    tried.append(block_reason)

def _sq(s):
    return "'" + str(s).replace("'", "''") + "'"

frag_lines = ['session_state:',
              f'  attempt: {attempt}',
              f'  last_block_reason: {_sq(block_reason)}',
              '  tried_approaches:']
for t in tried:
    frag_lines.append(f'  - {_sq(t)}')
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
print(f'[SESSION_STATE] attempt={attempt} block_reason={block_reason[:50]!r}', file=sys.stderr)
SESSION_STATE_PY
    fi
    exit 1
fi
