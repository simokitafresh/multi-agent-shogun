---
name: switch-to-codex
argument-hint: "[--scope all|core|agent_list]"
quality_metric: "将軍系: Codex切替cmdのcmd_save.shチェック通過率(q1-q4 BLOCKなしで保存できた割合)"
description: |
  【将軍専用】家老・忍者は使用禁止。将軍以外が呼んだ場合は即座に中断せよ。
  指定エージェント(shogun/karo/gunshi)をOpus CLIからCodex CLIに切替するスキル。
  settings.yaml更新→CLI respawn→動作確認の3ステップ。
  idle安全機構付き（in_progress時はスキップ）。shutsujin再起動でデフォルトOpus復帰。
  TRIGGER: /switch-to-codex、Codexに切替、家老をCodexに、軍師をCodexに、将軍をCodexに
  DO NOT TRIGGER: 忍者のモデル切替（→/hensei）、Opus全戻し（→/switch-to-opus）、
  settings.yaml直接編集
allowed-tools:
  - Bash
  - Read
  - Edit
---

# /switch-to-codex -- エージェント個別Codex切替

## 概要

将軍・家老・軍師のうち指定エージェントをOpus CLI(Claude Code)からCodex CLI(GPT)に切替する。
Opus消費削減が目的。品質は同等を維持（codex-{role}.md + hook代替gate + 同一Recovery手順）。

## 使い方

```
/switch-to-codex shogun   # 将軍をCodexに切替
/switch-to-codex karo     # 家老をCodexに切替
/switch-to-codex gunshi   # 軍師をCodexに切替
```

注意: 将軍切替時は殿が将軍ペインにいるため、殿自身が別ペインからrespawnを実行する必要がある。

## 前提条件

- `~/.codex/config.toml` に `model_context_window = 1000000` が設定済み
- `instructions/generated/codex-{role}.md` が存在する
- プロジェクト `AGENTS.md` に対象ロールのRecovery手順がある

## 実行手順

### Step 1: プリフライトチェック

```bash
# 対象エージェントのペインとstateを確認
AGENT="{agent_name}"  # karo or gunshi
PANE_ID=$(tmux list-panes -t "shogun:agents" -F '#{pane_id} #{@agent_id}' | grep " ${AGENT}$" | awk '{print $1}')
AGENT_STATE=$(tmux show-options -p -t "$PANE_ID" -v @agent_state 2>/dev/null || echo "unknown")

# in_progressなら中止
if [ "$AGENT_STATE" = "active" ]; then
    echo "ABORT: $AGENT is active (in_progress). Wait until idle."
    exit 1
fi

# Codex config確認
grep -q 'model_context_window = 1000000' ~/.codex/config.toml || echo "WARN: Codex 1M context not configured"

# codex-{role}.md存在確認
ls instructions/generated/codex-${AGENT}.md || echo "ABORT: codex-${AGENT}.md not found"
```

### Step 2: settings.yaml更新 + tmux変数同期

```bash
# settings.yaml更新（karo/gunshiエントリは事前追加済み）
bash scripts/lib/yaml_field_set.sh config/settings.yaml "${AGENT}" type codex

# tmux変数を即時同期（inbox_watcherがキャッシュを使うため、@agent_cliで直接通知）
tmux set-option -p -t "$PANE_ID" @agent_cli codex
```

重要: `@agent_cli` tmux変数の更新が必須。inbox_watcherはsettings.yamlのキャッシュを保持しており、
tmux変数が唯一のリアルタイム通知経路（穴4対策）。

### Step 3: CLI respawn（旧CLI終了→新CLI起動）

CLIタイプが変わるためrespawnが必須（設定変更だけでは切り替わらない）。
ninja_monitorと同じ方式: C-c→shell復帰→build_cli_command()で新CLI起動。

```bash
# 1. idle確認
tmux capture-pane -t "$PANE_ID" -p | tail -3

# 2. 旧CLI終了（C-c 2回でCLIプロセスを確実に停止）
tmux send-keys -t "$PANE_ID" C-c
sleep 1
tmux send-keys -t "$PANE_ID" C-c
sleep 1

# 3. 新CLI起動（build_cli_commandがsettings.yamlのtype=codexを読んでcodexコマンドを生成）
cd /mnt/c/tools/multi-agent-shogun
source lib/cli_adapter.sh
CLI_CMD=$(build_cli_command "${AGENT}")
echo "CLI_CMD: $CLI_CMD"  # 確認表示
tmux send-keys -t "$PANE_ID" "cd /mnt/c/tools/multi-agent-shogun && clear" Enter
sleep 1
tmux send-keys -t "$PANE_ID" "$CLI_CMD" Enter
```

注意: respawn後はCLIの起動に数秒〜十数秒かかる。Step 4で動作確認。

### Step 4: 動作確認

```bash
# 30秒待ってからペイン確認
sleep 30
tmux capture-pane -t "$PANE_ID" -p | tail -10

# agent_id確認（Recovery手順が正しく実行されたか）
tmux show-options -p -t "$PANE_ID" -v @agent_id
tmux show-options -p -t "$PANE_ID" -v @model_name
```

### Step 5: 完了報告

```bash
bash scripts/ntfy.sh "【将軍】${AGENT} Codex切替完了"
```

## 既知の注意事項（実戦検証済み 2026-04-22）

1. **旧CLI終了**: Claude CLIは`/exit`+Enterで終了。Codex CLIはC-c×3で終了。`/exit`が効かない場合はC-cを繰り返す
2. **Codex nudge応答遅延**: inbox_watcherのnudge(paste-buffer+Enter)がCodex CLIで即応答しない場合がある。手動Enterで解消。根因調査中
3. **revert時は必ず`/switch-to-opus`スキル経由**: 手動でsettings.yamlだけ戻すと@agent_cli tmux変数が不整合になる

## ロールバック

問題が発生した場合は `/switch-to-opus {agent}` で即座にOpusに戻せる。
手動revert禁止（@agent_cli tmux変数の同期漏れが発生する）。
