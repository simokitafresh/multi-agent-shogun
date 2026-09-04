#!/usr/bin/env python3
"""承認済み投稿(queue/x_rewrites/R4-*.yaml)へ Growth metadata を付け、live OOS 台帳へ事前 metadata を登録する。

殿指示 2026-09-04 14:51 §15(metadata 拡張)/§20(live OOS: 事前 metadata→投稿→KPI→保存)。
category_defaults(growth_schema.yaml)を既定にし、OVERRIDES で投稿ごとに上書きする。
既存フィールドは触らない(growth: ブロックを追記/更新するだけ)。yaml.dump は使わない(運用 YAML 安全規則)。
Usage: python3 scripts/x_ops/x_growth_tag.py [--dry-run]
"""
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / "skills/x-post-pipeline/growth_schema.yaml"
REWRITES = ROOT / "queue/x_rewrites"
LEDGER = ROOT / "queue/x_live_oos/ledger.yaml"

# 投稿ごとの上書き(本文を読んで判定。2026-09-04 将軍)
OVERRIDES = {
    "R4-A-1": {"audience": "general", "hook_type": "money", "conversation_gap": "high", "topic_level": 1},
    "R4-A-3": {"audience": "general", "hook_type": "math", "conversation_gap": "medium", "topic_level": 2},
    "R4-A-4": {"audience": "general", "hook_type": "money", "conversation_gap": "high", "topic_level": 1},
    "R4-B-1": {"conversation_gap": "medium", "desired_action": ["profile", "follow"]},
    "R4-B-3": {"funnel_stage": "trust", "audience": "investor", "hook_type": "result", "conversation_gap": "low"},
    "R4-B-4": {"conversation_gap": "medium"},
    "R4-C-1": {"funnel_stage": "follow", "conversation_gap": "high", "series_id": "trust_system", "series_order": 1, "series_total": 9},
    "R4-C-2": {"conversation_gap": "medium"},
    "R4-C-4": {"conversation_gap": "medium", "hook_type": "contradiction"},
    "R4-D-1": {"conversation_gap": "medium"},
    "R4-D-3": {"conversation_gap": "medium"},
    "R4-D-5": {"conversation_gap": "medium"},
    "R4-F-3": {"funnel_stage": "trust", "conversation_gap": "low", "link_type": "none"},
}


def render_growth(g):
    lines = ["growth:"]
    for k, v in g.items():
        if isinstance(v, list):
            lines.append(f"  {k}: [{', '.join(v)}]")
        else:
            lines.append(f"  {k}: {v}")
    return "\n".join(lines) + "\n"


def main():
    dry = "--dry-run" in sys.argv
    schema = yaml.safe_load(SCHEMA.read_text(encoding="utf-8"))
    defaults = schema["category_defaults"]
    stages = schema["funnel_stage"]
    entries = []
    for p in sorted(REWRITES.glob("R4-*.yaml")):
        did = p.stem
        cat = did.split("-")[1]
        g = {"content_category": cat, **defaults[cat]}
        g["desired_action"] = list(stages[g["funnel_stage"]]["desired_action"])
        g["conversation_gap"] = "medium"
        g["link_type"] = "none"
        g["external_context"] = "standalone"
        g["format"] = "short"  # v1.2: 承認 13 本は 104〜147 字=全て short
        if g["funnel_stage"] == "convert" or cat == "G":  # v1.3 §48: convert 投稿は作成時に campaign_id を発行(後付け禁止)
            import datetime as _dt
            g["campaign_id"] = g.get("campaign_id") or f"x_{_dt.date.today():%Y%m%d}_{cat}_{did.split('-')[-1].zfill(3)}"
        g.update(OVERRIDES.get(did, {}))
        g["content_lane"] = schema.get("content_lane", {}).get("lane_of_13", {}).get(did, "investing")  # v1.1 3 軸目
        if "funnel_stage" in OVERRIDES.get(did, {}) and "desired_action" not in OVERRIDES[did]:
            g["desired_action"] = list(stages[g["funnel_stage"]]["desired_action"])
        text = p.read_text(encoding="utf-8")
        block = render_growth(g)
        if re.search(r"^growth:\n(?:  .*\n)*", text, re.M):
            text = re.sub(r"^growth:\n(?:  .*\n)*", block, text, count=1, flags=re.M)
        else:
            text = text.rstrip("\n") + "\n" + block
        if not dry:
            p.write_text(text, encoding="utf-8")
        entries.append((did, g))
    # live OOS 台帳(事前 metadata)。既存 entry は保持し、無い draft だけ追加
    LEDGER.parent.mkdir(parents=True, exist_ok=True)
    existing = LEDGER.read_text(encoding="utf-8") if LEDGER.exists() else (
        "meta:\n  purpose: live OOS 台帳(殿指示 2026-09-04 §20)。事前 metadata→投稿→24h/7d KPI→保存。推測値を書かない\n"
        "  snapshot_script: scripts/x_ops/x_kpi_snapshot.py\n  schema: skills/x-post-pipeline/growth_schema.yaml\nentries:\n")
    add = ""
    for did, g in entries:
        if f"draft_id: {did}\n" in existing:
            continue
        add += f"- draft_id: {did}\n  draft_file: queue/x_drafts/2026-09-04_{did}.txt\n  " + render_growth(g).replace("\n", "\n  ").rstrip() + "\n"
        add += "  post_id: ''\n  posted_at: ''\n  snapshots: {}\n"
    if not dry and add:
        LEDGER.write_text(existing + add, encoding="utf-8")
    print(f"tagged={len(entries)} ledger_added={add.count('- draft_id:')} dry={dry}")
    from collections import Counter
    print("stage:", dict(Counter(g["funnel_stage"] for _, g in entries)), "audience:", dict(Counter(g["audience"] for _, g in entries)))


if __name__ == "__main__":
    main()
