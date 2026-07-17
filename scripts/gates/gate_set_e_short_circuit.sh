#!/usr/bin/env bash
# Level4 guard for LG041: a false test as a while-body's only command is fatal
# under set -e. Other short-circuits may intentionally return/exit and are not
# classified without control-flow context.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

scan_file() {
    local file="$1"
    [ -f "$file" ] || return 0
    [ "$file" = "scripts/gates/gate_set_e_short_circuit.sh" ] && return 0

    if ! awk '
        /^[[:space:]]*set[[:space:]]+-[^#]*(e|o[[:space:]]+errexit)/ { errexit=1 }
        errexit {
            line=$0
            sub(/^[[:space:]]*/, "", line)
            guarded=(line ~ /done([^|]|$)*\|\|[[:space:]]*true([[:space:]]|$)/)
            if (!guarded && (line ~ /do[[:space:]]+\[[^;]*\][[:space:]]*&&/ ||
                line ~ /do[[:space:]]+\[\[[^;]*\]\][[:space:]]*&&/)) {
                printf "%s:%d:%s\n", FILENAME, FNR, $0
                found=1
            }
        }
        END { exit found ? 1 : 0 }
    ' "$file"; then
        return 1
    fi
}

cd "$ROOT_DIR"
fail=0
if [ "$#" -gt 0 ]; then
    for file in "$@"; do
        scan_file "$file" || fail=1
    done
else
    while IFS= read -r file; do
        scan_file "$file" || fail=1
    done < <(find scripts .claude/hooks -type f -name '*.sh' 2>/dev/null | sort)
fi

if [ "$fail" -ne 0 ]; then
    echo "BLOCK(LG041): set -e配下のwhile本体test &&短絡をif/then/fiへ変換せよ" >&2
    exit 1
fi
echo "PASS(LG041): set -e配下のwhile本体test &&短絡 0件"
