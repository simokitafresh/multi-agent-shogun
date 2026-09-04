#!/bin/bash
# 定時投稿(live OOS)。cron 毎日 08:30/18:30 JST(v1.6: 殿裁定 2026-09-04 18:22 投資ネタだけで 4 週間、2 units/日)。
# v1.5(2026-09-04 17:50): 選定は live OOS 台帳の事前登録(content_category × format)で行う。
#   calendar の slot 文字=category。format 一致を優先し、無ければ同 category の short(format_fallback を記録)、それも無ければ次 slot へ。
#   Thread は x_thread_post.sh へ委譲(親+自己リプ=content_units 1)。
# 投稿は x_post.sh post(refresh helper→urllib 直叩き)。token を直接触らない。
set -euo pipefail
# T3-S-69(2026-09-04 16:25): 引数無視で本番投稿が走った。引数は fail-close にする
DRY=0
for a in "$@"; do case "$a" in --dry-run) DRY=1;; --help|-h) echo "usage: x_slot_post.sh [--dry-run]  (cron: 30 8,18 * * *)"; exit 0;; *) echo "x_slot_post.sh: unknown arg $a" >&2; exit 2;; esac; done
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
CAL="skills/x-post-pipeline/slot_calendar.yaml"
LEDGER="queue/x_live_oos/ledger.yaml"
PTR="queue/x_live_oos/slot_pointer.txt"
LOG="logs/x_slot_post.log"
mkdir -p queue/x_live_oos logs
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

ptr=$(cat "$PTR" 2>/dev/null || echo 0)
sel="$(python3 - "$CAL" "$LEDGER" "$ptr" <<'PY'
import os, sys, yaml
cal, ledger, ptr = sys.argv[1], sys.argv[2], int(sys.argv[3])
slots = [(s["slot"], s.get("format", "short")) for s in yaml.safe_load(open(cal, encoding="utf-8"))["slots"]]
d = yaml.safe_load(open(ledger, encoding="utf-8")) or {}
def ok(e):
    if e.get("post_id"):
        return False
    f = "queue/x_drafts/" + os.path.basename(str(e.get("draft_file", ""))).rsplit(".", 1)[0]
    return os.path.exists(f + ".approved") and not os.path.exists(f + ".posted")
ents = [e for e in d.get("entries", []) if ok(e)]
g = lambda e: e.get("growth", {}) or {}
n = len(slots)
for k in range(n):
    idx = (ptr + k) % n
    cat, fm = slots[idx]
    cand = [e for e in ents if (cat == "*" or g(e).get("content_category") == cat) and g(e).get("format") == fm and not g(e).get("thread_position")]
    fb = ""
    # v1.6(殿裁定 18:22): 在庫が無い slot は投稿しない(fallback 廃止)。次 slot へ繰り下げるだけ
    if cand:
        e = sorted(cand, key=lambda e: e["draft_id"])[0]
        print("|".join([str(idx), cat, fm, e["draft_id"], str(g(e).get("format")), fb or "-", os.path.basename(str(e["draft_file"])).rsplit(".", 1)[0]]))
        break
print("N|" + str(n))
PY
)"
n="$(printf '%s\n' "$sel" | awk -F'|' '$1=="N"{print $2}')"
line="$(printf '%s\n' "$sel" | grep -v '^N' | head -1 || true)"
if [[ -z "$line" ]]; then
    log "no approved unposted draft for any slot (ptr=$ptr)"
    bash scripts/ntfy.sh "【将軍】X 定時投稿: 承認済み在庫なし。生成→承認が必要" >/dev/null 2>&1 || true
    exit 0
fi
# T3-S-70(18:30 投稿失敗): tab 区切りは bash read が連続 tab を潰し空欄で列がずれた→'|' 区切り+空欄は '-'
IFS='|' read -r idx slot fmt picked_id real_fmt fb picked <<< "$line"
ptr=$(( (idx + 1) % n ))
log "slot=$slot planned_format=$fmt draft=$picked real_format=$real_fmt ptr_next=$ptr ${fb:-}"
[[ "$DRY" = 1 ]] && { log "dry-run: no post"; exit 0; }

if [[ "$real_fmt" = thread ]]; then
    base="${picked%-P}"; tid="${picked_id%-P}"
    reps=(); for r in 1 2 3; do [[ -f "queue/x_drafts/$base-R$r.approved" ]] && reps+=("$base-R$r"); done
    if bash scripts/x_ops/x_thread_post.sh "$tid" "$picked" "${reps[@]}" --lane investing --stage trust; then
        echo "$ptr" > "$PTR"; log "THREAD POSTED $tid"; exit 0
    else
        log "THREAD FAILED $tid"; exit 1
    fi
fi

if ! out="$(timeout 180 bash scripts/x_ops/x_post.sh post "$picked" 2>&1 | grep -vE 'warn|protected|^$')"; then
    log "POST FAILED draft=$picked: ${out:0:200}"
    bash scripts/ntfy.sh "【将軍】X 定時投稿 失敗 $picked: ${out:0:120}" >/dev/null 2>&1 || true
    exit 1
fi
echo "$ptr" > "$PTR"
pid="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["result"]["data"]["id"])' "queue/x_drafts/$picked.posted" 2>/dev/null || true)"
ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
if [[ -n "$pid" ]] && grep -q "^- draft_id: $picked_id$" "$LEDGER" 2>/dev/null; then
    python3 - "$LEDGER" "$picked_id" "$pid" "$ts" <<'PY'
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
