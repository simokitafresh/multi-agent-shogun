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

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MEMORY_FILE="$HOME/.claude/projects/-mnt-c-tools-multi-agent-shogun/memory/MEMORY.md"
CLAUDE_MD="$SCRIPT_DIR/CLAUDE.md"
CHANGELOG="$SCRIPT_DIR/queue/completed_changelog.yaml"
PENDING_DECISIONS="$SCRIPT_DIR/queue/pending_decisions.yaml"

HAS_ALERT=0
HAS_WARN=0

emit_actionable() {
    local message="$1"
    local action="$2"
    echo "$message"
    echo "action: $action"
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

    local lines
    lines=$(wc -l < "$MEMORY_FILE")

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

    local stale_cmds=()
    local stale_pds=()

    # MEMORY.md内のcmd_XXXパターンを抽出(ユニーク)
    # MCP Memory Indexテーブル行(|始まり)は除外 — 教訓の出典cmd等は陳腐化対象外
    local -a cmd_ids
    mapfile -t cmd_ids < <(grep -v '^\s*|' "$MEMORY_FILE" 2>/dev/null | grep -oE 'cmd_[0-9]+' | sort -u)

    # completed_changelog.yamlと照合
    if [ -f "$CHANGELOG" ] && [ ${#cmd_ids[@]} -gt 0 ]; then
        for cmd_id in "${cmd_ids[@]}"; do
            if grep -q "id: ${cmd_id}" "$CHANGELOG" 2>/dev/null; then
                stale_cmds+=("$cmd_id")
            fi
        done
    fi

    # MEMORY.md内のPD-XXXパターンを抽出(ユニーク)
    # MCP Memory Indexテーブル行(|始まり)は除外 — 裁定記録PDは陳腐化対象外
    local -a pd_ids
    mapfile -t pd_ids < <(grep -v '^\s*|' "$MEMORY_FILE" 2>/dev/null | grep -oE 'PD-[0-9]+' | sort -u)

    # pending_decisions.yamlと照合(resolvedのもの)
    if [ -f "$PENDING_DECISIONS" ] && [ ${#pd_ids[@]} -gt 0 ]; then
        for pd_id in "${pd_ids[@]}"; do
            # そのPD IDのブロックを取得し、status: resolvedか確認
            if awk -v id="$pd_id" '
                /^- / { in_block=0 }
                $0 ~ "id: " id { in_block=1 }
                in_block && /[[:space:]]+status:[[:space:]]+resolved/ { found=1; exit }
                END { exit !found }
            ' "$PENDING_DECISIONS" 2>/dev/null; then
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

    # MEMORY.md内の「cmd_XXX完了」パターンを持つ行からcmd_IDを抽出
    local -a memory_completed_cmds
    mapfile -t memory_completed_cmds < <(grep -oE 'cmd_[0-9]+' "$MEMORY_FILE" 2>/dev/null | sort -u)

    local dup_cmds=()
    for cmd_id in "${memory_completed_cmds[@]}"; do
        if grep -q "$cmd_id" "$CLAUDE_MD" 2>/dev/null; then
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

    # Meta欄の「Last curated:」から日付取得
    local curated_date
    curated_date=$(grep -oE 'Last curated:[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}' "$MEMORY_FILE" 2>/dev/null \
        | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')

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
    local staging_file="$SCRIPT_DIR/queue/mcp_sync_staging.yaml"
    local tracker_file="$SCRIPT_DIR/queue/mcp_sync_tracker.yaml"
    local sync_log="$SCRIPT_DIR/logs/mcp_sync.log"

    # staging file がなければ同期対象なし → OK
    if [ ! -f "$staging_file" ]; then
        echo "OK: MCP同期: staging fileなし(同期対象なし)"
        return
    fi

    # tracker がなければ全件未同期
    if [ ! -f "$tracker_file" ]; then
        # staging に entries があるかチェック
        local has_entries
        has_entries=$(python3 -c "
import yaml, sys
with open('$staging_file', encoding='utf-8') as f:
    d = yaml.safe_load(f) or {}
print(len(d.get('entries', [])))
" 2>/dev/null) || has_entries="0"

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
import yaml, hashlib, sys, os

staging_file = os.environ["STAGING_FILE"]
tracker_file = os.environ["TRACKER_FILE"]

with open(staging_file, encoding='utf-8') as f:
    staging = yaml.safe_load(f) or {}

with open(tracker_file, encoding='utf-8') as f:
    tracker = yaml.safe_load(f) or {}

entries = staging.get('entries', [])
if not entries:
    print("OK:0")
    sys.exit(0)

# Build set of tracked hashes
tracked_hashes = set()
for item in tracker.get('synced', []) or []:
    if isinstance(item, dict) and 'hash' in item:
        tracked_hashes.add(item['hash'])

# Count unsynced: hash = sha256(project:observation)
unsynced = 0
for entry in entries:
    obs = entry.get('observation', '')
    if not obs:
        continue
    project = entry.get('project', 'infra')
    h = hashlib.sha256(f"{project}:{obs}".encode('utf-8')).hexdigest()[:16]
    if h not in tracked_hashes:
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
        last_date=$(tail -1 "$sync_log" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}')
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
# メイン処理
# ============================================================
check_line_count
check_staleness
check_duplication
check_mcp
check_last_curated
check_mcp_sync

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
