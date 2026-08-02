#!/usr/bin/env bats
# test_necessity: Preserve capability non-equivalence and fail-closed deployment
# ancestry at the cdp-session-contract-v1 project-adapter boundary.

@test "DM-Signal auth and deploy adapters enforce contract boundaries" {
  run python3 - <<'PY'
import importlib.util, subprocess

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
print("auth=4/4 deploy=3/3")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"auth=4/4 deploy=3/3"* ]]
}
