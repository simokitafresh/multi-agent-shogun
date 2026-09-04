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
import time
from typing import Callable
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

import websocket


REQUIRED_RECEIPT_FIELDS = {
    "receipt_id", "issuer", "consumer", "issued_at", "expires_at",
    "endpoint", "chrome_pid", "profile_path", "capabilities",
}
CAPABILITY_RANK = {"viewer": 1, "admin": 2}
ADMIN_AUTH_NAVIGATION_RETRIES = 3
ADMIN_AUTH_DOM_TIMEOUT_MS = 60000
ADMIN_AUTH_WS_TIMEOUT_SEC = 90
TRANSIENT_NAVIGATION_ERRORS = (
    "Execution context was destroyed",
    "Inspected target navigated or closed",
)


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


def _cdp_endpoint(receipt: dict) -> str:
    endpoint = str(receipt.get("endpoint", "")).strip().rstrip("/")
    parsed = urlsplit(endpoint)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise AdapterError("CDP foundation receipt has an invalid endpoint")
    return endpoint


def _cdp_request(ws, method: str, params: dict | None = None) -> dict:
    request_id = int(time.time_ns() % 1_000_000_000)
    ws.send(json.dumps({"id": request_id, "method": method, "params": params or {}}))
    while True:
        message = json.loads(ws.recv())
        if message.get("id") == request_id:
            if message.get("error"):
                raise AdapterError(f"CDP {method} failed: {message['error']}")
            return message.get("result", {})


def _page_targets(endpoint: str) -> list[dict]:
    try:
        with urlopen(f"{endpoint}/json/list", timeout=5) as response:
            payload = json.load(response)
    except Exception as exc:
        raise AdapterError(f"CDP endpoint is unreachable: {type(exc).__name__}") from exc
    return [row for row in payload if row.get("type") == "page"]


def _page_ws(endpoint: str, target_url: str) -> str:
    host = urlsplit(target_url).netloc
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        pages = _page_targets(endpoint)
        for row in pages:
            if host in str(row.get("url", "")) and row.get("webSocketDebuggerUrl"):
                return str(row["webSocketDebuggerUrl"])
        time.sleep(0.2)
    raise AdapterError("CDP page target did not become available")


def _open_admin_page(endpoint: str, target_url: str) -> str:
    pages = _page_targets(endpoint)
    ws_url = next((str(row["webSocketDebuggerUrl"]) for row in pages
                   if row.get("webSocketDebuggerUrl")), None)
    if ws_url is None:
        try:
            with urlopen(f"{endpoint}/json/version", timeout=5) as response:
                browser_ws = json.load(response)["webSocketDebuggerUrl"]
            ws = websocket.create_connection(browser_ws, timeout=15)
            try:
                target = _cdp_request(ws, "Target.createTarget", {"url": target_url})
                if not target.get("targetId"):
                    raise AdapterError("CDP Target.createTarget returned no target")
            finally:
                ws.close()
        except AdapterError:
            raise
        except Exception as exc:
            raise AdapterError(f"CDP admin page creation failed: {type(exc).__name__}") from exc
        return _page_ws(endpoint, target_url)

    ws = websocket.create_connection(ws_url, timeout=15)
    try:
        _cdp_request(ws, "Page.navigate", {"url": target_url})
    finally:
        ws.close()
    return _page_ws(endpoint, target_url)


def _is_transient_navigation_error(exc: AdapterError) -> bool:
    message = str(exc)
    return any(marker in message for marker in TRANSIENT_NAVIGATION_ERRORS)


def _admin_ui_auth(target_url: str, env_file: str, receipt: dict) -> tuple[bool, str]:
    try:
        user = _load_env_value(env_file, "ADMIN_USER")
        password = _load_env_value(env_file, "ADMIN_PASS")
    except AdapterError as exc:
        return False, str(exc)
    endpoint = _cdp_endpoint(receipt)
    script = """
    (async () => {
      const deadline = Date.now() + %d;
      let passwordInput, userInput, button;
      while (Date.now() < deadline) {
        const bodyText = document.body?.innerText || '';
        if (!document.querySelector('input[type="password"]') &&
            /\\bAdmin\\b/.test(bodyText) && /\\bLogout\\b/.test(bodyText))
          return {ok:true, alreadyAuthenticated:true, url: location.href};
        const inputs = [...document.querySelectorAll('input')];
        passwordInput = inputs.find(x => x.type === 'password');
        userInput = inputs.find(x => x !== passwordInput &&
          ['text', 'email'].includes(x.type)) || inputs.find(x => x !== passwordInput);
        button = [...document.querySelectorAll('button')].find(x =>
          /login/i.test((x.innerText || x.textContent || '').trim()));
        if (userInput && passwordInput && button) break;
        await new Promise(resolve => setTimeout(resolve, 200));
      }
      if (!userInput || !passwordInput || !button)
        return {ok:false, reason:'admin login form not found'};
      const set = (el, value) => {
        const setter = Object.getOwnPropertyDescriptor(
          window.HTMLInputElement.prototype, 'value').set;
        setter.call(el, value);
        el.dispatchEvent(new Event('input', {bubbles:true}));
        el.dispatchEvent(new Event('change', {bubbles:true}));
      };
      set(userInput, %s); set(passwordInput, %s); button.click();
      await new Promise(resolve => setTimeout(resolve, 3000));
      return {ok: !document.querySelector('input[type="password"]'),
              url: location.href};
    })()
    """ % (ADMIN_AUTH_DOM_TIMEOUT_MS, json.dumps(user), json.dumps(password))
    for attempt in range(ADMIN_AUTH_NAVIGATION_RETRIES + 1):
        # Navigate only once. If the page is still replacing its execution
        # context, attach to the newest matching target and evaluate again.
        ws_url = (_open_admin_page(endpoint, target_url)
                  if attempt == 0 else _page_ws(endpoint, target_url))
        try:
            ws = websocket.create_connection(ws_url, timeout=ADMIN_AUTH_WS_TIMEOUT_SEC)
            try:
                result = _cdp_request(ws, "Runtime.evaluate", {
                    "expression": script, "awaitPromise": True, "returnByValue": True,
                })
            finally:
                ws.close()
        except AdapterError as exc:
            if not _is_transient_navigation_error(exc):
                raise
            if attempt >= ADMIN_AUTH_NAVIGATION_RETRIES:
                raise AdapterError(
                    "admin authentication failed after bounded navigation retries: "
                    f"{exc}"
                ) from exc
            time.sleep(0.2)
            continue
        break
    value = result.get("result", {}).get("value", {})
    if not value.get("ok"):
        raise AdapterError(f"admin authentication failed: {value.get('reason', 'form rejected')}")
    return True, f"admin UI authenticated at {value.get('url', target_url)}"


def _admin_auth(target_url: str, env_file: str, receipt: dict) -> tuple[bool, str]:
    # The auto-ops CLI performs its CDP HTTP preflight through Windows
    # PowerShell.  A Windows localhost endpoint is not authoritative from the
    # WSL caller: the same receipt can be reachable natively in WSL while the
    # PowerShell request times out.  Authenticate through the receipt endpoint
    # directly so endpoint, port, and process boundaries cannot drift.
    try:
        return _admin_ui_auth(target_url, env_file, receipt)
    except AdapterError:
        raise
    except subprocess.TimeoutExpired as exc:
        raise AdapterError("admin authentication failed (timeout)") from exc
    except Exception as exc:
        raise AdapterError(f"admin authentication failed ({type(exc).__name__})") from exc


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
      const passwordFormGone = !document.querySelector('input[type="password"]');
      const rows = document.querySelectorAll('tbody tr').length;
      return {ok: passwordFormGone && rows > 0, rows,
              reason: passwordFormGone && rows > 0
                ? `viewer authenticated; tbody rows=${rows}`
                : `viewer DOM verification failed; passwordFormGone=${passwordFormGone}; tbody rows=${rows}`};
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
                rows = value.get("rows")
                ok = bool(value.get("ok")) and isinstance(rows, int) and rows > 0
                reason = str(value.get("reason", "viewer authentication failed"))
                return ok, f"{reason}; verified_rows={rows}"
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
