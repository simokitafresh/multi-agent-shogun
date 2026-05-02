---
name: hensei-mixed
argument-hint: ""
description: |
  【将軍専用】家老・忍者は使用禁止。将軍以外が呼んだ場合は即座に中断せよ。
  GPT2+Sonnet2+Opus2の混成編成に切替する。idle安全機構付き。
  TRIGGER: /hensei-mixed、混成編成、モデル混成
  DO NOT TRIGGER: Opus全戻し（→/hensei-opus）、個別忍者の手動切替
quality_metric: "当該スキル起点cmdのcmd_save.shチェック通過率（q1-q3 BLOCKなし、q4_depth WARNINGなしの割合）"
allowed-tools:
  - Bash
  - Read
  - Edit
---

# /hensei-mixed -- GPT2+Sonnet2+Opus2混成編成

忍者6名を以下の混成に切替える。round-robinで均等配備。
家老・軍師・将軍は切替対象外（常にOpus）。

## 混成テーブル

| 忍者 | type | model_name | 区分 | RR順 |
|------|------|-----------|------|------|
| hayate | codex | gpt-5.4 | GPT | 1 |
| kagemaru | claude | claude-sonnet-4-6 | Sonnet | 2 |
| hanzo | claude | claude-opus-4-6 | Opus | 3 |
| saizo | codex | gpt-5.4 | GPT | 4 |
| kotaro | claude | claude-sonnet-4-6 | Sonnet | 5 |
| tobisaru | claude | claude-opus-4-6 | Opus | 6 |

### Codex 1Mコンテキスト設定

Codexはデフォルト272K。1Mにするには`~/.codex/config.toml`に以下を追加:

```toml
model_context_window = 1000000
model_auto_compact_token_limit = 900000
```

## 実行手順

### Step 1: ヘルパースクリプト実行

```bash
bash ~/.claude/skills/hensei/scripts/hensei_apply.sh mixed
```

自動実行内容:
1. プリフライトチェック
2. 全忍者のsettings.yaml更新（type + model_name）
3. idle Claude→Claude忍者はrespawn（1M+effort high確保）
4. type変更が必要な忍者（Claude↔Codex）はリスト出力（手動CLI再起動必要）
5. in_progress忍者はスキップ（settings.yaml更新のみ）

### Step 2: CLI再起動（type変更が必要な場合）

#### Claude → Codex（hayate, saizo）

```bash
PANE_ID=$(tmux list-panes -t "shogun:agents" -F '#{pane_id} #{@agent_id}' | grep " {ninja}$" | awk '{print $1}')
tmux capture-pane -t "$PANE_ID" -p | tail -3  # idle確認
CLI_CMD=$(source lib/cli_adapter.sh && build_cli_command "{ninja}")
tmux send-keys -t "$PANE_ID" "/exit" Enter
sleep 2
tmux send-keys -t "$PANE_ID" "$CLI_CMD" Enter
```

#### Codex → Claude（opus-all戻し時のみ）

```bash
PANE_ID=$(tmux list-panes -t "shogun:agents" -F '#{pane_id} #{@agent_id}' | grep " {ninja}$" | awk '{print $1}')
tmux capture-pane -t "$PANE_ID" -p | tail -3  # idle確認
CLI_CMD=$(source lib/cli_adapter.sh && build_cli_command "{ninja}")
tmux send-keys -t "$PANE_ID" C-c
sleep 2
tmux send-keys -t "$PANE_ID" "$CLI_CMD" Enter
```

### Step 3: 検証

```bash
tmux list-panes -t "shogun:agents" -F '#{@agent_id} #{@model_name}'
```

### Step 4: 完了報告

```bash
bash scripts/ntfy.sh "【将軍】編成切替完了: mixed（GPT2+Sonnet2+Opus2）"
```

## 安全機構

**in_progress忍者のCLI操作は絶対禁止。** ヘルパースクリプトが自動判定。
手動CLI再起動時もtmux capture-paneでidle確認必須。
スキップされた忍者は次回/clear時にninja_monitorが新設定で起動する。
