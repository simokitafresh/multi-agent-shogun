#!/usr/bin/env bash
# ============================================================
# gate_shogun_memory.sh
# 将軍のMEMORY.md + MCP Memoryの健全性を5項目でチェックする
#
# Usage:
#   bash scripts/gates/gate_shogun_memory.sh
#
# 6項目:
#   (1) MEMORY.md行数       >150 WARN, >180 ALERT
#   (2) 陳腐化検出          completed/resolved項目の残存 → WARN
#   (3) CLAUDE.mdとの重複   cmd_ID+キーワード重複 → WARN
#   (4) MCP observation数   INFO出力のみ(スクリプトからアクセス不可)
#   (5) 最終curation日      >7日 WARN, >14日 ALERT
#   (6) MCP→lessons未同期   sync log鮮度 >7日 WARN, >14日 ALERT
#
# Exit code: 0=全OK, 1=1つ以上ALERT, 2=WARNのみ(ALERTなし)
# ============================================================
set -euo pipefail

SCRIPT_DIR="${SHOGUN_MEMORY_SCRIPT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
MEMORY_FILE="${SHOGUN_MEMORY_FILE:-$HOME/.claude/projects/-mnt-c-tools-multi-agent-shogun/memory/MEMORY.md}"
CLAUDE_MD="${SHOGUN_MEMORY_CLAUDE_MD:-$SCRIPT_DIR/CLAUDE.md}"
CHANGELOG="${SHOGUN_MEMORY_CHANGELOG:-$SCRIPT_DIR/queue/completed_changelog.yaml}"
PENDING_DECISIONS="${SHOGUN_MEMORY_PENDING_DECISIONS:-$SCRIPT_DIR/queue/pending_decisions.yaml}"

HAS_ALERT=0
HAS_WARN=0

MEMORY_LINES=-1
MEMORY_CURATED_DATE=""
declare -a MEMORY_CMD_IDS=()
declare -a MEMORY_PD_IDS=()
declare -a MEMORY_REFS=()
declare -A COMPLETED_CMD_MAP=()
declare -A RESOLVED_PD_MAP=()
declare -A CLAUDE_CMD_MAP=()
COMPLETED_CMD_LOADED=0
RESOLVED_PD_LOADED=0
CLAUDE_CMD_LOADED=0

emit_actionable() {
    local message="$1"
    local action="$2"
    echo "$message"
    echo "action: $action"
}

load_memory_cache() {
    [ "$MEMORY_LINES" -ge 0 ] && return
    [ -f "$MEMORY_FILE" ] || return

    local -A seen_cmd=()
    local -A seen_pd=()
    local -A seen_ref=()

    while IFS= read -r record; do
        case "$record" in
            LINES:*)
                MEMORY_LINES=${record#LINES:}
                ;;
            CURATED:*)
                MEMORY_CURATED_DATE=${record#CURATED:}
                ;;
            CMD:*)
                local cmd_id=${record#CMD:}
                if [ -z "${seen_cmd[$cmd_id]+x}" ]; then
                    seen_cmd["$cmd_id"]=1
                    MEMORY_CMD_IDS+=("$cmd_id")
                fi
                ;;
            PD:*)
                local pd_id=${record#PD:}
                if [ -z "${seen_pd[$pd_id]+x}" ]; then
                    seen_pd["$pd_id"]=1
                    MEMORY_PD_IDS+=("$pd_id")
                fi
                ;;
            REF:*)
                local ref_path=${record#REF:}
                if [ -z "${seen_ref[$ref_path]+x}" ]; then
                    seen_ref["$ref_path"]=1
                    MEMORY_REFS+=("$ref_path")
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

            if ($0 ~ /^[[:space:]]*\|/) {
                next
            }

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
            if (curated != "") {
                print "CURATED:" curated
            }
        }
    ' "$MEMORY_FILE")
}

load_completed_cmd_map() {
    [ "$COMPLETED_CMD_LOADED" -eq 1 ] && return
    COMPLETED_CMD_LOADED=1
    [ -f "$CHANGELOG" ] || return

    while IFS= read -r cmd_id; do
        [ -n "$cmd_id" ] && COMPLETED_CMD_MAP["$cmd_id"]=1
    done < <(awk '
        /id:[[:space:]]*cmd_[0-9]+/ {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^cmd_[0-9]+$/) {
                    print $i
                }
            }
        }
    ' "$CHANGELOG")
}

load_resolved_pd_map() {
    [ "$RESOLVED_PD_LOADED" -eq 1 ] && return
    RESOLVED_PD_LOADED=1
    [ -f "$PENDING_DECISIONS" ] || return

    while IFS= read -r pd_id; do
        [ -n "$pd_id" ] && RESOLVED_PD_MAP["$pd_id"]=1
    done < <(awk '
        /^- / {
            if (id != "" && status == "resolved") {
                print id
            }
            id = ""
            status = ""
        }
        $1 == "id:" { id = $2 }
        $1 == "status:" { status = $2 }
        END {
            if (id != "" && status == "resolved") {
                print id
            }
        }
    ' "$PENDING_DECISIONS")
}

load_claude_cmd_map() {
    [ "$CLAUDE_CMD_LOADED" -eq 1 ] && return
    CLAUDE_CMD_LOADED=1
    [ -f "$CLAUDE_MD" ] || return

    while IFS= read -r cmd_id; do
        [ -n "$cmd_id" ] && CLAUDE_CMD_MAP["$cmd_id"]=1
    done < <(grep -oE 'cmd_[0-9]+' "$CLAUDE_MD" 2>/dev/null | sort -u)
}

# ============================================================
# (1) MEMORY.md行数
# ============================================================
check_line_count() {
    if [ ! -f "$MEMORY_FILE" ]; then
        emit_actionable \
            "ALERT: MEMORY.md行数: ファイルが見つかりません($MEMORY_FILE)" \
            "MEMORY.md の配置を確認し、欠損なら復旧してから再実行せよ。"
        HAS_ALERT=1
        return
    fi

    load_memory_cache
    local lines="$MEMORY_LINES"

    if [ "$lines" -gt 180 ]; then
        emit_actionable \
            "ALERT: MEMORY.md行数: ${lines}行(>180 ALERT閾値)" \
            "MEMORY.md を棚卸しし、古い項目を整理して 180 行以下へ圧縮せよ。"
        HAS_ALERT=1
    elif [ "$lines" -gt 150 ]; then
        emit_actionable \
            "WARN: MEMORY.md行数: ${lines}行(>150 WARN閾値)" \
            "MEMORY.md を棚卸しし、不要な重複や陳腐化項目を整理せよ。"
        HAS_WARN=1
    else
        echo "OK: MEMORY.md行数: ${lines}行(健全)"
    fi
}

# ============================================================
# (2) 陳腐化検出
# ============================================================
check_staleness() {
    if [ ! -f "$MEMORY_FILE" ]; then
        emit_actionable \
            "ALERT: 陳腐化検出: MEMORY.mdが見つかりません" \
            "MEMORY.md を復旧し、completed/resolved 項目の棚卸し前提を整えよ。"
        HAS_ALERT=1
        return
    fi

    load_memory_cache
    load_completed_cmd_map
    load_resolved_pd_map

    local stale_cmds=()
    local stale_pds=()

    if [ ${#MEMORY_CMD_IDS[@]} -gt 0 ] && [ ${#COMPLETED_CMD_MAP[@]} -gt 0 ]; then
        local cmd_id
        for cmd_id in "${MEMORY_CMD_IDS[@]}"; do
            if [ -n "${COMPLETED_CMD_MAP[$cmd_id]+x}" ]; then
                stale_cmds+=("$cmd_id")
            fi
        done
    fi

    if [ ${#MEMORY_PD_IDS[@]} -gt 0 ] && [ ${#RESOLVED_PD_MAP[@]} -gt 0 ]; then
        local pd_id
        for pd_id in "${MEMORY_PD_IDS[@]}"; do
            if [ -n "${RESOLVED_PD_MAP[$pd_id]+x}" ]; then
                stale_pds+=("$pd_id")
            fi
        done
    fi

    local total_stale=$(( ${#stale_cmds[@]} + ${#stale_pds[@]} ))

    if [ "$total_stale" -gt 0 ]; then
        local details=""
        if [ ${#stale_cmds[@]} -gt 0 ]; then
            details="completed_cmd: ${stale_cmds[*]}"
        fi
        if [ ${#stale_pds[@]} -gt 0 ]; then
            [ -n "$details" ] && details+=", "
            details+="resolved_PD: ${stale_pds[*]}"
        fi
        emit_actionable \
            "WARN: 陳腐化検出: ${total_stale}件の既解決項目がMEMORY.mdに残存(${details})" \
            "既に解決済みの cmd/PD を MEMORY.md から外し、必要なら他の恒久保存先へ移せ。"
        HAS_WARN=1
    else
        echo "OK: 陳腐化検出: 既解決項目の残存なし"
    fi
}

# ============================================================
# (3) CLAUDE.mdとの重複
# ============================================================
check_duplication() {
    if [ ! -f "$MEMORY_FILE" ] || [ ! -f "$CLAUDE_MD" ]; then
        emit_actionable \
            "WARN: CLAUDE.md重複: ファイル不在のためスキップ" \
            "MEMORY.md と CLAUDE.md の配置を確認し、重複監査できる状態へ戻せ。"
        HAS_WARN=1
        return
    fi

    load_memory_cache
    load_claude_cmd_map

    local dup_cmds=()
    local cmd_id
    for cmd_id in "${MEMORY_CMD_IDS[@]}"; do
        if [ -n "${CLAUDE_CMD_MAP[$cmd_id]+x}" ]; then
            dup_cmds+=("$cmd_id")
        fi
    done

    if [ ${#dup_cmds[@]} -gt 0 ]; then
        emit_actionable \
            "WARN: CLAUDE.md重複: ${#dup_cmds[@]}件のcmd_IDがMEMORY.mdとCLAUDE.mdの両方に存在(${dup_cmds[*]})" \
            "重複 cmd を整理し、MEMORY.md と CLAUDE.md の役割分担を回復せよ。"
        HAS_WARN=1
    else
        echo "OK: CLAUDE.md重複: MEMORY.mdとCLAUDE.mdの重複なし"
    fi
}

# ============================================================
# (4) MCP observation数
# ============================================================
check_mcp() {
    echo "INFO: MCP observation数: MCPはスクリプトからアクセス不可。将軍がread_graph結果を手動確認する際のリマインダー"
}

# ============================================================
# (5) 最終curation日
# ============================================================
check_last_curated() {
    if [ ! -f "$MEMORY_FILE" ]; then
        emit_actionable \
            "ALERT: 最終curation日: MEMORY.mdが見つかりません" \
            "MEMORY.md を復旧し、curation 日付を記録できる状態へ戻せ。"
        HAS_ALERT=1
        return
    fi

    load_memory_cache
    local curated_date="$MEMORY_CURATED_DATE"

    if [ -z "$curated_date" ]; then
        emit_actionable \
            "WARN: 最終curation日: Meta欄なし。/shogun-memory-teire推奨" \
            "Meta 欄へ Last curated を追加し、/shogun-memory-teire を実行せよ。"
        HAS_WARN=1
        return
    fi

    local today_epoch curated_epoch days_ago
    today_epoch=$(date +%s)
    curated_epoch=$(date -d "$curated_date" +%s 2>/dev/null) || {
        emit_actionable \
            "WARN: 最終curation日: 日付パース失敗($curated_date)" \
            "Last curated の日付形式を YYYY-MM-DD に修正せよ。"
        HAS_WARN=1
        return
    }

    days_ago=$(( (today_epoch - curated_epoch) / 86400 ))

    if [ "$days_ago" -gt 14 ]; then
        emit_actionable \
            "ALERT: 最終curation日: ${curated_date}(${days_ago}日前 >14日 ALERT閾値)" \
            "MEMORY.md を直ちに棚卸しし、Last curated を今日の日付へ更新せよ。"
        HAS_ALERT=1
    elif [ "$days_ago" -gt 7 ]; then
        emit_actionable \
            "WARN: 最終curation日: ${curated_date}(${days_ago}日前 >7日 WARN閾値)" \
            "近いうちに MEMORY.md を棚卸しし、Last curated を更新せよ。"
        HAS_WARN=1
    else
        echo "OK: 最終curation日: ${curated_date}(${days_ago}日前、健全)"
    fi
}

# ============================================================
# (6) MCP→lessons未同期チェック (cmd_735)
#     staging YAML vs tracker の差分比較で未同期を検知
# ============================================================
check_mcp_sync() {
    local staging_file="${SHOGUN_MEMORY_STAGING_FILE:-$SCRIPT_DIR/queue/mcp_sync_staging.yaml}"
    local tracker_file="${SHOGUN_MEMORY_TRACKER_FILE:-$SCRIPT_DIR/queue/mcp_sync_tracker.yaml}"
    local sync_log="${SHOGUN_MEMORY_SYNC_LOG:-$SCRIPT_DIR/logs/mcp_sync.log}"

    # staging file がなければ同期対象なし → OK
    if [ ! -f "$staging_file" ]; then
        echo "OK: MCP同期: staging fileなし(同期対象なし)"
        return
    fi

    # tracker がなければ全件未同期
    if [ ! -f "$tracker_file" ]; then
        # staging に entries があるかチェック
        local has_entries
        has_entries=$(STAGING_FILE="$staging_file" python3 - <<'PYEOF' 2>/dev/null
import os

path = os.environ["STAGING_FILE"]
count = 0
in_entries = False

with open(path, encoding="utf-8") as fh:
    for raw in fh:
        line = raw.rstrip("\n")
        if not in_entries:
            if line.startswith("entries:"):
                in_entries = True
            continue
        if line and not line[:1].isspace() and not line.startswith("- "):
            break
        if line.lstrip().startswith("- "):
            count += 1

print(count)
PYEOF
) || has_entries="0"

        if [ "$has_entries" -gt 0 ]; then
            emit_actionable \
                "WARN: MCP同期: tracker未作成。${has_entries}件の未同期[share:ninja]あり" \
                "mcp_sync_lesson.sh を実行し、tracker を作成して staging を同期せよ。"
            HAS_WARN=1
        else
            echo "OK: MCP同期: staging空、tracker未作成(同期対象なし)"
        fi
        return
    fi

    # staging vs tracker 差分比較 (python3)
    local result
    result=$(STAGING_FILE="$staging_file" TRACKER_FILE="$tracker_file" python3 << 'PYEOF'
import hashlib
import json
import os
import sys

staging_file = os.environ["STAGING_FILE"]
tracker_file = os.environ["TRACKER_FILE"]


def parse_scalar(raw: str) -> str:
    value = raw.strip()
    if not value:
        return ""
    if value.startswith('"'):
        return json.loads(value)
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1].replace("''", "'")
    return value


def parse_block_list(path: str, root_key: str):
    items = []
    current = None
    in_root = False
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not in_root:
                if line.startswith(f"{root_key}:"):
                    in_root = True
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

            if current is None or ":" not in stripped:
                continue

            key, value = stripped.split(":", 1)
            current[key.strip()] = parse_scalar(value)

    if current is not None:
        items.append(current)
    return items


entries = parse_block_list(staging_file, "entries")
if not entries:
    print("OK:0")
    sys.exit(0)

tracked_hashes = {
    item.get("hash")
    for item in parse_block_list(tracker_file, "synced")
    if item.get("hash")
}

unsynced = 0
for entry in entries:
    obs = entry.get("observation", "")
    if not obs:
        continue
    project = entry.get("project", "infra")
    digest = hashlib.sha256(f"{project}:{obs}".encode("utf-8")).hexdigest()[:16]
    if digest not in tracked_hashes:
        unsynced += 1

print(f"RESULT:{unsynced}:{len(entries)}")
PYEOF
    ) || {
        emit_actionable \
            "WARN: MCP同期: 差分比較スクリプト実行失敗" \
            "staging/tracker YAML の内容と python3 実行環境を確認せよ。"
        HAS_WARN=1
        return
    }

    if [[ "$result" == OK:* ]]; then
        echo "OK: MCP同期: staging空(同期対象なし)"
        return
    fi

    local unsynced_count total_count
    unsynced_count=$(echo "$result" | cut -d: -f2)
    total_count=$(echo "$result" | cut -d: -f3)

    if [ "$unsynced_count" -gt 0 ]; then
        emit_actionable \
            "WARN: MCP同期: ${unsynced_count}/${total_count}件の未同期[share:ninja]あり。mcp_sync_lesson.sh実行推奨" \
            "mcp_sync_lesson.sh を実行し、未同期 entry を lessons 側へ反映せよ。"
        HAS_WARN=1
    else
        echo "OK: MCP同期: 全${total_count}件同期済み"
    fi

    # 補助チェック: 同期ログの鮮度(同期自体が長期未実行でないか)
    if [ -f "$sync_log" ]; then
        local last_date
        last_date=$(awk '
            /^[0-9]{4}-[0-9]{2}-[0-9]{2}/ { last=$1 }
            END { print last }
        ' "$sync_log")
        if [ -n "$last_date" ]; then
            local today_epoch last_epoch days_ago
            today_epoch=$(date +%s)
            last_epoch=$(date -d "$last_date" +%s 2>/dev/null) || return
            days_ago=$(( (today_epoch - last_epoch) / 86400 ))
            if [ "$days_ago" -gt 14 ]; then
                emit_actionable \
                    "WARN: MCP同期(鮮度): 最終同期${last_date}(${days_ago}日前 >14日)" \
                    "mcp_sync_lesson.sh を再実行し、同期ログの鮮度を更新せよ。"
                HAS_WARN=1
            fi
        fi
    fi
}

# ============================================================
# (7) MEMORY.md参照ファイル実在チェック
#     索引内の全 `memory/*.md` パスが実ファイルとして存在するか検証
#     ハードコードなし。索引が増えれば自動的にチェック対象が増える
# ============================================================
check_referenced_files() {
    if [ ! -f "$MEMORY_FILE" ]; then
        return
    fi

    local memory_dir
    memory_dir="$(dirname "$MEMORY_FILE")"

    load_memory_cache

    local missing=()
    local checked=0
    local ref_path

    for ref_path in "${MEMORY_REFS[@]}"; do
        [ -z "$ref_path" ] && continue
        local basename_ref
        basename_ref="${ref_path#memory/}"
        local full_path="$memory_dir/$basename_ref"
        local alt_path="$SCRIPT_DIR/memory/$basename_ref"
        checked=$((checked + 1))
        if [ ! -f "$full_path" ] && [ ! -f "$alt_path" ]; then
            missing+=("$ref_path")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        emit_actionable \
            "ALERT: 参照ファイル不在: ${#missing[@]}件 — ${missing[*]}" \
            "MEMORY.md が参照するファイルが存在しない。配置するか索引を修正せよ。"
        HAS_ALERT=1
    else
        echo "OK: 参照ファイル実在: ${checked}件全て存在"
    fi
}

# ============================================================
# メイン処理
# ============================================================
check_line_count
check_staleness
check_duplication
check_mcp
check_last_curated
check_mcp_sync
check_referenced_files

# 総合判定
if [ "$HAS_ALERT" -gt 0 ]; then
    echo "--- 総合判定: ALERT ---"
    exit 1
elif [ "$HAS_WARN" -gt 0 ]; then
    echo "--- 総合判定: WARN ---"
    exit 2
else
    echo "--- 総合判定: OK ---"
    exit 0
fi
