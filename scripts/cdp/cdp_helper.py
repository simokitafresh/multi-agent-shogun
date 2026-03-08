#!/usr/bin/env python3
"""CDP Helper Library — WSL2 → Windows Browser Automation via Chrome DevTools Protocol.

Provides reusable functions for controlling Edge/Chrome from WSL2 through
PowerShell-mediated CDP connections. No external dependencies required.

Usage:
    from cdp_helper import launch_browser, get_tab, js_eval, navigate

Reference: zenn.dev/shio_shoppaize/articles/wsl2-edge-cdp-automation
"""

import base64
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
# 2. cdp_get — CDP REST API call
# ---------------------------------------------------------------------------

def cdp_get(path: str, port: int = 9223) -> object:
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
# 3. cdp_send — WebSocket CDP command via Base64 encoding
# ---------------------------------------------------------------------------

def cdp_send(ws_url: str, method: str, params: dict | None = None,
             timeout: int = 30) -> dict:
    """Send a CDP command over WebSocket using PowerShell + Base64 encoding.

    The Base64 approach avoids the 4-layer quoting problem:
    Python → shell → PowerShell → WebSocket → CDP.

    Args:
        ws_url: WebSocket debugger URL for the target tab.
        method: CDP method name (e.g. ``Runtime.evaluate``).
        params: Optional parameters dict.
        timeout: PowerShell execution timeout in seconds.

    Returns:
        Parsed CDP response dict.
    """
    msg_id = int(time.time() * 1000) % 100000
    payload = json.dumps({
        "id": msg_id,
        "method": method,
        "params": params or {},
    })
    b64_payload = base64.b64encode(payload.encode("utf-8")).decode("ascii")

    ps_script = f"""
$b64 = '{b64_payload}'
$bytes = [System.Convert]::FromBase64String($b64)
$msg = [System.Text.Encoding]::UTF8.GetString($bytes)

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ct = New-Object System.Threading.CancellationToken($false)
$uri = [System.Uri]::new('{ws_url}')
$ws.ConnectAsync($uri, $ct).Wait()

$sendBytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
$sendBuf = New-Object System.ArraySegment[byte] -ArgumentList @(,$sendBytes)
$ws.SendAsync($sendBuf, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

$recvBuf = New-Object byte[] 1048576
$seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$recvBuf)
$result = $ws.ReceiveAsync($seg, $ct).Result
$response = [System.Text.Encoding]::UTF8.GetString($recvBuf, 0, $result.Count)
Write-Output $response

$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, '', $ct).Wait()
"""
    raw = ps_run(ps_script, timeout=timeout)
    return json.loads(raw)


# ---------------------------------------------------------------------------
# 4. js_eval — JavaScript expression evaluation
# ---------------------------------------------------------------------------

def js_eval(ws_url: str, expression: str) -> object:
    """Evaluate a JavaScript expression in the target tab.

    Args:
        ws_url: WebSocket debugger URL for the tab.
        expression: JavaScript expression string.

    Returns:
        The evaluated value (or None if no value).
    """
    result = cdp_send(ws_url, "Runtime.evaluate", {
        "expression": expression,
        "returnByValue": True,
    })
    return result.get("result", {}).get("result", {}).get("value")


# ---------------------------------------------------------------------------
# 5. navigate — URL navigation with wait
# ---------------------------------------------------------------------------

def navigate(ws_url: str, url: str, wait: float = 5.0) -> dict:
    """Navigate the tab to a URL and wait for rendering.

    Args:
        ws_url: WebSocket debugger URL for the tab.
        url: Target URL.
        wait: Seconds to wait after navigation for SPA rendering.

    Returns:
        CDP Page.navigate response.
    """
    result = cdp_send(ws_url, "Page.navigate", {"url": url})
    if wait > 0:
        time.sleep(wait)
    return result


# ---------------------------------------------------------------------------
# 6. detect_browser — Auto-detect Edge/Chrome executable path
# ---------------------------------------------------------------------------

_EDGE_PATHS = [
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
]

_CHROME_PATHS = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
]


def detect_browser(prefer: str = "edge") -> str:
    """Detect the browser executable path on the Windows side.

    Args:
        prefer: ``"edge"`` (default) or ``"chrome"``.

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
# 7. launch_browser — Start browser in debug mode
# ---------------------------------------------------------------------------

def launch_browser(browser: str = "auto", port: int = 9223,
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
        f'"--remote-debugging-address=0.0.0.0"'
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


# ---------------------------------------------------------------------------
# 8. get_tab — Find tab by URL pattern
# ---------------------------------------------------------------------------

def get_tab(url_pattern: str | None = None, port: int = 9223) -> dict | None:
    """Get a tab's info (including webSocketDebuggerUrl) by URL pattern.

    Args:
        url_pattern: Substring to match against tab URLs.
            If None, returns the first available page tab.
        port: CDP debugging port.

    Returns:
        Tab info dict with ``webSocketDebuggerUrl``, or None if not found.
    """
    tabs = cdp_get("/json", port=port)
    for tab in tabs:
        if tab.get("type") != "page":
            continue
        if url_pattern is None:
            return tab
        if url_pattern in tab.get("url", ""):
            return tab
    return None


# ---------------------------------------------------------------------------
# 9. wait_for_element — Wait for DOM element to appear
# ---------------------------------------------------------------------------

def wait_for_element(ws_url: str, selector: str,
                     timeout: float = 10.0) -> bool:
    """Wait until a DOM element matching *selector* exists.

    Args:
        ws_url: WebSocket debugger URL for the tab.
        selector: CSS selector string.
        timeout: Maximum seconds to wait.

    Returns:
        True if element found within timeout, False otherwise.
    """
    deadline = time.time() + timeout
    escaped = selector.replace("'", "\\'")
    while time.time() < deadline:
        result = js_eval(ws_url, f"!!document.querySelector('{escaped}')")
        if result is True:
            return True
        time.sleep(0.5)
    return False


# ---------------------------------------------------------------------------
# 10. screenshot — Page.captureScreenshot
# ---------------------------------------------------------------------------

def screenshot(ws_url: str, path: str) -> str:
    """Capture a screenshot and save to *path*.

    Args:
        ws_url: WebSocket debugger URL for the tab.
        path: Output file path (PNG).

    Returns:
        Absolute path of the saved screenshot.
    """
    result = cdp_send(ws_url, "Page.captureScreenshot", {"format": "png"})
    img_data = base64.b64decode(result.get("result", {}).get("data", ""))
    abs_path = os.path.abspath(path)
    with open(abs_path, "wb") as f:
        f.write(img_data)
    return abs_path


# ---------------------------------------------------------------------------
# 11. get_page_metrics — Performance.getMetrics
# ---------------------------------------------------------------------------

def get_page_metrics(ws_url: str) -> dict:
    """Retrieve performance metrics for the page.

    Args:
        ws_url: WebSocket debugger URL for the tab.

    Returns:
        Dict of metric name → value.
    """
    result = cdp_send(ws_url, "Performance.getMetrics", {})
    metrics = result.get("result", {}).get("metrics", [])
    return {m["name"]: m["value"] for m in metrics}
