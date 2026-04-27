#!/usr/bin/env bash
# gunshi_notify.sh — notify_gunshi_for_report()を独立source可能にした関数
# 元: cmd_complete_gate.sh L300-337
# 抽出cmd: cmd_1665

# 呼び出し側で PROJECT_ROOT (= SCRIPT_DIR相当) を設定しておくこと
# 例: PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

notify_gunshi_for_report() {
    local ninja_name="$1"
    local report_path="$2"
    local cmd_id="$3"
    local project_root="${PROJECT_ROOT:-$SCRIPT_DIR}"

    # training/修行cmdはスキップ
    if [[ "$cmd_id" == cmd_training_* ]] || [[ "$cmd_id" == cmd_cycle_* ]]; then
        echo "  gunshi_notify: SKIP (training cmd: ${cmd_id})"
        return 0
    fi

    # 重複通知防止（フラグファイル）
    local gates_dir="$project_root/queue/gates/${cmd_id}"
    mkdir -p "$gates_dir"
    local flag_file="${gates_dir}/gunshi_notify_${ninja_name}.done"
    if [ -f "$flag_file" ]; then
        return 0
    fi

    # レポート内のstatus確認（LK002: status未設定でもnotify発火させる）
    # report YAMLが存在する時点で忍者は報告を書いた=完了意思。statusがcompleted/done以外でもnotify。
    # 旧コード: status!=completed&&!=done→return0 がhayate(cmd_2317 index.lock STALL後)でnotify不発の根因。
    local report_status
    report_status=$(grep -E '^\s*status:' "$report_path" | head -1 | sed 's/.*status:[[:space:]]*//' | tr -d "'" | tr -d '"')
    if [ "$report_status" = "failed" ] || [ "$report_status" = "cancelled" ]; then
        return 0
    fi

    # 軍師にinbox通知
    if bash "$project_root/scripts/inbox_write.sh" gunshi \
        "${ninja_name}報告完了。レビュー依頼: ${cmd_id} report=$(basename "$report_path")" \
        report_review karo 2>/dev/null; then
        echo "  gunshi_notify: SENT (${ninja_name} → gunshi)"
        echo "timestamp: $(date +%Y-%m-%dT%H:%M:%S)" > "$flag_file"
        echo "ninja: ${ninja_name}" >> "$flag_file"
        echo "report: $(basename "$report_path")" >> "$flag_file"
    else
        echo "  gunshi_notify: WARN (inbox_write failed for ${ninja_name})"
    fi
}
