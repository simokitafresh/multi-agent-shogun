#!/usr/bin/env bash
# firefighting_keywords.sh — 消火キーワードパターン共通定義
# 消費者: cmd_save.sh, deploy_task.sh
# source して FIREFIGHTING_PATTERN を使う
#   grep -qiE "$FIREFIGHTING_PATTERN"

# shellcheck disable=SC2034  # sourceされた側のスクリプトで使用
FIREFIGHTING_PATTERN='fix|修正|修復|revert|壊れた|障害|FAIL|CI赤|復旧|hotfix|バグ|不具合|(^|[[:blank:]_]|[^[:alnum:]_])bug([^[:alnum:]_]|$)|(^|[[:blank:]_]|[^[:alnum:]_])broken([^[:alnum:]_]|$)'
