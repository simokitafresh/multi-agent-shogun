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

# 最新session_summaryをセッション境界として扱う。/clear直前の最終防衛線なので、
# 「セッション中のcmd完了あり」を知識埋込みALERTの条件に使う。
session_start_ts=""
session_start_date=""
session_completed_cmds=0
if [ -f "$LORD_CONV" ]; then
  session_state="$(python3 - "$LORD_CONV" <<'PY'
import datetime as dt
import json
import re
import sys

path = sys.argv[1]
entries = []
with open(path, encoding="utf-8") as f:
    for raw in f:
        raw = raw.strip()
        if not raw:
            continue
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            entries.append(parsed)

session_start = ""
for entry in entries:
    if entry.get("direction") == "session_summary" and entry.get("ts"):
        session_start = str(entry["ts"])

cmds = set()
completion_words = ("GATE CLEAR", "委任完了", "完了", "PASS")
for entry in entries:
    ts = str(entry.get("ts", ""))
    if session_start and ts < session_start:
        continue
    if entry.get("direction") not in ("response", "outbound"):
        continue
    text = " ".join(str(entry.get(k, "")) for k in ("summary", "detail", "content", "message", "text"))
    if not any(word in text for word in completion_words):
        continue
    cmds.update(re.findall(r"cmd_[0-9]+", text))

date = ""
if session_start:
    date = session_start[:10]
if not date:
    date = dt.datetime.now().astimezone().date().isoformat()
print(f"{session_start}|{date}|{len(cmds)}")
PY
)"
  session_start_ts="${session_state%%|*}"
  session_state_rest="${session_state#*|}"
  session_start_date="${session_state_rest%%|*}"
  session_completed_cmds="${session_state_rest#*|}"
fi
if [ -z "$session_start_date" ]; then
  session_start_date=$(TZ=Asia/Tokyo date +%Y-%m-%d)
fi

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
if [ "${artifact_warn:-0}" -gt 0 ]; then
  echo "$artifact_output" | awk '/^  WARN:/ { print }'
fi

# ─── Check 8: セッション中の新知識埋込み確認 ───
embed_issues=0
embed_details=()

# (a) lesson_write_shogun.sh実行有無 — 最新session_summaryのts以降にlessonが追加されたか
LESSONS_SHOGUN="$ROOT_DIR/projects/infra/lessons_shogun.yaml"
lesson_count_session=0
cmd_save_block_session=0

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
  embed_details+=("(a)lesson登録: 0件(${session_start_date}以降) WARN lesson_write_shogun.sh未実行?")
else
  embed_details+=("(a)lesson登録: ${lesson_count_session}件(${session_start_date}以降) OK")
fi

CMD_QUALITY_LOG="$ROOT_DIR/logs/cmd_design_quality.yaml"
if [ -f "$CMD_QUALITY_LOG" ]; then
  cmd_save_block_session=$(python3 - "$CMD_QUALITY_LOG" "$session_start_date" <<'PY'
import sys

path = sys.argv[1]
date = sys.argv[2]
count = 0
block = {}

def flush(item):
    global count
    if (
        item.get("source") == "cmd_save"
        and item.get("gate_result") == "BLOCK"
        and item.get("timestamp", "")[:10] >= date
    ):
        count += 1

with open(path, encoding="utf-8") as f:
    for raw in f:
        line = raw.rstrip("\n")
        stripped = line.strip()
        if stripped.startswith("- "):
            flush(block)
            block = {}
            stripped = stripped[2:].strip()
        if ":" not in stripped:
            continue
        key, value = stripped.split(":", 1)
        block[key.strip()] = value.strip().strip('"').strip("'")
flush(block)
print(count)
PY
  )
fi
embed_details+=("(a2)cmd_save BLOCK履歴: ${cmd_save_block_session}件(${session_start_date}以降)")
if [ "${cmd_save_block_session:-0}" -gt 0 ] && [ "${lesson_count_session:-0}" -eq 0 ]; then
  embed_details+=("(a2)ALERT: cmd_save.sh BLOCK履歴あり + lesson_write_shogun.sh実行0件")
  embed_issues=$((embed_issues + 1))
fi

# (b) セマンティクスインデックス更新有無
SEMANTIC_INDEX="$ROOT_DIR/docs/semantic-index/index.md"
if [ -f "$SEMANTIC_INDEX" ]; then
  semantic_date=$(stat -c '%y' "$SEMANTIC_INDEX" 2>/dev/null | cut -d' ' -f1 || echo "1970-01-01")
  if [[ "$semantic_date" > "$session_start_date" || "$semantic_date" == "$session_start_date" ]]; then
    embed_details+=("(b)semantic-index: OK(更新: ${semantic_date})")
  else
    embed_details+=("(b)semantic-index: WARN(最終更新: ${semantic_date} — セッション前から未更新)")
    if [ "${session_completed_cmds:-0}" -gt 0 ]; then
      embed_details+=("(b)ALERT: セッション中cmd完了${session_completed_cmds}件 + semantic-index当日未更新")
      embed_issues=$((embed_issues + 1))
    fi
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
if [ "${pending_insights:-0}" -ge 5 ] && [ "${session_completed_cmds:-0}" -gt 0 ]; then
  embed_details+=("(c)ALERT: セッション中cmd完了${session_completed_cmds}件 + insights未処理${pending_insights}件")
  embed_issues=$((embed_issues + 1))
fi

# (d) 完了cmdのproject別にprojects/*.yamlの更新有無を確認
# セッション中にcmd完了したprojectのprojects/{id}.yamlがセッション後に更新されているか
CHRONICLE="$ROOT_DIR/context/cmd-chronicle.md"
if [ -f "$CHRONICLE" ] && [ -n "$session_start_date" ]; then
  # cmd-chronicleからセッション日以降の完了cmdのprojectを抽出
  session_projects=$(awk -v date="$session_start_date" '
    /^- cmd_[0-9]+:/ { cmd=$0 }
    /\(20[0-9]{2}-[0-9]{2}-[0-9]{2}\)/ {
      match($0, /\(([0-9]{4}-[0-9]{2}-[0-9]{2})\)/, m)
      if (m[1] >= date) {
        # projectを推定: shogun_to_karo.yamlから取得は重いので、chronicleのキーワードから推定
        if ($0 ~ /Simple-OCR|simple-ocr/) print "simple-ocr"
        else if ($0 ~ /DM-Signal|dm-signal/) print "dm-signal"
        else if ($0 ~ /google-classroom/) print "google-classroom"
        else if ($0 ~ /kj-partshift/) print "kj-partshift"
      }
    }
  ' "$CHRONICLE" 2>/dev/null | sort -u)

  # shogun_to_karo.yamlから直接project取得（より正確）
  if [ -f "$CMD_FILE" ]; then
    yaml_projects=$(awk '
      /^  cmd_[0-9]+:/ { cmd=1 }
      cmd && /project:/ {
        val=$2; gsub(/"/, "", val); gsub(/\047/, "", val)
        if (val != "infra" && val != "") projects[val]=1
        cmd=0
      }
      END { for (p in projects) print p }
    ' "$CMD_FILE" 2>/dev/null)
    if [ -n "$yaml_projects" ]; then
      session_projects="$yaml_projects"
    fi
  fi

  stale_projects=()
  for proj in $session_projects; do
    proj_yaml="$ROOT_DIR/projects/${proj}.yaml"
    if [ -f "$proj_yaml" ]; then
      proj_mtime=$(stat -c '%Y' "$proj_yaml" 2>/dev/null || echo 0)
      session_epoch=$(date -d "${session_start_date}T00:00:00" '+%s' 2>/dev/null || echo 0)
      if [ "$proj_mtime" -lt "$session_epoch" ]; then
        stale_projects+=("$proj")
      fi
    fi
  done

  if [ ${#stale_projects[@]} -gt 0 ]; then
    embed_details+=("(d)PJ知識未更新: ${stale_projects[*]} ⚠ projects/*.yamlにセッション中の設計知識が反映されていない可能性")
    embed_issues=$((embed_issues + 1))
  else
    if [ -n "$session_projects" ]; then
      embed_details+=("(d)PJ知識更新: OK(対象PJ全て更新済み)")
    else
      embed_details+=("(d)PJ知識更新: SKIP(infra以外のcmdなし)")
    fi
  fi
fi

echo "[8.知識埋込み] lesson:${lesson_count_session}件(${session_start_date}以降)"
echo "  セッション中cmd完了: ${session_completed_cmds}件"
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

# ─── Check 11: session_summary自動生成 ───
summary_status="SKIP"
summary_detail="lord_conversation.jsonl不在"
if [ -f "$LORD_CONV" ]; then
  summary_result="$(python3 - "$LORD_CONV" "$session_start_ts" <<'PY'
import datetime as dt
import fcntl
import json
import os
import sys

path = sys.argv[1]
session_start = sys.argv[2]

entries = []
bad_lines = 0
with open(path, encoding="utf-8") as f:
    for raw in f:
        line = raw.strip()
        if not line:
            continue
        try:
            parsed = json.loads(line)
        except json.JSONDecodeError:
            bad_lines += 1
            continue
        if isinstance(parsed, dict):
            entries.append(parsed)

inbound = []
for entry in entries:
    if entry.get("direction") != "inbound":
        continue
    ts = str(entry.get("ts", ""))
    if session_start and ts < session_start:
        continue
    text = str(entry.get("summary") or entry.get("detail") or "").strip()
    if text:
        inbound.append(text)

if not inbound:
    print("SKIP|inbound=0")
    raise SystemExit(0)

now = dt.datetime.now().astimezone().isoformat(timespec="seconds")
joined = " / ".join(inbound[-5:])
if len(joined) > 480:
    joined = joined[:479] + "…"
detail = f"auto clear prep summary: inbound={len(inbound)}件; latest={joined}"
entry = {
    "ts": now,
    "source": "clear_prep_check",
    "direction": "session_summary",
    "summary": detail[:140] if len(detail) <= 140 else detail[:139] + "…",
    "detail": detail,
    "agent": "shogun",
}
lock_path = path + ".lock"
with open(lock_path, "w", encoding="utf-8") as lock:
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
    with open(path, "a", encoding="utf-8") as out:
        out.write(json.dumps(entry, ensure_ascii=False) + "\n")
    fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
print(f"APPENDED|inbound={len(inbound)}, bad_json={bad_lines}")
PY
)"
  summary_status="${summary_result%%|*}"
  summary_detail="${summary_result#*|}"
fi
echo "[11.session_summary] ${summary_status}: ${summary_detail}"

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
