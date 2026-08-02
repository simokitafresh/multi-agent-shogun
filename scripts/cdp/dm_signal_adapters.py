#!/usr/bin/env python3
"""DM-Signal adapters for the generic CDP session contract.

The module deliberately keeps project credentials and Render semantics outside
the generic transport/session foundation.  Every public adapter either returns
the contract output or raises ``AdapterError``; there is no permissive result.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Callable
from urllib.request import Request, urlopen

import websocket


REQUIRED_RECEIPT_FIELDS = {
    "receipt_id", "issuer", "consumer", "issued_at", "expires_at",
    "endpoint", "chrome_pid", "profile_path", "capabilities",
}
CAPABILITY_RANK = {"viewer": 1, "admin": 2}


class AdapterError(RuntimeError):
    """A fail-closed adapter boundary rejection."""


def _validate_receipt(receipt: dict) -> None:
    if not isinstance(receipt, dict) or not REQUIRED_RECEIPT_FIELDS <= receipt.keys():
        raise AdapterError("missing or invalid CDP session receipt")


def _load_env_value(path: str, key: str) -> str:
    for raw in Path(path).read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        if name.strip() == key:
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            if value:
                return value
    raise AdapterError(f"{key} is missing from the configured environment file")


def _admin_auth(target_url: str, env_file: str, receipt: dict) -> tuple[bool, str]:
    cli = Path("/mnt/c/Python_app/auto-ops/scripts/cdp/cdp_cli.sh")
    if not cli.is_file():
        raise AdapterError("DM-Signal admin authentication helper is unavailable")
    port = str(receipt.get("daemon_cdp_port") or
               str(receipt["endpoint"]).rsplit(":", 1)[-1])
    result = subprocess.run(
        ["bash", str(cli), "auth", "--env", env_file, "--port", port,
         "--api-base-url", target_url],
        text=True, capture_output=True, timeout=30, check=False,
    )
    combined = f"{result.stdout}\n{result.stderr}"
    if result.returncode == 0:
        return True, "admin helper authenticated"
    if "401" in combined or "unauthor" in combined.lower():
        return False, "admin helper reported unauthorized"
    raise AdapterError(f"admin authentication failed (exit={result.returncode})")


def _page_websocket(endpoint: str, target_url: str) -> str:
    with urlopen(f"{endpoint.rstrip('/')}/json/list", timeout=5) as response:
        targets = json.load(response)
    host = target_url.split("//", 1)[-1].split("/", 1)[0]
    pages = [row for row in targets if row.get("type") == "page"]
    for row in pages:
        if host in str(row.get("url", "")) and row.get("webSocketDebuggerUrl"):
            return str(row["webSocketDebuggerUrl"])
    if pages and pages[0].get("webSocketDebuggerUrl"):
        return str(pages[0]["webSocketDebuggerUrl"])
    raise AdapterError("no page target is available for viewer authentication")


def _viewer_auth(target_url: str, receipt: dict, viewer_pass: str) -> tuple[bool, str]:
    ws = websocket.create_connection(
        _page_websocket(str(receipt["endpoint"]), target_url), timeout=15
    )
    script = """
    (async () => {
      const input = document.querySelector('input[type="password"]');
      if (!input) return {ok:false, reason:'viewer password form not found'};
      const setter = Object.getOwnPropertyDescriptor(
        window.HTMLInputElement.prototype, 'value').set;
      setter.call(input, %s);
      input.dispatchEvent(new Event('input', {bubbles:true}));
      input.dispatchEvent(new Event('change', {bubbles:true}));
      const form = input.closest('form');
      if (!form) return {ok:false, reason:'viewer form missing'};
      if (form.requestSubmit) form.requestSubmit(); else form.submit();
      await new Promise(resolve => setTimeout(resolve, 800));
      return {ok: !document.querySelector('input[type="password"]'),
              reason: 'viewer form submitted and checked'};
    })()
    """ % json.dumps(viewer_pass)
    try:
        ws.send(json.dumps({
            "id": 1, "method": "Runtime.evaluate",
            "params": {"expression": script, "awaitPromise": True,
                       "returnByValue": True},
        }))
        while True:
            message = json.loads(ws.recv())
            if message.get("id") == 1:
                value = message.get("result", {}).get("result", {}).get("value", {})
                return bool(value.get("ok")), str(value.get("reason", "viewer authentication failed"))
    finally:
        ws.close()


def auth_strategy(
    target_url: str,
    required_capability: str,
    receipt: dict,
    env_file: str,
    admin_auth: Callable[[str, str, dict], tuple[bool, str]] = _admin_auth,
    viewer_auth: Callable[[str, dict, str], tuple[bool, str]] = _viewer_auth,
) -> dict:
    """Return ``granted_capability/evidence`` or fail closed."""
    _validate_receipt(receipt)
    if required_capability not in CAPABILITY_RANK:
        raise AdapterError(f"unsupported required capability: {required_capability}")
    admin_ok, admin_evidence = admin_auth(target_url, env_file, receipt)
    if admin_ok:
        return {"granted_capability": "admin", "evidence": admin_evidence}
    if required_capability != "viewer":
        raise AdapterError("admin capability is required; viewer is not equivalent")
    viewer_pass = _load_env_value(env_file, "VIEWER_PASS")
    viewer_ok, viewer_evidence = viewer_auth(target_url, receipt, viewer_pass)
    if not viewer_ok:
        raise AdapterError(f"viewer authentication failed: {viewer_evidence}")
    return {"granted_capability": "viewer", "evidence": viewer_evidence}


def _render_revision(service_id: str, api_key: str) -> str:
    request = Request(
        f"https://api.render.com/v1/services/{service_id}/deploys?limit=1",
        headers={"Authorization": f"Bearer {api_key}", "Accept": "application/json"},
    )
    try:
        with urlopen(request, timeout=15) as response:
            payload = json.load(response)
    except Exception as exc:
        raise AdapterError(f"Render API request failed: {type(exc).__name__}") from exc
    rows = payload if isinstance(payload, list) else payload.get("deploys", [])
    deploy = rows[0].get("deploy", rows[0]) if rows else {}
    revision = deploy.get("commit", {}).get("id") or deploy.get("commitId")
    if not revision:
        raise AdapterError("Render API response lacks deployed commit SHA")
    return str(revision)


def deploy_verifier(
    target_commit: str,
    deployed_revision: str | None,
    receipt: dict,
    repo: str,
    revision_fetcher: Callable[[], str] | None = None,
) -> dict:
    """Return ``included/evidence`` only when target is deployed."""
    _validate_receipt(receipt)
    if not deployed_revision:
        if revision_fetcher is None:
            raise AdapterError("deployed revision and Render resolver are both missing")
        deployed_revision = revision_fetcher()
    result = subprocess.run(
        ["git", "-C", repo, "merge-base", "--is-ancestor", target_commit, deployed_revision],
        text=True, capture_output=True, check=False,
    )
    if result.returncode == 0:
        return {"included": True,
                "evidence": f"{target_commit} is an ancestor of {deployed_revision}"}
    if result.returncode == 1:
        raise AdapterError("target commit is not included in the deployed revision")
    raise AdapterError(f"git ancestry verification failed (exit={result.returncode})")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--receipt", required=True)
    sub = parser.add_subparsers(dest="adapter", required=True)
    auth = sub.add_parser("auth-strategy")
    auth.add_argument("--target-url", required=True)
    auth.add_argument("--required-capability", choices=tuple(CAPABILITY_RANK), required=True)
    auth.add_argument("--env-file", required=True)
    deploy = sub.add_parser("deploy-verifier")
    deploy.add_argument("--target-commit", required=True)
    deploy.add_argument("--deployed-revision")
    deploy.add_argument("--repo", required=True)
    deploy.add_argument("--service-id", default=os.environ.get("RENDER_SERVICE_ID"))
    args = parser.parse_args()
    try:
        receipt = json.loads(Path(args.receipt).read_text(encoding="utf-8"))
        if args.adapter == "auth-strategy":
            output = auth_strategy(args.target_url, args.required_capability,
                                   receipt, args.env_file)
        else:
            fetcher = None
            if not args.deployed_revision:
                key, service = os.environ.get("RENDER_API_KEY"), args.service_id
                if not key or not service:
                    raise AdapterError("RENDER_API_KEY and RENDER_SERVICE_ID are required")
                fetcher = lambda: _render_revision(service, key)
            output = deploy_verifier(args.target_commit, args.deployed_revision,
                                     receipt, args.repo, fetcher)
        print(json.dumps(output, sort_keys=True))
        return 0
    except (AdapterError, OSError, ValueError, json.JSONDecodeError) as exc:
        print(json.dumps({"error": str(exc)}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
