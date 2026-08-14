#!/usr/bin/env bash
# semantic-links: [[停滞判定一次確認]], [[殿裁定_偽陽性即時根治_20260814]]
# 停滞判定の標準一次確認プローブ(read-only)。
# 真因: 浅いtail captureでの手作業診断が「作業痕跡なし」誤診を生む
# (2026-08-14 将軍が小太郎を停滞と誤報→家老の-S深掘りで実作業中と判明)。
# 診断の深さを個人の手癖に依存させず、1コマンドで機械收集する。
# 使い方: bash scripts/stall_probe.sh <agent_name>
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
name="${1:?usage: stall_probe.sh <agent_name>}"

pane=$(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{@agent_id}' 2>/dev/null \
    | awk -v n="$name" '$2==n{print $1; exit}')
if [ -z "$pane" ]; then
    echo "ERROR: pane not found for agent=$name"
    exit 1
fi

task_file="queue/tasks/${name}.yaml"
echo "=== task YAML (${task_file}) ==="
if [ -f "$task_file" ]; then
    grep -E '^[[:space:]]*(task_id|status|acknowledged_at|assigned_at|updated_at|parent_cmd):' "$task_file" | head -10
else
    echo "(task file なし)"
fi

cap=$(tmux capture-pane -t "$pane" -p -S -50 2>/dev/null || true)

echo "=== pane深掘りcapture(-S -50)の作業痕跡 ==="
evidence=$(printf '%s\n' "$cap" \
    | grep -E 'Working|Explored|Brewed|esc to interrupt|tokens|⏺|●|Read\(|Edit\(|Bash\(|Write\(' \
    | tail -15 || true)
if [ -n "$evidence" ]; then
    printf '%s\n' "$evidence"
else
    echo "(作業痕跡なし)"
fi

echo "=== pane末尾10行(現在画面) ==="
printf '%s\n' "$cap" | tail -10

echo "=== 判定ガイド ==="
echo "作業痕跡あり + status古い → status更新漏れ(停滞ではない。誤報するな)"
echo "作業痕跡なし + prompt入力待ち → 真の停滞疑い(1回の観測で断定せず、時間を置いて再probe)"
