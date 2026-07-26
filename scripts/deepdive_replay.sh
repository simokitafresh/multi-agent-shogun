#!/usr/bin/env bash
# deepdive_replay.sh — deepdive追体験の実行装置(pane可視+受領証)
# 目的: 「本当に読んだのか」を自己申告から機械証跡へ変える(殿指摘2026-07-26 23:28)。
#   (1) Phase本文をpaneへ全文表示する(殿がpaneで読んだ内容を確認できる)
#   (2) 各Phaseに1行自問を要求する(空・短文は拒否)
#   (3) 受領証をlogs/deepdive_replay/<agent>.jsonlへ追記する(本文sha256で対象Phaseに束縛)
# usage: bash scripts/deepdive_replay.sh <agent> <mdファイル名(basename)> <phase番号> "<自問1行>"
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

agent="${1:-}"; md="${2:-}"; phase="${3:-}"; question="${4:-}"
if [[ -z "$agent" || -z "$md" || -z "$phase" || -z "$question" ]]; then
    echo "usage: deepdive_replay.sh <agent> <md_basename> <phase_no> \"<自問1行>\"" >&2
    exit 2
fi
file="$SCRIPT_DIR/memory/$md"
[[ -f "$file" ]] || { echo "ERROR: not found: memory/$md" >&2; exit 2; }
if [[ "${#question}" -lt 15 ]]; then
    echo "REJECT: 自問が短すぎる(15字以上)。読んだ内容と今の自分を結べ。" >&2
    exit 3
fi

# Phase本文抽出(## Phase <n>: から次の ## まで)
block="$(awk -v p="$phase" '
    $0 ~ "^## Phase " p "[:：]" {flag=1}
    flag && $0 ~ "^## " && $0 !~ "^## Phase " p "[:：]" {exit}
    flag {print}
' "$file")"
[[ -n "$block" ]] || { echo "ERROR: Phase $phase が memory/$md に見つからない" >&2; exit 2; }

# pane可視表示(全文。省略しない — 流れが本体)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "【deepdive追体験】 $agent — memory/$md Phase $phase"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf '%s\n' "$block"
echo "──────────────────────────────────────"
echo "★自問($agent): $question"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 受領証追記
mkdir -p "$SCRIPT_DIR/logs/deepdive_replay"
sha="$(printf '%s' "$block" | sha256sum | cut -d' ' -f1)"
ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
python3 - "$SCRIPT_DIR/logs/deepdive_replay/${agent}.jsonl" "$ts" "$agent" "$md" "$phase" "$sha" "$question" <<'PY'
import json, sys
path, ts, agent, md, phase, sha, q = sys.argv[1:8]
with open(path, 'a', encoding='utf-8') as f:
    f.write(json.dumps({"ts": ts, "agent": agent, "file": md, "phase": int(phase),
                        "sha256": sha, "self_question": q}, ensure_ascii=False) + "\n")
PY
echo "RECEIPT: logs/deepdive_replay/${agent}.jsonl phase=$phase sha=${sha:0:12}"
