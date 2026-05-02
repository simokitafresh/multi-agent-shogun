---
name: reset-layout
argument-hint: "[--dry-run]"
quality_metric: "家老系: reset-layout実行後のstartup/layout関連gate通過率(対象実行のうちpane構成・watcher確認gateがPASSした割合)"
description: |
  agentsウィンドウ(shogun:agents)のレイアウト・ペイン配置・変数を
  初期状態に一発復元するスキル。ペイン消失・入替・CLI死亡時に使用。
  TRIGGER: /reset-layout、ペイン復元、レイアウトリセット、ペイン消失、CLI死亡復旧
  DO NOT TRIGGER: 個別ペインの操作（手動split/swap）、ninja_monitorの自動復旧、
  設定変更（→config/settings.yaml手動編集）
allowed-tools:
  - Bash
  - Read
---

# /reset-layout — agentsウィンドウ一発復元

## 概要

shogun:agents ウィンドウの全8ペイン（karo + gunshi + ninja x6）を正規状態に復元する。

## 処理内容

1. ペイン数の自動復元（不足時にsplit-window+agent_id割当）
2. ペイン配置の修正（swap検出+修正）
3. 死亡ペインの復活（respawn + CLI再起動）
4. CLI未起動ペインの検出+CLI起動（全ペインでCLIが動くまで完了しない）
5. 全ペイン変数の正規化（@agent_id, @model_name, @agent_tier, @agent_cli, bg, title）
6. 正規レイアウト文字列の適用
7. inbox_watcher全再起動

## 使い方

### 事前診断（変更なし）

```bash
bash scripts/reset_layout.sh --dry-run
```

- どのペインがswap対象か
- どのペインが死亡しているか
- どの変数が不正か

を確認できる。

### 実行

```bash
bash scripts/reset_layout.sh
```

### 実行後の確認

```bash
tmux list-panes -t shogun:agents -F '#{pane_index} #{@agent_id} #{pane_dead} #{@agent_tier} #{@agent_cli} #{@model_name}'
```

## 手順（将軍CLI実行時）

1. `bash scripts/reset_layout.sh` を実行
2. 出力結果を確認（swap件数、respawn件数、変数修正件数）
3. `bash scripts/ntfy.sh "reset_layout完了。swap:N件、respawn:N件"` で殿に報告

`--dry-run` で事前確認してから実行することを推奨。

## 前提条件

- shogun:agents ウィンドウが存在すること
- ペイン数が8未満の場合は自動追加（8超過はERROR終了）
- CLIが起動するまでが本スキルの責務
