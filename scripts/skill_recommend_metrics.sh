#!/usr/bin/env bash
# semantic-links: [[Phase2計測基盤全ロール共通]]
# skill_recommend_metrics.sh — Compare skill recommendation logs with execution logs.
# Usage:
#   bash scripts/skill_recommend_metrics.sh [limit]

set -euo pipefail

REPO_ROOT="${SHOGUN_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LIMIT="${1:-30}"
RECOMMEND_LOG="${SKILL_RECOMMEND_LOG_FILE:-$REPO_ROOT/logs/skill_recommend_log.yaml}"
EXEC_LOG="${SKILL_EXECUTION_LOG_FILE:-$REPO_ROOT/logs/skill_execution_log.yaml}"

python3 - "$RECOMMEND_LOG" "$EXEC_LOG" "$LIMIT" <<'PY'
import sys
from collections import Counter
from datetime import datetime

import yaml

recommend_path, exec_path, raw_limit = sys.argv[1:4]
try:
    limit = int(raw_limit)
except ValueError:
    limit = 30
if limit <= 0:
    limit = 30


def load_yaml(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return yaml.safe_load(fh) or {}
    except FileNotFoundError:
        return {}
    except yaml.YAMLError as exc:
        print(f"ALERT: YAML parse failed: {path}: {exc}")
        raise SystemExit(1)


def normalize_ts(value):
    text = str(value or "").strip()
    if not text:
        return ""
    # Logs contain both +09:00 and +0900 offsets. Normalize before comparison.
    if len(text) >= 5 and text[-5] in "+-" and text[-3] != ":":
        text = f"{text[:-2]}:{text[-2:]}"
    try:
        return datetime.fromisoformat(text).isoformat()
    except ValueError:
        return text


recommend_data = load_yaml(recommend_path)
exec_data = load_yaml(exec_path)
raw_recommend_entries = [
    item for item in (recommend_data.get("recommendations") or [])
    if isinstance(item, dict)
]

seen_recent_tuples = set()
recommend_entries_reversed = []
for entry in reversed(raw_recommend_entries):
    agent_id = str(entry.get("agent_id") or "").strip() or "unknown"
    prompt_hash = str(entry.get("prompt_hash") or "").strip()
    skills = entry.get("recommended_skills") or []
    if isinstance(skills, str):
        skills = [skills]
    entry_tuples = []
    for skill in skills:
        skill_name = str(skill or "").strip()
        if skill_name:
            entry_tuples.append((agent_id, prompt_hash, skill_name))
    if not entry_tuples:
        continue
    new_tuples = [item for item in entry_tuples if item not in seen_recent_tuples]
    if not new_tuples:
        continue
    recommend_entries_reversed.append(entry)
    for item in new_tuples:
        seen_recent_tuples.add(item)
        if len(seen_recent_tuples) >= limit:
            break
    if len(seen_recent_tuples) >= limit:
        break
recommend_entries = list(reversed(recommend_entries_reversed))

# recall miss計算は推薦開始以降の実行ログのみ対象(推薦前の実行を誤計上しない)
first_recommend_ts = ""
for entry in recommend_entries:
    ts = normalize_ts(entry.get("ts"))
    if ts:
        first_recommend_ts = ts
        break

all_exec = [
    item for item in (exec_data.get("executions") or [])
    if isinstance(item, dict) and str(item.get("used", "true")).lower() != "false"
]
instrumented_agents = {
    str(item.get("executor") or "").strip() or "unknown"
    for item in all_exec
}
if first_recommend_ts:
    exec_entries = [e for e in all_exec if normalize_ts(e.get("ts")) >= first_recommend_ts][-limit:]
else:
    exec_entries = all_exec[-limit:]

seen_recommend_tuples = set()
recommended_by_agent = []
dropped_non_instrumented = 0
for entry in recommend_entries:
    agent_id = str(entry.get("agent_id") or "").strip() or "unknown"
    if agent_id not in instrumented_agents:
        dropped_non_instrumented += 1
        continue
    prompt_hash = str(entry.get("prompt_hash") or "").strip()
    skills = entry.get("recommended_skills") or []
    if isinstance(skills, str):
        skills = [skills]
    for skill in skills:
        skill_name = str(skill or "").strip()
        if not skill_name:
            continue
        recommend_tuple = (agent_id, prompt_hash, skill_name)
        if recommend_tuple in seen_recommend_tuples:
            continue
        if recommend_tuple not in seen_recent_tuples:
            continue
        seen_recommend_tuples.add(recommend_tuple)
        recommended_by_agent.append((agent_id, skill_name))

executed_by_agent = []
for entry in exec_entries:
    skill_name = str(entry.get("skill") or "").strip()
    if not skill_name:
        continue
    executor = str(entry.get("executor") or "").strip() or "unknown"
    executed_by_agent.append((executor, skill_name))

recommend_counter = Counter(recommended_by_agent)
executed_counter = Counter(executed_by_agent)

recommended_total = sum(recommend_counter.values())
hit_total = sum(min(count, executed_counter.get(key, 0)) for key, count in recommend_counter.items())
precision = round((hit_total / recommended_total) * 100) if recommended_total else 0
false_positive_candidate_count = max(0, recommended_total - hit_total)
false_positive_rate = round((false_positive_candidate_count / recommended_total) * 100) if recommended_total else 0
min_data = 10  # 推薦ログがmin_data未満ならrecall母集団なし(ALERT抑制)
auto_covered_recall_skills = {
    # cmd_complete_gate/dashboard_update自体が実行導線であり、prompt_state推薦ログに
    # 出ないことをrecall missにすると計測対象がズレる。
    "cmd-complete",
    "dashboard-update",
    # 忍者専用スキルはtask YAML推薦で到達。忍者プロンプト=inbox nudge(フィルタ済み)
    # のためprompt推薦が構造的に不可能。recall missは偽アラーム。
    "report-write",
    "verdict-check",
    "ninja-commit",
}
recall_misses = []
if recommended_total >= min_data:
    for (executor, skill), count in sorted(executed_counter.items()):
        if skill in auto_covered_recall_skills:
            continue
        miss_count = max(0, count - recommend_counter.get((executor, skill), 0))
        if miss_count:
            recall_misses.append((f"{executor}/{skill}", miss_count))
recall_miss_count = sum(count for _, count in recall_misses)

print(f"推薦ログ: 直近{len(recommend_entries)}件 / 実行ログ: 直近{len(exec_entries)}件")
if recommended_total:
    print(f"precision率: {precision}% ({hit_total}/{recommended_total})")
    print(f"偽陽性率: {false_positive_rate}% ({false_positive_candidate_count}/{recommended_total})")
else:
    print("precision率: 0% (0/0; 比較対象推薦ログなし)")
    print("偽陽性率: 0% (0/0; 比較対象推薦ログなし)")
if dropped_non_instrumented:
    print(f"比較対象外: 実行ログ未観測agentの推薦{dropped_non_instrumented}件を除外")
if recommended_total >= min_data:
    print(f"recall miss件数: {recall_miss_count}")
else:
    print(f"recall miss件数: N/A (推薦ログ不足: {recommended_total}件 < {min_data}件)")
if recall_misses:
    shown = ", ".join(f"{skill}:{count}" for skill, count in recall_misses[:5])
    print(f"recall miss top: {shown}")
if recommended_total < min_data:
    print(f"計測不足: 推薦ログ{recommended_total}件 < {min_data}件。ALERT抑制")
elif false_positive_rate > 20 or recall_miss_count > 5:
    print("ALERT: Phase 3 cmd起票候補 — 推薦抑制/aliases補完を検討せよ")
    raise SystemExit(2)
PY
