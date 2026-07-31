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


class LeaseHeldError(DurableStateError):
    exit_code = 6


class OutboxError(DurableStateError):
    exit_code = 7


class InvalidIdentityError(DurableStateError):
    exit_code = 9


class OutcomeUnknownError(OutboxError):
    exit_code = 10


OUTBOX_STATES = ("reserved", "inflight", "applied", "failed")


def _canonical_bytes(record: dict) -> bytes:
    payload = {k: v for k, v in record.items() if k != "checksum"}
    return json.dumps(payload, sort_keys=True, ensure_ascii=True).encode("utf-8")


def compute_checksum(record: dict) -> str:
    return hashlib.sha256(_canonical_bytes(record)).hexdigest()


def compute_idempotency_key(subject_type, subject_id, generation, action, target, payload_hash) -> str:
    return f"{subject_type}:{subject_id}:{generation}:{action}:{target}:{payload_hash}"


def _validate_identity(name: str, label: str) -> None:
    """Typed identity guard for subject_type/subject_id (gunshi containment RC):
    reject anything that is not a single, relative, plain path component --
    empty, absolute, '.'/'..' or containing '..', a path separator, or NUL."""
    if not isinstance(name, str) or not name:
        raise InvalidIdentityError(f"{label} must be a non-empty string")
    if "\x00" in name:
        raise InvalidIdentityError(f"{label} must not contain a NUL byte: {name!r}")
    if name in (".", ".."):
        raise InvalidIdentityError(f"{label} must not be '.' or '..': {name!r}")
    if name.startswith("/") or name.startswith("\\"):
        raise InvalidIdentityError(f"{label} must not be an absolute path: {name!r}")
    if "/" in name or "\\" in name:
        raise InvalidIdentityError(f"{label} must not contain a path separator: {name!r}")
    if ".." in name:
        raise InvalidIdentityError(f"{label} must not contain '..': {name!r}")


def _ensure_contained(root: Path, path: Path) -> Path:
    """realpath containment check (defense in depth, independent of
    _validate_identity): the resolved path must stay under the declared
    root even if it does not yet exist. Resolving realpath walks the whole
    chain, so this also catches a *fixed* state subdirectory (active/locks/
    leases/quarantine/outbox/outbox_locks) itself being a symlink out of
    root, not only a subject-identity injection."""
    root_real = os.path.realpath(str(root))
    path_real = os.path.realpath(str(path))
    if path_real != root_real and not path_real.startswith(root_real + os.sep):
        raise InvalidIdentityError(
            f"resolved path escapes declared root: {path_real!r} not under {root_real!r}"
        )
    return path


def _safe_dir(root: Path, path: Path) -> Path:
    """Common safe-join point (karo containment RC): verify realpath
    containment BEFORE creating any state directory, so a symlink planted
    at any fixed subdirectory cannot redirect subsequent writes outside the
    declared root."""
    _ensure_contained(root, path)
    path.mkdir(parents=True, exist_ok=True)
    return path


def _subject_dir(root: Path, subject_type: str, subject_id: str) -> Path:
    _validate_identity(subject_type, "subject_type")
    _validate_identity(subject_id, "subject_id")
    return _safe_dir(root, root / "active" / subject_type / subject_id)


def _quarantine_dir(root: Path) -> Path:
    return _safe_dir(root, root / "quarantine")


def _lock_path(root: Path, subject_type: str, subject_id: str) -> Path:
    _validate_identity(subject_type, "subject_type")
    _validate_identity(subject_id, "subject_id")
    d = _safe_dir(root, root / "locks")
    p = d / f"{subject_type}__{subject_id}.lock"
    _ensure_contained(root, p)
    return p


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
        _ensure_contained(root, qpath)
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


def _lease_path(root: Path, subject_type: str, subject_id: str) -> Path:
    _validate_identity(subject_type, "subject_type")
    _validate_identity(subject_id, "subject_id")
    d = _safe_dir(root, root / "leases")
    p = d / f"{subject_type}__{subject_id}.json"
    _ensure_contained(root, p)
    return p


def _read_lease(root: Path, subject_type: str, subject_id: str):
    path = _lease_path(root, subject_type, subject_id)
    if not path.exists():
        return None
    with open(path) as f:
        return json.loads(f.read())


def acquire_lease(root: Path, subject_type: str, subject_id: str, owner_id: str,
                   lease_ttl: float = 30.0) -> dict:
    """Grant a time-bounded lease so at most one reconciler mutates a subject
    at a time (safety: executable_owner_count <= 1). An expired lease may be
    reclaimed by any owner (liveness: eventually executable_owner_count == 1).
    """
    lock_path = _lock_path(root, subject_type, subject_id)
    with open(lock_path, "a+") as lock_f:
        fcntl.flock(lock_f, fcntl.LOCK_EX)
        try:
            now = time.time()
            current = _read_lease(root, subject_type, subject_id)
            if current is not None and current["owner_id"] != owner_id and current["expires_at"] > now:
                raise LeaseHeldError(
                    f"lease held by {current['owner_id']} until {current['expires_at']}"
                )
            lease = {
                "subject_type": subject_type,
                "subject_id": subject_id,
                "owner_id": owner_id,
                "acquired_at": now,
                "expires_at": now + lease_ttl,
                "lease_ttl": lease_ttl,
            }
            _atomic_publish(_lease_path(root, subject_type, subject_id), lease)
            return lease
        finally:
            fcntl.flock(lock_f, fcntl.LOCK_UN)


def terminal_receipt(root: Path, subject_type: str, subject_id: str, generation: int):
    """Commit-point read (§3.3 step 7): return the record only when the
    requested generation's terminal receipt, artifact hash, side-effect
    ledger, and current fence all agree. Any gap or mismatch yields None --
    never a false terminal."""
    record = read_active(root, subject_type, subject_id)
    if record is None:
        return None
    if record["generation"] != generation:
        return None
    if record["phase"] != "terminal":
        return None
    if record["fence_token"] != generation:
        return None
    if not record["artifact_hash"]:
        return None
    if record["terminal_result"] not in VALID_TERMINAL_RESULTS:
        return None
    if not isinstance(record["side_effect_ledger"], list):
        return None
    return record


def reconcile(root: Path, subject_type: str, subject_id: str, owner_id: str,
              observed_artifact_hash: str, side_effect_ledger=None,
              lease_ttl: float = 30.0) -> dict:
    """The single lease-holding reconciler drives a subject toward terminal.
    `intended`/`prepared` are left for their owner to resume or cancel
    (untouched here -- reconciler does not invent a decision for them).
    `published` rolls forward to terminal only when observed_artifact_hash
    matches the record's own artifact hash (owner/artifact match); any
    mismatch converges to rolled_back instead.
    """
    acquire_lease(root, subject_type, subject_id, owner_id, lease_ttl)
    current = read_active(root, subject_type, subject_id)
    if current is None:
        raise InvalidTransitionError("no active record to reconcile")
    if current["phase"] in TERMINAL_PHASES:
        return current
    if current["phase"] in ("intended", "prepared"):
        return current
    fence = current["fence_token"]
    if observed_artifact_hash and observed_artifact_hash == current["artifact_hash"]:
        return mutate(root, subject_type, subject_id, fence, "terminal",
                      terminal_result="CLEAR", side_effect_ledger=side_effect_ledger)
    return mutate(root, subject_type, subject_id, fence, "rolled_back",
                  side_effect_ledger=side_effect_ledger)


def _outbox_path(root: Path, idempotency_key: str) -> Path:
    d = _safe_dir(root, root / "outbox")
    digest = hashlib.sha256(idempotency_key.encode("utf-8")).hexdigest()
    p = d / f"{digest}.json"
    _ensure_contained(root, p)
    return p


def _outbox_lock_path(root: Path, idempotency_key: str) -> Path:
    d = _safe_dir(root, root / "outbox_locks")
    digest = hashlib.sha256(idempotency_key.encode("utf-8")).hexdigest()
    p = d / f"{digest}.lock"
    _ensure_contained(root, p)
    return p


def _outbox_read(root: Path, idempotency_key: str):
    path = _outbox_path(root, idempotency_key)
    if not path.exists():
        return None
    with open(path) as f:
        return json.loads(f.read())


def outbox_reserve(root: Path, idempotency_key: str, action: str, target: str,
                    payload_hash: str) -> dict:
    """Persist intent to deliver an external side effect before attempting
    it (§3.4). Reserving twice for the same key is idempotent."""
    lock_path = _outbox_lock_path(root, idempotency_key)
    with open(lock_path, "a+") as lock_f:
        fcntl.flock(lock_f, fcntl.LOCK_EX)
        try:
            existing = _outbox_read(root, idempotency_key)
            if existing is not None:
                return existing
            record = {
                "idempotency_key": idempotency_key,
                "state": "reserved",
                "action": action,
                "target": target,
                "payload_hash": payload_hash,
                "attempts": 0,
                "outcome_unknown": False,
                "recorded_at": time.time(),
            }
            _atomic_publish(_outbox_path(root, idempotency_key), record)
            return record
        finally:
            fcntl.flock(lock_f, fcntl.LOCK_UN)


def outbox_apply_once(root: Path, idempotency_key: str, apply_fn) -> dict:
    """Run `apply_fn` for this key at most once, even across repeated calls
    for the same key (subject+generation+action+target+payload_hash), by
    holding the per-key lock across the reserved->inflight->applied|failed
    transition (§3.4 idempotency collapse).

    `apply_fn` must return a non-empty provider receipt to count as applied
    (gunshi AC4 RC: a falsy/empty return is never treated as success, since
    a provider ack is the only proof the external effect actually landed).
    If `apply_fn` raises, whether the external side effect already fired is
    unknowable from here (e.g. the ack was lost after a real network call
    reached the provider) -- so the record is marked failed with
    outcome_unknown=True and this function refuses to retry it again.
    Only outbox_reconcile() (fed authoritative out-of-band evidence) may
    move a key out of that state; a naive automatic retry is exactly what
    caused a real side effect to fire twice."""
    lock_path = _outbox_lock_path(root, idempotency_key)
    with open(lock_path, "a+") as lock_f:
        fcntl.flock(lock_f, fcntl.LOCK_EX)
        try:
            record = _outbox_read(root, idempotency_key)
            if record is None:
                raise OutboxError(f"no reservation for key {idempotency_key}")
            if record["state"] == "applied":
                return record
            if record.get("outcome_unknown"):
                raise OutcomeUnknownError(
                    f"key {idempotency_key} has an unresolved outcome; "
                    "call outbox_reconcile() with provider evidence before retrying"
                )
            record["state"] = "inflight"
            record["attempts"] = record.get("attempts", 0) + 1
            record["recorded_at"] = time.time()
            _atomic_publish(_outbox_path(root, idempotency_key), record)
            try:
                receipt = apply_fn()
            except Exception as exc:  # noqa: BLE001 -- external side effect boundary
                record["state"] = "failed"
                record["outcome_unknown"] = True
                record["error"] = str(exc)
                record["recorded_at"] = time.time()
                _atomic_publish(_outbox_path(root, idempotency_key), record)
                raise
            if not receipt:
                record["state"] = "failed"
                record["outcome_unknown"] = True
                record["error"] = "apply_fn returned an empty provider receipt"
                record["recorded_at"] = time.time()
                _atomic_publish(_outbox_path(root, idempotency_key), record)
                raise OutcomeUnknownError(
                    f"key {idempotency_key}: apply_fn returned no provider receipt; "
                    "outcome cannot be trusted as applied"
                )
            record["state"] = "applied"
            record["provider_receipt"] = receipt
            record["outcome_unknown"] = False
            record["recorded_at"] = time.time()
            _atomic_publish(_outbox_path(root, idempotency_key), record)
            return record
        finally:
            fcntl.flock(lock_f, fcntl.LOCK_UN)


def outbox_reconcile(root: Path, idempotency_key: str, provider_receipt: str = "",
                      not_executed_proof: str = "") -> dict:
    """Resolve a key stuck in failed+outcome_unknown using authoritative
    out-of-band evidence obtained from the provider -- never an automatic
    retry. Exactly one of `provider_receipt` (proof the effect already
    landed -- collapse to applied, no re-run) or `not_executed_proof`
    (proof the effect never fired -- safe to reopen for a fresh attempt)
    must be supplied."""
    lock_path = _outbox_lock_path(root, idempotency_key)
    with open(lock_path, "a+") as lock_f:
        fcntl.flock(lock_f, fcntl.LOCK_EX)
        try:
            record = _outbox_read(root, idempotency_key)
            if record is None:
                raise OutboxError(f"no reservation for key {idempotency_key}")
            if record["state"] == "applied":
                return record
            if not record.get("outcome_unknown"):
                raise OutboxError(
                    f"key {idempotency_key} is not outcome_unknown; nothing to reconcile"
                )
            if bool(provider_receipt) == bool(not_executed_proof):
                raise OutboxError(
                    "supply exactly one of provider_receipt or not_executed_proof"
                )
            if provider_receipt:
                record["state"] = "applied"
                record["provider_receipt"] = provider_receipt
                record["outcome_unknown"] = False
            else:
                record["state"] = "reserved"
                record["not_executed_proof"] = not_executed_proof
                record["outcome_unknown"] = False
            record["recorded_at"] = time.time()
            _atomic_publish(_outbox_path(root, idempotency_key), record)
            return record
        finally:
            fcntl.flock(lock_f, fcntl.LOCK_UN)


def shadow_compare(root: Path, subject_type: str, subject_id: str) -> dict:
    """Read-only comparator: the canonical reader (schema+checksum validated)
    against a naive reader (plain json.loads, no validation). Used to prove
    the canonical reader diverges from a raw read only in the fail-closed
    direction (never accepts something the naive reader would also reject,
    and any divergence is reported rather than silently swallowed)."""
    path = _record_path(root, subject_type, subject_id)
    naive = None
    naive_error = None
    if path.exists():
        try:
            with open(path) as f:
                naive = json.loads(f.read())
        except json.JSONDecodeError as exc:
            naive_error = str(exc)
    canonical = None
    canonical_error = None
    try:
        canonical = read_active(root, subject_type, subject_id)
    except SchemaQuarantineError as exc:
        canonical_error = str(exc)

    if canonical is not None and naive is not None and canonical == naive:
        return {"result": "match", "canonical": canonical}
    if canonical is None and naive is None and naive_error is None:
        return {"result": "match", "canonical": None}
    return {
        "result": "diverge",
        "canonical": canonical,
        "canonical_error": canonical_error,
        "naive": naive,
        "naive_error": naive_error,
    }


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


def _cmd_lease_acquire(args) -> int:
    lease = acquire_lease(Path(args.root), args.subject_type, args.subject_id,
                          args.owner_id, args.lease_ttl)
    print(json.dumps(lease, sort_keys=True, ensure_ascii=True))
    return 0


def _cmd_reconcile(args) -> int:
    side_effect_ledger = json.loads(args.side_effect_ledger) if args.side_effect_ledger else None
    record = reconcile(
        Path(args.root), args.subject_type, args.subject_id, args.owner_id,
        observed_artifact_hash=args.observed_artifact_hash,
        side_effect_ledger=side_effect_ledger, lease_ttl=args.lease_ttl,
    )
    _print_record(record)
    return 0


def _cmd_terminal_receipt(args) -> int:
    _print_record(terminal_receipt(Path(args.root), args.subject_type, args.subject_id, args.generation))
    return 0


def _cmd_outbox_reserve(args) -> int:
    record = outbox_reserve(Path(args.root), args.idempotency_key, args.action,
                            args.target, args.payload_hash)
    print(json.dumps(record, sort_keys=True, ensure_ascii=True))
    return 0


def _cmd_outbox_apply(args) -> int:
    def apply_fn():
        if args.side_effect_log:
            with open(args.side_effect_log, "a") as f:
                f.write(f"{args.idempotency_key}\n")
        if args.fail_after_effect:
            # Simulate an ack lost after the external effect already fired
            # (e.g. the provider received the call but the response never
            # made it back) -- used to exercise the outcome_unknown path.
            raise RuntimeError("simulated ack loss after external effect fired")
        return "receipt-ok"

    record = outbox_apply_once(Path(args.root), args.idempotency_key, apply_fn)
    print(json.dumps(record, sort_keys=True, ensure_ascii=True))
    return 0


def _cmd_outbox_reconcile(args) -> int:
    record = outbox_reconcile(
        Path(args.root), args.idempotency_key,
        provider_receipt=args.provider_receipt, not_executed_proof=args.not_executed_proof,
    )
    print(json.dumps(record, sort_keys=True, ensure_ascii=True))
    return 0


def _cmd_shadow_compare(args) -> int:
    result = shadow_compare(Path(args.root), args.subject_type, args.subject_id)
    print(json.dumps(result, sort_keys=True, ensure_ascii=True))
    return 0 if result["result"] == "match" else 8


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

    p_lease = sub.add_parser("lease-acquire")
    p_lease.add_argument("--root", required=True)
    p_lease.add_argument("--subject-type", required=True)
    p_lease.add_argument("--subject-id", required=True)
    p_lease.add_argument("--owner-id", required=True)
    p_lease.add_argument("--lease-ttl", type=float, default=30.0)
    p_lease.set_defaults(func=_cmd_lease_acquire)

    p_reconcile = sub.add_parser("reconcile")
    p_reconcile.add_argument("--root", required=True)
    p_reconcile.add_argument("--subject-type", required=True)
    p_reconcile.add_argument("--subject-id", required=True)
    p_reconcile.add_argument("--owner-id", required=True)
    p_reconcile.add_argument("--observed-artifact-hash", default="")
    p_reconcile.add_argument("--side-effect-ledger", default="")
    p_reconcile.add_argument("--lease-ttl", type=float, default=30.0)
    p_reconcile.set_defaults(func=_cmd_reconcile)

    p_terminal = sub.add_parser("terminal-receipt")
    p_terminal.add_argument("--root", required=True)
    p_terminal.add_argument("--subject-type", required=True)
    p_terminal.add_argument("--subject-id", required=True)
    p_terminal.add_argument("--generation", type=int, required=True)
    p_terminal.set_defaults(func=_cmd_terminal_receipt)

    p_outbox_reserve = sub.add_parser("outbox-reserve")
    p_outbox_reserve.add_argument("--root", required=True)
    p_outbox_reserve.add_argument("--idempotency-key", required=True)
    p_outbox_reserve.add_argument("--action", required=True)
    p_outbox_reserve.add_argument("--target", required=True)
    p_outbox_reserve.add_argument("--payload-hash", required=True)
    p_outbox_reserve.set_defaults(func=_cmd_outbox_reserve)

    p_outbox_apply = sub.add_parser("outbox-apply")
    p_outbox_apply.add_argument("--root", required=True)
    p_outbox_apply.add_argument("--idempotency-key", required=True)
    p_outbox_apply.add_argument("--side-effect-log", default="")
    p_outbox_apply.add_argument("--fail-after-effect", action="store_true")
    p_outbox_apply.set_defaults(func=_cmd_outbox_apply)

    p_outbox_reconcile = sub.add_parser("outbox-reconcile")
    p_outbox_reconcile.add_argument("--root", required=True)
    p_outbox_reconcile.add_argument("--idempotency-key", required=True)
    p_outbox_reconcile.add_argument("--provider-receipt", default="")
    p_outbox_reconcile.add_argument("--not-executed-proof", default="")
    p_outbox_reconcile.set_defaults(func=_cmd_outbox_reconcile)

    p_shadow = sub.add_parser("shadow-compare")
    p_shadow.add_argument("--root", required=True)
    p_shadow.add_argument("--subject-type", required=True)
    p_shadow.add_argument("--subject-id", required=True)
    p_shadow.set_defaults(func=_cmd_shadow_compare)

    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except DurableStateError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return exc.exit_code


if __name__ == "__main__":
    sys.exit(main())
