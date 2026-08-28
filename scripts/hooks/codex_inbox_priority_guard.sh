#!/usr/bin/env bash
# codex_inbox_priority_guard.sh — Codex PreToolUse: 将軍からの未読指示を放置したまま他の作業を続けられない構造ガード
#
# 殿指摘 2026-08-26 22:15「家老にinboxを読むことを優先することを強制しないと、トラブルは今後も続く。
# inboxを無視し続けることが構造的に問題を生み続けている真因ではないか」
# 実証(同日): 15:10 push指示→2h未読 / 19:33 inbox8がCodex queueで停滞 / 21:50 方針転換(1commitずつpush)
# を未読のまま「fixed HEAD full runだけで判定」と手動フル走査を継続 / 22:08 inbox10。
# 真因=Codexはtool実行中はnudgeを受け取れず、届いた後に「読むか」が受け手の裁量に残る。
# 対処=裁量を消す: 将軍発の未読 task_assigned/cmd_new が INBOX_PRIORITY_MAX_AGE_SEC(既定180秒)以上残る間、
# inboxを読む/既読化する操作と、既読化に必要な将軍向け処理証跡の作成以外の全toolをBLOCK(exit 2)する。
# 証跡作成まで塞ぐと inbox_mark_read の証跡検査と相互待ちになるため、許可経路はここで限定する。
set -uo pipefail

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
ROOT="${SHOGUN_REPO_ROOT:-${_self%/scripts/hooks/codex_inbox_priority_guard.sh}}"

payload="$(cat 2>/dev/null || true)"
[[ -n "${payload//[[:space:]]/}" ]] || exit 0

agent="${SHOGUN_AGENT_ID:-}"
if [[ -z "$agent" && -n "${TMUX_PANE:-}" ]]; then
    agent="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
fi
[[ -n "$agent" ]] || exit 0

# 対象ロール(既定: 家老)。カンマ区切りで拡張可。
targets="${INBOX_PRIORITY_AGENTS:-karo}"
case ",${targets}," in *",${agent},"*) ;; *) exit 0 ;; esac

inbox="${SHOGUN_INBOX_FILE:-$ROOT/queue/inbox/${agent}.yaml}"
[[ -f "$inbox" ]] || exit 0

max_age="${INBOX_PRIORITY_MAX_AGE_SEC:-180}"

tool_name="$(jq -r '.tool_name // .tool // .name // empty' <<<"$payload" 2>/dev/null || true)"
command="$(jq -r '.tool_input.command // .tool_input.cmd // .input.command // .input.cmd // empty' <<<"$payload" 2>/dev/null || true)"
tool_target="$(jq -r '.tool_input.file_path // .tool_input.filePath // .tool_input.path // .input.file_path // .input.path // empty' <<<"$payload" 2>/dev/null || true)"

# shell command の引数ではなく、単一commandの実行位置にある script token
# だけを判定する。これにより許可scriptの後へ任意commandを連結する迂回と、
# shell substitution/process substitution/redirection/newline、本文だけの偽装を許可しない。
command_is_allowed_evidence() {
    python3 - "$command" <<'PY'
import shlex
import sys
import re

command = sys.argv[1]

def has_shell_syntax(value):
    """Reject active shell syntax while preserving quoted argument text."""
    state = "normal"
    index = 0
    while index < len(value):
        char = value[index]
        if state == "single":
            if char == "'":
                state = "normal"
            index += 1
            continue
        if state == "double":
            if char == "\\":
                index += 2
                continue
            if char == '"':
                state = "normal"
                index += 1
                continue
            # $() and backticks execute even inside double quotes.
            if char == "`" or (char == "$" and value[index:index + 2] == "$("):
                return True
            index += 1
            continue
        if char == "'":
            state = "single"
            index += 1
            continue
        if char == '"':
            state = "double"
            index += 1
            continue
        if char == "\\":
            # An escaped metacharacter is literal; a trailing escape/newline is
            # still rejected as an incomplete shell construct.
            if index + 1 >= len(value) or value[index + 1] == "\n":
                return True
            index += 2
            continue
        if char == "\n" or char in ";|&<>()":
            return True
        if char == "`" or (char == "$" and value[index:index + 2] == "$("):
            return True
        index += 1
    return state != "normal"

if has_shell_syntax(command):
    raise SystemExit(1)

try:
    lexer = shlex.shlex(command, posix=True)
    lexer.whitespace_split = True
    words = list(lexer)
except ValueError:
    raise SystemExit(1)

shells = {"bash", "sh", "zsh", "ksh", "dash"}
assignment = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=.*$")

def allowed_invocation(argv):
    """Recognize only the supported single writer invocation shape."""
    index = 0
    while index < len(argv) and assignment.match(argv[index]):
        index += 1
    # Common production wrappers may prefix the interpreter, but only their
    # option/value words are accepted. An arbitrary executable is not a prefix.
    if index < len(argv) and argv[index] == "env":
        index += 1
        while index < len(argv) and (assignment.match(argv[index]) or argv[index].startswith("-")):
            index += 1
    if index < len(argv) and argv[index] == "timeout":
        index += 1
        while index < len(argv) and (argv[index].replace(".", "", 1).isdigit() or argv[index].startswith("-")):
            index += 1
    if index >= len(argv):
        return False
    script = argv[index].rsplit("/", 1)[-1]
    if script in {"bulletin_write.sh", "inbox_write.sh"}:
        script_index = index
    elif argv[index] in shells and index + 1 < len(argv):
        script_index = index + 1
        script = argv[script_index].rsplit("/", 1)[-1]
    else:
        return False
    if script not in {"bulletin_write.sh", "inbox_write.sh"}:
        return False
    if script == "inbox_write.sh":
        return script_index + 1 < len(argv) and argv[script_index + 1] == "shogun"
    return True

raise SystemExit(0 if allowed_invocation(words) else 1)
PY
}

# inboxを読む/既読化する操作は常に通す(これが出口)。
if [[ "$command" == *"inbox_mark_read.sh"* || "$command" == *"queue/inbox/${agent}.yaml"* \
      || "$tool_target" == *"queue/inbox/${agent}.yaml"* || "$command" == *"inbox_archive.sh"* ]]; then
    exit 0
fi

# inbox_mark_read の証跡検査を先に満たす、将軍向けの正規証跡経路だけを通す。
if command_is_allowed_evidence; then
    exit 0
fi

stale="$(python3 - "$inbox" "$max_age" <<'PY' 2>/dev/null || true
import sys, yaml, datetime
path, max_age = sys.argv[1], int(sys.argv[2])
try:
    yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)
    data = yaml.safe_load(open(path, encoding="utf-8")) or {}
except Exception:
    sys.exit(0)
msgs = data.get("messages", []) if isinstance(data, dict) else []
now = datetime.datetime.now()
out = []
for m in msgs:
    if not isinstance(m, dict) or m.get("read") is not False:
        continue
    if m.get("from") != "shogun" or m.get("type") not in ("task_assigned", "cmd_new"):
        continue
    ts = str(m.get("timestamp") or "")
    try:
        age = (now - datetime.datetime.fromisoformat(ts)).total_seconds()
    except Exception:
        age = max_age + 1
    if age >= max_age:
        out.append(f"{m.get('id')} age={int(age)}s :: {str(m.get('content') or '')[:60]}")
print("\n".join(out))
PY
)"
[[ -n "$stale" ]] || exit 0

count="$(printf '%s\n' "$stale" | grep -c .)"
{
    printf 'BLOCK(INBOX_PRIORITY): %s 宛の将軍指示 %s件が %s秒以上未読のまま。他の作業より先に読め。\n' "$agent" "$count" "$max_age"
    printf '%s\n' "$stale"
    printf '  出口: Read queue/inbox/%s.yaml → 各IDを bash scripts/inbox_mark_read.sh %s <id> で既読化(判断して行動を変えた上で)。\n' "$agent" "$agent"
    printf '  理由: 未読指示の放置が方針乖離(2026-08-26 push 6h停滞)を生んだ。読むまでは進めない構造型ガード。\n'
} >&2
exit 2
