#!/usr/bin/env bats
# test_necessity: Preserve capability non-equivalence and fail-closed deployment
# ancestry, and authenticated non-empty DOM evidence at the
# cdp-session-contract-v1 project-adapter boundary.

@test "DM-Signal auth and deploy adapters enforce contract boundaries" {
  run python3 - <<'PY'
import importlib.util, json, subprocess

path = "scripts/cdp/dm_signal_adapters.py"
spec = importlib.util.spec_from_file_location("adapters", path)
adapters = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapters)
adapters._load_env_value = lambda *_: "fixture-secret"
receipt = {
    "receipt_id": "fixture", "issuer": "cdp_session_foundation",
    "consumer": "inspection", "issued_at": 1, "expires_at": 2,
    "endpoint": "http://127.0.0.1:9222", "chrome_pid": 1,
    "profile_path": "/tmp/fixture", "capabilities": ["transport"],
}
assert adapters.auth_strategy(
    "https://api", "admin", receipt, "fixture",
    admin_auth=lambda *_: (True, "admin ok"),
)["granted_capability"] == "admin"
assert adapters.auth_strategy(
    "https://api", "viewer", receipt, "fixture",
    admin_auth=lambda *_: (False, "401"),
    viewer_auth=lambda *_: (True, "viewer ok"),
)["granted_capability"] == "viewer"

class FixtureWebSocket:
    def __init__(self, rows):
        self.rows = rows
        self.sent = None
        self.closed = False
    def send(self, payload):
        self.sent = json.loads(payload)
    def recv(self):
        expression = self.sent["params"]["expression"]
        assert "document.querySelectorAll('tbody tr').length" in expression
        return json.dumps({
            "id": 1,
            "result": {"result": {"value": {
                "ok": self.rows > 0, "rows": self.rows,
                "reason": f"fixture tbody rows={self.rows}",
            }}},
        })
    def close(self):
        self.closed = True

adapters._page_websocket = lambda *_: "ws://fixture"
for rows, expected_ok in ((2, True), (0, False)):
    fixture_ws = FixtureWebSocket(rows)
    adapters.websocket.create_connection = lambda *_, _ws=fixture_ws, **__: _ws
    ok, evidence = adapters._viewer_auth("https://api", receipt, "fixture-secret")
    assert ok is expected_ok, (rows, ok, evidence)
    assert f"verified_rows={rows}" in evidence
    assert fixture_ws.closed is True
for required, viewer_ok in (("admin", True), ("viewer", False)):
    try:
        adapters.auth_strategy(
            "https://api", required, receipt, "fixture",
            admin_auth=lambda *_: (False, "401"),
            viewer_auth=lambda *_: (viewer_ok, "fixture"),
        )
    except adapters.AdapterError:
        pass
    else:
        raise AssertionError((required, viewer_ok))

class NavigationWebSocket:
    def __init__(self, outcome):
        self.outcome = outcome
        self.sent = []
        self.closed = False
    def send(self, payload):
        self.sent.append(json.loads(payload))
    def recv(self):
        request = self.sent[-1]
        if self.outcome.startswith("transient:"):
            return json.dumps({
                "id": request["id"],
                "error": {"code": -32000, "message": self.outcome.split(":", 1)[1]},
            })
        if self.outcome == "success":
            return json.dumps({
                "id": request["id"],
                "result": {"result": {"value": {"ok": True, "url": "https://api/admin"}}},
            })
        return json.dumps({
            "id": request["id"],
            "result": {"result": {"value": {"ok": False, "reason": "invalid credentials"}}},
        })
    def close(self):
        self.closed = True

original_open = adapters._open_admin_page
original_page_ws = adapters._page_ws
original_create_connection = adapters.websocket.create_connection
try:
    for marker in ("Execution context was destroyed", "Inspected target navigated or closed"):
        events = []
        sockets = [NavigationWebSocket(f"transient:{marker}"), NavigationWebSocket("success")]
        adapters._open_admin_page = lambda *_: (events.append("navigate") or "ws-initial")
        adapters._page_ws = lambda *_: (events.append("reattach") or "ws-latest")
        adapters.websocket.create_connection = lambda url, **_: sockets.pop(0)
        ok, evidence = adapters._admin_ui_auth("https://api/admin", "fixture", receipt)
        assert ok is True and "https://api/admin" in evidence
        assert events == ["navigate", "reattach"], events
        assert not sockets

    events = []
    sockets = [NavigationWebSocket("auth-failure")]
    adapters._open_admin_page = lambda *_: (events.append("navigate") or "ws-initial")
    adapters._page_ws = lambda *_: (events.append("reattach") or "ws-latest")
    adapters.websocket.create_connection = lambda url, **_: sockets.pop(0)
    try:
        adapters._admin_ui_auth("https://api/admin", "fixture", receipt)
    except adapters.AdapterError as exc:
        assert "invalid credentials" in str(exc)
    else:
        raise AssertionError("authentication failure must block")
    assert events == ["navigate"], events

    events = []
    sockets = [NavigationWebSocket("transient:Inspected target navigated or closed")
               for _ in range(adapters.ADMIN_AUTH_NAVIGATION_RETRIES + 1)]
    adapters._open_admin_page = lambda *_: (events.append("navigate") or "ws-initial")
    adapters._page_ws = lambda *_: (events.append("reattach") or "ws-latest")
    adapters.websocket.create_connection = lambda url, **_: sockets.pop(0)
    try:
        adapters._admin_ui_auth("https://api/admin", "fixture", receipt)
    except adapters.AdapterError as exc:
        assert "bounded navigation retries" in str(exc)
    else:
        raise AssertionError("retry exhaustion must block")
    assert events == ["navigate"] + ["reattach"] * adapters.ADMIN_AUTH_NAVIGATION_RETRIES
    assert not sockets
finally:
    adapters._open_admin_page = original_open
    adapters._page_ws = original_page_ws
    adapters.websocket.create_connection = original_create_connection
head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
parent = subprocess.check_output(["git", "rev-parse", "HEAD^"], text=True).strip()
assert adapters.deploy_verifier(parent, head, receipt, ".")["included"] is True
for target, deployed, fetcher in (
    (head, parent, None),
    (head, None, lambda: (_ for _ in ()).throw(adapters.AdapterError("api failed"))),
):
    try:
        adapters.deploy_verifier(target, deployed, receipt, ".", fetcher)
    except adapters.AdapterError:
        pass
    else:
        raise AssertionError((target, deployed))
print("auth=4/4 dom_rows=2/2 deploy=3/3")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"auth=4/4 dom_rows=2/2 deploy=3/3"* ]]
}
