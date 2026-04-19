#!/usr/bin/env python3
"""Persistent gate daemon for bats test suite.

Purpose: Eliminate repeated python3 startup cost (~100ms/invocation) for
test_report_template_gate_compat.bats.  A single python3 process handles all
_run_gate() calls via named-FIFO IPC.

Protocol:
  stdin:  <abs_report_path>\n   (one path per request)
  stdout: EXIT:<exit_code>\n
          <gate_output_line_1>\n
          ...
          ---END---\n

Usage (bats setup_file):
  exec {FD_IN}<>"$FIFO_IN"
  exec {FD_OUT}<>"$FIFO_OUT"
  python3 gate_daemon.py <"$FIFO_IN" >"$FIFO_OUT" 2>/dev/null &

Origin: cmd_2110 (kotaro CoDD perf optimization)
"""
from __future__ import annotations

import io
import os
import signal
import sys
from contextlib import redirect_stdout

_dir = os.path.dirname(os.path.abspath(__file__))
if _dir not in sys.path:
    sys.path.insert(0, _dir)

# Pre-load both modules once at daemon startup — eliminates per-test import cost
import gate_report_autofix_main as _autofix  # type: ignore[import]
import gate_report_format_main as _format    # type: ignore[import]

signal.signal(signal.SIGTERM, lambda s, f: sys.exit(0))
signal.signal(signal.SIGPIPE, signal.SIG_DFL)


def _process(path: str) -> tuple[int, str]:
    """Run combined gate logic for one report path.

    Mirrors gate_report_format_combined.py main() logic but accepts path
    as argument instead of sys.argv[1], so it can be called repeatedly
    from the same process.
    """
    # Set sys.argv so both sub-modules can read the path via sys.argv[1]
    sys.argv = [sys.argv[0], path]

    # Phase 1: autofix — capture stdout, surface non-trivial output to stderr
    _buf = io.StringIO()
    with redirect_stdout(_buf):
        try:
            _autofix_exit = _autofix.main()
        except SystemExit as e:
            _autofix_exit = e.code if isinstance(e.code, int) else 1
    _autofix_out = _buf.getvalue().strip()
    if _autofix_out and not _autofix_out.startswith("NO-FIX-NEEDED"):
        print(_autofix_out, file=sys.stderr, flush=True)
    if _autofix_exit != 0:
        print(f"  [WARN] autofix step failed: {_autofix_out}", file=sys.stderr, flush=True)

    # Phase 2: format validation — capture stdout for response
    _buf2 = io.StringIO()
    ec = 0
    with redirect_stdout(_buf2):
        try:
            ec = _format.main()
        except SystemExit as e:
            ec = e.code if isinstance(e.code, int) else 0
    return ec, _buf2.getvalue()


def serve() -> None:
    """Main loop: read paths from stdin, write results to stdout."""
    for raw in sys.stdin:
        path = raw.rstrip("\n")
        if not path:
            continue
        ec, result = _process(path)
        sys.stdout.write(f"EXIT:{ec}\n")
        if result:
            sys.stdout.write(result)
            if not result.endswith("\n"):
                sys.stdout.write("\n")
        sys.stdout.write("---END---\n")
        sys.stdout.flush()


if __name__ == "__main__":
    serve()
