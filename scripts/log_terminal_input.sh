#!/usr/bin/env bash
# log_terminal_input.sh — UserPromptSubmitフックで殿のターミナル入力を記録
set -eu

# 2026-09-01 15:19: TMUX_PANE が空/未設定の子プロセス(claude -p 等)では
# `tmux display-message -t ""` が active pane(=殿が見ている pane)を返し、
# 他プロセスの prompt が「殿→shogun の inbound」として記録された。
# pane 不明の入力は殿の入力ではない=記録しない。
[ -n "${TMUX_PANE:-}" ] || exit 0
AGENT_ID="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
[ -n "$AGENT_ID" ] && [ "$AGENT_ID" != "unknown" ] || exit 0

# 入力テキスト取得（stdin JSON の .prompt フィールドから）
PAYLOAD="$(cat 2>/dev/null || true)"
INPUT="$(jq -r '.prompt // ""' 2>/dev/null <<<"$PAYLOAD" || true)"
[ -n "$INPUT" ] || exit 0

# スラッシュコマンド除外
[[ "$INPUT" != /* ]] || exit 0

# nudge除外（inbox1, inbox3等）
[[ "$INPUT" != inbox* ]] || exit 0

_log_terminal_input_self="${BASH_SOURCE[0]}"
[[ "$_log_terminal_input_self" != /* ]] && _log_terminal_input_self="$PWD/$_log_terminal_input_self"
SCRIPT_DIR="${_log_terminal_input_self%/scripts/log_terminal_input.sh}"
unset _log_terminal_input_self

# A prompt may be delivered to several CLI hook processes.  The payload identity,
# not the process which happened to receive it, is therefore the routing SSOT.
PAYLOAD_TARGETS="$(jq -r '[.target_agent, .target, .pane_agent_id, .agent_id] | map(select(type == "string" and length > 0)) | unique | .[]' 2>/dev/null <<<"$PAYLOAD" || true)"
PAYLOAD_TARGET_COUNT="$(printf '%s\n' "$PAYLOAD_TARGETS" | awk 'NF{n++} END{print n+0}')"
PAYLOAD_TARGET="$(printf '%s\n' "$PAYLOAD_TARGETS" | awk 'NF{print; exit}')"
# turn_id is the Codex upstream identity for one real user turn.  It remains
# stable across fanout/retry/replay and differs for legitimate later turns.
SOURCE_EVENT_ID="$(jq -r '.source_event_id // .event_id // .prompt_id // .turn_id // ""' 2>/dev/null <<<"$PAYLOAD" || true)"
ACTIVE_AGENT_ID="$AGENT_ID"
MINIMAL_PAYLOAD=0

# UserPromptSubmit is also used as the transport for agent/task notifications.
# Those messages are system traffic, not Lord input.  Classify them at the
# producer so every consumer (conversation, memory, and lesson harvesting)
# sees the same source label instead of maintaining its own exclusion filter.
is_task_notification_payload() {
    local prompt="${1:-}" payload_json="${2:-}"
    [[ "$prompt" =~ ^[[:space:]]*\<task-notification([[:space:]>]|$) ]] && return 0
    jq -e '
      (.notification_type // .event_type // .message_type // .source // "")
      | strings | ascii_downcase
      | test("task[-_]notification|agent[-_]message|system[-_]notification")
    ' >/dev/null 2>&1 <<<"$payload_json"
}

INPUT_SOURCE="terminal"
INPUT_AGENT="lord"
INPUT_TARGET="$AGENT_ID"
if is_task_notification_payload "$INPUT" "$PAYLOAD"; then
    INPUT_SOURCE="task-notification"
    INPUT_AGENT="system"
fi

# Codex runs UserPromptSubmit inside the CLI process which received the input.
# The attached UI client's selected pane is unrelated (and may point at a
# different agent), so the hook execution pane is the minimal payload SSOT.
if [ "$PAYLOAD_TARGET_COUNT" -eq 0 ]; then
    MINIMAL_PAYLOAD=1
    PAYLOAD_TARGET="$ACTIVE_AGENT_ID"
    PAYLOAD_TARGET_COUNT=1
fi
if [ -z "$SOURCE_EVENT_ID" ] && [ "$PAYLOAD_TARGET_COUNT" -eq 1 ]; then
    # Minimal payload has no upstream retry identity.  Mint an invocation id;
    # explicit payload ids still retain durable cross-process idempotency.
    SOURCE_EVENT_ID="terminal:$(printf '%s\037%s\037%s' "$TMUX_PANE" "$EPOCHREALTIME" "$INPUT" | sha256sum | awk '{print $1}')"
fi

_route_diag() {
    local reason="$1"
    local diag="$SCRIPT_DIR/logs/lord_conversation_route_rejects.jsonl"
    mkdir -p "${diag%/*}"
    (
        flock -w 2 200 || exit 0
        jq -cn --arg ts "$(date -Iseconds)" --arg reason "$reason" \
            --arg pane_agent "$AGENT_ID" --arg payload_target "$PAYLOAD_TARGET" \
            --arg source_event_id "$SOURCE_EVENT_ID" \
            '{ts:$ts,reason:$reason,pane_agent:$pane_agent,payload_target:$payload_target,source_event_id:$source_event_id}' >>"$diag"
    ) 200>"${diag}.lock"
}

if [ "$PAYLOAD_TARGET_COUNT" -ne 1 ]; then
    _route_diag "missing_or_conflicting_payload_target"
    exit 0
fi
if [ "$PAYLOAD_TARGET" != "$AGENT_ID" ]; then
    _route_diag "cross_pane_target_mismatch"
    exit 0
fi
if [ -z "$SOURCE_EVENT_ID" ]; then
    _route_diag "missing_source_event_id"
    exit 0
fi

# lord_conversation.sh読込・環境変数設定
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/lord_conversation.sh"
export LORD_CONVERSATION="$SCRIPT_DIR/queue/lord_conversation.jsonl"
export LORD_CONVERSATION_LOCK="${LORD_CONVERSATION}.lock"
export LORD_CONVERSATION_SOURCE_EVENT_ID
LORD_CONVERSATION_SOURCE_EVENT_ID="$SOURCE_EVENT_ID"
export LORD_CONVERSATION_CONSUMED_LEDGER="$SCRIPT_DIR/queue/lord_conversation_consumed.tsv"

append_lord_conversation "$INPUT" "inbound" "$INPUT_AGENT" "$INPUT_SOURCE" "$INPUT_TARGET"

# セマンティクスインデックス候補化。会話記録そのものは上で完了済みのため、失敗しても入力処理は止めない。
# 最適化: python3起動コスト(~89ms)をjq -cnで回避。バックグラウンド実行でフック応答を即時化。
if [ -f "$SCRIPT_DIR/scripts/semantic_index_update.sh" ]; then
    (
        _semantic_payload=$(jq -cn --arg ts "$(date -Iseconds)" --arg summary "$INPUT" \
            '{"timestamp":$ts,"summary":$summary}' 2>/dev/null || true)
        [ -n "$_semantic_payload" ] && \
            bash "$SCRIPT_DIR/scripts/semantic_index_update.sh" discussion "$_semantic_payload" >/dev/null 2>&1
    ) &
fi
