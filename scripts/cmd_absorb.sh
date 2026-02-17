#!/bin/bash
# cmd_absorb.sh — cmd吸収/中止を記録する
# Usage: bash scripts/cmd_absorb.sh <absorbed_cmd> <absorbing_cmd> <reason>
# Example:
#   bash scripts/cmd_absorb.sh cmd_126 cmd_128 "AC6を吸収"
#   bash scripts/cmd_absorb.sh cmd_999 none "不要になった"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD_FILE="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
CHANGELOG_FILE="$SCRIPT_DIR/queue/completed_changelog.yaml"
CMD_LOCK="${CMD_FILE}.lock"
CHANGELOG_LOCK="${CHANGELOG_FILE}.lock"

ABSORBED_CMD="${1:-}"
ABSORBING_CMD="${2:-}"
REASON="${*:3}"

if [ -z "$ABSORBED_CMD" ] || [ -z "$REASON" ]; then
    echo "Usage: bash scripts/cmd_absorb.sh <absorbed_cmd> <absorbing_cmd> <reason>" >&2
    exit 1
fi

MODE="absorbed"
if [ -z "$ABSORBING_CMD" ] || [ "$ABSORBING_CMD" = "none" ]; then
    MODE="cancelled"
fi

yaml_escape_double_quoted() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

get_cmd_field() {
    local key="$1"
    awk -v id="  - id: ${ABSORBED_CMD}" -v key="$key" '
        $0 == id { found=1; next }
        found && /^  - id:/ { exit }
        found && $0 ~ ("^    " key ":") {
            line = $0
            sub("^    " key ": *\"?", "", line)
            sub(/"$/, "", line)
            print line
            exit
        }
    ' "$CMD_FILE"
}

update_cmd_yaml() {
    local reason_escaped
    reason_escaped="$(yaml_escape_double_quoted "$REASON")"
    local tmp_file
    tmp_file="$(mktemp "${CMD_FILE}.tmp.XXXXXX")"

    (
        flock -w 10 200 || { echo "ERROR: flock取得失敗: $CMD_FILE" >&2; rm -f "$tmp_file"; exit 1; }

        if ! grep -q "^  - id: ${ABSORBED_CMD}$" "$CMD_FILE"; then
            echo "ERROR: cmd not found: ${ABSORBED_CMD}" >&2
            rm -f "$tmp_file"
            exit 1
        fi

        if ! awk -v target="$ABSORBED_CMD" -v mode="$MODE" -v by="$ABSORBING_CMD" -v reason="$reason_escaped" '
            function emit_extra_fields() {
                if (mode == "absorbed") {
                    print "    absorbed_by: " by
                    print "    absorbed_reason: \"" reason "\""
                } else {
                    print "    cancelled_reason: \"" reason "\""
                }
            }

            {
                if ($0 ~ "^  - id: " target "$") {
                    in_target = 1
                } else if (in_target && $0 ~ /^  - id: /) {
                    in_target = 0
                }

                if (in_target && $0 ~ /^    (absorbed_by|absorbed_reason|cancelled_reason):/) {
                    next
                }

                if (in_target && $0 ~ /^    status:/) {
                    print "    status: " mode
                    emit_extra_fields()
                    status_updated = 1
                    next
                }

                print
            }

            END {
                if (!status_updated) {
                    print "ERROR: status line not found for " target > "/dev/stderr"
                    exit 1
                }
            }
        ' "$CMD_FILE" > "$tmp_file"; then
            rm -f "$tmp_file"
            exit 1
        fi

        mv "$tmp_file" "$CMD_FILE"
    ) 200>"$CMD_LOCK"
}

append_changelog() {
    local completed_at purpose project purpose_escaped reason_escaped
    completed_at="$(date '+%Y-%m-%dT%H:%M:%S')"
    purpose="$(get_cmd_field purpose)"
    project="$(get_cmd_field project)"
    [ -z "$project" ] && project="unknown"
    purpose_escaped="$(yaml_escape_double_quoted "$purpose")"
    reason_escaped="$(yaml_escape_double_quoted "$REASON")"

    (
        flock -w 10 200 || { echo "ERROR: flock取得失敗: $CHANGELOG_FILE" >&2; exit 1; }

        if [ ! -f "$CHANGELOG_FILE" ]; then
            echo "entries:" > "$CHANGELOG_FILE"
        fi

        {
            echo "  - id: ${ABSORBED_CMD}"
            echo "    project: ${project}"
            echo "    purpose: \"${purpose_escaped}\""
            echo "    completed_at: \"${completed_at}\""
            echo "    status: ${MODE}"
            if [ "$MODE" = "absorbed" ]; then
                echo "    absorbed_by: ${ABSORBING_CMD}"
                echo "    absorbed_reason: \"${reason_escaped}\""
            else
                echo "    cancelled_reason: \"${reason_escaped}\""
            fi
        } >> "$CHANGELOG_FILE"
    ) 200>"$CHANGELOG_LOCK"
}

notify_karo() {
    local message
    if [ "$MODE" = "absorbed" ]; then
        message="${ABSORBED_CMD}は${ABSORBING_CMD}に吸収。理由: ${REASON}"
    else
        message="${ABSORBED_CMD}はcancelled。理由: ${REASON}"
    fi
    bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$message" cmd_absorbed cmd_absorb
}

update_cmd_yaml
append_changelog
notify_karo

echo "OK: ${ABSORBED_CMD} -> ${MODE}"
