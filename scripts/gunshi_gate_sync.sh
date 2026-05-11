#!/usr/bin/env bash
# gunshi_gate_sync.sh — review_feedbackからgate_resultを自動更新
# 用途: inbox内のreview_feedbackメッセージを走査し、
#       gunshi_review_log.yamlのgate_result: nullを更新する
# 起源: GP-173セッション。55件のgate_result: null蓄積の真因=手動更新の自動化不在
# 実行: bash scripts/gunshi_gate_sync.sh [--dry-run]

set -euo pipefail
cd "$(dirname "$0")/.."

REVIEW_LOG="logs/gunshi_review_log.yaml"
INBOX="queue/inbox/gunshi.yaml"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# アーカイブログも対象に含める
ARCHIVE_LOGS=()
for f in logs/archive/gunshi_review_log_*.yaml; do
    [[ -f "$f" ]] && ARCHIVE_LOGS+=("$f")
done

updated=0
skipped=0

# inbox + archiveのreview_feedbackから gate_result: CLEAR/BLOCK パターンを抽出
extract_gate_results() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    grep -E 'gate_result: (CLEAR|BLOCK)' "$file" 2>/dev/null | while read -r line; do
        # パターン: "{cmd_id} gate_result: {CLEAR|BLOCK}" or "{cmd_id} gate_result: {BLOCK} reason=..."
        local cmd_id gate_result
        cmd_id=$(echo "$line" | grep -oP '\b(cmd_\S+|karo_\S+)\s+gate_result:' | awk '{print $1}')
        gate_result=$(echo "$line" | grep -oP 'gate_result: (CLEAR|BLOCK)' | awk '{print $2}')
        [[ -n "$cmd_id" && -n "$gate_result" ]] && echo "$cmd_id $gate_result"
    done
}

# 全ソースからgate_result情報を収集
declare -A GATE_MAP
while read -r cmd_id result; do
    [[ -n "$cmd_id" ]] && GATE_MAP["$cmd_id"]="$result"
done < <(extract_gate_results "$INBOX")

# archive済みinboxがあれば走査
for f in queue/inbox/archive/gunshi_*.yaml; do
    [[ -f "$f" ]] || continue
    while read -r cmd_id result; do
        [[ -n "$cmd_id" ]] && GATE_MAP["$cmd_id"]="$result"
    done < <(extract_gate_results "$f")
done

# archiveでstatus: done/completed/delegatedのcmdはCLEARと推定
# cancelled/halted/superseded/absorbed/shelvedはN/A（gateなし）
# 高速化: glob展開+basename loop(3.1s/1740files)→ls+awk(0.014s, 220x)
# WSL2 NTFSではglob展開が個別stat→致命的に遅い
if [[ -d "queue/archive/cmds" ]]; then
    # CLEAR: done/completed/delegated（delegated=STK未更新だが実質完了）
    while read -r local_cmd_id; do
        [[ -n "$local_cmd_id" ]] || continue
        [[ -n "${GATE_MAP[$local_cmd_id]:-}" ]] && continue
        GATE_MAP["$local_cmd_id"]="CLEAR"
    done < <(find queue/archive/cmds/ -maxdepth 1 \( -name '*_done_*.yaml' -o -name '*_completed_*.yaml' -o -name '*_delegated_*.yaml' \) 2>/dev/null | sed 's|.*/||; s/_done_.*//; s/_completed_.*//; s/_delegated_.*//' | sort -u)
    # N/A: cancelled/halted/superseded/absorbed/shelved（gateなし）
    while read -r local_cmd_id; do
        [[ -n "$local_cmd_id" ]] || continue
        [[ -n "${GATE_MAP[$local_cmd_id]:-}" ]] && continue
        GATE_MAP["$local_cmd_id"]="N/A"
    done < <(find queue/archive/cmds/ -maxdepth 1 \( -name '*_cancelled_*.yaml' -o -name '*_halted_*.yaml' -o -name '*_superseded_*.yaml' -o -name '*_absorbed_*.yaml' -o -name '*_shelved_*.yaml' \) 2>/dev/null | sed 's|.*/||; s/_cancelled_.*//; s/_halted_.*//; s/_superseded_.*//; s/_absorbed_.*//; s/_shelved_.*//' | sort -u)
fi

echo "=== gunshi_gate_sync: ${#GATE_MAP[@]}件のgate_result情報収集済み ==="

# review_logのnull/不在エントリを更新
update_log() {
    local target_file="$1"
    [[ -f "$target_file" ]] || return 0

    # Phase 1: gate_result: null → 置換
    local null_cmds
    null_cmds=$(grep -B10 'gate_result: null' "$target_file" 2>/dev/null | grep 'cmd_id:' | awk '{print $NF}' || true)

    for cmd_id in $null_cmds; do
        local result="${GATE_MAP[$cmd_id]:-}"
        if [[ -n "$result" ]]; then
            if $DRY_RUN; then
                echo "  [dry-run] $cmd_id: null → $result"
            else
                awk -v cid="$cmd_id" -v res="$result" '
                    /cmd_id:/ && $0 ~ cid { found=1 }
                    found && /gate_result: null/ {
                        sub(/gate_result: null/, "gate_result: " res)
                        found=0
                    }
                    { print }
                ' "$target_file" > "${target_file}.tmp" && mv "${target_file}.tmp" "$target_file"
            fi
            ((updated++)) || true
        else
            ((skipped++)) || true
        fi
    done

    # Phase 2: gate_resultフィールド不在のdraft/reportエントリ → 挿入
    local missing_cmds
    missing_cmds=$(awk '
        /^- cmd_id:/ {
            if (n>0 && !has_gate && (rt=="draft"||rt=="report")) print prev_cmd
            n++; has_gate=0; rt=""; prev_cmd=$3
        }
        /^  gate_result:/ { has_gate=1 }
        /^  review_type:/ { v=$2; gsub(/["'"'"']/, "", v); if (v=="draft"||v=="report") rt=v }
        END { if (n>0 && !has_gate && (rt=="draft"||rt=="report")) print prev_cmd }
    ' "$target_file")

    for cmd_id in $missing_cmds; do
        local result="${GATE_MAP[$cmd_id]:-}"
        if [[ -n "$result" ]]; then
            if $DRY_RUN; then
                echo "  [dry-run] $cmd_id: (missing) → $result"
            else
                # review_type行の直後にgate_resultを挿入
                awk -v cid="$cmd_id" -v res="$result" '
                    /cmd_id:/ && $0 ~ cid { found=1 }
                    { print }
                    found && /review_type:/ {
                        print "  gate_result: " res
                        found=0
                    }
                ' "$target_file" > "${target_file}.tmp" && mv "${target_file}.tmp" "$target_file"
            fi
            ((updated++)) || true
        else
            ((skipped++)) || true
        fi
    done
}

# メインログとアーカイブログを順次更新
update_log "$REVIEW_LOG"
for f in "${ARCHIVE_LOGS[@]}"; do
    update_log "$f"
done

echo "=== 完了: updated=$updated, skipped=$skipped (gate_result情報なし), dry_run=$DRY_RUN ==="
