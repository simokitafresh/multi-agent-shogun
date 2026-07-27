#!/usr/bin/env python3
"""AC3(cmd_karo_hotfix_retro_prompt_legacy_busy_singleflight_20260727):
旧event別key backlogを現行target+固定本文hashへ移行集約する。

各target内で最古(timestamp最小)の1件を現行content-stable keyのbacklogファイルへ
リネームし、残りは queue/retro/verbatim_reconciled/legacy_backlog_migrated_20260727/
へ移動する(削除しない=durable)。1件も失わないことをledgerで261/261検証する。
30件以下のbatchに分けて実行し、途中失敗しても再実行で冪等(既に移行済みpathはスキップ)。
"""
from __future__ import annotations

import hashlib
import sys
from datetime import datetime, timezone
from pathlib import Path

RETRO_PANE_PROMPT_SHA256 = "b605951bd574d99027a6a1e496aabd5d4e1e67d6d8a4be1b88f4e6472595f84f"
BATCH_SIZE = 30


def current_key(target: str) -> str:
    h = hashlib.sha256()
    h.update(target.encode("utf-8"))
    h.update(b"\0")
    h.update(RETRO_PANE_PROMPT_SHA256.encode("utf-8"))
    return h.hexdigest()


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    backlog_dir = root / "queue" / "retro" / "verbatim_backlog"
    archive_dir = root / "queue" / "retro" / "verbatim_reconciled" / "legacy_backlog_migrated_20260727"
    ledger = root / "logs" / "retro_pane_prompt.tsv"
    archive_dir.mkdir(parents=True, exist_ok=True)

    files = sorted(backlog_dir.glob("*.event"))
    total_seen = len(files)

    groups: dict[str, list[tuple[str, Path]]] = {}
    for f in files:
        lines = f.read_text(encoding="utf-8").splitlines()
        if len(lines) < 5:
            continue
        target = lines[0]
        ts = lines[4]
        groups.setdefault(target, []).append((ts, f))

    # planned entries carry the original filename explicitly so verification can
    # track each of the 261 originals to its real destination, not its old name.
    planned: list[tuple[str, str, Path, Path]] = []  # (action, original_name, src, dst)
    for target, items in groups.items():
        items.sort(key=lambda pair: pair[0])
        dst_current = backlog_dir / f"{current_key(target)}.event"
        # BUGFIX(discovered on live data 2026-07-27): an already-current-key file
        # inside this group must survive as the one visible backlog slot even if
        # it is not the oldest by timestamp. Picking the oldest unconditionally
        # sent live current-key files (shogun/karo/gunshi) to the archive and left
        # zero backlog entries for those targets.
        survivor = next((it for it in items if it[1].resolve() == dst_current.resolve()), items[0])
        for ts, path in items:
            if path.resolve() == survivor[1].resolve():
                if path.resolve() != dst_current.resolve():
                    planned.append(("migrated_to_current_backlog", path.name, path, dst_current))
                else:
                    planned.append(("already_current", path.name, path, path))
            else:
                dst_archive = archive_dir / path.name
                planned.append(("migrated_to_archive", path.name, path, dst_archive))

    destination: dict[str, Path] = {}
    migrated = 0
    skipped = 0
    with ledger.open("a", encoding="utf-8") as lf:
        for i in range(0, len(planned), BATCH_SIZE):
            batch = planned[i : i + BATCH_SIZE]
            for action, original_name, src, dst in batch:
                if action == "already_current":
                    destination[original_name] = dst
                    skipped += 1
                    continue
                if not src.exists():
                    # Idempotent re-run: already migrated in a prior pass. The
                    # destination this original resolved to is dst (or, if dst
                    # is also missing, the fallback archive path from that pass).
                    if dst.exists():
                        destination[original_name] = dst
                    else:
                        fallback = archive_dir / original_name
                        if fallback.exists():
                            destination[original_name] = fallback
                    skipped += 1
                    continue
                if dst.exists() and dst.resolve() != src.resolve():
                    # dst already occupied (idempotent re-run after partial success):
                    # treat src as already superseded, archive it instead of overwriting.
                    fallback = archive_dir / src.name
                    if fallback.exists():
                        destination[original_name] = fallback
                        skipped += 1
                        continue
                    src.rename(fallback)
                    destination[original_name] = fallback
                    lf.write(f"{now_iso()}\tmigrated_to_archive_fallback\t{fallback.name}\t{src.name}\n")
                    migrated += 1
                    continue
                src.rename(dst)
                destination[original_name] = dst
                lf.write(f"{now_iso()}\t{action}\t{dst.name}\t{src.name}\n")
                migrated += 1

    # Verification: every originally-seen event id must resolve to a durable
    # location (current backlog file or archive) — 261/261 accounting.
    accounted = 0
    missing: list[str] = []
    for f in files:
        name = f.name
        dst = destination.get(name)
        if dst is not None and dst.exists():
            accounted += 1
        else:
            missing.append(name)

    print(f"total_seen={total_seen} migrated={migrated} skipped_already_done={skipped}")
    print(f"accounted={accounted}/{total_seen} missing={len(missing)}")
    if missing:
        print("MISSING:" + ",".join(missing[:20]))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
