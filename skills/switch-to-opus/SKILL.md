---
name: switch-to-opus
argument-hint: "[--scope all|core|agent_list]"
quality_metric: "将軍系: Opus復帰cmdのcmd_save.shチェック通過率(q1-q4 BLOCKなしで保存できた割合)"
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

<!-- script_refs_checked_at: 2026-06-09T09:20:00+09:00 -->

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

Script refs verified: 2026-05-22 cmd_2959. `yaml_field_set.sh` はflock、root fallback、map/list block対応、複数行・inline scalar継続の安全置換、post-write readback検証を行う。settings.yaml更新はhelperの検証完了後にtmux変数同期へ進む。
Script refs verified: 2026-06-09 cmd_karo_skill_update_batch1. `yaml_field_set.sh` 直近変更(3de0d29c)は_yaml_field_set_apply_rootのskip_children条件修正(内部バグフィックス、I/F変更なし)。本スキルはroot操作を使わないため直接影響なし。呼び出し契約とreadback検証は維持。
Script refs verified: 2026-06-07 cmd_3206. `yaml_field_set.sh` はlock path純bash化で高速化されたが、`config/settings.yaml` の `type` と `model_name` を個別更新する呼び出し契約は維持。Step 2のsettings.yaml更新+tmux変数同期手順は現行と一致。

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
