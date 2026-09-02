#!/bin/bash
# publisher_admit.sh — 単一 publisher 化 U5: request の admission gate
# (LGTM+ACCEPT が queue 投入の必須条件、R13 の migration_ack 強制)
#
# Usage:
#   publisher_admit.sh admit <request.yaml>
#
# rc:
#   0  admitted
#   1  usage error / request file missing / cmd_id 不明
#   5  review_approvals/reports/<key>/{gunshi,karo}.yaml のいずれかが不足
#   6  kind=doc の path が将軍 identity allowlist(docs/ context/ queue/shogun_todo_map.md)外
#   11 R13: backend/app/db/ 配下の path があるのに karo.yaml に migration_ack が無い
#
# 承認 file(review_approvals/reports/<key>/{gunshi,karo}.yaml)は admit 自身では作らない。
#
# 設計書: docs/research/single_publisher_asis_tobe_5w1h_20260902.md §9.1 U5 / §4 R13
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# review_report_key() の唯一の正本を再利用する(admit と review_approval.sh が
# 別々にkeyを導出すると、アルゴリズムがずれた時に承認dirを見つけられなくなる)。
source "$SCRIPT_DIR/lib/review_approval.sh"
source "$SCRIPT_DIR/lib/yaml_field_set.sh"

_publisher_admit_scalar() {
    local file="$1" field="$2"
    grep -m1 "^${field}:" "$file" 2>/dev/null | sed -E "s/^${field}:[[:space:]]*//; s/^[\"']//; s/[\"']\$//"
}

_publisher_admit_paths() {
    python3 - "$1" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
paths = data.get("paths") or []
if isinstance(paths, list):
    for p in paths:
        print(str(p))
PY
}

cmd_admit() {
    local req="$1"
    if [ -z "$req" ] || [ ! -f "$req" ]; then
        echo "publisher_admit: admit requires an existing request file" >&2
        return 1
    fi

    local cmd_id
    cmd_id="$(_publisher_admit_scalar "$req" cmd_id)"
    [ -n "$cmd_id" ] || cmd_id="$(_publisher_admit_scalar "$req" parent_cmd)"
    if [ -z "$cmd_id" ]; then
        echo "publisher_admit: request missing cmd_id/parent_cmd: $req" >&2
        return 1
    fi

    local report_logical key dir
    report_logical="queue/reports/$(basename "$req")"
    key="$(review_report_key "$report_logical")"
    dir="$REPO_ROOT/queue/gates/$cmd_id/review_approvals/reports/$key"

    local missing="" f
    for f in gunshi karo; do
        [ -f "$dir/$f.yaml" ] || missing="$missing $f"
    done
    if [ -n "$missing" ]; then
        echo "publisher_admit: missing approval(s):$missing ($dir)" >&2
        return 5
    fi

    local kind
    kind="$(_publisher_admit_scalar "$req" kind)"
    local -a paths=()
    local p
    while IFS= read -r p; do
        [ -n "$p" ] && paths+=("$p")
    done < <(_publisher_admit_paths "$req")

    if [ "$kind" = doc ]; then
        local allowed
        for p in "${paths[@]}"; do
            allowed=0
            case "$p" in
                docs/*|context/*|queue/shogun_todo_map.md) allowed=1 ;;
            esac
            if [ "$allowed" -ne 1 ]; then
                echo "publisher_admit: kind=doc path outside shogun allowlist: $p" >&2
                return 6
            fi
        done
    fi

    local has_db_path=0
    for p in "${paths[@]}"; do
        case "$p" in
            backend/app/db/*) has_db_path=1 ;;
        esac
    done
    if [ "$has_db_path" -eq 1 ]; then
        yaml_field_set "$req" root db_migration true
        local ack=""
        [ -f "$dir/karo.yaml" ] && ack="$(_publisher_admit_scalar "$dir/karo.yaml" migration_ack)"
        if [ -z "$ack" ]; then
            bash "$SCRIPT_DIR/lib/publisher_event.sh" append r13_reject "$cmd_id" 11 \
                "db_migration path present without migration_ack: $req" || true
            bash "$SCRIPT_DIR/inbox_write.sh" karo \
                "publisher_admit: R13却下。request=$req cmd=$cmd_id にmigration_ackが無いためadmit拒否(rc=11)" \
                investigation_result publisher_admit notify_karo >/dev/null 2>&1 || true
            return 11
        fi
    fi

    return 0
}

main() {
    local sub="${1:-}"
    if [ -z "$sub" ]; then
        echo "Usage: publisher_admit.sh admit <request.yaml>" >&2
        exit 1
    fi
    shift
    case "$sub" in
        admit) cmd_admit "$@" ;;
        *) echo "publisher_admit: unknown subcommand: $sub" >&2; exit 1 ;;
    esac
}

main "$@"
