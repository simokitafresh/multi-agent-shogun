"""Tests for atomic_yaml_write caller-instrumentation log.

test_necessity: atomic_yaml_write must append one caller record per call to
logs/atomic_yaml_write_callers.jsonl (with a distinguishable caller site), and
the write's own content/round-trip behavior must remain unchanged by the
instrumentation.
"""
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

import pytest
import yaml

_ROOT = Path(__file__).resolve().parents[2]
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from scripts.lib.yaml_atomic import atomic_yaml_write, _CALLER_LOG_PATH  # noqa: E402


def _read_log_tail(before_size: int) -> list[dict]:
    log_path = Path(_CALLER_LOG_PATH)
    with open(log_path, encoding="utf-8") as f:
        f.seek(before_size)
        return [json.loads(line) for line in f if line.strip()]


def _log_size() -> int:
    log_path = Path(_CALLER_LOG_PATH)
    return log_path.stat().st_size if log_path.exists() else 0


def test_single_call_logs_one_caller_record(tmp_path):
    before = _log_size()
    atomic_yaml_write(str(tmp_path / "a.yaml"), {"x": 1})
    rows = _read_log_tail(before)
    assert len(rows) == 1
    assert rows[0]["write_path"] == str(tmp_path / "a.yaml")
    assert "caller" in rows[0] and rows[0]["caller"] != "unknown"


def test_distinct_callers_are_distinguished(tmp_path):
    def _caller_site_a():
        atomic_yaml_write(str(tmp_path / "a.yaml"), {"x": 1})

    def _caller_site_b():
        atomic_yaml_write(str(tmp_path / "b.yaml"), {"y": 2})

    before = _log_size()
    _caller_site_a()
    _caller_site_b()
    rows = _read_log_tail(before)
    assert len(rows) == 2
    assert rows[0]["caller"] != rows[1]["caller"]


def test_write_content_unchanged_by_instrumentation(tmp_path):
    data = {"a": 1, "b": [1, 2, 3], "c": {"d": "あ"}}
    target = tmp_path / "c.yaml"
    atomic_yaml_write(str(target), data)
    with open(target, encoding="utf-8") as f:
        reloaded = yaml.safe_load(f)
    assert reloaded == data


def test_disable_switch_suppresses_logging(tmp_path, monkeypatch):
    monkeypatch.setenv("ATOMIC_YAML_WRITE_LOG_DISABLE", "1")
    before = _log_size()
    atomic_yaml_write(str(tmp_path / "d.yaml"), {"z": 1})
    rows = _read_log_tail(before)
    assert rows == []


def test_parent_cmdline_is_recorded_for_heredoc_callers(tmp_path):
    """Bare pid/ppid cannot identify a python3 -c/heredoc invoker; parent
    cmdline is the only field that can (LG051-style tracing gap raised by
    gunshi review 2026-07-27)."""
    before = _log_size()
    atomic_yaml_write(str(tmp_path / "e.yaml"), {"w": 1})
    rows = _read_log_tail(before)
    assert len(rows) == 1
    assert "parent_cmdline" in rows[0]
    assert isinstance(rows[0]["parent_cmdline"], str)
    assert rows[0]["parent_cmdline"] != ""
