#!/usr/bin/env bats

# test_necessity: source-only publication proof must bind the exact remote tip;
# a stale receipt cannot mark a non-contained, non-equivalent source as published.

setup_file() {
    export GATE_SOURCE_PUBLISH_HELPERS="$BATS_FILE_TMPDIR/source_publish_helpers.sh"
    python3 - "$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh" >"$GATE_SOURCE_PUBLISH_HELPERS" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r"(?ms)^source_publish_receipt_matches\(\) \{.*?^\}", text)
if match is None:
    raise SystemExit("source_publish_receipt_matches helper not found")
print(match.group(0))
PY
}

@test "stale receipt cannot mark current non-equivalent remote tip published" {
    local base="$BATS_TEST_TMPDIR/stale-receipt"
    local receipt="$base/receipt.json"
    local marker="$base/marker"
    local generation="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    local source_sha="1111111111111111111111111111111111111111"
    local old_remote="2222222222222222222222222222222222222222"
    local current_remote="3333333333333333333333333333333333333333"
    mkdir -p "$base"

    cat >"$receipt" <<EOF
{"version":1,"state":"published","cmd_id":"cmd_stale_receipt_probe","completion_generation":"$generation","entries":[{"cmd_id":"cmd_stale_receipt_probe","completion_generation":"$generation","report_generation":"rpt-stale","repo":"$base/repo","source_sha":"$source_sha","remote_tip":"$old_remote","remote_contains_source_rc":0}]}
EOF
    source "$GATE_SOURCE_PUBLISH_HELPERS"
    run source_publish_receipt_matches "$receipt" cmd_stale_receipt_probe "$generation" "$base/repo" "$current_remote" "$source_sha" rpt-stale
    [ "$status" -ne 0 ]

    if source_publish_receipt_matches "$receipt" cmd_stale_receipt_probe "$generation" "$base/repo" "$current_remote" "$source_sha" rpt-stale; then
        printf '%s\n' "$current_remote" >"$marker"
    fi
    [ ! -e "$marker" ]
}
