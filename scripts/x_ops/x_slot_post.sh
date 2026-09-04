#!/bin/bash
# 定時投稿(live OOS)。cron 平日 08:30/18:30 JST から呼ぶ。
# slot_calendar v2 の slot 順(pointer)に従い、承認済み(.approved)かつ未投稿(.posted 無し)の draft を 1 本投稿し、
# live OOS 台帳へ post_id/posted_at を書く。該当 slot の在庫が無ければ次の slot 文字へ繰り下げる(最大 20)。
# 投稿は x_post.sh post(refresh helper→urllib 直叩き)。token を直接触らない。
# 殿指示 2026-09-04 14:51 §20 live OOS / §14 平日 2 投稿を維持。
set -euo pipefail
# T3-S-69(2026-09-04 16:25): 将軍が構文確認のつもりで `x_slot_post.sh --help` を実行し、引数無視で本番投稿(R4-A-1)が走った。引数は fail-close にする
DRY=0
for a in "$@"; do case "$a" in --dry-run) DRY=1;; --help|-h) echo "usage: x_slot_post.sh [--dry-run]  (cron: 30 8,12,18 * * *)"; exit 0;; *) echo "x_slot_post.sh: unknown arg $a" >&2; exit 2;; esac; done
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
CAL="skills/x-post-pipeline/slot_calendar.yaml"
LEDGER="queue/x_live_oos/ledger.yaml"
PTR="queue/x_live_oos/slot_pointer.txt"
LOG="logs/x_slot_post.log"
mkdir -p queue/x_live_oos logs
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

mapfile -t SLOTS < <(python3 - "$CAL" <<'PY'
import sys, yaml
for s in yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["slots"]:
    print(s["slot"] + ":" + s.get("format", "short"))
PY
)
n=${#SLOTS[@]}
ptr=$(cat "$PTR" 2>/dev/null || echo 0)
picked=""; slot=""
for ((k=0; k<n; k++)); do
    idx=$(( (ptr + k) % n )); slot="${SLOTS[$idx]%%:*}"; fmt="${SLOTS[$idx]#*:}"
    for f in $(ls queue/x_drafts/*_R[0-9]*-"$slot"-[0-9]*.approved 2>/dev/null | sort); do
        base="${f%.approved}"
        [[ -f "$base.posted" ]] && continue
        picked="$(basename "$base")"; break
    done
    [[ -n "$picked" ]] && { ptr=$(( (idx + 1) % n )); break; }
done
if [[ -z "$picked" ]]; then
    log "no approved unposted draft for any slot (ptr=$ptr)"
    bash scripts/ntfy.sh "【将軍】X 定時投稿: 承認済み在庫なし。生成→承認が必要" >/dev/null 2>&1 || true
    exit 0
fi
# v1.2: calendar format(long/thread/series_entry)に対し在庫が short しか無い間は format_fallback を記録(事前登録=正本、事後付け替え禁止)
fb=""; [[ "$fmt" != short ]] && fb=" format_fallback=short(在庫)"
log "slot=$slot planned_format=$fmt draft=$picked ptr_next=$ptr$fb"
[[ "$DRY" = 1 ]] && { log "dry-run: no post"; exit 0; }
if ! out="$(timeout 180 bash scripts/x_ops/x_post.sh post "$picked" 2>&1 | grep -vE 'warn|protected|^$')"; then
    log "POST FAILED draft=$picked: ${out:0:200}"
    bash scripts/ntfy.sh "【将軍】X 定時投稿 失敗 $picked: ${out:0:120}" >/dev/null 2>&1 || true
    exit 1
fi
echo "$ptr" > "$PTR"
pid="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["result"]["data"]["id"])' "queue/x_drafts/$picked.posted" 2>/dev/null || true)"
ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
draft_id="${picked#*_}"
if [[ -n "$pid" ]] && grep -q "^- draft_id: $draft_id$" "$LEDGER" 2>/dev/null; then
    python3 - "$LEDGER" "$draft_id" "$pid" "$ts" <<'PY'
import re, sys
p, did, pid, ts = sys.argv[1:]
t = open(p, encoding="utf-8").read()
i = t.index(f"- draft_id: {did}\n"); j = t.find("\n- draft_id: ", i + 1); j = len(t) if j < 0 else j
e = t[i:j]
e = re.sub(r"^  post_id: .*$", f"  post_id: '{pid}'", e, count=1, flags=re.M)
e = re.sub(r"^  posted_at: .*$", f"  posted_at: '{ts}'", e, count=1, flags=re.M)
open(p, "w", encoding="utf-8").write(t[:i] + e + t[j:])
PY
fi
log "POSTED draft=$picked id=$pid"
bash scripts/ntfy.sh "【将軍】X 定時投稿 $slot $picked → https://x.com/TokyoJibika/status/$pid" >/dev/null 2>&1 || true
