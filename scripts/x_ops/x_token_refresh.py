#!/usr/bin/env python3
"""X OAuth2 refresh_token で access token を更新し config/x_api.env を書き戻す。

2026-09-04 将軍 D0: access token は 2h で失効し、xdk 内部 refresh は
InvalidClientIdError で失敗した(第 2 弾投稿時に実測)。x_oauth_listener.py と
同じ confidential client 方式(Basic auth)で refresh する。
Usage: python3 scripts/x_ops/x_token_refresh.py [env_path]
"""
import base64
import hashlib
import json
import os
import secrets
import subprocess
import tempfile
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ENV = Path(sys.argv[1] if len(sys.argv) > 1 else "config/x_api.env")
REPO_ROOT = Path(__file__).resolve().parents[2]


def load(path):
    vals = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in line or line.lstrip().startswith("#"):
            continue
        k, v = line.split("=", 1)
        vals[k.strip()] = v.strip().strip('"').strip("'")
    return vals


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            out.write(content)
            out.flush()
            os.fsync(out.fileno())
        os.replace(tmp_name, path)
        os.chmod(path, 0o600)
    except Exception:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass
        raise


def notify_reauth(values):
    """Generate a fresh PKCE URL and deliver it through the action channel."""
    client_id = values.get("X_CLIENT_ID", "").strip()
    redirect_uri = values.get("X_REDIRECT_URI", "").strip()
    if not client_id or not redirect_uri:
        return False

    verifier = secrets.token_urlsafe(72)[:96]
    challenge = base64.urlsafe_b64encode(
        hashlib.sha256(verifier.encode("ascii")).digest()
    ).decode("ascii").rstrip("=")
    state = secrets.token_hex(16)
    verifier_path = Path(os.environ.get("X_PKCE_VERIFIER_FILE", "/tmp/x_pkce_verifier.txt"))
    state_path = Path(os.environ.get("X_PKCE_STATE_FILE", "/tmp/x_pkce_state.txt"))
    atomic_write(verifier_path, verifier + "\n")
    atomic_write(state_path, state + "\n")
    scopes = values.get(
        "X_SCOPES", "tweet.read tweet.write users.read media.write offline.access"
    )
    query = urllib.parse.urlencode({
        "response_type": "code",
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "scope": scopes,
        "state": state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    })
    url = "https://x.com/i/oauth2/authorize?" + query
    action_script = Path(os.environ.get("X_TOKEN_ACTION_NTFY_SCRIPT", REPO_ROOT / "scripts/ntfy_action.sh"))
    if not action_script.is_file():
        return False
    try:
        subprocess.run(
            [str(action_script), "X再認可URLを開いてAuthorize appを押してください。\n" + url],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return True


def main():
    e = load(ENV)
    missing = [k for k in ("X_CLIENT_ID", "X_CLIENT_SECRET", "X_REFRESH_TOKEN") if not e.get(k)]
    if missing:
        if "X_REFRESH_TOKEN" in missing:
            notify_reauth(e)
        print(f"x_token_refresh: {missing[0]} missing", file=sys.stderr)
        return 2
    data = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "refresh_token": e["X_REFRESH_TOKEN"],
        "client_id": e["X_CLIENT_ID"],
    }).encode()
    req = urllib.request.Request("https://api.x.com/2/oauth2/token", data=data)
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    basic = base64.b64encode(f"{e['X_CLIENT_ID']}:{e['X_CLIENT_SECRET']}".encode()).decode()
    req.add_header("Authorization", "Basic " + basic)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            tok = json.loads(r.read().decode())
    except urllib.error.HTTPError as ex:
        notify_reauth(e)
        print(f"x_token_refresh: http={ex.code}", file=sys.stderr)
        return 1
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as ex:
        notify_reauth(e)
        print(f"x_token_refresh: request failed ({type(ex).__name__})", file=sys.stderr)
        return 1
    access = tok.get("access_token")
    refresh = tok.get("refresh_token") or e["X_REFRESH_TOKEN"]
    if not access:
        notify_reauth(e)
        print("x_token_refresh: no access_token in response", file=sys.stderr)
        return 1
    lines = ENV.read_text(encoding="utf-8").splitlines()
    out, seen = [], set()
    repl = {
        "X_ACCESS_TOKEN": access,
        "X_REFRESH_TOKEN": refresh,
        "X_TOKEN_OBTAINED_AT": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }
    for line in lines:
        key = line.split("=", 1)[0].strip() if "=" in line else ""
        if key in repl:
            out.append(f"{key}={repl[key]}")
            seen.add(key)
        else:
            out.append(line)
    for k, v in repl.items():
        if k not in seen:
            out.append(f"{k}={v}")
    atomic_write(ENV, "\n".join(out) + "\n")
    print(f"x_token_refresh: ok expires_in={tok.get('expires_in')} rotated_refresh={'yes' if tok.get('refresh_token') else 'no'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
