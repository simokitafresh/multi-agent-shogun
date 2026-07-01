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
import re
import sys
from contextlib import redirect_stdout

# Add this file's directory to sys.path so sibling modules are importable
_dir = os.path.dirname(os.path.abspath(__file__))
if _dir not in sys.path:
    sys.path.insert(0, _dir)

import gate_report_autofix_main as _autofix  # type: ignore[import]
import gate_report_format_main as _format  # type: ignore[import]

_ENV_TOKEN_RE = re.compile(r"\b[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+\b")
_ENV_TOKEN_EXCLUDE = {
    "FILL_THIS",
    "PASS_NO_IMPROVEMENT",
    "WITH_CONCERNS",
    "NEEDS_CONTEXT",
}


def _iter_scalar_strings(value: object):
    if isinstance(value, dict):
        for child in value.values():
            yield from _iter_scalar_strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from _iter_scalar_strings(child)
    elif isinstance(value, str):
        yield value


def _report_env_tokens(report_data: dict) -> list[str]:
    found: set[str] = set()
    for text in _iter_scalar_strings(report_data):
        for token in _ENV_TOKEN_RE.findall(text):
            if token not in _ENV_TOKEN_EXCLUDE:
                found.add(token)
    return sorted(found)


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
    _format_exit = _format.main()

    # Phase 3 & 4: report YAML読込み（task_clarity + LU-COMBO共用、1回のみopen）
    _run_p3 = os.environ.get("GATE_CLARITY_WARN_DISABLE", "0") != "1"
    _run_p4 = os.environ.get("GATE_LU_COMBO_WARN_DISABLE", "0") != "1"
    _run_p5 = os.environ.get("GATE_REPORT_ENV_INFO_DISABLE", "0") != "1"
    _rd34: dict = {}
    if _run_p3 or _run_p4 or _run_p5:
        try:
            import yaml as _yaml  # already imported via gate_report_format_main
            with open(report_path, encoding="utf-8") as _f:
                _rd34 = _yaml.safe_load(_f) or {}
        except Exception:
            pass

    # Phase 3: task_clarity check — integrated here to avoid a 2nd python3 subprocess
    # (replaces the inline python3 heredoc in gate_report_format.sh)
    # perf: same process reuses already-loaded yaml module (~0.1s startup saved)
    if _run_p3:
        _tc = _rd34.get("task_clarity") or {}
        _score = str(_tc.get("score", "") or "").strip()
        if not _score:
            print("WARN: task_clarity.score未記入 (0-100で記入せよ)")

    # Phase 4: lesson_candidate.found=true + lessons_useful空リスト組合せWARN (LU-COMBO)
    # 忍者が新教訓を発見(found=true)しながらrelated_lessons注入済み教訓へのフィードバックを
    # 未記入のケースを検出し、記入を構造的に促す（cmd_3561）
    if _run_p4:
        _lc4 = _rd34.get("lesson_candidate") or {}
        _lu4 = _rd34.get("lessons_useful")
        if (isinstance(_lc4, dict)
                and str(_lc4.get("found", "")).strip().lower() == "true"
                and isinstance(_lu4, list)
                and len(_lu4) == 0):
            print(
                "WARN (LU-COMBO): lesson_candidate.found=true かつ lessons_useful空リスト"
                " — related_lessons注入済みの場合はフィードバック必須。"
                "report_field_set.sh経由でuseful/reasonを記入せよ"
            )

    # Phase 5: measurement ENV visibility — non-blocking INFO.
    # GA-154: unusual re-measurement conditions such as DISABLE_CACHE/GIT_TIMEOUT
    # must be visible to reviewers without turning valid reports into BLOCKs.
    if _run_p5:
        _env_tokens = _report_env_tokens(_rd34)
        if _env_tokens:
            print("INFO: report ENV variables detected: " + ", ".join(_env_tokens))

    return _format_exit


if __name__ == "__main__":
    raise SystemExit(main())
