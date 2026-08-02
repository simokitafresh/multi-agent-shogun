#!/usr/bin/env python3
"""Establish and clean up an owned Windows CDP transport session.

The receipt is the sole authority for cleanup.  Existing CDP endpoints are
reused and are never terminated; newly launched Chrome uses an isolated
profile and a finite, caller-visible port list.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Callable
from urllib.request import urlopen

import websocket

from cdp_helper import detect_browser, ps_run


ISSUER = "cdp_session_foundation"
DEFAULT_PORTS = (9222, 9223, 9224)
REQUIRED_RECEIPT_FIELDS = {
    "receipt_id", "issuer", "consumer", "issued_at", "expires_at",
    "endpoint", "chrome_pid", "profile_path", "capabilities",
}


class SessionError(RuntimeError):
    pass


def endpoint_alive(port: int, timeout: float = 1.0) -> bool:
    try:
        with urlopen(f"http://127.0.0.1:{port}/json/version", timeout=timeout) as response:
            payload = json.load(response)
        return bool(payload.get("webSocketDebuggerUrl"))
    except Exception:
        return False


def launch_windows_chrome(port: int, profile_path: str) -> int:
    executable = detect_browser("chrome")
    escaped_profile = profile_path.replace("'", "''")
    escaped_executable = executable.replace("'", "''")
    command = (
        f"$p=Start-Process -FilePath '{escaped_executable}' -PassThru "
        f"-ArgumentList '--remote-debugging-port={port}',"
        "'--remote-debugging-address=127.0.0.1','--remote-allow-origins=*',"
        f"'--user-data-dir={escaped_profile}'; $p.Id"
    )
    output = ps_run(command, timeout=15)
    try:
        return int(output.splitlines()[-1])
    except (ValueError, IndexError) as exc:
        raise SessionError("PowerShell launch did not return a Chrome PID") from exc


def wait_alive(port: int, alive: Callable[[int], bool], timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if alive(port):
            return True
        time.sleep(0.2)
    return alive(port)


def establish(
    consumer: str,
    ports: tuple[int, ...] = DEFAULT_PORTS,
    ttl: int = 3600,
    startup_timeout: float = 10,
    alive: Callable[[int], bool] = endpoint_alive,
    launcher: Callable[[int, str], int] = launch_windows_chrome,
    profile_factory: Callable[[int], str] | None = None,
) -> dict:
    if not ports or len(set(ports)) != len(ports):
        raise SessionError("fallback port list must be finite, non-empty, and unique")
    now = int(time.time())
    receipt_id = secrets.token_hex(12)
    for port in ports:
        if alive(port):
            return _receipt(receipt_id, consumer, now, ttl, port, None, "", False)

        profile = (profile_factory or _new_profile)(port)
        pid = launcher(port, profile)
        if wait_alive(port, alive, startup_timeout):
            return _receipt(receipt_id, consumer, now, ttl, port, pid, profile, True)
        # A failed launch is not authority to terminate an unverified process.
        # Preserve its profile for diagnosis and continue through the finite list.
    raise SessionError(f"no qualified CDP endpoint in finite ports: {list(ports)}")


def _new_profile(port: int) -> str:
    root = Path(tempfile.gettempdir()) / "cdp-session-profiles"
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    return tempfile.mkdtemp(prefix=f"p{port}-", dir=root)


def _receipt(receipt_id: str, consumer: str, now: int, ttl: int, port: int,
             pid: int | None, profile: str, owned: bool) -> dict:
    receipt = {
        "receipt_id": receipt_id,
        "issuer": ISSUER,
        "consumer": consumer,
        "issued_at": now,
        "expires_at": now + ttl,
        "endpoint": f"http://127.0.0.1:{port}",
        "chrome_pid": pid,
        "profile_path": profile,
        "capabilities": ["transport"],
        "owned": owned,
        "daemon_cdp_port": port,
    }
    assert REQUIRED_RECEIPT_FIELDS <= receipt.keys()
    return receipt


def cleanup(receipt: dict, session_close: Callable[[str], None] | None = None) -> bool:
    if not REQUIRED_RECEIPT_FIELDS <= receipt.keys() or receipt.get("issuer") != ISSUER:
        raise SessionError("invalid session receipt")
    if not receipt.get("owned"):
        return False
    pid, profile = receipt.get("chrome_pid"), receipt.get("profile_path")
    if not isinstance(pid, int) or not profile:
        raise SessionError("owned receipt lacks cleanup identity")
    profile_path = Path(profile).resolve()
    allowed_root = (Path(tempfile.gettempdir()) / "cdp-session-profiles").resolve()
    if allowed_root not in profile_path.parents:
        raise SessionError("profile is outside the owned cleanup boundary")
    (session_close or _close_owned_session)(receipt["endpoint"])
    if session_close is None:
        port = int(receipt["daemon_cdp_port"])
        deadline = time.monotonic() + 5
        while endpoint_alive(port) and time.monotonic() < deadline:
            time.sleep(0.2)
        if endpoint_alive(port):
            raise SessionError("owned browser did not exit; profile preserved")
    if profile_path.exists():
        shutil.rmtree(profile_path)
    return True


def _close_owned_session(endpoint: str) -> None:
    """Ask the owned browser to close through its protocol (no process signal)."""
    with urlopen(f"{endpoint}/json/version", timeout=2) as response:
        websocket_url = json.load(response).get("webSocketDebuggerUrl")
        if not websocket_url:
            raise SessionError("owned CDP endpoint is no longer qualified")
    connection = websocket.create_connection(websocket_url, timeout=3)
    try:
        connection.send(json.dumps({"id": 1, "method": "Browser.close"}))
        response = json.loads(connection.recv())
        if response.get("id") != 1 or response.get("error"):
            raise SessionError(f"Browser.close rejected: {response}")
    finally:
        connection.close()


def write_receipt(receipt: dict, output: str) -> None:
    path = Path(output)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(json.dumps(receipt, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    start = subparsers.add_parser("establish")
    start.add_argument("--consumer", choices=("inspection", "measurement", "note", "generic"), required=True)
    start.add_argument("--ports", default="9222,9223,9224")
    start.add_argument("--receipt", required=True)
    clean = subparsers.add_parser("cleanup")
    clean.add_argument("--receipt", required=True)
    args = parser.parse_args()
    try:
        if args.command == "establish":
            ports = tuple(int(value) for value in args.ports.split(",") if value)
            receipt = establish(args.consumer, ports=ports)
            write_receipt(receipt, args.receipt)
            print(json.dumps(receipt, sort_keys=True))
        else:
            receipt = json.loads(Path(args.receipt).read_text(encoding="utf-8"))
            print(json.dumps({"cleaned": cleanup(receipt)}))
        return 0
    except (SessionError, ValueError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
