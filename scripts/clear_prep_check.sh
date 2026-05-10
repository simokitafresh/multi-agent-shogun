#!/bin/bash
# clear_prep_check.sh — /shogun-clear-prep 用の/clear前確認
# /clearで消える情報がないか7項目チェック
# Usage: bash scripts/clear_prep_check.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PD_FILE="$ROOT_DIR/queue/pending_decisions.yaml"
CMD_FILE="$ROOT_DIR/queue/shogun_to_karo.yaml"
DASHBOARD_FILE="$ROOT_DIR/dashboard.md"
SNAPSHOT_FILE="$ROOT_DIR/queue/karo_snapshot.txt"
LORD_CONV="$ROOT_DIR/queue/lord_conversation.jsonl"
PROGRESS_FILE="$ROOT_DIR/context/l2-okugi-progress.md"
SNAPSHOT_STALE_THRESHOLD=600  # 10分（秒）

issues=0
issue_reasons=()

echo "=== clear_prep_check $(date '+%Y-%m-%dT%H:%M:%S%z') ==="

# ─── Check 1: PD未決 ───
pd_count=0
pd_ids="なし"
if [ -f "$PD_FILE" ]; then
  pd_result="$(awk '
    /^[[:space:]]*id:[[:space:]]*/ {
      id=$2
      gsub(/"/, "", id)
      gsub(/\047/, "", id)
    }
    /^[[:space:]]*status:[[:space:]]*/ {
      status=$2
      gsub(/"/, "", status)
      gsub(/\047/, "", status)
      if (id != "" && status != "resolved" && status != "deferred") {
        ids[++count] = id
      }
      id = ""
    }
    END {
      if (count == 0) {
        printf "0|なし"
      } else {
        printf "%d|", count
        for (i = 1; i <= count; i++) {
          printf "%s", ids[i]
          if (i < count) printf ", "
        }
      }
    }
  ' "$PD_FILE")"
  pd_count="${pd_result%%|*}"
  pd_ids="${pd_result#*|}"
fi
echo "[1.PD未決] ${pd_count}件: ${pd_ids}"
if [ "$pd_count" -gt 0 ]; then
  issues=$((issues + pd_count))
  issue_reasons+=("PD未決${pd_count}")
fi

# ─── Check 2: cmd pending ───
cmd_count=0
cmd_ids="なし"
if [ -f "$CMD_FILE" ]; then
  cmd_result="$(awk '
    /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/ {
      id=$3
      gsub(/"/, "", id)
      gsub(/\047/, "", id)
    }
    /^[[:space:]]*status:[[:space:]]*/ {
      status=$2
      gsub(/"/, "", status)
      gsub(/\047/, "", status)
      if (id != "" && status == "pending") {
        ids[++count] = id
      }
      id = ""
    }
    END {
      if (count == 0) {
        printf "0|なし"
      } else {
        printf "%d|", count
        for (i = 1; i <= count; i++) {
          printf "%s", ids[i]
          if (i < count) printf ", "
        }
      }
    }
  ' "$CMD_FILE")"
  cmd_count="${cmd_result%%|*}"
  cmd_ids="${cmd_result#*|}"
fi
echo "[2.cmd pending] ${cmd_count}件: ${cmd_ids}"
if [ "$cmd_count" -gt 0 ]; then
  issues=$((issues + cmd_count))
  issue_reasons+=("cmd_pending${cmd_count}")
fi

# ─── Check 3: 🚨要対応 ───
alert_count=0
alert_lines=()
if [ -f "$DASHBOARD_FILE" ]; then
  mapfile -t alert_lines < <(awk '
    /^## .*🚨 要対応/ { in_section=1; next }
    in_section && /^## / { in_section=0 }
    in_section && /^[[:space:]]*[0-9]+\./ {
      line=$0
      sub(/^[[:space:]]*[0-9]+\.[[:space:]]*/, "", line)
      print line
    }
  ' "$DASHBOARD_FILE")
  alert_count="${#alert_lines[@]}"
fi
echo "[3.🚨要対応] ${alert_count}件"
if [ "$alert_count" -gt 0 ]; then
  for line in "${alert_lines[@]}"; do
    echo "  - ${line}"
  done
  issues=$((issues + alert_count))
  issue_reasons+=("要対応${alert_count}")
else
  echo "  - なし"
fi

# ─── Check 4: 忍者状態+陣形図鮮度 ───
ninja_active=0
ninja_idle=0
ninja_blocked=0
if [ -f "$SNAPSHOT_FILE" ]; then
  ninja_result="$(awk -F'|' '
    /^ninja\|/ {
      status=$4
      if (status == "assigned" || status == "acknowledged" || status == "in_progress") {
        active++
      } else if (status == "blocked") {
        blocked++
      }
    }
    /^idle\|/ {
      split($2, names, ",")
      for (i in names) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", names[i])
        if (names[i] != "" && names[i] != "none") {
          idle++
        }
      }
    }
    END {
      printf "%d|%d|%d", active+0, idle+0, blocked+0
    }
  ' "$SNAPSHOT_FILE")"
  ninja_active="${ninja_result%%|*}"
  rest="${ninja_result#*|}"
  ninja_idle="${rest%%|*}"
  ninja_blocked="${rest#*|}"
fi

snapshot_stale=false
snapshot_age_min=0
if [ -f "$SNAPSHOT_FILE" ]; then
  snapshot_mtime=$(stat -c %Y "$SNAPSHOT_FILE" 2>/dev/null || echo 0)
  now=$(date +%s)
  snapshot_age_sec=$((now - snapshot_mtime))
  snapshot_age_min=$((snapshot_age_sec / 60))
  if [ "$snapshot_age_sec" -gt "$SNAPSHOT_STALE_THRESHOLD" ]; then
    snapshot_stale=true
  fi
fi

echo "[4.忍者] 稼働${ninja_active} / idle${ninja_idle} / blocked${ninja_blocked}"
if [ "$snapshot_stale" = true ]; then
  echo "  ⚠ 陣形図が古い (${snapshot_age_min}分前更新)"
  issues=$((issues + 1))
  issue_reasons+=("陣形図stale_${snapshot_age_min}min")
fi
if [ "$ninja_blocked" -gt 0 ]; then
  issues=$((issues + ninja_blocked))
  issue_reasons+=("blocked${ninja_blocked}")
fi

# ─── Check 5: 会話記録の健全度 ───
conv_status="OK"
conv_detail=""
if [ -f "$LORD_CONV" ]; then
  conv_result="$(python3 - "$LORD_CONV" <<'PY'
import json
import sys

path = sys.argv[1]
entries = []
bad_lines = 0
with open(path, encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            bad_lines += 1

session_start = ""
for entry in entries:
    if entry.get("direction") == "session_summary" and entry.get("ts"):
        session_start = entry["ts"]

inbound = [
    entry for entry in entries
    if entry.get("direction") == "inbound"
    and (not session_start or entry.get("ts", "") >= session_start)
]
last_inbound = inbound[-1].get("ts", "none") if inbound else "none"
print(f"{len(inbound)}|{last_inbound}|{session_start or 'none'}|{bad_lines}")
PY
)"
  inbound_session="${conv_result%%|*}"
  conv_rest="${conv_result#*|}"
  last_inbound_ts="${conv_rest%%|*}"
  conv_rest="${conv_rest#*|}"
  session_start_ts="${conv_rest%%|*}"
  bad_json_lines="${conv_rest#*|}"
  conv_detail="殿の発言 inbound=${inbound_session}件(現セッション), 直近=${last_inbound_ts}, session_start=${session_start_ts}"
  if [ "${bad_json_lines:-0}" -gt 0 ]; then
    conv_detail="${conv_detail}, JSON不正行=${bad_json_lines}"
    conv_status="WARN"
    issues=$((issues + 1))
    issue_reasons+=("会話記録JSON不正${bad_json_lines}")
  fi
  if [ "${inbound_session:-0}" -eq 0 ]; then
    conv_status="WARN"
    issues=$((issues + 1))
    issue_reasons+=("会話記録現セッションinbound=0")
  fi
else
  conv_status="WARN"
  conv_detail="lord_conversation.jsonl不在"
  issues=$((issues + 1))
  issue_reasons+=("会話記録ファイル不在")
fi
echo "[5.会話記録] ${conv_status}: ${conv_detail}"

# ─── Check 6: 未commit変更 ───
uncommitted_count=0
uncommitted_files=""
if command -v git &>/dev/null && git -C "$ROOT_DIR" rev-parse --git-dir &>/dev/null; then
  # Staged + unstaged modified + untracked (excluding queue/ logs/ etc.)
  # WSL2 NTFS最適化: フルスキャン(1.7s)→パス限定(0.2s)。除外grepチェーンも不要に
  uncommitted_files=$(git -C "$ROOT_DIR" status --porcelain -- scripts/ instructions/ config/ context/ CLAUDE.md 2>/dev/null \
    | head -20)
  uncommitted_count=$(echo "$uncommitted_files" | grep -c '[^ ]' || true)
fi
echo "[6.未commit] ${uncommitted_count}件"
if [ "$uncommitted_count" -gt 0 ]; then
  echo "$uncommitted_files" | head -10 | sed 's/^/  /'
  if [ "$uncommitted_count" -gt 10 ]; then
    echo "  ... (+$((uncommitted_count - 10))件)"
  fi
  # INFO扱い（WARNではない。運用ファイルの変更は常にある）
  # ただしscripts/やcontext/の変更はWARN
  critical_uncommitted=$(echo "$uncommitted_files" | grep -cE '^\s*[MADR?]+\s+(scripts/|context/|instructions/)' || true)
  if [ "$critical_uncommitted" -gt 0 ]; then
    echo "  ⚠ scripts/context/instructions配下に未commit変更あり(${critical_uncommitted}件)"
    issues=$((issues + 1))
    issue_reasons+=("重要ファイル未commit${critical_uncommitted}")
  fi
fi

# ─── Check 7: 成果物マッピング健全度 ───
artifact_status="SKIP"
if [ -f "$PROGRESS_FILE" ] && [ -f "$ROOT_DIR/scripts/gates/gate_artifact_map.sh" ]; then
  artifact_output=$(bash "$ROOT_DIR/scripts/gates/gate_artifact_map.sh" "$PROGRESS_FILE" 2>&1 || true)
  # gate出力の詳細行は "  WARN: [block]" (先頭スペースあり)。集計行は "WARN: N" (先頭スペースなし)
  artifact_warn=$(echo "$artifact_output" | grep '^  WARN:' | grep -c '' || true)
  artifact_blocks=$(echo "$artifact_output" | grep '総ブロック' | grep -oP '[0-9]+' | head -1 || echo "0")
  artifact_done=$(echo "$artifact_output" | grep 'GS完了ブロック' | grep -oP '[0-9]+' | head -1 || echo "0")
  if [ "$artifact_warn" -gt 0 ]; then
    artifact_status="WARN(${artifact_warn}件の成果物所在欠落)"
    issues=$((issues + 1))
    issue_reasons+=("成果物欠落${artifact_warn}")
  else
    artifact_status="OK(${artifact_blocks}ブロック, GS完了${artifact_done})"
  fi
else
  artifact_status="SKIP(進行表 or gateなし)"
fi
echo "[7.成果物] ${artifact_status}"

# ─── Check 8: セッション中の新知識埋込み確認 ───
embed_issues=0
embed_details=()

# (a) lesson_write_shogun.sh実行有無 — 最新session_summaryのts以降にlessonが追加されたか
LESSONS_SHOGUN="$ROOT_DIR/projects/infra/lessons_shogun.yaml"
session_start_date=""
lesson_count_session=0
if [ -f "$LORD_CONV" ]; then
  # 最新session_summaryのts日付(セッション開始時刻の近似)
  session_start_date=$(grep '"session_summary"' "$LORD_CONV" | tail -1 | \
    grep -oP '"ts":\s*"\K[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || echo "")
fi
if [ -z "$session_start_date" ]; then
  session_start_date=$(TZ=Asia/Tokyo date +%Y-%m-%d)
fi

if [ -f "$LESSONS_SHOGUN" ]; then
  lesson_count_session=$(awk -v date="$session_start_date" '
    /created_at:/ {
      val=$2; gsub(/'"'"'/, "", val); gsub(/"/, "", val)
      if (val >= date) count++
    }
    END { print count+0 }
  ' "$LESSONS_SHOGUN" 2>/dev/null || echo 0)
fi

if [ "${lesson_count_session:-0}" -eq 0 ]; then
  embed_details+=("(a)lesson登録: 0件(${session_start_date}以降) ⚠ lesson_write_shogun.sh未実行?")
  embed_issues=$((embed_issues + 1))
else
  embed_details+=("(a)lesson登録: ${lesson_count_session}件(${session_start_date}以降) OK")
fi

# (b) セマンティクスインデックス更新有無
SEMANTIC_INDEX="$ROOT_DIR/docs/semantic-index/index.md"
if [ -f "$SEMANTIC_INDEX" ]; then
  semantic_date=$(stat -c '%y' "$SEMANTIC_INDEX" 2>/dev/null | cut -d' ' -f1 || echo "1970-01-01")
  if [[ "$semantic_date" > "$session_start_date" || "$semantic_date" == "$session_start_date" ]]; then
    embed_details+=("(b)semantic-index: OK(更新: ${semantic_date})")
  else
    embed_details+=("(b)semantic-index: WARN(最終更新: ${semantic_date} — セッション前から未更新)")
  fi
else
  embed_details+=("(b)semantic-index: SKIP(ファイル不在)")
fi

# (c) insights未処理件数
INSIGHTS_FILE="$ROOT_DIR/queue/insights.yaml"
pending_insights=0
if [ -f "$INSIGHTS_FILE" ]; then
  pending_insights=$(grep -c 'status: pending' "$INSIGHTS_FILE" 2>/dev/null || echo 0)
fi
embed_details+=("(c)insights未処理: ${pending_insights}件")

echo "[8.知識埋込み] lesson:${lesson_count_session}件(${session_start_date}以降)"
for d in "${embed_details[@]}"; do
  echo "  ${d}"
done
if [ "$embed_issues" -gt 0 ]; then
  issues=$((issues + 1))
  issue_reasons+=("知識埋込み未確認")
fi

# ─── Check 9: 強くてニューゲームリマインダ ───
echo "[9.強くてニューゲーム] 今クリアされても次の将軍はこのセッションの学びを持っているか？"

# ─── Check 10: 裁定のprojects反映 ───
decision_status="OK"
decision_detail="裁定キーワードinbound=0件"
if [ -f "$LORD_CONV" ]; then
  decision_result="$(python3 - "$LORD_CONV" "$ROOT_DIR/projects" <<'PY'
import datetime as dt
import glob
import json
import os
import sys

conv_path = sys.argv[1]
projects_dir = sys.argv[2]
keywords = ("裁定", "決裁", "決定", "方針", "承認", "却下")

decision_count = 0
latest_decision_ts = ""
bad_lines = 0
with open(conv_path, encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            bad_lines += 1
            continue
        if entry.get("direction") != "inbound":
            continue
        text = " ".join(str(entry.get(k, "")) for k in ("detail", "content", "message", "text"))
        if not any(keyword in text for keyword in keywords):
            continue
        decision_count += 1
        ts = str(entry.get("ts", ""))
        if ts and ts > latest_decision_ts:
            latest_decision_ts = ts

project_files = glob.glob(os.path.join(projects_dir, "*.yaml"))
latest_project_mtime = 0.0
latest_project_path = "none"
for path in project_files:
    try:
        mtime = os.path.getmtime(path)
    except OSError:
        continue
    if mtime > latest_project_mtime:
        latest_project_mtime = mtime
        latest_project_path = os.path.basename(path)

def parse_ts(value):
    if not value:
        return 0.0
    normalized = value.replace("Z", "+00:00")
    try:
        return dt.datetime.fromisoformat(normalized).timestamp()
    except ValueError:
        return 0.0

latest_decision_epoch = parse_ts(latest_decision_ts)
latest_project_iso = "none"
if latest_project_mtime:
    latest_project_iso = dt.datetime.fromtimestamp(latest_project_mtime, dt.timezone.utc).astimezone().isoformat(timespec="seconds")

needs_update = decision_count > 0 and (not latest_project_mtime or latest_project_mtime < latest_decision_epoch)
print(f"{decision_count}|{latest_decision_ts or 'none'}|{latest_project_iso}|{latest_project_path}|{1 if needs_update else 0}|{bad_lines}")
PY
)"
  decision_count="${decision_result%%|*}"
  decision_rest="${decision_result#*|}"
  latest_decision_ts="${decision_rest%%|*}"
  decision_rest="${decision_rest#*|}"
  latest_project_ts="${decision_rest%%|*}"
  decision_rest="${decision_rest#*|}"
  latest_project_file="${decision_rest%%|*}"
  decision_rest="${decision_rest#*|}"
  decision_needs_update="${decision_rest%%|*}"
  decision_bad_lines="${decision_rest#*|}"
  decision_detail="裁定キーワードinbound=${decision_count}件, 最新裁定=${latest_decision_ts}, projects最新=${latest_project_ts}(${latest_project_file})"
  if [ "${decision_bad_lines:-0}" -gt 0 ]; then
    decision_detail="${decision_detail}, JSON不正行=${decision_bad_lines}"
  fi
  if [ "${decision_needs_update:-0}" -eq 1 ]; then
    decision_status="ALERT"
    issues=$((issues + 1))
    issue_reasons+=("裁定projects未反映")
  fi
else
  decision_detail="lord_conversation.jsonl不在"
fi
echo "[10.裁定反映] ${decision_status}: ${decision_detail}"

# ─── 総合判定 ───
echo ""
if [ "$issues" -gt 0 ]; then
  reason_str=$(IFS=','; echo "${issue_reasons[*]}")
  echo "[STATUS] ALERT (${reason_str})"
else
  echo "[STATUS] OK"
fi
echo "========================"

exit "$( [ "$issues" -gt 0 ] && echo 1 || echo 0 )"
