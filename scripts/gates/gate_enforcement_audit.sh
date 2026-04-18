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
AUDIT_ROOT="${ENFORCEMENT_AUDIT_ROOT:-$SCRIPT_DIR}"

CLAUDE_MD="${ENFORCEMENT_AUDIT_CLAUDE_MD:-$AUDIT_ROOT/CLAUDE.md}"
USER_SETTINGS="${ENFORCEMENT_AUDIT_USER_SETTINGS:-$HOME/.claude/settings.json}"
PROJECT_SETTINGS="${ENFORCEMENT_AUDIT_PROJECT_SETTINGS:-$AUDIT_ROOT/.claude/settings.json}"
PROJECT_LOCAL_SETTINGS="${ENFORCEMENT_AUDIT_PROJECT_LOCAL_SETTINGS:-$AUDIT_ROOT/.claude/settings.local.json}"

# 許容リスト(手動実行が意図された script は除外)
# 書式: 1行1 basename。'#' でコメント
ALLOWLIST_FILE="${ENFORCEMENT_AUDIT_ALLOWLIST:-$AUDIT_ROOT/config/enforcement_audit_allowlist.txt}"

echo "=== 強制度監査 gate $(date -Iseconds) ==="

if [[ ! -f "$CLAUDE_MD" ]]; then
  echo "ERROR: $CLAUDE_MD not found"
  exit 2
fi

python3 - "$CLAUDE_MD" "$ALLOWLIST_FILE" "$USER_SETTINGS" "$PROJECT_SETTINGS" "$PROJECT_LOCAL_SETTINGS" <<'PY'
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

claude_md = Path(sys.argv[1])
allowlist_file = Path(sys.argv[2])
settings_paths = [Path(path) for path in sys.argv[3:]]

claude_text = claude_md.read_text(encoding="utf-8")
claude_refs = sorted({
    match.group(1)
    for match in re.finditer(
        r"bash[ \t]+(scripts/[A-Za-z0-9_./-]+\.sh)",
        claude_text,
    )
})

hook_scripts: set[str] = set()
for path in settings_paths:
    if not path.is_file():
        continue
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        continue
    hooks = data.get("hooks", {})
    if not isinstance(hooks, dict):
        continue
    for entries in hooks.values():
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            for hook in entry.get("hooks", []) or []:
                if not isinstance(hook, dict):
                    continue
                command = str(hook.get("command", ""))
                for match in re.finditer(r"(scripts/[A-Za-z0-9_./-]+\.sh)", command):
                    hook_scripts.add(match.group(1))

allow_basenames: set[str] = set()
if allowlist_file.is_file():
    for raw_line in allowlist_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        allow_basenames.add(line)

hook_basenames = {Path(path).name for path in hook_scripts}
missing = [
    ref for ref in claude_refs
    if Path(ref).name not in allow_basenames and Path(ref).name not in hook_basenames
]

print(f"■ CLAUDE.md 参照 script: {len(claude_refs)} 本")
print(f"■ settings(*.json) 登録 hook script: {len(hook_scripts)} 本")

if not missing:
    print("")
    print("=== 総合判定: OK (意志依存 script 0 本) ===")
    sys.exit(0)

print("")
print(f"■ ⚠️ 意志依存 script 検出: {len(missing)} 本")
for ref in missing:
    print(f"  - {ref}")
print("")
print("これらは CLAUDE.md で参照されているが、どの settings.json の hooks にも未登録です。")
print("読み手の意志に依存しており、Phase 4 原理「LLM に生存本能はない」により実行スキップ可能。")
print("")
print("対処:")
print("  (A) hook 登録: settings.json の SessionStart / PreToolUse / PostToolUse 等に登録")
print("  (B) 他スクリプトから自動呼出: session_start_inject.sh のような既存 hook スクリプト内で bash 呼出")
print(f"  (C) 手動実行が正当: {allowlist_file} に basename を追記して許容")
print("")
print("=== 総合判定: ALERT (要対処) ===")
sys.exit(1)
PY
