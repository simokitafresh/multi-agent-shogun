---
name: switch-to-opus
argument-hint: "[--scope all|core|agent_list]"
description: |
  【将軍専用】家老・忍者は使用禁止。将軍以外が呼んだ場合は即座に中断せよ。
  指定エージェント(shogun/karo/gunshi)をCodex CLIからOpus CLI(Claude Code)に戻すスキル。
  settings.yaml更新→CLI respawn→動作確認の3ステップ。
  idle安全機構付き（in_progress時はスキップ）。shutsujin再起動でもデフォルトOpus復帰。
  TRIGGER: /switch-to-opus、Opusに戻す、家老をOpusに、軍師をOpusに、将軍をOpusに
  DO NOT TRIGGER: 忍者のモデル切替（→/hensei）、Codex切替（→/switch-to-codex）、
  settings.yaml直接編集
allowed-tools:
  - Bash
  - Read
  - Edit
---

# /switch-to-opus -- エージェント個別Opus復帰

## 概要

Codex CLIで稼働中のエージェントをOpus CLI(Claude Code v2.1.87)に戻す。
/switch-to-codex のロールバック。デフォルト状態への復帰。

## 使い方

```
/switch-to-opus karo     # 家老をOpusに復帰
/switch-to-opus gunshi   # 軍師をOpusに復帰
```

## 実行手順

### Step 1: プリフライトチェック

```bash
AGENT="{agent_name}"
PANE_ID=$(tmux list-panes -t "shogun:agents" -F '#{pane_id} #{@agent_id}' | grep " ${AGENT}$" | awk '{print $1}')
AGENT_STATE=$(tmux show-options -p -t "$PANE_ID" -v @agent_state 2>/dev/null || echo "unknown")

if [ "$AGENT_STATE" = "active" ]; then
    echo "ABORT: $AGENT is active. Wait until idle."
    exit 1
fi
```

### Step 2: settings.yaml更新 + tmux変数同期

```bash
# settings.yaml更新
bash scripts/lib/yaml_field_set.sh config/settings.yaml "${AGENT}" type claude
bash scripts/lib/yaml_field_set.sh config/settings.yaml "${AGENT}" model_name claude-opus-4-6

# tmux変数を即時同期（inbox_watcherキャッシュ対策）
tmux set-option -p -t "$PANE_ID" @agent_cli claude
```

### Step 3: CLI respawn（旧CLI終了→新CLI起動）

CLIタイプが変わるためrespawnが必須。

```bash
# 1. idle確認
tmux capture-pane -t "$PANE_ID" -p | tail -3

# 2. 旧CLI終了（C-c 2回）
tmux send-keys -t "$PANE_ID" C-c
sleep 1
tmux send-keys -t "$PANE_ID" C-c
sleep 1

# 3. 新CLI起動（build_cli_commandがsettings.yamlのtype=claudeを読んでOpusコマンドを生成）
cd /mnt/c/tools/multi-agent-shogun
source lib/cli_adapter.sh
CLI_CMD=$(build_cli_command "${AGENT}")
echo "CLI_CMD: $CLI_CMD"
tmux send-keys -t "$PANE_ID" "cd /mnt/c/tools/multi-agent-shogun && clear" Enter
sleep 1
tmux send-keys -t "$PANE_ID" "$CLI_CMD" Enter
```

### Step 4: 動作確認

```bash
sleep 30
tmux capture-pane -t "$PANE_ID" -p | tail -10
tmux show-options -p -t "$PANE_ID" -v @agent_id
tmux show-options -p -t "$PANE_ID" -v @model_name
```

### Step 5: 完了報告

```bash
bash scripts/ntfy.sh "【将軍】${AGENT} Opus復帰完了"
```
