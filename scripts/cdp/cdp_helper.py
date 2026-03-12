#!/usr/bin/env python3
"""CDP Helper Library — Browser Launch Utilities for WSL2.

Provides browser detection and launch functions for Chrome/Edge with
CDP remote debugging enabled. For CDP commands (navigate, eval, screenshot,
etc.), use the Daemon mode: cdp_cli.sh / cdp_server.py.

Usage:
    from cdp_helper import launch_browser, detect_browser
"""

import json
import os
import subprocess
import time


# ---------------------------------------------------------------------------
# 1. ps_run — PowerShell execution wrapper
# ---------------------------------------------------------------------------

def ps_run(cmd: str, timeout: int = 30) -> str:
    """Execute a PowerShell command from WSL2 and return stdout as string.

    Args:
        cmd: PowerShell command string.
        timeout: Seconds before TimeoutExpired is raised.

    Returns:
        Stripped stdout text.

    Raises:
        subprocess.TimeoutExpired: Command exceeded *timeout*.
        RuntimeError: PowerShell returned non-zero exit code.
    """
    result = subprocess.run(
        ["powershell.exe", "-NoProfile", "-Command", cmd],
        capture_output=True,
        timeout=timeout,
    )
    stdout = result.stdout.decode("utf-8", errors="replace").strip()
    if result.returncode != 0:
        stderr = result.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(
            f"PowerShell error (rc={result.returncode}): {stderr or stdout}"
        )
    return stdout


# ---------------------------------------------------------------------------
# 2. cdp_get — CDP REST API call (used by _is_cdp_alive)
# ---------------------------------------------------------------------------

def cdp_get(path: str, port: int = 9222) -> object:
    """Call CDP HTTP endpoint (e.g. /json, /json/version).

    Args:
        path: URL path such as ``/json``.
        port: CDP debugging port.

    Returns:
        Parsed JSON (list or dict).
    """
    cmd = (
        f"(Invoke-WebRequest -Uri 'http://localhost:{port}{path}' "
        f"-UseBasicParsing).Content"
    )
    raw = ps_run(cmd)
    return json.loads(raw)


# ---------------------------------------------------------------------------
# 3. detect_browser — Auto-detect Edge/Chrome executable path
# ---------------------------------------------------------------------------

_EDGE_PATHS = [
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
]

_CHROME_PATHS = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
]


def detect_browser(prefer: str = "chrome") -> str:
    """Detect the browser executable path on the Windows side.

    Args:
        prefer: ``"chrome"`` (default) or ``"edge"``.

    Returns:
        Windows-style path to the browser executable.

    Raises:
        FileNotFoundError: No supported browser found.
    """
    if prefer == "chrome":
        search_order = _CHROME_PATHS + _EDGE_PATHS
    else:
        search_order = _EDGE_PATHS + _CHROME_PATHS

    for win_path in search_order:
        wsl_path = _win_to_wsl_path(win_path)
        if os.path.isfile(wsl_path):
            return win_path

    raise FileNotFoundError(
        "No supported browser found. Install Edge or Chrome."
    )


def _win_to_wsl_path(win_path: str) -> str:
    """Convert a Windows path to WSL2 mount path."""
    # C:\Foo\bar.exe → /mnt/c/Foo/bar.exe
    drive_letter = win_path[0].lower()
    rest = win_path[2:].replace("\\", "/")
    return f"/mnt/{drive_letter}{rest}"


# ---------------------------------------------------------------------------
# 4. launch_browser — Start browser in debug mode
# ---------------------------------------------------------------------------

def launch_browser(browser: str = "auto", port: int = 9222,
                   timeout: int = 10) -> bool:
    """Launch browser with remote debugging enabled.

    Checks if CDP is already responding on *port* before launching.
    If a browser is already running without debug mode, it must be
    closed manually first (debug port can only be set at launch time).

    Args:
        browser: ``"auto"`` (detect), ``"edge"``, or ``"chrome"``.
        port: CDP debugging port.
        timeout: Seconds to wait for CDP to become available.

    Returns:
        True if CDP is responding after launch.
    """
    if _is_cdp_alive(port):
        return True

    if browser == "auto":
        exe_path = detect_browser()
    elif browser == "edge":
        exe_path = detect_browser(prefer="edge")
    else:
        exe_path = detect_browser(prefer="chrome")

    ps_cmd = (
        f'Start-Process "{exe_path}" '
        f'-ArgumentList "--remote-debugging-port={port}",'
        f'"--remote-debugging-address=0.0.0.0",'
        f'"--remote-allow-origins=*"'
    )
    ps_run(ps_cmd, timeout=15)

    deadline = time.time() + timeout
    while time.time() < deadline:
        if _is_cdp_alive(port):
            return True
        time.sleep(1)

    return False


def _is_cdp_alive(port: int) -> bool:
    """Check if CDP is responding on the given port."""
    try:
        cdp_get("/json/version", port=port)
        return True
    except Exception:
        return False
