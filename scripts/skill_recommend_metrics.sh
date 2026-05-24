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


recommend_data = load_yaml(recommend_path)
exec_data = load_yaml(exec_path)
recommend_entries = [
    item for item in (recommend_data.get("recommendations") or [])
    if isinstance(item, dict)
][-limit:]

# recall miss計算は推薦開始以降の実行ログのみ対象(推薦前の実行を誤計上しない)
first_recommend_ts = ""
for entry in recommend_entries:
    ts = str(entry.get("ts") or "").strip()
    if ts:
        first_recommend_ts = ts
        break

all_exec = [
    item for item in (exec_data.get("executions") or [])
    if isinstance(item, dict) and str(item.get("used", "true")).lower() != "false"
]
if first_recommend_ts:
    exec_entries = [e for e in all_exec if str(e.get("ts") or "") >= first_recommend_ts][-limit:]
else:
    exec_entries = all_exec[-limit:]

recommended = []
for entry in recommend_entries:
    skills = entry.get("recommended_skills") or []
    if isinstance(skills, str):
        skills = [skills]
    for skill in skills:
        skill_name = str(skill or "").strip()
        if skill_name:
            recommended.append(skill_name)

executed = [
    str(entry.get("skill") or "").strip()
    for entry in exec_entries
    if str(entry.get("skill") or "").strip()
]

recommend_counter = Counter(recommended)
executed_counter = Counter(executed)
recommended_total = sum(recommend_counter.values())
hit_total = sum(min(count, executed_counter.get(skill, 0)) for skill, count in recommend_counter.items())
precision = round((hit_total / recommended_total) * 100) if recommended_total else 0
false_positive_candidate_count = max(0, recommended_total - hit_total)
false_positive_rate = round((false_positive_candidate_count / recommended_total) * 100) if recommended_total else 0
recall_misses = []
for skill, count in sorted(executed_counter.items()):
    miss_count = max(0, count - recommend_counter.get(skill, 0))
    if miss_count:
        recall_misses.append((skill, miss_count))
recall_miss_count = sum(count for _, count in recall_misses)

print(f"推薦ログ: 直近{len(recommend_entries)}件 / 実行ログ: 直近{len(exec_entries)}件")
if recommended_total:
    print(f"precision率: {precision}% ({hit_total}/{recommended_total})")
    print(f"偽陽性率: {false_positive_rate}% ({false_positive_candidate_count}/{recommended_total})")
else:
    print("precision率: N/A (推薦ログなし)")
    print("偽陽性率: N/A (推薦ログなし)")
print(f"recall miss件数: {recall_miss_count}")
if recall_misses:
    shown = ", ".join(f"{skill}:{count}" for skill, count in recall_misses[:5])
    print(f"recall miss top: {shown}")
min_data = 10  # 推薦+実行合計がmin_data未満は計測不足(ALERT抑制)
if recommended_total + len(exec_entries) < min_data:
    print(f"計測不足: データ{recommended_total + len(exec_entries)}件 < {min_data}件。ALERT抑制")
elif false_positive_rate > 20 or recall_miss_count > 5:
    print("ALERT: Phase 3 cmd起票候補 — 推薦抑制/aliases補完を検討せよ")
    raise SystemExit(2)
PY
