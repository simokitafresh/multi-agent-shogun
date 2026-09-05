#!/usr/bin/env python3
"""Stage 2 本文承認(殿 19:28 §25)。殿の『Stage 2 承認』を受けて .approved を置き、台帳 growth.approved を埋める。除外 id を --except で指定可。
Usage: python3 scripts/x_ops/x_stage2_approve.py --plan skills/x-post-pipeline/plan_202609.yaml [--only P9-S-1,P9-L-2] [--except P9-S-3] [--dry-run]
"""
import sys, re, glob, datetime as dt
from pathlib import Path
import yaml
ROOT = Path(__file__).resolve().parents[2]


def main():
    a = sys.argv[1:]; dry = "--dry-run" in a
    plan = yaml.safe_load(Path(a[a.index("--plan") + 1]).read_text(encoding="utf-8"))
    only = set(a[a.index("--only") + 1].split(",")) if "--only" in a else None
    exc = set(a[a.index("--except") + 1].split(",")) if "--except" in a else set()
    ids = [p["draft_id"] for p in plan["plan"] if p["status"] == "scheduled" and (not only or p["draft_id"] in only) and p["draft_id"] not in exc]
    led = ROOT / "queue/x_live_oos/ledger.yaml"; s = led.read_text(encoding="utf-8"); original = s; stamp = f"lord_stage2_{dt.datetime.now():%Y%m%d_%H%M}"
    n = 0
    for did in ids:
        files = glob.glob(str(ROOT / f"queue/x_drafts/*_{did}.txt")) + glob.glob(str(ROOT / f"queue/x_drafts/*_{did}-P.txt")) + glob.glob(str(ROOT / f"queue/x_drafts/*_{did}-R*.txt"))
        if not files: print("no draft", did); continue
        for f in files:
            if not dry: Path(f[:-4] + ".approved").write_text(stamp + "\n")
        # 台帳: この draft_id(と thread の -P/-R*)の approved: '' を埋める
        for sub in [Path(f).stem.split("_", 1)[1] for f in files]:
            s, k = re.subn(rf"(- draft_id: {re.escape(sub)}\n(?:(?!- draft_id:).*\n)*?    approved: )''", rf"\g<1>{stamp}", s)
        n += 1
    if not dry:
        # 殿 2026-09-05: 検証→書込の順(旧: 書込→safe_load は壊れた台帳を publish してから気づく)
        import sys as _sys
        from pathlib import Path as _P
        _sys.path.insert(0, str(_P(__file__).resolve().parent))
        from x_ledger_guard import write_ledger_text
        try:
            write_ledger_text(led, s, expected_entries=original.count("- draft_id:"), expected_current_text=original)
        except ValueError as exc:
            print(f"x_stage2_approve: BLOCK ledger not written: {exc}", file=_sys.stderr)
            raise SystemExit(3)
        Path(a[a.index("--plan") + 1]).write_text(Path(a[a.index("--plan") + 1]).read_text(encoding="utf-8").replace("    stage2_copy: pending", f"    stage2_copy: approved({stamp}, {n} units{', except ' + ','.join(sorted(exc)) if exc else ''})", 1), encoding="utf-8")
    print(f"{'dry ' if dry else ''}approved {n} units; except={sorted(exc)}")


if __name__ == "__main__":
    main()
