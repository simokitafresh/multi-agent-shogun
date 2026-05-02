---
name: hensei
argument-hint: ""
description: |
  【将軍専用】家老・忍者は使用禁止。将軍以外が呼んだ場合は即座に中断せよ。
  忍者のモデル編成をプリセットで一括切替するスキル。
  opus-all: 全忍者をOpus統一（決戦モード）。mixed: GPT+Sonnet+Opus混成。
  idle安全機構付き（in_progress忍者のCLI操作をスキップ）。
  TRIGGER: /hensei、編成切替、モデル混成、Opus全戻し、決戦モード
  DO NOT TRIGGER: 個別忍者のモデル手動切替（inbox_write model_switch直接送信）、
  settings.yaml直接編集、ninja_monitor操作
quality_metric: "当該スキル起点cmdのcmd_save.shチェック通過率（q1-q3 BLOCKなし、q4_depth WARNINGなしの割合）"
allowed-tools:
  - Bash
  - Read
  - Edit
---

# /hensei -- 忍者モデル編成一括切替

## 概要

忍者6名のモデル編成をプリセットで一括切替する。将軍専用。
家老・軍師・将軍は切替対象外（常にOpus）。

## 使い方

```
/hensei opus-all    # 全忍者をOpus統一（決戦モード）
/hensei mixed       # GPT2+Sonnet2+Opus2混成
```

## プリセット定義

### opus-all（決戦モード）

全忍者: type=claude, model_name=claude-opus-4-6

### mixed（混成編成）

| 忍者 | type | model_name | 区分 |
|------|------|-----------|------|
| hayate | codex | gpt-5.4 | GPT |
| saizo | codex | gpt-5.4 | GPT |
| kagemaru | claude | claude-sonnet-4-6 | Sonnet |
| kotaro | claude | claude-sonnet-4-6 | Sonnet |
| hanzo | claude | claude-opus-4-6 | Opus |
| tobisaru | claude | claude-opus-4-6 | Opus |

### Codex 1Mコンテキスト設定

Codexはデフォルト272Kコンテキスト。1Mにするには`~/.codex/config.toml`に以下を設定:

```toml
model_context_window = 1000000
model_auto_compact_token_limit = 900000
```

## 実行手順

### Step 1: ヘルパースクリプト実行

```bash
bash ~/.claude/skills/hensei/scripts/hensei_apply.sh <preset>
```

このスクリプトが以下を自動実行:
1. プリフライトチェック（model_switch_preflight.sh）
2. 全忍者のsettings.yaml更新（type + model_name）
3. idle Claude忍者のモデル変更はrespawn（/exit→build_cli_command()で再起動。1M+effort high確保）
4. type変更が必要な忍者はリスト出力（手動CLI再起動が必要）
5. in_progress忍者はスキップ（settings.yaml更新のみ、CLI操作なし）

### Step 2: CLI再起動（ヘルパーが報告した場合のみ）

ヘルパーが「CLI再起動必要」と報告した忍者に対して、以下の手順を実行する。

#### A: Claude --> Codex への切替

```bash
# 1. ペインIDを取得
PANE_ID=$(tmux list-panes -t "shogun:agents" -F '#{pane_id} #{@agent_id}' | grep " {ninja}$" | awk '{print $1}')

# 2. idle確認（プロンプトが表示されていること）
tmux capture-pane -t "$PANE_ID" -p | tail -3

# 3. Claude終了 --> Codex起動（build_cli_command()で正しい起動コマンドを取得）
CLI_CMD=$(source lib/cli_adapter.sh && build_cli_command "{ninja}")
tmux send-keys -t "$PANE_ID" "/exit" Enter
sleep 2
tmux send-keys -t "$PANE_ID" "$CLI_CMD" Enter
```

#### B: Codex --> Claude への切替

```bash
# 1. ペインIDを取得
PANE_ID=$(tmux list-panes -t "shogun:agents" -F '#{pane_id} #{@agent_id}' | grep " {ninja}$" | awk '{print $1}')

# 2. idle確認（プロンプトが表示されていること）
tmux capture-pane -t "$PANE_ID" -p | tail -3

# 3. Codex終了 --> Claude起動（build_cli_command()で1M+effort high確保）
CLI_CMD=$(source lib/cli_adapter.sh && build_cli_command "{ninja}")
tmux send-keys -t "$PANE_ID" C-c
sleep 2
tmux send-keys -t "$PANE_ID" "$CLI_CMD" Enter
```

### Step 3: 検証

```bash
# 全忍者のpane border表示を確認
tmux list-panes -t "shogun:agents" -F '#{@agent_id} #{@model_name}'
```

### Step 4: 完了報告

```bash
bash scripts/ntfy.sh "【将軍】編成切替完了: <preset>"
```

## 安全機構

**in_progress忍者のCLI操作は絶対禁止。**

ヘルパースクリプトが自動判定する:

1. 各忍者のtask YAML statusを確認
2. status = in_progress | acknowledged --> **CLI操作スキップ**
   - settings.yaml更新のみ実行（次回/clear後に新モデルで起動）
   - スキップした忍者を一覧表示
3. status = idle | done | completed --> CLI操作実行可

手動CLI再起動(Step 2)でも同じ確認を行うこと:
- tmux capture-paneでidle状態を目視確認してから操作
- idle以外の状態では絶対にCLI操作しない

## 注意事項

- 家老(karo)・軍師(gunshi)・将軍(shogun)は切替対象外
- Codex CLIは/modelコマンド非対応。type変更時はCLI再起動必須
- settings.yaml更新は全忍者に対して即時実行（設定変更のみなので安全）
- CLI操作のみがin_progress制約の対象
- スキップされた忍者は次回/clear時にninja_monitorが新設定で起動する
