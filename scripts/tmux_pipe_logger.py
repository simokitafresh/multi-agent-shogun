#!/usr/bin/env python3
"""Append tmux pipe-pane output to a timestamped log file."""

from __future__ import annotations

import datetime as dt
import pathlib
import sys


def ts() -> str:
    return dt.datetime.now(dt.timezone.utc).astimezone().isoformat(timespec="milliseconds")


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: tmux_pipe_logger.py <pane_target> <log_file>", file=sys.stderr)
        return 1

    pane_target = sys.argv[1]
    log_file = pathlib.Path(sys.argv[2])
    log_file.parent.mkdir(parents=True, exist_ok=True)

    buffer = ""
    with log_file.open("a", encoding="utf-8") as fh:
        fh.write(f"\n=== trace start {ts()} pane={pane_target} ===\n")
        fh.flush()

        while True:
            chunk = sys.stdin.buffer.read1(4096)
            if not chunk:
                break

            buffer += chunk.decode("utf-8", errors="replace")
            while "\n" in buffer:
                line, buffer = buffer.split("\n", 1)
                fh.write(f"{ts()} {line}\n")
                fh.flush()

        if buffer:
            fh.write(f"{ts()} {buffer}\n")
        fh.write(f"=== trace stop {ts()} pane={pane_target} ===\n")
        fh.flush()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
