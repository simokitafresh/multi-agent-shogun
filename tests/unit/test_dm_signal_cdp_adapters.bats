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
