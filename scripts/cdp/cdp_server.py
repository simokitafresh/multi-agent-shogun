#!/usr/bin/env python3
"""CDP Persistent Daemon Server — WSL2 HTTP server wrapping Chrome DevTools Protocol.

Architecture:
    Claude Code (Bash tool)
      -> HTTP POST localhost:{port} (Bearer token auth)
        -> ThreadingHTTPServer
          -> websocket-client -> Chrome CDP (port 9222)

Endpoints:
    GET  /healthz       - Health check (no auth required)
    POST /cdp/command   - Send raw CDP command
    POST /ax/snapshot   - Get AXTree with ref assignments
    POST /ref/resolve   - Resolve ref to backendDOMNodeId

Features:
    - Bearer token auth (UUID -> /tmp/cdp-server.json)
    - 30-minute idle auto-shutdown
    - WebSocket failure -> os._exit(1) for fast crash recovery
    - ref-based element selection (e1, e2, ... for interactive elements)
    - Page navigation invalidates refs automatically (URL guard)
"""

import argparse
import json
import os
import signal
import sys
import threading
import time
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn

try:
    import websocket
except ImportError:
    print(
        "ERROR: websocket-client required. pip install websocket-client",
        file=sys.stderr,
    )
    sys.exit(1)


# ---------------------------------------------------------------------------
# Interactive ARIA roles for ref assignment
# ---------------------------------------------------------------------------
INTERACTIVE_ROLES = frozenset(
    {
        "button",
        "link",
        "textbox",
        "checkbox",
        "radio",
        "combobox",
        "listbox",
        "menuitem",
        "tab",
        "switch",
        "slider",
        "spinbutton",
        "searchbox",
        "option",
        "menuitemcheckbox",
        "menuitemradio",
        "treeitem",
    }
)


# ---------------------------------------------------------------------------
# DaemonState — shared state with RLock
# ---------------------------------------------------------------------------
class DaemonState:
    """Thread-safe shared state for the CDP daemon."""

    def __init__(self, token: str, cdp_port: int, idle_timeout: int):
        self.lock = threading.RLock()
        self.token = token
        self.cdp_port = cdp_port
        self.idle_timeout = idle_timeout
        self.last_activity = time.time()
        self.ws: websocket.WebSocket | None = None
        self.ws_url: str | None = None
        self.msg_id = 0
        # ref system
        self.ref_map: dict[str, dict] = {}
        self.ref_generation = 0
        self.ref_url: str | None = None

    def touch(self):
        """Update last activity timestamp."""
        with self.lock:
            self.last_activity = time.time()

    def is_idle(self) -> bool:
        with self.lock:
            return (time.time() - self.last_activity) > self.idle_timeout

    def next_msg_id(self) -> int:
        with self.lock:
            self.msg_id += 1
            return self.msg_id

    def clear_refs(self):
        with self.lock:
            self.ref_map.clear()
            self.ref_generation += 1
            self.ref_url = None


# ---------------------------------------------------------------------------
# CDP WebSocket connection management
# ---------------------------------------------------------------------------
def _get_ws_url(cdp_port: int) -> str:
    """Get WebSocket URL from Chrome's /json endpoint."""
    url = f"http://localhost:{cdp_port}/json"
    with urllib.request.urlopen(url, timeout=5) as resp:
        tabs = json.loads(resp.read().decode())
    for tab in tabs:
        if tab.get("type") == "page" and "webSocketDebuggerUrl" in tab:
            return tab["webSocketDebuggerUrl"]
    raise RuntimeError("No page tab with webSocketDebuggerUrl found")


def ensure_ws(state: DaemonState) -> websocket.WebSocket:
    """Ensure WebSocket connection is alive, reconnect if needed.

    On failure: os._exit(1) — fast crash for external restart.
    """
    with state.lock:
        if state.ws is not None:
            try:
                if state.ws.connected:
                    return state.ws
            except Exception:
                pass
            # Connection dead, clean up
            try:
                state.ws.close()
            except Exception:
                pass
            state.ws = None
            state.ws_url = None

        # (Re)connect
        try:
            ws_url = _get_ws_url(state.cdp_port)
            ws = websocket.create_connection(ws_url, timeout=10)
            state.ws = ws
            state.ws_url = ws_url
            return ws
        except Exception as e:
            print(
                f"FATAL: Cannot connect to Chrome CDP on port {state.cdp_port}: {e}",
                file=sys.stderr,
            )
            os._exit(1)


def cdp_command(state: DaemonState, method: str, params: dict | None = None) -> dict:
    """Send a CDP command and return the result.

    On WebSocket failure: os._exit(1).
    """
    ws = ensure_ws(state)
    msg_id = state.next_msg_id()
    payload = json.dumps(
        {"id": msg_id, "method": method, "params": params or {}}
    )
    try:
        ws.send(payload)
        deadline = time.time() + 30
        while time.time() < deadline:
            raw = ws.recv()
            if not raw:
                raise ConnectionError("Empty response from WebSocket")
            resp = json.loads(raw)
            if resp.get("id") == msg_id:
                if "error" in resp:
                    return {"error": resp["error"]}
                return resp.get("result", {})
            # Skip CDP events (no "id" field), keep reading
        return {"error": {"message": "Timeout waiting for CDP response"}}
    except Exception as e:
        print(f"FATAL: WebSocket error during CDP command: {e}", file=sys.stderr)
        with state.lock:
            state.ws = None
            state.ws_url = None
        os._exit(1)


# ---------------------------------------------------------------------------
# AXTree -> ref mapping
# ---------------------------------------------------------------------------
def build_ax_refs(
    state: DaemonState, interactive_only: bool = True
) -> list[dict]:
    """Build AXTree snapshot with ref assignments (DFS order).

    Returns list of {ref, role, name, backendDOMNodeId} for elements.
    """
    result = cdp_command(state, "Accessibility.getFullAXTree")
    if "error" in result:
        return []
    nodes = result.get("nodes", [])
    if not nodes:
        return []

    # Get current URL for ref guard
    url_result = cdp_command(
        state,
        "Runtime.evaluate",
        {"expression": "window.location.href", "returnByValue": True},
    )
    current_url = url_result.get("result", {}).get("value", "")

    with state.lock:
        state.ref_map.clear()
        state.ref_generation += 1
        state.ref_url = current_url

        ref_counter = 0
        snapshot_items = []

        # AXTree nodes from CDP are in document (DFS) order
        for node in nodes:
            if node.get("ignored", False):
                continue

            role_obj = node.get("role", {})
            role = (
                role_obj.get("value", "")
                if isinstance(role_obj, dict)
                else str(role_obj)
            )

            name_obj = node.get("name", {})
            name = (
                name_obj.get("value", "")
                if isinstance(name_obj, dict)
                else str(name_obj)
            )

            backend_node_id = node.get("backendDOMNodeId")

            if interactive_only and role not in INTERACTIVE_ROLES:
                continue

            ref_counter += 1
            ref = f"e{ref_counter}"

            entry = {
                "ref": ref,
                "role": role,
                "name": name,
                "backendDOMNodeId": backend_node_id,
            }
            state.ref_map[ref] = entry
            snapshot_items.append(entry)

        return snapshot_items


def resolve_ref(state: DaemonState, ref: str) -> dict | None:
    """Resolve a ref to its element info with URL guard.

    Returns None if ref not found or page has navigated since snapshot.
    """
    with state.lock:
        if ref not in state.ref_map:
            return None
        entry = state.ref_map[ref].copy()
        snapshot_url = state.ref_url

    # URL guard: check if page has navigated since snapshot
    url_result = cdp_command(
        state,
        "Runtime.evaluate",
        {"expression": "window.location.href", "returnByValue": True},
    )
    current_url = url_result.get("result", {}).get("value", "")

    if current_url != snapshot_url:
        state.clear_refs()
        return None

    return entry


def ref_action(
    state: DaemonState, backend_node_id: int, action: str, body: dict
) -> dict:
    """Perform an action on an element identified by backendDOMNodeId."""
    # Resolve backendDOMNodeId -> objectId
    resolve_result = cdp_command(
        state, "DOM.resolveNode", {"backendNodeId": backend_node_id}
    )
    if "error" in resolve_result:
        return {"ok": False, "error": resolve_result["error"]}
    object_id = resolve_result.get("object", {}).get("objectId")
    if not object_id:
        return {"ok": False, "error": "Could not resolve node to object"}

    if action == "click":
        # Scroll into view then click
        cdp_command(
            state,
            "Runtime.callFunctionOn",
            {
                "objectId": object_id,
                "functionDeclaration": "function() { this.scrollIntoView({block:'center'}); this.click(); }",
                "returnByValue": True,
            },
        )
        return {"ok": True, "action": "click"}

    elif action == "type":
        text = body.get("text", "")
        text_json = json.dumps(text)
        cdp_command(
            state,
            "Runtime.callFunctionOn",
            {
                "objectId": object_id,
                "functionDeclaration": f"""function() {{
                    this.focus();
                    var proto = Object.getPrototypeOf(this);
                    var desc = Object.getOwnPropertyDescriptor(proto, 'value')
                        || Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')
                        || Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value');
                    if (desc && desc.set) {{
                        desc.set.call(this, {text_json});
                    }} else {{
                        this.value = {text_json};
                    }}
                    this.dispatchEvent(new Event('input', {{bubbles: true}}));
                    this.dispatchEvent(new Event('change', {{bubbles: true}}));
                }}""",
                "returnByValue": True,
            },
        )
        return {"ok": True, "action": "type"}

    elif action == "get_text":
        result = cdp_command(
            state,
            "Runtime.callFunctionOn",
            {
                "objectId": object_id,
                "functionDeclaration": "function() { return (this.innerText || this.textContent || this.value || '').trim(); }",
                "returnByValue": True,
            },
        )
        text = result.get("result", {}).get("value", "")
        return {"ok": True, "action": "get_text", "text": text}

    else:
        return {"ok": False, "error": f"Unknown action: {action}"}


# ---------------------------------------------------------------------------
# HTTP Handler
# ---------------------------------------------------------------------------
class CDPHandler(BaseHTTPRequestHandler):
    """HTTP request handler for CDP daemon."""

    server: "CDPDaemonServer"

    def log_message(self, format, *args):
        """Suppress default request logging."""
        pass

    def _state(self) -> DaemonState:
        return self.server.state

    def _check_auth(self) -> bool:
        """Verify Bearer token. Returns True if authorized."""
        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            self._send_json(401, {"error": "Missing Bearer token"})
            return False
        token = auth[7:]
        if token != self._state().token:
            self._send_json(401, {"error": "Invalid token"})
            return False
        self._state().touch()
        return True

    def _send_json(self, status: int, data: dict):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self) -> dict:
        length = int(self.headers.get("Content-Length", 0))
        if length == 0:
            return {}
        raw = self.rfile.read(length)
        return json.loads(raw.decode("utf-8"))

    # -- GET ----------------------------------------------------------------

    def do_GET(self):
        if self.path == "/healthz":
            self._state().touch()
            with self._state().lock:
                ref_gen = self._state().ref_generation
                ref_count = len(self._state().ref_map)
            self._send_json(
                200,
                {
                    "status": "ok",
                    "cdp_port": self._state().cdp_port,
                    "ref_generation": ref_gen,
                    "ref_count": ref_count,
                    "uptime_seconds": int(
                        time.time() - self.server.start_time
                    ),
                },
            )
            return
        self._send_json(404, {"error": "Not found"})

    # -- POST ---------------------------------------------------------------

    def do_POST(self):
        if not self._check_auth():
            return

        if self.path == "/cdp/command":
            self._handle_cdp_command()
        elif self.path == "/ax/snapshot":
            self._handle_ax_snapshot()
        elif self.path == "/ref/resolve":
            self._handle_ref_resolve()
        elif self.path == "/ref/action":
            self._handle_ref_action()
        else:
            self._send_json(404, {"error": "Not found"})

    def _handle_cdp_command(self):
        body = self._read_body()
        method = body.get("method")
        params = body.get("params", {})
        if not method:
            self._send_json(400, {"error": "Missing 'method' field"})
            return
        result = cdp_command(self._state(), method, params)
        self._send_json(200, {"result": result})

    def _handle_ax_snapshot(self):
        body = self._read_body()
        interactive_only = body.get("interactive_only", True)
        items = build_ax_refs(self._state(), interactive_only=interactive_only)
        with self._state().lock:
            gen = self._state().ref_generation
            url = self._state().ref_url
        self._send_json(
            200,
            {
                "ref_generation": gen,
                "url": url,
                "elements": items,
                "count": len(items),
            },
        )

    def _handle_ref_resolve(self):
        body = self._read_body()
        ref = body.get("ref")
        if not ref:
            self._send_json(400, {"error": "Missing 'ref' field"})
            return
        entry = resolve_ref(self._state(), ref)
        if entry is None:
            self._send_json(
                404,
                {
                    "error": f"Ref '{ref}' not found or stale (page navigated)"
                },
            )
            return
        self._send_json(200, {"element": entry})

    def _handle_ref_action(self):
        body = self._read_body()
        ref = body.get("ref")
        action = body.get("action")
        if not ref or not action:
            self._send_json(400, {"error": "Missing 'ref' or 'action' field"})
            return

        entry = resolve_ref(self._state(), ref)
        if entry is None:
            self._send_json(
                404,
                {"error": f"Ref '{ref}' not found or stale (page navigated)"},
            )
            return

        backend_node_id = entry.get("backendDOMNodeId")
        if not backend_node_id:
            self._send_json(400, {"error": f"Ref '{ref}' has no backendDOMNodeId"})
            return

        result = ref_action(self._state(), backend_node_id, action, body)
        self._send_json(200, result)


# ---------------------------------------------------------------------------
# Threaded HTTP Server
# ---------------------------------------------------------------------------
class CDPDaemonServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True

    def __init__(self, address, handler_class, state: DaemonState):
        self.state = state
        self.start_time = time.time()
        super().__init__(address, handler_class)


# ---------------------------------------------------------------------------
# Idle watchdog
# ---------------------------------------------------------------------------
def idle_watchdog(state: DaemonState, server: CDPDaemonServer):
    """Background thread: exit if idle for configured timeout."""
    while True:
        time.sleep(60)
        if state.is_idle():
            elapsed = int(time.time() - state.last_activity)
            print(
                f"Idle for {elapsed}s (limit {state.idle_timeout}s), shutting down.",
                file=sys.stderr,
            )
            server.shutdown()
            os._exit(0)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="CDP Persistent Daemon Server"
    )
    parser.add_argument(
        "--port",
        type=int,
        default=9400,
        help="HTTP server port (default: 9400)",
    )
    parser.add_argument(
        "--cdp-port",
        type=int,
        default=9222,
        help="Chrome CDP port (default: 9222)",
    )
    parser.add_argument(
        "--idle-timeout",
        type=int,
        default=1800,
        help="Idle timeout in seconds (default: 1800 = 30min)",
    )
    args = parser.parse_args()

    # Generate Bearer token
    token = str(uuid.uuid4())
    cred_path = "/tmp/cdp-server.json"
    cred_data = {
        "token": token,
        "port": args.port,
        "cdp_port": args.cdp_port,
        "pid": os.getpid(),
    }
    with open(cred_path, "w") as f:
        json.dump(cred_data, f)
    os.chmod(cred_path, 0o600)

    # Create state
    state = DaemonState(
        token=token, cdp_port=args.cdp_port, idle_timeout=args.idle_timeout
    )

    # Verify CDP connection at startup
    ensure_ws(state)
    print(
        f"Connected to Chrome CDP on port {args.cdp_port}", file=sys.stderr
    )

    # Start HTTP server
    server = CDPDaemonServer(
        ("127.0.0.1", args.port), CDPHandler, state
    )

    # Start idle watchdog
    watchdog = threading.Thread(
        target=idle_watchdog, args=(state, server), daemon=True
    )
    watchdog.start()

    # Handle SIGTERM gracefully
    def sigterm_handler(signum, frame):
        print("SIGTERM received, shutting down.", file=sys.stderr)
        server.shutdown()
        sys.exit(0)

    signal.signal(signal.SIGTERM, sigterm_handler)

    print(
        f"CDP daemon listening on 127.0.0.1:{args.port}", file=sys.stderr
    )
    print(f"Credentials: {cred_path}", file=sys.stderr)
    print(f"Token: {token}", file=sys.stderr)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Interrupted, shutting down.", file=sys.stderr)
        server.shutdown()


if __name__ == "__main__":
    main()
