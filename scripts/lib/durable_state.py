#!/usr/bin/env python3
"""Durable state primitives (WAL publish, generation/fence CAS, phase transitions).

Design source: docs/research/hidden-infrastructure-gate-hook-remediation-design-20260730.md
§3.2 (schema), §3.3 (WAL/reconciliation), §5.2 (Foundation).

Every function takes an explicit `root` directory. Nothing here touches
production queue/log/WAL, tmux, ntfy, or the network -- callers must pass an
isolated root for tests/probes.
"""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import sys
import time
from pathlib import Path

SCHEMA_VERSION = "durable_state/v1"

PHASES = ("intended", "prepared", "published", "terminal", "rolled_back")
TERMINAL_PHASES = ("terminal", "rolled_back")
VALID_TRANSITIONS = {
    "intended": ("prepared", "rolled_back"),
    "prepared": ("published", "rolled_back"),
    "published": ("terminal", "rolled_back"),
}
VALID_TERMINAL_RESULTS = ("CLEAR", "BLOCK", "FAILED")

REQUIRED_FIELDS = (
    "schema_version", "subject_type", "subject_id", "generation",
    "fence_token", "phase", "attempt_id", "payload_hash", "artifact_hash",
    "checksum", "idempotency_key", "terminal_result", "side_effect_ledger",
    "recorded_at",
)


class DurableStateError(Exception):
    exit_code = 1


class SchemaQuarantineError(DurableStateError):
    exit_code = 3


class StaleFenceError(DurableStateError):
    exit_code = 4


class InvalidTransitionError(DurableStateError):
    exit_code = 5


def _canonical_bytes(record: dict) -> bytes:
    payload = {k: v for k, v in record.items() if k != "checksum"}
    return json.dumps(payload, sort_keys=True, ensure_ascii=True).encode("utf-8")


def compute_checksum(record: dict) -> str:
    return hashlib.sha256(_canonical_bytes(record)).hexdigest()


def compute_idempotency_key(subject_type, subject_id, generation, action, target, payload_hash) -> str:
    return f"{subject_type}:{subject_id}:{generation}:{action}:{target}:{payload_hash}"


def _subject_dir(root: Path, subject_type: str, subject_id: str) -> Path:
    d = root / "active" / subject_type / subject_id
    d.mkdir(parents=True, exist_ok=True)
    return d


def _quarantine_dir(root: Path) -> Path:
    d = root / "quarantine"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _lock_path(root: Path, subject_type: str, subject_id: str) -> Path:
    d = root / "locks"
    d.mkdir(parents=True, exist_ok=True)
    return d / f"{subject_type}__{subject_id}.lock"


def _record_path(root: Path, subject_type: str, subject_id: str) -> Path:
    return _subject_dir(root, subject_type, subject_id) / "state.json"


def validate_schema(record: dict) -> None:
    missing = [f for f in REQUIRED_FIELDS if f not in record]
    if missing:
        raise SchemaQuarantineError(f"missing fields: {missing}")
    if record["schema_version"] != SCHEMA_VERSION:
        raise SchemaQuarantineError(f"unknown schema_version: {record['schema_version']}")
    expected = compute_checksum(record)
    if record["checksum"] != expected:
        raise SchemaQuarantineError("checksum mismatch")
    if record["recorded_at"] > time.time():
        raise SchemaQuarantineError("future recorded_at")
    if record["phase"] not in PHASES:
        raise SchemaQuarantineError(f"unknown phase: {record['phase']}")
    if record["terminal_result"] not in ("", *VALID_TERMINAL_RESULTS):
        raise SchemaQuarantineError(f"invalid terminal_result: {record['terminal_result']}")


def _atomic_publish(path: Path, record: dict) -> None:
    """file write -> fsync -> atomic rename -> directory fsync (§3.3 step 1-2)."""
    tmp = path.with_name(path.name + f".tmp.{os.getpid()}.{time.time_ns()}")
    with open(tmp, "w") as f:
        f.write(json.dumps(record, sort_keys=True, ensure_ascii=True))
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)
    dir_fd = os.open(str(path.parent), os.O_RDONLY)
    try:
        os.fsync(dir_fd)
    finally:
        os.close(dir_fd)


def read_active(root: Path, subject_type: str, subject_id: str):
    """Return the active record, or None if absent. Corrupt/unknown-schema
    records are quarantined and never returned as active (§3.3 step 3)."""
    path = _record_path(root, subject_type, subject_id)
    if not path.exists():
        return None
    with open(path) as f:
        raw = f.read()
    try:
        record = json.loads(raw)
        validate_schema(record)
    except (json.JSONDecodeError, SchemaQuarantineError) as exc:
        qpath = _quarantine_dir(root) / f"{subject_type}__{subject_id}.{time.time_ns()}.json"
        with open(qpath, "w") as qf:
            qf.write(raw)
        raise SchemaQuarantineError(str(exc)) from exc
    return record


def begin_intended(root: Path, subject_type: str, subject_id: str, attempt_id: str,
                    payload_hash: str, artifact_hash: str = "") -> dict:
    """Open a new generation in phase=intended. generation is a WAL-lock CAS
    increment (§3.3 step 4); fence_token == generation for this primitive."""
    lock_path = _lock_path(root, subject_type, subject_id)
    with open(lock_path, "a+") as lock_f:
        fcntl.flock(lock_f, fcntl.LOCK_EX)
        try:
            current = read_active(root, subject_type, subject_id)
            generation = (current["generation"] + 1) if current else 1
            now = time.time()
            record = {
                "schema_version": SCHEMA_VERSION,
                "subject_type": subject_type,
                "subject_id": subject_id,
                "generation": generation,
                "fence_token": generation,
                "phase": "intended",
                "attempt_id": attempt_id,
                "payload_hash": payload_hash,
                "artifact_hash": artifact_hash,
                "terminal_result": "",
                "side_effect_ledger": [],
                "recorded_at": now,
            }
            record["idempotency_key"] = compute_idempotency_key(
                subject_type, subject_id, generation, "begin", subject_id, payload_hash
            )
            record["checksum"] = compute_checksum(record)
            _atomic_publish(_record_path(root, subject_type, subject_id), record)
            return record
        finally:
            fcntl.flock(lock_f, fcntl.LOCK_UN)


def mutate(root: Path, subject_type: str, subject_id: str, expected_fence: int,
           new_phase: str, terminal_result: str = "", side_effect_ledger=None) -> dict:
    """Transition the active record. Rejects (raises, applies nothing):
    - stale fence (expected_fence != current fence_token)
    - any transition outside intended->prepared->published->(terminal|rolled_back)
    - re-execution against a generation already terminal/rolled_back
    - terminal phase with a terminal_result outside CLEAR/BLOCK/FAILED (incl. "queued")
    """
    lock_path = _lock_path(root, subject_type, subject_id)
    with open(lock_path, "a+") as lock_f:
        fcntl.flock(lock_f, fcntl.LOCK_EX)
        try:
            current = read_active(root, subject_type, subject_id)
            if current is None:
                raise InvalidTransitionError("no active record for subject")
            if current["fence_token"] != expected_fence:
                raise StaleFenceError(
                    f"stale fence: expected={expected_fence} current={current['fence_token']}"
                )
            current_phase = current["phase"]
            if current_phase in TERMINAL_PHASES:
                raise InvalidTransitionError(
                    f"generation {current['generation']} already {current_phase}; "
                    "a new generation is required to retry"
                )
            allowed = VALID_TRANSITIONS.get(current_phase, ())
            if new_phase not in allowed:
                raise InvalidTransitionError(f"{current_phase} -> {new_phase} not allowed")
            if new_phase == "terminal":
                if terminal_result not in VALID_TERMINAL_RESULTS:
                    raise InvalidTransitionError(f"invalid terminal_result: {terminal_result!r}")
            elif terminal_result:
                raise InvalidTransitionError("terminal_result only valid when transitioning to terminal")

            now = time.time()
            record = dict(current)
            record["phase"] = new_phase
            record["terminal_result"] = terminal_result
            if side_effect_ledger is not None:
                record["side_effect_ledger"] = side_effect_ledger
            record["recorded_at"] = now
            record["idempotency_key"] = compute_idempotency_key(
                subject_type, subject_id, record["generation"], new_phase, subject_id, record["payload_hash"]
            )
            record.pop("checksum", None)
            record["checksum"] = compute_checksum(record)
            _atomic_publish(_record_path(root, subject_type, subject_id), record)
            return record
        finally:
            fcntl.flock(lock_f, fcntl.LOCK_UN)


def _print_record(record) -> None:
    if record is None:
        print("null")
    else:
        print(json.dumps(record, sort_keys=True, ensure_ascii=True))


def _cmd_begin(args) -> int:
    record = begin_intended(
        Path(args.root), args.subject_type, args.subject_id,
        args.attempt_id, args.payload_hash, args.artifact_hash,
    )
    _print_record(record)
    return 0


def _cmd_mutate(args) -> int:
    side_effect_ledger = json.loads(args.side_effect_ledger) if args.side_effect_ledger else None
    record = mutate(
        Path(args.root), args.subject_type, args.subject_id,
        expected_fence=args.expected_fence, new_phase=args.phase,
        terminal_result=args.terminal_result, side_effect_ledger=side_effect_ledger,
    )
    _print_record(record)
    return 0


def _cmd_read(args) -> int:
    _print_record(read_active(Path(args.root), args.subject_type, args.subject_id))
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="durable_state")
    sub = parser.add_subparsers(dest="command", required=True)

    p_begin = sub.add_parser("begin")
    p_begin.add_argument("--root", required=True)
    p_begin.add_argument("--subject-type", required=True)
    p_begin.add_argument("--subject-id", required=True)
    p_begin.add_argument("--attempt-id", required=True)
    p_begin.add_argument("--payload-hash", required=True)
    p_begin.add_argument("--artifact-hash", default="")
    p_begin.set_defaults(func=_cmd_begin)

    p_mutate = sub.add_parser("mutate")
    p_mutate.add_argument("--root", required=True)
    p_mutate.add_argument("--subject-type", required=True)
    p_mutate.add_argument("--subject-id", required=True)
    p_mutate.add_argument("--expected-fence", required=True, type=int)
    p_mutate.add_argument("--phase", required=True)
    p_mutate.add_argument("--terminal-result", default="")
    p_mutate.add_argument("--side-effect-ledger", default="")
    p_mutate.set_defaults(func=_cmd_mutate)

    p_read = sub.add_parser("read")
    p_read.add_argument("--root", required=True)
    p_read.add_argument("--subject-type", required=True)
    p_read.add_argument("--subject-id", required=True)
    p_read.set_defaults(func=_cmd_read)

    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except DurableStateError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return exc.exit_code


if __name__ == "__main__":
    sys.exit(main())
