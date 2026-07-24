#!/usr/bin/env bash
# semantic-links: [[将軍判定台帳]], [[エスカレーション抑止]], [[gate_karo_startup]]
# record_escalation_decision.sh — 将軍のエスカレーション判定を判定台帳へ記録する
#
# 将軍がinbox decisionでエスカレーションに判定を返した際に、家老がこのスクリプトを
# 呼び出して判定台帳(追記型TSV)へ記録する。
# gate_karo_startup.shの送出前突合がこの台帳を参照し、判定済み同一内容の再送を抑止する。
#
# Usage:
#   bash scripts/record_escalation_decision.sh <key> <decision> [expiry_hours] [reason]
#
#   key          : 正規化済みエスカレーションキー
#                  (gate_karo_startup.shのkey_for()出力と一致させること)
#   decision     : dismiss — 判定済み・再送抑止
#                  act     — cmd起票が必要(台帳記録のみ・抑止しない)
#   expiry_hours : 0=恒久抑止, 正数=N時間後まで抑止 (省略時=0)
#   reason       : 判定理由 (省略可)
#
# 台帳ファイル: logs/shogun_escalation_decisions.tsv
#   形式: key<TAB>decision<TAB>decided_at<TAB>expiry_hours<TAB>reason
#   追記型。同一keyの最新エントリが有効(gate_karo_startup.shは全行をスキャン)。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER_FILE="${SHOGUN_ESCALATION_DECISION_LEDGER:-$SCRIPT_DIR/logs/shogun_escalation_decisions.tsv}"
LEDGER_LOCK="${LEDGER_FILE}.lock"

KEY="${1:-}"
DECISION="${2:-}"
EXPIRY_HOURS="${3:-0}"
REASON="${4:-}"

if [ -z "$KEY" ] || [ -z "$DECISION" ]; then
    echo "Usage: $0 <key> <decision> [expiry_hours] [reason]" >&2
    exit 1
fi

case "$DECISION" in
    dismiss|act) ;;
    *) echo "ERROR: decision must be 'dismiss' or 'act', got: $DECISION" >&2; exit 1 ;;
esac

DECIDED_AT="$(date -Iseconds 2>/dev/null || python3 -c 'from datetime import datetime; print(datetime.now().astimezone().isoformat(timespec="seconds"))')"

mkdir -p "$(dirname "$LEDGER_FILE")"

(
flock -x 9
printf '%s\t%s\t%s\t%s\t%s\n' "$KEY" "$DECISION" "$DECIDED_AT" "$EXPIRY_HOURS" "$REASON" >> "$LEDGER_FILE"
) 9>"$LEDGER_LOCK"
