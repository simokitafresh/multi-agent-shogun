#!/bin/bash
# Thread 投稿 runner(Growth v1.2 §36、殿裁定 15:11)。親 1 本→自己リプ n 本を 1 コマンドで流し、thread_ledger へ記録する。
# Usage: bash scripts/x_ops/x_thread_post.sh <thread_id> <parent_draft_id> <reply_draft_id>... [--lane L] [--stage S]
#   例: bash scripts/x_ops/x_thread_post.sh T1 2026-09-04_R5-T-1-P 2026-09-04_R5-T-1-R1 2026-09-04_R5-T-1-R2 2026-09-04_R5-T-1-R3
# 各 draft は .approved 必須(x_post.sh post が検査)。content_units=1、physical_posts=1+n。token は x_post.sh の helper 経路のみ。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; cd "$ROOT"
TL="queue/x_live_oos/thread_ledger.yaml"; LOG="logs/x_thread_post.log"; mkdir -p logs
tid="${1:?thread_id}"; shift; parent="${1:?parent draft}"; shift
lane="investing"; stage="trust"; replies=()
while [[ $# -gt 0 ]]; do case "$1" in --lane) lane="$2"; shift 2;; --stage) stage="$2"; shift 2;; *) replies+=("$1"); shift;; esac; done
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
pid_of() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"]["data"]["id"])' "queue/x_drafts/$1.posted"; }
for d in "$parent" "${replies[@]}"; do [[ -f "queue/x_drafts/$d.approved" ]] || { log "not approved: $d"; exit 1; }; done
out="$(timeout 180 bash scripts/x_ops/x_post.sh post "$parent" 2>&1 | grep -vE 'warn|protected|^$')" || { log "PARENT FAILED $parent: ${out:0:160}"; exit 1; }
ppid="$(pid_of "$parent")"; log "parent $parent id=$ppid"
ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"; rep_yaml=""; prev="$ppid"; k=0
for d in "${replies[@]}"; do
    k=$((k+1)); sleep 20
    out="$(timeout 180 bash scripts/x_ops/x_post.sh post "$d" --reply-to "$prev" 2>&1 | grep -vE 'warn|protected|^$')" || { log "REPLY $k FAILED $d: ${out:0:160}"; break; }
    rid="$(pid_of "$d")"; log "reply $k $d id=$rid"; rep_yaml+="  - {position: $k, draft_id: $d, post_id: '$rid'}\n"; prev="$rid"
done
cat >> "$TL" <<EOF
- thread_id: $tid
  content_lane: $lane
  funnel_stage: $stage
  content_units: 1
  physical_posts: $((1 + k))
  parent: {draft_id: $parent, post_id: '$ppid', posted_at: '$ts'}
  replies:
$(printf "$rep_yaml")  snapshots: {}
EOF
python3 -c "import yaml;yaml.safe_load(open('$TL'))" && log "thread_ledger ok $tid physical_posts=$((1 + k))"
bash scripts/ntfy.sh "【将軍】X Thread $tid 投稿 親+$k → https://x.com/TokyoJibika/status/$ppid" >/dev/null 2>&1 || true
