#!/bin/bash
# Shared contract for escalation messages.
#
# Escalation is intentionally a type-level lane.  Other message types may
# legitimately mention BLOCK/FAIL while reporting a gate result and must not
# be rejected by this contract.

escalation_evidence_missing() {
    local content="${1:-}"
    printf '%s' "$content" | python3 -c '
import re
import sys

text = sys.stdin.read()
fields = [
    ("試行コマンド", r"(?:試行コマンド|trial[_ ]command|attempt[_ ]command)\s*[:：=]\s*(.*)"),
    ("exit code", r"(?:exit[_ ]?code|終了コード|終了code)\s*[:：=]\s*(.*)"),
    ("特定した不足", r"(?:特定した不足|identified[_ ]gap|不足箇所)\s*[:：=]\s*(.*)"),
    ("次の行動", r"(?:次の行動|next[_ ]action)\s*[:：=]\s*(.*)"),
    ("実行者", r"(?:実行者|executor|owner)\s*[:：=]\s*(.*)"),
]
labels = "|".join(re.escape(label) for _, label in fields)
invalid = {"", "-", "—", "なし", "不明", "未特定", "n/a", "na", "todo", "tbd", "fill_this"}
for label, pattern in fields:
    match = re.search(pattern, text, flags=re.IGNORECASE | re.MULTILINE)
    value = match.group(1).strip() if match else ""
    if value:
        value = re.split(r"\s+(?=(?:" + labels + r")\s*[:：=])", value, maxsplit=1, flags=re.IGNORECASE)[0].strip()
    if value.casefold() in invalid:
        print(label)
'
}

escalation_evidence_record() {
    local source_name="${1:-}" verdict="${2:-}" stamp event_id
    stamp="${EPOCHREALTIME/./}"
    stamp="${stamp//[^0-9]/}"
    event_id="escalation-evidence-${source_name}-${BASHPID}-${stamp}"
    # verdict=BLOCK counts rejected attempts; verdict=PASS counts accepted
    # evidence and is the durable signal for later self-resolution analysis.
    defense_overhead_write_async "$source_name" escalation_evidence_contract 0 "$verdict" "$event_id" || true
}

escalation_evidence_validate_or_block() {
    local source_name="$1" message_type="$2" content="$3" missing

    # The review ruling for cmd_4251 deliberately scopes this to the typed
    # escalation lane.  BLOCK/FAIL prose in all other lanes is not evidence of
    # an escalation and must remain deliverable.
    [ "$message_type" = "escalation" ] || return 0

    missing="$(escalation_evidence_missing "$content")"
    if [ -n "$missing" ]; then
        escalation_evidence_record "$source_name" BLOCK
        echo "BLOCK: type=escalation requires self-trial evidence before delivery." >&2
        echo "Missing: $(printf '%s\n' "$missing" | paste -sd, -)" >&2
        cat >&2 <<'EOF'
Template:
試行コマンド: <実行したコマンド>
exit_code: <実測した終了コード>
特定した不足: <特定した不足>
次の行動: <次に実行する行動>
実行者: <実行者>
EOF
        return 2
    fi

    escalation_evidence_record "$source_name" PASS
    return 0
}
