#!/bin/bash
# cmd_halt.sh — 将軍が誤cmdに気づいた瞬間に叩く緊急停止スクリプト
# Usage: bash scripts/cmd_halt.sh cmd_XXX
# 内部処理: inbox_write.sh で家老にhalt通知を送信するだけ

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD_ID="$1"

# 引数チェック（cmd_IDが必須）
if [ -z "$CMD_ID" ]; then
    echo "Usage: bash scripts/cmd_halt.sh cmd_XXX" >&2
    echo "ERROR: cmd_ID is required." >&2
    exit 1
fi

# cmd_プレフィックスチェック
if [[ ! "$CMD_ID" =~ ^cmd_ ]]; then
    echo "ERROR: cmd_ID must start with 'cmd_' (got: $CMD_ID)" >&2
    exit 1
fi

# 家老にhalt通知を送信
bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$CMD_ID HALT" halt shogun

echo "[cmd_halt] $CMD_ID HALT sent to karo inbox."
