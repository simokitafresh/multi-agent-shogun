#!/bin/bash
# shutsujin_departure.sh — セッション起動時の初期設定スクリプト
# Usage: bash scripts/shutsujin_departure.sh
#
# tmuxセッション作成後、エージェント起動前に実行する。
# セッション固有の設定を適用する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ─── remain-on-exit (cmd_183) ───
# CLIプロセスが死んでもペインを残す（OOM Kill等の原因調査用）
# agents window(shogun:2)のみ。将軍window(shogun:1)は不要。
tmux set-option -w -t shogun:2 remain-on-exit on 2>/dev/null

echo "[shutsujin] remain-on-exit: on (shogun:2)"
