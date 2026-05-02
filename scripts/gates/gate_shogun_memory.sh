#!/usr/bin/env bash
# gate_shogun_memory.sh - MEMORY.md + MCP Memory health gate.
#
# Usage:
#   bash scripts/gates/gate_shogun_memory.sh
#
# Exit code: 0=OK, 1=ALERT, 2=WARN only
set -euo pipefail

if [ -n "${SHOGUN_MEMORY_SCRIPT_DIR:-}" ]; then
    SCRIPT_DIR="$SHOGUN_MEMORY_SCRIPT_DIR"
else
    _self="${BASH_SOURCE[0]}"
    _dir="${_self%/*}"
    case "$_dir" in
        */scripts/gates) SCRIPT_DIR="${_dir%/scripts/gates}" ;;
        scripts/gates) SCRIPT_DIR="." ;;
        *) SCRIPT_DIR="$(cd "$_dir/../.." && pwd)" ;;
    esac
fi

MEMORY_FILE="${SHOGUN_MEMORY_FILE:-$HOME/.claude/projects/-mnt-c-tools-multi-agent-shogun/memory/MEMORY.md}"
CLAUDE_MD="${SHOGUN_MEMORY_CLAUDE_MD:-$SCRIPT_DIR/CLAUDE.md}"
CHANGELOG="${SHOGUN_MEMORY_CHANGELOG:-$SCRIPT_DIR/queue/completed_changelog.yaml}"
PENDING_DECISIONS="${SHOGUN_MEMORY_PENDING_DECISIONS:-$SCRIPT_DIR/queue/pending_decisions.yaml}"
HAS_ALERT=0
HAS_WARN=0

emit_actionable() {
    printf '%s\n' "$1"
    printf 'action: %s\n' "$2"
}

warn() {
    HAS_WARN=1
    emit_actionable "$1" "$2"
}

alert() {
    HAS_ALERT=1
    emit_actionable "$1" "$2"
}

declare -a MEMORY_CMD_IDS=()
declare -a MEMORY_PD_IDS=()
declare -a MEMORY_REFS=()
MEMORY_LINES=-1
MEMORY_CURATED_DATE=""

load_memory_cache() {
    [ "$MEMORY_LINES" -ge 0 ] && return
    [ -f "$MEMORY_FILE" ] || return

    local record kind value
    local -A seen_cmd=()
    local -A seen_pd=()
    local -A seen_ref=()
    while IFS= read -r record; do
        kind="${record%%:*}"
        value="${record#*:}"
        case "$kind" in
            LINES) MEMORY_LINES="$value" ;;
            CURATED) MEMORY_CURATED_DATE="$value" ;;
            CMD)
                if [ -z "${seen_cmd[$value]+x}" ]; then
                    seen_cmd["$value"]=1
                    MEMORY_CMD_IDS+=("$value")
                fi
                ;;
            PD)
                if [ -z "${seen_pd[$value]+x}" ]; then
                    seen_pd["$value"]=1
                    MEMORY_PD_IDS+=("$value")
                fi
                ;;
            REF)
                if [ -z "${seen_ref[$value]+x}" ]; then
                    seen_ref["$value"]=1
                    MEMORY_REFS+=("$value")
                fi
                ;;
        esac
    done < <(awk '
        {
            lines++
            if (curated == "" && index($0, "Last curated:") > 0 && match($0, /[0-9]{4}-[0-9]{2}-[0-9]{2}/)) {
                curated = substr($0, RSTART, RLENGTH)
            }
            ref_line = $0
            while (match(ref_line, /memory\/[A-Za-z0-9_-]+\.md/)) {
                print "REF:" substr(ref_line, RSTART, RLENGTH)
                ref_line = substr(ref_line, RSTART + RLENGTH)
            }
            if ($0 ~ /^[[:space:]]*\|/) next
            cmd_line = $0
            while (match(cmd_line, /cmd_[0-9]+/)) {
                print "CMD:" substr(cmd_line, RSTART, RLENGTH)
                cmd_line = substr(cmd_line, RSTART + RLENGTH)
            }
            pd_line = $0
            while (match(pd_line, /PD-[0-9]+/)) {
                print "PD:" substr(pd_line, RSTART, RLENGTH)
                pd_line = substr(pd_line, RSTART + RLENGTH)
            }
        }
        END {
            print "LINES:" lines
            if (curated != "") print "CURATED:" curated
        }
    ' "$MEMORY_FILE")
}

check_line_count() {
    if [ ! -f "$MEMORY_FILE" ]; then
        alert "ALERT: MEMORY.md行数: ファイルが見つかりません($MEMORY_FILE)" \
            "MEMORY.md の配置を確認し、欠損なら復旧してから再実行せよ。"
        return
    fi

    load_memory_cache
    if [ "$MEMORY_LINES" -gt 180 ]; then
        alert "ALERT: MEMORY.md行数: ${MEMORY_LINES}行(>180 ALERT閾値)" \
            "MEMORY.md を棚卸しし、古い項目を整理して 180 行以下へ圧縮せよ。"
    elif [ "$MEMORY_LINES" -gt 150 ]; then
        warn "WARN: MEMORY.md行数: ${MEMORY_LINES}行(>150 WARN閾値)" \
            "MEMORY.md を棚卸しし、不要な重複や陳腐化項目を整理せよ。"
    else
        printf 'OK: MEMORY.md行数: %s行(健全)\n' "$MEMORY_LINES"
    fi
}

check_staleness() {
    if [ ! -f "$MEMORY_FILE" ]; then
        alert "ALERT: 陳腐化検出: MEMORY.mdが見つかりません" \
            "MEMORY.md を復旧し、completed/resolved 項目の棚卸し前提を整えよ。"
        return
    fi

    load_memory_cache
    local stale_cmds=()
    local stale_pds=()
    local id

    if [ -f "$CHANGELOG" ]; then
        local -A completed=()
        while IFS= read -r id; do
            [ -n "$id" ] && completed["$id"]=1
        done < <(awk '/id:[[:space:]]*cmd_[0-9]+/ { for (i=1; i<=NF; i++) if ($i ~ /^cmd_[0-9]+$/) print $i }' "$CHANGELOG")
        for id in "${MEMORY_CMD_IDS[@]}"; do
            [ -n "${completed[$id]+x}" ] && stale_cmds+=("$id")
        done
    fi

    if [ -f "$PENDING_DECISIONS" ]; then
        local -A resolved=()
        while IFS= read -r id; do
            [ -n "$id" ] && resolved["$id"]=1
        done < <(awk '
            /^- / { if (id != "" && status == "resolved") print id; id=""; status="" }
            $1 == "id:" { id=$2 }
            $1 == "status:" { status=$2 }
            END { if (id != "" && status == "resolved") print id }
        ' "$PENDING_DECISIONS")
        for id in "${MEMORY_PD_IDS[@]}"; do
            [ -n "${resolved[$id]+x}" ] && stale_pds+=("$id")
        done
    fi

    local total=$(( ${#stale_cmds[@]} + ${#stale_pds[@]} ))
    if [ "$total" -eq 0 ]; then
        printf 'OK: 陳腐化検出: 既解決項目の残存なし\n'
        return
    fi

    local details=""
    if [ ${#stale_cmds[@]} -gt 0 ]; then
        details="completed_cmd: ${stale_cmds[*]}"
    fi
    if [ ${#stale_pds[@]} -gt 0 ]; then
        [ -n "$details" ] && details+=", "
        details+="resolved_PD: ${stale_pds[*]}"
    fi
    warn "WARN: 陳腐化検出: ${total}件の既解決項目がMEMORY.mdに残存(${details})" \
        "既に解決済みの cmd/PD を MEMORY.md から外し、必要なら他の恒久保存先へ移せ。"
}

check_duplication() {
    if [ ! -f "$MEMORY_FILE" ] || [ ! -f "$CLAUDE_MD" ]; then
        warn "WARN: CLAUDE.md重複: ファイル不在のためスキップ" \
            "MEMORY.md と CLAUDE.md の配置を確認し、重複監査できる状態へ戻せ。"
        return
    fi

    load_memory_cache
    local -A claude_cmd=()
    local id
    while IFS= read -r id; do
        [ -n "$id" ] && claude_cmd["$id"]=1
    done < <(grep -oE 'cmd_[0-9]+' "$CLAUDE_MD" 2>/dev/null | sort -u)

    local dup_cmds=()
    for id in "${MEMORY_CMD_IDS[@]}"; do
        [ -n "${claude_cmd[$id]+x}" ] && dup_cmds+=("$id")
    done

    if [ ${#dup_cmds[@]} -gt 0 ]; then
        warn "WARN: CLAUDE.md重複: ${#dup_cmds[@]}件のcmd_IDがMEMORY.mdとCLAUDE.mdの両方に存在(${dup_cmds[*]})" \
            "重複 cmd を整理し、MEMORY.md と CLAUDE.md の役割分担を回復せよ。"
    else
        printf 'OK: CLAUDE.md重複: MEMORY.mdとCLAUDE.mdの重複なし\n'
    fi
}

check_mcp() {
    printf 'INFO: MCP observation数: MCPはスクリプトからアクセス不可。将軍がread_graph結果を手動確認する際のリマインダー\n'
}

check_last_curated() {
    if [ ! -f "$MEMORY_FILE" ]; then
        alert "ALERT: 最終curation日: MEMORY.mdが見つかりません" \
            "MEMORY.md を復旧し、curation 日付を記録できる状態へ戻せ。"
        return
    fi

    load_memory_cache
    if [ -z "$MEMORY_CURATED_DATE" ]; then
        warn "WARN: 最終curation日: Meta欄なし。/shogun-memory-teire推奨" \
            "Meta 欄へ Last curated を追加し、/shogun-memory-teire を実行せよ。"
        return
    fi

    local today_epoch curated_epoch days_ago
    today_epoch=$(date +%s)
    curated_epoch=$(date -d "$MEMORY_CURATED_DATE" +%s 2>/dev/null) || {
        warn "WARN: 最終curation日: 日付パース失敗($MEMORY_CURATED_DATE)" \
            "Last curated の日付形式を YYYY-MM-DD に修正せよ。"
        return
    }
    days_ago=$(( (today_epoch - curated_epoch) / 86400 ))

    if [ "$days_ago" -gt 14 ]; then
        alert "ALERT: 最終curation日: ${MEMORY_CURATED_DATE}(${days_ago}日前 >14日 ALERT閾値)" \
            "MEMORY.md を直ちに棚卸しし、Last curated を今日の日付へ更新せよ。"
    elif [ "$days_ago" -gt 7 ]; then
        warn "WARN: 最終curation日: ${MEMORY_CURATED_DATE}(${days_ago}日前 >7日 WARN閾値)" \
            "近いうちに MEMORY.md を棚卸しし、Last curated を更新せよ。"
    else
        printf 'OK: 最終curation日: %s(%s日前、健全)\n' "$MEMORY_CURATED_DATE" "$days_ago"
    fi
}

_count_staging_entries() {
    awk '
        /^entries:/ { in_entries=1; next }
        in_entries && $0 !~ /^([[:space:]]|$|- )/ { exit }
        in_entries && /^[[:space:]]*- / { count++ }
        END { print count + 0 }
    ' "$1"
}

check_mcp_sync() {
    local staging_file="${SHOGUN_MEMORY_STAGING_FILE:-$SCRIPT_DIR/queue/mcp_sync_staging.yaml}"
    local tracker_file="${SHOGUN_MEMORY_TRACKER_FILE:-$SCRIPT_DIR/queue/mcp_sync_tracker.yaml}"
    local sync_log="${SHOGUN_MEMORY_SYNC_LOG:-$SCRIPT_DIR/logs/mcp_sync.log}"

    if [ ! -f "$staging_file" ]; then
        printf 'OK: MCP同期: staging fileなし(同期対象なし)\n'
        return
    fi

    local total_count
    total_count="$(_count_staging_entries "$staging_file")"
    if [ "$total_count" -eq 0 ]; then
        if [ -f "$tracker_file" ]; then
            printf 'OK: MCP同期: staging空(同期対象なし)\n'
        else
            printf 'OK: MCP同期: staging空、tracker未作成(同期対象なし)\n'
        fi
        return
    fi

    if [ ! -f "$tracker_file" ]; then
        warn "WARN: MCP同期: tracker未作成。${total_count}件の未同期[share:ninja]あり" \
            "mcp_sync_lesson.sh を実行し、tracker を作成して staging を同期せよ。"
        return
    fi

    local unsynced_count
    unsynced_count=$(STAGING_FILE="$staging_file" TRACKER_FILE="$tracker_file" python3 - <<'PYEOF'
import hashlib
import json
import os

def parse_scalar(raw):
    value = raw.strip()
    if value.startswith('"'):
        return json.loads(value)
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1].replace("''", "'")
    return value

def parse_block_list(path, root):
    items, current, in_root = [], None, False
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not in_root:
                in_root = line.startswith(f"{root}:")
                continue
            if line and not line[:1].isspace() and not line.startswith("- "):
                break
            stripped = line.lstrip()
            if stripped.startswith("- "):
                if current is not None:
                    items.append(current)
                current = {}
                remainder = stripped[2:]
                if ":" in remainder:
                    key, value = remainder.split(":", 1)
                    current[key.strip()] = parse_scalar(value)
                continue
            if current is not None and ":" in stripped:
                key, value = stripped.split(":", 1)
                current[key.strip()] = parse_scalar(value)
    if current is not None:
        items.append(current)
    return items

entries = parse_block_list(os.environ["STAGING_FILE"], "entries")
tracked = {item.get("hash") for item in parse_block_list(os.environ["TRACKER_FILE"], "synced") if item.get("hash")}
unsynced = 0
for entry in entries:
    obs = entry.get("observation", "")
    if not obs:
        continue
    project = entry.get("project", "infra")
    digest = hashlib.sha256(f"{project}:{obs}".encode()).hexdigest()[:16]
    if digest not in tracked:
        unsynced += 1
print(unsynced)
PYEOF
    ) || {
        warn "WARN: MCP同期: 差分比較スクリプト実行失敗" \
            "staging/tracker YAML の内容と python3 実行環境を確認せよ。"
        return
    }

    if [ "$unsynced_count" -gt 0 ]; then
        warn "WARN: MCP同期: ${unsynced_count}/${total_count}件の未同期[share:ninja]あり。mcp_sync_lesson.sh実行推奨" \
            "mcp_sync_lesson.sh を実行し、未同期 entry を lessons 側へ反映せよ。"
    else
        printf 'OK: MCP同期: 全%s件同期済み\n' "$total_count"
    fi

    if [ -f "$sync_log" ]; then
        local last_date today_epoch last_epoch days_ago
        last_date=$(awk '/^[0-9]{4}-[0-9]{2}-[0-9]{2}/ { last=$1 } END { print last }' "$sync_log")
        if [ -n "$last_date" ]; then
            today_epoch=$(date +%s)
            last_epoch=$(date -d "$last_date" +%s 2>/dev/null) || return
            days_ago=$(( (today_epoch - last_epoch) / 86400 ))
            if [ "$days_ago" -gt 14 ]; then
                warn "WARN: MCP同期(鮮度): 最終同期${last_date}(${days_ago}日前 >14日)" \
                    "mcp_sync_lesson.sh を再実行し、同期ログの鮮度を更新せよ。"
            fi
        fi
    fi
}

check_referenced_files() {
    [ -f "$MEMORY_FILE" ] || return
    load_memory_cache

    local memory_dir ref_path basename_ref full_path alt_path
    local checked=0
    local missing=()
    memory_dir="${MEMORY_FILE%/*}"

    for ref_path in "${MEMORY_REFS[@]}"; do
        [ -z "$ref_path" ] && continue
        basename_ref="${ref_path#memory/}"
        full_path="$memory_dir/$basename_ref"
        alt_path="$SCRIPT_DIR/memory/$basename_ref"
        checked=$((checked + 1))
        if [ ! -f "$full_path" ] && [ ! -f "$alt_path" ]; then
            missing+=("$ref_path")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        alert "ALERT: 参照ファイル不在: ${#missing[@]}件 — ${missing[*]}" \
            "MEMORY.md が参照するファイルが存在しない。配置するか索引を修正せよ。"
    else
        printf 'OK: 参照ファイル実在: %s件全て存在\n' "$checked"
    fi
}

check_line_count
if [ "$HAS_ALERT" -gt 0 ] && [ "${SHOGUN_MEMORY_FULL_SCAN:-0}" != "1" ]; then
    printf 'INFO: 後続チェック: MEMORY.md行数ALERTのため省略(SHOGUN_MEMORY_FULL_SCAN=1で全項目実行)\n'
    printf '%s\n' '--- 総合判定: ALERT ---'
    exit 1
fi
check_staleness
check_duplication
check_mcp
check_last_curated
check_mcp_sync
check_referenced_files

if [ "$HAS_ALERT" -gt 0 ]; then
    printf '%s\n' '--- 総合判定: ALERT ---'
    exit 1
elif [ "$HAS_WARN" -gt 0 ]; then
    printf '%s\n' '--- 総合判定: WARN ---'
    exit 2
fi

printf '%s\n' '--- 総合判定: OK ---'
