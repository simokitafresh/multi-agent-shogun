#!/usr/bin/env bash
# gate_enforcement_audit.sh — 強制度監査 gate (meta-level)
#
# 目的: 「自動化×強制」を謳っているが実は意志依存の script を自動検出する。
# Phase 4-5 原理(deepdive_why_chain_20260321.md)の監査装置。
#
# 動機: cmd_?? (2026-04-12)
#   軍師の /clear 復帰時に gate_gunshi_startup.sh が自動実行されなかった。
#   根因なぜなぜ7回で到達=「gate の gate 不在」メタレベル欠落。
#   CLAUDE.md に bash scripts/gates/foo.sh と書いてあるだけでは意志依存。
#   hooks に登録されて初めて強制。両者を突合する gate を環境に埋め込む。
#
# Usage: bash scripts/gates/gate_enforcement_audit.sh [--verbose]
# Exit:
#   0 — 監査完了(意志依存 script が 0 件、または全件が明示的許容)
#   1 — 意志依存 script を検出(要対処)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

CLAUDE_MD="$SCRIPT_DIR/CLAUDE.md"
USER_SETTINGS="$HOME/.claude/settings.json"
PROJECT_SETTINGS="$SCRIPT_DIR/.claude/settings.json"
PROJECT_LOCAL_SETTINGS="$SCRIPT_DIR/.claude/settings.local.json"

# 許容リスト(手動実行が意図された script は除外)
# 書式: 1行1 basename。'#' でコメント
ALLOWLIST_FILE="$SCRIPT_DIR/config/enforcement_audit_allowlist.txt"

echo "=== 強制度監査 gate $(date -Iseconds) ==="

# ---- Step 1: CLAUDE.md で参照されている bash scripts/* を列挙 ----
if [[ ! -f "$CLAUDE_MD" ]]; then
  echo "ERROR: $CLAUDE_MD not found"
  exit 2
fi

# 拾うパターン: `bash scripts/...` または `bash scripts/gates/...` (行内を1つ)
mapfile -t CLAUDE_REFS < <(
  grep -oE 'bash[[:space:]]+scripts/[A-Za-z0-9_./-]+\.sh' "$CLAUDE_MD" \
    | awk '{print $2}' \
    | sort -u
)

echo "■ CLAUDE.md 参照 script: ${#CLAUDE_REFS[@]} 本"

# ---- Step 2: hooks 登録されている script を 3 つの settings から抽出 ----
collect_hook_scripts() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  # jq でhooks[*].hooks[*].command を全部取り出す
  python3 - "$f" <<'PY' 2>/dev/null || true
import json, re, sys
try:
    with open(sys.argv[1]) as fp:
        data = json.load(fp)
except Exception:
    sys.exit(0)
hooks = data.get("hooks", {})
for event, entries in hooks.items():
    if not isinstance(entries, list):
        continue
    for entry in entries:
        for h in entry.get("hooks", []) or []:
            cmd = h.get("command", "")
            for m in re.findall(r'scripts/[A-Za-z0-9_./-]+\.sh', cmd):
                print(m)
PY
}

HOOK_SCRIPTS="$(
  {
    collect_hook_scripts "$USER_SETTINGS"
    collect_hook_scripts "$PROJECT_SETTINGS"
    collect_hook_scripts "$PROJECT_LOCAL_SETTINGS"
  } | sort -u
)"

hook_count=0
[[ -n "$HOOK_SCRIPTS" ]] && hook_count=$(echo "$HOOK_SCRIPTS" | wc -l | tr -d ' ')
echo "■ settings(*.json) 登録 hook script: $hook_count 本"

# ---- Step 3: 許容リストを読み込み ----
ALLOW_SCRIPTS=""
if [[ -f "$ALLOWLIST_FILE" ]]; then
  ALLOW_SCRIPTS="$(grep -vE '^[[:space:]]*(#|$)' "$ALLOWLIST_FILE" | sort -u)"
fi

# ---- Step 4: CLAUDE.md で参照されているが hooks に未登録の script を抽出 ----
# = 意志依存 script
will_dep_list=""
for ref in "${CLAUDE_REFS[@]}"; do
  base="$(basename "$ref")"
  # allowlist に入っていればスキップ
  if [[ -n "$ALLOW_SCRIPTS" ]] && echo "$ALLOW_SCRIPTS" | grep -qxF "$base"; then
    continue
  fi
  # hook に登録されていればスキップ
  if echo "$HOOK_SCRIPTS" | grep -qE "(^|/)${base}$"; then
    continue
  fi
  will_dep_list="${will_dep_list}${ref}"$'\n'
done

will_dep_count=0
[[ -n "$will_dep_list" ]] && will_dep_count=$(echo -n "$will_dep_list" | grep -c . || true)

# ---- Step 5: 結果表示 ----
if (( will_dep_count == 0 )); then
  echo ""
  echo "=== 総合判定: OK (意志依存 script 0 本) ==="
  exit 0
fi

echo ""
echo "■ ⚠️ 意志依存 script 検出: ${will_dep_count} 本"
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "  - $line"
done <<< "$will_dep_list"
echo ""
echo "これらは CLAUDE.md で参照されているが、どの settings.json の hooks にも未登録です。"
echo "読み手の意志に依存しており、Phase 4 原理「LLM に生存本能はない」により実行スキップ可能。"
echo ""
echo "対処:"
echo "  (A) hook 登録: settings.json の SessionStart / PreToolUse / PostToolUse 等に登録"
echo "  (B) 他スクリプトから自動呼出: session_start_inject.sh のような既存 hook スクリプト内で bash 呼出"
echo "  (C) 手動実行が正当: $ALLOWLIST_FILE に basename を追記して許容"
echo ""
echo "=== 総合判定: ALERT (要対処) ==="
exit 1
