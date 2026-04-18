#!/usr/bin/env python3
"""autofix + format validation in single python3 process.

cmd_2063: gate_report_format.sh 高速化
- 旧: bash gate_report_autofix.sh (→ python3 autofix_main.py) + python3 format_main.py = 2プロセス
- 新: python3 gate_report_format_combined.py (autofix_main + format_main を1プロセスで実行)
- 節約: python3インタープリタ起動コスト1回分 (~64ms on /mnt/c)
"""
from __future__ import annotations

import io
import os
import sys
from contextlib import redirect_stdout

# Add this file's directory to sys.path so sibling modules are importable
_dir = os.path.dirname(os.path.abspath(__file__))
if _dir not in sys.path:
    sys.path.insert(0, _dir)

import gate_report_autofix_main as _autofix  # type: ignore[import]
import gate_report_format_main as _format  # type: ignore[import]


def main() -> int:
    report_path = sys.argv[1] if len(sys.argv) > 1 else ""

    # Phase 1: autofix — capture stdout, print non-trivial results to stderr
    _buf = io.StringIO()
    with redirect_stdout(_buf):
        _autofix_exit = _autofix.main()
    _autofix_out = _buf.getvalue().strip()

    if _autofix_out and not _autofix_out.startswith("NO-FIX-NEEDED"):
        # AUTO-FIXED or UNFIXABLE — surface to bash caller via stderr
        print(_autofix_out, file=sys.stderr)

    if _autofix_exit != 0:
        # UNFIXABLE: log warning but proceed with validation anyway
        # (gate_report_format.sh will detect FAIL from format validation)
        print(f"  [WARN] autofix step failed: {_autofix_out}", file=sys.stderr)

    # Phase 2: format validation — normal stdout (PASS / FAIL: ...)
    return _format.main()


if __name__ == "__main__":
    raise SystemExit(main())
