#!/usr/bin/env bash
# gate_deepdive_replay.sh — deepdive追体験の受領証検証
# 目的: /clear後の追体験(Phase単位・自問つき)が「今セッションで」「全Phase」実行されたかを機械検証する。
#   PASS: 全必須ファイルの全Phaseに、セッションマーカー以降の受領証がある
#   FAIL: 不足Phaseを列挙(この出力をstartup gate/stop hookが強制に使う)
# usage: bash scripts/gates/gate_deepdive_replay.sh <agent>
# 設計不変量: 検証エラー時はfail-open(ERRORを出しPASS扱いにしない/BLOCKにもしない)。
#   受領証の偽造は自問本文の品質レビュー(軍師第三者検証)で捕捉する層別防御。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
agent="${1:-}"
[[ -n "$agent" ]] || { echo "usage: gate_deepdive_replay.sh <agent>"; exit 2; }

case "$agent" in
    shogun) files=(deepdive_why_chain_20260321.md deepdive_causal_tracing_20260415.md) ;;
    karo)   files=(deepdive_why_chain_20260321.md deepdive_karo_verification_20260405.md) ;;
    gunshi) files=(deepdive_why_chain_20260321.md) ;;
    *) echo "DEEPDIVE-REPLAY: SKIP (対象外ロール: $agent)"; exit 0 ;;
esac

receipt="$SCRIPT_DIR/logs/deepdive_replay/${agent}.jsonl"
marker="$SCRIPT_DIR/logs/deepdive_replay/${agent}.session"
marker_ts="1970-01-01T00:00:00+0000"
[[ -f "$marker" ]] && marker_ts="$(cat "$marker" 2>/dev/null || echo "$marker_ts")"

missing=""
for md in "${files[@]}"; do
    f="$SCRIPT_DIR/memory/$md"
    [[ -f "$f" ]] || { echo "DEEPDIVE-REPLAY: ERROR 必読ファイル不在 memory/$md"; exit 0; }
    phases="$(grep -oE '^## Phase [0-9]+' "$f" | grep -oE '[0-9]+' | sort -un)"
    for p in $phases; do
        ok="$(python3 - "$receipt" "$md" "$p" "$marker_ts" 2>/dev/null <<'PY'
import json, sys, os
path, md, phase, marker = sys.argv[1:5]
found = "0"
if os.path.exists(path):
    for line in open(path, encoding='utf-8'):
        try:
            e = json.loads(line)
        except Exception:
            continue
        if e.get("file") == md and str(e.get("phase")) == phase \
           and e.get("ts", "") >= marker and len(e.get("self_question", "")) >= 15:
            found = "1"
print(found)
PY
)"
        [[ "$ok" == "1" ]] || missing="$missing $md:Phase$p"
    done
done

if [[ -z "$missing" ]]; then
    echo "DEEPDIVE-REPLAY: PASS ($agent 今セッション追体験完了 marker=$marker_ts)"
    exit 0
else
    echo "DEEPDIVE-REPLAY: FAIL 未追体験:$missing"
    echo "  → 1 Phaseずつ実行せよ: bash scripts/deepdive_replay.sh $agent <mdファイル名> <Phase番号> \"<自問1行>\""
    exit 1
fi
