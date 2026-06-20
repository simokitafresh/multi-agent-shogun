#!/usr/bin/env python3
"""Atomic YAML rewrite helper for operational files.

Direct PyYAML dumps are intentionally centralized here so callers get the same
lock-friendly tmpfile behavior and round-trip verification instead of ad hoc
full-file rewrites spread through control-plane scripts.
"""

from __future__ import annotations

import os
import tempfile
from typing import Any

import yaml


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
