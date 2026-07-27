#!/usr/bin/env python3
"""Atomic YAML rewrite helper for operational files.

Direct PyYAML dumps are intentionally centralized here so callers get the same
lock-friendly tmpfile behavior and round-trip verification instead of ad hoc
full-file rewrites spread through control-plane scripts.
"""

from __future__ import annotations

import datetime
import inspect
import json
import os
import sys
import tempfile
from typing import Any

import yaml

_CALLER_LOG_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "logs",
    "atomic_yaml_write_callers.jsonl",
)


def _log_caller(path: str) -> None:
    """Append who invoked atomic_yaml_write to logs/ (dynamic capture; static grep misses embedded heredoc callers)."""
    if os.environ.get("ATOMIC_YAML_WRITE_LOG_DISABLE") == "1":
        return
    try:
        frame = inspect.currentframe().f_back.f_back
        caller = f"{frame.f_code.co_filename}:{frame.f_lineno}"
    except Exception:
        caller = "unknown"
    ppid = os.getppid()
    try:
        with open(f"/proc/{ppid}/cmdline", "rb") as f:
            parent_cmdline = f.read(2048).replace(b"\x00", b" ").strip().decode("utf-8", "replace")
    except OSError:
        parent_cmdline = ""
    try:
        record = {
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "write_path": path,
            "caller": caller,
            "argv0": sys.argv[0] if sys.argv else "",
            "pid": os.getpid(),
            "ppid": ppid,
            "parent_cmdline": parent_cmdline,
        }
        with open(_CALLER_LOG_PATH, "a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
    except OSError:
        pass


def _normalize(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(k): _normalize(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_normalize(v) for v in value]
    return value


def atomic_yaml_write(
    path: str,
    data: Any,
    *,
    header: str = "",
    default_flow_style: bool = False,
    allow_unicode: bool = True,
    indent: int = 2,
    sort_keys: bool = False,
    width: int | None = None,
) -> None:
    _log_caller(path)
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=directory, suffix=".tmp")
    kwargs = {
        "default_flow_style": default_flow_style,
        "allow_unicode": allow_unicode,
        "indent": indent,
        "sort_keys": sort_keys,
    }
    if width is not None:
        kwargs["width"] = width

    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            if header:
                f.write(header)
            yaml.dump(data, f, **kwargs)

        with open(tmp_path, encoding="utf-8") as f:
            reloaded = yaml.safe_load(f)
        if _normalize(reloaded) != _normalize(data):
            raise ValueError("YAML round-trip mismatch; original file preserved")

        os.replace(tmp_path, path)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise


def yaml_text(
    data: Any,
    *,
    default_flow_style: bool = False,
    allow_unicode: bool = True,
    sort_keys: bool = False,
    indent: int = 2,
    width: int | None = None,
) -> str:
    kwargs = {
        "default_flow_style": default_flow_style,
        "allow_unicode": allow_unicode,
        "sort_keys": sort_keys,
        "indent": indent,
    }
    if width is not None:
        kwargs["width"] = width
    text = yaml.dump(data, **kwargs)
    reloaded = yaml.safe_load(text)
    if _normalize(reloaded) != _normalize(data):
        raise ValueError("YAML fragment round-trip mismatch")
    return text
