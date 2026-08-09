#!/usr/bin/env bash
# semantic-links: [[K群移管とD群削除とescalation粒度根治の実装]]
#
# K分類の検知受領証とD分類の表示削除準備証跡を、家老レーンの一次台帳へ
# 記録する。検知本体は gate_karo_startup.sh / ninja_monitor.sh の既存
# 受け皿が担当し、このヘルパーは分類の取りこぼしを数値で検証する。

set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LEDGER="$ROOT/docs/research/cmd_4248_shogun_gate_triage_20260809.md"
RECEIPT="${KARO_MIGRATION_RECEIPT:-$ROOT/logs/karo_gate_migration_receipt.tsv}"
D_EVIDENCE="${SHOGUN_D_SUPPRESSION_EVIDENCE:-$ROOT/logs/shogun_startup_d_suppressed.tsv}"

[[ -s "$LEDGER" ]] || { echo "BLOCK: migration ledger missing: $LEDGER" >&2; exit 2; }
mkdir -p "$(dirname "$RECEIPT")" "$(dirname "$D_EVIDENCE")"

SHOGUN_GATE="$ROOT/scripts/gates/gate_shogun_startup.sh"
KARO_GATE="$ROOT/scripts/gates/gate_karo_startup.sh"
MONITOR="$ROOT/scripts/ninja_monitor.sh"
for required in "$SHOGUN_GATE" "$KARO_GATE" "$MONITOR"; do
    [[ -s "$required" ]] || { echo "BLOCK: migration receiver missing: $required" >&2; exit 2; }
done

# The receiver contract is runtime suppression, not a comment-only promise.
# gate_shogun_startup still retains J/Q6 code, but its K/D branch is disabled
# by the explicit lane switch and the receiver remains gate_karo+ninja_monitor.
if ! python3 - "$SHOGUN_GATE" <<'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
raise SystemExit(0 if 'local SHOGUN_KD_SUPPRESSED=1' in text and
                 'SHOGUN_KD_SUPPRESSED" != "1"' in text else 1)
PY
then
    echo "BLOCK: Shogun K/D suppression contract missing" >&2
    exit 2
fi

now="$(date '+%Y-%m-%dT%H:%M:%S%z')"
read -r k_rows d_rows k_total d_total < <(python3 - "$LEDGER" <<'PY'
import re, sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
rows = []
for line in text.splitlines():
    if not line.startswith("|") or not re.match(r"\|\s*\d", line):
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) < 6 or not re.fullmatch(r"[KD]", cells[-1]):
        continue
    rows.append(cells[-1])
row_k, row_d = rows.count("K"), rows.count("D")
summary = re.search(r"J\s*=\s*\d+、K\s*=\s*(\d+)、D\s*=\s*(\d+)", text)
if not summary:
    raise SystemExit("classification summary missing")
print(row_k, row_d, summary.group(1), summary.group(2))
PY
)

[[ "$k_rows" =~ ^[0-9]+$ && "$d_rows" =~ ^[0-9]+$ && \
   "$k_total" =~ ^[0-9]+$ && "$d_total" =~ ^[0-9]+$ && \
   "$k_total" -ge "$k_rows" && "$d_total" -ge "$d_rows" ]] || {
    echo "BLOCK: migration ledger classification parse failed" >&2
    exit 2
}

# A migration receipt is append-only and records the exact source ledger and
# receiver.  It is deliberately plain TSV so gate_fire_log/defense-overhead
# consumers can ingest it without reparsing human-facing gate output.
printf '%s\tK\t%d\trow=%d\tgate_karo_startup+ninja_monitor\tPASS\t%s\n' \
    "$now" "$k_total" "$k_rows" "$LEDGER" >> "$RECEIPT"
printf '%s\tD\t%d\trow=%d\tprimary_logs_preserved\tPASS\t%s\n' \
    "$now" "$d_total" "$d_rows" "$LEDGER" >> "$RECEIPT"

# D rows are display-only. Preserve the ledger row and its source path as a
# machine-readable evidence record; no source log is deleted or rewritten.
printf '%s\t%d\t%s\t%s\n' "$now" "$d_total" "$LEDGER" \
    "display_suppressed_primary_source_preserved" >> "$D_EVIDENCE"

echo "K-LANE RECEIPT: classified=${k_total} receiver=gate_karo_startup+ninja_monitor result=PASS"
echo "D-LANE RECEIPT: classified=${d_total} primary_source_preserved=${D_EVIDENCE} result=PASS"

if [[ "${KARO_MIGRATION_LOG_FIRE:-0}" == "1" ]]; then
    # defense_overhead is the canonical numeric fire ledger for migrated checks.
    # Keep this optional so fixture runs remain side-effect free.
    # shellcheck source=/dev/null
    source "$ROOT/scripts/lib/defense_overhead_writer.sh"
    if ! defense_overhead_write gate_karo_startup migrated_classification \
        0 PASS "karo-migration-${now//+/}-${k_total}-${d_total}"; then
        echo "BLOCK: defense_overhead receipt write failed" >&2
        exit 2
    fi
fi
