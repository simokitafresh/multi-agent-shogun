#!/usr/bin/env bash
# ============================================================
# gate_shogun_memory.sh
# 将軍のMEMORY.md + MCP Memoryの健全性を5項目でチェックする
#
# Usage:
#   bash scripts/gates/gate_shogun_memory.sh
#
# 5項目:
#   (1) MEMORY.md行数       >150 WARN, >180 ALERT
#   (2) 陳腐化検出          completed/resolved項目の残存 → WARN
#   (3) CLAUDE.mdとの重複   cmd_ID+キーワード重複 → WARN
#   (4) MCP observation数   INFO出力のみ(スクリプトからアクセス不可)
#   (5) 最終curation日      >7日 WARN, >14日 ALERT
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

# ============================================================
# (1) MEMORY.md行数
# ============================================================
check_line_count() {
    if [ ! -f "$MEMORY_FILE" ]; then
        echo "ALERT: MEMORY.md行数: ファイルが見つかりません($MEMORY_FILE)"
        HAS_ALERT=1
        return
    fi

    local lines
    lines=$(wc -l < "$MEMORY_FILE")

    if [ "$lines" -gt 180 ]; then
        echo "ALERT: MEMORY.md行数: ${lines}行(>180 ALERT閾値)"
        HAS_ALERT=1
    elif [ "$lines" -gt 150 ]; then
        echo "WARN: MEMORY.md行数: ${lines}行(>150 WARN閾値)"
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
        echo "ALERT: 陳腐化検出: MEMORY.mdが見つかりません"
        HAS_ALERT=1
        return
    fi

    local stale_cmds=()
    local stale_pds=()

    # MEMORY.md内のcmd_XXXパターンを抽出(ユニーク)
    local -a cmd_ids
    mapfile -t cmd_ids < <(grep -oE 'cmd_[0-9]+' "$MEMORY_FILE" 2>/dev/null | sort -u)

    # completed_changelog.yamlと照合
    if [ -f "$CHANGELOG" ] && [ ${#cmd_ids[@]} -gt 0 ]; then
        for cmd_id in "${cmd_ids[@]}"; do
            if grep -q "id: ${cmd_id}" "$CHANGELOG" 2>/dev/null; then
                stale_cmds+=("$cmd_id")
            fi
        done
    fi

    # MEMORY.md内のPD-XXXパターンを抽出(ユニーク)
    local -a pd_ids
    mapfile -t pd_ids < <(grep -oE 'PD-[0-9]+' "$MEMORY_FILE" 2>/dev/null | sort -u)

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
        echo "WARN: 陳腐化検出: ${total_stale}件の既解決項目がMEMORY.mdに残存(${details})"
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
        echo "WARN: CLAUDE.md重複: ファイル不在のためスキップ"
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
        echo "WARN: CLAUDE.md重複: ${#dup_cmds[@]}件のcmd_IDがMEMORY.mdとCLAUDE.mdの両方に存在(${dup_cmds[*]})"
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
        echo "ALERT: 最終curation日: MEMORY.mdが見つかりません"
        HAS_ALERT=1
        return
    fi

    # Meta欄の「Last curated:」から日付取得
    local curated_date
    curated_date=$(grep -oE 'Last curated:[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}' "$MEMORY_FILE" 2>/dev/null \
        | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')

    if [ -z "$curated_date" ]; then
        echo "WARN: 最終curation日: Meta欄なし。/shogun-memory-teire推奨"
        HAS_WARN=1
        return
    fi

    local today_epoch curated_epoch days_ago
    today_epoch=$(date +%s)
    curated_epoch=$(date -d "$curated_date" +%s 2>/dev/null) || {
        echo "WARN: 最終curation日: 日付パース失敗($curated_date)"
        HAS_WARN=1
        return
    }

    days_ago=$(( (today_epoch - curated_epoch) / 86400 ))

    if [ "$days_ago" -gt 14 ]; then
        echo "ALERT: 最終curation日: ${curated_date}(${days_ago}日前 >14日 ALERT閾値)"
        HAS_ALERT=1
    elif [ "$days_ago" -gt 7 ]; then
        echo "WARN: 最終curation日: ${curated_date}(${days_ago}日前 >7日 WARN閾値)"
        HAS_WARN=1
    else
        echo "OK: 最終curation日: ${curated_date}(${days_ago}日前、健全)"
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
