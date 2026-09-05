#!/usr/bin/env python3
"""承認在庫と slot_calendar の需要を突合し、7 日以内に空く slot があれば ntfy で知らせる(殿問 2026-09-04 19:12『在庫がない slot は投稿しないんで大丈夫なのか？』)。
fallback は復活させない。空く前に claim_bank から生成して埋める(Short=自動承認、Long/Series=殿承認)ための早期警報。
Usage: python3 scripts/x_ops/x_inventory_check.py [--days 7] [--ntfy]
"""
import collections, datetime as dt, subprocess, sys
from pathlib import Path
import yaml
ROOT = Path(__file__).resolve().parents[2]
def main():
    a = sys.argv[1:]; days = int(a[a.index("--days") + 1]) if "--days" in a else 7
    L = yaml.safe_load((ROOT / "queue/x_live_oos/ledger.yaml").read_text(encoding="utf-8"))["entries"]
    inv = collections.Counter((e.get("growth") or {}).get("format", "?") for e in L if not e.get("post_id") and (e.get("growth") or {}).get("approved"))  # 承認済み(growth.approved 非空)だけを在庫と数える。withdrawn/未承認は在庫ではない(2026-09-05 09:12 修正)
    C = yaml.safe_load((ROOT / "skills/x-post-pipeline/slot_calendar.yaml").read_text(encoding="utf-8"))["slots"]
    today = dt.date.today().isoformat(); horizon = (dt.date.today() + dt.timedelta(days=days)).isoformat()
    left = dict(inv); empty = []; first_empty = {}
    for s in sorted(C, key=lambda x: (x["date"], x["time"])):
        if s["date"] < today: continue
        f = s["format"]
        if left.get(f, 0) > 0: left[f] -= 1
        else:
            first_empty.setdefault(f, f"{s['date']} {s['time']}")
            if s["date"] <= horizon: empty.append(f"{s['date']} {s['time']} {f}")
    print(f"inventory={dict(inv)} first_empty={first_empty} empty_within_{days}d={len(empty)}")
    for e in empty: print("  ", e)
    if empty and "--ntfy" in a:
        subprocess.run(["bash", str(ROOT / "scripts/ntfy.sh"), f"【X 在庫警報】{days} 日以内に空 slot {len(empty)}: {empty[0]}〜。claim_bank から生成して埋めよ(fallback なし)"], cwd=ROOT)
    return 1 if empty else 0
if __name__ == "__main__":
    sys.exit(main())
