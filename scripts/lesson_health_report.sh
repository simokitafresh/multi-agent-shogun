#!/bin/bash
# lesson_health_report.sh - 教訓新陳代謝の効果検証レポート
# Usage: bash scripts/lesson_health_report.sh
# Read-only: lessons.yaml/gate_metricsへの書き込みなし
#   唯一の例外: baselineファイルの初回自動作成

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECTS_YAML="$SCRIPT_DIR/config/projects.yaml"
GATE_METRICS_LOG="$SCRIPT_DIR/logs/gate_metrics.log"
LESSON_TRACKING_TSV="$SCRIPT_DIR/logs/lesson_tracking.tsv"
BASELINE_FILE="$SCRIPT_DIR/queue/lesson_deprecation_baseline.yaml"

export SCRIPT_DIR PROJECTS_YAML GATE_METRICS_LOG LESSON_TRACKING_TSV BASELINE_FILE

python3 << 'PYEOF'
import os
import sys
from datetime import datetime
from pathlib import Path

import yaml

SCRIPT_DIR = os.environ["SCRIPT_DIR"]
PROJECTS_YAML = os.environ["PROJECTS_YAML"]
GATE_METRICS_LOG = os.environ["GATE_METRICS_LOG"]
LESSON_TRACKING_TSV = os.environ["LESSON_TRACKING_TSV"]
BASELINE_FILE = os.environ["BASELINE_FILE"]


def load_projects():
    """config/projects.yamlからactiveプロジェクト一覧を取得"""
    with open(PROJECTS_YAML, encoding="utf-8") as f:
        data = yaml.safe_load(f)
    projects = []
    for p in data.get("projects", []):
        if p.get("status") == "active":
            projects.append(p["id"])
    return projects


def load_lessons(project_id):
    """projects/{id}/lessons.yamlから教訓をロード"""
    path = os.path.join(SCRIPT_DIR, "projects", project_id, "lessons.yaml")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        data = yaml.safe_load(f)
    if not isinstance(data, dict):
        return []
    return data.get("lessons", []) or []


def is_deprecated(lesson):
    """deprecatedかどうかを判定(deprecated: true または status: deprecated)"""
    if not isinstance(lesson, dict):
        return False
    if lesson.get("deprecated") is True:
        return True
    if lesson.get("status") == "deprecated":
        return True
    return False


def iter_reversed_lines(filepath, chunk_size=8192):
    """ファイルを末尾から行単位でイテレート（WSL2 NTFS大ファイル対応）"""
    with open(filepath, "rb") as f:
        f.seek(0, 2)
        remaining = f.tell()
        buf = b""
        while remaining > 0:
            to_read = min(chunk_size, remaining)
            remaining -= to_read
            f.seek(remaining)
            chunk = f.read(to_read)
            buf = chunk + buf
            lines = buf.split(b"\n")
            buf = lines[0]  # 先頭は不完全な行かもしれない
            for line in reversed(lines[1:]):
                if line:
                    yield line.decode("utf-8", errors="replace")
        if buf:
            yield buf.decode("utf-8", errors="replace")


def parse_gate_metrics():
    """gate_metrics.logをパースし、cmd_idごとの最終結果をdedupして返す
    末尾から読み50 cmd_id収集でbreakする（全量scan回避: L511準拠）"""
    if not os.path.exists(GATE_METRICS_LOG):
        return []
    MAX_CMD_IDS = 50
    last_by_cmd = {}
    for line in iter_reversed_lines(GATE_METRICS_LOG):
        line = line.strip()
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        cmd_id = parts[1]
        if cmd_id not in last_by_cmd:
            last_by_cmd[cmd_id] = {
                "timestamp": parts[0],
                "cmd_id": cmd_id,
                "result": parts[2],
            }
            if len(last_by_cmd) >= MAX_CMD_IDS:
                break
    return sorted(last_by_cmd.values(), key=lambda x: x["timestamp"])


def parse_lesson_tracking(target_cmd_ids=None):
    """lesson_tracking.tsvをパースし、cmd_idごとの注入数を返す
    target_cmd_idsが指定された場合、全て揃い次第breakする（全量scan回避: L511準拠）"""
    if not os.path.exists(LESSON_TRACKING_TSV):
        return {}
    cmd_inject_counts = {}
    needed = set(target_cmd_ids) if target_cmd_ids else None
    for line in iter_reversed_lines(LESSON_TRACKING_TSV):
        line = line.strip()
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) < 5:
            continue
        if parts[0] == "timestamp":  # headerに達したらbreak
            break
        cmd_id = parts[1]
        if needed is not None and cmd_id not in needed:
            continue
        if cmd_id not in cmd_inject_counts:
            injected = parts[4]
            count = 0 if (injected == "none" or not injected) else len(injected.split(","))
            # cmd_idごとに末尾側(=最終行)の注入数を採用(dedup)
            cmd_inject_counts[cmd_id] = count
            if needed is not None and needed.issubset(cmd_inject_counts.keys()):
                break
    return cmd_inject_counts


def calc_clear_rate(entries):
    """CLEAR率を算出"""
    if not entries:
        return 0.0
    clear_count = sum(1 for e in entries if e["result"] == "CLEAR")
    return (clear_count / len(entries)) * 100.0


def calc_avg_inject(entries, inject_map):
    """平均注入数を算出"""
    counts = []
    for e in entries:
        if e["cmd_id"] in inject_map:
            counts.append(inject_map[e["cmd_id"]])
    if not counts:
        return 0.0
    return sum(counts) / len(counts)


def load_baseline():
    """baselineファイルをロード(存在しなければNone)"""
    if not os.path.exists(BASELINE_FILE):
        return None
    with open(BASELINE_FILE, encoding="utf-8") as f:
        return yaml.safe_load(f)


def save_baseline(data):
    """baselineファイルを保存"""
    with open(BASELINE_FILE, "w", encoding="utf-8") as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)


def main():
    projects = load_projects()

    # === 教訓集計 ===
    total_active = 0
    total_deprecated = 0
    pj_stats = {}
    for pid in projects:
        lessons = load_lessons(pid)
        active = 0
        deprecated = 0
        for lesson in lessons:
            if is_deprecated(lesson):
                deprecated = deprecated + 1
            else:
                active = active + 1
        pj_stats[pid] = {"active": active, "deprecated": deprecated}
        total_active = total_active + active
        total_deprecated = total_deprecated + deprecated

    total = total_active + total_deprecated
    dep_rate = (total_deprecated / total * 100.0) if total > 0 else 0.0

    # === gate_metrics解析 ===
    gate_entries = parse_gate_metrics()
    target_cmd_ids = {e["cmd_id"] for e in gate_entries}
    inject_map = parse_lesson_tracking(target_cmd_ids=target_cmd_ids)

    # 直近50件の算出（parse_gate_metricsが最大50件返すので冗長条件不要）
    last_50 = gate_entries[-50:]
    clear_rate_last50 = calc_clear_rate(last_50)
    avg_inject_last50 = calc_avg_inject(last_50, inject_map)

    # === レポート出力 ===
    print("=== 教訓新陳代謝レポート ===")
    print(f"総数: {total} (active: {total_active}, deprecated: {total_deprecated})")
    print(f"deprecated率: {dep_rate:.1f}%")
    print()
    print("=== PJ別内訳 ===")
    for pid in projects:
        s = pj_stats[pid]
        print(f"{pid}: active {s['active']}, deprecated {s['deprecated']}")
    print()

    # === baseline管理 + 効果検証 ===
    baseline = load_baseline()

    if baseline is None:
        # baseline未作成 → 現在の状態で自動作成
        baseline_data = {
            "timestamp": datetime.now().replace(microsecond=0).isoformat(),
            "total_lessons": total,
            "deprecated_count": total_deprecated,
            "avg_inject_count": round(avg_inject_last50, 2),
            "clear_rate_last50": round(clear_rate_last50, 1),
            "gate_entries_count": len(gate_entries),
        }
        save_baseline(baseline_data)
        print("=== 効果検証 ===")
        print(f"baseline作成完了 ({BASELINE_FILE})")
        print(f"現在のCLEAR率(直近50cmd): {clear_rate_last50:.1f}%")
        print(f"現在の平均注入数(直近50cmd): {avg_inject_last50:.1f}件/タスク")
        print()
        print("→ 次回実行時にbaseline比較が可能になります")
    else:
        # baseline存在 → 比較出力
        bl_inject = baseline.get("avg_inject_count", 0)
        bl_clear = baseline.get("clear_rate_last50", 0)
        bl_timestamp = baseline.get("timestamp", "unknown")

        inject_diff = avg_inject_last50 - bl_inject
        inject_pct = ((inject_diff / bl_inject) * 100.0) if bl_inject > 0 else 0.0
        clear_diff = clear_rate_last50 - bl_clear

        print("=== 効果検証 ===")
        print(f"baseline: {bl_timestamp}")
        print(f"平均注入数(baseline): {bl_inject:.1f}件/タスク")
        print(f"平均注入数(現在直近50cmd): {avg_inject_last50:.1f}件/タスク  ({inject_pct:+.1f}%)")
        print(f"CLEAR率(baseline): {bl_clear:.1f}%")
        print(f"CLEAR率(現在直近50cmd): {clear_rate_last50:.1f}%  ({clear_diff:+.1f}pp)")
        print()

        # 判定
        if inject_diff < 0 and clear_diff >= -1.0:
            print("→ 注入数減少+CLEAR率維持 = ノイズ削減成功")
        elif inject_diff < 0 and clear_diff < -1.0:
            print("→ 注入数減少だがCLEAR率低下 = 必要な教訓をdeprecateした可能性あり")
        elif inject_diff >= 0 and clear_diff >= 0:
            print("→ 注入数変化なし+CLEAR率維持 = deprecation効果は限定的")
        else:
            print("→ CLEAR率低下 = 要調査")


if __name__ == "__main__":
    main()
PYEOF
