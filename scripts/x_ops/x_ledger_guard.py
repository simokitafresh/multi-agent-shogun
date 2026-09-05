"""live OOS 台帳(queue/x_live_oos/ledger.yaml)の書込み前検証(殿 2026-09-05 19:36)。

全 writer(x_kpi_snapshot / x_growth_tag / x_stage2_approve / x_slot_post)が書込直前に
validate_ledger_text を通し、失敗したら書かない(fail-close)。台帳は append-only の観測記録で、
1 行の連結破損が safe_load 全体を止める(19:36 L275 実証)。
"""
import re

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


def write_ledger_text(path, text: str, expected_entries=None) -> dict:
    """検証してから書く。検証失敗は ValueError を上げ、file は触らない。"""
    doc = validate_ledger_text(text, expected_entries)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    return doc
