---
name: hensei-opus
description: |
  【将軍専用】家老・忍者は使用禁止。将軍以外が呼んだ場合は即座に中断せよ。
  全忍者をOpus統一に戻す（決戦モード）。idle安全機構付き。
  TRIGGER: /hensei-opus、Opus全戻し、決戦モード
  DO NOT TRIGGER: 混成編成（→/hensei-mixed）、個別忍者の手動切替
allowed-tools:
  - Bash
  - Read
  - Edit
---

# /hensei-opus -- 全忍者Opus統一（決戦モード）

全忍者をtype=claude, model_name=claude-opus-4-6に切替える。
家老・軍師・将軍は切替対象外（常にOpus）。

## 実行手順

### Step 1: ヘルパースクリプト実行

```bash
bash ~/.claude/skills/hensei/scripts/hensei_apply.sh opus-all
```

自動実行内容:
1. プリフライトチェック
2. 全忍者のsettings.yaml更新（type=claude, model_name=claude-opus-4-6）
3. idle Claude忍者はrespawn（/exit→build_cli_command()で再起動。1M+effort high確保）
4. type変更が必要な忍者（Codex→Claude）はリスト出力（手動CLI再起動必要）
5. in_progress忍者はスキップ（settings.yaml更新のみ）

### Step 2: CLI再起動（Codex→Claude切替が必要な場合のみ）

ヘルパーが「CLI再起動必要」と報告した忍者に対して:

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
bash scripts/ntfy.sh "【将軍】編成切替完了: opus-all（決戦モード）"
```

## 安全機構

**in_progress忍者のCLI操作は絶対禁止。** ヘルパースクリプトが自動判定。
手動CLI再起動時もtmux capture-paneでidle確認必須。
スキップされた忍者は次回/clear時にninja_monitorが新設定で起動する。
