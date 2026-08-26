#!/usr/bin/env bash
# codex_inbox_priority_guard.sh — Codex PreToolUse: 将軍からの未読指示を放置したまま他の作業を続けられない構造ガード
#
# 殿指摘 2026-08-26 22:15「家老にinboxを読むことを優先することを強制しないと、トラブルは今後も続く。
# inboxを無視し続けることが構造的に問題を生み続けている真因ではないか」
# 実証(同日): 15:10 push指示→2h未読 / 19:33 inbox8がCodex queueで停滞 / 21:50 方針転換(1commitずつpush)
# を未読のまま「fixed HEAD full runだけで判定」と手動フル走査を継続 / 22:08 inbox10。
# 真因=Codexはtool実行中はnudgeを受け取れず、届いた後に「読むか」が受け手の裁量に残る。
# 対処=裁量を消す: 将軍発の未読 task_assigned/cmd_new が INBOX_PRIORITY_MAX_AGE_SEC(既定180秒)以上残る間、
# inboxを読む/既読化する操作以外の全toolをBLOCK(exit 2)する。読めば自然に通る(構造型)。
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

# inboxを読む/既読化する操作は常に通す(これが出口)。
if [[ "$command" == *"inbox_mark_read.sh"* || "$command" == *"queue/inbox/${agent}.yaml"* \
      || "$tool_target" == *"queue/inbox/${agent}.yaml"* || "$command" == *"inbox_archive.sh"* ]]; then
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
