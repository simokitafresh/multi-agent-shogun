"""live OOS 台帳(queue/x_live_oos/ledger.yaml)の書込み前検証(殿 2026-09-05 19:36)。

全 writer(x_kpi_snapshot / x_growth_tag / x_stage2_approve / x_slot_post)が書込直前に
validate_ledger_text を通し、失敗したら書かない(fail-close)。台帳は append-only の観測記録で、
1 行の連結破損が safe_load 全体を止める(19:36 L275 実証)。
"""
import fcntl
import hashlib
import os
import re
import tempfile
from pathlib import Path

import yaml

GLUE_RE = re.compile(r"[^ \t]- draft_id:")


def ensure_trailing_newline(text: str) -> str:
    """append 前の既存 text が改行で終わらないと次 entry が前行に連結される。"""
    return text if (not text or text.endswith("\n")) else text + "\n"


def validate_ledger_text(text: str, expected_entries=None) -> dict:
    """構文と entry 境界を検証し、問題があれば ValueError。戻り値は parse 済み dict。"""
    for lineno, line in enumerate(text.split("\n"), 1):
        if GLUE_RE.search(line):
            raise ValueError(f"entry boundary glued at line {lineno}: {line.strip()[:80]}")
    try:
        doc = yaml.safe_load(text)
    except yaml.YAMLError as exc:
        raise ValueError(f"yaml.safe_load failed: {str(exc).splitlines()[0][:120]}") from exc
    if not isinstance(doc, dict) or not isinstance(doc.get("entries"), list):
        raise ValueError("ledger root must be a mapping with an entries list")
    if expected_entries is not None and len(doc["entries"]) != expected_entries:
        raise ValueError(f"entries count changed: {len(doc['entries'])} != {expected_entries}")
    return doc


def _text_sha256(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def write_ledger_text(path, text: str, expected_entries=None, expected_current_text=None) -> dict:
    """CAS検証後に同一directoryへatomic replaceする。

    各writerはread時のtextをexpected_current_textへ渡す。共有lock取得後の現物が
    異なればstale writerとして書かずに停止し、後勝ち上書きを構造的に防ぐ。
    """
    doc = validate_ledger_text(text, expected_entries)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = Path(str(path) + ".lock")
    with lock_path.open("a+", encoding="utf-8") as lock_handle:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
        current = path.read_text(encoding="utf-8") if path.exists() else ""
        if expected_current_text is not None and current != expected_current_text:
            raise ValueError(
                "stale ledger generation: current_sha=" + _text_sha256(current)
                + " expected_sha=" + _text_sha256(expected_current_text)
            )
        fd, tmp_name = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(text)
                fh.flush()
                os.fsync(fh.fileno())
            os.replace(tmp_name, path)
        finally:
            if os.path.exists(tmp_name):
                os.unlink(tmp_name)
    return doc
