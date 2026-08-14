#!/usr/bin/env python3
"""Classify CDP evidence without treating transport as successful work.

The command intentionally has one successful terminal state:
``artifact_complete``.  A foundation receipt proves only that a CDP transport
exists; it does not prove that a page was observed or that the observation was
saved.  ``dom_observed`` is therefore also a non-zero result and callers must
continue until an artifact is available.

Usage::

    python3 scripts/cdp/cdp_evidence_status.py --receipt RECEIPT
    python3 scripts/cdp/cdp_evidence_status.py --receipt RECEIPT \
        --dom-evidence DOM.json --artifact screenshot.png

DOM evidence may be JSON (``{"observed": true, "value": ...}``) or a
non-empty text file.  An artifact is complete only when it is a readable,
regular, non-empty file and DOM evidence is present.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import time
from typing import Any
from urllib.parse import urlparse


ISSUER = "cdp_session_foundation"
CONSUMERS = {"inspection", "measurement", "note", "generic"}
STATES = ("transport_only", "dom_observed", "artifact_complete")
EXIT_CODES = {"transport_only": 10, "dom_observed": 11, "artifact_complete": 0}
REQUIRED_RECEIPT_FIELDS = {
    "receipt_id",
    "issuer",
    "consumer",
    "issued_at",
    "expires_at",
    "endpoint",
    "capabilities",
}


class EvidenceError(ValueError):
    """Raised when the foundation evidence cannot be trusted."""


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise EvidenceError(f"receipt is not readable JSON: {path}") from exc


def _valid_endpoint(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    parsed = urlparse(value)
    return parsed.scheme in {"http", "https"} and bool(parsed.hostname)


def _validate_receipt(path: Path, now: float | None = None) -> dict[str, Any]:
    receipt = _read_json(path)
    if not isinstance(receipt, dict):
        raise EvidenceError("receipt must be a JSON object")
    missing = REQUIRED_RECEIPT_FIELDS - set(receipt)
    if missing:
        raise EvidenceError(f"receipt missing required fields: {', '.join(sorted(missing))}")
    if receipt.get("issuer") != ISSUER:
        raise EvidenceError("receipt issuer is not cdp_session_foundation")
    if receipt.get("consumer") not in CONSUMERS:
        raise EvidenceError("receipt consumer is invalid")
    if not _valid_endpoint(receipt.get("endpoint")):
        raise EvidenceError("receipt endpoint is invalid")
    try:
        issued_at = float(receipt["issued_at"])
        expires_at = float(receipt["expires_at"])
    except (TypeError, ValueError) as exc:
        raise EvidenceError("receipt timestamps must be numeric") from exc
    if not issued_at < expires_at:
        raise EvidenceError("receipt expiry must be after issue time")
    current = time.time() if now is None else now
    if not issued_at <= current < expires_at:
        raise EvidenceError("receipt is expired or not yet valid")
    if not isinstance(receipt.get("capabilities"), (list, tuple, dict)):
        raise EvidenceError("receipt capabilities are missing")
    return receipt


def _dom_value_present(path: Path) -> bool:
    try:
        raw = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise EvidenceError(f"DOM evidence is not readable: {path}") from exc
    if not raw.strip():
        return False
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return True
    if isinstance(payload, dict):
        if payload.get("observed") is False:
            return False
        for key in ("value", "actual", "text", "content", "dom"):
            if key in payload:
                value = payload[key]
                return value is not None and (not isinstance(value, str) or bool(value.strip()))
        return False
    return payload is not None and payload != ""


def _artifact_complete(path: Path) -> bool:
    try:
        if not path.is_file() or path.stat().st_size == 0:
            return False
        with path.open("rb") as handle:
            return bool(handle.read(1))
    except OSError as exc:
        raise EvidenceError(f"artifact is not readable: {path}") from exc


def classify(receipt_path: Path, dom_path: Path | None = None,
             artifact_path: Path | None = None, now: float | None = None) -> str:
    """Return exactly one evidence state for a valid foundation receipt."""

    _validate_receipt(receipt_path, now=now)
    if dom_path is None or not _dom_value_present(dom_path):
        return "transport_only"
    if artifact_path is None or not _artifact_complete(artifact_path):
        return "dom_observed"
    return "artifact_complete"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--dom-evidence", type=Path)
    parser.add_argument("--artifact", type=Path)
    args = parser.parse_args(argv)
    try:
        state = classify(args.receipt, args.dom_evidence, args.artifact)
    except EvidenceError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    print(state)
    return EXIT_CODES[state]


if __name__ == "__main__":
    raise SystemExit(main())
